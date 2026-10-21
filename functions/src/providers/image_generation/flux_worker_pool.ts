import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { EnvConfig } from "../../config/env_config";
import { FluxProviderError } from "./flux_thumbnail_provider";

export interface FluxWorkerConfig {
  workerId: string;
  accountId: string;
  apiKey: string;
  model: string;
}

export type FluxWorkerStatus = "available" | "busy" | "cooling_down" | "disabled";

export interface FluxWorkerRecord {
  workerId: string;
  status: FluxWorkerStatus;
  currentJob: string | null;
  lockedUntil: admin.firestore.Timestamp | null;
  lastUsedAt: admin.firestore.Timestamp | null;
  cooldownUntil: admin.firestore.Timestamp | null;
  failureCount: number;
  lastError: string | null;
  updatedAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
}

export interface FluxPoolStateRecord {
  dailyQuotaPausedUntil: admin.firestore.Timestamp | null;
  lastDailyQuotaErrorAt: admin.firestore.Timestamp | null;
  lastDailyQuotaWorkerId: string | null;
  lastSuccessfulGenerationAt: admin.firestore.Timestamp | null;
  dailyQuotaFailureStreak: number;
  dailyQuotaProbeInProgress: boolean;
  probeLockedUntil: admin.firestore.Timestamp | null;
  updatedAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
}

export class FluxWorkerPool {
  public static readonly COLLECTION_NAME = "flux_workers";
  public static readonly POOL_STATE_DOC_ID = "_pool_state";
  public static readonly LEASE_LOCK_DURATION_MS = 120000; // 2 minutes max lease
  public static readonly BASE_COOLDOWN_MS = 120000; // 2 minutes cooldown on rate-limit / capacity errors
  public static readonly DAILY_QUOTA_PROBE_COOLDOWN_MS = 30 * 60 * 1000; // 30 minutes bounded probe during rollover
  public static readonly PROBE_LOCK_DURATION_MS = 60 * 1000; // 1 minute probe lock

  /**
   * Helper to check if two dates fall on the exact same UTC calendar day.
   */
  public static isSameUtcDay(a: Date, b: Date): boolean {
    return (
      a.getUTCFullYear() === b.getUTCFullYear() &&
      a.getUTCMonth() === b.getUTCMonth() &&
      a.getUTCDate() === b.getUTCDate()
    );
  }

  /**
   * Calculates the appropriate cooldown period for daily quota exhaustion.
   * - During the post-midnight rollover / transition window (00:00 - 02:00 UTC) when no
   *   successful generations have occurred today: sets a bounded probe cooldown (30 min)
   *   to allow Cloudflare's edge quota synchronization to settle without locking out the whole day.
   * - Once genuine daily quota exhaustion occurs (after successful generations today, or past the
   *   rollover window): sets cooldown to the upcoming UTC reset with a 15-minute buffer (00:15 UTC).
   */
  public static calculateDailyQuotaCooldown(
    now: Date = new Date(),
    options?: {
      lastSuccessAt?: Date | null;
      failureStreak?: number;
    }
  ): { cooldownUntil: Date; isProbingWindow: boolean } {
    const utcHour = now.getUTCHours();
    const hasSucceededToday = options?.lastSuccessAt
      ? this.isSameUtcDay(now, options.lastSuccessAt)
      : false;

    // Transition / rollover window: 00:00 UTC - 02:00 UTC with no successful generation today
    const isProbingWindow = utcHour < 2 && !hasSucceededToday;

    if (isProbingWindow) {
      // Bounded retry cooldown (30 minutes)
      const cooldownUntil = new Date(now.getTime() + this.DAILY_QUOTA_PROBE_COOLDOWN_MS);
      return { cooldownUntil, isProbingWindow: true };
    }

    // Genuine exhaustion: cooldown until upcoming UTC reset tomorrow at 00:15:00 UTC
    // (15-minute buffer prevents probing before edge sync at 00:00-00:10 UTC)
    const nextUtcReset = new Date(Date.UTC(
      now.getUTCFullYear(),
      now.getUTCMonth(),
      now.getUTCDate() + 1,
      0, 15, 0
    ));

    return { cooldownUntil: nextUtcReset, isProbingWindow: false };
  }

  /**
   * Retrieves all active worker configurations from secure environment configuration.
   * NEVER exposes credentials in Firestore or logs.
   */
  public static getWorkerConfigs(): FluxWorkerConfig[] {
    return EnvConfig.getFluxWorkerConfigs();
  }

  /**
   * Deterministically and atomically reserves a free, available Flux worker using a Firestore transaction.
   * Selection strategy:
   * 1. Filters workers whose leases are active (lockedUntil > now) or cooldown active (cooldownUntil > now).
   * 2. Excludes permanently disabled workers.
   * 3. Sorts available workers by Least Recently Used (LRU) - null lastUsedAt first, then oldest lastUsedAt.
   * 4. Acquires an atomic lease lock for 2 minutes and marks the worker busy with the resourceId.
   * Returns the reserved worker's configuration, or null if all workers are busy or cooling down.
   */
  public static async reserveAvailableWorker(
    db: admin.firestore.Firestore,
    resourceId: string,
    customConfigs?: FluxWorkerConfig[]
  ): Promise<FluxWorkerConfig | null> {
    const configs = customConfigs || this.getWorkerConfigs();
    if (!configs || configs.length === 0) {
      logger.warn("[FLUX_POOL_WARN] No Flux workers configured in environment.");
      return null;
    }

    try {
      const reservedConfig = await db.runTransaction(async (transaction) => {
        const nowMs = Date.now();

        // 1. Check pool-wide daily quota pause and active probe gate
        const poolStateRef = db.collection(this.COLLECTION_NAME).doc(this.POOL_STATE_DOC_ID);
        const poolStateSnap = await transaction.get(poolStateRef);
        const poolState = poolStateSnap.exists ? poolStateSnap.data() || {} : {};

        let poolQuotaPausedUntilMs = 0;
        if (poolState.dailyQuotaPausedUntil) {
          poolQuotaPausedUntilMs = poolState.dailyQuotaPausedUntil.toDate
            ? poolState.dailyQuotaPausedUntil.toDate().getTime()
            : new Date(poolState.dailyQuotaPausedUntil).getTime();
        }

        if (poolQuotaPausedUntilMs > nowMs) {
          // Entire worker pool is in daily quota cooldown
          return null;
        }

        // Prevent concurrent probe storms across scheduler instances
        if (poolState.dailyQuotaProbeInProgress && poolState.probeLockedUntil) {
          const probeLockedUntilMs = poolState.probeLockedUntil.toDate
            ? poolState.probeLockedUntil.toDate().getTime()
            : new Date(poolState.probeLockedUntil).getTime();
          if (probeLockedUntilMs > nowMs) {
            // Another instance is actively executing a single recovery probe
            return null;
          }
        }

        const candidateRecords: Array<{
          config: FluxWorkerConfig;
          docRef: admin.firestore.DocumentReference;
          lastUsedMs: number;
          failureCount: number;
        }> = [];

        let hasSupersededLegacyQuota = false;

        for (const config of configs) {
          const docRef = db.collection(this.COLLECTION_NAME).doc(config.workerId);
          const snap = await transaction.get(docRef);

          let isAvailable = true;
          let lastUsedMs = 0;
          let failureCount = 0;

          if (snap.exists) {
            const data = snap.data() || {};
            failureCount = data.failureCount || 0;

            // Check permanent disabled state
            if (data.status === "disabled") {
              isAvailable = false;
            }

            // Check concurrency lease lock (busy with another job)
            if (isAvailable && data.lockedUntil) {
              const lockedUntilMs = data.lockedUntil.toDate
                ? data.lockedUntil.toDate().getTime()
                : new Date(data.lockedUntil).getTime();

              if (lockedUntilMs > nowMs) {
                // Currently holding an active lease
                isAvailable = false;
              }
            }

            // Check cooldown period
            if (isAvailable && data.cooldownUntil) {
              const cooldownUntilMs = data.cooldownUntil.toDate
                ? data.cooldownUntil.toDate().getTime()
                : new Date(data.cooldownUntil).getTime();

              if (cooldownUntilMs > nowMs) {
                // Check if this was a daily quota error and pool-wide quota pause has expired
                const isDailyQuotaError =
                  data.lastError &&
                  (data.lastError.includes("4006") ||
                   data.lastError.includes("daily free allocation") ||
                   data.lastError.includes("10,000 neurons"));

                if (isDailyQuotaError && poolQuotaPausedUntilMs <= nowMs) {
                  // Legacy/uncoordinated quota cooldown superseded by unpaused pool state: eligible
                  isAvailable = true;
                  hasSupersededLegacyQuota = true;
                } else {
                  // Still in active cooldown
                  isAvailable = false;
                }
              }
            }

            // Extract lastUsedAt for LRU sorting
            if (data.lastUsedAt) {
              lastUsedMs = data.lastUsedAt.toDate
                ? data.lastUsedAt.toDate().getTime()
                : new Date(data.lastUsedAt).getTime();
            }
          }

          if (isAvailable) {
            candidateRecords.push({
              config,
              docRef,
              lastUsedMs,
              failureCount,
            });
          }
        }

        if (candidateRecords.length === 0) {
          return null; // All workers are currently busy, cooling down, or disabled
        }

        // Deterministic LRU sorting: least recently used first (lowest lastUsedMs)
        // If tied (e.g. 0), sort by workerId string
        candidateRecords.sort((a, b) => {
          if (a.lastUsedMs !== b.lastUsedMs) {
            return a.lastUsedMs - b.lastUsedMs;
          }
          return a.config.workerId.localeCompare(b.config.workerId);
        });

        const chosen = candidateRecords[0];
        const leaseExpiration = new Date(nowMs + this.LEASE_LOCK_DURATION_MS);

        // Atomically lock and reserve the chosen worker
        transaction.set(
          chosen.docRef,
          {
            workerId: chosen.config.workerId,
            status: "busy",
            currentJob: resourceId,
            lockedUntil: admin.firestore.Timestamp.fromDate(leaseExpiration),
            lastUsedAt: admin.firestore.Timestamp.fromDate(new Date(nowMs)),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        let lastSuccessAt: Date | null = null;
        if (poolState.lastSuccessfulGenerationAt) {
          lastSuccessAt = poolState.lastSuccessfulGenerationAt.toDate
            ? poolState.lastSuccessfulGenerationAt.toDate()
            : new Date(poolState.lastSuccessfulGenerationAt);
        }
        const hasSucceededToday = lastSuccessAt
          ? this.isSameUtcDay(new Date(nowMs), lastSuccessAt)
          : false;

        // A reservation is genuinely acting as a quota-recovery probe only when:
        // 1. The pool previously entered a daily quota pause that has now elapsed, OR
        // 2. An active daily quota failure streak is recorded, OR
        // 3. Workers were revived from legacy uncoordinated quota cooldowns before any success today.
        // During normal steady-state operation, the probe gate remains unlocked to preserve full multi-worker concurrency.
        const isQuotaRecoveryProbe = Boolean(
          poolState.dailyQuotaPausedUntil != null ||
          (typeof poolState.dailyQuotaFailureStreak === "number" && poolState.dailyQuotaFailureStreak > 0) ||
          (!hasSucceededToday && hasSupersededLegacyQuota)
        );

        if (isQuotaRecoveryProbe) {
          // Lock probe gate in pool state to prevent concurrent recovery probe storms
          transaction.set(
            poolStateRef,
            {
              dailyQuotaProbeInProgress: true,
              probeLockedUntil: admin.firestore.Timestamp.fromDate(new Date(nowMs + this.PROBE_LOCK_DURATION_MS)),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );

          logger.info(
            `[FLUX_POOL_PROBE_LOCKED] Worker "${chosen.config.workerId}" designated as single authorized quota recovery probe.`
          );
        }

        logger.info(
          `[FLUX_POOL_RESERVED] Atomically reserved worker "${chosen.config.workerId}" for job "${resourceId}" (Lease expires: ${leaseExpiration.toISOString()})`
        );

        return chosen.config;
      });

      return reservedConfig;
    } catch (err: any) {
      logger.error(`[FLUX_POOL_TRANSACTION_ERROR] Failed reserving worker for "${resourceId}":`, err.message);
      return null;
    }
  }

  /**
   * Releases a worker lease after completion or failure.
   * If successful: marks worker available, resets failure count.
   * If temporary failure (429, 3040, 4006, 5xx, timeout): marks worker cooling_down with cooldownUntil.
   * If permanent failure (400, 401, 403): marks worker disabled.
   */
  public static async releaseWorker(
    db: admin.firestore.Firestore,
    workerId: string,
    outcome: {
      success: boolean;
      error?: Error;
      resourceId?: string;
    }
  ): Promise<void> {
    try {
      const docRef = db.collection(this.COLLECTION_NAME).doc(workerId);
      const snap = await docRef.get();
      const currentFailures = (snap.data()?.failureCount || 0);

      if (outcome.success) {
        await docRef.set(
          {
            workerId,
            status: "available",
            currentJob: null,
            lockedUntil: null,
            cooldownUntil: null,
            failureCount: 0,
            lastError: null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        logger.info(`[FLUX_POOL_RELEASE_SUCCESS] Worker "${workerId}" successfully completed and is now available.`);

        // Synchronize pool state: clear daily quota pause, reset probe lock and failure streak
        try {
          const poolStateRef = db.collection(this.COLLECTION_NAME).doc(this.POOL_STATE_DOC_ID);
          await poolStateRef.set(
            {
              dailyQuotaPausedUntil: null,
              dailyQuotaProbeInProgress: false,
              probeLockedUntil: null,
              dailyQuotaFailureStreak: 0,
              lastSuccessfulGenerationAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
        } catch (poolErr: any) {
          logger.warn("[FLUX_POOL_STATE_WARN] Failed synchronizing pool state on success:", poolErr.message);
        }
        return;
      }

      // Handle failure
      const err = outcome.error;
      const isRetryable = err instanceof FluxProviderError ? err.isRetryable : false;
      const cleanError = err?.message ? err.message.slice(0, 300) : "Unknown worker error";

      if (isRetryable) {
        const isDailyQuota = err instanceof FluxProviderError && err.isDailyQuotaExhausted;
        const nextFailures = currentFailures + 1;
        let cooldownUntil: Date;

        if (isDailyQuota) {
          const now = new Date();
          const poolStateRef = db.collection(this.COLLECTION_NAME).doc(this.POOL_STATE_DOC_ID);
          const poolStateSnap = await poolStateRef.get();
          const poolStateData = poolStateSnap.exists ? poolStateSnap.data() || {} : {};

          let lastSuccessAt: Date | null = null;
          if (poolStateData.lastSuccessfulGenerationAt) {
            lastSuccessAt = poolStateData.lastSuccessfulGenerationAt.toDate
              ? poolStateData.lastSuccessfulGenerationAt.toDate()
              : new Date(poolStateData.lastSuccessfulGenerationAt);
          }

          const streak = (poolStateData.dailyQuotaFailureStreak || 0) + 1;
          const { cooldownUntil: calculatedCd, isProbingWindow } = this.calculateDailyQuotaCooldown(now, {
            lastSuccessAt,
            failureStreak: streak,
          });
          cooldownUntil = calculatedCd;

          // Update pool-wide coordination state
          await poolStateRef.set(
            {
              dailyQuotaPausedUntil: admin.firestore.Timestamp.fromDate(cooldownUntil),
              lastDailyQuotaErrorAt: admin.firestore.FieldValue.serverTimestamp(),
              lastDailyQuotaWorkerId: workerId,
              dailyQuotaProbeInProgress: false,
              probeLockedUntil: null,
              dailyQuotaFailureStreak: streak,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );

          if (isProbingWindow) {
            logger.warn(
              `[FLUX_WORKER_DAILY_QUOTA_PROBE] Worker "${workerId}" hit 4006 during rollover window (attempt ${streak}). Pausing pool for bounded probe until: ${cooldownUntil.toISOString()}`
            );
          } else {
            logger.warn(
              `[FLUX_WORKER_DAILY_QUOTA_EXHAUSTED] Worker "${workerId}" exhausted daily allocation. In cooldown until UTC midnight reset: ${cooldownUntil.toISOString()}`
            );
          }
        } else {
          // Temporary error (429 rate limit, 3040 capacity, 408 timeout, 5xx): bounded exponential cooldown
          // Cooldown: 2m base * multiplier (up to 10m max)
          const cooldownMultiplier = Math.min(nextFailures, 5);
          const cooldownMs = this.BASE_COOLDOWN_MS * cooldownMultiplier;
          cooldownUntil = new Date(Date.now() + cooldownMs);
          logger.warn(
            `[FLUX_WORKER_COOLDOWN] Worker "${workerId}" experienced transient error (${cleanError}). In cooldown until ${cooldownUntil.toISOString()} (Failures: ${nextFailures})`
          );

          // Clear probe lock if this worker was probing
          try {
            const poolStateRef = db.collection(this.COLLECTION_NAME).doc(this.POOL_STATE_DOC_ID);
            await poolStateRef.set(
              {
                dailyQuotaProbeInProgress: false,
                probeLockedUntil: null,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true }
            );
          } catch (_) {}
        }

        await docRef.set(
          {
            workerId,
            status: "cooling_down",
            currentJob: null,
            lockedUntil: null,
            cooldownUntil: admin.firestore.Timestamp.fromDate(cooldownUntil),
            failureCount: nextFailures,
            lastError: cleanError,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      } else {
        // Permanent error (400, 401, 403): disable worker to prevent aggressive broken retries
        await docRef.set(
          {
            workerId,
            status: "disabled",
            currentJob: null,
            lockedUntil: null,
            failureCount: currentFailures + 1,
            lastError: cleanError,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        logger.error(
          `[FLUX_WORKER_DISABLED] Worker "${workerId}" disabled due to permanent error: ${cleanError}`
        );

        // Clear probe lock if this worker was probing
        try {
          const poolStateRef = db.collection(this.COLLECTION_NAME).doc(this.POOL_STATE_DOC_ID);
          await poolStateRef.set(
            {
              dailyQuotaProbeInProgress: false,
              probeLockedUntil: null,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
        } catch (_) {}
      }
    } catch (err: any) {
      logger.error(`[FLUX_POOL_RELEASE_ERROR] Failed releasing worker "${workerId}":`, err.message);
    }
  }

  /**
   * Retrieves overall real-time status of all workers in the pool.
   */
  public static async getPoolStatus(
    db: admin.firestore.Firestore,
    customConfigs?: FluxWorkerConfig[]
  ): Promise<{
    total: number;
    available: number;
    busy: number;
    coolingDown: number;
    disabled: number;
    allUnavailable: boolean;
    allDisabled: boolean;
    earliestCooldown?: Date;
    isDailyQuotaPaused?: boolean;
  }> {
    const configs = customConfigs || this.getWorkerConfigs();
    const nowMs = Date.now();

    let available = 0;
    let busy = 0;
    let coolingDown = 0;
    let disabled = 0;
    let earliestCooldownMs: number | null = null;

    try {
      const snap = await db.collection(this.COLLECTION_NAME).get();
      const recordsByWorker = new Map<string, any>();
      snap.forEach((doc) => {
        recordsByWorker.set(doc.id, doc.data());
      });

      // Check pool-wide daily quota pause first
      const poolState = recordsByWorker.get(this.POOL_STATE_DOC_ID);
      let poolQuotaPausedUntilMs = 0;
      if (poolState && poolState.dailyQuotaPausedUntil) {
        poolQuotaPausedUntilMs = poolState.dailyQuotaPausedUntil.toDate
          ? poolState.dailyQuotaPausedUntil.toDate().getTime()
          : new Date(poolState.dailyQuotaPausedUntil).getTime();

        if (poolQuotaPausedUntilMs > nowMs) {
          return {
            total: configs.length,
            available: 0,
            busy: 0,
            coolingDown: configs.length,
            disabled: 0,
            allUnavailable: true,
            allDisabled: false,
            earliestCooldown: new Date(poolQuotaPausedUntilMs),
            isDailyQuotaPaused: true,
          };
        }
      }

      for (const config of configs) {
        const d = recordsByWorker.get(config.workerId);
        if (!d) {
          available++;
          continue;
        }

        if (d.status === "disabled") {
          disabled++;
          continue;
        }

        if (d.lockedUntil) {
          const lockedUntilMs = d.lockedUntil.toDate
            ? d.lockedUntil.toDate().getTime()
            : new Date(d.lockedUntil).getTime();
          if (lockedUntilMs > nowMs) {
            busy++;
            continue;
          }
        }

        if (d.cooldownUntil) {
          const cdMs = d.cooldownUntil.toDate
            ? d.cooldownUntil.toDate().getTime()
            : new Date(d.cooldownUntil).getTime();
          if (cdMs > nowMs) {
            // Check if this was a daily quota cooldown superseded by an unpaused pool state
            const isDailyQuotaError =
              d.lastError &&
              (d.lastError.includes("4006") ||
               d.lastError.includes("daily free allocation") ||
               d.lastError.includes("10,000 neurons"));

            if (isDailyQuotaError && poolQuotaPausedUntilMs <= nowMs) {
              available++;
              continue;
            }

            coolingDown++;
            if (earliestCooldownMs === null || cdMs < earliestCooldownMs) {
              earliestCooldownMs = cdMs;
            }
            continue;
          }
        }

        available++;
      }
    } catch (err: any) {
      logger.error("[FLUX_POOL_STATUS_ERROR] Failed querying pool status:", err.message);
      // Fallback: assume available
      available = configs.length;
    }

    return {
      total: configs.length,
      available,
      busy,
      coolingDown,
      disabled,
      allUnavailable: available === 0,
      allDisabled: disabled === configs.length,
      earliestCooldown: earliestCooldownMs ? new Date(earliestCooldownMs) : undefined,
      isDailyQuotaPaused: false,
    };
  }
}

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

export class FluxWorkerPool {
  public static readonly COLLECTION_NAME = "flux_workers";
  public static readonly LEASE_LOCK_DURATION_MS = 120000; // 2 minutes max lease
  public static readonly BASE_COOLDOWN_MS = 120000; // 2 minutes cooldown on rate-limit / capacity errors

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
        const candidateRecords: Array<{
          config: FluxWorkerConfig;
          docRef: admin.firestore.DocumentReference;
          lastUsedMs: number;
          failureCount: number;
        }> = [];

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
                // Still in active cooldown
                isAvailable = false;
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
            failureCount: 0,
            lastError: null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        logger.info(`[FLUX_POOL_RELEASE_SUCCESS] Worker "${workerId}" successfully completed and is now available.`);
        return;
      }

      // Handle failure
      const err = outcome.error;
      const isRetryable = err instanceof FluxProviderError ? err.isRetryable : false;
      const cleanError = err?.message ? err.message.slice(0, 300) : "Unknown worker error";

      if (isRetryable) {
        // Temporary error (429, 3040, 4006, 408, 5xx, timeout): set per-worker cooldown
        const nextFailures = currentFailures + 1;
        // Cooldown: 2m base * multiplier (up to 10m max)
        const cooldownMultiplier = Math.min(nextFailures, 5);
        const cooldownMs = this.BASE_COOLDOWN_MS * cooldownMultiplier;
        const cooldownUntil = new Date(Date.now() + cooldownMs);

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

        logger.warn(
          `[FLUX_WORKER_COOLDOWN] Worker "${workerId}" experienced transient error (${cleanError}). In cooldown until ${cooldownUntil.toISOString()} (Failures: ${nextFailures})`
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
    };
  }
}

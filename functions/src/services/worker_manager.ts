import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { AIWorker, WorkersConfig, WorkerRole } from "../types/worker";
import { AIProviderRegistry } from "../providers/provider_registry";
import { FailedJobService } from "./failed_job_service";

const DEFAULT_WORKERS_CONFIG: WorkersConfig = {
  maxConcurrentWorkers: 10,
  discoveryQueueThreshold: 5,
  publisherQueueThreshold: 10,
  retryLimit: 3,
  cooldownMinutes: 15,
  maxArticlesPerWorker: 100,
  healthCheckInterval: 5,
};

export class WorkerManager {
  /**
   * Reads worker configuration from system/workersConfig or system/workers in Firestore.
   */
  static async getWorkersConfig(db: admin.firestore.Firestore): Promise<WorkersConfig> {
    try {
      let snap = await db.collection("system").doc("workersConfig").get();
      if (!snap.exists) {
        snap = await db.collection("system").doc("workers").get();
      }
      if (!snap.exists) {
        return { ...DEFAULT_WORKERS_CONFIG };
      }
      const d = snap.data() || {};
      return {
        maxConcurrentWorkers: d.maxConcurrentWorkers ?? DEFAULT_WORKERS_CONFIG.maxConcurrentWorkers,
        discoveryQueueThreshold: d.discoveryQueueThreshold ?? DEFAULT_WORKERS_CONFIG.discoveryQueueThreshold,
        publisherQueueThreshold: d.publisherQueueThreshold ?? DEFAULT_WORKERS_CONFIG.publisherQueueThreshold,
        retryLimit: d.retryLimit ?? DEFAULT_WORKERS_CONFIG.retryLimit,
        cooldownMinutes: d.cooldownMinutes ?? DEFAULT_WORKERS_CONFIG.cooldownMinutes,
        maxArticlesPerWorker: d.maxArticlesPerWorker ?? DEFAULT_WORKERS_CONFIG.maxArticlesPerWorker,
        healthCheckInterval: d.healthCheckInterval ?? DEFAULT_WORKERS_CONFIG.healthCheckInterval,
      };
    } catch (err) {
      logger.error("[WORKER_MANAGER] Failed to fetch system worker config, using defaults:", err);
      return { ...DEFAULT_WORKERS_CONFIG };
    }
  }

  /**
   * Checks if worker role matches requested role (case-insensitive & alias mapping).
   */
  static isRoleCompatible(workerRole: string, requestedRole: string): boolean {
    const w = (workerRole || "").toUpperCase().trim();
    const r = (requestedRole || "").toUpperCase().trim();
    if (w === "ANY" || r === "ANY") return true;
    if (r === "DISCOVERY" && (w === "DISCOVERY" || w === "DISCOVER")) return true;
    if (r === "WRITER" && (w === "WRITER" || w === "PUBLISHING" || w === "PUBLISHER")) return true;
    if (r === "IMAGE" && (w === "IMAGE" || w === "IMAGES")) return true;
    return w === r;
  }

  /**
   * Selects the best available AIWorker from Firestore workers collection based on:
   * 1. Enabled workers (enabled !== false)
   * 2. Ignore busy workers (busy === true || status === "busy")
   * 3. Ignore workers in cooldown (cooldownUntil > now || status === "cooldown")
   * 4. Ignore workers over rate limit (requestsThisMinute >= minuteLimit || requestsToday >= dailyLimit || remainingQuota <= 0)
   * 5. Role match (DISCOVERY, WRITER, IMAGE, or ANY)
   * 6. Lowest average latency -> Least recently used tie breaker
   */
  static async getAvailableWorker(
    db: admin.firestore.Firestore,
    requestedRole: WorkerRole = "DISCOVERY"
  ): Promise<AIWorker | null> {
    const now = Date.now();

    try {
      const snap = await db.collection("workers").get();
      const candidateWorkers: AIWorker[] = [];

      for (const doc of snap.docs) {
        const d = doc.data() || {};
        const workerId = doc.id;

        // 1. Enabled check
        const enabled = d.enabled !== false;
        if (!enabled) continue;

        // 2. Busy check
        const isBusy = d.busy === true || d.status === "busy";
        if (isBusy || d.status === "disabled") continue;

        // 3. Cooldown check
        if (d.cooldownUntil) {
          const cooldownTime = d.cooldownUntil.toDate ? d.cooldownUntil.toDate().getTime() : new Date(d.cooldownUntil).getTime();
          if (cooldownTime > now) {
            continue;
          }
        }
        if (d.status === "cooldown") continue;

        // 4. Rate Limiter & Quota check
        const minuteLimit = typeof d.minuteLimit === "number" ? d.minuteLimit : (typeof d.requestsPerMinute === "number" ? d.requestsPerMinute : 60);
        const dailyLimit = typeof d.dailyLimit === "number" ? d.dailyLimit : 1000;
        const requestsThisMinute = typeof d.requestsThisMinute === "number" ? d.requestsThisMinute : 0;
        const requestsToday = typeof d.requestsToday === "number" ? d.requestsToday : 0;
        const remainingQuota = typeof d.remainingQuota === "number" ? d.remainingQuota : 1000;

        if (minuteLimit > 0 && requestsThisMinute >= minuteLimit) continue;
        if (dailyLimit > 0 && requestsToday >= dailyLimit) continue;
        if (remainingQuota <= 0) continue;

        // 5. Role check
        const role = d.role || "ANY";
        if (!this.isRoleCompatible(role, requestedRole)) {
          continue;
        }

        // Provider registered check
        const providerName = d.provider || "openai";
        if (!AIProviderRegistry.hasProvider(providerName)) {
          logger.warn(`[WORKER_MANAGER] Worker ${workerId} has unregistered provider "${providerName}". Skipping.`);
          continue;
        }

        candidateWorkers.push({
          workerId,
          provider: providerName,
          model: d.model || "gpt-4o",
          apiKey: d.apiKey || d.apiKeyReference || "",
          apiKeyReference: d.apiKeyReference || d.apiKey || "",
          baseUrl: d.baseUrl || undefined,
          role,
          supportsWebSearch: d.supportsWebSearch !== false,
          supportsImages: d.supportsImages === true,
          enabled: true,
          busy: false,
          priority: typeof d.priority === "number" ? d.priority : 50,
          status: "idle",
          currentJobId: null,
          requestsPerMinute: minuteLimit,
          minuteLimit,
          dailyLimit,
          requestsToday,
          requestsThisMinute,
          remainingQuota,
          lastUsed: d.lastUsed || d.lastRequest || null,
          lastRequest: d.lastRequest || d.lastUsed || null,
          lastError: d.lastError || null,
          averageLatency: typeof d.averageLatency === "number" ? d.averageLatency : 500,
          failureCount: d.failureCount || 0,
          successCount: d.successCount || 0,
          cooldownUntil: d.cooldownUntil || null,
        });
      }

      if (candidateWorkers.length === 0) {
        logger.warn(`[WORKER_MANAGER] No active workers found for role "${requestedRole}". Creating fallback worker.`);
        return this.createFallbackWorker(requestedRole);
      }

      // LOAD BALANCER SORTING:
      // 1. Lowest averageLatency
      // 2. Least recently used (oldest lastUsed/lastRequest timestamp)
      // 3. Lower priority number
      const getTimeMs = (ts: any): number => {
        if (!ts) return 0;
        if (typeof ts.toDate === "function") return ts.toDate().getTime();
        if (ts instanceof Date) return ts.getTime();
        return new Date(ts).getTime();
      };

      candidateWorkers.sort((a, b) => {
        if (a.averageLatency !== b.averageLatency) return a.averageLatency - b.averageLatency;

        const timeA = getTimeMs(a.lastUsed);
        const timeB = getTimeMs(b.lastUsed);
        if (timeA !== timeB) return timeA - timeB;

        return a.priority - b.priority;
      });

      const selected = candidateWorkers[0];
      logger.info(
        `[WORKER_MANAGER] Selected worker "${selected.workerId}" (Provider=${selected.provider}, Latency=${selected.averageLatency}ms, Role=${selected.role})`
      );

      return selected;
    } catch (err: any) {
      logger.error("[WORKER_MANAGER_ERROR] Failed to query workers from Firestore:", err);
      return this.createFallbackWorker(requestedRole);
    }
  }

  /**
   * Atomically acquires lock on worker document in Firestore.
   */
  static async acquireWorker(
    db: admin.firestore.Firestore,
    workerId: string,
    jobId: string
  ): Promise<void> {
    if (workerId.startsWith("worker_env_")) return;

    const docRef = db.collection("workers").doc(workerId);
    try {
      await docRef.update({
        busy: true,
        status: "busy",
        currentJobId: jobId,
        lastUsed: admin.firestore.FieldValue.serverTimestamp(),
        lastRequest: admin.firestore.FieldValue.serverTimestamp(),
        requestsToday: admin.firestore.FieldValue.increment(1),
        requestsThisMinute: admin.firestore.FieldValue.increment(1),
      });
    } catch (err) {
      logger.warn(`[WORKER_MANAGER] Could not update acquire status for ${workerId}:`, err);
    }
  }

  /**
   * Releases worker status on job completion and records metrics.
   */
  static async releaseWorker(
    db: admin.firestore.Firestore,
    workerId: string,
    latencyMs: number,
    isSuccess: boolean
  ): Promise<void> {
    if (workerId.startsWith("worker_env_")) return;

    const docRef = db.collection("workers").doc(workerId);
    try {
      if (isSuccess) {
        await docRef.update({
          busy: false,
          status: "idle",
          currentJobId: null,
          successCount: admin.firestore.FieldValue.increment(1),
          remainingQuota: admin.firestore.FieldValue.increment(-1),
          averageLatency: latencyMs,
        });
      } else {
        await docRef.update({
          busy: false,
          status: "idle",
          currentJobId: null,
          failureCount: admin.firestore.FieldValue.increment(1),
        });
      }
    } catch (err) {
      logger.warn(`[WORKER_MANAGER] Could not update release status for ${workerId}:`, err);
    }
  }

  /**
   * Places worker into cooldown upon repeated failures or rate limit.
   */
  static async putWorkerInCooldown(
    db: admin.firestore.Firestore,
    workerId: string,
    cooldownMinutes: number = 15,
    reason: string = "Repeated execution failures"
  ): Promise<void> {
    if (workerId.startsWith("worker_env_")) return;

    const cooldownDate = new Date(Date.now() + cooldownMinutes * 60 * 1000);
    logger.warn(`[WORKER_COOLDOWN] Placing worker "${workerId}" into cooldown until ${cooldownDate.toISOString()}. Reason: ${reason}`);

    const docRef = db.collection("workers").doc(workerId);
    try {
      await docRef.update({
        busy: false,
        status: "cooldown",
        currentJobId: null,
        lastError: reason,
        cooldownUntil: admin.firestore.Timestamp.fromDate(cooldownDate),
      });
    } catch (err) {
      logger.error(`[WORKER_MANAGER] Failed to place ${workerId} into cooldown:`, err);
    }
  }

  /**
   * Firestore Transaction Locking: Atomically claims the next queued job for a worker.
   * Ensures no two workers process the same job or cluster concurrently.
   */
  static async claimNextJobWithTransaction(
    db: admin.firestore.Firestore,
    worker: AIWorker
  ): Promise<{ jobId: string; jobData: any } | null> {
    try {
      const queueSnap = await db
        .collection("job_queue")
        .where("status", "==", "queued")
        .limit(10)
        .get();

      if (queueSnap.empty) return null;

      for (const doc of queueSnap.docs) {
        const jobId = doc.id;
        const jobRef = db.collection("job_queue").doc(jobId);

        const claimedJob = await db.runTransaction(async (transaction) => {
          const freshSnap = await transaction.get(jobRef);
          if (!freshSnap.exists) return null;

          const data = freshSnap.data() || {};
          if (data.status !== "queued") return null; // Already taken by another worker

          transaction.update(jobRef, {
            status: "processing",
            assignedWorker: worker.workerId,
            startedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          return { jobId, jobData: data };
        });

        if (claimedJob) {
          await this.acquireWorker(db, worker.workerId, jobId);
          logger.info(`[TRANSACTION_LOCK_SUCCESS] Worker "${worker.workerId}" claimed job "${jobId}" atomically.`);
          return claimedJob;
        }
      }

      return null;
    } catch (err) {
      logger.error("[TRANSACTION_LOCK_ERROR] Error claiming queued job with transaction:", err);
      return null;
    }
  }

  /**
   * Failover & Retry Handler: Returns failed job to queue or moves to failed_jobs.
   */
  static async handleWorkerFailureAndFailover(
    db: admin.firestore.Firestore,
    workerId: string,
    jobId: string,
    errorMessage: string,
    retryLimit: number = 3
  ): Promise<void> {
    logger.warn(`[FAILOVER_TRIGGERED] Worker "${workerId}" failed on job "${jobId}". Error: ${errorMessage}`);

    // 1. Put worker into cooldown
    await this.putWorkerInCooldown(db, workerId, 15, `Job failure: ${errorMessage}`);

    // 2. Return job to queue or move to failed_jobs
    if (jobId) {
      const jobRef = db.collection("job_queue").doc(jobId);
      const jobSnap = await jobRef.get();
      const jobData = jobSnap.exists ? jobSnap.data() : {};

      await FailedJobService.handleJobFailure(db, jobId, jobData, errorMessage, retryLimit);
    }
  }

  /**
   * Generates a fallback worker using environment variable key if no Firestore workers exist.
   */
  private static createFallbackWorker(role: WorkerRole = "DISCOVERY"): AIWorker {
    return {
      workerId: "worker_env_openai",
      provider: "openai",
      model: "gpt-4o",
      apiKey: process.env.OPENAI_API_KEY || "",
      apiKeyReference: "env:OPENAI_API_KEY",
      role,
      supportsWebSearch: true,
      supportsImages: true,
      enabled: true,
      busy: false,
      priority: 1,
      status: "idle",
      currentJobId: null,
      requestsPerMinute: 60,
      minuteLimit: 60,
      dailyLimit: 1000,
      requestsToday: 0,
      requestsThisMinute: 0,
      remainingQuota: 1000,
      lastUsed: null,
      lastRequest: null,
      lastError: null,
      averageLatency: 300,
      failureCount: 0,
      successCount: 0,
      cooldownUntil: null,
    };
  }
}

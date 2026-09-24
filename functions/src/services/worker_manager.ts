import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { AIWorker, WorkerRole, WorkerStatus } from "../types/worker";
import { FailedJobService } from "./failed_job_service";
import { EnvConfig } from "../config/env_config";

const PROVIDER_RANKING: Record<string, number> = {
  gemini: 10,
  openai: 20,
  claude: 30,
  deepseek: 40,
  grok: 50,
  kimi: 60,
  pixabay: 70,
  wikimedia: 80,
  bing: 90,
  google: 100,
  unsplash: 110,
};

interface LocalWorkerState {
  status: WorkerStatus;
  cooldownUntil: number | null;
  failureCount: number;
  lastError?: string;
}

export interface ErrorClassification {
  type: "RATE_LIMIT" | "AUTH" | "TIMEOUT" | "SERVER" | "MALFORMED" | "UNKNOWN";
  cooldownSeconds: number;
  isPermanent: boolean;
  retryAfterSeconds?: number;
  cleanMessage: string;
}

export class WorkerManager {
  private static workerStateMap: Map<string, LocalWorkerState> = new Map();

  /**
   * Classifies runtime/API errors to determine exact cooldown and circuit-breaker behavior.
   */
  public static classifyError(error: any, failureCount = 0): ErrorClassification {
    const rawMessage = error?.message || String(error || "");
    const cleanMessage = rawMessage.slice(0, 300);

    // 1. HTTP 429 / Rate limit / Quota exceeded
    if (/429|rate.?limit|resource.?exhausted|quota/i.test(rawMessage)) {
      const retryAfterMatch = /retry-after\s*[:=]?\s*(\d+)/i.exec(rawMessage);
      const retryAfterSeconds = retryAfterMatch ? parseInt(retryAfterMatch[1], 10) : undefined;

      let cooldownSeconds: number;
      if (retryAfterSeconds && retryAfterSeconds > 0) {
        cooldownSeconds = Math.max(10, Math.min(retryAfterSeconds, 900));
      } else {
        // Exponential backoff: 30s, 60s, 120s, 240s, 480s, 900s
        const backoffTiers = [30, 60, 120, 240, 480, 900];
        const tier = backoffTiers[Math.min(failureCount, backoffTiers.length - 1)];
        // Add 0-5s jitter
        const jitter = Math.floor(Math.random() * 5);
        cooldownSeconds = tier + jitter;
      }

      return {
        type: "RATE_LIMIT",
        cooldownSeconds,
        isPermanent: false,
        retryAfterSeconds,
        cleanMessage,
      };
    }

    // 2. HTTP 401 / 403 / Authentication / Invalid Credentials
    if (/401|403|unauthorized|invalid.?key|invalid.?authentication|permission.?denied/i.test(rawMessage)) {
      return {
        type: "AUTH",
        cooldownSeconds: 86400, // 24 hours (quarantine)
        isPermanent: true,
        cleanMessage,
      };
    }

    // 3. Timeout / Connection reset
    if (/timeout|etimedout|econnreset|econnaborted|408/i.test(rawMessage)) {
      return {
        type: "TIMEOUT",
        cooldownSeconds: 15,
        isPermanent: false,
        cleanMessage,
      };
    }

    // 4. Server error (500, 502, 503, 504)
    if (/500|502|503|504|bad.?gateway|service.?unavailable/i.test(rawMessage)) {
      const cooldownSeconds = failureCount >= 2 ? 30 : 10;
      return {
        type: "SERVER",
        cooldownSeconds,
        isPermanent: false,
        cleanMessage,
      };
    }

    // 5. Malformed structured output from AI
    if (/incomplete structured article|malformed|json\.parse|syntaxerror/i.test(rawMessage)) {
      const cooldownSeconds = failureCount >= 2 ? 60 : 5;
      return {
        type: "MALFORMED",
        cooldownSeconds,
        isPermanent: false,
        cleanMessage,
      };
    }

    // Default unknown error
    return {
      type: "UNKNOWN",
      cooldownSeconds: 15,
      isPermanent: false,
      cleanMessage,
    };
  }

  /**
   * Checks if a worker is currently eligible to claim work.
   */
  public static isWorkerEligible(workerId: string): boolean {
    const state = this.workerStateMap.get(workerId);
    if (!state) return true;

    if (state.status === "disabled") {
      return false;
    }

    if (state.status === "cooldown") {
      const now = Date.now();
      if (state.cooldownUntil && now >= state.cooldownUntil) {
        // Cooldown has expired; transition back to idle
        state.status = "idle";
        state.cooldownUntil = null;
        logger.info(`[AI_WORKER_COOLDOWN_EXPIRED] Worker "${workerId}" cooldown expired. Status reset to "idle".`);
        return true;
      }
      return false;
    }

    if (state.status === "busy") {
      return false;
    }

    return true;
  }

  /**
   * Places a single worker into cooldown without affecting other workers.
   */
  public static async putWorkerInCooldown(
    db: admin.firestore.Firestore,
    workerId: string,
    cooldownSeconds: number,
    reason: string
  ): Promise<void> {
    const state = this.workerStateMap.get(workerId) || {
      status: "idle",
      cooldownUntil: null,
      failureCount: 0,
    };

    state.status = "cooldown";
    state.failureCount = (state.failureCount || 0) + 1;
    const cooldownUntilMs = Date.now() + cooldownSeconds * 1000;
    state.cooldownUntil = cooldownUntilMs;
    state.lastError = reason;
    this.workerStateMap.set(workerId, state);

    EnvConfig.setWorkerHealth(workerId, false, 0, reason);

    logger.warn(
      `[AI_WORKER_COOLDOWN] Worker="${workerId}" entered cooldown for ${cooldownSeconds}s (until ${new Date(cooldownUntilMs).toISOString()}). Reason: ${reason}`
    );

    try {
      await db.collection("workers").doc(workerId).set(
        {
          busy: false,
          status: "cooldown",
          currentJobId: null,
          failureCount: state.failureCount,
          lastError: reason,
          cooldownUntil: admin.firestore.Timestamp.fromMillis(cooldownUntilMs),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } catch (_) {}
  }

  /**
   * Permanently disables / quarantines a worker (e.g. on invalid API key / 401).
   */
  public static async disableWorker(
    db: admin.firestore.Firestore,
    workerId: string,
    reason: string
  ): Promise<void> {
    const state = this.workerStateMap.get(workerId) || {
      status: "idle",
      cooldownUntil: null,
      failureCount: 0,
    };

    state.status = "disabled";
    state.cooldownUntil = Date.now() + 86400 * 1000;
    state.lastError = reason;
    this.workerStateMap.set(workerId, state);

    EnvConfig.setWorkerHealth(workerId, false, 0, reason);

    logger.error(`[AI_WORKER_DISABLED] Worker "${workerId}" quarantined / disabled. Reason: ${reason}`);

    try {
      await db.collection("workers").doc(workerId).set(
        {
          busy: false,
          enabled: false,
          status: "disabled",
          currentJobId: null,
          lastError: reason,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } catch (_) {}
  }

  /**
   * Records a successful execution for a worker, resetting failure count.
   */
  public static async recordWorkerSuccess(
    db: admin.firestore.Firestore,
    workerId: string,
    latencyMs: number
  ): Promise<void> {
    const state = this.workerStateMap.get(workerId) || {
      status: "idle",
      cooldownUntil: null,
      failureCount: 0,
    };

    state.status = "idle";
    state.cooldownUntil = null;
    state.failureCount = 0;
    this.workerStateMap.set(workerId, state);

    EnvConfig.setWorkerHealth(workerId, true, latencyMs);

    try {
      await db.collection("workers").doc(workerId).set(
        {
          busy: false,
          status: "idle",
          currentJobId: null,
          failureCount: 0,
          averageLatency: latencyMs,
          lastUsed: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } catch (_) {}
  }

  private static isRoleCompatible(workerRole: string, requestedRole: string): boolean {
    if (requestedRole === "any" || workerRole === "any" || requestedRole === "ANY" || workerRole === "ANY") {
      return true;
    }
    const w = workerRole.toLowerCase();
    const r = requestedRole.toLowerCase();

    if (w === r) return true;
    if (r === "writer" && (w === "writer" || w === "publishing")) return true;
    if (r === "publishing" && (w === "writer" || w === "publishing")) return true;
    if (r === "discovery" && w === "discovery") return true;
    if (r === "image" && w === "image") return true;

    return false;
  }

  /**
   * Selects an eligible worker using provider ranking and round-robin least-recently-used rotation.
   */
  static async getAvailableWorker(
    db: admin.firestore.Firestore,
    requestedRole: WorkerRole = "DISCOVERY"
  ): Promise<AIWorker | null> {
    try {
      const allPoolWorkers = this.createEnvironmentPoolWorkers(requestedRole);
      const eligibleWorkers = allPoolWorkers.filter((w) => {
        if (!this.isRoleCompatible(w.role, requestedRole)) return false;
        if (!this.isWorkerEligible(w.workerId)) return false;
        if (!EnvConfig.isProviderHealthy(w.provider)) return false;
        return true;
      });

      if (eligibleWorkers.length === 0) {
        logger.warn(`[WORKER_MANAGER] No eligible workers available for role "${requestedRole}".`);
        return null;
      }

      // Sort by provider ranking (Gemini -> OpenAI -> Groq)
      eligibleWorkers.sort((a, b) => {
        const rankA = PROVIDER_RANKING[a.provider] || a.priority || 50;
        const rankB = PROVIDER_RANKING[b.provider] || b.priority || 50;
        if (rankA !== rankB) return rankA - rankB;
        return (a.failureCount || 0) - (b.failureCount || 0);
      });

      const selected = eligibleWorkers[0];
      logger.info(
        `[WORKER_MANAGER] Selected worker "${selected.workerId}" (Provider=${selected.provider}, Key=${selected.apiKeyReference}, Role=${selected.role})`
      );
      return selected;
    } catch (err: any) {
      logger.error("[WORKER_MANAGER_ERROR] Failed to select available worker:", err);
      return null;
    }
  }

  /**
   * Generates dynamic workers from environment variable key pools.
   * Each distinct API key is represented as a separate logical provider worker.
   */
  public static createEnvironmentPoolWorkers(role: WorkerRole = "WRITER"): AIWorker[] {
    const workers: AIWorker[] = [];

    // 1. Gemini Workers (Rank 10) - Each configured Gemini key has its own worker
    const geminiKeys = EnvConfig.getApiKeys("gemini");
    geminiKeys.forEach((geminiKey, index) => {
      const workerId = `worker_gemini_${String(index + 1).padStart(2, "0")}`;
      const state = this.workerStateMap.get(workerId);
      const isEligible = this.isWorkerEligible(workerId);

      workers.push({
        workerId,
        provider: "gemini",
        model: "gemini-3.6-flash",
        apiKey: geminiKey,
        apiKeyReference: EnvConfig.getKeyIdentifier("gemini", geminiKey, index),
        role,
        supportsWebSearch: true,
        supportsImages: true,
        enabled: state?.status !== "disabled",
        busy: state?.status === "busy",
        priority: 10,
        status: isEligible ? "idle" : (state?.status || "idle"),
        currentJobId: null,
        requestsPerMinute: 60,
        minuteLimit: 60,
        dailyLimit: 1000,
        requestsToday: 0,
        requestsThisMinute: 0,
        remainingQuota: 1000,
        lastUsed: null,
        lastRequest: null,
        lastError: state?.lastError || null,
        averageLatency: 150,
        failureCount: state?.failureCount || 0,
        successCount: 0,
        cooldownUntil: state?.cooldownUntil ? admin.firestore.Timestamp.fromMillis(state.cooldownUntil) : null,
      });
    });

    // 2. OpenAI / OpenRouter Workers (Rank 20)
    const openAiKeys = EnvConfig.getApiKeys("openai");
    const openAiBaseUrl = process.env.OPENAI_BASE_URL;
    const openAiModel = process.env.OPENAI_MODEL || "openai/gpt-4o-mini";
    openAiKeys.forEach((openAiKey, index) => {
      const workerId = `worker_openai_${String(index + 1).padStart(2, "0")}`;
      const state = this.workerStateMap.get(workerId);
      const isEligible = this.isWorkerEligible(workerId);

      workers.push({
        workerId,
        provider: "openai",
        model: openAiModel,
        baseUrl: openAiBaseUrl,
        apiKey: openAiKey,
        apiKeyReference: EnvConfig.getKeyIdentifier("openai", openAiKey, index),
        role,
        supportsWebSearch: true,
        supportsImages: true,
        enabled: state?.status !== "disabled",
        busy: state?.status === "busy",
        priority: 20,
        status: isEligible ? "idle" : (state?.status || "idle"),
        currentJobId: null,
        requestsPerMinute: 60,
        minuteLimit: 60,
        dailyLimit: 1000,
        requestsToday: 0,
        requestsThisMinute: 0,
        remainingQuota: 1000,
        lastUsed: null,
        lastRequest: null,
        lastError: state?.lastError || null,
        averageLatency: 120,
        failureCount: state?.failureCount || 0,
        successCount: 0,
        cooldownUntil: state?.cooldownUntil ? admin.firestore.Timestamp.fromMillis(state.cooldownUntil) : null,
      });
    });

    // 3. Groq / Grok Workers (Rank 50)
    const grokKeys = EnvConfig.getApiKeys("grok");
    const grokBaseUrl = process.env.GROK_BASE_URL || "https://api.groq.com/openai/v1";
    const grokModel = process.env.GROK_MODEL || "openai/gpt-oss-120b";
    grokKeys.forEach((grokKey, index) => {
      const workerId = `worker_grok_${String(index + 1).padStart(2, "0")}`;
      const state = this.workerStateMap.get(workerId);
      const isEligible = this.isWorkerEligible(workerId);

      workers.push({
        workerId,
        provider: "grok",
        model: grokModel,
        baseUrl: grokBaseUrl,
        apiKey: grokKey,
        apiKeyReference: EnvConfig.getKeyIdentifier("grok", grokKey, index),
        role,
        supportsWebSearch: true,
        supportsImages: true,
        enabled: state?.status !== "disabled",
        busy: state?.status === "busy",
        priority: 50,
        status: isEligible ? "idle" : (state?.status || "idle"),
        currentJobId: null,
        requestsPerMinute: 60,
        minuteLimit: 60,
        dailyLimit: 1000,
        requestsToday: 0,
        requestsThisMinute: 0,
        remainingQuota: 1000,
        lastUsed: null,
        lastRequest: null,
        lastError: state?.lastError || null,
        averageLatency: 100,
        failureCount: state?.failureCount || 0,
        successCount: 0,
        cooldownUntil: state?.cooldownUntil ? admin.firestore.Timestamp.fromMillis(state.cooldownUntil) : null,
      });
    });

    // 4. Kimi Worker Pool (Rank 60) - only created if genuine Kimi credentials exist
    const kimiKeys = EnvConfig.getApiKeys("kimi");
    kimiKeys.forEach((key, index) => {
      const workerId = `worker_kimi_${String(index + 1).padStart(2, "0")}`;
      const state = this.workerStateMap.get(workerId);
      const isEligible = this.isWorkerEligible(workerId);

      workers.push({
        workerId,
        provider: "kimi",
        model: "moonshot-v1-8k",
        apiKey: key,
        apiKeyReference: EnvConfig.getKeyIdentifier("kimi", key, index),
        role,
        supportsWebSearch: true,
        supportsImages: true,
        enabled: state?.status !== "disabled",
        busy: state?.status === "busy",
        priority: 60,
        status: isEligible ? "idle" : (state?.status || "idle"),
        currentJobId: null,
        requestsPerMinute: 60,
        minuteLimit: 60,
        dailyLimit: 1000,
        requestsToday: 0,
        requestsThisMinute: 0,
        remainingQuota: 1000,
        lastUsed: null,
        lastRequest: null,
        lastError: state?.lastError || null,
        averageLatency: 130,
        failureCount: state?.failureCount || 0,
        successCount: 0,
        cooldownUntil: state?.cooldownUntil ? admin.firestore.Timestamp.fromMillis(state.cooldownUntil) : null,
      });
    });

    return workers;
  }

  static async acquireWorker(db: admin.firestore.Firestore, workerId: string, jobId: string): Promise<void> {
    const state = this.workerStateMap.get(workerId) || {
      status: "idle",
      cooldownUntil: null,
      failureCount: 0,
    };
    state.status = "busy";
    this.workerStateMap.set(workerId, state);

    const docRef = db.collection("workers").doc(workerId);
    try {
      await docRef.set(
        {
          workerId,
          busy: true,
          status: "busy",
          currentJobId: jobId,
          lastUsed: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } catch (_) {}
  }

  static async releaseWorker(
    db: admin.firestore.Firestore,
    workerId: string,
    latencyMs: number,
    isSuccess: boolean
  ): Promise<void> {
    if (isSuccess) {
      await this.recordWorkerSuccess(db, workerId, latencyMs);
    }
  }

  /**
   * Atomically claims the next eligible job from Firestore with a 15-minute lease.
   */
  static async claimNextJobWithTransaction(
    db: admin.firestore.Firestore,
    worker: AIWorker,
    collectionName: string = "article_jobs"
  ): Promise<{ jobId: string; jobData: any } | null> {
    // If worker is in cooldown or disabled, do not claim jobs
    if (!this.isWorkerEligible(worker.workerId)) {
      return null;
    }

    try {
      const queueSnap = await db
        .collection(collectionName)
        .where("status", "==", "queued")
        .limit(10)
        .get();

      if (queueSnap.empty) return null;

      for (const doc of queueSnap.docs) {
        const jobId = doc.id;
        const jobRef = db.collection(collectionName).doc(jobId);

        const claimedJob = await db.runTransaction(async (transaction) => {
          const freshSnap = await transaction.get(jobRef);
          if (!freshSnap.exists) return null;

          const data = freshSnap.data() || {};
          if (data.status !== "queued") return null;

          const retryAtMs = data.retryAt?.toMillis?.() || 0;
          if (retryAtMs > Date.now()) return null;

          transaction.update(jobRef, {
            status: "processing",
            assignedWorker: worker.workerId,
            assignedProvider: worker.provider,
            startedAt: admin.firestore.FieldValue.serverTimestamp(),
            leaseExpiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 15 * 60 * 1000),
          });

          return { jobId, jobData: data };
        });

        if (claimedJob) return claimedJob;
      }
    } catch (err: any) {
      logger.error("[WORKER_MANAGER_TRANSACTION_ERROR] Failed transaction lock:", err);
    }
    return null;
  }

  static async handleWorkerFailureAndFailover(
    db: admin.firestore.Firestore,
    workerId: string,
    jobId: string,
    errorMessage: string,
    retryLimit: number = 3
  ): Promise<void> {
    logger.warn(`[FAILOVER_TRIGGERED] Worker "${workerId}" failed on job "${jobId}". Error: ${errorMessage}`);
    const classification = this.classifyError(new Error(errorMessage));
    if (classification.isPermanent) {
      await this.disableWorker(db, workerId, errorMessage);
    } else {
      await this.putWorkerInCooldown(db, workerId, classification.cooldownSeconds, errorMessage);
    }

    if (jobId) {
      const jobRef = db.collection("job_queue").doc(jobId);
      const jobSnap = await jobRef.get();
      const jobData = jobSnap.exists ? jobSnap.data() : {};
      await FailedJobService.handleJobFailure(db, jobId, jobData, errorMessage, retryLimit);
    }
  }
}


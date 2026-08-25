import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { AIWorker, WorkerRole } from "../types/worker";
import { AIProviderRegistry } from "../providers/provider_registry";
import { ImageProviderRegistry } from "../providers/image/image_provider_registry";
import { FailedJobService } from "./failed_job_service";
import { EnvConfig } from "../config/env_config";

const PROVIDER_RANKING: Record<string, number> = {
  openai: 10,
  gemini: 20,
  claude: 30,
  deepseek: 40,
  kimi: 50,
  grok: 60,
  pixabay: 70,
  wikimedia: 80,
  bing: 90,
  google: 100,
  unsplash: 110,
};

export class WorkerManager {
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
   * Provider-Agnostic Load Balancer with Worker-Level Health Check & Automatic Failover.
   * Ranking: OpenAI -> Gemini -> Claude -> DeepSeek -> Kimi Pool.
   */
  static async getAvailableWorker(
    db: admin.firestore.Firestore,
    requestedRole: WorkerRole = "DISCOVERY"
  ): Promise<AIWorker | null> {
    try {
      const snap = await db.collection("workers").get();
      const candidateWorkers: AIWorker[] = [];
      const now = Date.now();

      if (!snap.empty) {
        for (const doc of snap.docs) {
          const d = doc.data() || {};
          const workerId = doc.id;

          if (d.enabled === false) continue;
          if (d.busy === true) continue;

          // Check cooldown expiration
          if (d.status === "cooldown" || d.cooldownUntil) {
            const cooldownMs = d.cooldownUntil ? d.cooldownUntil.toDate().getTime() : 0;
            if (cooldownMs > now) {
              continue;
            } else {
              await db.collection("workers").doc(workerId).update({
                status: "idle",
                cooldownUntil: null,
              });
              d.status = "idle";
            }
          }

          const minuteLimit = typeof d.minuteLimit === "number" ? d.minuteLimit : 60;
          const dailyLimit = typeof d.dailyLimit === "number" ? d.dailyLimit : 1000;
          const requestsThisMinute = typeof d.requestsThisMinute === "number" ? d.requestsThisMinute : 0;
          const requestsToday = typeof d.requestsToday === "number" ? d.requestsToday : 0;
          const remainingQuota = typeof d.remainingQuota === "number" ? d.remainingQuota : 1000;

          if (minuteLimit > 0 && requestsThisMinute >= minuteLimit) continue;
          if (dailyLimit > 0 && requestsToday >= dailyLimit) continue;
          if (remainingQuota <= 0) continue;

          const role = d.role || "ANY";
          if (!this.isRoleCompatible(role, requestedRole)) continue;

          const providerName = (d.provider || "openai").toLowerCase();
          if (!AIProviderRegistry.hasProvider(providerName) && !ImageProviderRegistry.hasProvider(providerName)) {
            continue;
          }

          // Provider health check
          if (!EnvConfig.isProviderHealthy(providerName)) {
            logger.warn(`[WORKER_MANAGER] Provider "${providerName}" for worker "${workerId}" is UNHEALTHY. Skipping for failover.`);
            continue;
          }

          // Worker-level health check (e.g. specific Kimi key failure)
          if (!EnvConfig.isWorkerHealthy(workerId)) {
            logger.warn(`[WORKER_MANAGER] Worker "${workerId}" is marked UNHEALTHY. Skipping for worker pool failover.`);
            continue;
          }

          candidateWorkers.push({
            workerId,
            provider: providerName,
            model: d.model || (providerName === "kimi" ? "moonshot-v1-8k" : "gpt-4o"),
            apiKey: d.apiKey || EnvConfig.getApiKey(providerName),
            apiKeyReference: d.apiKeyReference || d.apiKey || "",
            baseUrl: d.baseUrl || undefined,
            role,
            supportsWebSearch: d.supportsWebSearch !== false,
            supportsImages: d.supportsImages === true,
            enabled: true,
            busy: false,
            priority: typeof d.priority === "number" ? d.priority : PROVIDER_RANKING[providerName] || 50,
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
            averageLatency: typeof d.averageLatency === "number" ? d.averageLatency : 300,
            failureCount: d.failureCount || 0,
            successCount: d.successCount || 0,
            cooldownUntil: d.cooldownUntil || null,
          });
        }
      }

      // If no candidate workers found in Firestore, dynamically populate environment pool workers
      if (candidateWorkers.length === 0) {
        const poolWorkers = this.createEnvironmentPoolWorkers(requestedRole);
        for (const w of poolWorkers) {
          if (EnvConfig.isProviderHealthy(w.provider) && EnvConfig.isWorkerHealthy(w.workerId)) {
            candidateWorkers.push(w);
          }
        }
      }

      if (candidateWorkers.length === 0) {
        logger.warn(`[WORKER_MANAGER] No healthy workers available for role "${requestedRole}".`);
        return null;
      }

      // LOAD BALANCER SORTING:
      // 1. Provider Priority Ranking (OpenAI -> Gemini -> Claude -> DeepSeek -> Kimi Pool)
      // 2. Least recently used (round-robin rotation across workers of same provider)
      // 3. Lowest averageLatency
      const getTimeMs = (ts: any): number => {
        if (!ts) return 0;
        if (typeof ts.toDate === "function") return ts.toDate().getTime();
        if (ts instanceof Date) return ts.getTime();
        return new Date(ts).getTime();
      };

      candidateWorkers.sort((a, b) => {
        const rankA = PROVIDER_RANKING[a.provider] || a.priority || 50;
        const rankB = PROVIDER_RANKING[b.provider] || b.priority || 50;
        if (rankA !== rankB) return rankA - rankB;

        const timeA = getTimeMs(a.lastUsed);
        const timeB = getTimeMs(b.lastUsed);
        if (timeA !== timeB) return timeA - timeB;

        return a.averageLatency - b.averageLatency;
      });

      const selected = candidateWorkers[0];
      logger.info(
        `[WORKER_MANAGER] Selected worker "${selected.workerId}" (Provider=${selected.provider}, Latency=${selected.averageLatency}ms, Role=${selected.role})`
      );

      return selected;
    } catch (err: any) {
      logger.error("[WORKER_MANAGER_ERROR] Failed to query workers:", err);
      return this.createEnvironmentPoolWorkers(requestedRole)[0] || null;
    }
  }

  /**
   * Generates dynamic workers from environment variable key pools (Kimi Pool, OpenAI, Gemini, Claude, DeepSeek).
   */
  public static createEnvironmentPoolWorkers(role: WorkerRole = "WRITER"): AIWorker[] {
    const workers: AIWorker[] = [];

    // 1. Gemini Workers (Verified High Quality & Grounded)
    const geminiKeys = EnvConfig.getApiKeys("gemini");
    geminiKeys.forEach((geminiKey, index) => {
      workers.push({
        workerId: `worker_gemini_${String(index + 1).padStart(2, "0")}`,
        provider: "gemini",
        model: "gemini-3.6-flash",
        apiKey: geminiKey,
        role,
        supportsWebSearch: true,
        supportsImages: true,
        enabled: true,
        busy: false,
        priority: 10,
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
        averageLatency: 150,
        failureCount: 0,
        successCount: 0,
        cooldownUntil: null,
      });
    });

    // 2. OpenAI / OpenRouter Workers (Verified via OpenRouter Gateway)
    const openAiKeys = EnvConfig.getApiKeys("openai");
    const openAiBaseUrl = process.env.OPENAI_BASE_URL;
    const openAiModel = process.env.OPENAI_MODEL || "openai/gpt-4o-mini";
    openAiKeys.forEach((openAiKey, index) => {
      workers.push({
        workerId: `worker_openai_${String(index + 1).padStart(2, "0")}`,
        provider: "openai",
        model: openAiModel,
        baseUrl: openAiBaseUrl,
        apiKey: openAiKey,
        role,
        supportsWebSearch: true,
        supportsImages: true,
        enabled: true,
        busy: false,
        priority: 15,
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
        averageLatency: 120,
        failureCount: 0,
        successCount: 0,
        cooldownUntil: null,
      });
    });

    // 3. Grok / Groq Workers (High Speed Verified Inference)
    const grokKeys = EnvConfig.getApiKeys("grok");
    const grokBaseUrl = process.env.GROK_BASE_URL || "https://api.groq.com/openai/v1";
    const grokModel = process.env.GROK_MODEL || "openai/gpt-oss-120b";
    grokKeys.forEach((grokKey, index) => {
      workers.push({
        workerId: `worker_grok_${String(index + 1).padStart(2, "0")}`,
        provider: "grok",
        model: grokModel,
        baseUrl: grokBaseUrl,
        apiKey: grokKey,
        role,
        supportsWebSearch: true,
        supportsImages: true,
        enabled: true,
        busy: false,
        priority: 20,
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
        averageLatency: 100,
        failureCount: 0,
        successCount: 0,
        cooldownUntil: null,
      });
    });

    // 4. Kimi Worker Pool (if configured with valid keys)
    const kimiKeys = EnvConfig.getApiKeys("kimi");
    kimiKeys.forEach((key, index) => {
      workers.push({
        workerId: `worker_kimi_${index + 1}`,
        provider: "kimi",
        model: "moonshot-v1-8k",
        apiKey: key,
        role,
        supportsWebSearch: true,
        supportsImages: true,
        enabled: true,
        busy: false,
        priority: 30,
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
        averageLatency: 130 + index * 5,
        failureCount: 0,
        successCount: 0,
        cooldownUntil: null,
      });
    });

    return workers;
  }

  static async acquireWorker(db: admin.firestore.Firestore, workerId: string, jobId: string): Promise<void> {
    const docRef = db.collection("workers").doc(workerId);
    try {
      await docRef.set({
        workerId,
        busy: true,
        status: "busy",
        currentJobId: jobId,
        lastUsed: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    } catch (_) {}
  }

  static async releaseWorker(
    db: admin.firestore.Firestore,
    workerId: string,
    latencyMs: number,
    isSuccess: boolean
  ): Promise<void> {
    const docRef = db.collection("workers").doc(workerId);
    try {
      await docRef.set({
        busy: false,
        status: "idle",
        currentJobId: null,
        averageLatency: latencyMs,
      }, { merge: true });
    } catch (_) {}
  }

  static async putWorkerInCooldown(
    db: admin.firestore.Firestore,
    workerId: string,
    cooldownMinutes: number = 1,
    reason: string = "Execution failure"
  ): Promise<void> {
    EnvConfig.setWorkerHealth(workerId, false, 0, reason);
    const cooldownDate = new Date(Date.now() + cooldownMinutes * 60 * 1000);
    const docRef = db.collection("workers").doc(workerId);
    try {
      await docRef.set({
        busy: false,
        status: "cooldown",
        currentJobId: null,
        cooldownUntil: admin.firestore.Timestamp.fromDate(cooldownDate),
      }, { merge: true });
    } catch (_) {}
  }

  static async claimNextJobWithTransaction(
    db: admin.firestore.Firestore,
    worker: AIWorker,
    collectionName: string = "article_jobs"
  ): Promise<{ jobId: string; jobData: any } | null> {
    try {
      const queueSnap = await db.collection(collectionName).where("status", "==", "queued").limit(10).get();
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
    await this.putWorkerInCooldown(db, workerId, 15, `Job failure: ${errorMessage}`);

    if (jobId) {
      const jobRef = db.collection("job_queue").doc(jobId);
      const jobSnap = await jobRef.get();
      const jobData = jobSnap.exists ? jobSnap.data() : {};
      await FailedJobService.handleJobFailure(db, jobId, jobData, errorMessage, retryLimit);
    }
  }
}

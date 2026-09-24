import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { AIProviderRegistry } from "../providers/provider_registry";
import { DiscoveredArticle, AIWorker } from "../types/worker";
import { DuplicateDetector } from "./duplicate_detector";
import { ExploreGenerationPipeline } from "./explore_generation_pipeline";
import { WorkerManager } from "./worker_manager";

export interface CanonicalCategory {
  categoryId: string;
  name: string;
  displayOrder: number;
  targetArticles: number;
  hourlyDiscoveryCount: number;
  retentionLimit: number;
}

export const TARGET_10_CATEGORIES: CanonicalCategory[] = [
  { categoryId: "sports", name: "Sports", displayOrder: 1, targetArticles: 25, hourlyDiscoveryCount: 4, retentionLimit: 30 },
  { categoryId: "business", name: "Business", displayOrder: 2, targetArticles: 25, hourlyDiscoveryCount: 4, retentionLimit: 30 },
  { categoryId: "health", name: "Health", displayOrder: 3, targetArticles: 25, hourlyDiscoveryCount: 4, retentionLimit: 30 },
  { categoryId: "technology", name: "Technology", displayOrder: 4, targetArticles: 25, hourlyDiscoveryCount: 4, retentionLimit: 30 },
  { categoryId: "politics", name: "Politics", displayOrder: 5, targetArticles: 25, hourlyDiscoveryCount: 4, retentionLimit: 30 },
  { categoryId: "lifestyle", name: "Lifestyle", displayOrder: 6, targetArticles: 25, hourlyDiscoveryCount: 4, retentionLimit: 30 },
  { categoryId: "kenya", name: "Kenya", displayOrder: 7, targetArticles: 25, hourlyDiscoveryCount: 4, retentionLimit: 30 },
  { categoryId: "africa", name: "Africa", displayOrder: 8, targetArticles: 25, hourlyDiscoveryCount: 4, retentionLimit: 30 },
  { categoryId: "entertainment", name: "Entertainment", displayOrder: 9, targetArticles: 25, hourlyDiscoveryCount: 4, retentionLimit: 30 },
  { categoryId: "agriculture", name: "Agriculture", displayOrder: 10, targetArticles: 25, hourlyDiscoveryCount: 4, retentionLimit: 30 },
];

const normalizeCategoryId = (value: string) => value.trim().toLowerCase()
  .replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

/**
 * The only production queue/publisher path for Explore. categoryNews is
 * metadata; explore_news is the canonical published article collection.
 */
export class CanonicalExploreService {
  /** Synchronizes categoryNews with the exact canonical 10 categories. */
  static async synchronizeCategoryConfiguration(db: admin.firestore.Firestore): Promise<number> {
    const batch = db.batch();
    const targetMap = new Map<string, CanonicalCategory>();
    for (const cat of TARGET_10_CATEGORIES) {
      targetMap.set(cat.categoryId, cat);
      const ref = db.collection("categoryNews").doc(cat.categoryId);
      batch.set(ref, {
        id: cat.categoryId,
        categoryId: cat.categoryId,
        name: cat.name,
        displayOrder: cat.displayOrder,
        targetArticles: cat.targetArticles,
        hourlyDiscoveryCount: cat.hourlyDiscoveryCount,
        retentionLimit: cat.retentionLimit,
        enabled: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    // Disable any legacy or non-canonical categories
    const snap = await db.collection("categoryNews").get();
    for (const doc of snap.docs) {
      const catId = normalizeCategoryId(doc.id);
      if (!targetMap.has(catId)) {
        batch.update(doc.ref, {
          enabled: false,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    await batch.commit();
    logger.info("[EXPLORE_CATEGORY_CONFIG_SYNC] Synchronized 10 canonical categories.");
    return TARGET_10_CATEGORIES.length;
  }

  static async enabledCategories(db: admin.firestore.Firestore): Promise<CanonicalCategory[]> {
    const snap = await db.collection("categoryNews").where("enabled", "==", true).get();
    const seen = new Set<string>();
    const result: CanonicalCategory[] = [];
    for (const doc of snap.docs) {
      const data = doc.data() || {};
      const name = typeof data.name === "string" && data.name.trim() ? data.name.trim() : doc.id;
      const categoryId = normalizeCategoryId(typeof data.categoryId === "string" ? data.categoryId : name);
      if (!categoryId || categoryId === "dummy" || name.toLowerCase().startsWith("dummy") || seen.has(categoryId)) continue;
      seen.add(categoryId);
      result.push({
        categoryId,
        name,
        displayOrder: typeof data.displayOrder === "number" ? data.displayOrder : 999,
        targetArticles: typeof data.targetArticles === "number" ? data.targetArticles : 25,
        hourlyDiscoveryCount: typeof data.hourlyDiscoveryCount === "number" ? data.hourlyDiscoveryCount : 4,
        retentionLimit: typeof data.retentionLimit === "number" ? data.retentionLimit : 30,
      });
    }
    return result.sort((a, b) => a.displayOrder - b.displayOrder);
  }

  static async enqueueDiscovery(db: admin.firestore.Firestore, mode: "initial" | "hourly"): Promise<number> {
    const categories = await this.enabledCategories(db);
    let queued = 0;
    const period = mode === "hourly" ? new Date().toISOString().slice(0, 13) : "initial";
    for (const category of categories) {
      const requestedTarget = mode === "initial" ? category.targetArticles : category.hourlyDiscoveryCount;
      // Initial jobs fill the category to its target; an hourly job always
      // seeks the configured number of additional, unseen events.
      const existing = await db.collection("story_candidates").where("categoryId", "==", category.categoryId).get();
      const target = mode === "initial" ? Math.max(0, requestedTarget - existing.size) : requestedTarget;
      if (target === 0) continue;
      const jobRef = db.collection("discovery_jobs").doc(`${category.categoryId}_${period}`);
      await db.runTransaction(async (tx) => {
        const existing = await tx.get(jobRef);
        if (existing.exists && ["queued", "processing"].includes(existing.data()?.status)) return;
        tx.set(jobRef, {
          categoryId: category.categoryId, category: category.name, target,
          mode, status: "queued", attempts: 0, createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        queued++;
      });
    }
    logger.info("[EXPLORE_DISCOVERY_ENQUEUED]", { mode, queued, categories: categories.length });
    return queued;
  }

  static async processDiscoveryQueue(db: admin.firestore.Firestore, concurrency = 5): Promise<void> {
    const discoveryWorkers = WorkerManager.createEnvironmentPoolWorkers("DISCOVERY").slice(0, concurrency);
    if (!discoveryWorkers.length) {
      logger.error("[EXPLORE_DISCOVERY_NO_WORKERS] No configured discovery keys.");
      return;
    }
    await Promise.all(discoveryWorkers.map((worker) => this.discoveryLoop(db, worker)));
  }

  private static async discoveryLoop(db: admin.firestore.Firestore, initialWorker: AIWorker): Promise<void> {
    while (true) {
      if (!WorkerManager.isWorkerEligible(initialWorker.workerId)) {
        return;
      }

      const job = await this.claimDiscoveryJob(db, initialWorker);
      if (!job) return;

      const availableWorkers = [
        initialWorker,
        ...WorkerManager.createEnvironmentPoolWorkers("DISCOVERY").filter((w) => w.workerId !== initialWorker.workerId),
      ].filter((w) => WorkerManager.isWorkerEligible(w.workerId));

      let accepted = 0;
      let lastError = "";

      for (const worker of availableWorkers) {
        if (accepted >= job.target) break;
        if (!WorkerManager.isWorkerEligible(worker.workerId)) continue;

        try {
          const provider = AIProviderRegistry.getProvider(worker.provider);
          for (let attempt = 0; attempt < 3 && accepted < job.target; attempt++) {
            const stories = await provider.discoverNews(job.category, Math.max(job.target * 2, 25), worker);
            for (const story of stories) {
              if (accepted >= job.target) break;
              if (await this.enqueueCandidate(db, story, job, worker)) accepted++;
            }
          }
          if (accepted > 0) {
            await WorkerManager.recordWorkerSuccess(db, worker.workerId, 150);
            break;
          }
        } catch (err: any) {
          lastError = err?.message || String(err);
          const classification = WorkerManager.classifyError(err, worker.failureCount);
          if (classification.type === "RATE_LIMIT") {
            await WorkerManager.putWorkerInCooldown(db, worker.workerId, classification.cooldownSeconds, classification.cleanMessage);
          } else if (classification.type === "AUTH") {
            await WorkerManager.disableWorker(db, worker.workerId, classification.cleanMessage);
          }
          logger.warn(
            `[EXPLORE_DISCOVERY_WORKER_WARN] Worker "${worker.workerId}" (${worker.provider}) failed for job "${job.id}": ${lastError}. Trying next discovery worker.`
          );
        }
      }

      if (accepted > 0) {
        await db.collection("discovery_jobs").doc(job.id).update({
          status: "completed",
          accepted,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        logger.info("[EXPLORE_DISCOVERY_COMPLETED]", { jobId: job.id, categoryId: job.categoryId, accepted });
      } else {
        await this.failDiscoveryJob(db, job.id, lastError || "All discovery workers failed");
        logger.error("[EXPLORE_DISCOVERY_FAILED]", { jobId: job.id, error: lastError });
      }
    }
  }

  private static async claimDiscoveryJob(db: admin.firestore.Firestore, worker: AIWorker): Promise<any | null> {
    if (!WorkerManager.isWorkerEligible(worker.workerId)) return null;

    const snap = await db.collection("discovery_jobs").where("status", "==", "queued").limit(10).get();
    for (const doc of snap.docs) {
      const claimed = await db.runTransaction(async (tx) => {
        const fresh = await tx.get(doc.ref);
        if (!fresh.exists || fresh.data()?.status !== "queued") return null;
        tx.update(doc.ref, { status: "processing", workerId: worker.workerId, provider: worker.provider, startedAt: admin.firestore.FieldValue.serverTimestamp() });
        return { id: doc.id, ...fresh.data() };
      });
      if (claimed) return claimed;
    }
    return null;
  }

  private static async enqueueCandidate(db: admin.firestore.Firestore, story: DiscoveredArticle, job: any, worker: AIWorker): Promise<boolean> {
    const title = (story.title || "").trim();
    const sourceUrl = (story.sourceUrl || "").trim();
    if (!title || !sourceUrl) return false;
    const fingerprint = DuplicateDetector.generateArticleHash(title, story.source || "");
    const candidateRef = db.collection("story_candidates").doc(fingerprint);
    return db.runTransaction(async (tx) => {
      const existing = await tx.get(candidateRef);
      if (existing.exists) return false;
      const candidate = {
        candidateId: fingerprint, title, categoryId: job.categoryId, category: job.category,
        source: story.source || "Unknown source", sourceUrl, publishedAt: story.publishedAt || null,
        summary: story.summary || "", canonicalIdentity: sourceUrl, fingerprint,
        status: "queued", discoveryWorker: worker.workerId, discoveryProvider: worker.provider,
        discoveredAt: admin.firestore.FieldValue.serverTimestamp(), createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      tx.set(candidateRef, candidate);
      tx.set(db.collection("article_jobs").doc(fingerprint), {
        ...candidate, status: "queued", attempts: 0, retryAt: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  static async processArticleQueue(db: admin.firestore.Firestore, maxWorkers = 15): Promise<void> {
    await this.recoverExpiredArticleLeases(db);
    const workers = WorkerManager.createEnvironmentPoolWorkers("WRITER")
      .filter((worker) => WorkerManager.isWorkerEligible(worker.workerId))
      .slice(0, maxWorkers);
    await Promise.all(workers.map((worker) => this.articleLoop(db, worker)));
  }

  private static async articleLoop(db: admin.firestore.Firestore, worker: AIWorker): Promise<void> {
    while (true) {
      if (!WorkerManager.isWorkerEligible(worker.workerId)) {
        logger.info(`[AI_WORKER_LOOP_EXIT] Worker "${worker.workerId}" is in cooldown or disabled. Exiting loop.`);
        return;
      }

      const claimed = await WorkerManager.claimNextJobWithTransaction(db, worker, "article_jobs");
      if (!claimed) return;
      const { jobId, jobData } = claimed;
      const startTime = Date.now();

      try {
        const result = await ExploreGenerationPipeline.generateArticleForTopic(
          db, jobData.title, jobData.category, true,
          { candidateId: jobId, source: jobData.source, sourceUrl: jobData.sourceUrl, publishedAt: jobData.publishedAt,
            discoveryWorker: jobData.discoveryWorker, discoveryProvider: jobData.discoveryProvider, categoryId: jobData.categoryId }, worker
        );
        if (!result.success) throw new Error(result.error || "Article failed readiness validation");

        const latencyMs = Date.now() - startTime;
        await WorkerManager.recordWorkerSuccess(db, worker.workerId, latencyMs);

        const batch = db.batch();
        batch.update(db.collection("article_jobs").doc(jobId), {
          status: "published",
          articleId: result.articleId,
          leaseExpiresAt: null,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        batch.update(db.collection("story_candidates").doc(jobId), {
          status: "published",
          articleId: result.articleId,
          publishedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await batch.commit();

        await this.enforceRetention(db, jobData.categoryId, 30);
        logger.info(
          `[AI_WORKER] worker="${worker.workerId}" provider="${worker.provider}" key="${worker.apiKeyReference}" status="idle" action="published" job="${jobId}" articleId="${result.articleId}"`
        );
      } catch (error: any) {
        const classification = WorkerManager.classifyError(error, worker.failureCount);

        if (classification.type === "RATE_LIMIT") {
          await WorkerManager.putWorkerInCooldown(db, worker.workerId, classification.cooldownSeconds, classification.cleanMessage);
          await this.failArticleJob(db, jobId, jobData, classification.cleanMessage, 10_000);
          logger.warn(
            `[AI_WORKER] worker="${worker.workerId}" provider="${worker.provider}" key="${worker.apiKeyReference}" status="cooldown" error="429_rate_limit" cooldownSeconds=${classification.cooldownSeconds} action="release_and_retry" job="${jobId}"`
          );
          return; // Exit this worker loop; other healthy workers continue
        } else if (classification.type === "AUTH") {
          await WorkerManager.disableWorker(db, worker.workerId, classification.cleanMessage);
          await this.failArticleJob(db, jobId, jobData, classification.cleanMessage, 0); // Immediate retry for other healthy workers
          logger.error(
            `[AI_WORKER] worker="${worker.workerId}" provider="${worker.provider}" key="${worker.apiKeyReference}" status="disabled" error="401_auth_failure" action="quarantine_key" job="${jobId}"`
          );
          return; // Exit this worker loop
        } else if (classification.type === "MALFORMED") {
          await this.failArticleJob(db, jobId, jobData, classification.cleanMessage, 5_000);
          logger.warn(
            `[AI_WORKER] worker="${worker.workerId}" provider="${worker.provider}" key="${worker.apiKeyReference}" status="retry" error="malformed_output" action="release_and_retry" job="${jobId}"`
          );
          if (classification.cooldownSeconds > 10) {
            await WorkerManager.putWorkerInCooldown(db, worker.workerId, classification.cooldownSeconds, classification.cleanMessage);
            return;
          }
        } else {
          // Timeout, server error, or other transient
          await this.failArticleJob(db, jobId, jobData, classification.cleanMessage, 15_000);
          logger.warn(
            `[AI_WORKER] worker="${worker.workerId}" provider="${worker.provider}" key="${worker.apiKeyReference}" status="retry" error="${classification.type}" action="release_and_retry" job="${jobId}"`
          );
          if (classification.cooldownSeconds > 10) {
            await WorkerManager.putWorkerInCooldown(db, worker.workerId, classification.cooldownSeconds, classification.cleanMessage);
            return;
          }
        }
      }
    }
  }

  static async enforceRetention(db: admin.firestore.Firestore, categoryId: string, fallbackLimit: number): Promise<void> {
    const category = (await this.enabledCategories(db)).find((item) => item.categoryId === categoryId);
    const limit = category?.retentionLimit || fallbackLimit;
    const snap = await db.collection("explore_news").where("categoryId", "==", categoryId).where("status", "==", "published").get();
    const docs = [...snap.docs].sort((a, b) => {
      const aMs = a.data().publishedAt?.toMillis?.() || 0;
      const bMs = b.data().publishedAt?.toMillis?.() || 0;
      return bMs - aMs;
    });
    const excess = docs.slice(limit);
    if (!excess.length) return;
    const batch = db.batch();
    excess.forEach((doc) => {
      // Retention is recoverable: retain a compact audit/archive record before
      // removing it from the realtime canonical collection.
      batch.set(db.collection("explore_news_archive").doc(doc.id), { ...doc.data(), archivedAt: admin.firestore.FieldValue.serverTimestamp(), archiveReason: "retention" });
      batch.delete(doc.ref);
    });
    await batch.commit();
    logger.info("[EXPLORE_RETENTION_DELETED]", { categoryId, deleted: excess.length, limit });
  }

  private static async failDiscoveryJob(db: admin.firestore.Firestore, id: string, error: string): Promise<void> {
    const ref = db.collection("discovery_jobs").doc(id);
    const snap = await ref.get();
    const attempts = (snap.data()?.attempts || 0) + 1;
    await ref.update({ status: attempts >= 3 ? "failed" : "queued", attempts, lastError: error, retryAt: admin.firestore.Timestamp.fromMillis(Date.now() + 60_000), updatedAt: admin.firestore.FieldValue.serverTimestamp() });
  }

  private static async failArticleJob(
    db: admin.firestore.Firestore,
    id: string,
    data: any,
    error: string,
    retryDelayMs: number = 60_000
  ): Promise<void> {
    const attempts = (data.attempts || 0) + 1;
    const ref = db.collection("article_jobs").doc(id);
    const update = {
      status: attempts >= 5 ? "failed" : "queued",
      attempts,
      lastError: error,
      assignedWorker: null,
      leaseExpiresAt: null,
      retryAt: attempts >= 5 ? null : admin.firestore.Timestamp.fromMillis(Date.now() + retryDelayMs),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await ref.update(update);
    if (attempts >= 5) await db.collection("failed_article_jobs").doc(id).set({ ...data, ...update, failedAt: admin.firestore.FieldValue.serverTimestamp() });
  }

  static async recoverExpiredArticleLeases(db: admin.firestore.Firestore): Promise<void> {
    try {
      const now = admin.firestore.Timestamp.now();
      const expired = await db.collection("article_jobs").where("status", "==", "processing").where("leaseExpiresAt", "<=", now).limit(100).get();
      if (expired.empty) return;
      const batch = db.batch();
      expired.docs.forEach((doc) => batch.update(doc.ref, {
        status: "queued", assignedWorker: null, leaseExpiresAt: null,
        lastError: "Worker lease expired; returned to queue", updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }));
      await batch.commit();
      logger.warn("[EXPLORE_EXPIRED_LEASES_RECOVERED]", { count: expired.size });
    } catch (err: any) {
      if (err?.message?.includes("index") || err?.code === 9) {
        try {
          const snap = await db.collection("article_jobs").where("status", "==", "processing").limit(100).get();
          const nowMs = Date.now();
          const batch = db.batch();
          let count = 0;
          snap.docs.forEach((doc) => {
            const leaseMs = doc.data().leaseExpiresAt?.toMillis?.() || 0;
            if (leaseMs > 0 && leaseMs <= nowMs) {
              batch.update(doc.ref, {
                status: "queued", assignedWorker: null, leaseExpiresAt: null,
                lastError: "Worker lease expired; returned to queue", updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              });
              count++;
            }
          });
          if (count > 0) await batch.commit();
        } catch (_) {}
      }
    }
  }
}

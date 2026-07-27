import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { ConfigService } from "./config_service";
import { SchedulerStateService } from "./scheduler_state_service";
import { WorkerManager } from "./worker_manager";
import { AIProviderRegistry } from "../providers/provider_registry";
import { DuplicateDetector } from "./duplicate_detector";
import { JobQueueItem, StoryClusterItem } from "../types/explore";
import { WriterPoolService } from "./writer_pool_service";
import { ImagePoolService } from "./image_pool_service";

export class ExploreScheduler {
  /**
   * Executes Provider-Agnostic News Discovery, Writing & Real Photo Search Scheduler.
   * Uses DISCOVERY workers for headlines, WRITER workers for article writing, and IMAGE workers for real photo search.
   */
  static async run(db: admin.firestore.Firestore): Promise<{
    success: boolean;
    reason?: string;
    categoriesProcessed?: number;
    totalArticlesQueued?: number;
    totalArticlesSkipped?: number;
    writerJobsProcessed?: number;
    imageJobsProcessed?: number;
    executionTimeMs?: number;
  }> {
    const startTime = Date.now();
    logger.info("[SCHEDULER_START] Distributed Provider-Agnostic Scheduler started");

    // 1. Acquire distributed lock on scheduler/explore
    const lock = await SchedulerStateService.acquireSearchLock(db);
    if (!lock.acquired) {
      logger.info(`[SCHEDULER_SKIP] Execution skipped: ${lock.reason}`);
      return {
        success: false,
        reason: lock.reason,
      };
    }

    let categoriesProcessedCount = 0;
    let totalQueuedCount = 0;
    let totalSkippedCount = 0;

    try {
      // 2. Read configuration from system/exploreConfig
      const config = await ConfigService.getExploreConfig(db);

      // 3. Read enabled categories from categoryNews collection dynamically
      const categoriesSnap = await db
        .collection("categoryNews")
        .where("enabled", "==", true)
        .get();

      if (!categoriesSnap.empty) {
        // Filter duplicates & sort categories by displayOrder ascending
        const seenCategoryNames = new Set<string>();
        const categories: Array<{
          id: string;
          name: string;
          displayOrder: number;
          targetArticles?: number;
        }> = [];

        for (const doc of categoriesSnap.docs) {
          const data = doc.data() || {};
          const name = typeof data.name === "string" ? data.name.trim() : doc.id;
          const normalizedName = name.toLowerCase();

          if (seenCategoryNames.has(normalizedName)) {
            logger.warn(`[SCHEDULER_WARN] Duplicate category name "${name}" detected. Skipping document ${doc.id}.`);
            continue;
          }
          seenCategoryNames.add(normalizedName);

          categories.push({
            id: doc.id,
            name,
            displayOrder: typeof data.displayOrder === "number" ? data.displayOrder : 999,
            targetArticles: typeof data.targetArticles === "number" ? data.targetArticles : undefined,
          });
        }

        categories.sort((a, b) => a.displayOrder - b.displayOrder);

        logger.info(
          `[SCHEDULER_CATEGORIES] Loaded ${categories.length} enabled categories from Firestore ordered by displayOrder.`
        );

        // 4. Process categories using DISCOVERY workers
        for (const cat of categories) {
          const categoryId = cat.id;
          const categoryName = cat.name;
          const targetArticles =
            cat.targetArticles && cat.targetArticles > 0
              ? cat.targetArticles
              : config.articlesPerCategory;

          // Request next available DISCOVERY worker from Load Balancer
          const worker = await WorkerManager.getAvailableWorker(db, "DISCOVERY");
          if (!worker) {
            logger.warn(`[SCHEDULER_WARN] No available DISCOVERY worker for category "${categoryName}".`);
            continue;
          }

          const provider = AIProviderRegistry.getProvider(worker.provider);
          logger.info(
            `[SCHEDULER_CATEGORY] Category="${categoryName}" Assigned Worker="${worker.workerId}" Provider="${provider.name}"`
          );

          await SchedulerStateService.updateCurrentCategory(db, categoryName);
          const catStartTime = Date.now();
          await WorkerManager.acquireWorker(db, worker.workerId, categoryId);

          try {
            // Discover news via Provider interface
            const discoveredArticles = await provider.discoverNews(
              categoryName,
              targetArticles,
              worker
            );

            const latencyMs = Date.now() - catStartTime;
            await WorkerManager.releaseWorker(db, worker.workerId, latencyMs, true);

            logger.info(
              `[SCHEDULER_STORIES] Provider="${provider.name}" Worker="${worker.workerId}" returned ${discoveredArticles.length} stories in ${latencyMs}ms.`
            );

            let accepted = 0;
            let skipped = 0;
            const localSeenHashes = new Set<string>();

            for (const article of discoveredArticles) {
              const articleHash = DuplicateDetector.generateArticleHash(
                article.title,
                article.source
              );
              const clusterId = article.clusterId || DuplicateDetector.generateClusterId(articleHash);

              // Deduplicate within the same batch
              if (localSeenHashes.has(articleHash)) {
                skipped++;
                continue;
              }
              localSeenHashes.add(articleHash);

              // Deduplicate against Firestore
              const isDup = await DuplicateDetector.isDuplicate(db, articleHash);
              if (isDup) {
                skipped++;
                continue;
              }

              // Write story cluster entry into storyClusters
              const clusterItem: StoryClusterItem = {
                clusterId,
                title: article.title,
                summary: article.summary,
                category: categoryName,
                source: article.source,
                sourceUrl: article.sourceUrl,
                publishedAt: article.publishedAt,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                articleHash,
                status: "discovered",
              };
              await db.collection("storyClusters").doc(clusterId).set(clusterItem);

              // Write headline job into job_queue
              const queueItem: JobQueueItem = {
                clusterId,
                title: article.title,
                summary: article.summary,
                category: categoryName,
                source: article.source,
                sourceUrl: article.sourceUrl,
                publishedAt: article.publishedAt,
                status: "queued",
                assignedWorker: null,
                retries: 0,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                articleHash,
              };
              await db.collection("job_queue").add(queueItem);

              accepted++;
            }

            logger.info(`[SCHEDULER_CATEGORY_METRICS] Category="${categoryName}" - Accepted: ${accepted}, Skipped: ${skipped}`);

            await SchedulerStateService.recordCategorySuccess(db, categoryId, accepted);

            categoriesProcessedCount++;
            totalQueuedCount += accepted;
            totalSkippedCount += skipped;
          } catch (catErr: any) {
            logger.error(`[SCHEDULER_CATEGORY_ERROR] Error discovering category "${categoryName}" with worker "${worker.workerId}":`, catErr);

            await WorkerManager.handleWorkerFailureAndFailover(
              db,
              worker.workerId,
              `category_${categoryId}`,
              catErr.message || "Category discovery error",
              3
            );
            await SchedulerStateService.recordCategoryFailure(db, categoryName, catErr);
          }
        }
      }

      // 5. Trigger Writer Pool to process queued jobs with WRITER workers
      let writerStats = { processedCount: 0, successCount: 0, failureCount: 0 };
      try {
        writerStats = await WriterPoolService.processWriterQueue(db, 10);
      } catch (writerErr) {
        logger.error("[SCHEDULER_WRITER_POOL_ERROR] Writer pool execution error:", writerErr);
      }

      // 6. Trigger Image Pool to attach real internet photos using IMAGE workers
      let imageStats = { processedCount: 0, successCount: 0, failureCount: 0 };
      try {
        imageStats = await ImagePoolService.processImageWorkerQueue(db, 5);
      } catch (imageErr) {
        logger.error("[SCHEDULER_IMAGE_POOL_ERROR] Image pool execution error:", imageErr);
      }

      // 7. Finalize scheduler state
      await SchedulerStateService.releaseSearchLock(db, config.refreshMinutes);

      const executionTimeMs = Date.now() - startTime;
      logger.info(
        `[SCHEDULER_FINISH] Completed in ${executionTimeMs}ms. CategoriesProcessed=${categoriesProcessedCount} Queued=${totalQueuedCount} WriterJobsProcessed=${writerStats.processedCount} ImageJobsProcessed=${imageStats.processedCount}`
      );

      return {
        success: true,
        categoriesProcessed: categoriesProcessedCount,
        totalArticlesQueued: totalQueuedCount,
        totalArticlesSkipped: totalSkippedCount,
        writerJobsProcessed: writerStats.processedCount,
        imageJobsProcessed: imageStats.processedCount,
        executionTimeMs,
      };
    } catch (fatalErr: any) {
      logger.error("[SCHEDULER_FATAL] Unexpected error in scheduler execution:", fatalErr);
      await SchedulerStateService.releaseSearchLock(db, 60);

      const executionTimeMs = Date.now() - startTime;
      return {
        success: false,
        reason: fatalErr.message,
        executionTimeMs,
      };
    }
  }
}

import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";
import { WorkerManager } from "./worker_manager";
import { ArticleImageSearchService } from "./article_image_service";

function getImageKit(): ImageKit {
  const publicKey = process.env.IMAGEKIT_PUBLIC_KEY || "public_fS58uA9h5vC6EwGv29Z=";
  const privateKey = process.env.IMAGEKIT_PRIVATE_KEY || "private_Ym87v5...=";
  const urlEndpoint = process.env.IMAGEKIT_URL_ENDPOINT || "https://ik.imagekit.io/ubgbitinve";

  return new ImageKit({
    publicKey,
    privateKey,
    urlEndpoint,
  });
}

export class ImagePoolService {
  /**
   * Processes articles needing real internet images using available IMAGE workers.
   * Finds articles in explore_news with imageSearchCompleted != true.
   */
  static async processImageWorkerQueue(
    db: admin.firestore.Firestore,
    maxArticlesToProcess: number = 5
  ): Promise<{
    processedCount: number;
    successCount: number;
    failureCount: number;
  }> {
    logger.info("[IMAGE_POOL_START] Starting Image Worker pool processing cycle...");

    let processedCount = 0;
    let successCount = 0;
    let failureCount = 0;

    try {
      // Fetch articles in explore_news requiring image processing
      const snap = await db
        .collection("explore_news")
        .where("imageSearchCompleted", "!=", true)
        .limit(maxArticlesToProcess)
        .get();

      if (snap.empty) {
        logger.info("[IMAGE_POOL_IDLE] No pending articles needing image processing.");
        return { processedCount, successCount, failureCount };
      }

      const ik = getImageKit();

      for (const doc of snap.docs) {
        // Get available IMAGE worker from WorkerManager Load Balancer
        const worker = await WorkerManager.getAvailableWorker(db, "IMAGE");
        if (!worker) {
          logger.warn("[IMAGE_POOL_NO_WORKER] No available IMAGE worker found. Pausing cycle.");
          break;
        }

        const articleData = doc.data() || {};
        const articleId = doc.id;
        const title = articleData.title || "Untitled News Story";
        const startTime = Date.now();

        logger.info(
          `[IMAGE_WORKER_EXECUTE] Worker="${worker.workerId}" Provider="${worker.provider}" processing images for articleId="${articleId}" Title="${title}"`
        );

        await WorkerManager.acquireWorker(db, worker.workerId, `img_${articleId}`);

        try {
          const result = await ArticleImageSearchService.processArticleImages(
            db,
            ik,
            {
              id: articleId,
              clusterId: articleData.clusterId || articleId,
              title: title,
              content: articleData.content || "",
              summary: articleData.summary || "",
              category: articleData.category || "General",
              source: articleData.source || "News",
            },
            5 // Target 5 real internet images
          );

          const latencyMs = Date.now() - startTime;
          await WorkerManager.releaseWorker(db, worker.workerId, latencyMs, true);

          // Update Firestore explore_news document
          await db.collection("explore_news").doc(articleId).update({
            images: result.images,
            imageCount: result.imageCount,
            imageSearchCompleted: true,
            imageSearchAttempts: admin.firestore.FieldValue.increment(1),
            imageSources: result.imageSources,
            content: result.updatedContent,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          successCount++;
          logger.info(
            `[IMAGE_WORKER_SUCCESS] Worker "${worker.workerId}" attached ${result.imageCount} real internet photos to article "${articleId}" in ${latencyMs}ms.`
          );
        } catch (err: any) {
          const latencyMs = Date.now() - startTime;
          logger.error(`[IMAGE_WORKER_ERROR] Error processing images for article "${articleId}":`, err);

          await WorkerManager.releaseWorker(db, worker.workerId, latencyMs, false);

          // Record attempt count & set completed true on failover so article is never blocked
          await db.collection("explore_news").doc(articleId).update({
            imageSearchCompleted: true,
            imageSearchAttempts: admin.firestore.FieldValue.increment(1),
            lastImageError: err.message || "Image processing error",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          failureCount++;
        }

        processedCount++;
      }
    } catch (err: any) {
      logger.error("[IMAGE_POOL_FATAL] Error in Image Worker processing cycle:", err);
    }

    logger.info(
      `[IMAGE_POOL_FINISH] Image Worker cycle finished. Processed=${processedCount} Success=${successCount} Failure=${failureCount}`
    );

    return { processedCount, successCount, failureCount };
  }
}

import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";
import { WorkerManager } from "./worker_manager";
import { ImageProviderRegistry } from "../providers/image/image_provider_registry";
import { ImageValidationService } from "./image_validation_service";
import { ArticleImageSearchService } from "./article_image_service";
import { ImageSearchResult } from "../types/image_worker";

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
   * Leverages ImageProviderRegistry to retrieve metadata only and ImageValidationService to download, validate, and upload.
   */
  static async processImageWorkerQueue(
    db: admin.firestore.Firestore,
    maxArticlesToProcess: number = 5
  ): Promise<{
    processedCount: number;
    successCount: number;
    failureCount: number;
  }> {
    logger.info("[IMAGE_POOL_START] Starting Provider-Agnostic Image Worker pool processing cycle...");

    let processedCount = 0;
    let successCount = 0;
    let failureCount = 0;

    try {
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
        const worker = await WorkerManager.getAvailableWorker(db, "IMAGE");
        if (!worker) {
          logger.warn("[IMAGE_POOL_NO_WORKER] No available IMAGE worker found. Pausing cycle.");
          break;
        }

        const articleData = doc.data() || {};
        const articleId = doc.id;
        const title = articleData.title || "Untitled News Story";
        const content = articleData.content || "";
        const summary = articleData.summary || "";
        const category = articleData.category || "General";
        const startTime = Date.now();

        logger.info(
          `[IMAGE_WORKER_EXECUTE] Worker="${worker.workerId}" ImageProvider="${worker.provider}" processing articleId="${articleId}" Title="${title}"`
        );

        await WorkerManager.acquireWorker(db, worker.workerId, `img_${articleId}`);

        try {
          // Get provider from ImageProviderRegistry
          const provider = ImageProviderRegistry.getProvider(worker.provider);
          const queries = ArticleImageSearchService.buildArticleSearchQueries(title, summary, category);
          const allCandidateMetadata: ImageSearchResult[] = [];
          const seenUrls = new Set<string>();

          for (const q of queries) {
            const searchResults = await provider.searchImages(q, { limit: 15 }, worker);
            for (const item of searchResults) {
              if (item && item.imageUrl && !seenUrls.has(item.imageUrl)) {
                seenUrls.add(item.imageUrl);
                allCandidateMetadata.push(item);
              }
            }
            if (allCandidateMetadata.length >= 20) break;
          }

          let valResult;
          if (allCandidateMetadata.length > 0) {
            // Process metadata with ImageValidationService (download, validate, hash check, upload to ImageKit)
            valResult = await ImageValidationService.processCandidateMetadata(
              db,
              ik,
              allCandidateMetadata,
              { title, content },
              5
            );
          } else {
            // Fallback to ArticleImageSearchService if provider returned 0 metadata
            valResult = await ArticleImageSearchService.processArticleImages(
              db,
              ik,
              {
                id: articleId,
                clusterId: articleData.clusterId || articleId,
                title,
                content,
                summary,
                category,
              },
              5
            );
          }

          const latencyMs = Date.now() - startTime;
          await WorkerManager.releaseWorker(db, worker.workerId, latencyMs, true);

          await db.collection("explore_news").doc(articleId).update({
            images: valResult.images,
            imageCount: valResult.imageCount,
            imageSearchCompleted: true,
            imageSearchAttempts: admin.firestore.FieldValue.increment(1),
            imageSources: valResult.imageSources,
            content: valResult.updatedContent,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          successCount++;
          logger.info(
            `[IMAGE_WORKER_SUCCESS] Provider="${provider.name}" Worker="${worker.workerId}" attached ${valResult.imageCount} real photos to article "${articleId}" in ${latencyMs}ms.`
          );
        } catch (err: any) {
          const latencyMs = Date.now() - startTime;
          logger.error(`[IMAGE_WORKER_ERROR] Error processing images for article "${articleId}":`, err);

          await WorkerManager.releaseWorker(db, worker.workerId, latencyMs, false);

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

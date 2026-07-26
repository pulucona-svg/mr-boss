import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { WorkerManager } from "./worker_manager";
import { AIProviderRegistry } from "../providers/provider_registry";

export class WriterPoolService {
  /**
   * Processes queued jobs in job_queue using available WRITER workers.
   * Uses atomic Firestore transaction locking to prevent duplicate processing.
   */
  static async processWriterQueue(
    db: admin.firestore.Firestore,
    maxJobsToProcess: number = 10
  ): Promise<{
    processedCount: number;
    successCount: number;
    failureCount: number;
  }> {
    logger.info("[WRITER_POOL_START] Starting Writer Pool processing cycle...");

    let processedCount = 0;
    let successCount = 0;
    let failureCount = 0;

    for (let i = 0; i < maxJobsToProcess; i++) {
      // 1. Get available WRITER worker
      const worker = await WorkerManager.getAvailableWorker(db, "WRITER");
      if (!worker) {
        logger.info("[WRITER_POOL_IDLE] No available WRITER workers. Ending cycle.");
        break;
      }

      // 2. Claim next queued job atomically via Firestore transaction
      const claimedJob = await WorkerManager.claimNextJobWithTransaction(db, worker);
      if (!claimedJob) {
        logger.info("[WRITER_POOL_EMPTY] No more queued jobs in job_queue.");
        break;
      }

      const { jobId, jobData } = claimedJob;
      const startTime = Date.now();

      try {
        const provider = AIProviderRegistry.getProvider(worker.provider);
        logger.info(
          `[WRITER_POOL_EXECUTE] Worker="${worker.workerId}" Provider="${provider.name}" processing job="${jobId}" Title="${jobData.title}"`
        );

        // 3. Execute publish / story generation via provider abstraction interface
        const result = await provider.publishArticle(jobData, worker);
        const latencyMs = Date.now() - startTime;

        if (result.success) {
          // Success: update worker metrics and mark job completed
          await WorkerManager.releaseWorker(db, worker.workerId, latencyMs, true);

          const batch = db.batch();

          // Mark completed in job_queue (or remove)
          const jobRef = db.collection("job_queue").doc(jobId);
          batch.update(jobRef, {
            status: "completed",
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
            processedByWorker: worker.workerId,
          });

          // Update storyClusters status
          if (jobData.clusterId) {
            const clusterRef = db.collection("storyClusters").doc(jobData.clusterId);
            batch.update(clusterRef, {
              status: "published",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }

          await batch.commit();

          successCount++;
          logger.info(`[WRITER_POOL_SUCCESS] Job "${jobId}" published successfully by "${worker.workerId}" in ${latencyMs}ms.`);
        } else {
          // Execution failed -> handle failover
          const errorMsg = result.error || "Article generation failed";
          await WorkerManager.handleWorkerFailureAndFailover(db, worker.workerId, jobId, errorMsg);
          failureCount++;
        }
      } catch (err: any) {
        logger.error(`[WRITER_POOL_ERROR] Exception processing job "${jobId}" with worker "${worker.workerId}":`, err);


        await WorkerManager.handleWorkerFailureAndFailover(
          db,
          worker.workerId,
          jobId,
          err.message || "Execution exception"
        );
        failureCount++;
      }

      processedCount++;
    }

    logger.info(
      `[WRITER_POOL_FINISH] Writer Pool cycle finished. Processed=${processedCount} Success=${successCount} Failure=${failureCount}`
    );

    return { processedCount, successCount, failureCount };
  }
}

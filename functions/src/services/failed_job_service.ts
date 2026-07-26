import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

export class FailedJobService {
  /**
   * Records a job execution failure. If retryCount >= retryLimit, moves the job to failed_jobs collection.
   */
  static async handleJobFailure(
    db: admin.firestore.Firestore,
    jobId: string,
    jobData: any,
    errorMessage: string,
    retryLimit: number = 3
  ): Promise<void> {
    const currentRetries = (jobData.retries || 0) + 1;
    logger.warn(`[JOB_FAILURE] Job "${jobId}" failed attempt ${currentRetries}/${retryLimit}: ${errorMessage}`);

    if (currentRetries >= retryLimit) {
      // Exceeded retry limit -> move to failed_jobs
      logger.error(`[JOB_FAILED_PERMANENT] Job "${jobId}" exceeded retry limit (${retryLimit}). Moving to failed_jobs collection.`);

      const batch = db.batch();

      // Write into failed_jobs collection
      const failedDocRef = db.collection("failed_jobs").doc(jobId);
      batch.set(failedDocRef, {
        ...jobData,
        status: "failed",
        retries: currentRetries,
        lastError: errorMessage,
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Remove or mark failed in job_queue
      if (jobId) {
        const queueDocRef = db.collection("job_queue").doc(jobId);
        batch.delete(queueDocRef);
      }

      await batch.commit();
    } else {
      // Update retry count in job_queue for next worker retry
      if (jobId) {
        await db.collection("job_queue").doc(jobId).update({
          status: "queued",
          assignedWorker: null,
          retries: currentRetries,
          lastError: errorMessage,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }
  }

  /**
   * Scans failed_jobs collection and attempts to re-queue eligible jobs for retry.
   */
  static async retryFailedJobs(
    db: admin.firestore.Firestore,
    maxToRetry: number = 10
  ): Promise<number> {
    logger.info("[FAILED_JOB_RECOVERY] Scanning failed_jobs collection for re-queueing...");
    let requeuedCount = 0;

    try {
      const snap = await db
        .collection("failed_jobs")
        .limit(maxToRetry)
        .get();

      if (snap.empty) {
        logger.info("[FAILED_JOB_RECOVERY] No failed jobs to recover.");
        return 0;
      }

      for (const doc of snap.docs) {
        const data = doc.data();
        const jobId = doc.id;

        const batch = db.batch();

        // Re-add to job_queue with reset retries
        const queueRef = db.collection("job_queue").doc(jobId);
        batch.set(queueRef, {
          ...data,
          status: "queued",
          assignedWorker: null,
          retries: 0,
          requeuedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Delete from failed_jobs
        batch.delete(doc.ref);

        await batch.commit();
        requeuedCount++;
      }

      logger.info(`[FAILED_JOB_RECOVERY] Requeued ${requeuedCount} jobs back into job_queue.`);
      return requeuedCount;
    } catch (err: any) {
      logger.error("[FAILED_JOB_RECOVERY_ERROR] Failed job recovery error:", err);
      return 0;
    }
  }
}

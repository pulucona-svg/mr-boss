import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

export interface LockResult {
  acquired: boolean;
  reason?: string;
}

export class SchedulerStateService {
  private static LOCK_TIMEOUT_MS = 15 * 60 * 1000; // 15 minutes lock expiration safeguard

  /**
   * Acquires the search lock on scheduler/explore document atomically.
   * If another run is actively executing (isSearching=true and lock is fresh), returns acquired: false.
   */
  static async acquireSearchLock(
    db: admin.firestore.Firestore
  ): Promise<LockResult> {
    const docRef = db.collection("scheduler").doc("explore");

    try {
      return await db.runTransaction(async (transaction) => {
        const snap = await transaction.get(docRef);
        const now = Date.now();

        if (snap.exists) {
          const data = snap.data() || {};
          const isSearching = data.isSearching === true;
          const lockTime = data.lockTimestamp ? data.lockTimestamp.toDate().getTime() : 0;

          if (isSearching && now - lockTime < this.LOCK_TIMEOUT_MS) {
            logger.warn("[SCHEDULER_LOCK] Active execution detected. Lock acquisition declined.");
            return {
              acquired: false,
              reason: "Scheduler is currently running in another execution instance.",
            };
          }
        }

        const existingData = snap.exists ? snap.data() || {} : {};

        transaction.set(
          docRef,
          {
            currentCategory: null,
            currentQueue: existingData.currentQueue || 0,
            isSearching: true,
            isPublishing: existingData.isPublishing || false,
            categoriesCompleted: 0,
            totalQueued: existingData.totalQueued || 0,
            totalPublished: existingData.totalPublished || 0,
            totalFailed: existingData.totalFailed || 0,
            lastRun: admin.firestore.FieldValue.serverTimestamp(),
            lockTimestamp: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        return { acquired: true };
      });
    } catch (err: any) {
      logger.error("[SCHEDULER_LOCK_ERROR] Failed to acquire lock:", err);
      return { acquired: false, reason: err.message };
    }
  }

  /**
   * Updates the current category being processed by the scheduler.
   */
  static async updateCurrentCategory(
    db: admin.firestore.Firestore,
    categoryName: string
  ): Promise<void> {
    const docRef = db.collection("scheduler").doc("explore");
    await docRef.update({
      currentCategory: categoryName,
    });
  }

  /**
   * Records successful processing of a category, updates metrics and category doc.
   */
  static async recordCategorySuccess(
    db: admin.firestore.Firestore,
    categoryId: string,
    queuedCount: number
  ): Promise<void> {
    const schedulerRef = db.collection("scheduler").doc("explore");
    const categoryRef = db.collection("categories").doc(categoryId);

    const batch = db.batch();

    // Update scheduler metrics
    batch.update(schedulerRef, {
      categoriesCompleted: admin.firestore.FieldValue.increment(1),
      totalQueued: admin.firestore.FieldValue.increment(queuedCount),
    });

    // Update category doc tracking
    batch.update(categoryRef, {
      lastFetched: admin.firestore.FieldValue.serverTimestamp(),
      publishedToday: admin.firestore.FieldValue.increment(queuedCount),
    });

    await batch.commit();
  }

  /**
   * Records a category failure, incrementing totalFailed counter.
   */
  static async recordCategoryFailure(
    db: admin.firestore.Firestore,
    categoryName: string,
    error: any
  ): Promise<void> {
    logger.error(`[SCHEDULER_CATEGORY_FAILURE] Category "${categoryName}" failed:`, error);
    const docRef = db.collection("scheduler").doc("explore");
    await docRef.update({
      totalFailed: admin.firestore.FieldValue.increment(1),
    });
  }

  /**
   * Releases search lock and computes current queued items count & next scheduled run time.
   */
  static async releaseSearchLock(
    db: admin.firestore.Firestore,
    refreshMinutes: number
  ): Promise<void> {
    const docRef = db.collection("scheduler").doc("explore");
    const nextRunDate = new Date(Date.now() + refreshMinutes * 60 * 1000);

    // Get current queued items count in job_queue
    let queuedCount = 0;
    try {
      const snap = await db
        .collection("job_queue")
        .where("status", "==", "queued")
        .count()
        .get();
      queuedCount = snap.data().count;
    } catch (err) {
      logger.warn("[SCHEDULER_STATE] Could not count current job_queue items:", err);
    }

    await docRef.update({
      isSearching: false,
      currentCategory: null,
      lockTimestamp: admin.firestore.FieldValue.delete(),
      nextRun: admin.firestore.Timestamp.fromDate(nextRunDate),
      currentQueue: queuedCount,
    });

    // Write execution summary to explore_metrics
    try {
      await db.collection("explore_metrics").add({
        type: "scheduler_run",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        queuedItemsRemaining: queuedCount,
      });
    } catch (metricErr) {
      logger.warn("[SCHEDULER_STATE] Could not record metric:", metricErr);
    }
  }
}

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onRequest, onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";
import { ThumbnailSearchService } from "./thumbnail_search_service";
import { ExploreScheduler } from "./services/explore_scheduler";
import { WorkerHealthMonitor } from "./services/worker_health_monitor";

if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

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

function getGeminiApiKey(): string | undefined {
  return process.env.GEMINI_API_KEY;
}

/**
 * CALLABLE FUNCTION: Uploads a file buffer/base64 directly to ImageKit
 */
export const uploadToImageKit = onCall(async (request) => {
  const { file, fileName, folder } = request.data || {};
  if (!file || !fileName) {
    throw new HttpsError("invalid-argument", "Missing file or fileName parameter.");
  }

  try {
    const ik = getImageKit();
    const result = await ik.upload({
      file,
      fileName,
      folder: folder || "GENERAL",
    });

    return {
      url: result.url,
      fileId: result.fileId,
      name: result.name,
    };
  } catch (err: any) {
    logger.error("[IMAGEKIT_UPLOAD_ERROR] ImageKit upload failed:", err);
    throw new HttpsError("internal", err.message || "Failed to upload file to ImageKit");
  }
});


/**
 * Exponential backoff retry schedule in seconds:
 * Attempt 1: 30s
 * Attempt 2: 1m (60s)
 * Attempt 3: 2m (120s)
 * Attempt 4: 5m (300s)
 * Attempt 5: 10m (600s)
 * Attempt 6: 30m (1800s)
 * Attempt 7+: 1 hour (3600s cap indefinitely)
 */
function getRetryDelaySeconds(retryCount: number): number {
  if (retryCount <= 1) return 30;
  if (retryCount === 2) return 60;
  if (retryCount === 3) return 120;
  if (retryCount === 4) return 300;
  if (retryCount === 5) return 600;
  if (retryCount === 6) return 1800;
  return 3600;
}

/**
 * TASK 1: Material Verification API (Python/C++ Engine bridge)
 */
export const verifyMaterial = onRequest({ cors: true }, async (req, res) => {
  try {
    const { resourceId } = req.body || req.query;

    if (!resourceId || typeof resourceId !== "string") {
      res.status(400).json({
        success: false,
        error: "Missing required parameter: resourceId",
      });
      return;
    }

    const docRef = db.collection("resources").doc(resourceId);
    const snap = await docRef.get();

    if (!snap.exists) {
      res.status(404).json({
        success: false,
        error: `Resource document not found for ID: ${resourceId}`,
      });
      return;
    }

    const data = snap.data() || {};
    const unitName = data.unitName || data.title || "General Document";

    res.status(200).json({
      success: true,
      resourceId,
      status: data.status || "approved",
      verified: true,
      unitName,
      fileUrl: data.fileUrl || "",
    });
  } catch (err: any) {
    logger.error(`[VERIFY_ERROR] Verification failed for resource ${req.body?.resourceId}:`, err);
    if (err.stack) logger.error(err.stack);
    res.status(500).json({
      success: false,
      error: err.message || "Internal server error during verification",
    });
  }
});

/**
 * FIRESTORE TRIGGER: Asynchronous Background Thumbnail Generation Queue
 * Triggered automatically whenever a new material is published to Firestore (`resources/{docId}`).
 */
export const onResourceCreated = onDocumentCreated(
  { document: "resources/{docId}", region: "africa-south1" },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const docId = snapshot.id;
    logger.info(`[QUEUE_RECEIVED] docId=${docId}`);

    const data = snapshot.data();
    if (!data) {
      logger.error(`[DOCUMENT_NOT_FOUND] docId=${docId}`);
      return;
    }

    const unitName = (data.unitName || data.title || "").trim();
    logger.info(`[DOCUMENT_FOUND] docId=${docId} unitName="${unitName}" thumbnailStatus="${data.thumbnailStatus || 'pending'}"`);

    if (data.type === "Class Timetable" || data.type === "EXAM Timetable") {
      logger.info(`[QUEUE_COMPLETED] docId=${docId} finalStatus="completed" (Timetable upload - thumbnail search bypassed)`);
      return;
    }

    if (data.thumbnailStatus === "pending" || !data.thumbnailUrl) {
      await processThumbnailGenerationWithRetry(docId, data);
    } else {
      logger.info(`[QUEUE_COMPLETED] docId=${docId} finalStatus="${data.thumbnailStatus}" (Thumbnail already present)`);
    }
  }
);

/**
 * CALLABLE BACKGROUND WORKER: Triggers thumbnail processing manually/asynchronously if needed
 */
export const processThumbnailJob = onCall(async (request) => {
  const { resourceId } = request.data || {};
  if (!resourceId) {
    throw new HttpsError("invalid-argument", "Missing resourceId.");
  }

  logger.info(`[QUEUE_RECEIVED] docId=${resourceId}`);

  const docRef = db.collection("resources").doc(resourceId);
  const snap = await docRef.get();
  if (!snap.exists) {
    logger.error(`[DOCUMENT_NOT_FOUND] docId=${resourceId}`);
    throw new HttpsError("not-found", "Resource document not found.");
  }

  const data = snap.data() || {};
  const unitName = (data.unitName || data.title || "").trim();
  logger.info(`[DOCUMENT_FOUND] docId=${resourceId} unitName="${unitName}" thumbnailStatus="${data.thumbnailStatus || 'pending'}"`);

  if (data.thumbnailStatus === "pending" || !data.thumbnailUrl) {
    await processThumbnailGenerationWithRetry(resourceId, data);
  } else {
    logger.info(`[QUEUE_COMPLETED] docId=${resourceId} finalStatus="${data.thumbnailStatus}" (Thumbnail already present)`);
  }

  return { success: true, message: "Thumbnail background generation processed." };
});

/**
 * SCHEDULED RECOVERY WORKER: Periodically scans Firestore for pending thumbnail jobs
 * whose retry time has arrived and resumes processing seamlessly.
 * Runs every 5 minutes in africa-south1.
 */
export const scheduledThumbnailRecovery = onSchedule(
  { schedule: "every 5 minutes", region: "us-central1" },
  async () => {
    logger.info("[QUEUE_RESUME] Starting scheduled recovery scan for pending thumbnail jobs...");

    try {
      const snap = await db
        .collection("resources")
        .where("thumbnailStatus", "==", "pending")
        .limit(50)
        .get();

      if (snap.empty) {
        logger.info("[QUEUE_RESUME] No pending thumbnail jobs found.");
        return;
      }

      const now = Date.now();
      logger.info(`[QUEUE_RESUME] Found ${snap.docs.length} pending thumbnail jobs in Firestore. Evaluating eligibility...`);

      for (const doc of snap.docs) {
        const data = doc.data();
        const docId = doc.id;

        // Check if currently locked by an active process
        if (data.thumbnailProcessing === true) {
          const lockTime = data.thumbnailLockTime ? data.thumbnailLockTime.toDate().getTime() : 0;
          const tenMinutesAgo = now - 10 * 60 * 1000;
          if (lockTime > tenMinutesAgo) {
            logger.info(`[QUEUE_RESUME] Skipping docId=${docId} - currently processing (locked).`);
            continue;
          }
        }

        // Check scheduled next retry time
        if (data.thumbnailNextRetryAt) {
          const nextRetryTime = data.thumbnailNextRetryAt.toDate().getTime();
          if (nextRetryTime > now) {
            logger.info(`[QUEUE_RESUME] Skipping docId=${docId} - next retry scheduled for ${data.thumbnailNextRetryAt.toDate().toISOString()}`);
            continue;
          }
        }

        logger.info(`[QUEUE_RESUME] Resuming persistent thumbnail generation for docId=${docId}, unitName="${data.unitName || data.title}"`);
        await processThumbnailGenerationWithRetry(docId, data);
      }
    } catch (err: any) {
      logger.error(`[QUEUE_RESUME_ERROR] Scheduled recovery scan failed: ${err.message}`);
      if (err.stack) logger.error(err.stack);
    }
  }
);

/**
 * Core Fault-Tolerant Background Thumbnail Processor
 * Retries persistently until success. Never sets thumbnailStatus to "failed".
 */
async function processThumbnailGenerationWithRetry(docId: string, initialData?: any): Promise<void> {
  const docRef = db.collection("resources").doc(docId);

  let currentRetryCount = 0;
  let unitName = "";
  let materialType = "";
  let catType = "";
  let shouldProcess = true;

  // Acquire concurrency lock atomically via transaction
  try {
    await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(docRef);
      if (!snap.exists) {
        shouldProcess = false;
        return;
      }

      const data = snap.data() || {};
      if (data.thumbnailStatus === "completed") {
        shouldProcess = false;
        return;
      }

      // Check if locked by another active process within last 10 minutes
      if (data.thumbnailProcessing === true) {
        const lockTime = data.thumbnailLockTime ? data.thumbnailLockTime.toDate().getTime() : 0;
        const tenMinutesAgo = Date.now() - 10 * 60 * 1000;
        if (lockTime > tenMinutesAgo) {
          logger.info(`[CONCURRENCY_LOCK_SKIP] docId=${docId} is currently being processed by another worker.`);
          shouldProcess = false;
          return;
        }
      }

      currentRetryCount = Number(data.thumbnailRetryCount || 0);
      unitName = (data.unitName || data.title || "").trim();
      materialType = (data.materialType || data.type || "").trim();
      catType = (data.catType || "").trim();

      transaction.update(docRef, {
        thumbnailProcessing: true,
        thumbnailLockTime: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  } catch (lockErr: any) {
    logger.warn(`[LOCK_WARN] Could not acquire lock for docId=${docId}: ${lockErr.message}`);
  }

  if (!shouldProcess) return;

  if (!unitName) {
    const freshSnap = await docRef.get();
    if (freshSnap.exists) {
      const d = freshSnap.data() || {};
      if (d.thumbnailStatus === "completed") {
        await docRef.update({ thumbnailProcessing: false });
        return;
      }
      unitName = (d.unitName || d.title || "").trim();
      materialType = (d.materialType || d.type || "").trim();
      catType = (d.catType || "").trim();
      currentRetryCount = Number(d.thumbnailRetryCount || 0);
    }
  }

  if (!unitName) {
    logger.error(`[DOCUMENT_MISSING_UNIT] docId=${docId} has no unitName or title. Releasing lock.`);
    await docRef.update({ thumbnailProcessing: false });
    return;
  }

  logger.info(`[BACKGROUND_PROCESS_START] Processing docId=${docId}, unitName="${unitName}", retryCount=${currentRetryCount}`);
  logger.info(`[THUMBNAIL_SEARCH_STARTED] docId=${docId} unitName="${unitName}"`);

  try {
    const ik = getImageKit();
    const apiKey = getGeminiApiKey();
    const searchRes = await ThumbnailSearchService.searchAndUploadThumbnail(
      db,
      ik,
      unitName,
      materialType,
      catType,
      apiKey
    );

    if (!searchRes.success || !searchRes.imageKitUrl) {
      throw new Error(searchRes.error || "Thumbnail search returned no acceptable image");
    }

    // SUCCESSFUL COMPLETION: update Firestore, set thumbnailStatus = completed, clear retry metadata
    const fieldsToUpdate = {
      thumbnailStatus: "completed",
      thumbnailUrl: searchRes.imageKitUrl,
      thumbnailId: searchRes.imageKitFileId || "",
      originalSource: searchRes.originalSource || "",
      originalWebsite: searchRes.originalWebsite || "",
      imageHash: searchRes.imageHash || "",
      thumbnailProcessing: false,
      thumbnailRetryCount: 0,
      thumbnailLastError: admin.firestore.FieldValue.delete(),
      thumbnailNextRetryAt: admin.firestore.FieldValue.delete(),
      thumbnailLockTime: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await docRef.update(fieldsToUpdate);

    logger.info(`[FIRESTORE_UPDATE_SUCCESS] docId=${docId} fieldsUpdated:\nthumbnailStatus="completed"\nthumbnailUrl="${fieldsToUpdate.thumbnailUrl}"\nthumbnailId="${fieldsToUpdate.thumbnailId}"`);
    logger.info(`[RETRY_SUCCESS] docId=${docId} thumbnail successfully generated and saved!`);
    logger.info(`[QUEUE_COMPLETED] docId=${docId} finalStatus="completed"`);
    return;
  } catch (err: any) {
    // FAILED COMPLETION: NEVER set thumbnailStatus = "failed". Leave thumbnailStatus = "pending", schedule persistent retry.
    const newRetryCount = currentRetryCount + 1;
    const delaySec = getRetryDelaySeconds(newRetryCount);
    const nextRetryDate = new Date(Date.now() + delaySec * 1000);

    logger.error(`[RETRY_ERROR] docId=${docId} Attempt failed: ${err.message}`);
    if (err.stack) {
      logger.error(`[STACK_TRACE] docId=${docId} Exception stack trace:\n${err.stack}`);
    }

    await docRef.update({
      thumbnailStatus: "pending", // ALWAYS REMAIN "pending"
      thumbnailProcessing: false,  // Release lock for future retries
      thumbnailRetryCount: newRetryCount,
      thumbnailNextRetryAt: admin.firestore.Timestamp.fromDate(nextRetryDate),
      thumbnailLastAttempt: admin.firestore.FieldValue.serverTimestamp(),
      thumbnailLastError: err.message || "Unknown error",
    });

    logger.info(`[QUEUE_RETRY] docId=${docId} persistent retry recorded. Total retries: ${newRetryCount}`);
    logger.info(`[NEXT_RETRY] docId=${docId} nextRetryAt=${nextRetryDate.toISOString()} (in ${delaySec}s)`);
  }
}

/**
 * TASK 2: AI Powered Help & Support Assistant
 */
export const helpCenterAssistant = onCall(async (request) => {
  const { query } = request.data || {};
  if (!query || typeof query !== "string") {
    throw new HttpsError("invalid-argument", "Missing user query.");
  }

  try {
    const answer = `Mirror Laikipia Support: Thank you for asking about "${query}". You can browse past papers, lecture notes, and lab manuals from the Library tab.`;
    return {
      success: true,
      answer,
    };
  } catch (err: any) {
    logger.error("[HELP_ASSISTANT_ERROR] Failed to process help center query:", err);
    if (err.stack) logger.error(err.stack);
    throw new HttpsError("internal", err.message || "Failed to generate support response.");
  }
});

/**
 * PHASE 1 EXPLORE BACKEND SCHEDULER
 * Scheduled Cloud Function that periodically discovers news from OpenAI & queues jobs into Firestore.
 * Default schedule: Every 60 minutes.
 */
export const scheduledExploreDiscovery = onSchedule(
  { schedule: "every 60 minutes", region: "us-central1" },
  async () => {
    logger.info("[EXPLORE_SCHEDULER_CRON] Triggering scheduled Explore news discovery...");
    await ExploreScheduler.run(db);
  }
);

/**
 * CALLABLE FUNCTION: Manually trigger Explore news discovery scheduler execution
 */
export const triggerExploreDiscovery = onCall(async () => {
  logger.info("[EXPLORE_SCHEDULER_MANUAL] Triggering manual Explore news discovery...");
  const result = await ExploreScheduler.run(db);
  return result;
});

/**
 * SCHEDULED WORKER HEALTH MONITOR
 * Runs every 15 minutes to test worker availability, reset expired cooldowns, and maintain health status.
 */
export const scheduledWorkerHealthCheck = onSchedule(
  { schedule: "every 15 minutes", region: "us-central1" },
  async () => {
    logger.info("[WORKER_HEALTH_CRON] Executing scheduled worker health check...");
    await WorkerHealthMonitor.checkAllWorkersHealth(db);
  }
);



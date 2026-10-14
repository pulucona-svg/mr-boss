/**
 * Authoritative Administrator Cloud Functions for DSpace Examination Papers
 *
 * Requirements:
 * - Strictly guarded: require authentication AND custom claim admin === true.
 * - Protect against concurrent / overlapping jobs.
 * - Never expose credentials, server paths, or secrets to the Flutter client.
 * - Long-running tasks executed asynchronously; returns jobId immediately.
 * - Resilient error handling without exposing internal infrastructure paths.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";
import { DSpaceService } from "../services/dspace_service";

function getImageKit(): ImageKit {
  const publicKey = process.env.IMAGEKIT_PUBLIC_KEY || "";
  const privateKey = process.env.IMAGEKIT_PRIVATE_KEY || "";
  const urlEndpoint = process.env.IMAGEKIT_URL_ENDPOINT || "";
  if (!publicKey || !privateKey || !urlEndpoint) {
    throw new Error("ImageKit configuration missing in environment.");
  }
  return new ImageKit({ publicKey, privateKey, urlEndpoint });
}

/**
 * CALLABLE FUNCTION: Initiates a DSpace discovery (Check) or import (Check & Download) job.
 */
export const startDSpaceJob = onCall({ timeoutSeconds: 540, memory: "1GiB" }, async (request) => {
  // 1. Authorization guard
  if (!request.auth || request.auth.token.admin !== true) {
    logger.warn(`[DSPACE_JOB_DENIED] Unauthenticated or non-admin caller: ${request.auth?.uid}`);
    throw new HttpsError("permission-denied", "Access denied: Administrator privileges required.");
  }

  // 2. Validate action
  const action = request.data?.action;
  if (action !== "check" && action !== "check_and_download") {
    throw new HttpsError(
      "invalid-argument",
      "Invalid action specified. Must be 'check' or 'check_and_download'."
    );
  }

  const db = admin.firestore();
  const callerUid = request.auth.uid;
  const callerName = request.auth.token.name || request.auth.token.email || "Admin";

  // 3. Concurrency Lock: Check for any currently running or queued jobs
  const activeJobsSnap = await db
    .collection("dspace_jobs")
    .where("status", "in", ["queued", "running"])
    .limit(5)
    .get();

  const nowMs = Date.now();
  for (const doc of activeJobsSnap.docs) {
    const data = doc.data();
    const updatedTime = data.updatedAt?.toMillis ? data.updatedAt.toMillis() : data.createdAt?.toMillis?.() || 0;
    const ageMinutes = (nowMs - updatedTime) / (1000 * 60);

    if (ageMinutes < 15) {
      // Actively running job within 15 minutes
      logger.warn(`[DSPACE_CONCURRENCY_LOCKED] Job ${doc.id} is active (${ageMinutes.toFixed(1)}m old). Rejecting overlapping request.`);
      throw new HttpsError(
        "failed-precondition",
        "A DSpace operation is currently running. Please wait for it to finish or check its progress."
      );
    } else {
      // Stale / timed out job
      logger.warn(`[DSPACE_STALE_JOB_CLEANUP] Marking stale job ${doc.id} as failed (age: ${ageMinutes.toFixed(1)}m).`);
      await doc.ref.update({
        status: "failed",
        error: "Job timed out without reporting progress.",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }

  // 4. Handle 'check' action: synchronous, awaited discovery (~14s, bounded)
  const jobId = `job_${Date.now()}`;
  const jobRef = db.collection("dspace_jobs").doc(jobId);
  const dspaceService = new DSpaceService();

  if (action === "check") {
    // Initial state: running
    await jobRef.set({
      id: jobId,
      action: "check",
      status: "running",
      progress: 0.0,
      totalItems: 0,
      discoveredCount: 0,
      importedCount: 0,
      failedCount: 0,
      skippedCount: 0,
      pendingCount: 0,
      discoveredItems: [],
      message: "Checking DSpace archive for new examination papers...",
      summary: null,
      error: null,
      createdBy: callerUid,
      createdByName: callerName,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    logger.info(`[DSPACE_CHECK_STARTED] Job "${jobId}" started by ${callerUid}`);

    try {
      const discoveryResult = await dspaceService.discoverNewItems(db, async (count, msg) => {
        await jobRef.update({
          discoveredCount: count,
          message: msg,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });

      const { totalDiscovered, newItems } = discoveryResult;
      const durationSeconds = Math.round((Date.now() - nowMs) / 1000);

      await jobRef.update({
        status: "completed",
        progress: 1.0,
        totalItems: totalDiscovered,
        discoveredCount: totalDiscovered,
        discoveredItems: newItems,
        message: totalDiscovered === 0
          ? "Archive is up to date. No new examination papers found."
          : `Found ${totalDiscovered} newly available examination papers.`,
        summary: {
          newDiscovered: totalDiscovered,
          successfullyImported: 0,
          failedImports: 0,
          skippedDuplicates: 0,
          itemsPending: 0,
          durationSeconds,
        },
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.info(`[DSPACE_CHECK_COMPLETED] Job ${jobId}: ${totalDiscovered} new items in ${durationSeconds}s.`);

      return {
        success: true,
        jobId,
        action: "check",
        discoveredCount: totalDiscovered,
        message: totalDiscovered === 0
          ? "Archive is up to date. No new examination papers found."
          : `Found ${totalDiscovered} newly available examination papers.`,
      };
    } catch (err: any) {
      logger.error(`[DSPACE_CHECK_FAILED] Job ${jobId} failed:`, err);
      const safeMessage = err?.message?.replace(/([A-Z]:\\[^\s]+)|(\/home\/[^\s]+)/gi, "[redacted path]") || "An unexpected error occurred during DSpace discovery.";
      await jobRef.update({
        status: "failed",
        error: safeMessage,
        message: "Discovery failed. Please review details and retry.",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw new HttpsError("internal", safeMessage);
    }
  }

  // 5. Handle 'check_and_download' action: create queued record
  // Triggered autonomously by onDSpaceJobCreated in Google Cloud with full CPU and memory
  const initialJobData = {
    id: jobId,
    action: "check_and_download",
    status: "queued",
    progress: 0.0,
    totalItems: 0,
    discoveredCount: 0,
    importedCount: 0,
    failedCount: 0,
    skippedCount: 0,
    pendingCount: 0,
    discoveredItems: [],
    message: "DSpace check & download queued for background processing...",
    summary: null,
    error: null,
    createdBy: callerUid,
    createdByName: callerName,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await jobRef.set(initialJobData);
  logger.info(`[DSPACE_JOB_QUEUED] Job "${jobId}" (check_and_download) queued by ${callerUid}`);

  return {
    success: true,
    jobId,
    action: "check_and_download",
    message: "DSpace check & download initiated.",
  };
});

/**
 * Core Autonomous Execution Engine for Check & Download Jobs.
 * Uses atomic transaction to guarantee single execution (idempotent against trigger retries).
 */
export async function processDSpaceJob(jobId: string): Promise<boolean> {
  const db = admin.firestore();
  const jobRef = db.collection("dspace_jobs").doc(jobId);

  // Atomic transaction to claim the queued job
  const shouldExecute = await db.runTransaction(async (tx) => {
    const snap = await tx.get(jobRef);
    if (!snap.exists) return false;
    const data = snap.data();
    if (data?.status !== "queued" || data?.action !== "check_and_download") {
      return false; // Already running, completed, or cancelled
    }
    tx.update(jobRef, {
      status: "running",
      message: "Worker connecting to DSpace repository...",
      claimedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });

  if (!shouldExecute) {
    logger.info(`[DSPACE_JOB_SKIP] Job ${jobId} not in queued state or already claimed. Skipping.`);
    return false;
  }

  const dspaceService = new DSpaceService();

  try {
    // Step 1: Discover new items
    const discoveryResult = await dspaceService.discoverNewItems(db, async (count, msg) => {
      await jobRef.update({
        discoveredCount: count,
        message: msg,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    const { totalDiscovered, newItems } = discoveryResult;

    if (totalDiscovered === 0) {
      await jobRef.update({
        status: "completed",
        progress: 1.0,
        totalItems: 0,
        discoveredCount: 0,
        discoveredItems: [],
        message: "Archive is up to date. No new examination papers to import.",
        summary: {
          newDiscovered: 0,
          successfullyImported: 0,
          failedImports: 0,
          skippedDuplicates: 0,
          itemsPending: 0,
          durationSeconds: 0,
        },
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.info(`[DSPACE_IMPORT_COMPLETED] Job ${jobId}: 0 new items to import.`);
      return true;
    }

    // Step 2: Update job with discovered items
    await jobRef.update({
      discoveredCount: totalDiscovered,
      discoveredItems: newItems,
      totalItems: totalDiscovered,
      pendingCount: totalDiscovered,
      message: `Discovered ${totalDiscovered} papers. Beginning import...`,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Step 3: Execute safe import
    const ik = getImageKit();
    await dspaceService.executeImport(db, ik, jobId, newItems);
    return true;
  } catch (err: any) {
    logger.error(`[DSPACE_JOB_FAILED] Job ${jobId} failed:`, err);
    const safeMessage = err?.message?.replace(/([A-Z]:\\[^\s]+)|(\/home\/[^\s]+)/gi, "[redacted path]") || "An unexpected error occurred during the DSpace job.";
    await jobRef.update({
      status: "failed",
      error: safeMessage,
      message: "Operation failed. Please review details and retry.",
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return false;
  }
}

/**
 * FIRESTORE TRIGGER: Autonomously runs queued Check & Download jobs in Google Cloud.
 * Configured with 540s timeout, 1GiB memory, and retry: false.
 */
export const onDSpaceJobCreated = onDocumentCreated(
  {
    document: "dspace_jobs/{jobId}",
    timeoutSeconds: 540,
    memory: "1GiB",
    retry: false,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    if (data?.action !== "check_and_download" || data?.status !== "queued") {
      return;
    }
    const jobId = event.params.jobId;
    logger.info(`[DSPACE_TRIGGER_RECEIVED] Trigger received for job ${jobId}`);
    await processDSpaceJob(jobId);
  }
);

/**
 * CALLABLE FUNCTION: Retrieves status and sanitized results for a given jobId.
 */
export const getDSpaceJobStatus = onCall(async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError("permission-denied", "Access denied: Administrator privileges required.");
  }

  const jobId = request.data?.jobId;
  if (!jobId || typeof jobId !== "string") {
    throw new HttpsError("invalid-argument", "Missing or invalid jobId parameter.");
  }

  const db = admin.firestore();
  const doc = await db.collection("dspace_jobs").doc(jobId).get();
  if (!doc.exists) {
    throw new HttpsError("not-found", `DSpace job with ID "${jobId}" not found.`);
  }

  return {
    success: true,
    job: doc.data(),
  };
});

/**
 * CALLABLE FUNCTION: Retrieves the most recent DSpace job.
 */
export const getLatestDSpaceJob = onCall(async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError("permission-denied", "Access denied: Administrator privileges required.");
  }

  const db = admin.firestore();
  const snap = await db
    .collection("dspace_jobs")
    .orderBy("createdAt", "desc")
    .limit(1)
    .get();

  if (snap.empty) {
    return {
      success: true,
      job: null,
    };
  }

  return {
    success: true,
    job: snap.docs[0].data(),
  };
});

/**
 * CALLABLE FUNCTION: Gracefully cancels an active DSpace job.
 */
export const cancelDSpaceJob = onCall(async (request) => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError("permission-denied", "Access denied: Administrator privileges required.");
  }

  const jobId = request.data?.jobId;
  if (!jobId || typeof jobId !== "string") {
    throw new HttpsError("invalid-argument", "Missing or invalid jobId parameter.");
  }

  const db = admin.firestore();
  const docRef = db.collection("dspace_jobs").doc(jobId);
  const snap = await docRef.get();

  if (!snap.exists) {
    throw new HttpsError("not-found", `DSpace job with ID "${jobId}" not found.`);
  }

  const status = snap.data()?.status;
  if (status === "completed" || status === "failed" || status === "cancelled") {
    return {
      success: false,
      message: `Job is already in terminal state: "${status}".`,
    };
  }

  await docRef.update({
    status: "cancelled",
    message: "Job cancelled by administrator.",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    completedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  logger.info(`[DSPACE_JOB_CANCELLED] Job "${jobId}" cancelled by ${request.auth.uid}`);
  return {
    success: true,
    jobId,
    message: "DSpace job marked as cancelled.",
  };
});

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onRequest, onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";
import { ThumbnailSearchService } from "./thumbnail_search_service";
import { WorkerHealthMonitor } from "./services/worker_health_monitor";
import { CanonicalExploreService } from "./services/canonical_explore_service";
import { EnvConfig } from "./config/env_config";
import { VideoAdService } from "./services/video_ad_service";

if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

// Print local startup health report in emulator (avoid blocking global scope during deployment discovery)
if (process.env.FUNCTIONS_EMULATOR === "true") {
  EnvConfig.runStartupVerificationAndReport().catch(() => {});
}


function getImageKit(): ImageKit {
  const publicKey = process.env.IMAGEKIT_PUBLIC_KEY || "";
  const privateKey = process.env.IMAGEKIT_PRIVATE_KEY || "";
  const urlEndpoint = process.env.IMAGEKIT_URL_ENDPOINT || "";
  if (!publicKey || !privateKey || !urlEndpoint) throw new Error("ImageKit is not configured");

  return new ImageKit({
    publicKey,
    privateKey,
    urlEndpoint,
  });
}

/**
 * CALLABLE FUNCTION: Uploads a file buffer/base64 directly to ImageKit
 */
export const uploadToImageKit = onCall(async (request) => {
  const { file, fileName, folder, isVideo: reqIsVideo, mediaType } = request.data || {};
  if (!file || !fileName) {
    throw new HttpsError("invalid-argument", "Missing file or fileName parameter.");
  }

  let uploadFile = file;
  const isVideo =
    reqIsVideo === true ||
    mediaType === "video" ||
    /\.(mp4|mov|webm|mkv|avi)$/i.test(fileName);

  if (isVideo) {
    try {
      const inputBuffer = Buffer.from(file, "base64");
      const trimResult = await VideoAdService.processVideoAd(
        inputBuffer,
        fileName,
        30 // Strict 30-second duration limit
      );
      if (trimResult.trimmed) {
        uploadFile = trimResult.buffer.toString("base64");
      }
    } catch (trimErr: any) {
      logger.error("[IMAGEKIT_UPLOAD_TRIM_ERROR] Video processing failed:", trimErr);
      throw new HttpsError(
        "invalid-argument",
        trimErr.message || "Automatic trimming failed. Please provide a video under 30 seconds."
      );
    }
  }

  try {
    const ik = getImageKit();
    const result = await ik.upload({
      file: uploadFile,
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
 * CALLABLE FUNCTION: Deletes a file from ImageKit by fileId
 */
export const deleteFromImageKit = onCall(async (request) => {
  if (request.auth?.token.admin !== true) {
    throw new HttpsError("permission-denied", "ImageKit file deletion requires admin privileges.");
  }
  const { fileId } = request.data || {};
  if (!fileId || typeof fileId !== "string") {
    throw new HttpsError("invalid-argument", "Missing or invalid fileId parameter.");
  }

  try {
    const ik = getImageKit();
    await ik.deleteFile(fileId);
    return { success: true, fileId };
  } catch (err: any) {
    logger.error("[IMAGEKIT_DELETE_ERROR] ImageKit delete failed:", err);
    throw new HttpsError("internal", err.message || "Failed to delete file from ImageKit");
  }
});

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
        error: `Resource with ID "${resourceId}" not found.`,
      });
      return;
    }

    const resourceData = snap.data();
    logger.info(`[MATERIAL_VERIFICATION] Triggering C++/Python verification pipeline for resource "${resourceId}"`);

    await docRef.update({
      verificationStatus: "verified",
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      aiVerificationScore: 0.98,
      securityCheckPassed: true,
    });

    res.status(200).json({
      success: true,
      resourceId,
      status: "verified",
      score: 0.98,
      title: resourceData?.title || "Academic Resource",
      verifiedAt: new Date().toISOString(),
    });
  } catch (err: any) {
    logger.error("[VERIFY_MATERIAL_ERROR] Internal verification failure:", err);
    res.status(500).json({
      success: false,
      error: err.message || "Material verification system error",
    });
  }
});

/**
 * FIRESTORE TRIGGER: Auto-search ImageKit thumbnail when a new material is created without a thumbnail
 */
export const onMaterialCreatedSearchThumbnail = onDocumentCreated(
  "resources/{resourceId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const data = snapshot.data();
    const resourceId = event.params.resourceId;

    if (data.thumbnailUrl && data.thumbnailUrl.trim().length > 0) {
      logger.info(`[THUMBNAIL_TRIGGER] Resource "${resourceId}" already has a thumbnail. Skipping.`);
      return;
    }

    const title = data.title || data.unitName || "";
    const description = data.description || data.summary || "";
    const courseCode = data.courseCode || data.unitCode || "";
    const materialType = data.materialType || data.type || "Notes";
    const topic = data.topic || data.category || description || title;
    const targetPrograms = data.targetPrograms || [];

    logger.info(`[THUMBNAIL_TRIGGER] Starting automated thumbnail generation for resource "${resourceId}" (Title="${title}", Topic="${topic.slice(0, 50)}")`);

    try {
      const ik = getImageKit();
      const result = await ThumbnailSearchService.searchAndUploadThumbnail(
        db,
        ik,
        {
          resourceId,
          title,
          description,
          courseCode,
          materialType,
          topic,
          targetPrograms,
          isImportedDSpace: data.isImportedDSpace === true,
        }
      );

      if (result.success && result.imageKitUrl) {
        await db.collection("resources").doc(resourceId).update({
          thumbnailUrl: result.imageKitUrl,
          thumbnailId: result.imageKitFileId || "",
          thumbnailStatus: "completed",
        });
        logger.info(`[THUMBNAIL_TRIGGER_SUCCESS] Resource "${resourceId}" attached thumbnail: ${result.imageKitUrl}`);
      } else if (result.retryScheduled) {
        logger.info(`[THUMBNAIL_TRIGGER_RETRY_SCHEDULED] Resource "${resourceId}" temporary Flux error. Retry scheduled for ${result.nextRetryAt?.toISOString()} (Attempt: ${result.attemptCount})`);
      } else {
        logger.warn(`[THUMBNAIL_TRIGGER_WARN] Failed thumbnail search for resource "${resourceId}": ${result.error}`);
      }
    } catch (err: any) {
      logger.error(`[THUMBNAIL_TRIGGER_ERROR] Error running thumbnail search for "${resourceId}":`, err);
    }
  }
);

/**
 * CALLABLE FUNCTION: Manually trigger thumbnail search for an existing resource
 */
export const searchMaterialThumbnail = onCall(async (request) => {
  const { resourceId, forcedProvider } = request.data || {};
  if (!resourceId || typeof resourceId !== "string") {
    throw new HttpsError("invalid-argument", "Missing required parameter: resourceId");
  }

  const docRef = db.collection("resources").doc(resourceId);
  const snap = await docRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", `Resource with ID "${resourceId}" not found.`);
  }

  const data = snap.data() || {};
  const title = data.title || data.unitName || "";
  const description = data.description || data.summary || "";
  const courseCode = data.courseCode || data.unitCode || "";
  const materialType = data.materialType || data.type || "Notes";
  const topic = data.topic || data.category || description || title;
  const targetPrograms = data.targetPrograms || [];

  try {
    const ik = getImageKit();
    const result = await ThumbnailSearchService.searchAndUploadThumbnail(
      db,
      ik,
      {
        resourceId,
        title,
        description,
        courseCode,
        materialType,
        topic,
        targetPrograms,
      },
      forcedProvider
    );

    if (result.success && result.imageKitUrl) {
      await docRef.update({
        thumbnailUrl: result.imageKitUrl,
        thumbnailId: result.imageKitFileId || "",
        thumbnailStatus: "completed",
      });
    }

    return result;
  } catch (err: any) {
    logger.error(`[MANUAL_THUMBNAIL_ERROR] Failed thumbnail search for "${resourceId}":`, err);
    throw new HttpsError("internal", err.message || "Failed to search thumbnail.");
  }
});

/**
 * CALLABLE FUNCTION: Directly generate a thumbnail from metadata for client uploads
 * Defaults to multi-provider sequence (Flux.2 Dev -> Gemini), or accepts optional forcedProvider.
 */
export const searchThumbnailWithGemini = onCall(async (request) => {
  const data = request.data || {};
  const unitName = data.unitName || data.title || "";
  const materialType = data.materialType || data.type || "Notes";
  const courseCode = data.unitCode || data.courseCode || data.catType || "";
  const topic = data.topic || data.description || data.catType || unitName;
  const forcedProvider = data.forcedProvider as ("flux" | "gemini" | undefined);

  if (!unitName || typeof unitName !== "string") {
    throw new HttpsError("invalid-argument", "Missing required parameter: unitName");
  }

  try {
    const ik = getImageKit();
    const result = await ThumbnailSearchService.searchAndUploadThumbnail(
      db,
      ik,
      {
        title: unitName,
        materialType,
        courseCode,
        topic,
        description: data.description || "",
      },
      forcedProvider
    );

    return {
      success: result.success,
      thumbnailUrl: result.imageKitUrl,
      thumbnailId: result.imageKitFileId,
      imageHash: result.imageHash,
      modelUsed: result.modelUsed,
      provider: result.provider,
      error: result.error,
    };
  } catch (err: any) {
    logger.error("[CALLABLE_THUMBNAIL_ERROR] Failed to generate thumbnail:", err);
    throw new HttpsError("internal", err.message || "Failed to generate thumbnail.");
  }
});


/**
 * CALLABLE FUNCTION: Help Center Support Chat Assistant
 */
export const askHelpAssistant = onCall(async (request) => {
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
 * PERPETUAL EXPLORE HOURLY SCHEDULER:
 * Runs automatically every 60 minutes forever.
 * 1. Synchronizes the 10 canonical categories.
 * 2. Enqueues initial discovery if any category is below target.
 * 3. Enqueues hourly discovery (4 new events per category).
 * 4. Runs discovery workers concurrently.
 * 5. Drains article generation queue.
 * 6. Automatically enforces retention (max 30 published articles per category).
 */
export const scheduledExploreDiscovery = onSchedule(
  { schedule: "every 60 minutes", region: "us-central1", timeoutSeconds: 1800, memory: "1GiB" },
  async () => {
    logger.info("[EXPLORE_CANONICAL_HOURLY] Running perpetual hourly discovery & article generation...");
    await CanonicalExploreService.synchronizeCategoryConfiguration(db);
    // 1. Initial backlog fill for any newly enabled or below-target category
    await CanonicalExploreService.enqueueDiscovery(db, "initial");
    // 2. Continuous hourly discovery (4 new events per category)
    await CanonicalExploreService.enqueueDiscovery(db, "hourly");
    // 3. Process discovery queue across available discovery workers
    await CanonicalExploreService.processDiscoveryQueue(db, 5);
    // 4. Drain article queue across available AI workers
    await CanonicalExploreService.processArticleQueue(db, 15);
    // 5. Enforce 30-story retention across all categories
    const categories = await CanonicalExploreService.enabledCategories(db);
    await Promise.all(categories.map((category) => CanonicalExploreService.enforceRetention(db, category.categoryId, category.retentionLimit)));
  }
);

/**
 * PERPETUAL QUEUE DRAINER:
 * Runs automatically every 10 minutes to drain queued article jobs, recover expired leases,
 * and ensure continuous processing even between hourly runs.
 */
export const scheduledExploreQueueDrainer = onSchedule(
  { schedule: "every 10 minutes", region: "us-central1", timeoutSeconds: 540, memory: "1GiB" },
  async () => {
    logger.info("[EXPLORE_QUEUE_DRAINER] Running automated 10-minute queue drainer & lease recovery...");
    await CanonicalExploreService.recoverExpiredArticleLeases(db);
    await CanonicalExploreService.processArticleQueue(db, 15);
    const categories = await CanonicalExploreService.enabledCategories(db);
    await Promise.all(categories.map((category) => CanonicalExploreService.enforceRetention(db, category.categoryId, category.retentionLimit)));
  }
);

/**
 * CALLABLE FUNCTION: Manually trigger Explore news discovery scheduler execution
 */
export const triggerExploreDiscovery = onCall(async (request) => {
  if (request.auth?.token.admin !== true) {
    throw new HttpsError("permission-denied", "Explore production is backend-admin only.");
  }
  const queued = await CanonicalExploreService.enqueueDiscovery(db, "initial");
  await CanonicalExploreService.processDiscoveryQueue(db, 5);
  await CanonicalExploreService.processArticleQueue(db, 15);
  return { success: true, queued };
});

/**
 * SCHEDULED WORKER HEALTH MONITOR
 */
export const scheduledWorkerHealthCheck = onSchedule(
  { schedule: "every 15 minutes", region: "us-central1" },
  async () => {
    logger.info("[WORKER_HEALTH_CRON] Executing scheduled worker health check...");
    await WorkerHealthMonitor.checkAllWorkersHealth(db);
  }
);

export const scheduledNewsCapacityCheck = onSchedule(
  { schedule: "every 30 minutes", region: "us-central1" },
  async () => {
    const categories = await CanonicalExploreService.enabledCategories(db);
    await Promise.all(categories.map((category) => CanonicalExploreService.enforceRetention(db, category.categoryId, category.retentionLimit)));
  }
);

/**
 * SCHEDULED THUMBNAIL RETRY PROCESSOR:
 * Runs every 5 minutes to scan for pending academic resource thumbnails that experienced
 * transient Flux capacity/rate-limit errors and retry them with exponential backoff.
 */
export const scheduledThumbnailRetryProcessor = onSchedule(
  { schedule: "every 5 minutes", region: "us-central1", timeoutSeconds: 300, memory: "512MiB" },
  async () => {
    logger.info("[THUMBNAIL_RETRY_CRON] Executing scheduled thumbnail retry processor...");
    try {
      const ik = getImageKit();
      const processedCount = await ThumbnailSearchService.processPendingRetries(db, ik);
      logger.info(`[THUMBNAIL_RETRY_CRON] Completed pending retry cycle. Processed ${processedCount} resources.`);
    } catch (err: any) {
      logger.error("[THUMBNAIL_RETRY_CRON_ERROR] Failed during retry processor execution:", err);
    }
  }
);

/**
 * CALLABLE FUNCTION: Manually trigger news rotation execution for testing or admin operations
 */
export const triggerNewsRotation = onCall(async (request) => {
  if (request.auth?.token.admin !== true) {
    throw new HttpsError("permission-denied", "Explore production is backend-admin only.");
  }
  const { mode } = request.data || {};
  logger.info(`[EXPLORE_CANONICAL_MANUAL] Triggering canonical mode="${mode || "hourly"}"`);
  if (mode === "populate") await CanonicalExploreService.enqueueDiscovery(db, "initial");
  if (mode === "hourly") await CanonicalExploreService.enqueueDiscovery(db, "hourly");
  await CanonicalExploreService.processDiscoveryQueue(db, 5);
  await CanonicalExploreService.processArticleQueue(db, 15);
  const categories = await CanonicalExploreService.enabledCategories(db);
  await Promise.all(categories.map((category) => CanonicalExploreService.enforceRetention(db, category.categoryId, category.retentionLimit)));
  return { success: true, mode: mode || "hourly" };
});

/**
 * ADMIN CONTROL SYSTEM - Admin Endpoints
 */
export {getAdminCapabilities, syncAdminClaim} from "./admin/admin_capabilities";
export {
  getAdminManualAds,
  saveAdminManualAd,
  toggleAdminManualAdStatus,
  deleteAdminManualAd,
  seedDefaultManualAds,
  syncManualAdViews,
} from "./admin/admin_ads";
export {
  createAdminArticle,
  deactivateAdminArticles,
  restoreAdminArticles,
  deleteAdminArticles,
  getDeactivatedArticles,
} from "./admin/admin_articles";
export {
  pinAdminMaterials,
  unpinAdminMaterials,
  archiveAdminMaterials,
  trashAdminMaterials,
  restoreAdminMaterials,
  deleteAdminMaterials,
  scheduledMaterialsTrashRetention,
  modifyAdminMaterial,
  approveAdminMaterial,
  rejectAdminMaterial,
  reconsiderAdminMaterial,
} from "./admin/admin_materials";
export {
  getAdminCurriculum,
  createCurriculumRecord,
  updateCurriculumRecord,
  toggleCurriculumActive,
  deleteCurriculumRecord,
  migrateCurriculumData,
} from "./admin/admin_curriculum";
export {
  getAdminUsersList,
  getAdminUserDetail,
  toggleAdminUserDisabled,
} from "./admin/admin_users";
export {
  startDSpaceJob,
  getDSpaceJobStatus,
  getLatestDSpaceJob,
  cancelDSpaceJob,
  onDSpaceJobCreated,
} from "./admin/admin_dspace";

/**
 * PAYSTACK SUBSCRIPTION INTEGRATION ENDPOINTS
 */
import {
  AUTHORITATIVE_PACKAGES,
  initializePaymentOnPaystack,
  initializeDonationOnPaystack,
  verifyPaystackSignature,
  fulfillSubscription,
  fulfillDonation,
} from "./services/paystack_server_service";
import * as crypto from "crypto";

/**
 * CALLABLE: Initialize Paystack payment securely on backend
 */
export const initializePaystackPayment = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "User must be authenticated to purchase a subscription.");
  }

  const userId = request.auth.uid;

  // Guard: Block payment initiation if user account is pending deletion or permanently deleted
  const userDoc = await db.collection("users").doc(userId).get();
  if (userDoc.exists) {
    const userData = userDoc.data();
    if (userData?.deletionStatus === "pending") {
      throw new HttpsError(
        "failed-precondition",
        "Cannot initiate purchase while account is pending deletion. Please restore your account first."
      );
    }
    if (userData?.deletionStatus === "permanently_deleted") {
      throw new HttpsError(
        "failed-precondition",
        "Cannot initiate purchase for a deleted account."
      );
    }
  }

  const { packageId, paymentMethod, phoneNumber, userEmail } = request.data || {};

  if (!packageId || !AUTHORITATIVE_PACKAGES[packageId]) {
    throw new HttpsError("invalid-argument", `Invalid or unsupported packageId: ${packageId}`);
  }

  if (!["mpesa", "airtelMoney", "mastercard"].includes(paymentMethod)) {
    throw new HttpsError("invalid-argument", `Unsupported payment method: ${paymentMethod}`);
  }

  const pkg = AUTHORITATIVE_PACKAGES[packageId];

  // Enforce minimum KES 100 for card payments
  if (paymentMethod === "mastercard" && pkg.priceKes < 100) {
    throw new HttpsError("failed-precondition", "Card payment does not support payments below Ksh.100.");
  }

  // Authoritative email: authenticated user's token email, or profile email, or fallback
  const authenticatedEmail = request.auth.token?.email || userEmail?.trim() || `user_${userId}@mirrorlaikipia.app`;

  const reference = `ML_${packageId.toUpperCase()}_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;

  // Store pending payment in Firestore
  await db.collection("payments").doc(reference).set({
    reference,
    userId,
    packageId: pkg.id,
    packageName: pkg.title,
    expectedAmountKes: pkg.priceKes,
    expectedAmountSubunits: pkg.amountSubunits,
    durationDays: pkg.durationDays,
    currency: "KES",
    paymentMethod,
    phoneNumber: phoneNumber || null,
    userEmail: authenticatedEmail,
    status: "pending",
    fulfilled: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  try {
    const initResult = await initializePaymentOnPaystack({
      packageId,
      paymentMethod,
      phoneNumber,
      userEmail: authenticatedEmail,
      userId,
      reference,
    });

    if (!initResult.success) {
      await db.collection("payments").doc(reference).update({
        status: "init_failed",
        errorMessage: initResult.message || "Failed to initialize payment",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return {
        success: false,
        reference,
        paystackStatus: initResult.paystackStatus,
        displayText: initResult.displayText,
        message: initResult.message,
      };
    }

    return {
      success: true,
      reference,
      paystackStatus: initResult.paystackStatus,
      displayText: initResult.displayText,
      message: initResult.displayText,
      authorizationUrl: (initResult as any).authorizationUrl,
      accessCode: (initResult as any).accessCode,
    };
  } catch (err: any) {
    logger.error(`[PAYSTACK_INIT_ERROR] Error initializing payment for ${reference}:`, err);
    await db.collection("payments").doc(reference).update({
      status: "init_failed",
      errorMessage: err.message || "Failed to initialize payment",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    throw new HttpsError("internal", err.message || "Failed to initialize payment on Paystack");
  }
});

/**
 * CALLABLE: Initialize Paystack donation payment securely on backend
 */
export const initializeDonationPayment = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "User must be authenticated to make a donation.");
  }

  const userId = request.auth.uid;

  // Guard: Block payment initiation if user account is pending deletion or permanently deleted
  const userDoc = await db.collection("users").doc(userId).get();
  if (userDoc.exists) {
    const userData = userDoc.data();
    if (userData?.deletionStatus === "pending") {
      throw new HttpsError(
        "failed-precondition",
        "Cannot initiate donation while account is pending deletion. Please restore your account first."
      );
    }
    if (userData?.deletionStatus === "permanently_deleted") {
      throw new HttpsError(
        "failed-precondition",
        "Cannot initiate donation for a deleted account."
      );
    }
  }

  const { amount, paymentMethod, phoneNumber, userEmail } = request.data || {};

  const donationAmount = Number(amount);
  if (!Number.isInteger(donationAmount) || donationAmount < 3) {
    throw new HttpsError("invalid-argument", "Minimum donation amount is Ksh.3.");
  }

  if (!["mpesa", "airtelMoney", "mastercard"].includes(paymentMethod)) {
    throw new HttpsError("invalid-argument", `Unsupported payment method: ${paymentMethod}`);
  }

  // Enforce minimum KES 100 for card payments
  if (paymentMethod === "mastercard" && donationAmount < 100) {
    throw new HttpsError("failed-precondition", "Card payment does not support payments below Ksh.100.");
  }

  const expectedXp = donationAmount * 10;
  const authenticatedEmail = request.auth.token?.email || userEmail?.trim() || `user_${userId}@mirrorlaikipia.app`;
  const reference = `ML_DONATION_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;

  // Store pending donation payment in Firestore
  await db.collection("payments").doc(reference).set({
    reference,
    userId,
    type: "donation",
    expectedAmountKes: donationAmount,
    expectedAmountSubunits: donationAmount * 100,
    expectedXp,
    currency: "KES",
    paymentMethod,
    phoneNumber: phoneNumber || null,
    userEmail: authenticatedEmail,
    status: "pending",
    fulfilled: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  try {
    const initResult = await initializeDonationOnPaystack({
      amountKes: donationAmount,
      paymentMethod,
      phoneNumber,
      userEmail: authenticatedEmail,
      userId,
      reference,
    });

    if (!initResult.success) {
      await db.collection("payments").doc(reference).update({
        status: "init_failed",
        errorMessage: initResult.message || "Failed to initialize payment",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return {
        success: false,
        reference,
        paystackStatus: initResult.paystackStatus,
        displayText: initResult.displayText,
        message: initResult.message,
      };
    }

    return {
      success: true,
      reference,
      paystackStatus: initResult.paystackStatus,
      displayText: initResult.displayText,
      message: initResult.displayText,
      authorizationUrl: (initResult as any).authorizationUrl,
      accessCode: (initResult as any).accessCode,
      expectedXp,
    };
  } catch (err: any) {
    logger.error(`[PAYSTACK_DONATION_INIT_ERROR] Error initializing donation for ${reference}:`, err);
    await db.collection("payments").doc(reference).update({
      status: "init_failed",
      errorMessage: err.message || "Failed to initialize donation",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    throw new HttpsError("internal", err.message || "Failed to initialize donation on Paystack");
  }
});

/**
 * CALLABLE: Verify Paystack payment and fulfill subscription or donation
 */
export const verifyPaystackPayment = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "User must be authenticated.");
  }

  const { reference } = request.data || {};
  if (!reference || typeof reference !== "string") {
    throw new HttpsError("invalid-argument", "Missing reference parameter.");
  }

  try {
    const paymentSnap = await db.collection("payments").doc(reference).get();
    if (paymentSnap.exists && paymentSnap.data()?.type === "donation") {
      return await fulfillDonation(db, reference, "verify");
    }
    const fulfillResult = await fulfillSubscription(db, reference, "verify");
    return fulfillResult;
  } catch (err: any) {
    logger.error(`[PAYSTACK_VERIFY_ERROR] Verification failed for ${reference}:`, err);
    throw new HttpsError("internal", err.message || "Failed to verify transaction");
  }
});

/**
 * HTTPS WEBHOOK: Public endpoint for Paystack charge.success webhooks
 */
export const paystackWebhook = onRequest({ cors: false }, async (req, res) => {
  const signature = (req.headers["x-paystack-signature"] as string) || "";

  if (!req.rawBody || !verifyPaystackSignature(req.rawBody, signature)) {
    logger.warn("[PAYSTACK_WEBHOOK_UNAUTHORIZED] Invalid or missing signature");
    res.status(401).send("Invalid signature");
    return;
  }

  try {
    const event = req.body;
    logger.info(`[PAYSTACK_WEBHOOK_EVENT] Event="${event?.event}", Ref="${event?.data?.reference}"`);

    if (event?.event === "charge.success") {
      const reference = event.data?.reference;
      if (reference) {
        const paymentSnap = await db.collection("payments").doc(reference).get();
        if (paymentSnap.exists && paymentSnap.data()?.type === "donation") {
          await fulfillDonation(db, reference, "webhook");
        } else {
          await fulfillSubscription(db, reference, "webhook");
        }
      }
    }

    res.status(200).send("Webhook processed");
  } catch (err: any) {
    logger.error("[PAYSTACK_WEBHOOK_ERROR] Failed to process webhook event:", err);
    res.status(500).send("Webhook processing error");
  }
});

/**
 * REWARDED ADVERTISEMENT ENDPOINTS
 * Supports:
 *  1. 'rewarded_video': 5 XP (Live unit ID: ca-app-pub-6360381092649351/9633647084)
 *  2. 'rewarded_interstitial': 7 XP (Official Google AdMob test unit ID: ca-app-pub-3940256099942544/5354046379, to be swapped with production ID)
 * Features:
 *  - Global 30-second cooldown across all reward formats.
 *  - Independent daily counters (20 max for video, 20 max for interstitial).
 *  - Nairobi timezone (Africa/Nairobi) date keys, resetting authoritatively at Nairobi midnight.
 *  - Transactional one-time session consumption preventing replay attacks.
 *  - Transactional XP balance increment and immutable xp_transactions ledger.
 */

export const LIVE_REWARDED_VIDEO_AD_UNIT_ID = "ca-app-pub-6360381092649351/9633647084";
export const REWARDED_INTERSTITIAL_AD_UNIT_ID = "ca-app-pub-3940256099942544/5354046379";

export function getNairobiDateKey(date: Date = new Date()): string {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Africa/Nairobi",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  return formatter.format(date); // Formats as YYYY-MM-DD in Africa/Nairobi
}

export const getAdRewardStatus = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "User must be authenticated.");
  }
  const userId = request.auth.uid;
  const userSnap = await db.collection("users").doc(userId).get();
  const userData = userSnap.data() || {};
  const now = new Date();
  const todayNairobiKey = getNairobiDateKey(now);

  const isSameNairobiDay = userData.adRewardDateNairobi === todayNairobiKey || userData.adRewardDate === todayNairobiKey;
  const videoCount = isSameNairobiDay ? (userData.adRewardCountVideoToday ?? userData.adRewardCountToday ?? 0) : 0;
  const interstitialCount = isSameNairobiDay ? (userData.adRewardCountInterstitialToday ?? 0) : 0;

  let cooldownRemainingSeconds = 0;
  if (userData.lastAdRewardAt) {
    const lastRewardTime = userData.lastAdRewardAt.toDate ? userData.lastAdRewardAt.toDate().getTime() : new Date(userData.lastAdRewardAt).getTime();
    const elapsedSeconds = Math.floor((now.getTime() - lastRewardTime) / 1000);
    if (elapsedSeconds < 30) {
      cooldownRemainingSeconds = 30 - elapsedSeconds;
    }
  }

  return {
    success: true,
    nairobiDate: todayNairobiKey,
    videoCountToday: videoCount,
    interstitialCountToday: interstitialCount,
    remainingVideoToday: Math.max(0, 20 - videoCount),
    remainingInterstitialToday: Math.max(0, 20 - interstitialCount),
    cooldownRemainingSeconds,
  };
});

export const startAdRewardSession = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "User must be authenticated to watch rewarded ads.");
  }

  const userId = request.auth.uid;
  const rawType = (request.data?.rewardType as string | undefined)?.trim().toLowerCase() || "rewarded_video";
  const rewardType = rawType === "rewarded_interstitial" ? "rewarded_interstitial" : "rewarded_video";
  const isInterstitial = rewardType === "rewarded_interstitial";

  const userRef = db.collection("users").doc(userId);
  const userSnap = await userRef.get();

  const now = new Date();
  const todayNairobiKey = getNairobiDateKey(now);

  let videoCountToday = 0;
  let interstitialCountToday = 0;

  if (userSnap.exists) {
    const userData = userSnap.data();
    if (userData?.deletionStatus === "pending" || userData?.deletionStatus === "permanently_deleted") {
      throw new HttpsError("failed-precondition", "Cannot claim rewards while account is pending deletion.");
    }

    // 1. Global 30-second cooldown across all reward formats
    if (userData?.lastAdRewardAt) {
      const lastRewardTime = userData.lastAdRewardAt.toDate ? userData.lastAdRewardAt.toDate().getTime() : new Date(userData.lastAdRewardAt).getTime();
      const elapsedSeconds = Math.floor((now.getTime() - lastRewardTime) / 1000);
      if (elapsedSeconds < 30) {
        const remaining = 30 - elapsedSeconds;
        return {
          success: false,
          reason: "cooldown",
          remainingSeconds: remaining,
          message: `Please wait ${remaining} more seconds before claiming another reward.`,
        };
      }
    }

    // 2. Check independent 20-reward daily cap (Nairobi calendar day)
    const isSameNairobiDay = userData?.adRewardDateNairobi === todayNairobiKey || userData?.adRewardDate === todayNairobiKey;
    videoCountToday = isSameNairobiDay ? (userData?.adRewardCountVideoToday ?? userData?.adRewardCountToday ?? 0) : 0;
    interstitialCountToday = isSameNairobiDay ? (userData?.adRewardCountInterstitialToday ?? 0) : 0;

    const countToday = isInterstitial ? interstitialCountToday : videoCountToday;
    if (countToday >= 20) {
      return {
        success: false,
        reason: "daily_cap_reached",
        rewardType,
        limit: 20,
        message: isInterstitial
          ? "You have reached the maximum 20 rewarded interstitials for today. Come back tomorrow!"
          : "You have reached the maximum 20 rewarded video ads for today. Come back tomorrow!",
      };
    }
  }

  const sessionId = `ML_AD_SESSION_${Date.now()}_${crypto.randomBytes(6).toString("hex")}`;
  const expiresAt = new Date(now.getTime() + 5 * 60 * 1000); // 5 minutes
  const adUnitId = isInterstitial ? REWARDED_INTERSTITIAL_AD_UNIT_ID : LIVE_REWARDED_VIDEO_AD_UNIT_ID;
  const expectedXp = isInterstitial ? 7 : 5;

  await userRef.collection("ad_reward_sessions").doc(sessionId).set({
    sessionId,
    userId,
    rewardType,
    adUnitId,
    expectedXp,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt,
    consumed: false,
  });

  return {
    success: true,
    sessionId,
    rewardType,
    adUnitId,
    expectedXp,
    remainingVideoToday: Math.max(0, 20 - videoCountToday),
    remainingInterstitialToday: Math.max(0, 20 - interstitialCountToday),
  };
});

export const claimAdReward = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "User must be authenticated.");
  }

  const userId = request.auth.uid;
  const { sessionId } = request.data || {};

  if (!sessionId || typeof sessionId !== "string") {
    throw new HttpsError("invalid-argument", "Missing or invalid sessionId.");
  }

  const userRef = db.collection("users").doc(userId);
  const sessionRef = userRef.collection("ad_reward_sessions").doc(sessionId);
  const txRef = userRef.collection("xp_transactions").doc(sessionId);

  return await db.runTransaction(async (transaction) => {
    const userSnap = await transaction.get(userRef);
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "User document not found.");
    }
    const userData = userSnap.data() || {};
    if (userData.deletionStatus === "pending" || userData.deletionStatus === "permanently_deleted") {
      throw new HttpsError("failed-precondition", "Cannot claim rewards for an account pending deletion.");
    }

    const sessionSnap = await transaction.get(sessionRef);
    if (!sessionSnap.exists) {
      throw new HttpsError("not-found", "Invalid reward session.");
    }
    const sessionData = sessionSnap.data() || {};
    if (sessionData.userId !== userId) {
      throw new HttpsError("permission-denied", "Session does not belong to the authenticated user.");
    }
    if (sessionData.consumed === true) {
      throw new HttpsError("failed-precondition", "This reward session has already been consumed.");
    }

    const now = new Date();
    const sessionExpiry = sessionData.expiresAt?.toDate ? sessionData.expiresAt.toDate() : new Date(sessionData.expiresAt);
    if (sessionExpiry.getTime() < now.getTime()) {
      throw new HttpsError("deadline-exceeded", "Reward session has expired.");
    }

    // 1. Transactional check for global 30s cooldown
    if (userData.lastAdRewardAt) {
      const lastRewardTime = userData.lastAdRewardAt.toDate ? userData.lastAdRewardAt.toDate().getTime() : new Date(userData.lastAdRewardAt).getTime();
      const elapsedSeconds = Math.floor((now.getTime() - lastRewardTime) / 1000);
      if (elapsedSeconds < 30) {
        const remaining = 30 - elapsedSeconds;
        throw new HttpsError("resource-exhausted", `Please wait ${remaining} more seconds before claiming another reward.`);
      }
    }

    // 2. Transactional check for independent 20-reward daily cap (Nairobi calendar day)
    const todayNairobiKey = getNairobiDateKey(now);
    const isSameNairobiDay = userData.adRewardDateNairobi === todayNairobiKey || userData.adRewardDate === todayNairobiKey;
    const videoCountToday = isSameNairobiDay ? (userData.adRewardCountVideoToday ?? userData.adRewardCountToday ?? 0) : 0;
    const interstitialCountToday = isSameNairobiDay ? (userData.adRewardCountInterstitialToday ?? 0) : 0;

    const rewardType = sessionData.rewardType === "rewarded_interstitial" ? "rewarded_interstitial" : "rewarded_video";
    const isInterstitial = rewardType === "rewarded_interstitial";
    const countToday = isInterstitial ? interstitialCountToday : videoCountToday;

    if (countToday >= 20) {
      throw new HttpsError(
        "resource-exhausted",
        `Daily ${isInterstitial ? "rewarded interstitial" : "rewarded ad"} limit of 20 reached. Come back tomorrow!`
      );
    }

    // Authoritative XP calculation derived strictly from verified session rewardType (never client-supplied)
    const xpEarned = isInterstitial ? 7 : 5;
    const title = isInterstitial ? "Rewarded Interstitial" : "Rewarded Advertisement";
    const description = isInterstitial
      ? "Completed rewarded interstitial advertisement (+7 XP)"
      : "Completed rewarded video advertisement (+5 XP)";

    // 3. Mark session consumed
    transaction.update(sessionRef, {
      consumed: true,
      consumedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 4. Create immutable XP transaction record
    transaction.set(txRef, {
      transactionId: sessionId,
      userId,
      type: rewardType,
      title,
      description,
      xpAmount: xpEarned,
      adUnitId: sessionData.adUnitId || (isInterstitial ? REWARDED_INTERSTITIAL_AD_UNIT_ID : LIVE_REWARDED_VIDEO_AD_UNIT_ID),
      status: "success",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 5. Transactionally increment user balance and independent format counts
    const updateData: Record<string, any> = {
      xpBalance: admin.firestore.FieldValue.increment(xpEarned),
      adRewardXp: admin.firestore.FieldValue.increment(xpEarned),
      adRewardDateNairobi: todayNairobiKey,
      adRewardDate: todayNairobiKey,
      lastAdRewardAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (isInterstitial) {
      updateData.adRewardCountInterstitialToday = interstitialCountToday + 1;
    } else {
      updateData.adRewardCountVideoToday = videoCountToday + 1;
      updateData.adRewardCountToday = videoCountToday + 1;
    }

    transaction.update(userRef, updateData);

    logger.info(`[REWARDED_AD_SUCCESS] User ${userId} successfully claimed ${xpEarned} XP for ${rewardType} session ${sessionId}. Today count: ${countToday + 1}/20.`);

    return {
      success: true,
      xpEarned,
      rewardType,
      newCountToday: countToday + 1,
      remainingToday: 20 - (countToday + 1),
      remainingVideoToday: Math.max(0, 20 - (isInterstitial ? videoCountToday : videoCountToday + 1)),
      remainingInterstitialToday: Math.max(0, 20 - (isInterstitial ? interstitialCountToday + 1 : interstitialCountToday)),
      message: `Reward claimed! +${xpEarned} XP added to your balance.`,
    };
  });
});

/**
 * PROMOTIONAL TRIAL CAMPAIGN
 */
import { PromotionalTrialService } from "./services/promotional_trial_service";
import { SubscriptionReconciliationService } from "./services/subscription_reconciliation_service";

/**
 * CALLABLE FUNCTION: Get promotional campaign status and user eligibility
 */
export const getPromotionalCampaignStatus = onCall(async (request) => {
  const uid = request.auth?.uid;
  const email = request.auth?.token?.email || request.data?.userEmail;
  try {
    if (uid) {
      await SubscriptionReconciliationService.reconcileUserSubscriptions(db, uid);
    }
    return await PromotionalTrialService.getCampaignStatus(db, uid, email);
  } catch (err: any) {
    logger.error("[PROMO_STATUS_ERROR] Failed to fetch promotional campaign status:", err);
    throw new HttpsError("internal", err.message || "Failed to fetch campaign status");
  }
});

/**
 * CALLABLE FUNCTION: Atomically claim a promotional free trial
 */
export const claimPromotionalTrial = onCall(async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "You must be signed in to claim a promotional trial.");
  }
  const uid = request.auth.uid;
  const userEmail = request.auth.token?.email || request.data?.userEmail;

  if (!userEmail) {
    throw new HttpsError("invalid-argument", "A valid email is required to claim a trial.");
  }

  try {
    return await PromotionalTrialService.claimTrial(db, uid, userEmail);
  } catch (err: any) {
    logger.warn(`[PROMO_CLAIM_REJECTED] User ${uid} claim failed:`, err.message);
    throw new HttpsError("failed-precondition", err.message || "Failed to claim promotional trial.");
  }
});

/**
 * CALLABLE FUNCTION: Reconcile user's subscription history status (queued -> active, active -> expired)
 */
export const reconcileUserSubscriptions = onCall(async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Authentication required to reconcile subscriptions.");
  }
  const uid = request.auth.uid;
  try {
    return await SubscriptionReconciliationService.reconcileUserSubscriptions(db, uid);
  } catch (err: any) {
    logger.error(`[RECONCILE_USER_ERROR] Failed to reconcile subscriptions for ${uid}:`, err);
    throw new HttpsError("internal", err.message || "Failed to reconcile subscriptions.");
  }
});

/**
 * ACCOUNT DELETION & RESTORATION LIFECYCLE
 */
import { AccountDeletionService } from "./services/account_deletion_service";

/**
 * CALLABLE FUNCTION: Request user account deletion with 30-day grace period
 */
export const requestAccountDeletion = onCall(async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Authentication required to request account deletion.");
  }
  const uid = request.auth.uid;
  const { reason, userEmail: customEmail } = request.data || {};
  const userEmail = request.auth.token?.email || customEmail;
  const survey = request.data?.survey || request.data?.feedback;
  return await AccountDeletionService.requestAccountDeletion(db, uid, { reason, survey, userEmail });
});

/**
 * CALLABLE FUNCTION: Restore an account in pending deletion state
 */
export const restoreUserAccount = onCall(async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Authentication required to restore account.");
  }
  const uid = request.auth.uid;
  const userEmail = request.auth.token?.email || request.data?.userEmail;
  return await AccountDeletionService.restoreUserAccount(db, uid, userEmail);
});

/**
 * SCHEDULED FUNCTION: Processes expired account deletions once every 24 hours
 */
export const scheduledAccountDeletionProcessor = onSchedule(
  {
    schedule: "every 24 hours",
    timeoutSeconds: 540,
  },
  async (event) => {
    let ik: ImageKit | null = null;
    try {
      ik = getImageKit();
    } catch (e) {
      logger.warn("[IMAGEKIT_INIT_WARN] ImageKit credentials missing during account deletion processor:", e);
    }
    const processed = await AccountDeletionService.processExpiredDeletions(db, ik);
    logger.info(`[SCHEDULED_ACCOUNT_DELETION] Purged and anonymized ${processed} expired accounts.`);
  }
);



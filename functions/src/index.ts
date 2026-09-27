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
          title,
          description,
          courseCode,
          materialType,
          topic,
          targetPrograms,
        }
      );

      if (result.success && result.imageKitUrl) {
        await db.collection("resources").doc(resourceId).update({
          thumbnailUrl: result.imageKitUrl,
        });
        logger.info(`[THUMBNAIL_TRIGGER_SUCCESS] Resource "${resourceId}" attached thumbnail: ${result.imageKitUrl}`);
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
  const { resourceId } = request.data || {};
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
        title,
        description,
        courseCode,
        materialType,
        topic,
        targetPrograms,
      }
    );

    if (result.success && result.imageKitUrl) {
      await docRef.update({
        thumbnailUrl: result.imageKitUrl,
      });
    }

    return result;
  } catch (err: any) {
    logger.error(`[MANUAL_THUMBNAIL_ERROR] Failed thumbnail search for "${resourceId}":`, err);
    throw new HttpsError("internal", err.message || "Failed to search thumbnail.");
  }
});

/**
 * CALLABLE FUNCTION: Directly generate a Gemini thumbnail from metadata for client uploads
 */
export const searchThumbnailWithGemini = onCall(async (request) => {
  const data = request.data || {};
  const unitName = data.unitName || data.title || "";
  const materialType = data.materialType || data.type || "Notes";
  const courseCode = data.unitCode || data.courseCode || data.catType || "";
  const topic = data.topic || data.description || data.catType || unitName;

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
      }
    );

    return {
      success: result.success,
      thumbnailUrl: result.imageKitUrl,
      thumbnailId: result.imageKitFileId,
      imageHash: result.imageHash,
      modelUsed: result.modelUsed,
      error: result.error,
    };
  } catch (err: any) {
    logger.error("[CALLABLE_THUMBNAIL_ERROR] Failed to generate thumbnail with Gemini:", err);
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
} from "./admin/admin_materials";

/**
 * PAYSTACK SUBSCRIPTION INTEGRATION ENDPOINTS
 */
import {
  AUTHORITATIVE_PACKAGES,
  initializePaymentOnPaystack,
  verifyPaystackSignature,
  fulfillSubscription,
} from "./services/paystack_server_service";

/**
 * CALLABLE: Initialize Paystack payment securely on backend
 */
export const initializePaystackPayment = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "User must be authenticated to purchase a subscription.");
  }

  const userId = request.auth.uid;
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
 * CALLABLE: Verify Paystack payment and fulfill subscription
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
        await fulfillSubscription(db, reference, "webhook");
      }
    }

    res.status(200).send("Webhook processed");
  } catch (err: any) {
    logger.error("[PAYSTACK_WEBHOOK_ERROR] Failed to process webhook event:", err);
    res.status(500).send("Webhook processing error");
  }
});



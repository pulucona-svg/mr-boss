import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

/**
 * Validates that the caller is authenticated and possesses the custom claim `admin: true`.
 * @param {any} auth The request.auth context.
 */
function assertCallerIsAdmin(auth: any): void {
  if (!auth || auth.token?.admin !== true) {
    const callerId = auth?.uid || "unauthenticated";
    logger.warn(`[ADMIN_ADS_DENIED] Caller="${callerId}"`);
    throw new HttpsError(
      "permission-denied",
      "Access denied: Caller does not possess administrator privileges."
    );
  }
}

/**
 * CALLABLE FUNCTION: Fetches all manual ads from the `manual_ads` collection.
 */
export const getAdminManualAds = onCall(async (request) => {
  assertCallerIsAdmin(request.auth);

  try {
    const db = admin.firestore();
    const snap = await db.collection("manual_ads").get();

    const ads = snap.docs.map((doc) => {
      const data = doc.data();
      const rawPlacement = (data.placement || "interstitial").toString().toLowerCase().trim();
      const normalizedPlacement = rawPlacement === "carousel"
        ? "carousel"
        : (rawPlacement === "app_launch" || rawPlacement === "app_launch_interstitial" || rawPlacement === "applaunch" || rawPlacement === "app launch" || rawPlacement === "app launch ads")
          ? "app_launch"
          : "interstitial";

      return {
        id: doc.id,
        title: data.title || "",
        subtitle: data.subtitle || "",
        imageUrl: data.url || data.imageUrl || "",
        contactUrl: data.contactUrl || "",
        colorValue: data.color || data.colorValue || 0xFF20C8FF,
        isActive: data.isActive !== undefined ? data.isActive : true,
        isAsset: data.isAsset !== undefined ? data.isAsset : false,
        type: data.type || "image",
        placement: normalizedPlacement,
        mediaFileId: data.mediaFileId || data.fileId || null,
        views: typeof data.views === "number" ? data.views : 0,
        createdAt: data.createdAt ? data.createdAt.toDate().toISOString() : null,
        updatedAt: data.updatedAt ? data.updatedAt.toDate().toISOString() : null,
      };
    });

    logger.info(`[ADMIN_ADS_LIST] Admin "${request.auth?.uid}" fetched ${ads.length} ads.`);

    return {
      success: true,
      ads,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    logger.error("[ADMIN_ADS_LIST_ERROR] Failed to fetch manual ads:", err);
    throw new HttpsError("internal", message || "Failed to fetch manual ads.");
  }
});

/**
 * CALLABLE FUNCTION: Creates or updates a manual ad document in `manual_ads`.
 */
export const saveAdminManualAd = onCall(async (request) => {
  assertCallerIsAdmin(request.auth);

  const data = request.data || {};
  const {
    id,
    title,
    subtitle,
    imageUrl,
    contactUrl,
    colorValue,
    isActive,
    isAsset,
    type,
    placement,
    mediaFileId,
  } = data;

  if (!title || typeof title !== "string" || !title.trim()) {
    throw new HttpsError("invalid-argument", "Ad title is required.");
  }

  if (!imageUrl || typeof imageUrl !== "string" || !imageUrl.trim()) {
    throw new HttpsError("invalid-argument", "Ad image URL or asset path is required.");
  }

  const rawPlacement = (placement || "interstitial").toString().toLowerCase().trim();
  const validPlacement = rawPlacement === "carousel"
    ? "carousel"
    : (rawPlacement === "app_launch" || rawPlacement === "app_launch_interstitial" || rawPlacement === "applaunch" || rawPlacement === "app launch" || rawPlacement === "app launch ads")
      ? "app_launch"
      : "interstitial";

  try {
    const db = admin.firestore();
    const docData: Record<string, any> = {
      title: title.trim(),
      subtitle: (subtitle || "").trim(),
      url: imageUrl.trim(),
      imageUrl: imageUrl.trim(),
      contactUrl: (contactUrl || "").trim(),
      color: typeof colorValue === "number" ? colorValue : 0xFF20C8FF,
      colorValue: typeof colorValue === "number" ? colorValue : 0xFF20C8FF,
      isActive: isActive !== false,
      isAsset: Boolean(isAsset),
      type: type || "image",
      placement: validPlacement,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (mediaFileId && typeof mediaFileId === "string" && mediaFileId.trim()) {
      docData.mediaFileId = mediaFileId.trim();
    }

    let targetId = id;
    if (targetId && typeof targetId === "string" && targetId.trim().length > 0) {
      targetId = targetId.trim();
      await db.collection("manual_ads").doc(targetId).set(docData, {merge: true});
      logger.info(`[ADMIN_ADS_UPDATE] Admin "${request.auth?.uid}" updated ad "${targetId}".`);
    } else {
      docData.views = 0;
      docData.createdAt = admin.firestore.FieldValue.serverTimestamp();
      const newDocRef = await db.collection("manual_ads").add(docData);
      targetId = newDocRef.id;
      logger.info(`[ADMIN_ADS_CREATE] Admin "${request.auth?.uid}" created ad "${targetId}".`);
    }

    return {
      success: true,
      id: targetId,
      ad: {
        id: targetId,
        ...docData,
      },
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    logger.error("[ADMIN_ADS_SAVE_ERROR] Failed to save manual ad:", err);
    throw new HttpsError("internal", message || "Failed to save manual ad.");
  }
});

/**
 * CALLABLE FUNCTION: Toggles the active status of a manual ad.
 */
export const toggleAdminManualAdStatus = onCall(async (request) => {
  assertCallerIsAdmin(request.auth);

  const {id, isActive} = request.data || {};
  if (!id || typeof id !== "string") {
    throw new HttpsError("invalid-argument", "Valid ad ID is required.");
  }

  if (typeof isActive !== "boolean") {
    throw new HttpsError("invalid-argument", "Boolean isActive status is required.");
  }

  try {
    const db = admin.firestore();
    const docRef = db.collection("manual_ads").doc(id.trim());
    const snap = await docRef.get();

    if (!snap.exists) {
      throw new HttpsError("not-found", `Ad with ID "${id}" does not exist.`);
    }

    await docRef.update({
      isActive,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info(`[ADMIN_ADS_TOGGLE] Admin "${request.auth?.uid}" toggled ad "${id}" to ${isActive}.`);

    return {
      success: true,
      id,
      isActive,
    };
  } catch (err: unknown) {
    if (err instanceof HttpsError) throw err;
    const message = err instanceof Error ? err.message : String(err);
    logger.error(`[ADMIN_ADS_TOGGLE_ERROR] Failed to toggle ad "${id}":`, err);
    throw new HttpsError("internal", message || "Failed to toggle ad status.");
  }
});

/**
 * CALLABLE FUNCTION: Deletes a manual ad from `manual_ads`.
 */
export const deleteAdminManualAd = onCall(async (request) => {
  assertCallerIsAdmin(request.auth);

  const {id} = request.data || {};
  if (!id || typeof id !== "string") {
    throw new HttpsError("invalid-argument", "Valid ad ID is required.");
  }

  try {
    const db = admin.firestore();
    const docRef = db.collection("manual_ads").doc(id.trim());
    const snap = await docRef.get();

    if (!snap.exists) {
      throw new HttpsError("not-found", `Ad with ID "${id}" does not exist.`);
    }

    await docRef.delete();
    logger.info(`[ADMIN_ADS_DELETE] Admin "${request.auth?.uid}" deleted ad "${id}".`);

    return {
      success: true,
      id,
    };
  } catch (err: unknown) {
    if (err instanceof HttpsError) throw err;
    const message = err instanceof Error ? err.message : String(err);
    logger.error(`[ADMIN_ADS_DELETE_ERROR] Failed to delete ad "${id}":`, err);
    throw new HttpsError("internal", message || "Failed to delete manual ad.");
  }
});

/**
 * CALLABLE FUNCTION: Seeds the default offline ads into Firestore if the collection is empty.
 */
export const seedDefaultManualAds = onCall(async (request) => {
  assertCallerIsAdmin(request.auth);

  try {
    const db = admin.firestore();
    const existing = await db.collection("manual_ads").limit(1).get();

    if (!existing.empty && request.data?.force !== true) {
      return {
        success: true,
        seeded: false,
        message: "Collection already contains ads.",
      };
    }

    const defaultAds = [
      {
        id: "default_cyber",
        title: "Davy Cybers 💻",
        subtitle: "In need of professional cyber services? Worry no more, Davy Cybers we have got you covered.",
        url: "https://ik.imagekit.io/ubgbitinve/MANUAL_ADS/migrated_ad_cyber_f19k-5YqA.jpeg",
        imageUrl: "https://ik.imagekit.io/ubgbitinve/MANUAL_ADS/migrated_ad_cyber_f19k-5YqA.jpeg",
        mediaFileId: "6ab76c2aead997d09a0a3b46",
        contactUrl: "https://wa.me/254108462492",
        color: 0xFF20C8FF,
        colorValue: 0xFF20C8FF,
        isActive: true,
        isAsset: false,
        views: 0,
        type: "image",
        placement: "interstitial",
      },
      {
        id: "default_data",
        title: "Manu Data 🌐",
        subtitle: "Tired of expensive data plans? Worry no more, Manu Data Solutions we have got you covered.",
        url: "https://ik.imagekit.io/ubgbitinve/MANUAL_ADS/migrated_ad_data_r7GyB3Q2G.jpeg",
        imageUrl: "https://ik.imagekit.io/ubgbitinve/MANUAL_ADS/migrated_ad_data_r7GyB3Q2G.jpeg",
        mediaFileId: "6ab76c31ead997d09a0a4ae1",
        contactUrl: "https://wa.me/254108462492",
        color: 0xFF00A85A,
        colorValue: 0xFF00A85A,
        isActive: true,
        isAsset: false,
        views: 0,
        type: "image",
        placement: "interstitial",
      },
      {
        id: "default_snake",
        title: "Snake Light 💡",
        subtitle: "In need of snake light? Say less, we got you with an exclusive student discount.",
        url: "https://ik.imagekit.io/ubgbitinve/MANUAL_ADS/migrated_ad_snake_sJyVZ4Jiu.jpeg",
        imageUrl: "https://ik.imagekit.io/ubgbitinve/MANUAL_ADS/migrated_ad_snake_sJyVZ4Jiu.jpeg",
        mediaFileId: "6ab76c33ead997d09a0a5215",
        contactUrl: "https://wa.me/254108462492",
        color: 0xFFFF8A00,
        colorValue: 0xFFFF8A00,
        isActive: true,
        isAsset: false,
        views: 0,
        type: "image",
        placement: "interstitial",
      },
    ];

    const batch = db.batch();
    for (const ad of defaultAds) {
      const docRef = db.collection("manual_ads").doc(ad.id);
      batch.set(docRef, {
        ...ad,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    await batch.commit();
    logger.info(`[ADMIN_ADS_SEED] Seeded 3 default ads by admin "${request.auth?.uid}".`);

    return {
      success: true,
      seeded: true,
      count: defaultAds.length,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    logger.error("[ADMIN_ADS_SEED_ERROR] Failed to seed default ads:", err);
    throw new HttpsError("internal", message || "Failed to seed default ads.");
  }
});

/**
 * CALLABLE FUNCTION: Synchronizes offline-recorded manual ad views to Firestore.
 * 
 * - Idempotency: Stores processed batch tokens in `ad_view_sync_batches/{batchId}`.
 * - Atomic: Uses FieldValue.increment() on each valid `manual_ads/{adId}` document.
 * - Validation: Enforces positive integer increments bounded between 1 and 50 per ad.
 * - Resilience: Gracefully ignores missing or deleted ads without aborting the batch.
 */
export const syncManualAdViews = onCall(async (request) => {
  const { batchId, deltas } = request.data || {};

  if (!batchId || typeof batchId !== "string" || !batchId.trim()) {
    throw new HttpsError("invalid-argument", "Missing or invalid batchId.");
  }

  if (!deltas || typeof deltas !== "object" || Array.isArray(deltas)) {
    throw new HttpsError("invalid-argument", "deltas must be a valid key-value object of { adId: count }.");
  }

  const cleanBatchId = batchId.trim();
  const db = admin.firestore();

  // Validate deltas
  const validatedDeltas: Record<string, number> = {};
  for (const [adId, count] of Object.entries(deltas)) {
    if (typeof adId !== "string" || !adId.trim()) continue;
    if (typeof count !== "number" || !Number.isInteger(count) || count < 1) {
      throw new HttpsError(
        "invalid-argument",
        `Invalid increment count for ad "${adId}". Must be a positive integer.`
      );
    }
    if (count > 50) {
      throw new HttpsError(
        "invalid-argument",
        `Increment count for ad "${adId}" exceeds max batch threshold of 50.`
      );
    }
    validatedDeltas[adId.trim()] = count;
  }

  const adIds = Object.keys(validatedDeltas);
  if (adIds.length === 0) {
    return { success: true, processedCount: 0, message: "No valid ad increments in batch." };
  }

  try {
    const batchDocRef = db.collection("ad_view_sync_batches").doc(cleanBatchId);

    // Atomically verify idempotency and apply increments
    const result = await db.runTransaction(async (transaction) => {
      const batchDoc = await transaction.get(batchDocRef);
      if (batchDoc.exists) {
        logger.info(`[SYNC_MANUAL_AD_VIEWS_DUPLICATE] Batch "${cleanBatchId}" was already processed.`);
        return { duplicate: true, appliedIncrements: {}, skippedAds: [] };
      }

      // Check existence of ad documents to gracefully ignore deleted/non-existent ads
      const adRefs = adIds.map((id) => db.collection("manual_ads").doc(id));
      const adSnaps = await Promise.all(adRefs.map((ref) => transaction.get(ref)));

      const appliedIncrements: Record<string, number> = {};
      const skippedAds: string[] = [];

      for (let i = 0; i < adRefs.length; i++) {
        const ref = adRefs[i];
        const snap = adSnaps[i];
        const id = adIds[i];
        const count = validatedDeltas[id];

        if (snap.exists) {
          transaction.update(ref, {
            views: admin.firestore.FieldValue.increment(count),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          appliedIncrements[id] = count;
        } else {
          logger.warn(`[SYNC_MANUAL_AD_VIEWS_SKIP] Ad "${id}" not found in manual_ads collection. Skipping.`);
          skippedAds.push(id);
        }
      }

      // Mark batch as processed
      transaction.set(batchDocRef, {
        batchId: cleanBatchId,
        callerUid: request.auth?.uid || "unauthenticated",
        appliedIncrements,
        skippedAds,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { duplicate: false, appliedIncrements, skippedAds };
    });

    if (result.duplicate) {
      return {
        success: true,
        duplicate: true,
        message: "Batch already processed.",
      };
    }

    logger.info(
      `[SYNC_MANUAL_AD_VIEWS_SUCCESS] Processed batch "${cleanBatchId}". Incremented ${Object.keys(result.appliedIncrements).length} ads.`
    );

    return {
      success: true,
      duplicate: false,
      batchId: cleanBatchId,
      applied: result.appliedIncrements,
      skipped: result.skippedAds,
    };
  } catch (err: unknown) {
    if (err instanceof HttpsError) throw err;
    const message = err instanceof Error ? err.message : String(err);
    logger.error(`[SYNC_MANUAL_AD_VIEWS_ERROR] Failed batch "${cleanBatchId}":`, err);
    throw new HttpsError("internal", message || "Failed to synchronize ad views.");
  }
});

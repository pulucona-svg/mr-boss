import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";

function getImageKit(): ImageKit {
  const publicKey = process.env.IMAGEKIT_PUBLIC_KEY || "";
  const privateKey = process.env.IMAGEKIT_PRIVATE_KEY || "";
  const urlEndpoint = process.env.IMAGEKIT_URL_ENDPOINT || "";
  if (!publicKey || !privateKey || !urlEndpoint) {
    throw new Error("ImageKit credentials are not properly configured on server.");
  }

  return new ImageKit({
    publicKey,
    privateKey,
    urlEndpoint,
  });
}

function requireAdmin(request: any) {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError(
      "permission-denied",
      "Access denied: Caller does not possess administrator privileges."
    );
  }
}

/**
 * CALLABLE FUNCTION: Pins one or more materials to the top of Materials Home.
 * Enforces server-authoritative maximum of 4 pinned items.
 */
export const pinAdminMaterials = onCall(async (request) => {
  requireAdmin(request);

  const db = admin.firestore();
  const { materialIds, titles } = request.data || {};
  const identifiers: string[] = Array.isArray(materialIds)
    ? materialIds
    : Array.isArray(titles)
    ? titles
    : [];

  if (identifiers.length === 0) {
    throw new HttpsError("invalid-argument", "Missing or empty material identifiers.");
  }

  // 1. Fetch target docs
  const targetDocs: FirebaseFirestore.DocumentSnapshot[] = [];
  for (const idOrTitle of identifiers) {
    if (typeof idOrTitle !== "string" || !idOrTitle.trim()) continue;
    const clean = idOrTitle.trim();
    // Try by document ID first
    let docSnap = await db.collection("resources").doc(clean).get();
    if (!docSnap.exists) {
      // Try by title
      const querySnap = await db.collection("resources").where("title", "==", clean).limit(1).get();
      if (!querySnap.empty) {
        docSnap = querySnap.docs[0];
      }
    }
    if (docSnap.exists) {
      targetDocs.push(docSnap);
    }
  }

  if (targetDocs.length === 0) {
    throw new HttpsError("not-found", "No matching materials found to pin.");
  }

  // 2. Fetch existing pinned resources to enforce max 4 limit
  const currentPinnedSnap = await db.collection("resources")
    .where("isPinned", "==", true)
    .get();

  const existingPinnedDocs = currentPinnedSnap.docs.filter(
    (d) => !targetDocs.some((td) => td.id === d.id)
  );

  const batch = db.batch();
  const now = admin.firestore.Timestamp.now();

  // Pin the target docs with microsecond offset to preserve selection order
  for (let i = 0; i < targetDocs.length; i++) {
    const docRef = targetDocs[i].ref;
    // Lower index (first selected) gets slightly newer timestamp
    const offsetSeconds = targetDocs.length - i;
    const pinTimestamp = admin.firestore.Timestamp.fromMillis(now.toMillis() + offsetSeconds * 1000);
    batch.update(docRef, {
      isPinned: true,
      pinnedAt: pinTimestamp,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  // Total allowed existing pinned docs = 4 - targetDocs.length
  const maxAllowedExisting = Math.max(0, 4 - targetDocs.length);
  for (let i = maxAllowedExisting; i < existingPinnedDocs.length; i++) {
    batch.update(existingPinnedDocs[i].ref, {
      isPinned: false,
      pinnedAt: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  await batch.commit();
  logger.info(`[ADMIN_PIN_SUCCESS] Pinned ${targetDocs.length} materials.`);

  return {
    success: true,
    pinnedCount: targetDocs.length,
    message: `${targetDocs.length} material(s) pinned successfully.`,
  };
});

/**
 * CALLABLE FUNCTION: Unpins one or more materials.
 */
export const unpinAdminMaterials = onCall(async (request) => {
  requireAdmin(request);

  const db = admin.firestore();
  const { materialIds, titles } = request.data || {};
  const identifiers: string[] = Array.isArray(materialIds)
    ? materialIds
    : Array.isArray(titles)
    ? titles
    : [];

  if (identifiers.length === 0) {
    throw new HttpsError("invalid-argument", "Missing or empty material identifiers.");
  }

  const batch = db.batch();
  let count = 0;

  for (const idOrTitle of identifiers) {
    if (typeof idOrTitle !== "string" || !idOrTitle.trim()) continue;
    const clean = idOrTitle.trim();

    let docSnap = await db.collection("resources").doc(clean).get();
    if (!docSnap.exists) {
      const querySnap = await db.collection("resources").where("title", "==", clean).limit(1).get();
      if (!querySnap.empty) {
        docSnap = querySnap.docs[0];
      }
    }

    if (docSnap.exists) {
      batch.update(docSnap.ref, {
        isPinned: false,
        pinnedAt: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      count++;
    }
  }

  if (count > 0) {
    await batch.commit();
  }

  logger.info(`[ADMIN_UNPIN_SUCCESS] Unpinned ${count} materials.`);

  return {
    success: true,
    unpinnedCount: count,
    message: `${count} material(s) unpinned successfully.`,
  };
});

/**
 * CALLABLE FUNCTION: Archives one or more materials.
 * Removes them from active materials for all users.
 */
export const archiveAdminMaterials = onCall(async (request) => {
  requireAdmin(request);

  const db = admin.firestore();
  const { materialIds, titles } = request.data || {};
  const identifiers: string[] = Array.isArray(materialIds)
    ? materialIds
    : Array.isArray(titles)
    ? titles
    : [];

  if (identifiers.length === 0) {
    throw new HttpsError("invalid-argument", "Missing or empty material identifiers.");
  }

  const batch = db.batch();
  let count = 0;

  for (const idOrTitle of identifiers) {
    if (typeof idOrTitle !== "string" || !idOrTitle.trim()) continue;
    const clean = idOrTitle.trim();

    let docSnap = await db.collection("resources").doc(clean).get();
    if (!docSnap.exists) {
      const querySnap = await db.collection("resources").where("title", "==", clean).limit(1).get();
      if (!querySnap.empty) {
        docSnap = querySnap.docs[0];
      }
    }

    if (docSnap.exists) {
      batch.update(docSnap.ref, {
        status: "archived",
        archivedAt: admin.firestore.FieldValue.serverTimestamp(),
        isPinned: false,
        pinnedAt: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      count++;
    }
  }

  if (count > 0) {
    await batch.commit();
  }

  logger.info(`[ADMIN_ARCHIVE_SUCCESS] Archived ${count} materials.`);

  return {
    success: true,
    archivedCount: count,
    message: `${count} material(s) archived successfully.`,
  };
});

/**
 * CALLABLE FUNCTION: Moves one or more materials to Trash.
 */
export const trashAdminMaterials = onCall(async (request) => {
  requireAdmin(request);

  const db = admin.firestore();
  const { materialIds, titles } = request.data || {};
  const identifiers: string[] = Array.isArray(materialIds)
    ? materialIds
    : Array.isArray(titles)
    ? titles
    : [];

  if (identifiers.length === 0) {
    throw new HttpsError("invalid-argument", "Missing or empty material identifiers.");
  }

  const batch = db.batch();
  let count = 0;

  for (const idOrTitle of identifiers) {
    if (typeof idOrTitle !== "string" || !idOrTitle.trim()) continue;
    const clean = idOrTitle.trim();

    let docSnap = await db.collection("resources").doc(clean).get();
    if (!docSnap.exists) {
      const querySnap = await db.collection("resources").where("title", "==", clean).limit(1).get();
      if (!querySnap.empty) {
        docSnap = querySnap.docs[0];
      }
    }

    if (docSnap.exists) {
      batch.update(docSnap.ref, {
        status: "trash",
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        isPinned: false,
        pinnedAt: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      count++;
    }
  }

  if (count > 0) {
    await batch.commit();
  }

  logger.info(`[ADMIN_TRASH_SUCCESS] Moved ${count} materials to Trash.`);

  return {
    success: true,
    trashedCount: count,
    message: `${count} material(s) moved to Trash.`,
  };
});

/**
 * CALLABLE FUNCTION: Restores one or more materials from Archives or Trash back to active.
 */
export const restoreAdminMaterials = onCall(async (request) => {
  requireAdmin(request);

  const db = admin.firestore();
  const { materialIds, titles } = request.data || {};
  const identifiers: string[] = Array.isArray(materialIds)
    ? materialIds
    : Array.isArray(titles)
    ? titles
    : [];

  if (identifiers.length === 0) {
    throw new HttpsError("invalid-argument", "Missing or empty material identifiers.");
  }

  const batch = db.batch();
  let count = 0;

  for (const idOrTitle of identifiers) {
    if (typeof idOrTitle !== "string" || !idOrTitle.trim()) continue;
    const clean = idOrTitle.trim();

    let docSnap = await db.collection("resources").doc(clean).get();
    if (!docSnap.exists) {
      const querySnap = await db.collection("resources").where("title", "==", clean).limit(1).get();
      if (!querySnap.empty) {
        docSnap = querySnap.docs[0];
      }
    }

    if (docSnap.exists) {
      batch.update(docSnap.ref, {
        status: "approved",
        archivedAt: null,
        deletedAt: null,
        restoredAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      count++;
    }
  }

  if (count > 0) {
    await batch.commit();
  }

  logger.info(`[ADMIN_RESTORE_SUCCESS] Restored ${count} materials.`);

  return {
    success: true,
    restoredCount: count,
    message: `${count} material(s) restored successfully.`,
  };
});

/**
 * CALLABLE FUNCTION: Permanently deletes one or more materials.
 * Purges Firestore document and cleans up ImageKit file and thumbnail assets.
 */
export const deleteAdminMaterials = onCall(async (request) => {
  requireAdmin(request);

  const db = admin.firestore();
  let ik: ImageKit | null = null;
  try {
    ik = getImageKit();
  } catch (e) {
    logger.warn("[IMAGEKIT_INIT_WARN] ImageKit credentials missing during permanent deletion:", e);
  }

  const { materialIds, titles } = request.data || {};
  const identifiers: string[] = Array.isArray(materialIds)
    ? materialIds
    : Array.isArray(titles)
    ? titles
    : [];

  if (identifiers.length === 0) {
    throw new HttpsError("invalid-argument", "Missing or empty material identifiers.");
  }

  let deletedCount = 0;

  for (const idOrTitle of identifiers) {
    if (typeof idOrTitle !== "string" || !idOrTitle.trim()) continue;
    const clean = idOrTitle.trim();

    let docSnap = await db.collection("resources").doc(clean).get();
    if (!docSnap.exists) {
      const querySnap = await db.collection("resources").where("title", "==", clean).limit(1).get();
      if (!querySnap.empty) {
        docSnap = querySnap.docs[0];
      }
    }

    if (docSnap.exists) {
      const data = docSnap.data() || {};
      const fileId = data.fileId as string | undefined;
      const thumbnailId = data.thumbnailId as string | undefined;

      // 1. Delete associated media from ImageKit
      if (ik) {
        if (fileId) {
          try {
            await ik.deleteFile(fileId);
            logger.info(`[ADMIN_DELETE_IMAGEKIT] Deleted material fileId="${fileId}"`);
          } catch (e) {
            logger.warn(`[ADMIN_DELETE_IMAGEKIT_WARN] Failed to delete fileId="${fileId}":`, e);
          }
        }
        if (thumbnailId) {
          try {
            await ik.deleteFile(thumbnailId);
            logger.info(`[ADMIN_DELETE_IMAGEKIT] Deleted material thumbnailId="${thumbnailId}"`);
          } catch (e) {
            logger.warn(`[ADMIN_DELETE_IMAGEKIT_WARN] Failed to delete thumbnailId="${thumbnailId}":`, e);
          }
        }
      }

      // 2. Delete Firestore document
      await docSnap.ref.delete();
      deletedCount++;
    }
  }

  logger.info(`[ADMIN_DELETE_PERMANENT_SUCCESS] Purged ${deletedCount} materials.`);

  return {
    success: true,
    deletedCount,
    message: `${deletedCount} material(s) permanently deleted.`,
  };
});

/**
 * SCHEDULED FUNCTION: Purges materials in Trash older than 30 days.
 * Runs once every 24 hours.
 */
export const scheduledMaterialsTrashRetention = onSchedule("every 24 hours", async (event) => {
  const db = admin.firestore();
  let ik: ImageKit | null = null;
  try {
    ik = getImageKit();
  } catch (e) {
    logger.warn("[IMAGEKIT_INIT_WARN] ImageKit credentials missing during trash retention:", e);
  }

  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
  const cutoffTimestamp = admin.firestore.Timestamp.fromDate(thirtyDaysAgo);

  logger.info(`[MATERIALS_TRASH_RETENTION] Checking trashed/rejected materials deleted before ${thirtyDaysAgo.toISOString()}...`);

  const trashSnap = await db.collection("resources")
    .where("status", "==", "trash")
    .where("deletedAt", "<=", cutoffTimestamp)
    .limit(100)
    .get();

  const rejectedSnap = await db.collection("resources")
    .where("status", "==", "rejected")
    .where("deletedAt", "<=", cutoffTimestamp)
    .limit(100)
    .get();

  const expiredDocs = [...trashSnap.docs, ...rejectedSnap.docs];

  if (expiredDocs.length === 0) {
    logger.info("[MATERIALS_TRASH_RETENTION] No expired materials in Trash or Rejected found.");
    return;
  }

  let purgedCount = 0;
  for (const doc of expiredDocs) {
    const data = doc.data() || {};
    const fileId = data.fileId as string | undefined;
    const thumbnailId = data.thumbnailId as string | undefined;

    if (ik) {
      if (fileId) {
        try {
          await ik.deleteFile(fileId);
        } catch (_) {}
      }
      if (thumbnailId) {
        try {
          await ik.deleteFile(thumbnailId);
        } catch (_) {}
      }
    }

    await doc.ref.delete();
    purgedCount++;
  }

  logger.info(`[MATERIALS_TRASH_RETENTION] Successfully purged ${purgedCount} expired materials.`);
});

/**
 * CALLABLE FUNCTION: Modifies an existing material in-place.
 * Enforces admin authorization, atomically updates metadata,
 * and safely cleans up old PDF/thumbnail from ImageKit if replaced.
 */
export const modifyAdminMaterial = onCall(async (request) => {
  requireAdmin(request);

  const db = admin.firestore();
  const {
    materialId,
    unitName,
    unitCode,
    title,
    materialType,
    catType,
    yearOfPublication,
    yearOfStudy,
    semester,
    targetPrograms,
    programCodes,
    lecturers,
    fileUrl,
    fileId,
    fileName,
    materialFormat,
    thumbnailUrl,
    thumbnailId,
    thumbnailStatus,
    isAnonymous,
    yearOfUpload,
    oldFileId,
    oldThumbnailId,
    status,
    adminRemark,
  } = request.data || {};

  if (!materialId || typeof materialId !== "string" || !materialId.trim()) {
    throw new HttpsError("invalid-argument", "Missing required materialId.");
  }

  const cleanId = materialId.trim();
  const docRef = db.collection("resources").doc(cleanId);
  const docSnap = await docRef.get();

  if (!docSnap.exists) {
    throw new HttpsError("not-found", `Material with ID "${cleanId}" not found.`);
  }

  const existingData = docSnap.data() || {};

  // Build updated fields dictionary
  const updateData: Record<string, any> = {
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedByAdmin: true,
  };

  if (unitName !== undefined) updateData.unitName = unitName;
  if (unitCode !== undefined) updateData.unitCode = unitCode;
  if (title !== undefined) updateData.title = title;
  if (materialType !== undefined) {
    updateData.type = materialType;
    updateData.materialType = materialType;
  }
  if (catType !== undefined) updateData.catType = catType;
  if (yearOfPublication !== undefined) updateData.publicationYear = String(yearOfPublication);
  if (yearOfStudy !== undefined) updateData.yearOfStudy = yearOfStudy;
  if (semester !== undefined) updateData.semester = semester;
  if (Array.isArray(targetPrograms)) updateData.targetPrograms = targetPrograms;
  if (Array.isArray(programCodes)) updateData.programCodes = programCodes;
  if (Array.isArray(lecturers)) updateData.lecturers = lecturers;
  if (materialFormat !== undefined) updateData.materialFormat = materialFormat;
  if (isAnonymous !== undefined) updateData.isAnonymous = isAnonymous;
  if (yearOfUpload !== undefined) {
    updateData.year = String(yearOfUpload);
    updateData.uploadYear = String(yearOfUpload);
  }

  // Handle moderation modify
  if (status === "modified") {
    updateData.status = "modified";
    updateData.modifiedAndApprovedAt = admin.firestore.FieldValue.serverTimestamp();
    if (adminRemark !== undefined && adminRemark !== null && String(adminRemark).trim() !== "") {
      updateData.adminRemark = String(adminRemark).trim();
    }
  }

  // Handle PDF file replacement
  let fileReplaced = false;
  if (fileUrl && fileUrl !== existingData.fileUrl) {
    updateData.fileUrl = fileUrl;
    if (fileId) updateData.fileId = fileId;
    if (fileName) updateData.fileName = fileName;
    fileReplaced = true;
  }

  // Handle thumbnail replacement
  let thumbReplaced = false;
  if (thumbnailUrl && thumbnailUrl !== existingData.thumbnailUrl) {
    updateData.thumbnailUrl = thumbnailUrl;
    if (thumbnailId) updateData.thumbnailId = thumbnailId;
    if (thumbnailStatus) updateData.thumbnailStatus = thumbnailStatus;
    thumbReplaced = true;
  }

  // 1. Atomically update existing Firestore document in place (preserving same document ID)
  await docRef.update(updateData);
  logger.info(`[ADMIN_MODIFY_SUCCESS] Material "${cleanId}" modified in-place.`);

  // If moderation modified, create idempotent notification to uploader
  if (status === "modified") {
    const uploaderId = existingData.uploaderId;
    if (uploaderId && typeof uploaderId === "string") {
      const notifId = `notif_modify_${cleanId}`;
      const notifRef = db.collection("users").doc(uploaderId).collection("notifications").doc(notifId);
      const notifSnap = await notifRef.get();
      if (!notifSnap.exists) {
        await notifRef.set({
          id: notifId,
          type: "materialModified",
          title: "Material Modified & Approved",
          message: `Your uploaded material "${updateData.title || existingData.title || "Material"}" was modified and approved by an admin. You can view the changes.`,
          resourceTitle: updateData.title || existingData.title || "",
          materialId: cleanId,
          remark: updateData.adminRemark || null,
          senderName: "Admin",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          isRead: false,
        });
        logger.info(`[ADMIN_MODIFY_NOTIF] Created notification for uploader "${uploaderId}".`);
      }
    }
  }

  // 2. Only after successful update commit, permanently delete the old PDF/thumbnail
  let ik: ImageKit | null = null;
  try {
    ik = getImageKit();
  } catch (e) {
    logger.warn("[IMAGEKIT_INIT_WARN] ImageKit credentials missing during modify cleanup:", e);
  }

  if (ik) {
    const toDeleteFileId = oldFileId || (fileReplaced ? existingData.fileId : null);
    if (fileReplaced && toDeleteFileId && toDeleteFileId !== fileId) {
      try {
        await ik.deleteFile(toDeleteFileId);
        logger.info(`[ADMIN_MODIFY_CLEANUP] Deleted old PDF fileId="${toDeleteFileId}"`);
      } catch (e) {
        logger.warn(`[ADMIN_MODIFY_CLEANUP_WARN] Failed to delete old PDF fileId="${toDeleteFileId}":`, e);
      }
    }

    const toDeleteThumbId = oldThumbnailId || (thumbReplaced ? existingData.thumbnailId : null);
    if (thumbReplaced && toDeleteThumbId && toDeleteThumbId !== thumbnailId) {
      try {
        await ik.deleteFile(toDeleteThumbId);
        logger.info(`[ADMIN_MODIFY_CLEANUP] Deleted old thumbnail thumbnailId="${toDeleteThumbId}"`);
      } catch (e) {
        logger.warn(`[ADMIN_MODIFY_CLEANUP_WARN] Failed to delete old thumbnailId="${toDeleteThumbId}":`, e);
      }
    }
  }

  return {
    success: true,
    materialId: cleanId,
    message: "Material modified successfully.",
  };
});

/**
 * CALLABLE FUNCTION: Approves a pending material.
 * Enforces admin authorization, transitions status: pending -> approved,
 * records approval timestamp & optional admin remark, and sends an idempotent
 * approval notification to the uploader.
 */
export const approveAdminMaterial = onCall(async (request) => {
  requireAdmin(request);

  const db = admin.firestore();
  const { materialId, adminRemark } = request.data || {};

  if (!materialId || typeof materialId !== "string" || !materialId.trim()) {
    throw new HttpsError("invalid-argument", "Missing required materialId.");
  }

  const cleanId = materialId.trim();
  const docRef = db.collection("resources").doc(cleanId);
  const docSnap = await docRef.get();

  if (!docSnap.exists) {
    throw new HttpsError("not-found", `Material with ID "${cleanId}" not found.`);
  }

  const existingData = docSnap.data() || {};
  const uploaderId = existingData.uploaderId;
  const title = existingData.title || "Material";

  const updateData: Record<string, any> = {
    status: "approved",
    approvedAt: admin.firestore.FieldValue.serverTimestamp(),
    approvedByAdmin: true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (adminRemark !== undefined && adminRemark !== null && String(adminRemark).trim() !== "") {
    updateData.adminRemark = String(adminRemark).trim();
  }

  await docRef.update(updateData);
  logger.info(`[ADMIN_APPROVE_SUCCESS] Material "${cleanId}" approved in-place.`);

  // Idempotent notification to uploader
  if (uploaderId && typeof uploaderId === "string") {
    const notifId = `notif_approve_${cleanId}`;
    const notifRef = db.collection("users").doc(uploaderId).collection("notifications").doc(notifId);
    const notifSnap = await notifRef.get();
    if (!notifSnap.exists) {
      await notifRef.set({
        id: notifId,
        type: "materialApproved",
        title: "Material Approved",
        message: `Your uploaded material "${title}" was approved! Thank you for contributing to the platform.`,
        resourceTitle: title,
        materialId: cleanId,
        remark: updateData.adminRemark || null,
        senderName: "Admin",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
      });
      logger.info(`[ADMIN_APPROVE_NOTIF] Created notification for uploader "${uploaderId}".`);
    }
  }

  return {
    success: true,
    materialId: cleanId,
    message: "Material approved successfully.",
  };
});

/**
 * CALLABLE FUNCTION: Rejects a pending material.
 * Enforces admin authorization, transitions status: pending -> rejected,
 * records 30-day retention timestamps (rejectedAt, deletedAt), selected rejection reasons,
 * optional admin remark, and sends an idempotent rejection notification to the uploader.
 */
export const rejectAdminMaterial = onCall(async (request) => {
  requireAdmin(request);

  const db = admin.firestore();
  const { materialId, rejectionReasons, adminRemark } = request.data || {};

  if (!materialId || typeof materialId !== "string" || !materialId.trim()) {
    throw new HttpsError("invalid-argument", "Missing required materialId.");
  }

  if (!Array.isArray(rejectionReasons) || rejectionReasons.length === 0) {
    throw new HttpsError("invalid-argument", "At least one rejection reason must be selected.");
  }

  const cleanId = materialId.trim();
  const docRef = db.collection("resources").doc(cleanId);
  const docSnap = await docRef.get();

  if (!docSnap.exists) {
    throw new HttpsError("not-found", `Material with ID "${cleanId}" not found.`);
  }

  const existingData = docSnap.data() || {};
  const uploaderId = existingData.uploaderId;
  const title = existingData.title || "Material";

  const now = admin.firestore.Timestamp.now();
  const updateData: Record<string, any> = {
    status: "rejected",
    rejectedAt: now,
    deletedAt: now, // Triggers 30-day retention cleanup
    rejectionReasons: rejectionReasons,
    rejectedByAdmin: true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (adminRemark !== undefined && adminRemark !== null && String(adminRemark).trim() !== "") {
    updateData.adminRemark = String(adminRemark).trim();
  }

  await docRef.update(updateData);
  logger.info(`[ADMIN_REJECT_SUCCESS] Material "${cleanId}" rejected.`);

  // Idempotent notification to uploader
  if (uploaderId && typeof uploaderId === "string") {
    const notifId = `notif_reject_${cleanId}`;
    const notifRef = db.collection("users").doc(uploaderId).collection("notifications").doc(notifId);
    const notifSnap = await notifRef.get();
    if (!notifSnap.exists) {
      await notifRef.set({
        id: notifId,
        type: "materialRejected",
        title: "Material Rejected",
        message: `Your uploaded material "${title}" was not approved.`,
        resourceTitle: title,
        materialId: cleanId,
        rejectionReasons: rejectionReasons,
        remark: updateData.adminRemark || null,
        senderName: "Admin",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
      });
      logger.info(`[ADMIN_REJECT_NOTIF] Created rejection notification for uploader "${uploaderId}".`);
    }
  }

  return {
    success: true,
    materialId: cleanId,
    message: "Material rejected successfully.",
  };
});

/**
 * CALLABLE FUNCTION: Reconsiders a previously rejected material.
 * Enforces admin authorization, removes the rejected state, returns status to "pending",
 * clears rejection metadata, and allows fresh vetting without auto-approving.
 */
export const reconsiderAdminMaterial = onCall(async (request) => {
  requireAdmin(request);

  const db = admin.firestore();
  const { materialId } = request.data || {};

  if (!materialId || typeof materialId !== "string" || !materialId.trim()) {
    throw new HttpsError("invalid-argument", "Missing required materialId.");
  }

  const cleanId = materialId.trim();
  const docRef = db.collection("resources").doc(cleanId);
  const docSnap = await docRef.get();

  if (!docSnap.exists) {
    throw new HttpsError("not-found", `Material with ID "${cleanId}" not found.`);
  }

  await docRef.update({
    status: "pending",
    reconsideredAt: admin.firestore.FieldValue.serverTimestamp(),
    rejectedAt: null,
    deletedAt: null,
    rejectionReasons: null,
    adminRemark: null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  logger.info(`[ADMIN_RECONSIDER_SUCCESS] Material "${cleanId}" returned to pending.`);

  return {
    success: true,
    materialId: cleanId,
    message: "Material returned to Pending for reconsideration.",
  };
});

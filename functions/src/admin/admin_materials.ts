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

  logger.info(`[MATERIALS_TRASH_RETENTION] Checking trashed materials deleted before ${thirtyDaysAgo.toISOString()}...`);

  const snap = await db.collection("resources")
    .where("status", "==", "trash")
    .where("deletedAt", "<=", cutoffTimestamp)
    .limit(100)
    .get();

  if (snap.empty) {
    logger.info("[MATERIALS_TRASH_RETENTION] No expired materials in Trash found.");
    return;
  }

  let purgedCount = 0;
  for (const doc of snap.docs) {
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

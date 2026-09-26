import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";
import { CanonicalExploreService } from "../services/canonical_explore_service";

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

function isValidHttpUrl(str: string): boolean {
  try {
    const url = new URL(str.trim());
    return url.protocol === "http:" || url.protocol === "https:";
  } catch (_) {
    return false;
  }
}

export interface SubtopicInput {
  title: string;
  body: string;
  imageBase64?: string;
  imageUrl?: string;
  imageFileId?: string;
  imageFileName?: string;
  imageDescription: string;
}

/**
 * CALLABLE FUNCTION: Creates a new article manually submitted by an admin,
 * uploads images to ImageKit under NEWS_ARTICLES, stitches Markdown, writes
 * to explore_news, and triggers 30-article retention.
 */
export const createAdminArticle = onCall(async (request) => {
  requireAdmin(request);

  const db = admin.firestore();
  const data = request.data || {};
  const {
    categoryId,
    categoryName,
    source,
    title,
    sourceUrl,
    subtopics,
  } = data;

  // 1. Validate Category
  if (!categoryId || typeof categoryId !== "string" || !categoryId.trim()) {
    throw new HttpsError("invalid-argument", "Article category is required.");
  }
  const cleanCategoryName = (categoryName || categoryId).toString().trim();
  const cleanCategoryId = categoryId.toString().trim().toLowerCase().replace(/[^a-z0-9]+/g, "-");

  // 2. Validate Source
  if (!source || typeof source !== "string" || !source.trim()) {
    throw new HttpsError("invalid-argument", "Article source publisher is required.");
  }
  const cleanSource = source.trim();

  // 3. Validate Title
  if (!title || typeof title !== "string" || title.trim().length < 5) {
    throw new HttpsError("invalid-argument", "Article title must be at least 5 characters.");
  }
  const cleanTitle = title.trim();

  // 4. Validate URL / Reference link
  if (!sourceUrl || typeof sourceUrl !== "string" || !isValidHttpUrl(sourceUrl)) {
    throw new HttpsError("invalid-argument", "A valid http:// or https:// source URL is required.");
  }
  const cleanSourceUrl = sourceUrl.trim();

  // 5. Validate Subtopics (minimum 4 completed subtopics)
  if (!Array.isArray(subtopics) || subtopics.length < 4) {
    throw new HttpsError(
      "invalid-argument",
      "At least four completed subtopics are strictly required to create an article."
    );
  }

  for (let i = 0; i < subtopics.length; i++) {
    const sub = subtopics[i] as SubtopicInput;
    if (!sub || typeof sub !== "object") {
      throw new HttpsError("invalid-argument", `Subtopic ${i + 1} is invalid.`);
    }
    if (!sub.title || typeof sub.title !== "string" || sub.title.trim().length < 3) {
      throw new HttpsError("invalid-argument", `Subtopic ${i + 1} requires a valid title (min 3 characters).`);
    }
    if (!sub.body || typeof sub.body !== "string" || sub.body.trim().length < 10) {
      throw new HttpsError("invalid-argument", `Subtopic ${i + 1} requires a valid body text (min 10 characters).`);
    }
    if (!sub.imageBase64 && !sub.imageUrl) {
      throw new HttpsError("invalid-argument", `Subtopic ${i + 1} requires a selected image.`);
    }
    if (!sub.imageDescription || typeof sub.imageDescription !== "string" || sub.imageDescription.trim().length < 3) {
      throw new HttpsError("invalid-argument", `Subtopic ${i + 1} requires an image description/caption.`);
    }
  }

  // 6. ImageKit Uploads & Processing
  const ik = getImageKit();
  const processedImages: Array<{
    position: number;
    caption: string;
    imageUrl: string;
    fileId?: string;
    sourceUrl?: string;
    sourceDomain?: string;
  }> = [];

  const sanitizedSlug = cleanTitle.replace(/[^a-zA-Z0-9]/g, "_").toLowerCase().slice(0, 30);

  try {
    for (let i = 0; i < subtopics.length; i++) {
      const sub = subtopics[i] as SubtopicInput;
      let finalImageUrl = sub.imageUrl || "";
      let finalFileId = sub.imageFileId || "";

      if (sub.imageBase64) {
        const cleanBase64 = sub.imageBase64.includes(",")
          ? sub.imageBase64.split(",")[1]
          : sub.imageBase64;
        const buffer = Buffer.from(cleanBase64, "base64");

        const extMatch = sub.imageFileName?.match(/\.(jpg|jpeg|png|webp)$/i);
        const ext = extMatch ? extMatch[1].toLowerCase() : "jpg";
        const fileName = `admin_${sanitizedSlug}_sub_${i + 1}_${Date.now()}.${ext}`;

        const uploadRes = await ik.upload({
          file: cleanBase64,
          fileName,
          folder: "NEWS_ARTICLES",
          useUniqueFileName: true,
        });

        if (!uploadRes || !uploadRes.url) {
          throw new Error(`Failed to upload image for subtopic ${i + 1} to ImageKit.`);
        }

        finalImageUrl = uploadRes.url;
        finalFileId = uploadRes.fileId;

        // Record hash for deduplication
        try {
          const hash = crypto.createHash("sha256").update(buffer).digest("hex");
          await db.collection("used_article_images").add({
            imageHash: hash,
            imageKitUrl: finalImageUrl,
            articleTitle: cleanTitle,
            sourceUrl: cleanSourceUrl,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      }

      processedImages.push({
        position: i + 1,
        caption: sub.imageDescription.trim(),
        imageUrl: finalImageUrl,
        fileId: finalFileId,
        sourceUrl: cleanSourceUrl,
        sourceDomain: "ImageKit",
      });
    }
  } catch (imgErr: any) {
    logger.error("[ADMIN_ARTICLE_IMAGE_FAIL]", imgErr);
    // Cleanup any uploaded images in this batch to prevent orphans
    for (const item of processedImages) {
      if (item.fileId) {
        try {
          await ik.deleteFile(item.fileId);
        } catch (_) {}
      }
    }
    throw new HttpsError(
      "internal",
      `Image upload failed: ${imgErr.message || "Could not complete media upload."}`
    );
  }

  // 7. Markdown Content Stitching (Strict Explore schema format)
  // # Headline
  // Lead paragraph (Subtopic 1 body)
  // ![Caption](ImageUrl)
  // *Caption*
  // ## Subtopic 2 Title
  // Subtopic 2 body
  // ...
  let markdownContent = `# ${cleanTitle}\n\n${subtopics[0].body.trim()}\n\n`;
  markdownContent += `![${processedImages[0].caption}](${processedImages[0].imageUrl})\n*${processedImages[0].caption}*\n\n`;

  for (let i = 1; i < subtopics.length; i++) {
    const sub = subtopics[i];
    const img = processedImages[i];
    markdownContent += `## ${sub.title.trim()}\n\n${sub.body.trim()}\n\n`;
    markdownContent += `![${img.caption}](${img.imageUrl})\n*${img.caption}*\n\n`;
  }

  // 8. Summary Generation
  const rawSub0Body = subtopics[0].body.trim();
  const sentences = rawSub0Body.split(/(?<=[.!?])\s+/);
  const summary = (sentences.length >= 2 ? sentences.slice(0, 2).join(" ") : rawSub0Body).slice(0, 300);

  // 9. Document assembly
  const articleDocRef = db.collection("explore_news").doc();
  const articleId = articleDocRef.id;
  const firstImageUrl = processedImages[0].imageUrl;
  const imageUrls = processedImages.map((img) => img.imageUrl);

  const articlePayload = {
    articleId,
    id: articleId,
    title: cleanTitle,
    summary,
    editorialSummary: summary,
    content: markdownContent,
    category: cleanCategoryName,
    categoryId: cleanCategoryId,
    coverImage: firstImageUrl,
    thumbnailUrl: firstImageUrl,
    imageUrls,
    images: processedImages,
    imageCount: processedImages.length,
    imageSearchCompleted: true,
    imageSearchAttempts: 1,
    imageSources: ["ImageKit"],
    source: cleanSource,
    sourceUrl: cleanSourceUrl,
    originalSourceUrl: cleanSourceUrl,
    status: "published",
    createdVia: "admin_manual",
    createdBy: request.auth?.uid || "admin",
    publishedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  try {
    await articleDocRef.set(articlePayload);
    logger.info(`[ADMIN_ARTICLE_CREATED] Article "${cleanTitle}" (docId="${articleId}") published in category="${cleanCategoryId}".`);

    // 10. Enforce 30-article category retention rule
    await CanonicalExploreService.enforceRetention(db, cleanCategoryId, 30);

    return {
      success: true,
      articleId,
      title: cleanTitle,
      category: cleanCategoryName,
      categoryId: cleanCategoryId,
      message: "Article created and published successfully.",
    };
  } catch (saveErr: any) {
    logger.error("[ADMIN_ARTICLE_SAVE_FAIL]", saveErr);
    throw new HttpsError("internal", `Failed to save article to database: ${saveErr.message}`);
  }
});

/**
 * CALLABLE FUNCTION: Deactivates one or more active articles.
 * Moves status to "deactivated" without deleting document or media.
 */
export const deactivateAdminArticles = onCall(async (request) => {
  requireAdmin(request);

  const db = admin.firestore();
  const { articleIds } = request.data || {};

  if (!Array.isArray(articleIds) || articleIds.length === 0) {
    throw new HttpsError("invalid-argument", "Missing or empty articleIds parameter.");
  }

  const batch = db.batch();
  let count = 0;

  for (const id of articleIds) {
    if (typeof id === "string" && id.trim()) {
      const docRef = db.collection("explore_news").doc(id.trim());
      batch.update(docRef, {
        status: "deactivated",
        deactivatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      count++;
    }
  }

  if (count === 0) {
    throw new HttpsError("invalid-argument", "No valid article IDs provided.");
  }

  await batch.commit();
  logger.info(`[ADMIN_ARTICLES_DEACTIVATED] Deactivated ${count} articles.`);

  return {
    success: true,
    deactivatedCount: count,
    message: `${count} article(s) deactivated successfully.`,
  };
});

/**
 * CALLABLE FUNCTION: Restores one or more deactivated articles back to "published".
 * Preserves the original publishedAt timestamp and immediately enforces 30-article retention.
 */
export const restoreAdminArticles = onCall(async (request) => {
  requireAdmin(request);

  const db = admin.firestore();
  const { articleIds } = request.data || {};

  if (!Array.isArray(articleIds) || articleIds.length === 0) {
    throw new HttpsError("invalid-argument", "Missing or empty articleIds parameter.");
  }

  const batch = db.batch();
  const categoriesToEnforce = new Set<string>();
  let count = 0;

  for (const id of articleIds) {
    if (typeof id === "string" && id.trim()) {
      const docRef = db.collection("explore_news").doc(id.trim());
      const snap = await docRef.get();
      if (snap.exists) {
        const data = snap.data() || {};
        const catId = data.categoryId || "";
        if (catId) categoriesToEnforce.add(catId);

        // Restore to "published" while preserving original publishedAt!
        batch.update(docRef, {
          status: "published",
          restoredAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        count++;
      }
    }
  }

  if (count === 0) {
    throw new HttpsError("not-found", "None of the specified articles were found.");
  }

  await batch.commit();
  logger.info(`[ADMIN_ARTICLES_RESTORED] Restored ${count} articles.`);

  // Enforce 30-article retention for each affected category
  for (const catId of categoriesToEnforce) {
    try {
      await CanonicalExploreService.enforceRetention(db, catId, 30);
    } catch (retentionErr) {
      logger.warn(`[ADMIN_RESTORE_RETENTION_WARN] Category "${catId}" retention check error:`, retentionErr);
    }
  }

  return {
    success: true,
    restoredCount: count,
    message: `${count} article(s) restored successfully.`,
  };
});

/**
 * CALLABLE FUNCTION: Permanently deletes one or more articles.
 * Purges document from explore_news (and explore_news_archive),
 * deletes associated ImageKit assets, and removes deduplication hashes.
 */
export const deleteAdminArticles = onCall(async (request) => {
  requireAdmin(request);

  const db = admin.firestore();
  const ik = getImageKit();
  const { articleIds } = request.data || {};

  if (!Array.isArray(articleIds) || articleIds.length === 0) {
    throw new HttpsError("invalid-argument", "Missing or empty articleIds parameter.");
  }

  let deletedCount = 0;

  for (const id of articleIds) {
    if (typeof id !== "string" || !id.trim()) continue;
    const cleanId = id.trim();

    const docRef = db.collection("explore_news").doc(cleanId);
    const snap = await docRef.get();
    let data = snap.exists ? snap.data() : null;

    // Check archive as well if not found in primary
    if (!data) {
      const archRef = db.collection("explore_news_archive").doc(cleanId);
      const archSnap = await archRef.get();
      if (archSnap.exists) {
        data = archSnap.data();
      }
    }

    if (data) {
      // 1. Delete associated images from ImageKit
      const images = (data.images || []) as any[];
      for (const img of images) {
        if (img.fileId) {
          try {
            await ik.deleteFile(img.fileId);
            logger.info(`[ADMIN_DELETE_IMAGEKIT] Deleted ImageKit fileId="${img.fileId}"`);
          } catch (e) {
            logger.warn(`[ADMIN_DELETE_IMAGEKIT_WARN] Failed to delete fileId="${img.fileId}":`, e);
          }
        }
      }

      // 2. Remove deduplication hashes in used_article_images
      try {
        const hashSnaps = await db
          .collection("used_article_images")
          .where("articleTitle", "==", data.title || "")
          .get();
        for (const hDoc of hashSnaps.docs) {
          await hDoc.ref.delete();
        }
      } catch (_) {}

      // 3. Delete from explore_news and explore_news_archive
      await docRef.delete();
      await db.collection("explore_news_archive").doc(cleanId).delete();
      deletedCount++;
    }
  }

  logger.info(`[ADMIN_ARTICLES_DELETED_PERMANENTLY] Purged ${deletedCount} articles.`);

  return {
    success: true,
    deletedCount,
    message: `${deletedCount} article(s) permanently deleted.`,
  };
});

/**
 * CALLABLE FUNCTION: Fetches deactivated articles for the Admin Activate/Recovery screen.
 */
export const getDeactivatedArticles = onCall(async (request) => {
  requireAdmin(request);

  const db = admin.firestore();
  const { limit = 50 } = request.data || {};

  const snap = await db
    .collection("explore_news")
    .where("status", "==", "deactivated")
    .limit(limit)
    .get();

  const articles = snap.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      articleId: doc.id,
      title: data.title || "",
      summary: data.summary || data.editorialSummary || "",
      category: data.category || "General",
      categoryId: data.categoryId || "general",
      source: data.source || "Mirror News",
      sourceUrl: data.sourceUrl || data.originalSourceUrl || "",
      coverImage: data.coverImage || (data.imageUrls && data.imageUrls[0]) || "",
      imageUrls: data.imageUrls || [],
      images: data.images || [],
      publishedAt: data.publishedAt?.toDate ? data.publishedAt.toDate().toISOString() : null,
      deactivatedAt: data.deactivatedAt?.toDate ? data.deactivatedAt.toDate().toISOString() : null,
      status: "deactivated",
    };
  });

  // Sort descending by deactivatedAt or publishedAt
  articles.sort((a, b) => {
    const aTime = a.deactivatedAt || a.publishedAt || "";
    const bTime = b.deactivatedAt || b.publishedAt || "";
    return bTime.localeCompare(aTime);
  });

  return {
    success: true,
    count: articles.length,
    articles,
  };
});

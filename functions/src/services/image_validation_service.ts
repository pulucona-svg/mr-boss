import * as admin from "firebase-admin";
import * as crypto from "crypto";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";
import { ImageSearchResult } from "../types/image_worker";
import { ArticleImageData } from "../types/explore";
import { ImageSafetyGateService } from "./image_safety_gate_service";

export class ImageValidationService {
  /**
   * Validates metadata candidate using ImageSafetyGateService.
   */
  public static isValidMetadata(cand: ImageSearchResult): boolean {
    const check = ImageSafetyGateService.filterCandidateMetadata(cand.imageUrl, cand.caption, cand.sourceDomain);
    return check.safe;
  }

  /**
   * Downloads and validates image buffer with ImageSafetyGateService.
   */
  public static async downloadAndValidateBuffer(
    url: string
  ): Promise<{ buffer: Buffer; contentType: string } | null> {
    const res = await ImageSafetyGateService.downloadAndValidateBuffer(url);
    if (res.success && res.buffer) {
      return { buffer: res.buffer, contentType: res.contentType || "image/jpeg" };
    }
    return null;
  }

  /**
   * Processes candidate metadata array: Downloads, validates, checks visual safety, checks SHA-256 duplicates, uploads to ImageKit, and formats article placeholders.
   */
  public static async processCandidateMetadata(
    db: admin.firestore.Firestore,
    ik: ImageKit,
    candidates: ImageSearchResult[],
    article: { title: string; content: string },
    targetCount: number = 5
  ): Promise<{
    images: ArticleImageData[];
    imageCount: number;
    updatedContent: string;
    imageSources: string[];
  }> {
    const selectedImages: ArticleImageData[] = [];
    const imageSources: string[] = [];
    const usedHashes = new Set<string>();

    for (const cand of candidates) {
      if (selectedImages.length >= targetCount) break;

      // 1. Metadata check (Stage A)
      if (!this.isValidMetadata(cand)) continue;

      // 2. Download buffer & validate magic bytes (Stage B)
      const dl = await this.downloadAndValidateBuffer(cand.imageUrl);
      if (!dl) continue;

      const { buffer, contentType } = dl;

      // 3. Visual Safety AI Classifier check (Stage C)
      const visualSafety = await ImageSafetyGateService.classifyImageVisualSafety(buffer, contentType, article.title);
      if (!visualSafety.isSafe) {
        logger.warn(`[IMAGE_VALIDATION_REJECT] Visual safety rejection for "${cand.imageUrl.slice(0, 80)}": ${visualSafety.reason}`);
        continue;
      }

      // 4. SHA-256 hash deduplication
      const hash = crypto.createHash("sha256").update(buffer).digest("hex");
      if (usedHashes.has(hash)) continue;
      usedHashes.add(hash);

      const isUsedInDb = await this.isImageHashUsedInDb(db, hash);
      if (isUsedInDb) continue;

      // 5. ImageKit Upload (Stage D)
      const uploadRes = await this.uploadToImageKit(
        ik,
        buffer,
        article.title,
        selectedImages.length + 1,
        contentType
      );
      if (!uploadRes) continue;

      const caption = cand.caption && cand.caption.length > 5 ? cand.caption : `${article.title} photo ${selectedImages.length + 1}`;

      selectedImages.push({
        position: selectedImages.length + 1,
        caption,
        imageUrl: uploadRes.url,
        sourceUrl: cand.sourceUrl || cand.imageUrl,
        sourceDomain: cand.sourceDomain || "web",
      });

      if (cand.sourceDomain && !imageSources.includes(cand.sourceDomain)) {
        imageSources.push(cand.sourceDomain);
      }

      await this.recordUsedImageInDb(db, hash, uploadRes.url, cand.imageUrl, article.title);
    }

    // Replace placeholders [IMAGE_1]...[IMAGE_5] in content
    let updatedContent = article.content || "";
    for (let i = 1; i <= targetCount; i++) {
      const placeholder = `[IMAGE_${i}]`;
      const imgData = selectedImages.find((img) => img.position === i);

      if (imgData) {
        const markdownImg = `\n\n![${imgData.caption}](${imgData.imageUrl})\n*${imgData.caption}*\n\n`;
        updatedContent = updatedContent.replace(placeholder, markdownImg);
      } else {
        updatedContent = updatedContent.replace(placeholder, "");
      }
    }

    return {
      images: selectedImages,
      imageCount: selectedImages.length,
      updatedContent,
      imageSources,
    };
  }

  private static async uploadToImageKit(
    ik: ImageKit,
    buffer: Buffer,
    articleTitle: string,
    position: number,
    contentType: string
  ): Promise<{ url: string; fileId: string } | null> {
    try {
      const base64Str = buffer.toString("base64");
      const cleanTitle = articleTitle.replace(/[^a-zA-Z0-9]/g, "_").toLowerCase().slice(0, 30);
      const ext = contentType.includes("png") ? "png" : contentType.includes("webp") ? "webp" : "jpg";
      const fileName = `article_${cleanTitle}_img_${position}_${Date.now()}.${ext}`;

      const res = await ik.upload({
        file: base64Str,
        fileName,
        folder: "NEWS_ARTICLES",
        useUniqueFileName: true,
      });

      if (res && res.url) {
        return { url: res.url, fileId: res.fileId };
      }
    } catch (e: any) {
      logger.error("[IMAGE_VALIDATION_UPLOAD_ERROR] ImageKit upload failed:", e);
    }
    return null;
  }

  private static async isImageHashUsedInDb(db: admin.firestore.Firestore, hash: string): Promise<boolean> {
    if (!hash) return false;
    const snap = await db.collection("used_article_images").where("imageHash", "==", hash).limit(1).get();
    return !snap.empty;
  }

  private static async recordUsedImageInDb(
    db: admin.firestore.Firestore,
    hash: string,
    imageKitUrl: string,
    originalUrl: string,
    articleTitle: string
  ): Promise<void> {
    await db.collection("used_article_images").add({
      imageHash: hash,
      imageKitUrl,
      originalUrl,
      articleTitle,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
}

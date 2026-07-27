import * as admin from "firebase-admin";
import * as crypto from "crypto";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";
import { ImageSearchResult } from "../types/image_worker";
import { ArticleImageData } from "../types/explore";

export class ImageValidationService {
  private static readonly EXCLUDED_TERMS = [
    "ai generated",
    "ai-generated",
    "dall-e",
    "dalle",
    "midjourney",
    "stable diffusion",
    "stablediffusion",
    "imagen",
    "logo",
    "watermark",
    "meme",
    "clipart",
    "icon",
    "vector",
    "illustration",
    "drawing",
    "cartoon",
    "symbol",
    "diagram",
    "chart",
    "poster",
    "badge",
    "stamp",
    "graphic",
    "coat_of_arms",
    "screenshot",
    "banner",
    "advertisement",
    "infographic",
    "stock placeholder",
  ];

  /**
   * Validates metadata candidate for AI exclusion terms and invalid extensions.
   */
  public static isValidMetadata(cand: ImageSearchResult): boolean {
    const combined = `${cand.imageUrl} ${cand.caption}`.toLowerCase();
    for (const term of this.EXCLUDED_TERMS) {
      if (combined.includes(term)) return false;
    }
    if (cand.imageUrl.endsWith(".svg") || cand.imageUrl.endsWith(".gif")) return false;
    return true;
  }

  /**
   * Downloads image buffer via HTTP, checking status 200, content-type, and magic bytes.
   */
  public static async downloadAndValidateBuffer(
    url: string
  ): Promise<{ buffer: Buffer; contentType: string } | null> {
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 7000);

      const res = await fetch(url, {
        headers: {
          "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        },
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (!res.ok) return null;

      const contentType = res.headers.get("content-type") || "image/jpeg";
      if (!contentType.includes("image/")) return null;

      const arrayBuf = await res.arrayBuffer();
      if (!arrayBuf || arrayBuf.byteLength < 5000) return null; // Min 5KB

      const buffer = Buffer.from(arrayBuf);

      // Verify JPEG/PNG/WEBP Magic Bytes
      const isJpeg = buffer[0] === 0xff && buffer[1] === 0xd8;
      const isPng = buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47;
      const isWebp = buffer.toString("utf8", 8, 12) === "WEBP";

      if (!isJpeg && !isPng && !isWebp) return null;

      return { buffer, contentType };
    } catch (e) {
      return null;
    }
  }

  /**
   * Processes candidate metadata array: Downloads, validates, checks SHA-256 duplicates, uploads to ImageKit, and formats article placeholders.
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

      // 1. Metadata check
      if (!this.isValidMetadata(cand)) continue;

      // 2. Download buffer & validate magic bytes
      const dl = await this.downloadAndValidateBuffer(cand.imageUrl);
      if (!dl) continue;

      const { buffer, contentType } = dl;

      // 3. SHA-256 hash deduplication
      const hash = crypto.createHash("sha256").update(buffer).digest("hex");
      if (usedHashes.has(hash)) continue;
      usedHashes.add(hash);

      const isUsedInDb = await this.isImageHashUsedInDb(db, hash);
      if (isUsedInDb) continue;

      // 4. ImageKit Upload
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

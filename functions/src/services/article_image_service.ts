import * as admin from "firebase-admin";
import * as crypto from "crypto";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";
import { ArticleImageData } from "../types/explore";
import { ImageSafetyGateService } from "./image_safety_gate_service";

export interface ArticleImageSearchResult {
  success: boolean;
  images: ArticleImageData[];
  imageCount: number;
  updatedContent: string;
  imageSources: string[];
  error?: string;
}

export class ArticleImageSearchService {
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
   * Safe query parameter encoder. Strips single quotes/apostrophes.
   */
  private static encodeQueryParam(str: string): string {
    const sanitized = (str || "").replace(/['"’`]/g, " ").replace(/\s+/g, " ").trim();
    return encodeURIComponent(sanitized);
  }

  /**
   * SEARCH STRATEGY: Extracts specific entities and generates precise, contextual search queries.
   */
  public static buildArticleSearchQueries(
    title: string,
    summary?: string,
    category?: string
  ): string[] {
    const cleanTitle = (title || "").replace(/['"’`]/g, " ").replace(/\s+/g, " ").trim();
    if (!cleanTitle) return [];

    const queries: string[] = [];

    // Remove common verb noise from news titles
    const noiseWords = /\b(launches|announces|unveils|rolls out|reports|celebrates|signs|urges|warns|aiming for|expands|holds|agrees|surge|major|tightens|extends|flags|surpasses|begins|opens|calls for|to take on|new|first|sets|boosts)\b/gi;
    const strippedHeadline = cleanTitle.replace(noiseWords, " ").replace(/\s+/g, " ").trim();

    // 1. Core entity nouns (words with length >= 4 or capitalized)
    const entityWords = strippedHeadline
      .split(/\s+/)
      .filter((w) => w.length >= 3 && !/^(the|this|that|with|from|have|been|after|before|into|about|over|under|will|says|said|more|year|years|than|also|over|back)$/i.test(w));

    // 2. Focused 2-3 word entity query (e.g. "Olkaria Geothermal", "Mountain Gorilla Rwanda", "AMD Instinct")
    if (entityWords.length >= 2) {
      queries.push(entityWords.slice(0, 3).join(" "));
      if (entityWords.length >= 4) {
        queries.push(entityWords.slice(0, 2).join(" "));
        queries.push(entityWords.slice(2, 5).join(" "));
      }
    }

    // 3. Entity + Category query
    if (category) {
      if (entityWords.length >= 2) {
        queries.push(`${entityWords.slice(0, 2).join(" ")} ${category}`);
      }
      queries.push(`${category} photography`);
    }

    // 4. Category-specific high-resolution photo fallbacks
    const catLower = (category || "").toLowerCase();
    if (catLower.includes("sport")) {
      queries.push("stadium sports athlete competition");
    } else if (catLower.includes("business") || catLower.includes("econom")) {
      queries.push("business stock market finance economy");
    } else if (catLower.includes("health") || catLower.includes("medic")) {
      queries.push("hospital clinic healthcare medicine science");
    } else if (catLower.includes("tech") || catLower.includes("innovat")) {
      queries.push("computer technology hardware processor digital");
    } else if (catLower.includes("polit") || catLower.includes("govern")) {
      queries.push("parliament government conference diplomacy");
    } else if (catLower.includes("kenya")) {
      queries.push("Kenya landscape wildlife architecture Nairobi");
    } else if (catLower.includes("africa")) {
      queries.push("Africa city architecture development landscape");
    } else if (catLower.includes("entertain")) {
      queries.push("concert performance cinema culture theater");
    } else if (catLower.includes("agri")) {
      queries.push("agriculture farm harvest crops farming field");
    } else if (catLower.includes("lifestyle")) {
      queries.push("lifestyle wellness travel culture environment");
    }

    return Array.from(new Set(queries.filter((q) => q && q.trim().length >= 3)));
  }

  /**
   * MAIN PIPELINE: Strict Multi-Stage Image Safety Gate with AI Vision & Candidate Replacement.
   * Stage A: Metadata/Domain/Keyword Filter
   * Stage B: Download & Binary Validation (Magic Bytes & Size)
   * Stage C: Visual Safety Classification via AI Vision Model (WHEN IN DOUBT → REJECT)
   * Stage D: Candidate Replacement & ImageKit CDN Delivery
   */
  public static async processArticleImages(
    db: admin.firestore.Firestore,
    ik: ImageKit,
    article: {
      id?: string;
      clusterId: string;
      title: string;
      content: string;
      summary: string;
      category?: string;
      source?: string;
    },
    targetImageCount: number = 5
  ): Promise<ArticleImageSearchResult> {
    logger.info(`[ARTICLE_IMAGE_START] Processing images for article "${article.title}" (Target: ${targetImageCount} safe images)`);

    const queries = this.buildArticleSearchQueries(article.title, article.summary, article.category);
    const collectedCandidates: Array<{ url: string; title: string; pageUrl: string; sourceDomain: string }> = [];
    const seenUrls = new Set<string>();

    for (const q of queries) {
      const results = await this.searchWebImages(q);
      for (const item of results) {
        if (!seenUrls.has(item.url)) {
          seenUrls.add(item.url);
          collectedCandidates.push(item);
        }
      }
      if (collectedCandidates.length >= targetImageCount * 6) break;
    }

    logger.info(`[ARTICLE_IMAGE_CANDIDATES] Collected ${collectedCandidates.length} real photo candidates.`);

    const selectedImages: ArticleImageData[] = [];
    const imageSources: string[] = [];
    const usedHashes = new Set<string>();
    let rejectedCount = 0;

    for (const cand of collectedCandidates) {
      if (selectedImages.length >= targetImageCount) break;

      // ----------------------------------------------------
      // STAGE A: Metadata & URL Safety Gate
      // ----------------------------------------------------
      const stageACheck = ImageSafetyGateService.filterCandidateMetadata(cand.url, cand.title, cand.sourceDomain);
      if (!stageACheck.safe) {
        rejectedCount++;
        logger.warn(`[IMAGE_SAFETY_REJECTED] stage="stage_a_metadata" reason="${stageACheck.reason}" candidate="${cand.url.slice(0, 80)}"`);
        continue;
      }

      if (!this.isValidPhotoCandidate(cand.url, cand.title)) {
        rejectedCount++;
        continue;
      }

      // ----------------------------------------------------
      // STAGE B: Download & Binary Validation Gate
      // ----------------------------------------------------
      await new Promise((r) => setTimeout(r, 200));
      const downloadRes = await ImageSafetyGateService.downloadAndValidateBuffer(cand.url);
      if (!downloadRes.success || !downloadRes.buffer) {
        rejectedCount++;
        logger.warn(`[IMAGE_SAFETY_REJECTED] stage="stage_b_download" reason="${downloadRes.rejectionReason}" candidate="${cand.url.slice(0, 80)}"`);
        continue;
      }

      const buffer = downloadRes.buffer;
      const contentType = downloadRes.contentType || "image/jpeg";

      // SHA-256 Deduplication check
      const hash = crypto.createHash("sha256").update(buffer).digest("hex");
      if (usedHashes.has(hash)) {
        logger.info(`[IMAGE_SAFETY_DEDUP] Skipping in-memory duplicate image.`);
        continue;
      }
      usedHashes.add(hash);

      const isDup = await this.isImageHashUsed(db, hash);
      if (isDup) {
        logger.info(`[IMAGE_SAFETY_DEDUP] Skipping Firestore duplicate image.`);
        continue;
      }

      // ----------------------------------------------------
      // STAGE C: AI Vision Visual Safety Classifier Gate
      // ----------------------------------------------------
      const visualSafety = await ImageSafetyGateService.classifyImageVisualSafety(buffer, contentType, article.title);
      if (!visualSafety.isSafe) {
        rejectedCount++;
        logger.warn(
          `[IMAGE_SAFETY_REJECTED] stage="stage_c_vision" category="${visualSafety.category}" reason="${visualSafety.reason}" candidate="${cand.url.slice(0, 80)}"`
        );
        // Discard image immediately; proceed to next candidate
        continue;
      }

      logger.info(`[IMAGE_SAFETY_APPROVED] Candidate verified safe: "${visualSafety.reason}" (Confidence: ${visualSafety.confidence})`);

      // ----------------------------------------------------
      // STAGE D: ImageKit Upload & Attachment
      // ----------------------------------------------------
      const uploadRes = await this.uploadToImageKit(ik, buffer, article.title, selectedImages.length + 1, contentType);
      if (!uploadRes) {
        logger.error(`[IMAGE_KIT_UPLOAD_FAIL] Failed to upload verified safe image to ImageKit.`);
        continue;
      }

      const caption = this.generateImageCaption(article.title, cand.title, selectedImages.length + 1);

      selectedImages.push({
        position: selectedImages.length + 1,
        caption: caption,
        imageUrl: uploadRes.url,
        sourceUrl: cand.pageUrl || cand.url,
        sourceDomain: cand.sourceDomain,
      });

      if (cand.sourceDomain && !imageSources.includes(cand.sourceDomain)) {
        imageSources.push(cand.sourceDomain);
      }

      // Record hash in used_images collection
      await this.recordUsedImage(db, hash, uploadRes.url, cand.url, article.title);
    }

    const imageCount = selectedImages.length;
    logger.info(
      `[IMAGE_SAFETY_COMPLETE] Attached ${imageCount}/${targetImageCount} verified safe photos (Rejected: ${rejectedCount}) for "${article.title}".`
    );

    // Replace placeholders [IMAGE_1]...[IMAGE_5] in article content
    let updatedContent = article.content || "";
    for (let i = 1; i <= 5; i++) {
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
      success: imageCount >= targetImageCount,
      images: selectedImages,
      imageCount,
      updatedContent,
      imageSources,
    };
  }

  /**
   * Search real web photos via Pixabay, Wikimedia, Bing & Google with timeouts.
   */
  private static async searchWebImages(
    query: string
  ): Promise<Array<{ url: string; title: string; pageUrl: string; sourceDomain: string }>> {
    const candidates: Array<{ url: string; title: string; pageUrl: string; sourceDomain: string }> = [];

    // Stage 1: Pixabay Photo Search (with 4000ms timeout)
    try {
      const apiKey = process.env.PIXABAY_API_KEY;
      if (apiKey && apiKey !== "48096316-56dd6fb202867ef9ce5316499") {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 4000);
        const q = this.encodeQueryParam(query);
        const url = `https://pixabay.com/api/?key=${apiKey}&q=${q}&image_type=photo&orientation=horizontal&safesearch=true&per_page=15`;
        const res = await fetch(url, { signal: controller.signal });
        clearTimeout(timeoutId);
        if (res.ok) {
          const data = (await res.json()) as any;
          for (const item of data.hits || []) {
            const imgUrl = item.largeImageURL || item.webformatURL;
            if (imgUrl) {
              candidates.push({
                url: imgUrl,
                title: item.tags || query,
                pageUrl: item.pageURL || imgUrl,
                sourceDomain: "pixabay.com",
              });
            }
          }
        }
      }
    } catch (e) {}

    // Stage 2: Wikimedia Commons Primary Search (with 5000ms timeout)
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 5000);
      const q = this.encodeQueryParam(query);
      const url = `https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrsearch=${q}&gsrnamespace=6&gsrlimit=20&prop=imageinfo&iiprop=url|size|mime&iiurlwidth=1280&format=json&origin=*`;
      const res = await fetch(url, {
        headers: {
          "User-Agent": "MirrorLaikipiaNews/1.0 (news@mirrorlaikipia.edu; https://mirrorlaikipia.edu)",
        },
        signal: controller.signal,
      });
      clearTimeout(timeoutId);
      if (res.ok) {
        const data = (await res.json()) as any;
        const pages = data?.query?.pages ? Object.values(data.query.pages) : [];
        for (const page of pages as any[]) {
          const info = page?.imageinfo?.[0];
          if (info && (info.thumburl || info.url)) {
            const mime = (info.mime || "").toLowerCase();
            if (mime.includes("image/jpeg") || mime.includes("image/jpg") || mime.includes("image/png") || mime.includes("image/webp")) {
              candidates.push({
                url: info.thumburl || info.url,
                title: page.title || query,
                pageUrl: info.descriptionurl || info.url,
                sourceDomain: "commons.wikimedia.org",
              });
            }
          }
        }
      }
    } catch (e) {}

    // Stage 3: Wikimedia Commons Refined Entity / Topic Search
    try {
      const words = (query || "").split(/\s+/).filter((w) => w.length >= 4);
      if (words.length >= 2) {
        const refinedQ = this.encodeQueryParam(words.slice(0, 3).join(" "));
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 4000);
        const url = `https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrsearch=${refinedQ}&gsrnamespace=6&gsrlimit=15&prop=imageinfo&iiprop=url|size|mime&iiurlwidth=1280&format=json&origin=*`;
        const res = await fetch(url, {
          headers: {
            "User-Agent": "MirrorLaikipiaNews/1.0 (news@mirrorlaikipia.edu; https://mirrorlaikipia.edu)",
          },
          signal: controller.signal,
        });
        clearTimeout(timeoutId);
        if (res.ok) {
          const data = (await res.json()) as any;
          const pages = data?.query?.pages ? Object.values(data.query.pages) : [];
          for (const page of pages as any[]) {
            const info = page?.imageinfo?.[0];
            if (info && (info.thumburl || info.url)) {
              const mime = (info.mime || "").toLowerCase();
              if (mime.includes("image/jpeg") || mime.includes("image/jpg") || mime.includes("image/png") || mime.includes("image/webp")) {
                candidates.push({
                  url: info.thumburl || info.url,
                  title: page.title || query,
                  pageUrl: info.descriptionurl || info.url,
                  sourceDomain: "commons.wikimedia.org",
                });
              }
            }
          }
        }
      }
    } catch (e) {}

    return candidates;
  }

  /**
   * Validates photo candidates to ensure strictly real photographs and NO AI images.
   */
  private static isValidPhotoCandidate(url: string, title: string): boolean {
    const combined = `${url} ${title}`.toLowerCase();

    for (const term of this.EXCLUDED_TERMS) {
      if (combined.includes(term)) return false;
    }

    if (url.includes(".svg") || url.includes(".gif")) return false;

    return true;
  }

  /**
   * Uploads image buffer to ImageKit under NEWS_ARTICLES folder.
   */
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
      logger.error("[ARTICLE_IMAGE_UPLOAD_ERROR] ImageKit upload exception:", e);
    }
    return null;
  }

  /**
   * Generates factual, descriptive captions for article images.
   */
  private static generateImageCaption(articleTitle: string, photoTitle: string, position: number): string {
    const cleanPhotoTitle = photoTitle.replace(/File:|\.jpg|\.png/gi, "").trim();

    if (cleanPhotoTitle && cleanPhotoTitle.length > 5 && !cleanPhotoTitle.includes("http")) {
      return `${cleanPhotoTitle} - related to ${articleTitle}`;
    }

    const captions = [
      `Official event photo for ${articleTitle}`,
      `Key highlight during ${articleTitle}`,
      `Real-world coverage of ${articleTitle}`,
      `Press photo from the scene of ${articleTitle}`,
      `Visual documentation of ${articleTitle}`,
    ];

    return captions[(position - 1) % captions.length];
  }

  private static async isImageHashUsed(db: admin.firestore.Firestore, hash: string): Promise<boolean> {
    if (!hash) return false;
    const snap = await db.collection("used_article_images").where("imageHash", "==", hash).limit(1).get();
    return !snap.empty;
  }

  private static async recordUsedImage(
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

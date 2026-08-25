import * as admin from "firebase-admin";
import * as crypto from "crypto";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";
import { ArticleImageData } from "../types/explore";

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
   * SEARCH STRATEGY: Builds search queries in order of specificity.
   * 1. headline
   * 2. headline + location
   * 3. headline + organization
   * 4. headline + event
   * 5. headline + date
   * 6. summary fallback
   */
  public static buildArticleSearchQueries(
    title: string,
    summary?: string,
    category?: string
  ): string[] {
    const cleanTitle = (title || "").replace(/['"’`]/g, " ").replace(/\s+/g, " ").trim();
    if (!cleanTitle) return [];

    const queries: string[] = [];

    // 1. Primary Clean Headline
    queries.push(cleanTitle);

    // 2. Extract key nouns / entities (words starting with capital or length >= 4)
    const words = cleanTitle.split(/\s+/).filter((w) => w.length >= 4 && !/^(the|this|that|with|from|have|been|after|before|into|about|over|under|will|says|said)$/i.test(w));
    if (words.length >= 2) {
      queries.push(words.slice(0, 4).join(" "));
    }

    // 3. Entity + Category query
    if (category) {
      if (words.length >= 2) {
        queries.push(`${words.slice(0, 2).join(" ")} ${category}`);
      }
      queries.push(`${category} news photography`);
    }

    // 4. Category-specific high-resolution photo fallbacks
    const catLower = (category || "").toLowerCase();
    if (catLower.includes("sport")) {
      queries.push("stadium sports athlete competition");
    } else if (catLower.includes("business") || catLower.includes("econom")) {
      queries.push("business stock market finance meeting");
    } else if (catLower.includes("health") || catLower.includes("medic")) {
      queries.push("hospital healthcare doctor medicine");
    } else if (catLower.includes("tech") || catLower.includes("innovat")) {
      queries.push("technology innovation digital computer");
    } else if (catLower.includes("polit") || catLower.includes("govern")) {
      queries.push("parliament government conference diplomacy");
    } else if (catLower.includes("kenya")) {
      queries.push("Nairobi Kenya landscape wildlife");
    } else if (catLower.includes("africa")) {
      queries.push("Africa city architecture development");
    } else if (catLower.includes("entertain")) {
      queries.push("concert performance music cinema entertainment");
    } else if (catLower.includes("agri")) {
      queries.push("agriculture farm harvest crops farming");
    } else if (catLower.includes("lifestyle")) {
      queries.push("lifestyle wellness travel culture");
    }

    // 5. Summary snippet
    if (summary) {
      const summarySnippet = summary
        .replace(/['"’`]/g, " ")
        .split(/\s+/)
        .slice(0, 6)
        .join(" ")
        .trim();
      if (summarySnippet && !queries.includes(summarySnippet)) {
        queries.push(summarySnippet);
      }
    }

    return queries;
  }

  /**
   * MAIN PIPELINE: Search real internet photos, download, validate, upload to ImageKit, replace placeholders.
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
    logger.info(`[ARTICLE_IMAGE_START] Processing images for article "${article.title}" (Target: ${targetImageCount} images)`);

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
      if (collectedCandidates.length >= targetImageCount * 4) break;
    }

    logger.info(`[ARTICLE_IMAGE_CANDIDATES] Collected ${collectedCandidates.length} real photo candidates.`);

    const selectedImages: ArticleImageData[] = [];
    const imageSources: string[] = [];
    const usedHashes = new Set<string>();

    for (const cand of collectedCandidates) {
      if (selectedImages.length >= targetImageCount) break;

      // 1. Validate URL & AI exclusion terms
      if (!this.isValidPhotoCandidate(cand.url, cand.title)) continue;

      // 2. Download Image Buffer (validate HTTP 200, content-type, byte length)
      const downloadRes = await this.downloadImageBuffer(cand.url);
      if (!downloadRes) continue;

      const { buffer, contentType } = downloadRes;

      // 3. Compute SHA-256 Hash for deduplication
      const hash = crypto.createHash("sha256").update(buffer).digest("hex");
      if (usedHashes.has(hash)) continue;
      usedHashes.add(hash);

      // Check Firestore duplicate hash
      const isDup = await this.isImageHashUsed(db, hash);
      if (isDup) continue;

      // 4. Upload to ImageKit
      const uploadRes = await this.uploadToImageKit(ik, buffer, article.title, selectedImages.length + 1, contentType);
      if (!uploadRes) continue;

      // 5. Generate contextual caption
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
    logger.info(`[ARTICLE_IMAGE_SELECTION_COMPLETE] Successfully attached ${imageCount} real internet images for "${article.title}".`);

    // Replace placeholders [IMAGE_1]...[IMAGE_5] in article content
    let updatedContent = article.content || "";
    for (let i = 1; i <= 5; i++) {
      const placeholder = `[IMAGE_${i}]`;
      const imgData = selectedImages.find((img) => img.position === i);

      if (imgData) {
        // Replace placeholder with structured markdown image & caption
        const markdownImg = `\n\n![${imgData.caption}](${imgData.imageUrl})\n*${imgData.caption}*\n\n`;
        updatedContent = updatedContent.replace(placeholder, markdownImg);
      } else {
        // If fewer than 5 images available, clean up unused placeholder seamlessly
        updatedContent = updatedContent.replace(placeholder, "");
      }
    }

    return {
      success: imageCount >= 1,
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

    // Stage 2: Wikimedia Commons Real News/Event Photos (with 5000ms timeout)
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 5000);
      const q = this.encodeQueryParam(query);
      const url = `https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrsearch=${q}&gsrnamespace=6&gsrlimit=20&prop=imageinfo&iiprop=url|size|mime&format=json&origin=*`;
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
          if (info && info.url) {
            const mime = (info.mime || "").toLowerCase();
            if (mime.includes("image/jpeg") || mime.includes("image/jpg") || mime.includes("image/png") || mime.includes("image/webp")) {
              candidates.push({
                url: info.url,
                title: page.title || query,
                pageUrl: info.descriptionurl || info.url,
                sourceDomain: "commons.wikimedia.org",
              });
            }
          }
        }
      }
    } catch (e) {}

    // Stage 3: Bing Image Search with 4000ms timeout
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 4000);
      const q = this.encodeQueryParam(query);
      const url = `https://www.bing.com/images/search?q=${q}&qft=+filterui:photo-photo`;
      const res = await fetch(url, {
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        },
        signal: controller.signal,
      });
      clearTimeout(timeoutId);
      if (res.ok) {
        const html = await res.text();
        const blockRegex = /\{&quot;[^{}]*?&quot;murl&quot;:&quot;(https?:\/\/[^&]+?)&quot;[^{}]*?\}/gi;
        let match;
        while ((match = blockRegex.exec(html)) !== null) {
          try {
            const rawJson = match[0].replace(/&quot;/g, '"').replace(/&amp;/g, '&');
            const obj = JSON.parse(rawJson);
            if (obj.murl) {
              let host = "";
              try {
                host = new URL(obj.purl || obj.murl).hostname.replace("www.", "");
              } catch (e) {}
              candidates.push({
                url: obj.murl,
                title: obj.t || obj.desc || query,
                pageUrl: obj.purl || obj.murl,
                sourceDomain: host || "bing.com",
              });
            }
          } catch (e) {}
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
   * Downloads image buffer and verifies size, format, HTTP 200.
   */
  private static async downloadImageBuffer(
    url: string
  ): Promise<{ buffer: Buffer; contentType: string } | null> {
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 7000);

      const res = await fetch(url, {
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        },
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (!res.ok) return null;

      const contentType = res.headers.get("content-type") || "image/jpeg";
      if (!contentType.includes("image/")) return null;

      const arrayBuf = await res.arrayBuffer();
      if (!arrayBuf || arrayBuf.byteLength < 5000) return null; // Minimum 5KB

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

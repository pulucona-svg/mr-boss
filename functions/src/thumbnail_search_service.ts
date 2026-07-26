import * as admin from "firebase-admin";
import * as crypto from "crypto";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";

export interface ImageCandidate {
  url: string;
  pageUrl: string;
  width: number;
  height: number;
  sourceWebsite: string;
  title: string;
  altText: string;
}

export interface ThumbnailSearchResult {
  success: boolean;
  imageKitUrl?: string;
  imageKitFileId?: string;
  originalSource?: string;
  originalWebsite?: string;
  imageHash?: string;
  reason?: string;
  score?: number;
  error?: string;
}

export class ThumbnailSearchService {
  private static readonly EXCLUDED_TERMS = [
    "logo",
    "watermark",
    "meme",
    "clipart",
    "icon",
    "text",
    "vector",
    "illustration",
    "drawing",
    "cartoon",
    "symbol",
    "sign",
    "flag",
    "map",
    "diagram",
    "chart",
    "poster",
    "badge",
    "stamp",
    "graphic",
    "coat_of_arms",
    "seal",
    "screenshot",
    "banner",
    "advertisement",
    "infographic",
    "structure",
  ];

  /**
   * Encodes query string parameters for URLs, safely stripping single quotes/apostrophes
   * to prevent HTTP 400 Bad Request responses from search engine APIs (e.g. Pixabay).
   */
  private static encodeQueryParam(str: string): string {
    const sanitized = (str || "").replace(/['"’`]/g, " ").replace(/\s+/g, " ").trim();
    return encodeURIComponent(sanitized);
  }

  /**
   * STEP 1 - Build search queries based on rules.
   * Handles punctuation/apostrophes gracefully (e.g. "Intro' to Quantum Chemistry").
   */
  public static buildSearchQueries(unitName: string, materialType?: string, catType?: string): string[] {
    const cleanUnit = (unitName || "").trim();
    if (!cleanUnit) return [];

    const queries: string[] = [];
    const categoryStr = `${materialType || ""} ${catType || ""}`.toLowerCase();
    const isPracticalCategory =
      categoryStr.includes("practical") ||
      categoryStr.includes("lab") ||
      categoryStr.includes("laboratory") ||
      categoryStr.includes("field practical");

    // Cleaned unit name without apostrophes/punctuation
    const noPunctuation = cleanUnit.replace(/['"’`]/g, " ").replace(/\s+/g, " ").trim();

    // Core topic (extracting prefixes like Intro to, Introduction to)
    const coreTopic = cleanUnit
      .replace(/^(Intro'|Intro|Introduction|Fundamentals|Principles|Basic|Advanced|Applied)\s+(to|of)?\s*/i, "")
      .replace(/['"’`]/g, " ")
      .replace(/\s+/g, " ")
      .trim();

    if (isPracticalCategory) {
      queries.push(`${noPunctuation} laboratory`);
      queries.push(`${noPunctuation} practical`);
      queries.push(`${noPunctuation} experiment`);
    } else {
      queries.push(noPunctuation);
    }

    if (coreTopic && coreTopic.length >= 3 && !queries.includes(coreTopic)) {
      queries.push(coreTopic);
    }

    if (cleanUnit !== noPunctuation && !queries.includes(cleanUnit)) {
      queries.push(cleanUnit);
    }

    return queries;
  }

  /**
   * Main Entry Point: Search Internet -> Candidate Collection -> Gemini AI Ranking -> Download -> Duplicate Check -> ImageKit Upload
   */
  public static async searchAndUploadThumbnail(
    db: admin.firestore.Firestore,
    ik: ImageKit,
    unitName: string,
    materialType?: string,
    catType?: string,
    geminiApiKey?: string
  ): Promise<ThumbnailSearchResult> {
    const queries = this.buildSearchQueries(unitName, materialType, catType);
    if (queries.length === 0) {
      return { success: false, error: "Missing or invalid unitName" };
    }

    logger.info(`[THUMBNAIL_PIPELINE_START] Unit: "${unitName}", Queries: ${JSON.stringify(queries)}`);

    let candidates: ImageCandidate[] = [];
    for (const query of queries) {
      candidates = await this.collectCandidates(query);
      if (candidates.length > 0) {
        logger.info(`[CANDIDATE_COLLECTION_SUCCESS] Query "${query}" collected ${candidates.length} candidate images.`);
        break;
      }
    }

    if (candidates.length === 0) {
      return { success: false, error: `Zero search candidate images found for Unit "${unitName}"` };
    }

    const candidatePool = candidates.slice(0, 50);

    // Gemini AI Ranking
    const rankedCandidates = await this.rankCandidatesWithGemini(candidatePool, unitName, materialType, geminiApiKey);

    // Download, Validate, Duplicate Detection, ImageKit Upload
    return await this.processRankedCandidates(db, ik, rankedCandidates, unitName);
  }

  /**
   * Collect candidate metadata using Stage 3 (Pixabay) and Stage 4 (Wikimedia), with Google/Bing fallbacks.
   */
  private static async collectCandidates(query: string): Promise<ImageCandidate[]> {
    // Stage 3: Pixabay Search
    const pixabayCandidates = await this.searchPixabayImages(query);
    if (pixabayCandidates.length > 0) {
      return pixabayCandidates;
    }

    // Stage 4: Wikimedia Search if Pixabay returns zero images
    logger.info(`[WIKIMEDIA_FALLBACK_TRIGGER] Pixabay returned 0 candidates for query "${query}". Triggering Stage 4: Wikimedia Search.`);
    const wikimediaCandidates = await this.searchWikimediaImages(query);
    if (wikimediaCandidates.length > 0) {
      return wikimediaCandidates;
    }

    // Extra Fallback: Google / Bing search engines
    logger.info(`[SEARCH_FALLBACK_ENGINES] Pixabay and Wikimedia yielded 0 images for "${query}". Checking Google/Bing...`);
    const googleCandidates = await this.searchGoogleImages(query);
    if (googleCandidates.length > 0) {
      return googleCandidates;
    }

    const bingCandidates = await this.searchBingImages(query);
    return bingCandidates;
  }

  /**
   * STAGE 3: Pixabay Image Search
   */
  private static async searchPixabayImages(query: string): Promise<ImageCandidate[]> {
    const apiKey = process.env.PIXABAY_API_KEY || "48096316-56dd6fb202867ef9ce5316499";
    const encodedQuery = this.encodeQueryParam(query);
    const requestUrl = `https://pixabay.com/api/?key=${apiKey}&q=${encodedQuery}&image_type=photo&orientation=horizontal&safesearch=true&per_page=20`;

    logger.info(`[PIXABAY_SEARCH] Query: "${query}"`);
    logger.info(`[PIXABAY_SEARCH] request URL: ${requestUrl}`);

    try {
      const res = await fetch(requestUrl);
      const httpStatus = res.status;
      const rawText = await res.text();
      const bodyLength = rawText.length;

      let hitsCount = 0;
      const candidates: ImageCandidate[] = [];

      if (res.ok) {
        const data = JSON.parse(rawText);
        const hits = data.hits || [];
        hitsCount = hits.length;

        for (const item of hits) {
          const imgUrl = item.largeImageURL || item.webformatURL;
          if (imgUrl) {
            candidates.push({
              url: imgUrl,
              pageUrl: item.pageURL || imgUrl,
              width: Number(item.imageWidth || 1920),
              height: Number(item.imageHeight || 1080),
              sourceWebsite: "pixabay.com",
              title: item.tags || query,
              altText: item.tags || query,
            });
          }
        }
      } else {
        logger.warn(`[PIXABAY_HTTP_WARN] Pixabay HTTP ${httpStatus}: ${rawText}`);
      }

      logger.info(`[PIXABAY_SEARCH] HTTP status: ${httpStatus}, response body length: ${bodyLength}, number of hits: ${hitsCount}`);
      return candidates;
    } catch (err: any) {
      logger.error(`[PIXABAY_SEARCH_ERROR] Pixabay query failed for "${query}":`, err);
      if (err.stack) logger.error(err.stack);
      return [];
    }
  }

  /**
   * STAGE 4: Wikimedia Commons Search
   */
  private static async searchWikimediaImages(query: string, retryCount = 0): Promise<ImageCandidate[]> {
    const encodedQuery = this.encodeQueryParam(query);
    const requestUrl = `https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrsearch=${encodedQuery}&gsrnamespace=6&gsrlimit=20&prop=imageinfo&iiprop=url|size|mime&format=json&origin=*`;

    logger.info(`[WIKIMEDIA_SEARCH] Query: "${query}"`);
    logger.info(`[WIKIMEDIA_SEARCH] request URL: ${requestUrl}`);

    try {
      const res = await fetch(requestUrl, {
        headers: {
          "User-Agent": "MirrorLaikipiaApp/1.0 (contact@mirrorlaikipia.edu; https://mirrorlaikipia.edu)",
        },
      });

      if (res.status === 429 && retryCount < 2) {
        logger.warn(`[WIKIMEDIA_RETRY_429] Rate limited. Retrying ${retryCount + 1}...`);
        await new Promise((resolve) => setTimeout(resolve, 1000));
        return this.searchWikimediaImages(query, retryCount + 1);
      }

      const httpStatus = res.status;
      const rawText = await res.text();
      const bodyLength = rawText.length;

      let hitsCount = 0;
      const candidates: ImageCandidate[] = [];

      if (res.ok) {
        const data = JSON.parse(rawText);
        const pages = data?.query?.pages ? Object.values(data.query.pages) : [];
        hitsCount = pages.length;

        for (const page of pages as any[]) {
          const info = page?.imageinfo?.[0];
          if (info && info.url) {
            const mime = (info.mime || "").toLowerCase();
            if (mime.includes("image/jpeg") || mime.includes("image/jpg") || mime.includes("image/png") || mime.includes("image/webp")) {
              candidates.push({
                url: info.url,
                pageUrl: info.descriptionurl || info.url,
                width: Number(info.width || 1920),
                height: Number(info.height || 1080),
                sourceWebsite: "commons.wikimedia.org",
                title: page.title || query,
                altText: page.title || query,
              });
            }
          }
        }
      }

      logger.info(`[WIKIMEDIA_SEARCH] HTTP status: ${httpStatus}, response body length: ${bodyLength}, number of hits: ${hitsCount}`);
      return candidates;
    } catch (err: any) {
      logger.error(`[WIKIMEDIA_SEARCH_ERROR] Wikimedia query failed for "${query}":`, err);
      if (err.stack) logger.error(err.stack);
      return [];
    }
  }

  /**
   * STAGE 5: Download image bytes with explicit logging and HTTP 429 retry logic
   */
  private static async downloadImageBuffer(url: string, retryCount = 0): Promise<{ buffer: Buffer; httpStatus: number; byteLength: number } | null> {
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 8000);

      const headers: Record<string, string> = {
        "User-Agent": url.includes("wikimedia.org")
          ? "MirrorLaikipiaApp/1.0 (contact@mirrorlaikipia.edu; https://mirrorlaikipia.edu)"
          : "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
      };

      const res = await fetch(url, {
        headers: headers,
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      const httpStatus = res.status;
      if (httpStatus === 429 && retryCount < 2) {
        logger.warn(`[DOWNLOAD_RETRY_429] HTTP 429 for ${url}. Pausing 500ms before retry ${retryCount + 1}...`);
        await new Promise((resolve) => setTimeout(resolve, 500));
        return this.downloadImageBuffer(url, retryCount + 1);
      }

      if (!res.ok) {
        logger.warn(`[DOWNLOAD_FAILED] Candidate Image URL: ${url}, HTTP status: ${httpStatus}`);
        return null;
      }

      const arrayBuffer = await res.arrayBuffer();
      if (!arrayBuffer || arrayBuffer.byteLength < 5000) {
        logger.warn(`[DOWNLOAD_FAILED] Candidate Image URL: ${url}, Small buffer size: ${arrayBuffer?.byteLength || 0} bytes`);
        return null;
      }

      const buffer = Buffer.from(arrayBuffer);
      logger.info(`[DOWNLOAD_SUCCESS] Candidate Image URL: ${url}, HTTP status: ${httpStatus}, byte size: ${buffer.byteLength} bytes`);
      return { buffer, httpStatus, byteLength: buffer.byteLength };
    } catch (err: any) {
      logger.error(`[DOWNLOAD_EXCEPTION] Error downloading image from ${url}:`, err);
      if (err.stack) logger.error(err.stack);
      return null;
    }
  }

  /**
   * Google Custom Search
   */
  private static async searchGoogleImages(query: string): Promise<ImageCandidate[]> {
    const apiKey = process.env.GOOGLE_SEARCH_API_KEY;
    const cseId = process.env.GOOGLE_CSE_ID;

    if (apiKey && cseId) {
      try {
        const encodedQuery = this.encodeQueryParam(query);
        const url = `https://www.googleapis.com/customsearch/v1?key=${apiKey}&cx=${cseId}&searchType=image&q=${encodedQuery}&num=10&imgSize=large&imgType=photo&imgAspect=wide`;
        const res = await fetch(url);
        if (res.ok) {
          const data = (await res.json()) as any;
          const items = data.items || [];
          return items.map((item: any) => {
            let host = "";
            try {
              host = new URL(item.image.contextLink || item.link).hostname.replace("www.", "");
            } catch (e) {}

            return {
              url: item.link,
              pageUrl: item.image.contextLink || item.link,
              width: Number(item.image.width || 1920),
              height: Number(item.image.height || 1080),
              sourceWebsite: host || item.displayLink || "google.com",
              title: item.title || item.snippet || "",
              altText: item.snippet || item.title || "",
            };
          });
        }
      } catch (e: any) {
        logger.warn(`[GOOGLE_CSE_WARN] Google Custom Search query failed for "${query}": ${e.message}`);
      }
    }
    return [];
  }

  /**
   * Bing Image Search
   */
  private static async searchBingImages(query: string): Promise<ImageCandidate[]> {
    try {
      const encodedQuery = this.encodeQueryParam(query);
      const url = `https://www.bing.com/images/search?q=${encodedQuery}`;
      const res = await fetch(url, {
        headers: {
          "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
          Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
          "Accept-Language": "en-US,en;q=0.9",
        },
      });

      if (!res.ok) return [];

      const html = await res.text();
      const candidates: ImageCandidate[] = [];
      const blockRegex = /\{&quot;[^{}]*?&quot;murl&quot;:&quot;(https?:\/\/[^&]+?)&quot;[^{}]*?\}/gi;
      let match;
      const seenUrls = new Set<string>();

      while ((match = blockRegex.exec(html)) !== null) {
        try {
          const rawJson = match[0].replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/[\uE000-\uF8FF]/g, '');
          const obj = JSON.parse(rawJson);

          if (obj.murl && !seenUrls.has(obj.murl)) {
            seenUrls.add(obj.murl);
            const pageUrl = obj.purl || obj.murl;
            let host = "";
            try {
              host = new URL(pageUrl).hostname.replace("www.", "");
            } catch (e) {}

            const cleanTitle = (obj.t || obj.desc || "").replace(/[\uE000-\uF8FF]/g, "").trim();
            const cleanAlt = (obj.desc || obj.t || "").replace(/[\uE000-\uF8FF]/g, "").trim();

            candidates.push({
              url: obj.murl,
              pageUrl: pageUrl,
              width: Number(obj.w || 1920),
              height: Number(obj.h || 1080),
              sourceWebsite: host || "bing.com",
              title: cleanTitle,
              altText: cleanAlt,
            });
          }
        } catch (e) {}
      }

      return candidates;
    } catch (e: any) {
      logger.warn(`[BING_SEARCH_WARN] Bing search failed for "${query}": ${e.message}`);
      return [];
    }
  }

  /**
   * STEP 3: AI Ranking via Gemini API
   */
  private static async rankCandidatesWithGemini(
    candidates: ImageCandidate[],
    unitName: string,
    materialType?: string,
    apiKey?: string
  ): Promise<Array<ImageCandidate & { score?: number; reason?: string }>> {
    const keyToUse = apiKey || process.env.GEMINI_API_KEY || "AIzaSyBPZQLky87GWco62fT7jCz5g_GJBiZahTk";

    const systemPrompt = `You are a Senior Educational Content Editor for Mirror Laikipia.
Your task is to select ONE image that would serve as the thumbnail for university academic material.
Return ONLY JSON.
{
  "selectedImage": {
    "url": "...",
    "pageUrl": "...",
    "reason": "...",
    "score": 98
  },
  "rankedCandidates": [
    {
      "url": "...",
      "pageUrl": "...",
      "reason": "...",
      "score": 98
    }
  ]
}`;

    const userContent = `Unit Name: ${unitName}
Category: ${materialType || "General Academic Material"}
Candidates count: ${candidates.length}`;

    try {
      const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${keyToUse}`;
      const res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: `${systemPrompt}\n\n${userContent}\n${JSON.stringify(candidates.slice(0, 15))}` }] }],
          generationConfig: {
            temperature: 0.2,
            responseMimeType: "application/json",
          },
        }),
      });

      if (res.ok) {
        const rawJson = (await res.json()) as any;
        const text = rawJson?.candidates?.[0]?.content?.parts?.[0]?.text;
        if (text) {
          const parsed = JSON.parse(text);
          const rankedList: Array<ImageCandidate & { score?: number; reason?: string }> = [];
          const seen = new Set<string>();

          if (parsed.selectedImage && parsed.selectedImage.url) {
            const match = candidates.find((c) => c.url === parsed.selectedImage.url);
            if (match) {
              seen.add(match.url);
              rankedList.push({
                ...match,
                score: parsed.selectedImage.score || 98,
                reason: parsed.selectedImage.reason || "Selected by Gemini AI as top educational thumbnail",
              });
            }
          }

          if (Array.isArray(parsed.rankedCandidates)) {
            for (const item of parsed.rankedCandidates) {
              if (item.url && !seen.has(item.url)) {
                const match = candidates.find((c) => c.url === item.url);
                if (match) {
                  seen.add(match.url);
                  rankedList.push({
                    ...match,
                    score: item.score || 80,
                    reason: item.reason || "Ranked candidate by Gemini AI",
                  });
                }
              }
            }
          }

          for (const c of candidates) {
            if (!seen.has(c.url)) {
              seen.add(c.url);
              rankedList.push(c);
            }
          }

          if (rankedList.length > 0) {
            logger.info(`[GEMINI_AI_RANKING_SUCCESS] Gemini AI ranked ${rankedList.length} candidates.`);
            return rankedList;
          }
        }
      }
    } catch (e: any) {
      logger.warn(`[GEMINI_RANKING_WARN] Gemini API call warning: ${e.message}`);
    }

    return this.heuristicWeightedRanking(candidates, unitName);
  }

  /**
   * Fallback Weighted Heuristic Ranking Engine
   */
  private static heuristicWeightedRanking(
    candidates: ImageCandidate[],
    unitName: string
  ): Array<ImageCandidate & { score?: number; reason?: string }> {
    const cleanUnitTerms = unitName.toLowerCase().split(/\s+/).filter(Boolean);

    const scored = candidates.map((cand) => {
      let score = 50;

      const title = (cand.title || "").toLowerCase();
      const alt = (cand.altText || "").toLowerCase();
      const combined = `${title} ${alt}`;

      let relevanceMatches = 0;
      for (const term of cleanUnitTerms) {
        if (combined.includes(term)) relevanceMatches++;
      }
      const relevanceScore = Math.min(40, (relevanceMatches / Math.max(1, cleanUnitTerms.length)) * 40);
      score += relevanceScore;

      const photoKeywords = [
        "student",
        "laboratory",
        "experiment",
        "lecturer",
        "research",
        "campus",
        "specimen",
        "microscope",
        "hospital",
        "university",
        "workshop",
        "equipment",
      ];
      let photoMatches = 0;
      for (const kw of photoKeywords) {
        if (combined.includes(kw)) photoMatches++;
      }
      const photoScore = Math.min(25, photoMatches * 8);
      score += photoScore;

      for (const term of this.EXCLUDED_TERMS) {
        if (combined.includes(term)) {
          score -= 30;
        }
      }

      if (cand.width >= cand.height && cand.height > 0) {
        const ar = cand.width / cand.height;
        if (ar >= 1.3) score += 5;
      }
      if (cand.width >= 1200) score += 5;

      return {
        ...cand,
        score: Math.min(99, Math.max(1, Math.round(score))),
        reason: "Ranked via weighted educational quality criteria",
      };
    });

    scored.sort((a, b) => (b.score || 0) - (a.score || 0));
    return scored;
  }

  /**
   * STEP 4, STEP 5, STEP 6: Download, Validate, Duplicate Detection, ImageKit Upload
   */
  private static async processRankedCandidates(
    db: admin.firestore.Firestore,
    ik: ImageKit,
    rankedCandidates: Array<ImageCandidate & { score?: number; reason?: string }>,
    unitName: string
  ): Promise<ThumbnailSearchResult> {
    for (const cand of rankedCandidates) {
      const originalSource = cand.pageUrl || cand.url;
      const originalWebsite = cand.sourceWebsite || "web";

      // Duplicate Check - Original Source URL
      const isUsedSource = await this.isSourceAlreadyUsed(db, originalSource, cand.url);
      if (isUsedSource) {
        logger.info(`[DUPLICATE_DISCARDED] Source URL already used in used_thumbnails: ${originalSource}`);
        continue;
      }

      // Stage 5: Download Candidate Image
      const downloadRes = await this.downloadImageBuffer(cand.url);
      if (!downloadRes) {
        logger.info(`[DOWNLOAD_FAILED] Unable to download image from candidate URL: ${cand.url}`);
        continue;
      }

      const { buffer } = downloadRes;

      // Quality & Format Validation
      if (!this.isValidImageBuffer(buffer, cand)) {
        logger.info(`[VALIDATION_FAILED] Image failed quality/landscape validation: ${cand.url}`);
        continue;
      }

      // Duplicate Check - Compute SHA-256 Hash
      const imageHash = crypto.createHash("sha256").update(buffer).digest("hex");
      const isUsedHash = await this.isHashAlreadyUsed(db, imageHash);
      if (isUsedHash) {
        logger.info(`[DUPLICATE_DISCARDED] Image SHA-256 hash already used: ${imageHash}`);
        continue;
      }

      // Stage 6: Upload to ImageKit
      const uploadRes = await this.uploadToImageKit(ik, buffer, unitName);
      if (!uploadRes) {
        logger.warn(`[IMAGEKIT_UPLOAD_FAIL] ImageKit upload failed for candidate: ${cand.url}`);
        continue;
      }

      // Save duplicate prevention record to `used_thumbnails` collection in Firestore
      await this.recordUsedThumbnail(db, {
        imageHash: imageHash,
        imageKitUrl: uploadRes.url,
        originalSource: originalSource,
        originalWebsite: originalWebsite,
        unitName: unitName,
      });

      logger.info(`[IMAGE_SELECTED] selectedUrl="${cand.url}" score=${cand.score || 90}`);
      logger.info(`[IMAGEKIT_UPLOAD_SUCCESS] imageUrl="${uploadRes.url}" fileId="${uploadRes.fileId}"`);

      return {
        success: true,
        imageKitUrl: uploadRes.url,
        imageKitFileId: uploadRes.fileId,
        originalSource: originalSource,
        originalWebsite: originalWebsite,
        imageHash: imageHash,
        reason: cand.reason,
        score: cand.score,
      };
    }

    return {
      success: false,
      error: `Zero candidate images passed download, quality validation, and duplicate detection for Unit "${unitName}"`,
    };
  }

  /**
   * Quality & Format Validation
   */
  private static isValidImageBuffer(buffer: Buffer, cand: ImageCandidate): boolean {
    if (!buffer || buffer.byteLength < 5000) return false;

    const isJpeg = buffer[0] === 0xff && buffer[1] === 0xd8;
    const isPng = buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47;
    const isWebp = buffer.toString("utf8", 8, 12) === "WEBP";

    if (!isJpeg && !isPng && !isWebp) return false;

    if (cand.width > 0 && cand.height > 0) {
      if (cand.width < cand.height) return false;
      const ar = cand.width / cand.height;
      if (ar < 1.1) return false;
    }

    return true;
  }



  private static async isHashAlreadyUsed(db: admin.firestore.Firestore, hash: string): Promise<boolean> {
    if (!hash) return false;
    const snap = await db.collection("used_thumbnails").where("imageHash", "==", hash).limit(1).get();
    return !snap.empty;
  }

  private static async isSourceAlreadyUsed(
    db: admin.firestore.Firestore,
    originalSource: string,
    candidateUrl: string
  ): Promise<boolean> {
    const cleanSrc = (originalSource || "").trim().toLowerCase();
    const cleanCand = (candidateUrl || "").trim().toLowerCase();

    if (cleanSrc) {
      const snap1 = await db.collection("used_thumbnails").where("originalSource", "==", cleanSrc).limit(1).get();
      if (!snap1.empty) return true;
    }

    if (cleanCand) {
      const snap2 = await db.collection("used_thumbnails").where("originalSource", "==", cleanCand).limit(1).get();
      if (!snap2.empty) return true;
    }

    return false;
  }

  /**
   * STAGE 6: ImageKit Upload with explicit logging
   */
  private static async uploadToImageKit(
    ik: ImageKit,
    buffer: Buffer,
    unitName: string
  ): Promise<{ url: string; fileId: string } | null> {
    try {
      const base64Image = buffer.toString("base64");
      const sanitizeName = unitName.replace(/[^a-zA-Z0-9]/g, "_").toLowerCase();
      const fileName = `thumb_${sanitizeName}_${Date.now()}.jpg`;

      const uploadRes = await ik.upload({
        file: base64Image,
        fileName: fileName,
        folder: "THUMBNAILS",
        useUniqueFileName: true,
      });

      if (uploadRes && uploadRes.url) {
        logger.info(`[IMAGEKIT_UPLOAD_SUCCESS] ImageKit URL: ${uploadRes.url}, file ID: ${uploadRes.fileId}`);
        return {
          url: uploadRes.url,
          fileId: uploadRes.fileId,
        };
      }
    } catch (err: any) {
      logger.error("[IMAGEKIT_UPLOAD_ERROR] Failed to upload thumbnail to ImageKit:", err);
      if (err.stack) logger.error(err.stack);
    }
    return null;
  }

  private static async recordUsedThumbnail(
    db: admin.firestore.Firestore,
    data: {
      imageHash: string;
      imageKitUrl: string;
      originalSource: string;
      originalWebsite: string;
      unitName: string;
    }
  ): Promise<void> {
    await db.collection("used_thumbnails").add({
      imageHash: data.imageHash,
      imageKitUrl: data.imageKitUrl,
      originalSource: data.originalSource,
      originalWebsite: data.originalWebsite,
      unitName: data.unitName,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
}

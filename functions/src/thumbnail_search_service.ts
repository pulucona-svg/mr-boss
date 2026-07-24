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
   * STEP 1 - Build search queries based on rules.
   * Normal materials: Search ONLY using Unit Name.
   * Practical materials (Practical, Lab Practical, Laboratory, Field Practical):
   * Search in order:
   * 1. <Unit Name> laboratory
   * 2. <Unit Name> practical
   * 3. <Unit Name> experiment
   */
  public static buildSearchQueries(unitName: string, materialType?: string, catType?: string): string[] {
    const cleanUnit = (unitName || "").trim();
    if (!cleanUnit) return [];

    const categoryStr = `${materialType || ""} ${catType || ""}`.toLowerCase();
    const isPracticalCategory =
      categoryStr.includes("practical") ||
      categoryStr.includes("lab") ||
      categoryStr.includes("laboratory") ||
      categoryStr.includes("field practical");

    if (isPracticalCategory) {
      return [
        `${cleanUnit} laboratory`,
        `${cleanUnit} practical`,
        `${cleanUnit} experiment`,
      ];
    } else {
      return [cleanUnit];
    }
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

    // STEP 1 & STEP 2: Search Internet and Collect Candidates (30–50)
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

    // Limit pool to first 30-50 candidates
    const candidatePool = candidates.slice(0, 50);

    // STEP 3: Gemini AI Ranking
    const rankedCandidates = await this.rankCandidatesWithGemini(candidatePool, unitName, materialType, geminiApiKey);

    // STEP 4, STEP 5, STEP 6: Download, Validate, Duplicate Detection, ImageKit Upload
    return await this.processRankedCandidates(db, ik, rankedCandidates, unitName);
  }

  /**
   * STEP 1 & STEP 2: Collect candidate metadata from Search Engines
   */
  private static async collectCandidates(query: string): Promise<ImageCandidate[]> {
    // 1. Google Image Search (via Google CSE API if available)
    const googleCandidates = await this.searchGoogleImages(query);
    if (googleCandidates.length >= 10) {
      return googleCandidates;
    }

    // 2. Bing Image Search (fallback if Google returns nothing or insufficient candidates)
    logger.info(`[SEARCH_FALLBACK_BING] Fetching Bing Image Search candidates for query "${query}"...`);
    const bingCandidates = await this.searchBingImages(query);

    // Combine candidate lists avoiding duplicate URLs
    const combined: ImageCandidate[] = [...googleCandidates];
    const seenUrls = new Set(googleCandidates.map((c) => c.url));

    for (const bc of bingCandidates) {
      if (!seenUrls.has(bc.url)) {
        seenUrls.add(bc.url);
        combined.push(bc);
      }
    }

    return combined;
  }

  /**
   * Google Image Search
   */
  private static async searchGoogleImages(query: string): Promise<ImageCandidate[]> {
    const apiKey = process.env.GOOGLE_SEARCH_API_KEY;
    const cseId = process.env.GOOGLE_CSE_ID;

    if (apiKey && cseId) {
      try {
        const url = `https://www.googleapis.com/customsearch/v1?key=${apiKey}&cx=${cseId}&searchType=image&q=${encodeURIComponent(
          query
        )}&num=10&imgSize=large&imgType=photo&imgAspect=wide`;
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
        logger.warn(`[GOOGLE_CSE_WARN] Google Custom Search query failed: ${e.message}`);
      }
    }
    return [];
  }

  /**
   * Bing Image Search
   */
  private static async searchBingImages(query: string): Promise<ImageCandidate[]> {
    try {
      const url = `https://www.bing.com/images/search?q=${encodeURIComponent(query)}`;
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
      logger.warn(`[BING_SEARCH_WARN] Bing search failed: ${e.message}`);
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

Your objective is maximum educational quality.

Always choose the image that looks like it belongs in an international university textbook, laboratory manual or academic website.

You MUST return ONLY ONE image.

Prefer images showing:
✔ University students
✔ Lecturers
✔ Laboratories
✔ Scientific equipment
✔ Real experiments
✔ Medical specimens
✔ Agricultural field work
✔ Computer laboratories
✔ Engineering workshops
✔ Microscopes
✔ Skeletons
✔ Hospitals
✔ Classrooms
✔ Real campus environments
✔ Academic demonstrations
✔ Educational field activities
✔ Scientific research
✔ Real photography

Reject immediately:
❌ Logos
❌ Icons
❌ Book covers
❌ Watermarks
❌ AI-generated art
❌ Cartoons
❌ Clipart
❌ Memes
❌ Screenshots
❌ Advertisements
❌ Social media graphics
❌ Posters
❌ Infographics
❌ Chemical structure diagrams
❌ Pure text images
❌ Portrait orientation
❌ Blurry images
❌ Low resolution
❌ Duplicate images already stored by Mirror Laikipia

Ranking Priorities
Rank using these weights:
Educational relevance      40%
Real photograph            25%
Visual quality             15%
Professional appearance    10%
Landscape orientation        5%
High resolution              5%

Technical Requirements
Minimum width: 1200 px
Preferred: 1920 px or higher
Orientation: Landscape only.
Aspect ratio: >= 1.3

Output
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

Candidates metadata list (${candidates.length} candidates):
${JSON.stringify(candidates, null, 2)}`;

    try {
      const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${keyToUse}`;
      const res = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: `${systemPrompt}\n\n${userContent}` }] }],
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

          // Append any remaining unranked candidates
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

    // Fallback: Weighted Heuristic Ranking (40% relevance, 25% real photo, 15% visual, 10% prof, 5% landscape, 5% high res)
    logger.info(`[HEURISTIC_RANKING_FALLBACK] Ranking ${candidates.length} candidates via weighted educational quality rules.`);
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

      // 1. Educational relevance (40%)
      let relevanceMatches = 0;
      for (const term of cleanUnitTerms) {
        if (combined.includes(term)) relevanceMatches++;
      }
      const relevanceScore = Math.min(40, (relevanceMatches / Math.max(1, cleanUnitTerms.length)) * 40);
      score += relevanceScore;

      // 2. Real photograph (25%)
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

      // Deduct heavily for excluded terms
      for (const term of this.EXCLUDED_TERMS) {
        if (combined.includes(term)) {
          score -= 30;
        }
      }

      // 3. Landscape & High Resolution (10%)
      if (cand.width >= cand.height && cand.height > 0) {
        const ar = cand.width / cand.height;
        if (ar >= 1.3) score += 5; // Landscape aspect ratio >= 1.3
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

      // STEP 5: Duplicate Check - Original Source URL
      const isUsedSource = await this.isSourceAlreadyUsed(db, originalSource, cand.url);
      if (isUsedSource) {
        logger.info(`[DUPLICATE_DISCARDED] Source URL already used in used_thumbnails: ${originalSource}`);
        continue;
      }

      // STEP 4: Download ONLY selected candidate image
      const buffer = await this.downloadImageBuffer(cand.url);
      if (!buffer) {
        logger.info(`[DOWNLOAD_FAILED] Unable to download image from candidate URL: ${cand.url}`);
        continue;
      }

      // STEP 4: Quality & Format Validation
      if (!this.isValidImageBuffer(buffer, cand)) {
        logger.info(`[VALIDATION_FAILED] Image failed quality/landscape validation: ${cand.url}`);
        continue;
      }

      // STEP 5: Duplicate Check - Compute SHA-256 Hash
      const imageHash = crypto.createHash("sha256").update(buffer).digest("hex");
      const isUsedHash = await this.isHashAlreadyUsed(db, imageHash);
      if (isUsedHash) {
        logger.info(`[DUPLICATE_DISCARDED] Image SHA-256 hash already used: ${imageHash}`);
        continue;
      }

      // STEP 6: Upload ONLY to ImageKit
      const uploadRes = await this.uploadToImageKit(ik, buffer, unitName);
      if (!uploadRes) {
        logger.warn(`[IMAGEKIT_UPLOAD_FAIL] ImageKit upload failed for candidate: ${cand.url}`);
        continue;
      }

      // STEP 6: Save duplicate prevention record to `used_thumbnails` collection in Firestore
      await this.recordUsedThumbnail(db, {
        imageHash: imageHash,
        imageKitUrl: uploadRes.url,
        originalSource: originalSource,
        originalWebsite: originalWebsite,
        unitName: unitName,
      });

      logger.info(`[SELECTION_SUCCESS] Selected image uploaded to ImageKit: ${uploadRes.url} (Score: ${cand.score})`);

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
   * STEP 4: Quality & Format Validation
   */
  private static isValidImageBuffer(buffer: Buffer, cand: ImageCandidate): boolean {
    if (!buffer || buffer.byteLength < 5000) return false;

    // Check magic bytes for JPEG, PNG, WEBP
    const isJpeg = buffer[0] === 0xff && buffer[1] === 0xd8;
    const isPng = buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47;
    const isWebp = buffer.toString("utf8", 8, 12) === "WEBP";

    if (!isJpeg && !isPng && !isWebp) return false;

    // Landscape orientation requirement
    if (cand.width > 0 && cand.height > 0) {
      if (cand.width < cand.height) return false; // Reject portrait orientation
      const ar = cand.width / cand.height;
      if (ar < 1.1) return false; // Landscape aspect ratio requirement
    }

    return true;
  }

  /**
   * Download image bytes with a strict 6-second network timeout
   */
  private static async downloadImageBuffer(url: string): Promise<Buffer | null> {
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 6000);

      const res = await fetch(url, {
        headers: {
          "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        },
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (!res.ok) return null;

      const arrayBuffer = await res.arrayBuffer();
      if (!arrayBuffer || arrayBuffer.byteLength < 5000) return null;

      return Buffer.from(arrayBuffer);
    } catch (e) {
      return null;
    }
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
        return {
          url: uploadRes.url,
          fileId: uploadRes.fileId,
        };
      }
    } catch (err: any) {
      logger.error("[IMAGEKIT_UPLOAD_FAIL] Failed to upload thumbnail to ImageKit:", err);
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

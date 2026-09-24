import * as logger from "firebase-functions/logger";
import { EnvConfig } from "../config/env_config";

export interface ImageSafetyClassification {
  isSafe: boolean;
  confidence: number;
  category: "safe" | "nudity" | "sexual" | "suggestive" | "violence" | "vulgar" | "inconclusive" | "invalid_format";
  reason: string;
}

export interface ImageDownloadResult {
  success: boolean;
  buffer?: Buffer;
  contentType?: string;
  rejectionReason?: string;
}

export class ImageSafetyGateService {
  private static readonly BLOCKED_DOMAINS = new Set([
    "pornhub.com",
    "xvideos.com",
    "xnxx.com",
    "xhamster.com",
    "xhamster.desi",
    "fapality.com",
    "pictoa.com",
    "redtube.com",
    "youporn.com",
    "tube8.com",
    "spankbang.com",
    "beeg.com",
    "tnaflix.com",
    "drtuber.com",
    "eporner.com",
    "hqporner.com",
    "imagefap.com",
    "motherless.com",
    "onlyfans.com",
    "fansly.com",
    "chaturbate.com",
    "myfreecams.com",
    "cam4.com",
    "livejasmin.com",
    "stripchat.com",
    "camsoda.com",
    "bongacams.com",
    "brazzers.com",
    "naughtyamerica.com",
    "realitykings.com",
    "playboy.com",
    "penthouse.com",
    "hustler.com",
    "erome.com",
    "redgifs.com",
    "rule34.xxx",
    "gelbooru.com",
    "danbooru.donmai.us",
    "e-shuushuu.net",
    "hentaihaven.xxx",
    "nhentai.net",
    "hitomi.la",
    "fakku.net",
    "luscious.net",
    "heavy-r.com",
    "bestgore.fun",
    "kaotic.com",
    "crazyshit.com",
  ]);

  private static readonly ADULT_KEYWORDS = [
    "nude",
    "naked",
    "nudity",
    "porn",
    "porno",
    "pornography",
    "xxx",
    "erotic",
    "erotica",
    "sex",
    "sexy",
    "sensual",
    "bikini",
    "lingerie",
    "underwear",
    "cleavage",
    "boobs",
    "breasts",
    "tits",
    "butt",
    "buttocks",
    "penis",
    "vagina",
    "genitalia",
    "fetish",
    "bdsm",
    "nsfw",
    "hentai",
    "escort",
    "onlyfans",
    "camgirl",
    "playboy",
    "penthouse",
    "adult",
    "strip",
    "stripper",
    "swinger",
    "orgasm",
    "intercourse",
    "masturbat",
    "milf",
    "mature",
    "babe",
    "amateur",
    "topless",
    "bottomless",
    "provocative",
    "seductive",
    "uncensored",
    "explicit",
    "hardcore",
    "softcore",
    "thong",
    "pussy",
    "cock",
    "dick",
    "cum",
    "fap",
    "panties",
  ];

  private static readonly AI_EXCLUDED_TERMS = [
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
   * STAGE A: Source URL and Metadata Filtering.
   * Checks domain blocklist, adult keywords, AI art terms, and invalid file extensions.
   */
  public static filterCandidateMetadata(
    url: string,
    title?: string,
    sourceDomain?: string
  ): { safe: boolean; reason?: string } {
    if (!url || typeof url !== "string") {
      return { safe: false, reason: "missing_url" };
    }

    const cleanUrl = url.toLowerCase().trim();
    const cleanTitle = (title || "").toLowerCase().trim();
    const cleanDomain = (sourceDomain || "").toLowerCase().trim();
    const combined = `${cleanUrl} ${cleanTitle} ${cleanDomain}`;

    // 1. Check Domain Blocklist
    for (const blocked of this.BLOCKED_DOMAINS) {
      if (cleanUrl.includes(blocked) || cleanDomain.includes(blocked)) {
        return { safe: false, reason: `blocked_domain_${blocked}` };
      }
    }

    // 2. Check Adult/NSFW Keywords
    for (const kw of this.ADULT_KEYWORDS) {
      const regex = new RegExp(`\\b${kw}\\b|[/_\\-.]${kw}[/_\\-.]`, "i");
      if (regex.test(combined)) {
        return { safe: false, reason: `adult_keyword_${kw}` };
      }
    }

    // 3. Check AI Generated & Graphic Exclusions
    for (const term of this.AI_EXCLUDED_TERMS) {
      if (combined.includes(term)) {
        return { safe: false, reason: `excluded_term_${term.replace(/\s+/g, "_")}` };
      }
    }

    // 4. Exclude vector/animation formats
    if (cleanUrl.endsWith(".svg") || cleanUrl.endsWith(".gif")) {
      return { safe: false, reason: "unsupported_extension" };
    }

    return { safe: true };
  }

  /**
   * STAGE B: Download & Binary Validation Gate.
   * Downloads bytes, verifies HTTP 200, checks image MIME type, validates magic bytes, and enforces size constraints.
   */
  public static async downloadAndValidateBuffer(
    url: string,
    timeoutMs: number = 6000
  ): Promise<ImageDownloadResult> {
    try {
      // Basic URL sanity check
      if (!/^https?:\/\//i.test(url)) {
        return { success: false, rejectionReason: "invalid_protocol" };
      }

      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

      const res = await fetch(url, {
        headers: {
          "User-Agent":
            "MirrorLaikipiaNews/1.0 (https://mirrorlaikipia.edu; news@mirrorlaikipia.edu) Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
          Accept: "image/avif,image/webp,image/apng,image/jpeg,image/png,image/*,*/*;q=0.8",
        },
        signal: controller.signal,
        redirect: "follow",
      });

      clearTimeout(timeoutId);

      if (!res.ok) {
        return { success: false, rejectionReason: `http_status_${res.status}` };
      }

      // Verify redirect target domain is safe
      if (res.url && res.url !== url) {
        const redirectCheck = this.filterCandidateMetadata(res.url);
        if (!redirectCheck.safe) {
          return { success: false, rejectionReason: `unsafe_redirect_${redirectCheck.reason}` };
        }
      }

      // Verify Content-Type header
      const contentType = (res.headers.get("content-type") || "").toLowerCase().trim();
      if (!contentType.startsWith("image/") && !contentType.includes("image/jpeg") && !contentType.includes("image/png") && !contentType.includes("image/webp")) {
        return { success: false, rejectionReason: `invalid_content_type_${contentType.slice(0, 30)}` };
      }

      if (contentType.includes("text/html") || contentType.includes("application/json")) {
        return { success: false, rejectionReason: "html_or_json_response" };
      }

      const arrayBuf = await res.arrayBuffer();
      if (!arrayBuf) {
        return { success: false, rejectionReason: "empty_buffer" };
      }

      const byteLength = arrayBuf.byteLength;
      // Enforce size limits: Min 10KB (10,240 bytes), Max 10MB (10,485,760 bytes)
      if (byteLength < 10240) {
        return { success: false, rejectionReason: `image_too_small_${byteLength}_bytes` };
      }
      if (byteLength > 10485760) {
        return { success: false, rejectionReason: `image_too_large_${byteLength}_bytes` };
      }

      const buffer = Buffer.from(arrayBuf);

      // Verify Binary Magic Bytes
      const isJpeg = buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
      const isPng =
        buffer[0] === 0x89 &&
        buffer[1] === 0x50 &&
        buffer[2] === 0x4e &&
        buffer[3] === 0x47 &&
        buffer[4] === 0x0d &&
        buffer[5] === 0x0a &&
        buffer[6] === 0x1a &&
        buffer[7] === 0x0a;
      const isWebp = buffer.toString("utf8", 8, 12) === "WEBP" && buffer.toString("utf8", 0, 4) === "RIFF";

      if (!isJpeg && !isPng && !isWebp) {
        // Check if HTML document masquerading as image
        const head = buffer.toString("utf8", 0, 100).toLowerCase();
        if (head.includes("<!doctype") || head.includes("<html") || head.includes("<?xml")) {
          return { success: false, rejectionReason: "html_payload_masquerading_as_image" };
        }
        return { success: false, rejectionReason: "invalid_image_magic_bytes" };
      }

      const normalizedContentType = isPng ? "image/png" : isWebp ? "image/webp" : "image/jpeg";
      return { success: true, buffer, contentType: normalizedContentType };
    } catch (err: any) {
      const isTimeout = err?.name === "AbortError" || /timeout/i.test(err?.message || "");
      return { success: false, rejectionReason: isTimeout ? "download_timeout" : `download_error_${err?.message?.slice(0, 50)}` };
    }
  }

  /**
   * STAGE C: AI Vision Visual Safety Classifier.
   * Uses Gemini Vision Multimodal inference to analyze the ACTUAL downloaded image bytes.
   * POLICY: Conservative safety - WHEN IN DOUBT → REJECT.
   */
  public static async classifyImageVisualSafety(
    buffer: Buffer,
    mimeType: string = "image/jpeg",
    context: string = ""
  ): Promise<ImageSafetyClassification> {
    try {
      const geminiKeys = EnvConfig.getApiKeys("gemini");
      if (!geminiKeys || geminiKeys.length === 0) {
        // If no Gemini key is available for vision moderation, reject per conservative safety policy
        logger.warn("[IMAGE_SAFETY_VISION_WARN] No Gemini key available for visual safety classification. Conservative reject.");
        return {
          isSafe: false,
          confidence: 0,
          category: "inconclusive",
          reason: "no_vision_moderation_key_available",
        };
      }

      const apiKey = geminiKeys[0];
      const model = "gemini-flash-lite-latest";
      const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

      const base64Data = buffer.toString("base64");

      const promptText = `
You are an ultra-strict news content safety moderator for a professional, family-safe public news platform.
Analyze this news photo candidate carefully for visual content safety.

STRICT REJECTION CRITERIA:
1. Pornography, nudity, exposed genitalia, bare breasts, or bare buttocks.
2. Sexual acts, masturbation, sexual intercourse, erotic touching, fetish, BDSM.
3. Suggestive adult content (cleavage-focused erotic poses, transparent/see-through clothing, erotic lingerie/swimwear modeling).
4. Vulgar adult promotional imagery or erotic selfies.
5. Graphic gore, mutilated corpses, or gratuitous violence.

ACCEPTABLE CONTENT:
Standard, family-safe, legitimate editorial, news, sports, nature, technology, cultural, or documentary photography.

POLICY:
WHEN IN DOUBT → REJECT (isSafe: false).

Output MUST be strictly valid JSON matching this schema:
{
  "isSafe": true,
  "confidence": 0.95,
  "category": "safe",
  "reason": "Family-safe documentary photograph of an agricultural field."
}
`;

      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 15000);

      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [
            {
              parts: [
                {
                  inlineData: {
                    mimeType: mimeType || "image/jpeg",
                    data: base64Data,
                  },
                },
                { text: promptText },
              ],
            },
          ],
          generationConfig: {
            temperature: 0.1,
            responseMimeType: "application/json",
          },
        }),
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (!res.ok) {
        const errText = await res.text();
        logger.warn(`[IMAGE_SAFETY_VISION_HTTP_ERR] HTTP ${res.status}: ${errText.slice(0, 100)}`);
        return {
          isSafe: false,
          confidence: 0,
          category: "inconclusive",
          reason: `vision_api_http_${res.status}`,
        };
      }

      const json = (await res.json()) as any;
      const text = json.candidates?.[0]?.content?.parts?.[0]?.text;
      if (!text) {
        return {
          isSafe: false,
          confidence: 0,
          category: "inconclusive",
          reason: "empty_vision_response",
        };
      }

      let cleanText = text.trim();
      if (cleanText.startsWith("```json")) {
        cleanText = cleanText.replace(/^```json/, "").replace(/```$/, "").trim();
      } else if (cleanText.startsWith("```")) {
        cleanText = cleanText.replace(/^```/, "").replace(/```$/, "").trim();
      }

      const result = JSON.parse(cleanText);
      const isSafe = Boolean(result.isSafe === true && (result.confidence || 1.0) >= 0.8);
      const category = isSafe ? "safe" : (result.category || "suggestive");
      const reason = result.reason || (isSafe ? "Verified family-safe news photo" : "Visual safety filter triggered");

      return {
        isSafe,
        confidence: Number(result.confidence || 0.9),
        category,
        reason,
      };
    } catch (err: any) {
      logger.warn(`[IMAGE_SAFETY_VISION_EXCEPTION] Visual classification exception: ${err.message}. Conservative reject.`);
      return {
        isSafe: false,
        confidence: 0,
        category: "inconclusive",
        reason: `vision_exception_${err?.message?.slice(0, 50)}`,
      };
    }
  }
}

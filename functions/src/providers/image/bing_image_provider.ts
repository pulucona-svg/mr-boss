import * as logger from "firebase-functions/logger";
import { BaseImageProvider } from "./base_image_provider";
import { ImageSearchResult } from "../../types/image_worker";
import { AIWorker } from "../../types/worker";

export class BingImageProvider extends BaseImageProvider {
  readonly name = "bing";

  async searchImages(
    query: string,
    options?: { limit?: number; category?: string },
    worker?: AIWorker
  ): Promise<ImageSearchResult[]> {
    const cleanQuery = this.sanitizeQuery(query);
    if (!cleanQuery) return [];

    const requestUrl = `https://www.bing.com/images/search?q=${encodeURIComponent(cleanQuery)}&qft=+filterui:photo-photo`;

    logger.info(`[BING_IMAGE_PROVIDER] Query="${cleanQuery}" Worker="${worker?.workerId || 'none'}"`);

    try {
      const res = await fetch(requestUrl, {
        headers: {
          "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        },
      });

      if (!res.ok) return [];

      const html = await res.text();
      const results: ImageSearchResult[] = [];
      const blockRegex = /\{&quot;[^{}]*?&quot;murl&quot;:&quot;(https?:\/\/[^&]+?)&quot;[^{}]*?\}/gi;
      let match;
      const seenUrls = new Set<string>();

      while ((match = blockRegex.exec(html)) !== null && results.length < (options?.limit || 15)) {
        try {
          const rawJson = match[0].replace(/&quot;/g, '"').replace(/&amp;/g, '&');
          const obj = JSON.parse(rawJson);

          if (obj.murl && !seenUrls.has(obj.murl)) {
            seenUrls.add(obj.murl);
            let host = "";
            try {
              host = new URL(obj.purl || obj.murl).hostname.replace("www.", "");
            } catch (e) {}

            results.push({
              imageUrl: obj.murl,
              thumbnailUrl: obj.turl || obj.murl,
              sourceUrl: obj.purl || obj.murl,
              sourceDomain: host || "bing.com",
              caption: (obj.t || obj.desc || cleanQuery).replace(/[\uE000-\uF8FF]/g, "").trim(),
              width: Number(obj.w || 1920),
              height: Number(obj.h || 1080),
              publishedAt: new Date().toISOString(),
              confidence: 0.85,
            });
          }
        } catch (e) {}
      }

      return results;
    } catch (err: any) {
      logger.error(`[BING_PROVIDER_ERROR] Search failed for "${cleanQuery}":`, err);
      return [];
    }
  }
}

import * as logger from "firebase-functions/logger";
import { BaseImageProvider } from "./base_image_provider";
import { ImageSearchResult } from "../../types/image_worker";
import { AIWorker } from "../../types/worker";

export class GoogleImageProvider extends BaseImageProvider {
  readonly name = "google";

  async searchImages(
    query: string,
    options?: { limit?: number; category?: string },
    worker?: AIWorker
  ): Promise<ImageSearchResult[]> {
    const cleanQuery = this.sanitizeQuery(query);
    if (!cleanQuery) return [];

    const apiKey = worker?.apiKey || process.env.GOOGLE_SEARCH_API_KEY;
    const cseId = process.env.GOOGLE_CSE_ID;

    logger.info(`[GOOGLE_IMAGE_PROVIDER] Query="${cleanQuery}" Worker="${worker?.workerId || 'none'}"`);

    if (!apiKey || !cseId) {
      logger.info(`[GOOGLE_IMAGE_PROVIDER_SKIP] Missing Google CSE API Key or CSE ID`);
      return [];
    }

    try {
      const url = `https://www.googleapis.com/customsearch/v1?key=${apiKey}&cx=${cseId}&searchType=image&q=${encodeURIComponent(cleanQuery)}&num=${options?.limit || 10}&imgSize=large&imgType=photo`;
      const res = await fetch(url);
      if (!res.ok) return [];

      const data = (await res.json()) as any;
      const items = data.items || [];
      const results: ImageSearchResult[] = [];

      for (const item of items) {
        let host = "";
        try {
          host = new URL(item.image.contextLink || item.link).hostname.replace("www.", "");
        } catch (e) {}

        results.push({
          imageUrl: item.link,
          thumbnailUrl: item.image?.thumbnailLink || item.link,
          sourceUrl: item.image?.contextLink || item.link,
          sourceDomain: host || item.displayLink || "google.com",
          caption: item.title || item.snippet || cleanQuery,
          width: Number(item.image?.width || 1920),
          height: Number(item.image?.height || 1080),
          publishedAt: new Date().toISOString(),
          confidence: 0.9,
        });
      }

      return results;
    } catch (err: any) {
      logger.error(`[GOOGLE_PROVIDER_ERROR] Search failed for "${cleanQuery}":`, err);
      return [];
    }
  }
}

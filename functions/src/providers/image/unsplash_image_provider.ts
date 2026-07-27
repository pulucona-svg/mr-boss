import * as logger from "firebase-functions/logger";
import { BaseImageProvider } from "./base_image_provider";
import { ImageSearchResult } from "../../types/image_worker";
import { AIWorker } from "../../types/worker";

export class UnsplashImageProvider extends BaseImageProvider {
  readonly name = "unsplash";

  async searchImages(
    query: string,
    options?: { limit?: number; category?: string },
    worker?: AIWorker
  ): Promise<ImageSearchResult[]> {
    const cleanQuery = this.sanitizeQuery(query);
    if (!cleanQuery) return [];

    const apiKey = worker?.apiKey || process.env.UNSPLASH_ACCESS_KEY || "demo_key";
    const limit = options?.limit || 15;
    const url = `https://api.unsplash.com/search/photos?query=${encodeURIComponent(cleanQuery)}&per_page=${limit}`;

    logger.info(`[UNSPLASH_IMAGE_PROVIDER] Query="${cleanQuery}" Worker="${worker?.workerId || 'none'}"`);

    try {
      const res = await fetch(url, {
        headers: {
          Authorization: `Client-ID ${apiKey}`,
        },
      });

      if (!res.ok) return [];

      const data = (await res.json()) as any;
      const items = data.results || [];
      const results: ImageSearchResult[] = [];

      for (const item of items) {
        if (item.urls?.regular) {
          results.push({
            imageUrl: item.urls.regular,
            thumbnailUrl: item.urls.thumb || item.urls.small || item.urls.regular,
            sourceUrl: item.links?.html || item.urls.regular,
            sourceDomain: "unsplash.com",
            caption: item.alt_description || item.description || cleanQuery,
            width: Number(item.width || 1920),
            height: Number(item.height || 1080),
            publishedAt: item.created_at || new Date().toISOString(),
            confidence: 0.88,
          });
        }
      }

      return results;
    } catch (err: any) {
      logger.error(`[UNSPLASH_PROVIDER_ERROR] Search failed for "${cleanQuery}":`, err);
      return [];
    }
  }
}

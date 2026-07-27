import * as logger from "firebase-functions/logger";
import { BaseImageProvider } from "./base_image_provider";
import { ImageSearchResult } from "../../types/image_worker";
import { AIWorker } from "../../types/worker";

export class PixabayImageProvider extends BaseImageProvider {
  readonly name = "pixabay";

  async searchImages(
    query: string,
    options?: { limit?: number; category?: string },
    worker?: AIWorker
  ): Promise<ImageSearchResult[]> {
    const cleanQuery = this.sanitizeQuery(query);
    if (!cleanQuery) return [];

    const apiKey = worker?.apiKey || process.env.PIXABAY_API_KEY || "48096316-56dd6fb202867ef9ce5316499";
    const limit = options?.limit || 15;
    const requestUrl = `https://pixabay.com/api/?key=${apiKey}&q=${encodeURIComponent(cleanQuery)}&image_type=photo&orientation=horizontal&safesearch=true&per_page=${limit}`;

    logger.info(`[PIXABAY_IMAGE_PROVIDER] Query="${cleanQuery}" Worker="${worker?.workerId || 'none'}"`);

    try {
      const res = await fetch(requestUrl);
      if (!res.ok) {
        logger.warn(`[PIXABAY_HTTP_WARN] HTTP ${res.status} for query "${cleanQuery}"`);
        return [];
      }

      const data = (await res.json()) as any;
      const hits = data.hits || [];
      const results: ImageSearchResult[] = [];

      for (const item of hits) {
        const imgUrl = item.largeImageURL || item.webformatURL;
        if (imgUrl) {
          results.push({
            imageUrl: imgUrl,
            thumbnailUrl: item.previewURL || item.webformatURL || imgUrl,
            sourceUrl: item.pageURL || imgUrl,
            sourceDomain: "pixabay.com",
            caption: item.tags || cleanQuery,
            width: Number(item.imageWidth || 1920),
            height: Number(item.imageHeight || 1080),
            publishedAt: new Date().toISOString(),
            confidence: 0.9,
          });
        }
      }

      return results;
    } catch (err: any) {
      logger.error(`[PIXABAY_PROVIDER_ERROR] Search failed for "${cleanQuery}":`, err);
      return [];
    }
  }
}

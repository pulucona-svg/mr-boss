import * as logger from "firebase-functions/logger";
import { BaseImageProvider } from "./base_image_provider";
import { ImageSearchResult } from "../../types/image_worker";
import { AIWorker } from "../../types/worker";

export class WikimediaImageProvider extends BaseImageProvider {
  readonly name = "wikimedia";

  async searchImages(
    query: string,
    options?: { limit?: number; category?: string },
    worker?: AIWorker
  ): Promise<ImageSearchResult[]> {
    const cleanQuery = this.sanitizeQuery(query);
    if (!cleanQuery) return [];

    const limit = options?.limit || 15;
    const requestUrl = `https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrsearch=${encodeURIComponent(cleanQuery)}&gsrnamespace=6&gsrlimit=${limit}&prop=imageinfo&iiprop=url|size|mime&format=json&origin=*`;

    logger.info(`[WIKIMEDIA_IMAGE_PROVIDER] Query="${cleanQuery}" Worker="${worker?.workerId || 'none'}"`);

    try {
      const res = await fetch(requestUrl, {
        headers: {
          "User-Agent": "MirrorLaikipiaApp/1.0 (contact@mirrorlaikipia.edu; https://mirrorlaikipia.edu)",
        },
      });

      if (!res.ok) {
        logger.warn(`[WIKIMEDIA_HTTP_WARN] HTTP ${res.status} for query "${cleanQuery}"`);
        return [];
      }

      const data = (await res.json()) as any;
      const pages = data?.query?.pages ? Object.values(data.query.pages) : [];
      const results: ImageSearchResult[] = [];

      for (const page of pages as any[]) {
        const info = page?.imageinfo?.[0];
        if (info && info.url) {
          const mime = (info.mime || "").toLowerCase();
          if (mime.includes("image/jpeg") || mime.includes("image/jpg") || mime.includes("image/png") || mime.includes("image/webp")) {
            results.push({
              imageUrl: info.url,
              thumbnailUrl: info.thumburl || info.url,
              sourceUrl: info.descriptionurl || info.url,
              sourceDomain: "commons.wikimedia.org",
              caption: page.title || cleanQuery,
              width: Number(info.width || 1920),
              height: Number(info.height || 1080),
              publishedAt: new Date().toISOString(),
              confidence: 0.95,
            });
          }
        }
      }

      return results;
    } catch (err: any) {
      logger.error(`[WIKIMEDIA_PROVIDER_ERROR] Search failed for "${cleanQuery}":`, err);
      return [];
    }
  }
}

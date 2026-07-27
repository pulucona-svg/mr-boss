import { IImageProvider, ImageSearchResult } from "../../types/image_worker";
import { AIWorker } from "../../types/worker";

export abstract class BaseImageProvider implements IImageProvider {
  abstract readonly name: string;

  abstract searchImages(
    query: string,
    options?: { limit?: number; category?: string },
    worker?: AIWorker
  ): Promise<ImageSearchResult[]>;

  async healthCheck(worker?: AIWorker): Promise<boolean> {
    try {
      const results = await this.searchImages("news photo", { limit: 1 }, worker);
      return Array.isArray(results);
    } catch (_) {
      return false;
    }
  }

  supportsFeature(feature: string): boolean {
    const supported = ["search", "metadata", "healthcheck", "real_photos"];
    return supported.includes(feature.toLowerCase());
  }

  async estimateLatency(worker?: AIWorker): Promise<number> {
    return worker?.averageLatency || 300;
  }

  async estimateQuota(worker?: AIWorker): Promise<number> {
    return worker?.remainingQuota || 1000;
  }

  protected sanitizeQuery(str: string): string {
    return (str || "").replace(/['"’`]/g, " ").replace(/\s+/g, " ").trim();
  }
}

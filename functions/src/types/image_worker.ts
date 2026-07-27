import { AIWorker } from "./worker";

export interface ImageSearchResult {
  imageUrl: string;
  thumbnailUrl: string;
  sourceUrl: string;
  sourceDomain: string;
  caption: string;
  width: number;
  height: number;
  publishedAt: string;
  confidence: number; // 0.0 to 1.0
}

export interface IImageProvider {
  readonly name: string;
  searchImages(
    query: string,
    options?: { limit?: number; category?: string },
    worker?: AIWorker
  ): Promise<ImageSearchResult[]>;
  healthCheck(worker?: AIWorker): Promise<boolean>;
  supportsFeature(feature: string): boolean;
  estimateLatency(worker?: AIWorker): Promise<number>;
  estimateQuota(worker?: AIWorker): Promise<number>;
}

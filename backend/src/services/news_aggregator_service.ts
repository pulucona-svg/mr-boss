import { NewsPublishingPipeline } from './news_publishing_pipeline';
import { CollectionResult } from '../models/news_article.model';

export class NewsAggregatorService {
  private pipeline: NewsPublishingPipeline;

  constructor() {
    this.pipeline = new NewsPublishingPipeline();
  }

  public async collectAndProcess(query?: string): Promise<CollectionResult> {
    return this.pipeline.executePipeline(query);
  }
}

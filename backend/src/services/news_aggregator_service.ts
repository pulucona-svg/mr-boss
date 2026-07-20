import { NewsApiCollector } from '../collectors/news_api_collector';
import { NewsDataCollector } from '../collectors/news_data_collector';
import { NormalizationService } from './normalization_service';
import { DeduplicationService } from './deduplication_service';
import {
  AppCategory,
  APP_CATEGORIES,
  CollectionResult,
  CollectionStats,
  NormalizedArticle,
} from '../models/news_article.model';
import { Logger } from '../utils/logger';
import { config } from '../config/environment';

export class NewsAggregatorService {
  private newsApiCollector: NewsApiCollector;
  private newsDataCollector: NewsDataCollector;

  constructor() {
    this.newsApiCollector = new NewsApiCollector(config.newsApiKey);
    this.newsDataCollector = new NewsDataCollector(config.newsDataApiKey);
  }

  /**
   * Orchestrates news collection, normalization, filtering, and deduplication.
   */
  public async collectAndProcess(query?: string): Promise<CollectionResult> {
    const searchQuery = query || config.defaultQuery;
    Logger.logHeader(`STARTING NEWS COLLECTION (Query: "${searchQuery}")`);

    // 1. Fetch from NewsAPI.org with fallback error handling
    let rawNewsApiArticles: any[] = [];
    try {
      rawNewsApiArticles = await this.newsApiCollector.fetchArticles(searchQuery);
    } catch (err: any) {
      Logger.error('Error during NewsAPI collection:', err.message || err);
    }

    // 2. Fetch from NewsData.io with fallback error handling
    let rawNewsDataArticles: any[] = [];
    try {
      rawNewsDataArticles = await this.newsDataCollector.fetchArticles('Kenya');
    } catch (err: any) {
      Logger.error('Error during NewsData collection:', err.message || err);
    }

    const countNewsApi = rawNewsApiArticles.length;
    const countNewsData = rawNewsDataArticles.length;
    const totalFetched = countNewsApi + countNewsData;

    Logger.info(
      `Raw articles gathered - NewsAPI: ${countNewsApi}, NewsData: ${countNewsData}, Total: ${totalFetched}`
    );

    // 3. Normalize & filter incomplete articles
    const normalizedArticles: NormalizedArticle[] = [];
    let filteredIncompleteCount = 0;

    for (const rawArticle of rawNewsApiArticles) {
      const normalized = NormalizationService.normalizeNewsApiArticle(rawArticle);
      if (normalized) {
        normalizedArticles.push(normalized);
      } else {
        filteredIncompleteCount++;
      }
    }

    for (const rawArticle of rawNewsDataArticles) {
      const normalized = NormalizationService.normalizeNewsDataArticle(rawArticle);
      if (normalized) {
        normalizedArticles.push(normalized);
      } else {
        filteredIncompleteCount++;
      }
    }

    // 4. Intelligently remove duplicates
    const { uniqueArticles, duplicatesRemovedCount } =
      DeduplicationService.deduplicate(normalizedArticles);

    // 5. Compute category breakdown
    const categoryBreakdown: Record<AppCategory, number> = APP_CATEGORIES.reduce(
      (acc, cat) => {
        acc[cat] = 0;
        return acc;
      },
      {} as Record<AppCategory, number>
    );

    for (const article of uniqueArticles) {
      categoryBreakdown[article.category] = (categoryBreakdown[article.category] || 0) + 1;
    }

    // 6. Build stats summary
    const stats: CollectionStats = {
      receivedFromNewsApi: countNewsApi,
      receivedFromNewsData: countNewsData,
      totalFetched,
      filteredIncomplete: filteredIncompleteCount,
      duplicatesRemoved: duplicatesRemovedCount,
      finalCount: uniqueArticles.length,
      categoryBreakdown,
    };

    // 7. Log summary
    Logger.logSummary(stats);

    return {
      stats,
      articles: uniqueArticles,
    };
  }
}

import { NewsApiCollector } from '../collectors/news_api_collector';
import { NewsDataCollector } from '../collectors/news_data_collector';
import { NormalizationService } from './normalization_service';
import { DeduplicationService } from './deduplication_service';
import {
  AppCategory,
  APP_CATEGORIES,
  CollectionResult,
  CollectionStats,
  NormalizedNews,
  RegionPriority,
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
   * Orchestrates news collection, normalization, quality filtering, deduplication, scoring, and classification.
   */
  public async collectAndProcess(query?: string): Promise<CollectionResult> {
    const searchQuery = query || config.defaultQuery;
    Logger.logHeader(`STARTING INTELLIGENT NEWS PIPELINE (Query: "${searchQuery}")`);

    // 1. Fetch from NewsAPI.org
    let rawNewsApiArticles: any[] = [];
    try {
      rawNewsApiArticles = await this.newsApiCollector.fetchArticles(searchQuery);
    } catch (err: any) {
      Logger.error('Error during NewsAPI collection:', err.message || err);
    }

    // 2. Fetch from NewsData.io
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

    // 3. Normalize & Quality Filter
    const candidateArticles: NormalizedNews[] = [];
    let filteredIncompleteCount = 0;
    let filteredLowQualityCount = 0;

    for (const rawArticle of rawNewsApiArticles) {
      if (!rawArticle.title || !rawArticle.url) {
        filteredIncompleteCount++;
        continue;
      }
      const normalized = NormalizationService.normalizeNewsApiArticle(rawArticle);
      if (normalized) {
        candidateArticles.push(normalized);
      } else {
        filteredLowQualityCount++;
      }
    }

    for (const rawArticle of rawNewsDataArticles) {
      if (!rawArticle.title || !rawArticle.link) {
        filteredIncompleteCount++;
        continue;
      }
      const normalized = NormalizationService.normalizeNewsDataArticle(rawArticle);
      if (normalized) {
        candidateArticles.push(normalized);
      } else {
        filteredLowQualityCount++;
      }
    }

    // 4. Intelligent Deduplication & Highest-Scoring Version Selection
    const { uniqueArticles, duplicatesRemovedCount } =
      DeduplicationService.deduplicate(candidateArticles);

    // 5. Compute Category & Region Breakdown
    const categoryBreakdown: Record<AppCategory, number> = APP_CATEGORIES.reduce(
      (acc, cat) => {
        acc[cat] = 0;
        return acc;
      },
      {} as Record<AppCategory, number>
    );

    const regionBreakdown: Record<RegionPriority, number> = {
      Kenya: 0,
      'East Africa': 0,
      Africa: 0,
      World: 0,
    };

    for (const article of uniqueArticles) {
      categoryBreakdown[article.category] = (categoryBreakdown[article.category] || 0) + 1;
      regionBreakdown[article.regionPriority] =
        (regionBreakdown[article.regionPriority] || 0) + 1;
    }

    // Sort final output: Kenya first, then higher qualityScore, then freshness
    uniqueArticles.sort((a, b) => {
      if (b.regionScore !== a.regionScore) {
        return b.regionScore - a.regionScore;
      }
      if (b.qualityScore !== a.qualityScore) {
        return b.qualityScore - a.qualityScore;
      }
      return b.freshnessScore - a.freshnessScore;
    });

    // 6. Build Stats Summary
    const stats: CollectionStats = {
      receivedFromNewsApi: countNewsApi,
      receivedFromNewsData: countNewsData,
      totalFetched,
      filteredIncomplete: filteredIncompleteCount,
      filteredLowQuality: filteredLowQualityCount,
      duplicatesRemoved: duplicatesRemovedCount,
      finalCount: uniqueArticles.length,
      categoryBreakdown,
      regionBreakdown,
    };

    // 7. Log Summary
    Logger.logSummary(stats);

    return {
      stats,
      articles: uniqueArticles,
    };
  }
}

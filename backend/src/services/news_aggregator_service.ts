import { NewsApiCollector } from '../collectors/news_api_collector';
import { NewsDataCollector } from '../collectors/news_data_collector';
import { NormalizationService } from './normalization_service';
import { DeduplicationService } from './deduplication_service';
import { RankingService } from './ranking_service';
import { ClusteringService } from './clustering_service';
import {
  AppCategory,
  APP_CATEGORIES,
  CollectionResult,
  CollectionStats,
  NewsPackage,
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
   * Orchestrates the complete News Ranking & Editorial Engine pipeline.
   * Produces a unified NewsPackage ready for Phase-3 storage.
   */
  public async collectAndProcess(query?: string): Promise<CollectionResult> {
    const searchQuery = query || config.defaultQuery;
    Logger.logHeader(`STARTING EDITORIAL & RANKING ENGINE (Query: "${searchQuery}")`);

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

    // 4. Intelligent Deduplication
    const { uniqueArticles, duplicatesRemovedCount } =
      DeduplicationService.deduplicate(candidateArticles);

    // 5. Calculate Importance Scores
    for (const article of uniqueArticles) {
      article.importanceScore = RankingService.calculateImportanceScore(article);
    }

    // 6. Story Clustering
    const storyClusters = ClusteringService.clusterArticles(uniqueArticles);

    // 7. Top Story Selection (Top 5)
    const topStories = RankingService.selectTopStories(uniqueArticles);

    // 8. Trending Detection (Top 10)
    const { trendingArticles, trendingPackageTopics } = RankingService.detectTrending(
      uniqueArticles,
      storyClusters
    );

    // 9. Organize Articles into Categories & Regional Priority
    const categoryNews: Record<AppCategory, NormalizedNews[]> = APP_CATEGORIES.reduce(
      (acc, cat) => {
        acc[cat] = [];
        return acc;
      },
      {} as Record<AppCategory, NormalizedNews[]>
    );

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

      if (categoryNews[article.category]) {
        categoryNews[article.category].push(article);
      }
    }

    // Sort latest news feed by importanceScore and freshness
    const latestNews = [...uniqueArticles].sort((a, b) => {
      if (b.importanceScore !== a.importanceScore) {
        return b.importanceScore - a.importanceScore;
      }
      return b.freshnessScore - a.freshnessScore;
    });

    // 10. Build Final NewsPackage Output
    const nowIso = new Date().toISOString();
    const stats: CollectionStats = {
      receivedFromNewsApi: countNewsApi,
      receivedFromNewsData: countNewsData,
      totalFetched,
      filteredIncomplete: filteredIncompleteCount,
      filteredLowQuality: filteredLowQualityCount,
      duplicatesRemoved: duplicatesRemovedCount,
      finalCount: uniqueArticles.length,
      topStoriesCount: topStories.length,
      trendingCount: trendingPackageTopics.length,
      clustersCount: storyClusters.length,
      categoryBreakdown,
      regionBreakdown,
    };

    const newsPackage: NewsPackage = {
      generatedAt: nowIso,
      stats,
      topStories,
      trendingTopics: trendingPackageTopics,
      latestNews,
      categoryNews,
      storyClusters,
      totalCleanArticles: uniqueArticles.length,
    };

    // 11. Log Summary
    Logger.logSummary(stats);

    return {
      stats,
      package: newsPackage,
      articles: uniqueArticles,
    };
  }
}

import {
  NormalizedNews,
  StoryCluster,
  TrendingPackageTopic,
} from '../models/news_article.model';

export class RankingService {
  /**
   * Calculates overall Importance Score (0 to 100) based on Editorial Rules
   */
  public static calculateImportanceScore(article: NormalizedNews): number {
    let score = 0;

    // 1. Regional Relevance (Max 25 pts)
    switch (article.regionPriority) {
      case 'Kenya':
        score += 25;
        break;
      case 'East Africa':
        score += 20;
        break;
      case 'Africa':
        score += 15;
        break;
      case 'World':
        score += 10;
        break;
    }

    // 2. Breaking News Status (Max 20 pts)
    if (article.category === 'Breaking' || article.secondaryCategories.includes('Breaking')) {
      score += 20;
    }

    // 3. Trusted Publisher Boost (Max 15 pts)
    if (article.qualityScore >= 80) {
      score += 15;
    } else if (article.qualityScore >= 60) {
      score += 10;
    } else {
      score += 5;
    }

    // 4. Freshness Boost (Max 15 pts)
    score += Math.round(article.freshnessScore * 15);

    // 5. Impact Topics Keywords (Max 25 pts)
    const text = `${article.title} ${article.summary}`.toLowerCase();

    if (/\b(government|ruto|state house|parliament|gazette|ministry|policy|cabinet|tax|bill)\b/i.test(text)) {
      score += 10;
    }

    if (/\b(disaster|emergency|flood|drought|tragedy|accident|explosion|rescue|fire)\b/i.test(text)) {
      score += 15;
    }

    if (/\b(university|kcse|knec|tsc|school|education|curriculum|exam)\b/i.test(text)) {
      score += 10;
    }

    if (/\b(health|outbreak|hospital|who|vaccine|virus|disease|epidemic)\b/i.test(text)) {
      score += 10;
    }

    if (/\b(final|championship|gold|trophy|olympics|afcon|cup|winner|record)\b/i.test(text)) {
      score += 10;
    }

    if (/\b(ai|artificial intelligence|breakthrough|launch|patent|spacex|quantum|cyber)\b/i.test(text)) {
      score += 10;
    }

    return Math.min(100, score);
  }

  /**
   * Selects Top 5 Top Stories based on Importance Score & Quality
   */
  public static selectTopStories(articles: NormalizedNews[]): NormalizedNews[] {
    // Sort candidate articles by importanceScore descending, tie-breaking by qualityScore
    const sorted = [...articles].sort((a, b) => {
      if (b.importanceScore !== a.importanceScore) {
        return b.importanceScore - a.importanceScore;
      }
      return b.qualityScore - a.qualityScore;
    });

    const count = Math.min(sorted.length, Math.max(4, Math.min(5, sorted.length)));
    const topStories = sorted.slice(0, count);

    topStories.forEach((art, index) => {
      art.isTopStory = true;
      art.topStoryRank = index + 1;
    });

    return topStories;
  }

  /**
   * Detects and extracts Top 10 Trending Topics & Articles
   */
  public static detectTrending(
    articles: NormalizedNews[],
    clusters: StoryCluster[]
  ): { trendingArticles: NormalizedNews[]; trendingPackageTopics: TrendingPackageTopic[] } {
    // 1. Calculate trending score for each cluster
    const clusterScores: { cluster: StoryCluster; score: number }[] = clusters.map((cluster) => {
      const main = cluster.mainArticle;
      // Coverage bonus: multiple publishers reporting same story (+20 pts per additional publisher)
      const clusterCoverageBonus = Math.min(40, (cluster.clusterSize - 1) * 20);
      const isBreakingBonus = main.category === 'Breaking' ? 25 : 0;
      const freshnessBonus = main.freshnessScore * 25;

      const totalTrendingScore = main.importanceScore + clusterCoverageBonus + isBreakingBonus + freshnessBonus;

      return { cluster, score: totalTrendingScore };
    });

    // Sort clusters by trending score descending
    clusterScores.sort((a, b) => b.score - a.score);

    const topTrendingClusters = clusterScores.slice(0, 10);
    const trendingArticles: NormalizedNews[] = [];
    const trendingPackageTopics: TrendingPackageTopic[] = [];

    topTrendingClusters.forEach((item, index) => {
      const cluster = item.cluster;
      const main = cluster.mainArticle;

      main.isTrending = true;
      main.trendingRank = index + 1;
      trendingArticles.push(main);

      // Map cluster to UI-ready TrendingPackageTopic for Explore screen
      const iconInfo = RankingService.getCategoryIconAndGradients(main.category);

      const images = [
        main.imageUrl,
        ...cluster.relatedArticles.map((r) => r.imageUrl).filter(Boolean),
      ].slice(0, 3);

      trendingPackageTopics.push({
        id: cluster.clusterId,
        title: main.title,
        clusterSize: cluster.clusterSize,
        iconName: iconInfo.iconName,
        gradientColors: iconInfo.gradientColors,
        imageUrls: images,
        description: main.summary,
        details: {
          'Why it\'s Trending': `Covered by ${cluster.clusterSize} news sources with high engagement.`,
          'Recent Activity': `Latest update ${RankingService.formatTimeAgo(main.publishedAt)}.`,
          'Primary Category': main.category,
          'Region Focus': main.regionPriority,
        },
        source: `${main.sourceName}${cluster.clusterSize > 1 ? ` +${cluster.clusterSize - 1} sources` : ''}`,
        timeAgo: RankingService.formatTimeAgo(main.publishedAt),
        importanceScore: Math.round(item.score),
      });
    });

    return { trendingArticles, trendingPackageTopics };
  }

  private static formatTimeAgo(dateIso: string): string {
    try {
      const diffMs = new Date().getTime() - new Date(dateIso).getTime();
      const diffMins = Math.floor(diffMs / (1000 * 60));
      if (diffMins < 60) return `${diffMins}m ago`;
      const diffHrs = Math.floor(diffMins / 60);
      if (diffHrs < 24) return `${diffHrs}h ago`;
      return `${Math.floor(diffHrs / 24)}d ago`;
    } catch {
      return 'Just now';
    }
  }

  private static getCategoryIconAndGradients(category: string): {
    iconName: string;
    gradientColors: string[];
  } {
    switch (category) {
      case 'Technology':
        return { iconName: 'memory_rounded', gradientColors: ['#00F2FF', '#0072FF'] };
      case 'Politics':
        return { iconName: 'gavel_rounded', gradientColors: ['#FF512F', '#DD2476'] };
      case 'Business':
        return { iconName: 'trending_up_rounded', gradientColors: ['#11998e', '#38ef7d'] };
      case 'Sports':
        return { iconName: 'sports_soccer_rounded', gradientColors: ['#FF9966', '#FF5E62'] };
      case 'Health':
        return { iconName: 'health_and_safety_rounded', gradientColors: ['#8E2DE2', '#4A00E0'] };
      case 'Education':
        return { iconName: 'school_rounded', gradientColors: ['#F2994A', '#F2C94C'] };
      case 'Breaking':
        return { iconName: 'bolt_rounded', gradientColors: ['#FF0000', '#FF7300'] };
      default:
        return { iconName: 'newspaper_rounded', gradientColors: ['#20C8FF', '#287BFF'] };
    }
  }
}

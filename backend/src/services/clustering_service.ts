import { NormalizedNews, StoryCluster } from '../models/news_article.model';
import { DeduplicationService } from './deduplication_service';
import crypto from 'crypto';

export class ClusteringService {
  /**
   * Clusters related articles discussing the same story/event.
   */
  public static clusterArticles(articles: NormalizedNews[]): StoryCluster[] {
    const clusterMap: Map<string, NormalizedNews[]> = new Map();
    const articleClusterMap: Map<string, string> = new Map();

    let clusterCounter = 1;

    for (const article of articles) {
      let matchedClusterId: string | null = null;

      // Check if article matches any existing cluster main article
      for (const [cId, clusterList] of clusterMap.entries()) {
        const representative = clusterList[0];
        if (DeduplicationService.areArticlesDuplicate(article, representative)) {
          matchedClusterId = cId;
          break;
        }
      }

      if (matchedClusterId) {
        clusterMap.get(matchedClusterId)!.push(article);
        article.clusterId = matchedClusterId;
      } else {
        const newClusterId = `cluster_${Date.now()}_${clusterCounter++}_${crypto
          .randomBytes(3)
          .toString('hex')}`;
        clusterMap.set(newClusterId, [article]);
        article.clusterId = newClusterId;
      }
    }

    const storyClusters: StoryCluster[] = [];

    for (const [cId, group] of clusterMap.entries()) {
      // Sort cluster by importanceScore descending
      group.sort((a, b) => b.importanceScore - a.importanceScore);

      const mainArticle = group[0];
      const relatedArticles = group.slice(1);

      storyClusters.push({
        clusterId: cId,
        topicTitle: mainArticle.title,
        clusterSize: group.length,
        mainArticle,
        relatedArticles,
        createdAt: mainArticle.publishedAt || new Date().toISOString(),
      });
    }

    return storyClusters;
  }
}

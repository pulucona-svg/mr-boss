import { NormalizedArticle } from '../models/news_article.model';
import { StringUtils } from '../utils/string_utils';

export interface DeduplicationResult {
  uniqueArticles: NormalizedArticle[];
  duplicatesRemovedCount: number;
}

export class DeduplicationService {
  /**
   * Intelligently removes duplicate articles based on normalized title or source URL.
   */
  public static deduplicate(articles: NormalizedArticle[]): DeduplicationResult {
    const seenTitles = new Set<string>();
    const seenUrls = new Set<string>();
    const seenIds = new Set<string>();
    const uniqueArticles: NormalizedArticle[] = [];
    let duplicatesCount = 0;

    for (const article of articles) {
      const normalizedTitle = StringUtils.normalizeTitle(article.title);
      const normalizedUrl = StringUtils.normalizeUrl(article.sourceUrl);
      const articleId = article.id;

      // Check if title, URL, or ID has been seen
      if (seenTitles.has(normalizedTitle) || seenUrls.has(normalizedUrl) || seenIds.has(articleId)) {
        duplicatesCount++;
        continue;
      }

      // Mark as seen
      seenTitles.add(normalizedTitle);
      seenUrls.add(normalizedUrl);
      seenIds.add(articleId);

      uniqueArticles.push(article);
    }

    return {
      uniqueArticles,
      duplicatesRemovedCount: duplicatesCount,
    };
  }
}

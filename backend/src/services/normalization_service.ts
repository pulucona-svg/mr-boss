import {
  NewsApiArticle,
  NewsDataArticle,
  NormalizedArticle,
} from '../models/news_article.model';
import { ClassificationService } from './classification_service';
import { StringUtils } from '../utils/string_utils';

export class NormalizationService {
  /**
   * Normalizes a raw NewsAPI.org article into standard NormalizedArticle format.
   * Returns null if missing title, image, or content/description.
   */
  public static normalizeNewsApiArticle(article: NewsApiArticle): NormalizedArticle | null {
    const title = article.title?.trim();
    const imageUrl = article.urlToImage?.trim();
    const description = article.description?.trim() || '';
    const content = article.content?.trim() || '';

    // Requirement 4: Ignore articles without title, image, content/description
    if (!title || title === '[Removed]' || !imageUrl || (!description && !content)) {
      return null;
    }

    const sourceUrl = article.url?.trim() || '';
    if (!sourceUrl) return null;

    const publishedAt = article.publishedAt || new Date().toISOString();
    const sourceName = article.source?.name || 'NewsAPI';
    const author = article.author?.trim() || null;
    const category = ClassificationService.classify(title, description);
    const slug = StringUtils.slugify(title);
    const id = StringUtils.generateArticleId(sourceUrl, title);
    const now = new Date().toISOString();

    return {
      id,
      title,
      summary: description || content.slice(0, 200),
      content: content || description,
      imageUrl,
      sourceUrl,
      publishedAt,
      sourceName,
      author,
      category,
      slug,
      createdAt: now,
      updatedAt: now,
      status: 'published',
      priority: 0,
    };
  }

  /**
   * Normalizes a raw NewsData.io article into standard NormalizedArticle format.
   * Returns null if missing title, image, or content/description.
   */
  public static normalizeNewsDataArticle(article: NewsDataArticle): NormalizedArticle | null {
    const title = article.title?.trim();
    const imageUrl = article.image_url?.trim();
    const description = article.description?.trim() || '';
    const content = article.content?.trim() || '';

    // Requirement 4: Ignore articles without title, image, content/description
    if (!title || !imageUrl || (!description && !content)) {
      return null;
    }

    const sourceUrl = article.link?.trim() || '';
    if (!sourceUrl) return null;

    const publishedAt = article.pubDate || new Date().toISOString();
    const sourceName = article.source_id || 'NewsData';
    const author = Array.isArray(article.creator) && article.creator.length > 0
      ? article.creator.join(', ')
      : null;

    const category = ClassificationService.classify(title, description, article.category || undefined);
    const slug = StringUtils.slugify(title);
    const id = StringUtils.generateArticleId(sourceUrl, title);
    const now = new Date().toISOString();

    return {
      id,
      title,
      summary: description || content.slice(0, 200),
      content: content || description,
      imageUrl,
      sourceUrl,
      publishedAt,
      sourceName,
      author,
      category,
      slug,
      createdAt: now,
      updatedAt: now,
      status: 'published',
      priority: 0,
    };
  }
}

import {
  NewsApiArticle,
  NewsDataArticle,
  NormalizedNews,
} from '../models/news_article.model';
import { QualityFilterService } from './quality_filter_service';
import { ClassificationService } from './classification_service';
import { ScoringService } from './scoring_service';
import { ExpirationService } from './expiration_service';
import { StringUtils } from '../utils/string_utils';

export class NormalizationService {
  /**
   * Normalizes a raw NewsAPI.org article into standard NormalizedNews format.
   * Returns null if it fails quality validation or is missing required fields.
   */
  public static normalizeNewsApiArticle(article: NewsApiArticle): NormalizedNews | null {
    const title = article.title?.trim() || '';
    const imageUrl = article.urlToImage?.trim() || '';
    const description = article.description?.trim() || '';
    const content = article.content?.trim() || '';

    const sourceUrl = article.url?.trim() || '';
    if (!sourceUrl) return null;

    // 1. Run Quality & Language Filtering
    const qualityResult = QualityFilterService.validateArticle(
      title,
      description || content,
      imageUrl
    );
    if (!qualityResult.isValid) {
      return null;
    }

    // 2. Perform Multi-Category & Regional Classification
    const classification = ClassificationService.classifyDetailed(title, description);

    // 3. Calculate Quality & Freshness Scores
    const publishedAt = article.publishedAt || new Date().toISOString();
    const sourceName = article.source?.name || 'NewsAPI';
    const scoreResult = ScoringService.calculateScores(
      title,
      description || content,
      imageUrl,
      sourceName,
      publishedAt
    );

    const nowIso = new Date().toISOString();
    const expiresAt = ExpirationService.calculateExpiration(
      classification.primaryCategory,
      publishedAt
    );

    const author = article.author?.trim() || null;
    const slug = StringUtils.slugify(title);
    const id = StringUtils.generateArticleId(sourceUrl, title);

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
      category: classification.primaryCategory,
      secondaryCategories: classification.secondaryCategories,
      regionPriority: classification.regionPriority,
      regionScore: classification.regionScore,
      slug,
      createdAt: publishedAt,
      updatedAt: nowIso,
      expiresAt,
      collectedAt: nowIso,
      qualityScore: scoreResult.qualityScore,
      freshnessScore: scoreResult.freshnessScore,
      scoreBreakdown: scoreResult.breakdown,
      status: 'published',
      priority: classification.regionScore,
    };
  }

  /**
   * Normalizes a raw NewsData.io article into standard NormalizedNews format.
   * Returns null if it fails quality validation or is missing required fields.
   */
  public static normalizeNewsDataArticle(article: NewsDataArticle): NormalizedNews | null {
    const title = article.title?.trim() || '';
    const imageUrl = article.image_url?.trim() || '';
    const description = article.description?.trim() || '';
    const content = article.content?.trim() || '';

    const sourceUrl = article.link?.trim() || '';
    if (!sourceUrl) return null;

    // 1. Run Quality & Language Filtering
    const qualityResult = QualityFilterService.validateArticle(
      title,
      description || content,
      imageUrl,
      article.language
    );
    if (!qualityResult.isValid) {
      return null;
    }

    // 2. Perform Multi-Category & Regional Classification
    const classification = ClassificationService.classifyDetailed(
      title,
      description,
      article.category || undefined
    );

    // 3. Calculate Quality & Freshness Scores
    const publishedAt = article.pubDate || new Date().toISOString();
    const sourceName = article.source_id || 'NewsData';
    const scoreResult = ScoringService.calculateScores(
      title,
      description || content,
      imageUrl,
      sourceName,
      publishedAt
    );

    const nowIso = new Date().toISOString();
    const expiresAt = ExpirationService.calculateExpiration(
      classification.primaryCategory,
      publishedAt
    );

    const author =
      Array.isArray(article.creator) && article.creator.length > 0
        ? article.creator.join(', ')
        : null;
    const slug = StringUtils.slugify(title);
    const id = StringUtils.generateArticleId(sourceUrl, title);

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
      category: classification.primaryCategory,
      secondaryCategories: classification.secondaryCategories,
      regionPriority: classification.regionPriority,
      regionScore: classification.regionScore,
      slug,
      createdAt: publishedAt,
      updatedAt: nowIso,
      expiresAt,
      collectedAt: nowIso,
      qualityScore: scoreResult.qualityScore,
      freshnessScore: scoreResult.freshnessScore,
      scoreBreakdown: scoreResult.breakdown,
      status: 'published',
      priority: classification.regionScore,
    };
  }
}

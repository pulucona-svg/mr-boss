import { NormalizedNews } from '../models/news_article.model';
import { Logger } from '../utils/logger';

export class ImageEnrichmentService {
  /**
   * Ensures every article has at least 4 unique relevant images related to its topic.
   * If fewer than 4 images exist, searches backend services (Wikimedia Commons API / related topic search)
   * to enrich and return at least 4 distinct topic-relevant images.
   */
  public static async enrichArticleImages(
    article: NormalizedNews,
    clusterImageUrls: string[] = []
  ): Promise<string[]> {
    const imagesSet = new Set<string>();

    if (article.imageUrl && article.imageUrl.trim().length > 0) {
      imagesSet.add(article.imageUrl.trim());
    }
    if (article.coverImage && article.coverImage.trim().length > 0) {
      imagesSet.add(article.coverImage.trim());
    }

    for (const url of clusterImageUrls) {
      if (url && url.trim().length > 0) {
        imagesSet.add(url.trim());
      }
    }

    if (imagesSet.size >= 4) {
      return Array.from(imagesSet).slice(0, 4);
    }

    // Search backend services for topic-related images
    try {
      const topicQuery = ImageEnrichmentService.extractTopicQuery(article.title, article.category);
      const fetchedImages = await ImageEnrichmentService.searchWikimediaImages(topicQuery);

      for (const imgUrl of fetchedImages) {
        if (imagesSet.size >= 6) break;
        imagesSet.add(imgUrl);
      }
    } catch (err: any) {
      Logger.warn(`[IMAGE_ENRICH] Topic image search note for '${article.title}': ${err.message || err}`);
    }

    return Array.from(imagesSet);
  }

  private static extractTopicQuery(title: string, category: string): string {
    const stopWords = new Set([
      'a', 'an', 'the', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with',
      'by', 'from', 'up', 'about', 'into', 'over', 'after', 'is', 'are', 'was', 'were',
      'be', 'been', 'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would',
      'shall', 'should', 'can', 'could', 'may', 'might', 'must', 'new', 'latest', 'update'
    ]);

    const words = title
      .replaceAll(/[^\w\s]/g, '')
      .split(/\s+/)
      .filter((w) => w.length > 2 && !stopWords.has(w.toLowerCase()));

    const keyWords = words.slice(0, 3).join(' ');
    return keyWords.length > 0 ? keyWords : category;
  }

  private static async searchWikimediaImages(query: string): Promise<string[]> {
    const results: string[] = [];
    const url = `https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrsearch=${encodeURIComponent(
      query
    )}&gsrlimit=10&prop=imageinfo&iiprop=url&format=json&origin=*`;

    const response = await fetch(url, {
      headers: {
        'User-Agent': 'MirrorLaikipia-NewsBackend/1.0 (https://mirrorlaikipia.com)',
      },
    });

    if (!response.ok) return results;

    const data = (await response.json()) as any;
    if (!data.query || !data.query.pages) return results;

    for (const pageId of Object.keys(data.query.pages)) {
      const page = data.query.pages[pageId];
      if (page.imageinfo && Array.isArray(page.imageinfo) && page.imageinfo[0]?.url) {
        const imgUrl = page.imageinfo[0].url as string;
        // Filter out non-web image formats like SVG/OGG
        if (/\.(jpg|jpeg|png|webp)/i.test(imgUrl)) {
          results.push(imgUrl);
        }
      }
    }

    return results;
  }
}

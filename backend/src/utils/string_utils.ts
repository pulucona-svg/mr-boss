import crypto from 'crypto';

export class StringUtils {
  /**
   * Generates a URL-friendly slug from a title string
   */
  public static slugify(text: string): string {
    return text
      .toLowerCase()
      .trim()
      .replace(/[^\w\s-]/g, '')
      .replace(/[\s_-]+/g, '-')
      .replace(/^-+|-+$/g, '');
  }

  /**
   * Normalizes a title for exact or fuzzy deduplication
   */
  public static normalizeTitle(title: string): string {
    return title
      .toLowerCase()
      .replace(/[^\w\s]/gi, '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  /**
   * Normalizes a URL for exact matching in deduplication
   */
  public static normalizeUrl(url: string): string {
    try {
      const parsed = new URL(url.trim());
      // Remove trailing slashes and tracking parameters
      parsed.searchParams.delete('utm_source');
      parsed.searchParams.delete('utm_medium');
      parsed.searchParams.delete('utm_campaign');
      return parsed.toString().replace(/\/$/, '').toLowerCase();
    } catch {
      return url.trim().toLowerCase();
    }
  }

  /**
   * Generates a deterministic unique ID for an article
   */
  public static generateArticleId(sourceUrl: string, title: string): string {
    const data = `${sourceUrl.trim()}_${title.trim()}`;
    return crypto.createHash('md5').update(data).digest('hex');
  }
}

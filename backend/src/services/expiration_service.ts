import { AppCategory } from '../models/news_article.model';
import { config } from '../config/environment';

export class ExpirationService {
  /**
   * Category specific TTL rules (in hours)
   */
  private static readonly CATEGORY_EXPIRY_HOURS: Partial<Record<AppCategory, number>> = {
    Breaking: 12,
    Politics: 24,
    Business: 24,
    Technology: 36,
    Education: 48,
    Science: 48,
    Health: 36,
    Sports: 24,
    Entertainment: 24,
    World: 24,
    Africa: 24,
    Kenya: 36,
  };

  /**
   * Calculates expiration ISO string based on article category and publication/collection time.
   */
  public static calculateExpiration(
    category: AppCategory,
    baseDateIso: string,
    customExpiryHours?: number
  ): string {
    const hours =
      customExpiryHours ||
      ExpirationService.CATEGORY_EXPIRY_HOURS[category] ||
      config.defaultExpiryHours;

    const baseTime = new Date(baseDateIso).getTime();
    const expiryTime = baseTime + hours * 60 * 60 * 1000;
    return new Date(expiryTime).toISOString();
  }
}

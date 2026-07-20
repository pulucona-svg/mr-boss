import { AppCategory } from '../models/news_article.model';
import { config } from '../config/environment';

export class ExpirationService {
  /**
   * Configurable category-specific TTL rules (in hours)
   */
  public static categoryExpiryHoursConfig: Record<AppCategory, number> = {
    Breaking: 12,
    Politics: 24,
    Business: 24,
    Technology: 48,
    Education: 72,
    Science: 72,
    Health: 48,
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
      ExpirationService.categoryExpiryHoursConfig[category] ||
      config.defaultExpiryHours;

    const baseTime = new Date(baseDateIso).getTime();
    const expiryTime = baseTime + hours * 60 * 60 * 1000;
    return new Date(expiryTime).toISOString();
  }
}

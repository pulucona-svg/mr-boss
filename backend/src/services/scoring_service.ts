import { ScoreBreakdown } from '../models/news_article.model';

export class ScoringService {
  // Known trusted news publishers & domains
  private static readonly TRUSTED_PUBLISHERS = [
    'reuters',
    'bbc news',
    'bbc',
    'daily nation',
    'nation media',
    'the standard',
    'standard media',
    'capital fm',
    'the star kenya',
    'the star',
    'business daily',
    'bloomberg',
    'al jazeera',
    'techcrunch',
    'cnn',
    'associated press',
    'ap news',
    'afp',
    'financial times',
    'the guardian',
    'citizen digital',
    'nation.africa',
    'standardmedia.co.ke',
  ];

  /**
   * Calculates overall quality score (0 to 100) and freshness score (0.0 to 1.0)
   */
  public static calculateScores(
    title: string,
    description: string,
    imageUrl: string,
    sourceName: string,
    publishedAt: string
  ): { qualityScore: number; freshnessScore: number; breakdown: ScoreBreakdown } {
    // 1. Title Quality Score (Max 25 pts)
    const titleScore = ScoringService.evaluateTitleQuality(title);

    // 2. Image Quality Score (Max 20 pts)
    const imageScore = ScoringService.evaluateImageQuality(imageUrl);

    // 3. Description Depth Score (Max 25 pts)
    const descriptionScore = ScoringService.evaluateDescriptionDepth(description);

    // 4. Trusted Publisher Score (Max 20 pts)
    const publisherScore = ScoringService.evaluatePublisherTrust(sourceName);

    // 5. Freshness Score (0.0 to 1.0, Max 10 pts in overall score)
    const freshnessScore = ScoringService.calculateFreshnessScore(publishedAt);
    const freshnessPts = Math.round(freshnessScore * 10);

    const totalScore = Math.min(
      100,
      titleScore + imageScore + descriptionScore + publisherScore + freshnessPts
    );

    const breakdown: ScoreBreakdown = {
      titleQualityScore: titleScore,
      imageQualityScore: imageScore,
      descriptionDepthScore: descriptionScore,
      publisherTrustScore: publisherScore,
      freshnessScore,
      totalScore,
    };

    return {
      qualityScore: totalScore,
      freshnessScore,
      breakdown,
    };
  }

  /**
   * Evaluates Title Quality (0 - 25 pts)
   */
  private static evaluateTitleQuality(title: string): number {
    const len = title.trim().length;
    let score = 0;

    if (len >= 30 && len <= 110) {
      score += 15; // Ideal headline length
    } else if (len >= 20 && len <= 140) {
      score += 10;
    } else {
      score += 5;
    }

    // Title starts with Capital letter
    if (/^[A-Z]/.test(title.trim())) {
      score += 5;
    }

    // Proper word count (5 to 18 words)
    const words = title.trim().split(/\s+/).length;
    if (words >= 6 && words <= 16) {
      score += 5;
    }

    return Math.min(25, score);
  }

  /**
   * Evaluates Image Quality (0 - 20 pts)
   */
  private static evaluateImageQuality(imageUrl: string): number {
    let score = 10; // Base valid image score

    // HTTPS preference
    if (imageUrl.startsWith('https://')) {
      score += 5;
    }

    // Standard high quality image extensions or CDN paths
    if (/\.(jpg|jpeg|png|webp)(\?.*)?$/i.test(imageUrl)) {
      score += 5;
    }

    return Math.min(20, score);
  }

  /**
   * Evaluates Description Depth & Richness (0 - 25 pts)
   */
  private static evaluateDescriptionDepth(description: string): number {
    const len = description.trim().length;
    let score = 0;

    if (len >= 200) {
      score += 25;
    } else if (len >= 120) {
      score += 20;
    } else if (len >= 80) {
      score += 15;
    } else if (len >= 50) {
      score += 10;
    } else {
      score += 5;
    }

    return score;
  }

  /**
   * Evaluates Publisher Trust (0 - 20 pts)
   */
  private static evaluatePublisherTrust(sourceName: string): number {
    const normalized = sourceName.toLowerCase();
    for (const trusted of ScoringService.TRUSTED_PUBLISHERS) {
      if (normalized.includes(trusted)) {
        return 20; // High trust bonus
      }
    }
    return 10; // Standard baseline publisher
  }

  /**
   * Calculates Freshness Score (0.0 to 1.0) based on hours elapsed since publication
   */
  public static calculateFreshnessScore(publishedAt: string): number {
    try {
      const pubDate = new Date(publishedAt).getTime();
      const now = new Date().getTime();
      const hoursDiff = (now - pubDate) / (1000 * 60 * 60);

      if (isNaN(hoursDiff) || hoursDiff < 0) return 0.8;

      if (hoursDiff <= 2) return 1.0;
      if (hoursDiff <= 6) return 0.9;
      if (hoursDiff <= 12) return 0.8;
      if (hoursDiff <= 24) return 0.6;
      if (hoursDiff <= 48) return 0.4;
      return 0.2;
    } catch {
      return 0.5;
    }
  }
}

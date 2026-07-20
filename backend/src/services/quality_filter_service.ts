import { Logger } from '../utils/logger';
import { config } from '../config/environment';

export interface QualityValidationResult {
  isValid: boolean;
  reason?: string;
}

export class QualityFilterService {
  private static readonly PLACEHOLDER_PATTERNS = [
    /placeholder/i,
    /default_image/i,
    /no[-_]?image/i,
    /1x1/i,
    /pixel\.gif/i,
    /blank\.png/i,
    /missing\.jpg/i,
    /avatar/i,
    /dummy/i,
    /fallback/i,
    /stock[-_]?photo[-_]?generic/i,
    /sample[-_]?image/i,
  ];

  private static readonly LOW_QUALITY_KEYWORDS = [
    /\b\[removed\]\b/i,
    /\b\[deleted\]\b/i,
    /\badvertisement\b/i,
    /\bsponsored content\b/i,
    /\b404 not found\b/i,
    /\bpage not found\b/i,
    /\bcontent removed\b/i,
    /\barticle deleted\b/i,
    /\berror 404\b/i,
    /\baccess denied\b/i,
    /\bsubscribe to read\b/i,
    /\bpaywall\b/i,
  ];

  private static readonly CLICKBAIT_PATTERNS = [
    /\b(you won't believe|what happened next|will blow your mind|shocking truth|click here|top \d+ reasons|number \d+ will|secret revealed)\b/i,
    /!{2,}/, // Excessive exclamation points like !! or !!!
    /\?{2,}/, // Excessive question marks
  ];

  /**
   * Evaluates an article's quality and returns whether it meets quality standards.
   */
  public static validateArticle(
    title: string,
    description: string,
    imageUrl: string,
    language?: string
  ): QualityValidationResult {
    // 1. Check Language
    if (language && !language.toLowerCase().startsWith('en')) {
      return { isValid: false, reason: `Non-English language code: "${language}"` };
    }

    // Heuristic English check: ensure text uses basic Latin characters and contains English common words
    if (!QualityFilterService.isEnglishText(`${title} ${description}`)) {
      return { isValid: false, reason: 'Text failed English language heuristic check' };
    }

    // 2. Title validation
    const trimmedTitle = title.trim();
    if (!trimmedTitle || trimmedTitle.length < 15) {
      return { isValid: false, reason: 'Title too short (< 15 characters)' };
    }

    // 3. Clickbait & Excessive CAPS Check
    if (QualityFilterService.isObviousClickbait(trimmedTitle)) {
      return { isValid: false, reason: 'Rejected: Obvious clickbait title or excessive ALL-CAPS' };
    }

    // 4. Description length check
    const trimmedDesc = description.trim();
    if (!trimmedDesc || trimmedDesc.length < config.minDescriptionLength) {
      return {
        isValid: false,
        reason: `Description too short (${trimmedDesc.length} chars < ${config.minDescriptionLength})`,
      };
    }

    const wordCount = trimmedDesc.split(/\s+/).length;
    if (wordCount < 8) {
      return { isValid: false, reason: `Word count too low (${wordCount} words < 8)` };
    }

    // 5. Low Quality / Junk Content Keywords Check
    const combinedText = `${trimmedTitle} ${trimmedDesc}`;
    for (const pattern of QualityFilterService.LOW_QUALITY_KEYWORDS) {
      if (pattern.test(combinedText)) {
        return { isValid: false, reason: `Contains low quality keyword matching ${pattern}` };
      }
    }

    // 6. Image URL validation & Placeholder check
    const imageValidation = QualityFilterService.validateImage(imageUrl);
    if (!imageValidation.isValid) {
      return imageValidation;
    }

    return { isValid: true };
  }

  /**
   * Validates image URL format and checks for placeholder patterns.
   */
  public static validateImage(imageUrl?: string): QualityValidationResult {
    if (!imageUrl || typeof imageUrl !== 'string') {
      return { isValid: false, reason: 'Missing image URL' };
    }

    const trimmedUrl = imageUrl.trim();
    if (!trimmedUrl.startsWith('http://') && !trimmedUrl.startsWith('https://')) {
      return { isValid: false, reason: 'Invalid image URL protocol (must be http/https)' };
    }

    if (trimmedUrl.length < 15) {
      return { isValid: false, reason: 'Image URL too short' };
    }

    // Check placeholder keywords in URL
    for (const pattern of QualityFilterService.PLACEHOLDER_PATTERNS) {
      if (pattern.test(trimmedUrl)) {
        return { isValid: false, reason: `Image matches placeholder pattern: ${pattern}` };
      }
    }

    return { isValid: true };
  }

  /**
   * Detects clickbait title patterns or excessive uppercase formatting.
   */
  public static isObviousClickbait(title: string): boolean {
    // Check clickbait regexes
    for (const pattern of QualityFilterService.CLICKBAIT_PATTERNS) {
      if (pattern.test(title)) return true;
    }

    // Check excessive ALL-CAPS (e.g. > 65% of letters are uppercase)
    const letters = title.replace(/[^a-zA-Z]/g, '');
    if (letters.length >= 10) {
      const upperCount = (title.match(/[A-Z]/g) || []).length;
      if (upperCount / letters.length > 0.65) {
        return true;
      }
    }

    return false;
  }

  /**
   * Simple heuristic to confirm text is written in English.
   */
  private static isEnglishText(text: string): boolean {
    // Basic test for non-Latin scripts (Arabic, Cyrillic, Chinese, CJK, Devangari, etc.)
    const nonLatinRegex = /[\u0600-\u06FF\u0400-\u04FF\u4E00-\u9FFF\u3040-\u309F\u30A0-\u30FF\u0900-\u097F]/;
    if (nonLatinRegex.test(text)) {
      return false;
    }

    // Check presence of at least two common English stopwords
    const commonEnglishWords = /\b(the|and|in|of|to|a|is|for|on|with|that|as|at|by|from|an|be|it|are|was)\b/i;
    const matches = text.match(new RegExp(commonEnglishWords, 'gi'));
    return matches !== null && matches.length >= 2;
  }
}

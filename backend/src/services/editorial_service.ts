export class EditorialService {
  /**
   * Generates a clean 80-120 word editorial summary without inventing details.
   */
  public static generateEditorialSummary(title: string, summary: string, content: string): string {
    const rawText = `${title}. ${summary} ${content}`.replace(/\s+/g, ' ').trim();
    
    // Clean unwanted boilerplates or tags
    const cleaned = rawText
      .replace(/\[\+\d+ chars\]/gi, '')
      .replace(/read full article|click here for more|image credit:|source:|copyright/gi, '')
      .replace(/\s+/g, ' ')
      .trim();

    const words = cleaned.split(' ');

    if (words.length >= 80 && words.length <= 120) {
      return words.join(' ');
    }

    if (words.length > 120) {
      // Truncate cleanly at sentence boundary around 80-120 words
      const targetText = words.slice(0, 115).join(' ');
      const lastPeriodIndex = targetText.lastIndexOf('.');
      if (lastPeriodIndex > 250) {
        return targetText.substring(0, lastPeriodIndex + 1);
      }
      return targetText + '...';
    }

    // If text is shorter than 80 words, polish and pad with context without inventing facts
    return `${title}. ${summary}`.trim();
  }

  /**
   * Estimates reading time in minutes (based on average 200 words per minute reading speed)
   */
  public static calculateReadingTime(text: string): number {
    const wordCount = text.trim().split(/\s+/).filter((w) => w.length > 0).length;
    const minutes = Math.ceil(wordCount / 190); // 190 wpm for mobile reading
    return Math.max(1, minutes);
  }

  /**
   * Automatically extracts searchable keywords for indexing
   */
  public static extractKeywords(title: string, description: string, category: string): string[] {
    const text = `${title} ${description} ${category}`.toLowerCase();
    
    const stopWords = new Set([
      'the', 'a', 'an', 'in', 'on', 'of', 'for', 'to', 'at', 'by', 'with', 'from', 'as', 'is', 'are',
      'was', 'were', 'be', 'been', 'has', 'have', 'had', 'that', 'this', 'these', 'those', 'it', 'its',
      'and', 'or', 'but', 'if', 'not', 'no', 'can', 'will', 'about', 'over', 'after', 'before', 'more',
    ]);

    const cleanTokens = text
      .replace(/[^\w\s]/g, '')
      .split(/\s+/)
      .filter((word) => word.length > 2 && !stopWords.has(word));

    // Calculate frequency
    const freqMap = new Map<string, number>();
    for (const token of cleanTokens) {
      freqMap.set(token, (freqMap.get(token) || 0) + 1);
    }

    // Sort by frequency
    const sorted = Array.from(freqMap.entries())
      .sort((a, b) => b[1] - a[1])
      .map((entry) => entry[0]);

    // Return top 12 unique keywords
    return Array.from(new Set(sorted)).slice(0, 12);
  }
}

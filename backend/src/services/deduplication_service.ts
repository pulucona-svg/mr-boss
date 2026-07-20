import { NormalizedNews } from '../models/news_article.model';
import { StringUtils } from '../utils/string_utils';

export interface DeduplicationResult {
  uniqueArticles: NormalizedNews[];
  duplicatesRemovedCount: number;
}

export class DeduplicationService {
  /**
   * Intelligently groups and deduplicates articles covering the same story,
   * keeping ONLY the highest-scoring version for each unique story cluster.
   */
  public static deduplicate(articles: NormalizedNews[]): DeduplicationResult {
    if (articles.length <= 1) {
      return { uniqueArticles: articles, duplicatesRemovedCount: 0 };
    }

    const clusters: NormalizedNews[][] = [];
    let duplicatesRemovedCount = 0;

    for (const currentArticle of articles) {
      let matchedClusterIndex = -1;

      for (let i = 0; i < clusters.length; i++) {
        const representative = clusters[i][0];
        if (DeduplicationService.areArticlesDuplicate(currentArticle, representative)) {
          matchedClusterIndex = i;
          break;
        }
      }

      if (matchedClusterIndex !== -1) {
        clusters[matchedClusterIndex].push(currentArticle);
        duplicatesRemovedCount++;
      } else {
        clusters.push([currentArticle]);
      }
    }

    // Select the HIGHEST-SCORING article from each story cluster
    const uniqueArticles: NormalizedNews[] = clusters.map((cluster) => {
      if (cluster.length === 1) return cluster[0];

      // Sort by qualityScore descending, tie-breaking by regionScore & freshness
      cluster.sort((a, b) => {
        if (b.qualityScore !== a.qualityScore) {
          return b.qualityScore - a.qualityScore;
        }
        if (b.regionScore !== a.regionScore) {
          return b.regionScore - a.regionScore;
        }
        return b.freshnessScore - a.freshnessScore;
      });

      return cluster[0];
    });

    return {
      uniqueArticles,
      duplicatesRemovedCount,
    };
  }

  /**
   * Evaluates if two articles represent the exact same news story based on:
   * 1. URL exact match
   * 2. Title similarity score >= 0.50 within a 48-hour publication window
   */
  public static areArticlesDuplicate(a: NormalizedNews, b: NormalizedNews): boolean {
    // 1. URL Match
    const normUrlA = StringUtils.normalizeUrl(a.sourceUrl);
    const normUrlB = StringUtils.normalizeUrl(b.sourceUrl);
    if (normUrlA && normUrlB && normUrlA === normUrlB) {
      return true;
    }

    // 2. Publication Time Window Check (max 48 hrs difference)
    const timeA = new Date(a.publishedAt).getTime();
    const timeB = new Date(b.publishedAt).getTime();
    const hoursDiff = Math.abs(timeA - timeB) / (1000 * 60 * 60);

    if (hoursDiff > 48) {
      return false; // Stories published > 48h apart are treated as distinct
    }

    // 3. Title Token & Trigram Similarity Check
    const titleA = StringUtils.normalizeTitle(a.title);
    const titleB = StringUtils.normalizeTitle(b.title);

    if (titleA === titleB) {
      return true; // Exact title match
    }

    const tokenSim = DeduplicationService.calculateTokenSimilarity(titleA, titleB);
    const trigramSim = DeduplicationService.calculateTrigramSimilarity(titleA, titleB);

    const overallSimilarity = Math.max(tokenSim, trigramSim);

    // If similarity is >= 50%, consider it the same story
    return overallSimilarity >= 0.50;
  }

  /**
   * Stemmed Token Jaccard Similarity
   */
  public static calculateTokenSimilarity(text1: string, text2: string): number {
    const stemWord = (w: string) =>
      w
        .toLowerCase()
        .replace(/ing$|ed$|s$|es$|ion$|tion$|ment$/i, '')
        .replace(/technology/i, 'tech')
        .replace(/university|universities/i, 'univ');

    const tokens1 = new Set(
      text1
        .toLowerCase()
        .split(/\s+/)
        .filter((w) => w.length > 2)
        .map(stemWord)
    );

    const tokens2 = new Set(
      text2
        .toLowerCase()
        .split(/\s+/)
        .filter((w) => w.length > 2)
        .map(stemWord)
    );

    if (tokens1.size === 0 || tokens2.size === 0) return 0;

    let intersectionCount = 0;
    for (const token of tokens1) {
      if (tokens2.has(token)) {
        intersectionCount++;
      }
    }

    const unionSize = new Set([...tokens1, ...tokens2]).size;
    return unionSize === 0 ? 0 : intersectionCount / unionSize;
  }

  /**
   * Character Trigram Similarity
   */
  public static calculateTrigramSimilarity(text1: string, text2: string): number {
    const getTrigrams = (str: string) => {
      const clean = str.replace(/\s+/g, ' ').trim().toLowerCase();
      const trigrams = new Set<string>();
      for (let i = 0; i <= clean.length - 3; i++) {
        trigrams.add(clean.substring(i, i + 3));
      }
      return trigrams;
    };

    const tri1 = getTrigrams(text1);
    const tri2 = getTrigrams(text2);

    if (tri1.size === 0 || tri2.size === 0) return 0;

    let intersectionCount = 0;
    for (const tri of tri1) {
      if (tri2.has(tri)) {
        intersectionCount++;
      }
    }

    const unionSize = new Set([...tri1, ...tri2]).size;
    return unionSize === 0 ? 0 : intersectionCount / unionSize;
  }
}

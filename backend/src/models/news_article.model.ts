/**
 * Predefined News Categories matching the Mirror Laikipia Flutter App
 */
export type AppCategory =
  | 'Breaking'
  | 'Politics'
  | 'Business'
  | 'Technology'
  | 'Education'
  | 'Health'
  | 'Sports'
  | 'Entertainment'
  | 'Science'
  | 'World'
  | 'Africa'
  | 'Kenya';

export const APP_CATEGORIES: AppCategory[] = [
  'Breaking',
  'Politics',
  'Business',
  'Technology',
  'Education',
  'Health',
  'Sports',
  'Entertainment',
  'Science',
  'World',
  'Africa',
  'Kenya',
];

/**
 * Regional Priority Hierarchy
 */
export type RegionPriority = 'Kenya' | 'East Africa' | 'Africa' | 'World';

export interface ScoreBreakdown {
  titleQualityScore: number;
  imageQualityScore: number;
  descriptionDepthScore: number;
  publisherTrustScore: number;
  freshnessScore: number;
  totalScore: number;
}

/**
 * Final Normalized Pipeline Output: NormalizedNews
 * Contains all metadata required for Firebase ingestion and ImageKit processing in Phase 2.
 */
export interface NormalizedNews {
  id: string;
  title: string;
  summary: string;
  content: string;
  imageUrl: string;
  sourceUrl: string;
  publishedAt: string;
  sourceName: string;
  author: string | null;
  category: AppCategory; // Primary Category
  secondaryCategories: AppCategory[]; // Secondary Categories
  regionPriority: RegionPriority;
  regionScore: number; // 4 = Kenya, 3 = East Africa, 2 = Africa, 1 = World
  slug: string;
  createdAt: string;
  updatedAt: string;
  expiresAt: string;
  collectedAt: string;
  qualityScore: number;
  freshnessScore: number;
  scoreBreakdown?: ScoreBreakdown;
  status: 'published' | 'draft';
  priority: number;

  // Phase 2 readiness fields (ImageKit & Firebase Storage / Viewer)
  viewerDocumentId?: string;
  viewerUrl?: string;
  coverImage?: string;
}

/**
 * Alias for backward compatibility
 */
export type NormalizedArticle = NormalizedNews;

/**
 * Raw Article from NewsAPI.org
 */
export interface NewsApiArticle {
  source: {
    id: string | null;
    name: string;
  };
  author: string | null;
  title: string;
  description: string | null;
  url: string;
  urlToImage: string | null;
  publishedAt: string;
  content: string | null;
}

export interface NewsApiResponse {
  status: string;
  totalResults: number;
  articles: NewsApiArticle[];
}

/**
 * Raw Article from NewsData.io
 */
export interface NewsDataArticle {
  article_id: string;
  title: string;
  link: string;
  keywords?: string[] | null;
  creator?: string[] | null;
  video_url?: string | null;
  description?: string | null;
  content?: string | null;
  pubDate: string;
  image_url?: string | null;
  source_id?: string;
  source_priority?: number;
  category?: string[] | null;
  country?: string[] | null;
  language?: string;
}

export interface NewsDataResponse {
  status: string;
  totalResults: number;
  results: NewsDataArticle[];
}

/**
 * News Collection Result containing statistics and articles list
 */
export interface CollectionStats {
  receivedFromNewsApi: number;
  receivedFromNewsData: number;
  totalFetched: number;
  filteredIncomplete: number;
  filteredLowQuality: number;
  duplicatesRemoved: number;
  finalCount: number;
  categoryBreakdown: Record<AppCategory, number>;
  regionBreakdown: Record<RegionPriority, number>;
}

export interface CollectionResult {
  stats: CollectionStats;
  articles: NormalizedNews[];
}

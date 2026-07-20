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
 * Common Unified News Article Interface for Mirror Laikipia
 */
export interface NormalizedArticle {
  id: string;
  title: string;
  summary: string;
  content: string;
  imageUrl: string;
  sourceUrl: string;
  publishedAt: string;
  sourceName: string;
  author: string | null;
  category: AppCategory;
  slug: string;
  createdAt: string;
  updatedAt: string;
  status: 'published' | 'draft';
  priority: number;

  // Phase 2 readiness fields (ImageKit & Firebase Storage / Viewer)
  viewerDocumentId?: string;
  viewerUrl?: string;
  coverImage?: string;
}

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
  duplicatesRemoved: number;
  finalCount: number;
  categoryBreakdown: Record<AppCategory, number>;
}

export interface CollectionResult {
  stats: CollectionStats;
  articles: NormalizedArticle[];
}

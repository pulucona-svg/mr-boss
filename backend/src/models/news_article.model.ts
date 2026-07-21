/**
 * Predefined News Categories matching the Mirror Laikipia Flutter App
 */
export type AppCategory =
  | 'Breaking'
  | 'Kenya'
  | 'Africa'
  | 'World'
  | 'Politics'
  | 'Business'
  | 'Technology'
  | 'Science'
  | 'Education'
  | 'Health'
  | 'Nature'
  | 'Culture'
  | 'Entertainment'
  | 'Sports';

export const APP_CATEGORIES: AppCategory[] = [
  'Breaking',
  'Kenya',
  'Africa',
  'World',
  'Politics',
  'Business',
  'Technology',
  'Science',
  'Education',
  'Health',
  'Nature',
  'Culture',
  'Entertainment',
  'Sports',
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

  // News Ranking & Editorial Engine fields
  importanceScore: number; // 0 to 100
  isTopStory: boolean;
  topStoryRank?: number; // 1 to 5
  isTrending: boolean;
  trendingRank?: number; // 1 to 10
  editorialSummary: string; // 80 - 120 words refined factual summary
  readingTime: number; // Estimated reading time in minutes
  keywords: string[]; // Searchable index keywords
  clusterId?: string; // Story cluster ID

  // Phase 2 & AI Enrichment fields
  viewerDocumentId?: string;
  viewerUrl?: string;
  coverImage?: string;
  imageUrls?: string[];

  // Optional Gemini AI Enrichment fields
  headline?: string;
  article?: string;
  background?: string;
  analysis?: string;
  whyItMatters?: string;
  whatNext?: string;
  aiGenerated?: boolean;
}

/**
 * Alias for backward compatibility
 */
export type NormalizedArticle = NormalizedNews;

/**
 * Grouped Story Cluster representing multiple publishers covering the same event
 */
export interface StoryCluster {
  clusterId: string;
  topicTitle: string;
  clusterSize: number;
  mainArticle: NormalizedNews;
  relatedArticles: NormalizedNews[];
  createdAt: string;
}

/**
 * Trending Topic Package for Explore Screen feed
 */
export interface TrendingPackageTopic {
  id: string;
  title: string;
  clusterSize: number;
  iconName: string;
  gradientColors: string[];
  imageUrls: string[];
  description: string;
  details: Record<string, string>;
  source: string;
  timeAgo: string;
  importanceScore: number;
}

/**
 * Final Package Output containing top stories, trending, category news, and story clusters
 */
export interface NewsPackage {
  generatedAt: string;
  stats: CollectionStats;
  topStories: NormalizedNews[]; // Top 5
  trendingTopics: TrendingPackageTopic[]; // Top 10
  latestNews: NormalizedNews[];
  categoryNews: Record<AppCategory, NormalizedNews[]>;
  storyClusters: StoryCluster[];
  totalCleanArticles: number;
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
  filteredLowQuality: number;
  duplicatesRemoved: number;
  finalCount: number;
  topStoriesCount: number;
  trendingCount: number;
  clustersCount: number;
  categoryBreakdown: Record<AppCategory, number>;
  regionBreakdown: Record<RegionPriority, number>;
}

export interface CollectionResult {
  stats: CollectionStats;
  package: NewsPackage;
  articles: NormalizedNews[];
}

import { Timestamp } from "firebase-admin/firestore";

export interface ExploreConfig {
  workerCount: number;
  articlesPerCategory: number;
  refreshMinutes: number;
  maxRetries: number;
  searchModel: string;
  openAiApiKey?: string;
}

export interface ExploreCategory {
  id: string;
  name: string;
  enabled: boolean;
  displayOrder: number;
  icon?: string;
  color?: string;
  description?: string;
  targetArticles?: number;
  lastFetched?: Timestamp | null;
  publishedToday?: number;
}

export interface SchedulerState {
  currentCategory: string | null;
  currentQueue: number;
  isSearching: boolean;
  isPublishing: boolean;
  categoriesCompleted: number;
  totalQueued: number;
  totalPublished: number;
  totalFailed: number;
  lastRun: Timestamp | null;
  nextRun: Timestamp | null;
  lockTimestamp?: Timestamp | null;
}

export interface DiscoveredArticle {
  clusterId: string;
  title: string;
  source: string;
  sourceUrl: string;
  publishedAt: string;
  summary: string;
  category?: string;
}

export interface JobQueueItem {
  clusterId: string;
  title: string;
  summary: string;
  category: string;
  source: string;
  sourceUrl: string;
  publishedAt: string;
  status: "queued" | "processing" | "completed" | "failed";
  assignedWorker: string | null;
  retries: number;
  createdAt: any; // FieldValue or Timestamp
  articleHash: string;
}

export interface StoryClusterItem {
  clusterId: string;
  title: string;
  summary: string;
  category: string;
  source: string;
  sourceUrl: string;
  publishedAt: string;
  createdAt: any;
  articleHash: string;
  status: "discovered" | "processing" | "published" | "failed";
}

export interface ArticleImageData {
  position: number;
  caption: string;
  imageUrl: string;
  sourceUrl?: string;
  sourceDomain?: string;
}

export interface ExploreNewsItem {
  id?: string;
  clusterId: string;
  title: string;
  content: string;
  summary: string;
  category: string;
  source: string;
  sourceUrl: string;
  publishedAt: string;
  createdAt: any;
  images: ArticleImageData[];
  imageCount: number;
  imageSearchCompleted: boolean;
  imageSearchAttempts: number;
  imageSources: string[];
}


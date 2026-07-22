/**
 * Structured Article Viewer Content Block Types
 */
export type ViewerBlockType = 'paragraph' | 'image' | 'heading' | 'quote' | 'divider';

export interface ViewerContentBlock {
  type: ViewerBlockType;
  text?: string;
  url?: string;
  caption?: string;
  level?: number; // 1 = main section heading, 2 = sub-heading
}

export interface ViewerSection {
  heading: string;
  paragraphs: string[];
}

export interface RelatedArticleSummary {
  id: string;
  title: string;
  source: string;
  category: string;
  imageUrl: string;
}

export interface ViewerImageItem {
  url: string;
  caption?: string;
}

/**
 * Complete Article Viewer JSON Document Model
 * Stored on ImageKit under /mirror_laikipia/news/viewers/viewer_{id}.json.
 * Opened when user taps "Read Article..." in the Flutter app.
 */
export interface ArticleViewerDocument {
  articleId: string;
  title: string;
  subtitle: string;
  subtitles: string[];
  category: string;
  secondaryCategories: string[];
  source: string;
  author: string | null;
  publishedAt: string;
  readingTime: number; // in minutes
  editorialSummary: string;
  fullStory: string;
  paragraphs: string[];
  content: ViewerContentBlock[];
  images: ViewerImageItem[];
  sections: ViewerSection[];
  relatedArticles: RelatedArticleSummary[];
  keywords: string[];
  isTopStory: boolean;
  isTrending: boolean;
  qualityScore: number;
  importanceScore: number;
  expiresAt: string;
  originalSourceUrl: string;
  generatedAt: string;
}

/**
 * Alias for MagazineViewerDocument
 */
export type MagazineViewerDocument = ArticleViewerDocument;

/**
 * ImageKit Upload Result Metadata
 */
export interface ImageKitUploadResult {
  fileId: string;
  url: string;
  size: number;
  width?: number;
  height?: number;
  mimeType?: string;
}

/**
 * Lightweight Metadata Document stored in Firestore collections.
 * Firestore NEVER stores the full article body.
 */
export interface FirestoreNewsDocument {
  id: string;
  title: string;
  category: string;
  secondaryCategories: string[];
  summary: string;
  editorialSummary: string;
  thumbnailUrl: string; // ImageKit URL for thumbnail/cover
  imageKitFileId: string;
  viewerDocumentUrl: string; // ImageKit URL for viewer JSON
  viewerDocumentId: string;
  source: string;
  publishedAt: string;
  expiresAt: string;
  collectedAt: string;
  importanceScore: number;
  qualityScore: number;
  freshnessScore: number;
  readingTime: number;
  keywords: string[];
  regionPriority: string;
  regionScore: number;
  clusterId?: string;
  isTopStory: boolean;
  topStoryRank?: number;
  isTrending: boolean;
  trendingRank?: number;
  originalSourceUrl: string;
  status: 'published' | 'draft';
  priority: number;
  imageUrls?: string[];
  headline?: string;
  article?: string;
  background?: string;
  analysis?: string;
  whyItMatters?: string;
  whatNext?: string;
  aiGenerated?: boolean;
  groundedSources?: string[];
  images?: Array<{
    url: string;
    width?: number;
    height?: number;
    caption?: string;
    credit?: string;
    source?: string;
  }>;
  imageCredits?: string[];
  imageSearchStatus?: 'completed' | 'partial' | 'failed';
  enrichmentVersion?: string;
}

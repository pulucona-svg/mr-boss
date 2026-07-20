import { ImageKitService } from './imagekit_service';
import { MagazineGeneratorService } from './magazine_generator_service';
import { FirestoreService } from './firestore_service';
import { NormalizedNews, StoryCluster } from '../models/news_article.model';
import { FirestoreNewsDocument, ImageKitUploadResult } from '../models/magazine_viewer.model';
import { Logger } from '../utils/logger';

export interface PublishingResult {
  success: boolean;
  articleId: string;
  imageKitUrl?: string;
  viewerDocumentUrl?: string;
  error?: string;
}

export class TransactionPublishingService {
  /**
   * Transactionally publishes a single NormalizedNews article.
   * Handles downloading/uploading image to ImageKit, generating & uploading viewer JSON,
   * writing metadata to Firestore, and performing complete rollbacks if any step fails.
   */
  public static async publishArticleTransactionally(
    article: NormalizedNews,
    cluster?: StoryCluster
  ): Promise<PublishingResult> {
    Logger.info(`[TRANSACTION] Starting transactional publish for article ID: ${article.id}`);

    let uploadedImageResult: ImageKitUploadResult | null = null;
    let uploadedViewerResult: ImageKitUploadResult | null = null;
    let firestorePublished = false;

    try {
      // 1. Upload Cover Image to ImageKit
      uploadedImageResult = await ImageKitService.uploadArticleImage(
        article.imageUrl,
        article.id
      );

      if (!uploadedImageResult) {
        throw new Error('ImageKit image upload failed or image was broken');
      }

      // Update article cover image URL
      const finalCoverImageUrl = uploadedImageResult.url;
      article.coverImage = finalCoverImageUrl;

      // 2. Generate Magazine Viewer JSON Document & Upload to ImageKit
      const viewerDoc = MagazineGeneratorService.generateViewerDocument(
        article,
        finalCoverImageUrl,
        cluster
      );

      uploadedViewerResult = await ImageKitService.uploadViewerDocument(viewerDoc);

      if (!uploadedViewerResult) {
        throw new Error('ImageKit magazine viewer JSON upload failed');
      }

      // Update viewer document fields
      article.viewerDocumentId = uploadedViewerResult.fileId;
      article.viewerUrl = uploadedViewerResult.url;

      // 3. Prepare Metadata Document for Firestore
      const firestoreDoc: FirestoreNewsDocument = {
        id: article.id,
        title: article.title,
        category: article.category,
        secondaryCategories: article.secondaryCategories || [],
        summary: article.summary,
        editorialSummary: article.editorialSummary || article.summary,
        thumbnailUrl: finalCoverImageUrl,
        imageKitFileId: uploadedImageResult.fileId,
        viewerDocumentUrl: uploadedViewerResult.url,
        viewerDocumentId: uploadedViewerResult.fileId,
        importanceScore: article.importanceScore || 0,
        qualityScore: article.qualityScore || 0,
        freshnessScore: article.freshnessScore || 0,
        publishedAt: article.publishedAt,
        expiresAt: article.expiresAt,
        collectedAt: article.collectedAt,
        readingTime: article.readingTime || 2,
        keywords: article.keywords || [],
        regionPriority: article.regionPriority,
        regionScore: article.regionScore,
        source: article.sourceName,
        originalSourceUrl: article.sourceUrl,
        clusterId: article.clusterId,
        isTopStory: article.isTopStory || false,
        topStoryRank: article.topStoryRank,
        isTrending: article.isTrending || false,
        trendingRank: article.trendingRank,
        status: article.status || 'published',
        priority: article.priority || article.regionScore,
      };

      // 4. Write Metadata to Firestore Collections
      firestorePublished = await FirestoreService.publishArticleMetadata(firestoreDoc);

      if (!firestorePublished) {
        throw new Error('Firestore document write transaction failed');
      }

      Logger.info(
        `[TRANSACTION] Success! Published article ${article.id} to ImageKit & Firestore.`
      );

      return {
        success: true,
        articleId: article.id,
        imageKitUrl: finalCoverImageUrl,
        viewerDocumentUrl: uploadedViewerResult.url,
      };
    } catch (error: any) {
      Logger.error(
        `[TRANSACTION_FAIL] Publishing failed for ${article.id}: ${error.message || error}. Initiating Rollback...`
      );

      // ROLLBACK STEP: Delete any uploaded ImageKit files & Firestore docs to avoid orphans
      await TransactionPublishingService.rollback(
        article.id,
        article.category,
        uploadedImageResult?.fileId,
        uploadedViewerResult?.fileId,
        firestorePublished
      );

      return {
        success: false,
        articleId: article.id,
        error: error.message || String(error),
      };
    }
  }

  /**
   * Safely rolls back ImageKit uploads and Firestore documents on failure.
   */
  private static async rollback(
    articleId: string,
    category: string,
    imageFileId?: string,
    viewerFileId?: string,
    wasFirestorePublished: boolean = false
  ): Promise<void> {
    Logger.logHeader(`[ROLLBACK] Rolling back transaction for ${articleId}`);

    if (imageFileId) {
      Logger.info(`[ROLLBACK] Deleting ImageKit image: ${imageFileId}`);
      await ImageKitService.deleteFile(imageFileId);
    }

    if (viewerFileId) {
      Logger.info(`[ROLLBACK] Deleting ImageKit viewer document: ${viewerFileId}`);
      await ImageKitService.deleteFile(viewerFileId);
    }

    if (wasFirestorePublished) {
      Logger.info(`[ROLLBACK] Deleting Firestore documents for: ${articleId}`);
      await FirestoreService.deleteArticleDocument(articleId, category);
    }

    Logger.info(`[ROLLBACK] Rollback complete for ${articleId}. Zero orphan files remain.`);
  }
}

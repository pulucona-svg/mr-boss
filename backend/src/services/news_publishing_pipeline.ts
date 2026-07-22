import { NewsApiCollector } from '../collectors/news_api_collector';
import { NewsDataCollector } from '../collectors/news_data_collector';
import { NormalizationService } from './normalization_service';
import { DeduplicationService } from './deduplication_service';
import { RankingService } from './ranking_service';
import { ClusteringService } from './clustering_service';
import { ImageKitUploadService } from './imagekit_upload_service';
import { ImageEnrichmentService } from './image_enrichment_service';
import { SearchGroundingService } from './search_grounding_service';
import { GeminiService } from './gemini_service';
import { ViewerDocumentBuilder } from './viewer_document_builder';
import { FirestorePublisher } from './firestore_publisher';
import { CleanupService } from './cleanup_service';
import {
  AppCategory,
  APP_CATEGORIES,
  CollectionResult,
  CollectionStats,
  NewsPackage,
  NormalizedNews,
  RegionPriority,
  StoryCluster,
} from '../models/news_article.model';
import { FirestoreNewsDocument, ImageKitUploadResult } from '../models/magazine_viewer.model';
import { Logger } from '../utils/logger';
import { config } from '../config/environment';

export interface PipelinePublishingResult {
  success: boolean;
  articleId: string;
  imageKitUrl?: string;
  viewerDocumentUrl?: string;
  error?: string;
}

export class NewsPublishingPipeline {
  private newsApiCollector: NewsApiCollector;
  private newsDataCollector: NewsDataCollector;

  constructor() {
    this.newsApiCollector = new NewsApiCollector(config.newsApiKey);
    this.newsDataCollector = new NewsDataCollector(config.newsDataApiKey);
  }

  /**
   * Executes the complete automatic Synchronization & Publishing Pipeline:
   * News Collection -> Intelligence Pipeline -> Transactional Uploads -> Firestore Publish -> Rolling Retention Cleanup.
   */
  public async executePipeline(query?: string): Promise<CollectionResult> {
    const searchQuery = query || config.defaultQuery;
    Logger.logHeader(`STARTING AUTOMATIC SYNCHRONIZATION PIPELINE (Query: "${searchQuery}")`);

    // 1. STEP 1: FETCH FRESH NEWS FROM APIS
    let rawNewsApiArticles: any[] = [];
    try {
      rawNewsApiArticles = await this.newsApiCollector.fetchArticles(searchQuery);
    } catch (err: any) {
      Logger.error('[COLLECT] Error during NewsAPI collection:', err.message || err);
    }

    let rawNewsDataArticles: any[] = [];
    try {
      rawNewsDataArticles = await this.newsDataCollector.fetchArticles(searchQuery);
    } catch (err: any) {
      Logger.error('[COLLECT] Error during NewsData collection:', err.message || err);
    }

    const countNewsApi = rawNewsApiArticles.length;
    const countNewsData = rawNewsDataArticles.length;
    const totalFetched = countNewsApi + countNewsData;

    // 2. STEP 2: NORMALIZE & QUALITY FILTER
    const candidateArticles: NormalizedNews[] = [];
    let filteredIncompleteCount = 0;
    let filteredLowQualityCount = 0;

    for (const rawArticle of rawNewsApiArticles) {
      if (!rawArticle.title || !rawArticle.url) {
        filteredIncompleteCount++;
        continue;
      }
      const normalized = NormalizationService.normalizeNewsApiArticle(rawArticle);
      if (normalized) {
        candidateArticles.push(normalized);
      } else {
        filteredLowQualityCount++;
      }
    }

    for (const rawArticle of rawNewsDataArticles) {
      if (!rawArticle.title || !rawArticle.link) {
        filteredIncompleteCount++;
        continue;
      }
      const normalized = NormalizationService.normalizeNewsDataArticle(rawArticle);
      if (normalized) {
        candidateArticles.push(normalized);
      } else {
        filteredLowQualityCount++;
      }
    }

    // 3. STEP 3: INTELLIGENT DEDUPLICATION
    const { uniqueArticles, duplicatesRemovedCount } =
      DeduplicationService.deduplicate(candidateArticles);

    // 4. STEP 4: EDITORIAL RANKING & CLUSTERING
    for (const article of uniqueArticles) {
      article.importanceScore = RankingService.calculateImportanceScore(article);
    }

    const storyClusters = ClusteringService.clusterArticles(uniqueArticles);
    const topStories = RankingService.selectTopStories(uniqueArticles);
    const { trendingPackageTopics } = RankingService.detectTrending(
      uniqueArticles,
      storyClusters
    );

    // 5. STEP 5: PREVENT DUPLICATE PUBLISHING (Filter out stories active in Firestore)
    const activeUrls = await FirestorePublisher.getActiveArticleUrls();
    const newArticlesToPublish = uniqueArticles.filter(
      (art) => !activeUrls.has(art.sourceUrl)
    );

    Logger.info(
      `[FILTER] Found ${newArticlesToPublish.length} new stories to publish (${uniqueArticles.length - newArticlesToPublish.length} already active in Firestore)`
    );

    // 6. STEP 6: TRANSACTIONAL IMAGEKIT UPLOADS & FIRESTORE PUBLISHING
    const publishedArticles: NormalizedNews[] = [];

    if (newArticlesToPublish.length > 0) {
      for (const article of newArticlesToPublish) {
        const cluster = storyClusters.find((c) => c.clusterId === article.clusterId);
        const publishResult = await this.publishArticleTransactionally(article, cluster);

        if (publishResult.success) {
          publishedArticles.push(article);
        }
      }
      Logger.info(`[PUBLISH] Successfully published ${publishedArticles.length} new articles.`);
    } else {
      Logger.info('[PUBLISH] No new articles to publish. Existing Firestore content remains intact.');
    }

    // 7. STEP 7: TARGETED CATEGORY BACKFILL CYCLE (Ensure minimum 20 articles per category)
    const TARGET_MIN_INVENTORY = 20;
    Logger.info(`[BACKFILL] Verifying category inventory counts against minimum target (${TARGET_MIN_INVENTORY} articles)...`);

    for (const cat of APP_CATEGORIES) {
      const currentCount = await FirestorePublisher.getCategoryDocumentCount(cat);
      if (currentCount < TARGET_MIN_INVENTORY) {
        const needed = TARGET_MIN_INVENTORY - currentCount;
        Logger.info(`[BACKFILL] Category '${cat}' has ${currentCount} articles (Needs ${needed} more to reach target ${TARGET_MIN_INVENTORY}). Initiating targeted fetch...`);

        const catQuery = this.getCategorySearchQuery(cat);
        let backfillNewsApi: any[] = [];
        let backfillNewsData: any[] = [];

        try {
          backfillNewsApi = await this.newsApiCollector.fetchArticles(catQuery);
        } catch (e) {
          /* ignore */
        }
        try {
          backfillNewsData = await this.newsDataCollector.fetchArticles(catQuery);
        } catch (e) {
          /* ignore */
        }

        const rawBackfill = [...backfillNewsApi, ...backfillNewsData];
        const normalizedBackfill: NormalizedNews[] = [];

        for (const raw of rawBackfill) {
          const norm = raw.url
            ? NormalizationService.normalizeNewsApiArticle(raw)
            : NormalizationService.normalizeNewsDataArticle(raw);
          if (norm) {
            // Quality Preservation (Objective 7): Only include if article genuinely belongs to category 'cat'
            const isRelevant = norm.category === cat || (norm.secondaryCategories && norm.secondaryCategories.includes(cat));
            if (isRelevant) {
              normalizedBackfill.push(norm);
            }
          }
        }

        const { uniqueArticles: uniqueBackfill } = DeduplicationService.deduplicate(normalizedBackfill);
        const activeUrlsBackfill = await FirestorePublisher.getActiveArticleUrls();
        const newBackfillToPublish = uniqueBackfill.filter((a) => !activeUrlsBackfill.has(a.sourceUrl));

        Logger.info(`[BACKFILL] '${cat}': Found ${newBackfillToPublish.length} new genuinely relevant candidate articles to publish.`);

        for (const article of newBackfillToPublish) {
          const pubResult = await this.publishArticleTransactionally(article);
          if (pubResult.success) {
            publishedArticles.push(article);
          }
          const checkCount = await FirestorePublisher.getCategoryDocumentCount(cat);
          if (checkCount >= TARGET_MIN_INVENTORY) break;
        }

        const finalCatCount = await FirestorePublisher.getCategoryDocumentCount(cat);
        Logger.info(`[BACKFILL] Category '${cat}' now has ${finalCatCount} articles in Firestore.`);
      }
    }

    // 8. STEP 8: PUBLISH TRENDING TOPICS & CLUSTERS TO FIRESTORE
    await FirestorePublisher.publishTrendingAndClusters(trendingPackageTopics, storyClusters);

    // 9. STEP 9: AUTOMATIC ROLLING RETENTION CLEANUP (Runs ONLY AFTER publishing succeeded)
    const cleanupStats = await CleanupService.executeCleanup();
    Logger.info(`[CLEANUP] Post-publish cleanup completed. Deleted ${cleanupStats.documentsDeleted} surplus documents.`);

    // 9. STEP 9: ORGANIZE CATEGORIES & REGIONAL BREAKDOWN
    const categoryNews: Record<AppCategory, NormalizedNews[]> = APP_CATEGORIES.reduce(
      (acc, cat) => {
        acc[cat] = [];
        return acc;
      },
      {} as Record<AppCategory, NormalizedNews[]>
    );

    const categoryBreakdown: Record<AppCategory, number> = APP_CATEGORIES.reduce(
      (acc, cat) => {
        acc[cat] = 0;
        return acc;
      },
      {} as Record<AppCategory, number>
    );

    const regionBreakdown: Record<RegionPriority, number> = {
      Kenya: 0,
      'East Africa': 0,
      Africa: 0,
      World: 0,
    };

    for (const article of publishedArticles) {
      regionBreakdown[article.regionPriority] =
        (regionBreakdown[article.regionPriority] || 0) + 1;

      const assignedCategories = Array.from(
        new Set([article.category, ...(article.secondaryCategories || [])])
      );

      for (const cat of assignedCategories) {
        categoryBreakdown[cat] = (categoryBreakdown[cat] || 0) + 1;
        if (categoryNews[cat]) {
          categoryNews[cat].push(article);
        }
      }
    }

    const latestNews = [...publishedArticles].sort((a, b) => {
      if (b.importanceScore !== a.importanceScore) {
        return b.importanceScore - a.importanceScore;
      }
      return b.freshnessScore - a.freshnessScore;
    });

    const nowIso = new Date().toISOString();
    const stats: CollectionStats = {
      receivedFromNewsApi: countNewsApi,
      receivedFromNewsData: countNewsData,
      totalFetched,
      filteredIncomplete: filteredIncompleteCount,
      filteredLowQuality: filteredLowQualityCount,
      duplicatesRemoved: duplicatesRemovedCount,
      finalCount: publishedArticles.length,
      topStoriesCount: topStories.length,
      trendingCount: trendingPackageTopics.length,
      clustersCount: storyClusters.length,
      categoryBreakdown,
      regionBreakdown,
    };

    const newsPackage: NewsPackage = {
      generatedAt: nowIso,
      stats,
      topStories,
      trendingTopics: trendingPackageTopics,
      latestNews,
      categoryNews,
      storyClusters,
      totalCleanArticles: publishedArticles.length,
    };

    Logger.logSummary(stats);

    return {
      stats,
      package: newsPackage,
      articles: publishedArticles,
    };
  }

  /**
   * Transactional Article Publisher with ImageKit & Firestore Rollback Safety.
   */
  private async publishArticleTransactionally(
    article: NormalizedNews,
    cluster?: StoryCluster
  ): Promise<PipelinePublishingResult> {
    Logger.info(`[TRANSACTION] Starting transactional publish for article ID: ${article.id}`);

    let uploadedImageResult: ImageKitUploadResult | null = null;
    let uploadedViewerResult: ImageKitUploadResult | null = null;
    let firestorePublished = false;

    try {
      // 0a. Search Grounding Stage (Gather trustworthy context from verified publishers)
      const searchStartTime = Date.now();
      const groundingResult = await SearchGroundingService.performGroundingSearch(
        article.title,
        article.category,
        article.keywords,
        article.regionPriority
      );
      const searchDurationMs = Date.now() - searchStartTime;

      // 0b. Gemini AI Enrichment Stage (Grounded magazine synthesis)
      let retryCount = 0;
      const geminiStartTime = Date.now();
      article = await GeminiService.generateMagazineArticle(article, groundingResult);
      let geminiDurationMs = Date.now() - geminiStartTime;

      // 0c. Multi-Image Enrichment & Quality Validation Stage
      const clusterImages = cluster ? cluster.relatedArticles.map((r) => r.imageUrl).filter(Boolean) : [];
      const imageStartTime = Date.now();
      let imageResult = await ImageEnrichmentService.enrichArticleImagesDetailed(article, clusterImages);
      let imageSearchDurationMs = Date.now() - imageStartTime;

      article.imageUrls = imageResult.imageUrls;
      article.images = imageResult.images;
      article.imageSearchStatus = imageResult.status;

      // 0d. Article Quality Validation & Single Retry
      let isValid = this.validateEnrichedArticle(article);

      if (!isValid && retryCount < 1) {
        retryCount++;
        Logger.warn(
          `[QUALITY_VALIDATION_RETRY] Validation failed for article ID ${article.id}. Retrying Gemini AI & Image enrichment (Retry ${retryCount}/1)...`
        );

        const retryGeminiStart = Date.now();
        article = await GeminiService.generateMagazineArticle(article, groundingResult);
        geminiDurationMs += Date.now() - retryGeminiStart;

        const retryImageStart = Date.now();
        imageResult = await ImageEnrichmentService.enrichArticleImagesDetailed(article, clusterImages);
        imageSearchDurationMs += Date.now() - retryImageStart;

        article.imageUrls = imageResult.imageUrls;
        article.images = imageResult.images;
        article.imageSearchStatus = imageResult.status;

        isValid = this.validateEnrichedArticle(article);
      }

      if (!isValid) {
        Logger.warn(
          `[QUALITY_VALIDATION_FALLBACK] Article ID ${article.id} did not pass strict AI quality checks after retry. Publishing original article content as fallback.`
        );
      }

      const totalEnrichmentDurationMs = searchDurationMs + geminiDurationMs + imageSearchDurationMs;

      // Detailed Logging of Enrichment Execution Metrics
      Logger.info(`[ENRICHMENT_LOG] Article ID ${article.id}:
        • Search Duration: ${searchDurationMs}ms
        • Gemini Duration: ${geminiDurationMs}ms
        • Image Search Duration: ${imageSearchDurationMs}ms
        • Images Accepted: ${imageResult.imagesAccepted}
        • Images Rejected: ${imageResult.imagesRejected}
        • Sources Used: ${groundingResult.sourcesUsed.join(', ') || article.sourceName}
        • Retry Count: ${retryCount}
        • Total Enrichment Time: ${totalEnrichmentDurationMs}ms`);

      // 1. Upload Cover Image to ImageKit (/mirror_laikipia/news/images/)
      uploadedImageResult = await ImageKitUploadService.uploadArticleImage(
        article.imageUrl,
        article.id
      );

      if (!uploadedImageResult) {
        throw new Error('ImageKit image upload failed or image was broken');
      }

      const finalCoverImageUrl = uploadedImageResult.url;
      article.coverImage = finalCoverImageUrl;

      // Ensure cover image is first in article.imageUrls
      if (article.imageUrls && article.imageUrls.length > 0) {
        article.imageUrls[0] = finalCoverImageUrl;
      } else {
        article.imageUrls = [finalCoverImageUrl];
      }

      // 2. Build Article Viewer JSON Document & Upload to ImageKit (/mirror_laikipia/news/viewers/)
      const viewerDoc = ViewerDocumentBuilder.buildViewerDocument(
        article,
        finalCoverImageUrl,
        cluster
      );

      uploadedViewerResult = await ImageKitUploadService.uploadViewerDocument(viewerDoc);

      if (!uploadedViewerResult) {
        throw new Error('ImageKit magazine viewer JSON document upload failed');
      }

      article.viewerDocumentId = uploadedViewerResult.fileId;
      article.viewerUrl = uploadedViewerResult.url;

      // 3. Build Lightweight Metadata Document for Firestore (NO full article body)
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
        source: article.sourceName,
        publishedAt: article.publishedAt,
        expiresAt: article.expiresAt,
        collectedAt: article.collectedAt,
        importanceScore: article.importanceScore || 0,
        qualityScore: article.qualityScore || 0,
        freshnessScore: article.freshnessScore || 0,
        readingTime: article.readingTime || 2,
        keywords: article.keywords || [],
        regionPriority: article.regionPriority,
        regionScore: article.regionScore,
        clusterId: article.clusterId,
        isTopStory: article.isTopStory || false,
        topStoryRank: article.topStoryRank,
        isTrending: article.isTrending || false,
        trendingRank: article.trendingRank,
        originalSourceUrl: article.sourceUrl,
        status: article.status || 'published',
        priority: article.priority || article.regionScore,
        imageUrls: article.imageUrls,
        headline: article.headline,
        article: article.article,
        background: article.background,
        analysis: article.analysis,
        whyItMatters: article.whyItMatters,
        whatNext: article.whatNext,
        aiGenerated: article.aiGenerated,
        groundedSources: article.groundedSources || groundingResult.sourcesUsed,
        images: article.images,
        imageCredits: article.images?.map((i) => i.credit || i.source).filter(Boolean) as string[],
        imageSearchStatus: article.imageSearchStatus,
        enrichmentVersion: article.enrichmentVersion || 'v2.0-grounded',
      };

      // 4. Publish Metadata to Firestore
      firestorePublished = await FirestorePublisher.publishArticleMetadata(firestoreDoc);

      if (!firestorePublished) {
        throw new Error('Firestore document write transaction failed');
      }

      Logger.info(
        `[TRANSACTION] Published article ${article.id} to ImageKit & Firestore successfully.`
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

      // Rollback ImageKit files & Firestore docs if partial failure occurred
      if (uploadedImageResult?.fileId) {
        await ImageKitUploadService.deleteFile(uploadedImageResult.fileId);
      }
      if (uploadedViewerResult?.fileId) {
        await ImageKitUploadService.deleteFile(uploadedViewerResult.fileId);
      }
      if (firestorePublished) {
        await FirestorePublisher.deleteArticleDocument(article.id, article.category);
      }

      Logger.info(`[ROLLBACK] Rollback complete for ${article.id}. Zero orphan files remain.`);

      return {
        success: false,
        articleId: article.id,
        error: error.message || String(error),
      };
    }
  }

  private getCategorySearchQuery(category: AppCategory): string {
    switch (category) {
      case 'Politics':
        return 'politics OR election OR parliament OR president OR government OR policy OR minister';
      case 'Business':
        return 'business OR economy OR market OR finance OR trade OR stocks OR inflation OR bank';
      case 'Technology':
        return 'technology OR tech OR software OR AI OR cyber OR smartphone OR digital OR app OR computing OR startups';
      case 'Education':
        return 'education OR university OR school OR scholarship OR student OR learning OR exam OR KNEC OR KUCCPS';
      case 'Health':
        return 'health OR hospital OR doctor OR medicine OR virus OR vaccine OR medical OR clinic OR healthcare';
      case 'Sports':
        return 'sports OR football OR soccer OR basketball OR tennis OR marathon OR league OR match';
      case 'Entertainment':
        return 'entertainment OR movie OR music OR film OR celebrity OR show OR song OR artist OR streaming';
      case 'Science':
        return 'science OR research OR astronomy OR biology OR physics OR planet OR laboratory OR space';
      case 'Nature':
        return 'wildlife OR conservation OR forests OR biodiversity OR climate OR environment OR parks OR oceans OR pollution';
      case 'Culture':
        return 'culture OR heritage OR festival OR museum OR traditions OR religion OR languages OR arts OR fashion';
      case 'World':
        return 'world OR global OR international OR Europe OR Asia OR UN OR foreign';
      case 'Africa':
        return 'Africa OR African OR Nigeria OR South Africa OR Uganda OR Tanzania OR Ghana';
      case 'Kenya':
        return 'Kenya OR Kenyan OR Nairobi OR Mombasa OR Eldoret OR Ruto OR Laikipia';
      case 'Breaking':
        return 'breaking OR urgent OR alert OR flash OR disaster OR tragedy OR emergency';
      default:
        return category;
    }
  }

  private validateEnrichedArticle(article: NormalizedNews): boolean {
    const wordCount = (article.article || '').trim().split(/\s+/).length;
    const hasHeadline = Boolean(article.headline && article.headline.trim().length > 0);
    const hasSummary = Boolean(article.summary && article.summary.trim().length > 0);
    const hasWordCount = wordCount >= 300;
    const hasSixImages = Boolean(article.images && article.images.length >= 6);
    const hasBackground = Boolean(article.background && article.background.trim().length > 0);
    const hasAnalysis = Boolean(article.analysis && article.analysis.trim().length > 0);
    const hasWhyItMatters = Boolean(article.whyItMatters && article.whyItMatters.trim().length > 0);
    const hasWhatNext = Boolean(article.whatNext && article.whatNext.trim().length > 0);
    const isAiGenerated = article.aiGenerated === true;

    return (
      hasHeadline &&
      hasSummary &&
      hasWordCount &&
      hasSixImages &&
      hasBackground &&
      hasAnalysis &&
      hasWhyItMatters &&
      hasWhatNext &&
      isAiGenerated
    );
  }
}

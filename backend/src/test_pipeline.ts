import { ImageKitUploadService } from './services/imagekit_upload_service';
import { SearchGroundingService } from './services/search_grounding_service';
import { ImageEnrichmentService } from './services/image_enrichment_service';
import { GeminiService } from './services/gemini_service';
import { ViewerDocumentBuilder } from './services/viewer_document_builder';
import { FirestorePublisher } from './services/firestore_publisher';
import { CleanupService } from './services/cleanup_service';
import { SyncScheduler } from './scheduler/sync_scheduler';
import { NewsPublishingPipeline } from './services/news_publishing_pipeline';
import { NormalizationService } from './services/normalization_service';
import { RankingService } from './services/ranking_service';
import { ClusteringService } from './services/clustering_service';
import { Logger } from './utils/logger';
import { NewsApiArticle, NormalizedNews } from './models/news_article.model';

async function testCompleteStorageAndPublishingPipeline() {
  Logger.logHeader('TESTING COMPLETE PHASE 3 STORAGE, PUBLISHING & SYNC PIPELINE');

  const sampleArticle: NewsApiArticle = {
    source: { id: 'standard-media', name: 'Standard Media' },
    author: 'Jane Doe',
    title: 'Kenya Unveils New Renewable Solar Grid Infrastructure in Rift Valley',
    description: 'The Ministry of Energy has launched a massive solar grid expansion connecting rural schools and medical centres.',
    url: 'https://standardmedia.co.ke/kenya/article/998877/new-solar-grid-rift-valley',
    urlToImage: 'https://images.unsplash.com/photo-1509391365360-2e959784a276',
    publishedAt: new Date().toISOString(),
    content: 'The Ministry of Energy has officially commissioned a 50MW solar grid facility in the Rift Valley region. Local leaders commended the sustainable development initiative.',
  };

  // 1. Normalize & Rank
  const normalized: NormalizedNews | null = NormalizationService.normalizeNewsApiArticle(sampleArticle);
  if (!normalized) {
    Logger.error('Sample article normalization failed.');
    return;
  }

  normalized.importanceScore = RankingService.calculateImportanceScore(normalized);
  const clusters = ClusteringService.clusterArticles([normalized]);

  // 1b. Test SearchGroundingService
  console.log('\n--- 0a. TESTING SearchGroundingService ---');
  const grounding = await SearchGroundingService.performGroundingSearch(
    normalized.title,
    normalized.category,
    normalized.keywords,
    normalized.regionPriority
  );
  console.log('Grounded Items Count:', grounding.items.length);
  console.log('Sources Used:', grounding.sourcesUsed);

  // 1c. Test GeminiService Enrichment with Grounded Research
  console.log('\n--- 0b. TESTING GeminiService (AI Enrichment with Grounded Research) ---');
  const enrichedArticle = await GeminiService.generateMagazineArticle(normalized, grounding);
  console.log('Enriched Headline:', enrichedArticle.headline);
  console.log('Enriched Summary:', enrichedArticle.summary);
  console.log('AI Generated Flag:', enrichedArticle.aiGenerated);
  console.log('Why It Matters:', enrichedArticle.whyItMatters);
  console.log('What Next:', enrichedArticle.whatNext);

  // 1d. Test ImageEnrichmentService Detailed
  console.log('\n--- 0c. TESTING ImageEnrichmentService (Multi-Image 6-10 Validation) ---');
  const imageEnrichment = await ImageEnrichmentService.enrichArticleImagesDetailed(enrichedArticle);
  console.log('Images Accepted:', imageEnrichment.imagesAccepted);
  console.log('Images Rejected:', imageEnrichment.imagesRejected);
  console.log('Image Search Status:', imageEnrichment.status);

  // 2. Test ViewerDocumentBuilder
  console.log('\n--- 1. TESTING ViewerDocumentBuilder ---');
  const viewerDoc = ViewerDocumentBuilder.buildViewerDocument(
    enrichedArticle,
    enrichedArticle.imageUrl,
    clusters[0]
  );
  console.log(JSON.stringify(viewerDoc, null, 2));

  // 3. Test ImageKitUploadService
  console.log('\n--- 2. TESTING ImageKitUploadService (Image & Viewer Upload) ---');
  const imageResult = await ImageKitUploadService.uploadArticleImage(
    normalized.imageUrl,
    normalized.id
  );
  console.log('ImageUploadResult:', imageResult);

  const viewerResult = await ImageKitUploadService.uploadViewerDocument(viewerDoc);
  console.log('ViewerUploadResult:', viewerResult);

  // 4. Test FirestorePublisher
  console.log('\n--- 3. TESTING FirestorePublisher (Lightweight Metadata Document) ---');
  const firestorePublished = await FirestorePublisher.publishArticleMetadata({
    id: normalized.id,
    title: normalized.title,
    category: normalized.category,
    secondaryCategories: normalized.secondaryCategories || [],
    summary: normalized.summary,
    editorialSummary: normalized.editorialSummary || normalized.summary,
    thumbnailUrl: imageResult?.url || normalized.imageUrl,
    imageKitFileId: imageResult?.fileId || 'ik_img_test',
    viewerDocumentUrl: viewerResult?.url || 'ik_doc_test',
    viewerDocumentId: viewerResult?.fileId || 'ik_doc_test',
    source: normalized.sourceName,
    publishedAt: normalized.publishedAt,
    expiresAt: normalized.expiresAt,
    collectedAt: normalized.collectedAt,
    importanceScore: normalized.importanceScore || 0,
    qualityScore: normalized.qualityScore || 0,
    freshnessScore: normalized.freshnessScore || 0,
    readingTime: normalized.readingTime || 2,
    keywords: normalized.keywords || [],
    regionPriority: normalized.regionPriority,
    regionScore: normalized.regionScore,
    clusterId: normalized.clusterId,
    isTopStory: true,
    topStoryRank: 1,
    isTrending: true,
    trendingRank: 1,
    originalSourceUrl: normalized.sourceUrl,
    status: 'published',
    priority: 4,
  });
  console.log('FirestorePublished:', firestorePublished);

  // 5. Test CleanupService
  console.log('\n--- 4. TESTING CleanupService (Expiration Cleanup) ---');
  const cleanupStats = await CleanupService.executeCleanup();
  console.log('CleanupStats:', cleanupStats);

  // 6. Test NewsPublishingPipeline
  console.log('\n--- 5. TESTING NewsPublishingPipeline & SyncScheduler ---');
  const pipeline = new NewsPublishingPipeline();
  console.log('NewsPublishingPipeline instance initialized successfully.');

  const scheduler = new SyncScheduler();
  console.log('SyncScheduler instance initialized successfully.');
}

testCompleteStorageAndPublishingPipeline();

import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";
import { WorkerManager } from "./worker_manager";
import { ProviderRegistry } from "../providers/provider_registry";
import { ImageProviderRegistry } from "../providers/image/image_provider_registry";
import { ImageValidationService } from "./image_validation_service";
import { ArticleImageSearchService } from "./article_image_service";
import { ImageSearchResult } from "../types/image_worker";
import { ArticleImageData } from "../types/explore";

function getImageKit(): ImageKit {
  const publicKey = process.env.IMAGEKIT_PUBLIC_KEY || "public_fS58uA9h5vC6EwGv29Z=";
  const privateKey = process.env.IMAGEKIT_PRIVATE_KEY || "private_Ym87v5...=";
  const urlEndpoint = process.env.IMAGEKIT_URL_ENDPOINT || "https://ik.imagekit.io/ubgbitinve";

  return new ImageKit({
    publicKey,
    privateKey,
    urlEndpoint,
  });
}

export interface ExploreGenerationResult {
  success: boolean;
  articleId: string;
  article?: {
    id: string;
    title: string;
    summary: string;
    content: string;
    category: string;
    images: ArticleImageData[];
    imageCount: number;
    imageSources: string[];
    publishedAt: string;
    provider: string;
  };
  error?: string;
}

export class ExploreGenerationPipeline {
  /**
   * Generates a complete Explore news article end-to-end from a user search / topic query.
   * End-to-end pipeline:
   * 1. Check existing Firestore cache
   * 2. Acquire best AI WRITER worker from WorkerManager (with automatic failover across OpenAI, Gemini, Claude, DeepSeek, Kimi)
   * 3. Generate structured article with markdown sections and [IMAGE_1]...[IMAGE_5] placeholders
   * 4. Acquire best IMAGE worker from WorkerManager to search 3–5 real internet photographs
   * 5. Download, validate, hash-deduplicate, and upload real photos to ImageKit
   * 6. Replace placeholders in markdown content with ImageKit CDN URLs
   * 7. Save document to Firestore (`explore_news`)
   * 8. Return finalized payload to Flutter client
   */
  public static async generateArticleForTopic(
    db: admin.firestore.Firestore,
    query: string,
    category: string = "General",
    bypassCache: boolean = false
  ): Promise<ExploreGenerationResult> {
    const cleanQuery = (query || "").trim();
    if (!cleanQuery) {
      return { success: false, articleId: "", error: "Search query cannot be empty." };
    }

    logger.info(`[PIPELINE_START] Initiating Explore article generation pipeline for query="${cleanQuery}" category="${category}" (BypassCache=${bypassCache})`);

    // 1. Check if an article for this query already exists in explore_news (unless bypassCache is true)
    if (!bypassCache) {
      try {
        const existingSnap = await db
          .collection("explore_news")
          .where("topicQuery", "==", cleanQuery.toLowerCase())
          .where("imageSearchCompleted", "==", true)
          .limit(1)
          .get();

        if (!existingSnap.empty) {
          const doc = existingSnap.docs[0];
          const data = doc.data();
          logger.info(`[PIPELINE_CACHE_HIT] Article already generated for query="${cleanQuery}" docId="${doc.id}"`);
          return {
            success: true,
            articleId: doc.id,
            article: {
              id: doc.id,
              title: data.title || cleanQuery,
              summary: data.summary || "",
              content: data.content || "",
              category: data.category || category,
              images: data.images || [],
              imageCount: data.imageCount || 0,
              imageSources: data.imageSources || [],
              publishedAt: data.publishedAt?.toDate ? data.publishedAt.toDate().toISOString() : new Date().toISOString(),
              provider: data.provider || "cache",
            },
          };
        }
      } catch (e: any) {
        logger.warn(`[PIPELINE_CACHE_CHECK_WARN] Cache query skipped: ${e.message}`);
      }
    }

    // 2. Select AI Provider & Worker via WorkerManager Load Balancer (with failover)
    const writerWorker = await WorkerManager.getAvailableWorker(db, "WRITER");
    if (!writerWorker) {
      return { success: false, articleId: "", error: "No healthy AI WRITER worker available." };
    }

    logger.info(`[PIPELINE_WRITER_ALLOCATED] WorkerId="${writerWorker.workerId}" Provider="${writerWorker.provider}" Model="${writerWorker.model}"`);

    const articleDocRef = db.collection("explore_news").doc();
    const articleId = articleDocRef.id;
    const startTime = Date.now();

    await WorkerManager.acquireWorker(db, writerWorker.workerId, `gen_${articleId}`);

    let generatedArticle: { title: string; summary: string; content: string; category: string };

    try {
      // Get AI Provider implementation from ProviderRegistry
      const aiProvider = ProviderRegistry.getProvider(writerWorker.provider);

      // System Prompt & User Prompt for structured article generation
      const prompt = `
Write a comprehensive, professional news article on the topic: "${cleanQuery}".
Category: "${category}".

STRICT FORMAT & STRUCTURE REQUIREMENTS:
1. Title: Create a compelling, clear news headline.
2. Summary: Write a concise 2-3 sentence overview.
3. Content: Write a detailed news article in Markdown format with subheadings.
4. Placeholders: Embed exactly 5 image placeholders in the body text:
   [IMAGE_1], [IMAGE_2], [IMAGE_3], [IMAGE_4], [IMAGE_5]
   Place them evenly between sections where relevant news photographs should appear.

Output MUST be strictly valid JSON:
{
  "title": "News Headline",
  "summary": "2-3 sentence summary",
  "category": "${category}",
  "content": "# Headline\\n\\nArticle introduction...\\n\\n[IMAGE_1]\\n\\n## Section 1\\n\\nDetail text...\\n\\n[IMAGE_2]\\n\\n## Section 2\\n\\nDetail text...\\n\\n[IMAGE_3]\\n\\n## Section 3\\n\\nDetail text...\\n\\n[IMAGE_4]\\n\\n## Conclusion\\n\\nFinal text...\\n\\n[IMAGE_5]"
}
`;

      const genData = await aiProvider.generateMetadata(prompt, writerWorker);
      const latencyMs = Date.now() - startTime;
      await WorkerManager.releaseWorker(db, writerWorker.workerId, latencyMs, true);

      generatedArticle = {
        title: genData?.title || `${cleanQuery} Breaking News`,
        summary: genData?.summary || `Latest reporting on ${cleanQuery}.`,
        content: genData?.content || `# ${cleanQuery}\n\nLatest updates on ${cleanQuery}.\n\n[IMAGE_1]\n\nDetails and analysis.\n\n[IMAGE_2]`,
        category: genData?.category || category,
      };

      logger.info(`[PIPELINE_ARTICLE_GENERATED] Title="${generatedArticle.title}" by Worker="${writerWorker.workerId}" in ${latencyMs}ms`);
    } catch (err: any) {
      const latencyMs = Date.now() - startTime;
      await WorkerManager.releaseWorker(db, writerWorker.workerId, latencyMs, false);
      logger.error(`[PIPELINE_WRITER_ERROR] Writer worker "${writerWorker.workerId}" failed:`, err);
      return { success: false, articleId: "", error: `AI Generation failed: ${err.message}` };
    }

    // 3. Sourcing, Validating & Uploading 3–5 Real Internet Images via IMAGE Worker & ImageValidationService
    const imageWorker = await WorkerManager.getAvailableWorker(db, "IMAGE");
    const ik = getImageKit();
    let valResult: { images: ArticleImageData[]; imageCount: number; updatedContent: string; imageSources: string[] };

    if (imageWorker) {
      const imgStartTime = Date.now();
      await WorkerManager.acquireWorker(db, imageWorker.workerId, `img_${articleId}`);

      try {
        const imgProvider = ImageProviderRegistry.getProvider(imageWorker.provider);
        const searchQueries = ArticleImageSearchService.buildArticleSearchQueries(
          generatedArticle.title,
          generatedArticle.summary,
          generatedArticle.category
        );

        const candidateMetadata: ImageSearchResult[] = [];
        const seenUrls = new Set<string>();

        for (const q of searchQueries) {
          const results = await imgProvider.searchImages(q, { limit: 15 }, imageWorker);
          for (const item of results) {
            if (item && item.imageUrl && !seenUrls.has(item.imageUrl)) {
              seenUrls.add(item.imageUrl);
              candidateMetadata.push(item);
            }
          }
          if (candidateMetadata.length >= 20) break;
        }

        if (candidateMetadata.length > 0) {
          valResult = await ImageValidationService.processCandidateMetadata(
            db,
            ik,
            candidateMetadata,
            { title: generatedArticle.title, content: generatedArticle.content },
            5
          );
        } else {
          valResult = await ArticleImageSearchService.processArticleImages(
            db,
            ik,
            {
              id: articleId,
              clusterId: articleId,
              title: generatedArticle.title,
              content: generatedArticle.content,
              summary: generatedArticle.summary,
              category: generatedArticle.category,
            },
            5
          );
        }

        const imgLatency = Date.now() - imgStartTime;
        await WorkerManager.releaseWorker(db, imageWorker.workerId, imgLatency, true);
        logger.info(`[PIPELINE_IMAGES_ATTACHED] ImageWorker="${imageWorker.workerId}" attached ${valResult.imageCount} real internet photos in ${imgLatency}ms.`);
      } catch (imgErr: any) {
        const imgLatency = Date.now() - imgStartTime;
        await WorkerManager.releaseWorker(db, imageWorker.workerId, imgLatency, false);
        logger.warn(`[PIPELINE_IMAGE_WORKER_WARN] IMAGE worker failed, using fallback: ${imgErr.message}`);

        valResult = await ArticleImageSearchService.processArticleImages(
          db,
          ik,
          {
            id: articleId,
            clusterId: articleId,
            title: generatedArticle.title,
            content: generatedArticle.content,
            summary: generatedArticle.summary,
            category: generatedArticle.category,
          },
          5
        );
      }
    } else {
      // Fallback if no dedicated IMAGE worker is available
      valResult = await ArticleImageSearchService.processArticleImages(
        db,
        ik,
        {
          id: articleId,
          clusterId: articleId,
          title: generatedArticle.title,
          content: generatedArticle.content,
          summary: generatedArticle.summary,
          category: generatedArticle.category,
        },
        5
      );
    }

    // 4. Save finished article and metadata in Firestore (`explore_news`)
    const publishedAtDate = new Date();
    const firestorePayload = {
      topicQuery: cleanQuery.toLowerCase(),
      clusterId: articleId,
      title: generatedArticle.title,
      summary: generatedArticle.summary,
      content: valResult.updatedContent,
      category: generatedArticle.category,
      images: valResult.images,
      imageCount: valResult.imageCount,
      imageSearchCompleted: true,
      imageSearchAttempts: 1,
      imageSources: valResult.imageSources,
      assignedWorker: writerWorker.workerId,
      provider: writerWorker.provider,
      status: "published",
      publishedAt: admin.firestore.Timestamp.fromDate(publishedAtDate),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await articleDocRef.set(firestorePayload);
    logger.info(`[PIPELINE_COMPLETE] Article successfully generated, enriched with ${valResult.imageCount} photos, and saved to Firestore docId="${articleId}".`);

    // 5. Return complete response payload to client
    return {
      success: true,
      articleId,
      article: {
        id: articleId,
        title: generatedArticle.title,
        summary: generatedArticle.summary,
        content: valResult.updatedContent,
        category: generatedArticle.category,
        images: valResult.images,
        imageCount: valResult.imageCount,
        imageSources: valResult.imageSources,
        publishedAt: publishedAtDate.toISOString(),
        provider: writerWorker.provider,
      },
    };
  }
}

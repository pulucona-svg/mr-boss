import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";
import { WorkerManager } from "./worker_manager";
import { AIWorker } from "../types/worker";
import { ProviderRegistry } from "../providers/provider_registry";
import { ArticleImageSearchService } from "./article_image_service";
import { ArticleImageData } from "../types/explore";

function getImageKit(): ImageKit {
  const publicKey = process.env.IMAGEKIT_PUBLIC_KEY || "";
  const privateKey = process.env.IMAGEKIT_PRIVATE_KEY || "";
  const urlEndpoint = process.env.IMAGEKIT_URL_ENDPOINT || "";
  if (!publicKey || !privateKey || !urlEndpoint) throw new Error("ImageKit is not configured");

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

export interface ArticleSourceContext {
  candidateId?: string;
  source?: string;
  sourceUrl?: string;
  publishedAt?: string;
  discoveredAt?: admin.firestore.Timestamp | admin.firestore.FieldValue;
  discoveryWorker?: string;
  discoveryProvider?: string;
  categoryId?: string;
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
    bypassCache: boolean = false,
    sourceContext?: ArticleSourceContext,
    assignedWorker?: AIWorker
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
    const writerWorker = assignedWorker || await WorkerManager.getAvailableWorker(db, "WRITER");
    if (!writerWorker) {
      return { success: false, articleId: "", error: "No healthy AI WRITER worker available." };
    }

    logger.info(`[PIPELINE_WRITER_ALLOCATED] WorkerId="${writerWorker.workerId}" Provider="${writerWorker.provider}" Model="${writerWorker.model}"`);

    const articleDocRef = db.collection("explore_news").doc();
    const articleId = articleDocRef.id;
    const startTime = Date.now();

    if (!assignedWorker) await WorkerManager.acquireWorker(db, writerWorker.workerId, `gen_${articleId}`);

    let generatedArticle: { title: string; summary: string; content: string; category: string };

    try {
      // Get AI Provider implementation from ProviderRegistry
      const aiProvider = ProviderRegistry.getProvider(writerWorker.provider);

      // System Prompt & User Prompt for structured article generation
      const prompt = `
You are a senior investigative journalist writing for a professional news publication.
Write a factual, engaging, humanized news article of approximately 500 words on the event: "${cleanQuery}".
Category: "${category}".

SOURCE CONTEXT:
${sourceContext?.source ? `Primary Source: ${sourceContext.source}` : ""}
${sourceContext?.sourceUrl ? `Source URL: ${sourceContext.sourceUrl}` : ""}
${sourceContext?.publishedAt ? `Source Timestamp: ${sourceContext.publishedAt}` : ""}

JOURNALISTIC & WRITING RULES:
1. Tone: Clear, natural, professional journalism written for ordinary readers on mobile.
2. Length: Approximately 450 to 550 words.
3. Sentence Variety: Vary sentence lengths and structure. Avoid robotic cadence.
4. FORBIDDEN AI PHRASES: Do NOT use clichés like "In today's rapidly evolving world", "In an era of...", "In a significant development", "It remains to be seen", "A testament to", "Delve into", "Tapestry", or similar AI boilerplate.
5. NO MENTION OF AI: Never mention AI, LLMs, generation processes, or prompting.
6. STRICT FACTUAL ACCURACY: Do NOT invent facts, quotes, names, statistics, dates, or historical events. Only report verifiable information from reputable reporting and context. Clearly attribute statements to original sources where appropriate.
7. Image Placeholders: Embed exactly 5 image placeholders ([IMAGE_1], [IMAGE_2], [IMAGE_3], [IMAGE_4], [IMAGE_5]) distributed evenly between sections so photos accompany paragraphs naturally.

REQUIRED JSON OUTPUT FORMAT (Strictly JSON, no extra text):
{
  "title": "Clear, Engaging Headline Without Clickbait",
  "summary": "Crisp 2-sentence executive summary covering who, what, and impact.",
  "category": "${category}",
  "content": "# Headline\\n\\nOpening lead paragraph establishing the core news and why it matters...\\n\\n[IMAGE_1]\\n\\n## Background and Key Developments\\n\\nDetailed context and factual background...\\n\\n[IMAGE_2]\\n\\n## Direct Impact and Analysis\\n\\nAnalysis of what this means for stakeholders and the public...\\n\\n[IMAGE_3]\\n\\n## Broader Industry and Regional Context\\n\\nPerspectives and verifiable context from industry or regional observers...\\n\\n[IMAGE_4]\\n\\n## Outlook\\n\\nForward-looking facts and next expected milestones...\\n\\n[IMAGE_5]"
}
`;

      const genData = await aiProvider.generateMetadata(prompt, writerWorker);
      const latencyMs = Date.now() - startTime;
       if (!assignedWorker) await WorkerManager.releaseWorker(db, writerWorker.workerId, latencyMs, true);

      generatedArticle = {
        title: (genData?.title || "").trim(),
        summary: (genData?.summary || "").trim(),
        content: (genData?.content || "").trim(),
        category: (genData?.category || category).trim(),
      };

      // Strict validation of AI structured output
      if (!generatedArticle.title || generatedArticle.title.length < 10) {
        throw new Error("Writer returned invalid or missing article title (min 10 characters)");
      }
      if (!generatedArticle.summary || generatedArticle.summary.length < 20) {
        throw new Error("Writer returned invalid or missing article summary (min 20 characters)");
      }
      if (!generatedArticle.content || generatedArticle.content.length < 200) {
        throw new Error("Writer returned invalid or truncated article content (min 200 characters)");
      }

      logger.info(
        `[AI_WORKER] worker="${writerWorker.workerId}" provider="${writerWorker.provider}" key="${writerWorker.apiKeyReference || "primary"}" action="article_generated" title="${generatedArticle.title}" latency="${latencyMs}ms"`
      );
    } catch (err: any) {
      const latencyMs = Date.now() - startTime;
      if (!assignedWorker) await WorkerManager.releaseWorker(db, writerWorker.workerId, latencyMs, false);
      logger.error(`[PIPELINE_WRITER_ERROR] Writer worker "${writerWorker.workerId}" failed:`, err);
      return { success: false, articleId: "", error: `AI Generation failed: ${err.message}` };
    }

    // 3. Sourcing, Validating & Uploading Real Internet Images to ImageKit
    const ik = getImageKit();
    const valResult = await ArticleImageSearchService.processArticleImages(
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

    // 4. Validate images before publication (strictly require 5 validated images)
    if (valResult.imageCount < 5 || valResult.images.length < 5) {
      logger.warn(`[PIPELINE_NOT_READY] Article ${articleId} does not have 5 validated images (found ${valResult.imageCount}).`);
      return { success: false, articleId, error: `Article failed validation: requires 5 images (found ${valResult.imageCount}).` };
    }

    // Check for idempotency: if candidate was already published, avoid duplicate
    if (sourceContext?.candidateId) {
      const existingSnap = await db
        .collection("explore_news")
        .where("candidateId", "==", sourceContext.candidateId)
        .limit(1)
        .get();
      if (!existingSnap.empty) {
        const existingDoc = existingSnap.docs[0];
        logger.info(`[PIPELINE_IDEMPOTENT] Candidate "${sourceContext.candidateId}" already published as docId="${existingDoc.id}". Skipping duplicate write.`);
        return {
          success: true,
          articleId: existingDoc.id,
          article: existingDoc.data() as any,
        };
      }
    }

    // 5. Save finished article and metadata in Firestore (`explore_news`)
    const publishedAtDate = new Date();
    const categoryId = sourceContext?.categoryId || generatedArticle.category
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "");

    const firstImageUrl = valResult.images?.[0]?.imageUrl || "";
    const imageUrls = valResult.images.map((img) => img.imageUrl);

    const firestorePayload = {
      articleId,
      id: articleId,
      topicQuery: cleanQuery.toLowerCase(),
      clusterId: articleId,
      title: generatedArticle.title,
      summary: generatedArticle.summary,
      editorialSummary: generatedArticle.summary,
      content: valResult.updatedContent,
      category: generatedArticle.category,
      categoryId,
      coverImage: firstImageUrl,
      thumbnailUrl: firstImageUrl,
      imageUrls,
      images: valResult.images,
      imageCount: valResult.imageCount,
      imageSearchCompleted: true,
      imageSearchAttempts: 1,
      imageSources: valResult.imageSources,
      assignedWorker: writerWorker.workerId,
      provider: writerWorker.provider,
      source: sourceContext?.source || "",
      sourceUrl: sourceContext?.sourceUrl || "",
      originalSourceUrl: sourceContext?.sourceUrl || "",
      sourcePublishedAt: sourceContext?.publishedAt || null,
      candidateId: sourceContext?.candidateId || null,
      discoveryWorker: sourceContext?.discoveryWorker || null,
      discoveryProvider: sourceContext?.discoveryProvider || null,
      discoveredAt: sourceContext?.discoveredAt || admin.firestore.FieldValue.serverTimestamp(),
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

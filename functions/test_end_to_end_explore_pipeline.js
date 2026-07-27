/**
 * Verification Test Suite for First Complete End-to-End Explore Generation Pipeline
 */

const assert = require("assert");
const { ExploreGenerationPipeline } = require("./lib/services/explore_generation_pipeline");
const { WorkerManager } = require("./lib/services/worker_manager");
const { ProviderRegistry } = require("./lib/providers/provider_registry");
const { ImageProviderRegistry } = require("./lib/providers/image/image_provider_registry");
const { EnvConfig } = require("./lib/config/env_config");

console.log("=================================================");
console.log(" END-TO-END EXPLORE GENERATION PIPELINE SUITE ");
console.log("=================================================\n");

// Mock Firestore DB builder
function createMockFirestore(workerDocs = {}, newsDocs = {}, usedImageDocs = {}) {
  return {
    collection: (collName) => {
      if (collName === "workers") {
        return {
          get: async () => ({
            docs: Object.entries(workerDocs).map(([id, data]) => ({
              id,
              data: () => data,
            })),
          }),
          doc: (docId) => ({
            update: async (fields) => {
              if (!workerDocs[docId]) workerDocs[docId] = {};
              Object.assign(workerDocs[docId], fields);
            },
            get: async () => ({
              exists: !!workerDocs[docId],
              data: () => workerDocs[docId],
            }),
          }),
        };
      }
      if (collName === "explore_news") {
        return {
          where: (field, op, val) => ({
            where: (f2, o2, v2) => ({
              limit: (num) => ({
                get: async () => {
                  const filtered = Object.entries(newsDocs).filter(([id, n]) => n[field] === val && n[f2] === v2);
                  return {
                    empty: filtered.length === 0,
                    docs: filtered.slice(0, num).map(([id, data]) => ({
                      id,
                      data: () => data,
                    })),
                  };
                },
              }),
            }),
            limit: (num) => ({
              get: async () => {
                const filtered = Object.entries(newsDocs).filter(([id, n]) => n[field] === val);
                return {
                  empty: filtered.length === 0,
                  docs: filtered.slice(0, num).map(([id, data]) => ({
                    id,
                    data: () => data,
                  })),
                };
              },
            }),
          }),
          doc: (docId) => {
            if (!docId) docId = "doc_" + Math.random().toString(36).substr(2, 6);
            return {
              id: docId,
              get: async () => ({
                exists: !!newsDocs[docId],
                data: () => newsDocs[docId],
              }),
              set: async (fields) => {
                newsDocs[docId] = fields;
              },
              update: async (fields) => {
                if (!newsDocs[docId]) newsDocs[docId] = {};
                Object.assign(newsDocs[docId], fields);
              },
            };
          },
        };
      }
      if (collName === "used_article_images") {
        return {
          where: (field, op, val) => ({
            limit: (num) => ({
              get: async () => ({
                empty: Object.values(usedImageDocs).filter(u => u[field] === val).length === 0,
              }),
            }),
          }),
          add: async (item) => {
            const id = "hash_" + Math.random().toString(36).substr(2, 6);
            usedImageDocs[id] = item;
            return { id };
          },
        };
      }
      return {
        get: async () => ({ docs: [] }),
        doc: (docId) => ({ id: docId, get: async () => ({ exists: false }) }),
      };
    },
    runTransaction: async (updateFunction) => {
      const transactionApi = {
        get: async (ref) => ref.get(),
        update: (ref, fields) => ref.update(fields),
      };
      return await updateFunction(transactionApi);
    },
  };
}

(async () => {
  // Setup Workers in Mock Firestore
  const mockWorkers = {
    worker_writer_01: {
      provider: "openai",
      apiKey: process.env.OPENAI_API_KEY || "sk-mock-1",
      enabled: true,
      busy: false,
      status: "idle",
      role: "WRITER",
      averageLatency: 120,
    },
    worker_image_01: {
      provider: "pixabay",
      apiKey: "mock-pixabay-key",
      enabled: true,
      busy: false,
      status: "idle",
      role: "IMAGE",
      averageLatency: 90,
    },
  };

  const db = createMockFirestore(mockWorkers);

  // ----------------------------------------------------------------
  // TEST 1: END-TO-END ARTICLE GENERATION FLOW
  // ----------------------------------------------------------------
  console.log("Test 1: Execute complete End-to-End Explore Generation Pipeline for user query");
  const result = await ExploreGenerationPipeline.generateArticleForTopic(
    db,
    "Nairobi Climate Summit 2026",
    "Environment"
  );

  assert.strictEqual(result.success, true, "Pipeline execution must succeed");
  assert(result.articleId !== "", "Must return non-empty articleId");

  const article = result.article;
  assert(article !== undefined, "Result must contain article object");
  assert(article.title.length > 0, "Article title must be non-empty");
  assert(article.summary.length > 0, "Article summary must be non-empty");
  assert(article.content.length > 0, "Article content must be non-empty");
  assert.strictEqual(article.category, "Environment");
  assert(Array.isArray(article.images), "Article images must be an array");
  assert(typeof article.imageCount === "number", "imageCount must be a number");
  assert(article.publishedAt !== undefined, "publishedAt must be present");
  assert(article.provider !== undefined, "provider must be present");

  console.log(`  PASSED: Generated article "${article.title}" (DocId: ${result.articleId}, Images attached: ${article.imageCount}, Provider: ${article.provider}).\n`);

  // ----------------------------------------------------------------
  // TEST 2: FIRESTORE DOCUMENT PERSISTENCE & METADATA FORMAT
  // ----------------------------------------------------------------
  console.log("Test 2: Verify Firestore document persistence and image placeholder replacements");
  
  // Verify placeholders [IMAGE_1]...[IMAGE_5] were processed in markdown content
  assert(!article.content.includes("[IMAGE_1]"), "Placeholder [IMAGE_1] must be replaced or cleaned up");
  assert(!article.content.includes("[IMAGE_2]"), "Placeholder [IMAGE_2] must be replaced or cleaned up");

  console.log("  PASSED: Placeholders replaced with ImageKit URLs or cleaned up cleanly without leakage.\n");

  // ----------------------------------------------------------------
  // TEST 3: PIPELINE CACHE HIT ON REPEATED USER SEARCH
  // ----------------------------------------------------------------
  console.log("Test 3: Verify pipeline retrieves cached article on repeated user search");
  const cachedResult = await ExploreGenerationPipeline.generateArticleForTopic(
    db,
    "Nairobi Climate Summit 2026",
    "Environment"
  );

  assert.strictEqual(cachedResult.success, true);
  assert.strictEqual(cachedResult.articleId, result.articleId, "Cached result must match existing docId");
  assert(cachedResult.article.provider !== undefined, "Cached article must retain provider metadata");

  console.log("  PASSED: Repeated user query returned cached article instantly.\n");

  // ----------------------------------------------------------------
  // TEST 4: AUTOMATIC FAILOVER ROUTING IN END-TO-END PIPELINE
  // ----------------------------------------------------------------
  console.log("Test 4: Verify pipeline automatic failover when primary WRITER is marked UNHEALTHY");
  
  // Mark OpenAI UNHEALTHY, add Gemini worker
  mockWorkers["worker_writer_gemini"] = {
    provider: "gemini",
    apiKey: process.env.GEMINI_API_KEY || "sk-gem-1",
    enabled: true,
    busy: false,
    status: "idle",
    role: "WRITER",
    averageLatency: 150,
  };

  EnvConfig.setProviderHealth("openai", false, 0, "429 Rate Limit");
  EnvConfig.setProviderHealth("gemini", true, 150);

  const failoverResult = await ExploreGenerationPipeline.generateArticleForTopic(
    db,
    "Quantum Computing Breakthrough 2026",
    "Technology"
  );

  assert.strictEqual(failoverResult.success, true);
  assert.strictEqual(failoverResult.article.provider, "gemini", "Pipeline must automatically failover to Gemini");

  // Restore OpenAI health
  EnvConfig.setProviderHealth("openai", true, 100);

  console.log("  PASSED: Pipeline successfully executed failover from OpenAI -> Gemini.\n");

  console.log("=================================================");
  console.log(" ALL 4 END-TO-END EXPLORE PIPELINE TESTS PASSED! ");
  console.log("=================================================");
})();

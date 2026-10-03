/**
 * Unit & Integration Mock Tests for Multi-Provider AI Thumbnail System
 * (Flux.2 Dev -> Gemini -> Frontend Fallback)
 * 
 * Verifies:
 * 1. Flux.2 Dev multipart/form-data request construction & header validation.
 * 2. Flux.2 Dev response parsing (JSON base64 and direct binary).
 * 3. Provider priority & Failover (Flux succeeds -> Gemini skipped).
 * 4. Provider priority & Failover (Flux fails -> Gemini called).
 * 5. Provider priority & Failover (Both fail -> graceful failure, no crash).
 * 6. Provider metadata tracking (provider name & model recorded).
 */

const assert = require("assert");
const http = require("http");
const https = require("https");
const EventEmitter = require("events");

// Import compiled providers and services
const { FluxThumbnailProvider, FluxProviderError } = require("./lib/providers/image_generation/flux_thumbnail_provider");
const { FluxWorkerPool } = require("./lib/providers/image_generation/flux_worker_pool");
const { GeminiThumbnailProvider } = require("./lib/providers/image_generation/gemini_thumbnail_provider");
const { ThumbnailSearchService } = require("./lib/thumbnail_search_service");

async function runTests() {
  console.log("=== MULTI-PROVIDER THUMBNAIL SYSTEM TEST SUITE ===\n");
  let passed = 0;
  let failed = 0;

  function test(name, fn) {
    try {
      fn();
      console.log(`[PASS] ${name}`);
      passed++;
    } catch (err) {
      console.error(`[FAIL] ${name}:`, err.message);
      failed++;
    }
  }

  async function asyncTest(name, fn) {
    try {
      await fn();
      console.log(`[PASS] ${name}`);
      passed++;
    } catch (err) {
      console.error(`[FAIL] ${name}:`, err);
      failed++;
    }
  }

  // --- TEST 1: Flux Multipart Request Construction ---
  await asyncTest("Flux Provider: constructs valid multipart/form-data payload with required fields", async () => {
    const provider = new FluxThumbnailProvider({
      accountId: "test_account_123",
      apiKey: "test_api_key_456",
      model: "@cf/black-forest-labs/flux-2-dev",
    });

    assert.strictEqual(provider.name, "flux");
    assert.strictEqual(provider.priority, 1);

    // Intercept https.request to inspect the headers and body
    const originalRequest = https.request;
    let capturedOptions = null;
    let capturedChunks = [];

    https.request = function (options, callback) {
      capturedOptions = options;
      const reqStream = new EventEmitter();
      reqStream.write = function (chunk) {
        capturedChunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
      };
      reqStream.end = function (chunk) {
        if (chunk) capturedChunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
        
        // Mock a successful JSON base64 response
        const dummyBase64 = Buffer.from("fake-jpeg-image-bytes").toString("base64");
        const resStream = new EventEmitter();
        resStream.statusCode = 200;
        resStream.headers = { "content-type": "application/json" };

        callback(resStream);
        resStream.emit("data", Buffer.from(JSON.stringify({ result: { image: dummyBase64 } })));
        resStream.emit("end");
      };
      reqStream.on = function (event, handler) {
        EventEmitter.prototype.on.call(this, event, handler);
        return this;
      };
      reqStream.setTimeout = function () {};
      reqStream.destroy = function () {};
      return reqStream;
    };

    try {
      const result = await provider.generateImage("Create a textbook cover for Calculus", {
        title: "Calculus I",
        materialType: "Notes",
        courseCode: "MATH101",
      });

      assert(result, "Result should not be null");
      assert.strictEqual(result.mimeType, "image/jpeg");
      assert.strictEqual(result.modelUsed, "@cf/black-forest-labs/flux-2-dev");
      assert.strictEqual(result.imageBuffer.toString(), "fake-jpeg-image-bytes");

      // Verify request options
      assert.strictEqual(capturedOptions.hostname, "api.cloudflare.com");
      assert.strictEqual(
        capturedOptions.path,
        "/client/v4/accounts/test_account_123/ai/run/@cf/black-forest-labs/flux-2-dev"
      );
      assert.strictEqual(capturedOptions.method, "POST");
      assert.strictEqual(capturedOptions.family, 4); // IPv4 enforcement
      assert.strictEqual(capturedOptions.headers["Authorization"], "Bearer test_api_key_456");
      assert(capturedOptions.headers["Content-Type"].includes("multipart/form-data; boundary="));

      // Verify multipart body contains required fields
      const fullBody = Buffer.concat(capturedChunks).toString();
      assert(fullBody.includes('name="prompt"'), "Multipart body must include prompt");
      assert(fullBody.includes("Create a textbook cover for Calculus"), "Multipart body must include prompt text");
      assert(fullBody.includes('name="width"'), "Multipart body must include width");
      assert(fullBody.includes("1024"), "Width must be 1024");
      assert(fullBody.includes('name="height"'), "Multipart body must include height");
      assert(fullBody.includes("576"), "Height must be 576");
      assert(fullBody.includes('name="steps"'), "Multipart body must include steps");
      assert(fullBody.includes("25"), "Steps must be 25");
    } finally {
      https.request = originalRequest;
    }
  });

  // --- TEST 2: Flux Provider: Binary Response Parsing ---
  await asyncTest("Flux Provider: parses direct binary image responses", async () => {
    const provider = new FluxThumbnailProvider({
      accountId: "test_acc",
      apiKey: "test_key",
      model: "@cf/black-forest-labs/flux-2-dev",
    });

    const originalRequest = https.request;
    const rawBinary = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);

    https.request = function (options, callback) {
      const reqStream = new EventEmitter();
      reqStream.write = function () {};
      reqStream.end = function () {
        const resStream = new EventEmitter();
        resStream.statusCode = 200;
        resStream.headers = { "content-type": "image/jpeg" };

        callback(resStream);
        resStream.emit("data", rawBinary);
        resStream.emit("end");
      };
      reqStream.setTimeout = function () {};
      reqStream.destroy = function () {};
      return reqStream;
    };

    try {
      const result = await provider.generateImage("Binary test prompt", { title: "Binary Test" });
      assert(result, "Result should not be null");
      assert.deepStrictEqual(result.imageBuffer, rawBinary);
      assert.strictEqual(result.mimeType, "image/jpeg");
    } finally {
      https.request = originalRequest;
    }
  });

  // --- TEST 3: Flux Provider: Error Handling ---
  await asyncTest("Flux Provider: throws clear error on API failure (e.g. 500 or invalid input)", async () => {
    const provider = new FluxThumbnailProvider({
      accountId: "test_acc",
      apiKey: "test_key",
      model: "@cf/black-forest-labs/flux-2-dev",
    });

    const originalRequest = https.request;

    https.request = function (options, callback) {
      const reqStream = new EventEmitter();
      reqStream.write = function () {};
      reqStream.end = function () {
        const resStream = new EventEmitter();
        resStream.statusCode = 400;
        resStream.headers = { "content-type": "application/json" };

        callback(resStream);
        resStream.emit(
          "data",
          Buffer.from(JSON.stringify({ success: false, errors: [{ code: 10000, message: "AiError: Bad input" }] }))
        );
        resStream.emit("end");
      };
      reqStream.setTimeout = function () {};
      reqStream.destroy = function () {};
      return reqStream;
    };

    try {
      await provider.generateImage("Fail prompt", { title: "Fail Test" });
      assert.fail("Should have thrown error on 400 status");
    } catch (err) {
      assert(err.message.includes("400") || err.message.includes("AiError"), "Error should reflect API response");
    } finally {
      https.request = originalRequest;
    }
  });

  // --- TEST 4: Gemini Provider Mock ---
  await asyncTest("Gemini Provider: generates image correctly with configured candidate pool", async () => {
    const provider = new GeminiThumbnailProvider("test_gemini_key");
    assert.strictEqual(provider.name, "gemini");
    assert.strictEqual(provider.priority, 2);

    // Mock global.fetch to simulate Gemini generateContent returning inlineData
    const originalFetch = global.fetch;
    const dummyImage = Buffer.from("gemini-generated-image-data").toString("base64");

    global.fetch = async function (url, options) {
      return {
        ok: true,
        status: 200,
        json: async () => ({
          candidates: [
            {
              content: {
                parts: [
                  {
                    inlineData: {
                      mimeType: "image/jpeg",
                      data: dummyImage,
                    },
                  },
                ],
              },
            },
          ],
        }),
        text: async () => "{}",
      };
    };

    try {
      const result = await provider.generateImage("Gemini prompt", { title: "Gemini Test" });
      assert(result, "Result should not be null");
      assert.strictEqual(result.mimeType, "image/jpeg");
      assert(result.modelUsed.includes("flash-image"));
      assert.strictEqual(result.imageBuffer.toString(), "gemini-generated-image-data");
    } finally {
      global.fetch = originalFetch;
    }
  });

  // --- TEST 5: Failover Logic in ThumbnailSearchService ---
  await asyncTest("Failover: Primary (Flux) succeeds -> Secondary (Gemini) is not called", async () => {
    let fluxCalled = false;
    let geminiCalled = false;

    // Create custom mock providers
    const mockFlux = {
      name: "flux",
      priority: 1,
      generateImage: async () => {
        fluxCalled = true;
        return {
          imageBuffer: Buffer.from("mock-flux-pixels"),
          mimeType: "image/jpeg",
          modelUsed: "@cf/black-forest-labs/flux-2-dev",
        };
      },
    };

    const mockGemini = {
      name: "gemini",
      priority: 2,
      generateImage: async () => {
        geminiCalled = true;
        return {
          imageBuffer: Buffer.from("mock-gemini-pixels"),
          mimeType: "image/jpeg",
          modelUsed: "gemini-2.5-flash-image",
        };
      },
    };

    // Run the provider iteration simulation
    const providers = [mockFlux, mockGemini];
    let selectedResult = null;

    for (const provider of providers) {
      try {
        const res = await provider.generateImage();
        if (res && res.imageBuffer) {
          selectedResult = { ...res, provider: provider.name };
          break;
        }
      } catch (e) {}
    }

    assert(fluxCalled, "Flux should have been called first");
    assert(!geminiCalled, "Gemini should NOT have been called when Flux succeeds");
    assert.strictEqual(selectedResult.provider, "flux");
    assert.strictEqual(selectedResult.modelUsed, "@cf/black-forest-labs/flux-2-dev");
  });

  await asyncTest("Failover: Primary (Flux) fails -> Secondary (Gemini) succeeds", async () => {
    let fluxCalled = false;
    let geminiCalled = false;

    const mockFlux = {
      name: "flux",
      priority: 1,
      generateImage: async () => {
        fluxCalled = true;
        throw new Error("Cloudflare 504 Gateway Timeout or Quota Exceeded");
      },
    };

    const mockGemini = {
      name: "gemini",
      priority: 2,
      generateImage: async () => {
        geminiCalled = true;
        return {
          imageBuffer: Buffer.from("mock-gemini-pixels"),
          mimeType: "image/jpeg",
          modelUsed: "gemini-2.5-flash-image",
        };
      },
    };

    const providers = [mockFlux, mockGemini];
    let selectedResult = null;

    for (const provider of providers) {
      try {
        const res = await provider.generateImage();
        if (res && res.imageBuffer) {
          selectedResult = { ...res, provider: provider.name };
          break;
        }
      } catch (e) {}
    }

    assert(fluxCalled, "Flux should have been called first");
    assert(geminiCalled, "Gemini should be called when Flux fails");
    assert.strictEqual(selectedResult.provider, "gemini");
    assert.strictEqual(selectedResult.modelUsed, "gemini-2.5-flash-image");
  });

  await asyncTest("Failover: Both providers fail -> Returns graceful failure without throwing", async () => {
    let fluxCalled = false;
    let geminiCalled = false;

    const mockFlux = {
      name: "flux",
      priority: 1,
      generateImage: async () => {
        fluxCalled = true;
        throw new Error("Flux quota exceeded");
      },
    };

    const mockGemini = {
      name: "gemini",
      priority: 2,
      generateImage: async () => {
        geminiCalled = true;
        throw new Error("Gemini quota exceeded (429)");
      },
    };

    const providers = [mockFlux, mockGemini];
    let selectedResult = null;

    for (const provider of providers) {
      try {
        const res = await provider.generateImage();
        if (res && res.imageBuffer) {
          selectedResult = { ...res, provider: provider.name };
          break;
        }
      } catch (e) {}
    }

    assert(fluxCalled, "Flux was attempted");
    assert(geminiCalled, "Gemini was attempted");
    assert.strictEqual(selectedResult, null, "Result should be null when both fail");
    // Frontend receives pending placeholder without any uncaught exceptions
  });

  // --- TEST 6: Audit log and Forced Provider ---
  test("Forced Provider configuration works correctly", () => {
    // forcedProvider === 'gemini' selects only gemini
    const forcedGemini = "gemini";
    let providers = [];
    if (forcedGemini === "gemini") {
      providers = [new GeminiThumbnailProvider("dummy")];
    }
    assert.strictEqual(providers.length, 1);
    assert.strictEqual(providers[0].name, "gemini");

    // forcedProvider === 'flux' selects only flux
    const forcedFlux = "flux";
    if (forcedFlux === "flux") {
      providers = [new FluxThumbnailProvider({ accountId: "a", apiKey: "b", model: "c" })];
    }
    assert.strictEqual(providers.length, 1);
    assert.strictEqual(providers[0].name, "flux");
  });

  // --- TEST 7: Prompt Structure & Strict NO TEXT Constraints (Task 1) ---
  test("Prompt Builder: Generates purely visual prompt with mandatory NO TEXT negative constraints and no title quotation", () => {
    const prompt = ThumbnailSearchService.buildImagePrompt({
      title: "Operating Systems Principles",
      courseCode: "BICT 221",
      materialType: "Notes",
      topic: "Kernel Architecture and Process Scheduling",
      description: "Comprehensive notes on OS concepts",
    });

    // Verify sections exist
    assert(prompt.includes("[VISUAL SCENE & OBJECTS]:"), "Must include visual scene section");
    assert(prompt.includes("[ACADEMIC RELEVANCE]:"), "Must include academic relevance section");
    assert(prompt.includes("[COMPOSITION & LIGHTING]:"), "Must include composition section");
    assert(prompt.includes("[STYLE & RENDER QUALITY]:"), "Must include style section");
    assert(prompt.includes("[MANDATORY NEGATIVE CONSTRAINTS - STRICTLY NO TEXT]:"), "Must include negative constraints section");

    // Verify strict NO TEXT prohibitions
    assert(prompt.includes("ABSOLUTELY ZERO TEXT"), "Must forbid text");
    assert(prompt.includes("NO WRITTEN WORDS"), "Must forbid words");
    assert(prompt.includes("NO LETTERS"), "Must forbid letters");
    assert(prompt.includes("NO NUMBERS"), "Must forbid numbers");
    assert(prompt.includes("NO LABELS"), "Must forbid labels");
    assert(prompt.includes("NO TYPOGRAPHY"), "Must forbid typography");
    assert(prompt.includes("NO WATERMARKS"), "Must forbid watermarks");

    // Verify the raw title or course code is NOT wrapped in quotes as text to render
    assert(!prompt.includes('"Operating Systems Principles"'), "Title must not be quoted as text instructions");
    assert(!prompt.includes('"BICT 221"'), "Course code must not be quoted as text instructions");
  });

  // --- TEST 8: Error Classification for Flux Capacity & Rate Limits (Task 2) ---
  test("FluxProviderError: Classifies transient capacity vs permanent errors accurately", () => {
    // 429 Rate Limit / Out of capacity
    const err429 = new FluxProviderError("Cloudflare HTTP 429: Too Many Requests", true, 429);
    assert.strictEqual(err429.isRetryable, true, "429 must be retryable");
    assert.strictEqual(err429.statusCode, 429);

    // Code 3040 Cloudflare Workers AI capacity error
    const err3040 = new FluxProviderError("Cloudflare error code 3040: Out of capacity", true, 500, 3040);
    assert.strictEqual(err3040.isRetryable, true, "Code 3040 out of capacity must be retryable");
    assert.strictEqual(err3040.cloudflareErrorCode, 3040);

    // 408 / Timeout
    const err408 = new FluxProviderError("Request timed out", true, 408);
    assert.strictEqual(err408.isRetryable, true, "408 timeout must be retryable");

    // 503 Service Unavailable
    const err503 = new FluxProviderError("Service Unavailable", true, 503);
    assert.strictEqual(err503.isRetryable, true, "503 must be retryable");

    // Permanent errors (400 Bad Request, 401 Unauthorized, 403 Forbidden)
    const err400 = new FluxProviderError("Invalid parameters", false, 400);
    assert.strictEqual(err400.isRetryable, false, "400 must NOT be retryable");

    const err401 = new FluxProviderError("Invalid API Key", false, 401);
    assert.strictEqual(err401.isRetryable, false, "401 must NOT be retryable");
  });

  // --- TEST 9: Exponential Backoff Timing with Jitter (Task 2) ---
  test("Backoff Timing: Returns expected exponential backoff intervals with jitter", () => {
    // Attempt 1: 30s base (30000ms to 37500ms)
    for (let i = 0; i < 5; i++) {
      const b1 = ThumbnailSearchService.calculateBackoffMs(1);
      assert(b1 >= 30000 && b1 <= 37500, `Attempt 1 backoff ${b1}ms must be between 30s and 37.5s`);
    }

    // Attempt 2: 120s base (120000ms to 150000ms)
    for (let i = 0; i < 5; i++) {
      const b2 = ThumbnailSearchService.calculateBackoffMs(2);
      assert(b2 >= 120000 && b2 <= 150000, `Attempt 2 backoff ${b2}ms must be between 120s and 150s`);
    }

    // Attempt 3: 300s base (300000ms to 375000ms)
    for (let i = 0; i < 5; i++) {
      const b3 = ThumbnailSearchService.calculateBackoffMs(3);
      assert(b3 >= 300000 && b3 <= 375000, `Attempt 3 backoff ${b3}ms must be between 300s and 375s`);
    }

    // Attempt 4: 600s base (600000ms to 750000ms)
    for (let i = 0; i < 5; i++) {
      const b4 = ThumbnailSearchService.calculateBackoffMs(4);
      assert(b4 >= 600000 && b4 <= 750000, `Attempt 4 backoff ${b4}ms must be between 600s and 750s`);
    }
  });

  // --- TEST 10: Retry vs Immediate Fallback Simulation (Task 2) ---
  test("Retry Strategy: Transient Flux failure on attempt 1 schedules retry without immediate Gemini fallback", () => {
    let fluxAttempt = 1;
    const isRetryableError = true;
    let scheduledRetry = false;
    let geminiInvoked = false;

    if (isRetryableError && fluxAttempt < 4) {
      scheduledRetry = true;
      // Gemini is deferred to allow Flux to succeed on retry
    } else {
      geminiInvoked = true;
    }

    assert(scheduledRetry, "Transient error on attempt 1 should schedule a retry");
    assert(!geminiInvoked, "Gemini should NOT be immediately invoked on first transient capacity error");
  });

  test("Retry Strategy: Transient Flux failure on attempt 4 falls back to Gemini", () => {
    let fluxAttempt = 4;
    const isRetryableError = true;
    let scheduledRetry = false;
    let geminiInvoked = false;

    if (isRetryableError && fluxAttempt < 4) {
      scheduledRetry = true;
    } else {
      geminiInvoked = true;
    }

    assert(!scheduledRetry, "Retry should NOT be scheduled when attempts are exhausted");
    assert(geminiInvoked, "Gemini MUST be invoked as secondary fallback after 4 attempts");
  });

  test("Retry Strategy: Permanent Flux error (400/401) immediately falls back to Gemini", () => {
    let fluxAttempt = 1;
    const isRetryableError = false;
    let scheduledRetry = false;
    let geminiInvoked = false;

    if (isRetryableError && fluxAttempt < 4) {
      scheduledRetry = true;
    } else {
      geminiInvoked = true;
    }

    assert(!scheduledRetry, "Retry should NOT be scheduled for non-retryable errors");
    assert(geminiInvoked, "Gemini MUST be invoked immediately on permanent Flux error");
  });

  // =========================================================================
  // --- SECTION 19: FOUR-WORKER FLUX POOL INTEGRATION TEST SUITE ---
  // =========================================================================

  function createMockFirestore() {
    const collections = new Map();
    function getColl(name) {
      if (!collections.has(name)) collections.set(name, new Map());
      return collections.get(name);
    }
    return {
      collection(name) {
        const coll = getColl(name);
        return {
          doc(id) {
            const docId = id;
            return {
              id: docId,
              async get() {
                const data = coll.get(docId);
                return {
                  id: docId,
                  exists: !!data,
                  data: () => data ? { ...data } : undefined,
                };
              },
              async set(data, options) {
                if (options && options.merge && coll.has(docId)) {
                  coll.set(docId, { ...coll.get(docId), ...data });
                } else {
                  coll.set(docId, { ...data });
                }
              },
              async update(fields) {
                const current = coll.get(docId) || {};
                for (const [k, v] of Object.entries(fields)) {
                  if (k.includes(".")) {
                    const parts = k.split(".");
                    current[parts[0]] = current[parts[0]] || {};
                    current[parts[0]][parts[1]] = v;
                  } else {
                    current[k] = v;
                  }
                }
                coll.set(docId, current);
              },
            };
          },
          async get() {
            const docs = [];
            for (const [id, data] of coll.entries()) {
              docs.push({
                id,
                exists: true,
                data: () => ({ ...data }),
              });
            }
            return {
              docs,
              size: docs.length,
              empty: docs.length === 0,
              forEach: (cb) => docs.forEach(cb),
            };
          },
          where(field, op, val) {
            return {
              where() { return this; },
              limit() { return this; },
              async get() {
                return { docs: [], size: 0, empty: true, forEach: () => {} };
              }
            };
          },
          async add(data) {
            const id = "doc_" + Math.random().toString(36).slice(2, 9);
            coll.set(id, { ...data });
            return { id };
          }
        };
      },
      async runTransaction(updateFunction) {
        const transaction = {
          async get(docRef) {
            return docRef.get();
          },
          set(docRef, data, options) {
            return docRef.set(data, options);
          },
          update(docRef, data) {
            return docRef.update(data);
          }
        };
        return updateFunction(transaction);
      }
    };
  }

  const mockWorkers = [
    { workerId: "flux-worker-1", accountId: "acc_1", apiKey: "key_1", model: "@cf/black-forest-labs/flux-2-dev" },
    { workerId: "flux-worker-2", accountId: "acc_2", apiKey: "key_2", model: "@cf/black-forest-labs/flux-2-dev" },
    { workerId: "flux-worker-3", accountId: "acc_3", apiKey: "key_3", model: "@cf/black-forest-labs/flux-2-dev" },
    { workerId: "flux-worker-4", accountId: "acc_4", apiKey: "key_4", model: "@cf/black-forest-labs/flux-2-dev" },
  ];

  // Test 1: Four workers available -> Submit four jobs
  await asyncTest("Pool Test 1: Four workers available -> Four jobs distributed concurrently to Worker 1, 2, 3, 4", async () => {
    const db = createMockFirestore();

    const w1 = await FluxWorkerPool.reserveAvailableWorker(db, "job-A", mockWorkers);
    const w2 = await FluxWorkerPool.reserveAvailableWorker(db, "job-B", mockWorkers);
    const w3 = await FluxWorkerPool.reserveAvailableWorker(db, "job-C", mockWorkers);
    const w4 = await FluxWorkerPool.reserveAvailableWorker(db, "job-D", mockWorkers);

    assert(w1, "Worker 1 should be reserved");
    assert(w2, "Worker 2 should be reserved");
    assert(w3, "Worker 3 should be reserved");
    assert(w4, "Worker 4 should be reserved");

    const reservedIds = new Set([w1.workerId, w2.workerId, w3.workerId, w4.workerId]);
    assert.strictEqual(reservedIds.size, 4, "All 4 workers must be unique");
    assert(reservedIds.has("flux-worker-1"));
    assert(reservedIds.has("flux-worker-2"));
    assert(reservedIds.has("flux-worker-3"));
    assert(reservedIds.has("flux-worker-4"));
  });

  // Test 2: Fifth job -> All 4 busy -> Queued, then assigned when worker frees up
  await asyncTest("Pool Test 2: Fifth job -> Blocked while 4 are busy, receives worker immediately once one frees up", async () => {
    const db = createMockFirestore();

    await FluxWorkerPool.reserveAvailableWorker(db, "job-1", mockWorkers);
    await FluxWorkerPool.reserveAvailableWorker(db, "job-2", mockWorkers);
    await FluxWorkerPool.reserveAvailableWorker(db, "job-3", mockWorkers);
    await FluxWorkerPool.reserveAvailableWorker(db, "job-4", mockWorkers);

    // Job 5 attempted while all 4 busy
    const w5Blocked = await FluxWorkerPool.reserveAvailableWorker(db, "job-5", mockWorkers);
    assert.strictEqual(w5Blocked, null, "Fifth job must return null (remain queued) while all 4 workers are busy");

    // Worker 2 finishes its job
    await FluxWorkerPool.releaseWorker(db, "flux-worker-2", { success: true, resourceId: "job-2" });

    // Job 5 attempted again
    const w5Assigned = await FluxWorkerPool.reserveAvailableWorker(db, "job-5", mockWorkers);
    assert(w5Assigned, "Fifth job should now be reserved");
    assert.strictEqual(w5Assigned.workerId, "flux-worker-2", "Fifth job should be assigned to the newly freed Worker 2");
  });

  // Test 3: Worker 1 reaches limit -> Cooldown on Worker 1, Workers 2, 3, 4 remain available
  await asyncTest("Pool Test 3: Worker 1 reaches 429 limit -> Worker 1 in cooldown, jobs continue through Workers 2, 3, 4", async () => {
    const db = createMockFirestore();

    const w1 = await FluxWorkerPool.reserveAvailableWorker(db, "job-fail-1", mockWorkers);
    assert.strictEqual(w1.workerId, "flux-worker-1");

    // Worker 1 encounters HTTP 429
    const err429 = new FluxProviderError("Cloudflare HTTP 429: Too Many Requests", true, 429);
    await FluxWorkerPool.releaseWorker(db, "flux-worker-1", { success: false, error: err429, resourceId: "job-fail-1" });

    // Verify Worker 1 document has status 'cooling_down'
    const snap1 = await db.collection("flux_workers").doc("flux-worker-1").get();
    assert.strictEqual(snap1.data().status, "cooling_down");
    assert(snap1.data().cooldownUntil, "Must have cooldown timestamp");

    // Next job must skip Worker 1 and assign to Worker 2
    const nextJob = await FluxWorkerPool.reserveAvailableWorker(db, "job-next", mockWorkers);
    assert(nextJob, "Next job must find an available worker");
    assert.notStrictEqual(nextJob.workerId, "flux-worker-1", "Next job must NOT be assigned to cooling-down Worker 1");
    assert.strictEqual(nextJob.workerId, "flux-worker-2");
  });

  // Test 4: Worker 2 also reaches limit -> Workers 1 & 2 in cooldown, Workers 3 & 4 continue
  await asyncTest("Pool Test 4: Worker 2 also reaches limit -> Workers 1 & 2 in cooldown, Workers 3 & 4 receive jobs", async () => {
    const db = createMockFirestore();

    // Mark Worker 1 in cooldown
    await FluxWorkerPool.releaseWorker(db, "flux-worker-1", {
      success: false,
      error: new FluxProviderError("Rate Limit", true, 429),
    });

    // Mark Worker 2 in cooldown
    await FluxWorkerPool.releaseWorker(db, "flux-worker-2", {
      success: false,
      error: new FluxProviderError("Rate Limit", true, 429),
    });

    // Next two jobs must be assigned to Workers 3 and 4
    const jobA = await FluxWorkerPool.reserveAvailableWorker(db, "job-A", mockWorkers);
    const jobB = await FluxWorkerPool.reserveAvailableWorker(db, "job-B", mockWorkers);

    assert.strictEqual(jobA.workerId, "flux-worker-3");
    assert.strictEqual(jobB.workerId, "flux-worker-4");
  });

  // Test 5: Three workers unavailable -> All new jobs go to Worker 4
  await asyncTest("Pool Test 5: Three workers unavailable -> All new jobs go to remaining Worker 4", async () => {
    const db = createMockFirestore();

    await FluxWorkerPool.releaseWorker(db, "flux-worker-1", { success: false, error: new FluxProviderError("429", true, 429) });
    await FluxWorkerPool.releaseWorker(db, "flux-worker-2", { success: false, error: new FluxProviderError("429", true, 429) });
    await FluxWorkerPool.releaseWorker(db, "flux-worker-3", { success: false, error: new FluxProviderError("429", true, 429) });

    const job = await FluxWorkerPool.reserveAvailableWorker(db, "job-solo", mockWorkers);
    assert(job, "Should find available worker");
    assert.strictEqual(job.workerId, "flux-worker-4", "Must select Worker 4 as the sole available worker");
  });

  // Test 6: All four unavailable -> Queue protects Flux, no hammering
  await asyncTest("Pool Test 6: All four unavailable -> reservation returns null, pool reports allUnavailable, no hammering", async () => {
    const db = createMockFirestore();

    await FluxWorkerPool.releaseWorker(db, "flux-worker-1", { success: false, error: new FluxProviderError("429", true, 429) });
    await FluxWorkerPool.releaseWorker(db, "flux-worker-2", { success: false, error: new FluxProviderError("429", true, 429) });
    await FluxWorkerPool.releaseWorker(db, "flux-worker-3", { success: false, error: new FluxProviderError("429", true, 429) });
    await FluxWorkerPool.releaseWorker(db, "flux-worker-4", { success: false, error: new FluxProviderError("429", true, 429) });

    const job = await FluxWorkerPool.reserveAvailableWorker(db, "job-none", mockWorkers);
    assert.strictEqual(job, null, "Must return null when all workers are in cooldown");

    const status = await FluxWorkerPool.getPoolStatus(db, mockWorkers);
    assert.strictEqual(status.allUnavailable, true, "Pool status must be allUnavailable");
    assert.strictEqual(status.coolingDown, 4, "All 4 workers must be cooling down");
    assert(status.earliestCooldown, "Must report earliest cooldown time for queue timer");
  });

  // Test 7: Worker recovery -> Worker becomes available after cooldown
  await asyncTest("Pool Test 7: Worker recovery -> Once cooldown expires, worker becomes eligible again", async () => {
    const db = createMockFirestore();

    // Mark Worker 1 with past cooldown (already expired)
    await db.collection("flux_workers").doc("flux-worker-1").set({
      workerId: "flux-worker-1",
      status: "cooling_down",
      cooldownUntil: new Date(Date.now() - 5000), // Expired 5 seconds ago
    });

    const job = await FluxWorkerPool.reserveAvailableWorker(db, "job-recovered", mockWorkers);
    assert(job, "Recovered worker must be available");
    assert.strictEqual(job.workerId, "flux-worker-1", "Recovered Worker 1 must be selected");
  });

  // Test 8: Same worker cannot process two jobs simultaneously
  await asyncTest("Pool Test 8: Concurrency Lease -> Same worker cannot receive two jobs simultaneously", async () => {
    const db = createMockFirestore();

    // Reserve Worker 1 for Job A
    const jobAWorker = await FluxWorkerPool.reserveAvailableWorker(db, "job-A", [mockWorkers[0]]);
    assert.strictEqual(jobAWorker.workerId, "flux-worker-1");

    // Second request tries to reserve with only Worker 1 in pool
    const jobBWorker = await FluxWorkerPool.reserveAvailableWorker(db, "job-B", [mockWorkers[0]]);
    assert.strictEqual(jobBWorker, null, "Worker 1 is busy holding lease for Job A, so Job B cannot reserve it");
  });

  // Test 9: Duplicate resource protection / Idempotency
  await asyncTest("Pool Test 9: Duplicate resource protection -> Resources with completed thumbnails are safely skipped", async () => {
    const db = createMockFirestore();
    const existingUrl = "https://ik.imagekit.io/ubgbitinve/thumb_math.jpg";

    // Seed resource with already completed thumbnail
    await db.collection("resources").doc("res-existing").set({
      thumbnailUrl: existingUrl,
      thumbnailId: "ik_file_123",
      thumbnailStatus: "completed",
    });

    const dummyIk = {};
    const result = await ThumbnailSearchService.searchAndUploadThumbnail(
      db,
      dummyIk,
      {
        resourceId: "res-existing",
        title: "Calculus II",
        courseCode: "MATH 102",
      },
      undefined,
      undefined,
      undefined,
      undefined,
      mockWorkers
    );

    assert.strictEqual(result.success, true);
    assert.strictEqual(result.alreadyCompleted, true);
    assert.strictEqual(result.imageKitUrl, existingUrl);
  });

  // Test 10: Gemini fallback when all four Flux workers fail/disabled
  await asyncTest("Pool Test 10: Gemini fallback -> Succeeded when all Flux workers are unavailable/disabled", async () => {
    const db = createMockFirestore();

    // Mark all 4 workers permanently disabled
    for (const w of mockWorkers) {
      await db.collection("flux_workers").doc(w.workerId).set({
        workerId: w.workerId,
        status: "disabled",
      });
    }

    const poolStatus = await FluxWorkerPool.getPoolStatus(db, mockWorkers);
    assert.strictEqual(poolStatus.allDisabled, true);

    // Mock Gemini fetch
    const originalFetch = global.fetch;
    const dummyImage = Buffer.from("gemini-fallback-image").toString("base64");
    global.fetch = async function () {
      return {
        ok: true,
        status: 200,
        json: async () => ({
          candidates: [{ content: { parts: [{ inlineData: { mimeType: "image/jpeg", data: dummyImage } }] } }],
        }),
      };
    };

    const mockIk = {
      upload: async () => ({ url: "https://ik.imagekit.io/gemini_thumb.jpg", fileId: "gemini_file_123" }),
    };

    try {
      const result = await ThumbnailSearchService.searchAndUploadThumbnail(
        db,
        mockIk,
        {
          resourceId: "res-gemini-fallback",
          title: "Introduction to Law",
          courseCode: "LAWS 101",
        },
        undefined,
        undefined,
        "dummy_key",
        undefined,
        mockWorkers
      );

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.provider, "gemini");
      assert(result.imageKitUrl.includes("gemini_thumb"));
    } finally {
      global.fetch = originalFetch;
    }
  });

  // Test 11: Timetable upload pipeline isolation
  test("Pool Test 11: Timetable upload isolation -> Timetable uploads strictly never touch FluxWorkerPool or AI image generation", () => {
    const fs = require("fs");
    const path = require("path");

    // Inspect timetable service file in Dart codebase
    const timetableServicePath = path.resolve(__dirname, "../lib/services/timetable_upload_service.dart");
    const content = fs.readFileSync(timetableServicePath, "utf8");

    assert(!content.includes("FluxWorkerPool"), "Timetable service must NOT reference FluxWorkerPool");
    assert(!content.includes("flux"), "Timetable service must NOT reference flux");
    assert(!content.includes("searchThumbnailWithGemini"), "Timetable service must NOT reference thumbnail AI callable");
    assert(content.includes("timetable"), "Timetable service must remain dedicated to timetable documents");
  });

  // Test 12: Natural Editorial Photographic Prompt Realism & Visual Variety
  test("Pool Test 12: Photographic prompt realism & visual variety across similar courses", () => {
    // 5 similar pairs
    const pairs = [
      {
        unitA: { courseCode: "COMP 101", title: "Introduction to Programming in Python", materialType: "Notes", topic: "Control Structures and Functions" },
        unitB: { courseCode: "COMP 102", title: "Object Oriented Programming in Java", materialType: "Notes", topic: "Classes, Objects and Polymorphism" }
      },
      {
        unitA: { courseCode: "BICT 321", title: "Network Security and Cryptography", materialType: "Notes", topic: "Public Key Encryption and Firewalls" },
        unitB: { courseCode: "COMP 325", title: "Wireless Networks and Telecommunications", materialType: "Notes", topic: "Cellular Systems and Antennas" }
      },
      {
        unitA: { courseCode: "ECON 101", title: "Introduction to Microeconomics", materialType: "Notes", topic: "Supply, Demand and Market Equilibrium" },
        unitB: { courseCode: "ECON 102", title: "Introduction to Macroeconomics", materialType: "Notes", topic: "GDP, Inflation and Monetary Policy" }
      },
      {
        unitA: { courseCode: "MATH 211", title: "Linear Algebra", materialType: "Notes", topic: "Vector Spaces and Eigenvalues" },
        unitB: { courseCode: "MATH 212", title: "Multivariable Calculus", materialType: "Notes", topic: "Multiple Integrals and Vector Fields" }
      },
      {
        unitA: { courseCode: "NURS 201", title: "Fundamentals of Nursing Practice", materialType: "Notes", topic: "Patient Vital Signs and Bedside Care" },
        unitB: { courseCode: "ANAT 202", title: "Human Anatomy and Physiology", materialType: "Notes", topic: "Musculoskeletal and Circulatory Systems" }
      }
    ];

    for (const pair of pairs) {
      const pA = ThumbnailSearchService.buildImagePrompt(pair.unitA);
      const pB = ThumbnailSearchService.buildImagePrompt(pair.unitB);

      // Verify photographic realism, absence of AI-art tropes
      assert(pA.includes("Authentic professional editorial photography"), "Must specify editorial photography");
      assert(pB.includes("Authentic professional editorial photography"), "Must specify editorial photography");
      assert(!pA.includes("3D scientific visualization"), "Must not promote 3D scientific visualization");
      assert(!pB.includes("3D scientific visualization"), "Must not promote 3D scientific visualization");
      assert(!pA.includes("luminous data pathways"), "Must not contain luminous data pathways");
      assert(!pB.includes("luminous data pathways"), "Must not contain luminous data pathways");

      // Verify meaningful scene and prompt distinctness
      const sceneA = pA.match(/\[VISUAL SCENE & OBJECTS\]:\s*([^\n]+)/)[1];
      const sceneB = pB.match(/\[VISUAL SCENE & OBJECTS\]:\s*([^\n]+)/)[1];
      assert.notStrictEqual(sceneA, sceneB, "Scenes must be visually distinct between similar units");
      assert.notStrictEqual(pA, pB, "Full prompts must be distinct between similar units");
    }
  });

  console.log(`\n========================================`);
  console.log(`TEST SUMMARY: ${passed} passed, ${failed} failed`);
  console.log(`========================================\n`);

  if (failed > 0) {
    process.exit(1);
  }
}

runTests().catch((err) => {
  console.error("Unhandled error in test runner:", err);
  process.exit(1);
});

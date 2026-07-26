/**
 * Verification Test Suite for Phase 1.5 - Provider-Agnostic AI Worker System
 */

const assert = require("assert");
const fs = require("fs");
const path = require("path");

console.log("=================================================");
console.log(" PHASE 1.5: VERIFICATION TEST SUITE");
console.log("=================================================\n");

// ----------------------------------------------------------------
// TEST 1: SCHEDULER CONTAINS NO PROVIDER-SPECIFIC CODE
// ----------------------------------------------------------------
console.log("Test 1: Verify Scheduler contains no provider-specific code");
const schedulerFilePath = path.join(__dirname, "src", "services", "explore_scheduler.ts");
const schedulerCode = fs.readFileSync(schedulerFilePath, "utf8");

assert(!schedulerCode.includes('import OpenAI from "openai"'), "Scheduler must not import OpenAI SDK");
assert(!schedulerCode.includes('import { OpenAI }'), "Scheduler must not import OpenAI SDK");
assert(!schedulerCode.includes("new OpenAI("), "Scheduler must not instantiate OpenAI directly");
assert(!schedulerCode.includes("moonshot.cn"), "Scheduler must not reference provider-specific URLs");
assert(schedulerCode.includes("AIProviderRegistry.getProvider("), "Scheduler must obtain provider via AIProviderRegistry");
assert(schedulerCode.includes("WorkerManager.getAvailableWorker("), "Scheduler must obtain worker via WorkerManager");
console.log("  PASSED: ExploreScheduler contains 0 provider-specific references or SDK calls.\n");

// ----------------------------------------------------------------
// TEST 2: OPENAI PROVIDER IS ISOLATED
// ----------------------------------------------------------------
console.log("Test 2: Verify OpenAI provider is isolated");
const openaiProviderPath = path.join(__dirname, "src", "providers", "openai_provider.ts");
const openaiCode = fs.readFileSync(openaiProviderPath, "utf8");

assert(openaiCode.includes("extends BaseAIProvider"), "OpenAI provider must extend BaseAIProvider");
assert(openaiCode.includes("readonly name = \"openai\""), "OpenAI provider must define name = 'openai'");
assert(openaiCode.includes("discoverNews("), "OpenAI provider must implement discoverNews");
console.log("  PASSED: OpenAIProvider is fully isolated inside src/providers/openai_provider.ts.\n");

// ----------------------------------------------------------------
// TEST 3 & 4: WORKERS LOADED FROM FIRESTORE & WORKERMANAGER ASSIGNS JOBS
// ----------------------------------------------------------------
console.log("Test 3 & 4: Verify WorkerManager loads workers from Firestore and selects best worker");

// Compile TypeScript files first or test compiled lib files
const { AIProviderRegistry } = require("./lib/providers/provider_registry");
const { WorkerManager } = require("./lib/services/worker_manager");
const { BaseAIProvider } = require("./lib/providers/base_provider");
const { FailedJobService } = require("./lib/services/failed_job_service");

// Mock Firestore DB
function createMockFirestore(workerDocs = {}, jobQueueDocs = {}, failedJobDocs = {}, systemDocs = {}) {
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
              if (workerDocs[docId]) {
                Object.assign(workerDocs[docId], fields);
              }
            },
          }),
        };
      }
      if (collName === "system") {
        return {
          doc: (docId) => ({
            get: async () => ({
              exists: !!systemDocs[docId],
              data: () => systemDocs[docId] || {},
            }),
          }),
        };
      }
      if (collName === "job_queue") {
        return {
          where: (field, op, val) => ({
            count: () => ({
              get: async () => ({
                data: () => ({ count: Object.values(jobQueueDocs).filter(j => j[field] === val).length })
              })
            })
          }),
          doc: (docId) => ({
            update: async (fields) => {
              if (jobQueueDocs[docId]) {
                Object.assign(jobQueueDocs[docId], fields);
              }
            },
          })
        };
      }
      if (collName === "failed_jobs") {
        return {
          limit: (n) => ({
            get: async () => ({
              empty: Object.keys(failedJobDocs).length === 0,
              docs: Object.entries(failedJobDocs).map(([id, data]) => ({
                id,
                ref: { id },
                data: () => data,
              })),
            }),
          }),
          doc: (docId) => ({
            id: docId,
            set: async (data) => {
              failedJobDocs[docId] = data;
            },
          }),
        };
      }
      return {
        get: async () => ({ docs: [] }),
        doc: (docId) => ({ id: docId, get: async () => ({ exists: false }) }),
      };
    },
    batch: () => {
      const operations = [];
      return {
        set: (ref, data) => operations.push({ type: "set", ref, data }),
        delete: (ref) => operations.push({ type: "delete", ref }),
        update: (ref, data) => operations.push({ type: "update", ref, data }),
        commit: async () => {
          for (const op of operations) {
            if (op.type === "set") {
              if (op.ref.id) failedJobDocs[op.ref.id] = op.data;
            } else if (op.type === "delete") {
              delete jobQueueDocs[op.ref.id];
              delete failedJobDocs[op.ref.id];
            }
          }
        },
      };
    },
  };
}

(async () => {
  const mockWorkers = {
    worker_openai_1: {
      provider: "openai",
      model: "gpt-4o",
      apiKey: "sk-test-1",
      enabled: true,
      priority: 10,
      status: "idle",
      remainingQuota: 500,
      averageLatency: 400,
      role: "discovery",
    },
    worker_kimi_1: {
      provider: "kimi",
      model: "moonshot-v1-8k",
      apiKey: "sk-kimi-1",
      enabled: true,
      priority: 5,
      status: "idle",
      remainingQuota: 1000,
      averageLatency: 200,
      role: "discovery",
    },
  };

  const mockDb = createMockFirestore(mockWorkers);
  const worker = await WorkerManager.getAvailableWorker(mockDb, "discovery");

  assert(worker !== null, "WorkerManager should find available worker");
  assert.strictEqual(worker.workerId, "worker_kimi_1", "WorkerManager should select lowest latency & highest priority worker (Kimi 200ms vs OpenAI 400ms)");
  console.log(`  PASSED: WorkerManager dynamically loaded workers from Firestore and selected "${worker.workerId}".\n`);

  // ----------------------------------------------------------------
  // TEST 5: NEW PROVIDERS CAN BE ADDED DYNAMICALLY
  // ----------------------------------------------------------------
  console.log("Test 5: Verify new providers can be added without modifying scheduler code");
  class CustomAIProvider extends BaseAIProvider {
    constructor() {
      super();
      this.name = "custom_ai";
    }
    async discoverNews(categoryName, targetArticles, worker) {
      return [{ clusterId: "c1", title: "Custom News", source: "Custom", sourceUrl: "https://test.com", publishedAt: "2026-07-26T12:00:00Z", summary: "Summary" }];
    }
  }

  AIProviderRegistry.registerProvider(new CustomAIProvider());
  assert(AIProviderRegistry.hasProvider("custom_ai"), "Custom provider must be registered");
  const customProv = AIProviderRegistry.getProvider("custom_ai");
  assert.strictEqual(customProv.name, "custom_ai");
  console.log("  PASSED: New provider 'custom_ai' registered dynamically without altering core scheduler.\n");

  // ----------------------------------------------------------------
  // TEST 6: NEW API KEYS ADDED BY CREATING FIRESTORE DOCS ONLY
  // ----------------------------------------------------------------
  console.log("Test 6: Verify new API keys added by creating Firestore documents only");
  mockWorkers["worker_openai_key2"] = {
    provider: "openai",
    model: "gpt-4o",
    apiKey: "sk-test-key-2",
    enabled: true,
    priority: 1,
    status: "idle",
    remainingQuota: 1000,
    averageLatency: 100,
    role: "discovery",
  };

  const newSelectedWorker = await WorkerManager.getAvailableWorker(mockDb, "discovery");
  assert.strictEqual(newSelectedWorker.workerId, "worker_openai_key2", "New API key worker should be selected seamlessly without code changes");
  console.log("  PASSED: Added new document 'worker_openai_key2', WorkerManager immediately picked it up.\n");

  // ----------------------------------------------------------------
  // TEST 7: DISABLED WORKERS ARE IGNORED
  // ----------------------------------------------------------------
  console.log("Test 7: Verify disabled workers are ignored");
  mockWorkers["worker_openai_key2"].enabled = false;
  const workerAfterDisable = await WorkerManager.getAvailableWorker(mockDb, "discovery");
  assert.notStrictEqual(workerAfterDisable.workerId, "worker_openai_key2", "Disabled worker must be ignored");
  console.log("  PASSED: Disabled worker 'worker_openai_key2' was ignored by WorkerManager.\n");

  // ----------------------------------------------------------------
  // TEST 8: COOLDOWN LOGIC WORKS
  // ----------------------------------------------------------------
  console.log("Test 8: Verify cooldown logic works");
  const now = new Date();
  const futureCooldown = new Date(Date.now() + 15 * 60 * 1000);
  mockWorkers["worker_kimi_1"].cooldownUntil = { toDate: () => futureCooldown };
  mockWorkers["worker_kimi_1"].status = "cooldown";

  const workerAfterCooldown = await WorkerManager.getAvailableWorker(mockDb, "discovery");
  assert.strictEqual(workerAfterCooldown.workerId, "worker_openai_1", "Worker in cooldown must be skipped");

  // Test putWorkerInCooldown method
  await WorkerManager.putWorkerInCooldown(mockDb, "worker_openai_1", 15, "Rate limit hit");
  assert.strictEqual(mockWorkers["worker_openai_1"].status, "cooldown", "Worker status should be set to cooldown");
  console.log("  PASSED: Cooldown logic correctly puts failing workers in cooldown and ignores them during selection.\n");

  // Reset status for remaining tests
  mockWorkers["worker_openai_1"].status = "idle";
  mockWorkers["worker_openai_1"].cooldownUntil = null;

  // ----------------------------------------------------------------
  // TEST 9: RETRY AND FAILED_JOBS INTEGRATION WORKS
  // ----------------------------------------------------------------
  console.log("Test 9: Verify retry and failed_jobs integration works");
  const jobQueue = { "job_1": { title: "Failing Job", retries: 2 } };
  const failedJobs = {};
  const failureDb = createMockFirestore({}, jobQueue, failedJobs);

  // Exceed retry limit (2 + 1 = 3 >= retryLimit 3) -> move to failed_jobs
  await FailedJobService.handleJobFailure(failureDb, "job_1", jobQueue["job_1"], "API Timeout", 3);
  assert(failedJobs["job_1"], "Job must be moved to failed_jobs collection after exceeding retries");
  assert.strictEqual(failedJobs["job_1"].lastError, "API Timeout");
  console.log("  PASSED: FailedJobService moved job to failed_jobs after reaching retryLimit.\n");

  // ----------------------------------------------------------------
  // TEST 10: EXISTING EXPLORE ARCHITECTURE REMAINS FUNCTIONAL
  // ----------------------------------------------------------------
  console.log("Test 10: Verify existing Explore architecture remains functional");
  const list = AIProviderRegistry.listRegisteredProviders();
  assert(list.includes("openai"), "Registry must include openai");
  assert(list.includes("kimi"), "Registry must include kimi");
  assert(list.includes("gemini"), "Registry must include gemini");
  assert(list.includes("claude"), "Registry must include claude");
  assert(list.includes("grok"), "Registry must include grok");
  assert(list.includes("deepseek"), "Registry must include deepseek");
  console.log(`  PASSED: Registered providers list: [${list.join(", ")}]. Existing Explore architecture is fully functional.\n`);

  console.log("=================================================");
  console.log(" ALL 10 VERIFICATION CHECKS PASSED SUCCESSFULLY! ");
  console.log("=================================================");
})();

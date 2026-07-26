/**
 * Comprehensive Verification Test Suite for Provider-Agnostic Distributed AI Worker Architecture
 */

const assert = require("assert");
const fs = require("fs");
const path = require("path");

console.log("=================================================");
console.log(" DISTRIBUTED WORKER SYSTEM VERIFICATION SUITE ");
console.log("=================================================\n");

// Compile TypeScript files first or test compiled lib files
const { AIProviderRegistry, ProviderRegistry } = require("./lib/providers/provider_registry");
const { WorkerManager } = require("./lib/services/worker_manager");
const { BaseAIProvider } = require("./lib/providers/base_provider");
const { WriterPoolService } = require("./lib/services/writer_pool_service");
const { WorkerHealthMonitor } = require("./lib/services/worker_health_monitor");

// Mock Firestore DB builder
function createMockFirestore(workerDocs = {}, jobQueueDocs = {}, storyClusterDocs = {}, failedJobDocs = {}) {
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
      if (collName === "job_queue") {
        return {
          where: (field, op, val) => ({
            limit: (num) => ({
              get: async () => ({
                empty: Object.values(jobQueueDocs).filter(j => j[field] === val).length === 0,
                docs: Object.entries(jobQueueDocs)
                  .filter(([id, j]) => j[field] === val)
                  .slice(0, num)
                  .map(([id, data]) => ({
                    id,
                    data: () => data,
                  })),
              }),
            }),
            count: () => ({
              get: async () => ({
                data: () => ({ count: Object.values(jobQueueDocs).filter(j => j[field] === val).length })
              })
            })
          }),
          doc: (docId) => ({
            id: docId,
            get: async () => ({
              exists: !!jobQueueDocs[docId],
              data: () => jobQueueDocs[docId],
            }),
            update: async (fields) => {
              if (jobQueueDocs[docId]) {
                Object.assign(jobQueueDocs[docId], fields);
              }
            },
          }),
          add: async (item) => {
            const id = "job_" + Math.random().toString(36).substr(2, 6);
            jobQueueDocs[id] = item;
            return { id };
          }
        };
      }
      if (collName === "storyClusters") {
        return {
          doc: (docId) => ({
            set: async (item) => {
              storyClusterDocs[docId] = item;
            },
            update: async (fields) => {
              if (storyClusterDocs[docId]) Object.assign(storyClusterDocs[docId], fields);
            }
          })
        };
      }
      if (collName === "failed_jobs") {
        return {
          doc: (docId) => ({
            id: docId,
            set: async (data) => {
              failedJobDocs[docId] = data;
            },
          }),
        };
      }
      if (collName === "system" || collName === "categories") {
        return {
          get: async () => ({ docs: [] }),
          doc: () => ({ get: async () => ({ exists: false }) })
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
    batch: () => {
      const ops = [];
      return {
        update: (ref, data) => ops.push({ type: "update", ref, data }),
        commit: async () => {
          for (const op of ops) {
            await op.ref.update(op.data);
          }
        }
      };
    }
  };
}

(async () => {
  // ----------------------------------------------------------------
  // TEST 1: WORKER ASSIGNMENT ALGORITHM BY ROLE
  // ----------------------------------------------------------------
  console.log("Test 1: Verify Worker Assignment Algorithm filters by Role (DISCOVERY vs WRITER vs IMAGE)");
  const mockWorkers = {
    worker_openai_01: {
      provider: "openai",
      model: "gpt-4o",
      apiKey: "sk-disc-1",
      enabled: true,
      busy: false,
      status: "idle",
      role: "DISCOVERY",
      averageLatency: 300,
      requestsToday: 10,
      requestsThisMinute: 1,
      dailyLimit: 1000,
      minuteLimit: 60,
    },
    worker_gemini_01: {
      provider: "gemini",
      model: "gemini-1.5-flash",
      apiKey: "sk-writer-1",
      enabled: true,
      busy: false,
      status: "idle",
      role: "WRITER",
      averageLatency: 200,
      requestsToday: 5,
      requestsThisMinute: 0,
      dailyLimit: 1000,
      minuteLimit: 60,
    },
    worker_claude_01: {
      provider: "claude",
      model: "claude-3-5-sonnet",
      apiKey: "sk-img-1",
      enabled: true,
      busy: false,
      status: "idle",
      role: "IMAGE",
      averageLatency: 150,
      requestsToday: 0,
      requestsThisMinute: 0,
      dailyLimit: 500,
      minuteLimit: 30,
    }
  };

  const db1 = createMockFirestore(mockWorkers);
  const discWorker = await WorkerManager.getAvailableWorker(db1, "DISCOVERY");
  assert.strictEqual(discWorker.workerId, "worker_openai_01", "Should pick worker with DISCOVERY role");

  const writerWorker = await WorkerManager.getAvailableWorker(db1, "WRITER");
  assert.strictEqual(writerWorker.workerId, "worker_gemini_01", "Should pick worker with WRITER role");

  const imgWorker = await WorkerManager.getAvailableWorker(db1, "IMAGE");
  assert.strictEqual(imgWorker.workerId, "worker_claude_01", "Should pick worker with IMAGE role");
  console.log("  PASSED: Worker assignment algorithm strictly respects role filters (DISCOVERY / WRITER / IMAGE).\n");

  // ----------------------------------------------------------------
  // TEST 2: DYNAMIC PROVIDER REGISTRY
  // ----------------------------------------------------------------
  console.log("Test 2: Verify ProviderRegistry resolves registered providers dynamically");
  assert(ProviderRegistry.hasProvider("openai"), "Registry must have openai");
  assert(ProviderRegistry.hasProvider("gemini"), "Registry must have gemini");
  assert(ProviderRegistry.hasProvider("kimi"), "Registry must have kimi");
  assert(ProviderRegistry.hasProvider("claude"), "Registry must have claude");
  assert(ProviderRegistry.hasProvider("grok"), "Registry must have grok");
  assert(ProviderRegistry.hasProvider("deepseek"), "Registry must have deepseek");
  console.log("  PASSED: ProviderRegistry dynamically resolves all registered provider instances.\n");

  // ----------------------------------------------------------------
  // TEST 3: LOAD BALANCING (LATENCY & LRU TIE-BREAKER)
  // ----------------------------------------------------------------
  console.log("Test 3: Verify Load Balancer chooses lowest average latency and least recently used worker");
  const loadBalWorkers = {
    w1: { provider: "openai", apiKey: "k1", enabled: true, busy: false, role: "WRITER", averageLatency: 400, minuteLimit: 60, dailyLimit: 1000, lastUsed: new Date("2026-07-26T10:00:00Z") },
    w2: { provider: "openai", apiKey: "k2", enabled: true, busy: false, role: "WRITER", averageLatency: 150, minuteLimit: 60, dailyLimit: 1000, lastUsed: new Date("2026-07-26T12:00:00Z") },
    w3: { provider: "openai", apiKey: "k3", enabled: true, busy: false, role: "WRITER", averageLatency: 150, minuteLimit: 60, dailyLimit: 1000, lastUsed: new Date("2026-07-26T08:00:00Z") },
  };

  const db3 = createMockFirestore(loadBalWorkers);
  const selectedLB = await WorkerManager.getAvailableWorker(db3, "WRITER");
  assert.strictEqual(selectedLB.workerId, "w3", "Should select w3 because 150ms latency equal to w2 but w3 was used earlier (08:00 vs 12:00)");
  console.log(`  PASSED: Load Balancer selected "${selectedLB.workerId}" (Lowest latency 150ms & oldest lastUsed timestamp).\n`);

  // ----------------------------------------------------------------
  // TEST 4: RATE LIMITER (MINUTE & DAILY LIMITS)
  // ----------------------------------------------------------------
  console.log("Test 4: Verify Rate Limiter ignores workers exceeding minuteLimit or dailyLimit");
  const rateLimitWorkers = {
    w_minute_exceeded: { provider: "openai", apiKey: "k1", enabled: true, busy: false, role: "DISCOVERY", averageLatency: 100, minuteLimit: 10, requestsThisMinute: 10, dailyLimit: 1000 },
    w_daily_exceeded: { provider: "openai", apiKey: "k2", enabled: true, busy: false, role: "DISCOVERY", averageLatency: 120, minuteLimit: 60, requestsToday: 1000, dailyLimit: 1000 },
    w_available: { provider: "openai", apiKey: "k3", enabled: true, busy: false, role: "DISCOVERY", averageLatency: 300, minuteLimit: 60, requestsThisMinute: 2, dailyLimit: 1000 },
  };

  const db4 = createMockFirestore(rateLimitWorkers);
  const selectedRL = await WorkerManager.getAvailableWorker(db4, "DISCOVERY");
  assert.strictEqual(selectedRL.workerId, "w_available", "Rate Limiter must bypass workers that reached minute/daily limits");
  console.log(`  PASSED: Rate Limiter ignored minute/daily capped workers and selected available "${selectedRL.workerId}".\n`);

  // ----------------------------------------------------------------
  // TEST 5: AUTOMATIC DISCOVERY OF NEW WORKERS FROM FIRESTORE
  // ----------------------------------------------------------------
  console.log("Test 5: Verify automatic discovery of new workers added to Firestore");
  rateLimitWorkers["worker_new_dynamically_added"] = {
    provider: "deepseek",
    apiKey: "sk-ds-new",
    enabled: true,
    busy: false,
    role: "DISCOVERY",
    averageLatency: 50,
    minuteLimit: 60,
    dailyLimit: 1000,
  };

  const selectedNew = await WorkerManager.getAvailableWorker(db4, "DISCOVERY");
  assert.strictEqual(selectedNew.workerId, "worker_new_dynamically_added", "Newly added Firestore worker document must be discovered automatically without code changes");
  console.log(`  PASSED: Added document 'worker_new_dynamically_added', WorkerManager immediately picked it up.\n`);

  // ----------------------------------------------------------------
  // TEST 6 & 7: FIRESTORE TRANSACTION LOCKING & QUEUE DISTRIBUTION
  // ----------------------------------------------------------------
  console.log("Test 6 & 7: Verify Firestore transaction locking prevents duplicate processing");
  const jobQueue = {
    job_101: { title: "Story 1", status: "queued", clusterId: "c1" },
    job_102: { title: "Story 2", status: "queued", clusterId: "c2" },
  };

  const writerPoolWorkers = {
    writer_1: { provider: "openai", apiKey: "k1", enabled: true, busy: false, role: "WRITER", averageLatency: 200 },
    writer_2: { provider: "openai", apiKey: "k2", enabled: true, busy: false, role: "WRITER", averageLatency: 250 },
  };

  const dbQueue = createMockFirestore(writerPoolWorkers, jobQueue);

  // Claim job 1 with writer_1
  const claimed1 = await WorkerManager.claimNextJobWithTransaction(dbQueue, { workerId: "writer_1", provider: "openai", role: "WRITER" });
  assert(claimed1 !== null, "Writer 1 should claim first job");
  assert.strictEqual(claimed1.jobId, "job_101");
  assert.strictEqual(jobQueue["job_101"].status, "processing");
  assert.strictEqual(jobQueue["job_101"].assignedWorker, "writer_1");

  // Claim job 2 with writer_2
  const claimed2 = await WorkerManager.claimNextJobWithTransaction(dbQueue, { workerId: "writer_2", provider: "openai", role: "WRITER" });
  assert(claimed2 !== null, "Writer 2 should claim second job");
  assert.strictEqual(claimed2.jobId, "job_102");
  assert.strictEqual(jobQueue["job_102"].status, "processing");
  assert.strictEqual(jobQueue["job_102"].assignedWorker, "writer_2");

  // Attempt third claim when queue is empty
  const claimed3 = await WorkerManager.claimNextJobWithTransaction(dbQueue, { workerId: "writer_1", provider: "openai", role: "WRITER" });
  assert.strictEqual(claimed3, null, "Third claim should return null as queue is empty");
  console.log("  PASSED: Transaction locking guaranteed atomic job assignment across multiple writer workers.\n");

  // ----------------------------------------------------------------
  // TEST 8: FAILOVER & RETRY MECHANISM
  // ----------------------------------------------------------------
  console.log("Test 8: Verify Failover puts failing worker in cooldown and returns job to queue");
  const failoverWorkers = {
    worker_failing: { provider: "openai", apiKey: "k1", enabled: true, busy: true, status: "busy", role: "WRITER", failureCount: 0 },
  };
  const failoverQueue = {
    job_fail: { title: "Failing Job", status: "processing", assignedWorker: "worker_failing", retries: 0 }
  };
  const dbFailover = createMockFirestore(failoverWorkers, failoverQueue);

  await WorkerManager.handleWorkerFailureAndFailover(dbFailover, "worker_failing", "job_fail", "Timeout 504", 3);

  assert.strictEqual(failoverWorkers["worker_failing"].status, "cooldown", "Failing worker must be placed in cooldown");
  assert.strictEqual(failoverQueue["job_fail"].status, "queued", "Job must be returned to status queued for retry");
  assert.strictEqual(failoverQueue["job_fail"].retries, 1, "Job retry count must be incremented");
  console.log("  PASSED: Failover placed failing worker in cooldown and returned job to queue.\n");

  // ----------------------------------------------------------------
  // TEST 9 & 10: SCALABILITY PROOF & HEALTH MONITOR
  // ----------------------------------------------------------------
  console.log("Test 9 & 10: Verify Scalability (200+ workers) & Health Monitor metrics computation");
  const scaleWorkers = {};
  for (let i = 1; i <= 200; i++) {
    scaleWorkers[`worker_auto_${i}`] = {
      provider: i % 2 === 0 ? "openai" : "gemini",
      apiKey: `key_${i}`,
      enabled: true,
      busy: false,
      status: "idle",
      role: i % 3 === 0 ? "DISCOVERY" : "WRITER",
      averageLatency: 100 + (i % 50),
      successCount: 90 + i,
      failureCount: 10,
    };
  }

  const dbScale = createMockFirestore(scaleWorkers);
  const healthRes = await WorkerHealthMonitor.checkAllWorkersHealth(dbScale);
  assert.strictEqual(healthRes.scanned, 200, "Health monitor should scan all 200 workers");
  assert(scaleWorkers["worker_auto_1"].lastHeartbeat !== undefined, "Health monitor must set lastHeartbeat");
  assert.strictEqual(typeof scaleWorkers["worker_auto_1"].successRate, "number", "Health monitor must calculate successRate");

  console.log(`  PASSED: Health Monitor successfully processed ${healthRes.scanned} workers, updating heartbeats and success rates.\n`);

  console.log("=================================================");
  console.log(" ALL 10 DISTRIBUTED WORKER VERIFICATION TESTS PASSED SUCCESSFULLY! ");
  console.log("=================================================");
})();

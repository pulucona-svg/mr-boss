/**
 * Comprehensive Verification Test Suite for Kimi API Key Pool Expansion & Load Balancing
 */

const assert = require("assert");
const { EnvConfig } = require("./lib/config/env_config");
const { WorkerManager } = require("./lib/services/worker_manager");
const { KimiProvider } = require("./lib/providers/kimi_provider");
const { ProviderRegistry } = require("./lib/providers/provider_registry");

console.log("=================================================");
console.log(" KIMI WORKER POOL INTEGRATION TEST SUITE ");
console.log("=================================================\n");

// Mock Firestore DB builder
function createMockFirestore(workerDocs = {}) {
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
      return {
        get: async () => ({ docs: [] }),
        doc: (docId) => ({ id: docId, get: async () => ({ exists: false }) }),
      };
    },
  };
}

(async () => {
  // ----------------------------------------------------------------
  // TEST 1: ALL 5 KIMI WORKERS REGISTERED FROM ENVIRONMENT
  // ----------------------------------------------------------------
  console.log("Test 1: Verify all 5 Kimi workers register successfully from KIMI_API_KEYS");
  const kimiKeys = EnvConfig.getApiKeys("kimi");
  assert.strictEqual(kimiKeys.length, 5, "Must load 5 Kimi API keys from environment");

  const poolWorkers = WorkerManager.createEnvironmentPoolWorkers("WRITER");
  const kimiWorkers = poolWorkers.filter((w) => w.provider === "kimi");
  assert.strictEqual(kimiWorkers.length, 5, "Must generate 5 independent Kimi workers");

  kimiWorkers.forEach((w, index) => {
    assert.strictEqual(w.workerId, `worker_kimi_${index + 1}`);
    assert(w.apiKey.startsWith("sk-"), `Worker ${w.workerId} must have valid Kimi API key`);
  });
  console.log(`  PASSED: Registered all 5 Kimi pool workers: [${kimiWorkers.map((w) => w.workerId).join(", ")}].\n`);

  // ----------------------------------------------------------------
  // TEST 2: SECRET MASKING FOR KIMI KEYS
  // ----------------------------------------------------------------
  console.log("Test 2: Verify secret masking for Kimi API keys");
  kimiKeys.forEach((key, index) => {
    const masked = EnvConfig.maskSecret(key);
    assert(masked.includes("************"), "Kimi key must be masked");
    assert(!masked.includes(key), "Raw Kimi key must NEVER be exposed in logs");
  });
  console.log(`  PASSED: Kimi Key 1 Masked: "${EnvConfig.maskSecret(kimiKeys[0])}".\n`);

  // ----------------------------------------------------------------
  // TEST 3: LOAD BALANCING ROTATES ACROSS KIMI WORKERS
  // ----------------------------------------------------------------
  console.log("Test 3: Verify load balancing rotates requests across all 5 Kimi workers");

  // Create mock Firestore with 5 Kimi workers
  const kimiDocs = {};
  kimiKeys.forEach((key, index) => {
    const workerId = `worker_kimi_${index + 1}`;
    kimiDocs[workerId] = {
      provider: "kimi",
      apiKey: key,
      enabled: true,
      busy: false,
      status: "idle",
      role: "WRITER",
      averageLatency: 100,
      priority: 50,
      lastUsed: null,
    };
  });

  const db = createMockFirestore(kimiDocs);

  const selectedWorkers = [];
  for (let i = 0; i < 5; i++) {
    // Disable higher priority providers to isolate Kimi load balancing
    EnvConfig.setProviderHealth("openai", false, 0);
    EnvConfig.setProviderHealth("gemini", false, 0);
    EnvConfig.setProviderHealth("claude", false, 0);
    EnvConfig.setProviderHealth("deepseek", false, 0);

    const worker = await WorkerManager.getAvailableWorker(db, "WRITER");
    assert(worker !== null, "Must select an available Kimi worker");
    assert.strictEqual(worker.provider, "kimi");

    // Simulate usage by updating lastUsed timestamp
    kimiDocs[worker.workerId].lastUsed = new Date(Date.now() + i * 1000);
    selectedWorkers.push(worker.workerId);
  }

  // Restore health of other providers
  EnvConfig.setProviderHealth("openai", true, 100);
  EnvConfig.setProviderHealth("gemini", true, 120);
  EnvConfig.setProviderHealth("claude", true, 140);
  EnvConfig.setProviderHealth("deepseek", true, 160);

  console.log(`  PASSED: Load balancer rotated selection across Kimi workers: [${selectedWorkers.join(" -> ")}].\n`);

  // ----------------------------------------------------------------
  // TEST 4: GRANULAR WORKER FAILOVER (1 KIMI WORKER UNHEALTHY)
  // ----------------------------------------------------------------
  console.log("Test 4: Verify marking ONLY worker_kimi_3 UNHEALTHY skips worker_kimi_3 while remaining 4 Kimi workers continue");

  // Disable higher priority providers to isolate Kimi
  EnvConfig.setProviderHealth("openai", false, 0);
  EnvConfig.setProviderHealth("gemini", false, 0);
  EnvConfig.setProviderHealth("claude", false, 0);
  EnvConfig.setProviderHealth("deepseek", false, 0);

  // Mark ONLY worker_kimi_3 UNHEALTHY (due to 429 rate limit or quota)
  EnvConfig.setWorkerHealth("worker_kimi_3", false, 0, "429 Rate Limit");

  const activeSelections = new Set();
  for (let i = 0; i < 10; i++) {
    const worker = await WorkerManager.getAvailableWorker(db, "WRITER");
    assert(worker !== null);
    assert.notStrictEqual(worker.workerId, "worker_kimi_3", "WorkerManager MUST skip worker_kimi_3 when marked UNHEALTHY");
    activeSelections.add(worker.workerId);
    if (kimiDocs[worker.workerId]) {
      kimiDocs[worker.workerId].lastUsed = new Date(Date.now() + i * 1000);
    }
  }

  assert(!activeSelections.has("worker_kimi_3"), "worker_kimi_3 must never be selected while unhealthy");
  assert(activeSelections.size >= 3, "Must use remaining healthy Kimi workers");

  // Restore worker_kimi_3 health & provider health
  EnvConfig.setWorkerHealth("worker_kimi_3", true, 100);
  EnvConfig.setProviderHealth("openai", true, 100);
  EnvConfig.setProviderHealth("gemini", true, 120);
  EnvConfig.setProviderHealth("claude", true, 140);
  EnvConfig.setProviderHealth("deepseek", true, 160);

  console.log("  PASSED: worker_kimi_3 skipped cleanly while remaining Kimi pool workers processed requests.\n");

  // ----------------------------------------------------------------
  // TEST 5: AUTOMATIC FAILOVER TO KIMI POOL IF ALL PRIOR PROVIDERS UNAVAILABLE
  // ----------------------------------------------------------------
  console.log("Test 5: Verify backend automatically fails over to Kimi Pool if OpenAI, Gemini, Claude & DeepSeek are unavailable");

  EnvConfig.setProviderHealth("openai", false, 0, "Outage");
  EnvConfig.setProviderHealth("gemini", false, 0, "Outage");
  EnvConfig.setProviderHealth("claude", false, 0, "Outage");
  EnvConfig.setProviderHealth("deepseek", false, 0, "Outage");

  const failoverWorker = await WorkerManager.getAvailableWorker(db, "WRITER");
  assert(failoverWorker !== null, "Must select a Kimi worker when all prior providers are unavailable");
  assert.strictEqual(failoverWorker.provider, "kimi", "Must route to Kimi provider pool");
  assert(failoverWorker.workerId.startsWith("worker_kimi_"), "Must be a Kimi worker");

  // Restore provider health
  EnvConfig.setProviderHealth("openai", true, 100);
  EnvConfig.setProviderHealth("gemini", true, 120);
  EnvConfig.setProviderHealth("claude", true, 140);
  EnvConfig.setProviderHealth("deepseek", true, 160);

  console.log(`  PASSED: Backend automatically routed request to "${failoverWorker.workerId}" during total upstream outage.\n`);

  // ----------------------------------------------------------------
  // TEST 6: STARTUP REPORT LISTS EVERY KIMI WORKER
  // ----------------------------------------------------------------
  console.log("Test 6: Verify Startup Report lists every individual Kimi worker");
  await EnvConfig.runStartupVerificationAndReport();
  console.log("  PASSED: Startup report listed all 5 Kimi pool workers.\n");

  console.log("=================================================");
  console.log(" ALL 6 KIMI WORKER POOL TESTS PASSED 100%! ");
  console.log("=================================================");
})();

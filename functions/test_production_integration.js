/**
 * Production Integration Verification Test Suite
 */

const assert = require("assert");
const { EnvConfig } = require("./lib/config/env_config");
const { WorkerManager } = require("./lib/services/worker_manager");
const { OpenAIProvider } = require("./lib/providers/openai_provider");
const { GeminiProvider } = require("./lib/providers/gemini_provider");

console.log("=================================================");
console.log(" PRODUCTION INTEGRATION VERIFICATION TEST SUITE ");
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
  // TEST 1: SECRET MASKING IN LOGS
  // ----------------------------------------------------------------
  console.log("Test 1: Verify secret masking masks keys correctly (sk-..., AIza..., private_...)");
  const openAiMasked = EnvConfig.maskSecret(process.env.OPENAI_API_KEY);
  const geminiMasked = EnvConfig.maskSecret(process.env.GEMINI_API_KEY);
  const ikMasked = EnvConfig.maskSecret(process.env.IMAGEKIT_PRIVATE_KEY);

  assert(openAiMasked.includes("************"), "OpenAI key must be masked");
  assert(!openAiMasked.includes(process.env.OPENAI_API_KEY), "Raw OpenAI key must NEVER be printed");
  assert(geminiMasked.includes("************"), "Gemini key must be masked");
  assert(ikMasked.includes("************"), "ImageKit key must be masked");
  console.log(`  PASSED: OpenAI Masked="${openAiMasked}", Gemini Masked="${geminiMasked}".\n`);

  // ----------------------------------------------------------------
  // TEST 2: ENVIRONMENT CONFIGURATION LOADING & VALIDATION
  // ----------------------------------------------------------------
  console.log("Test 2: Verify Centralized EnvConfig loads process.env variables cleanly");
  const { valid, missingVars } = EnvConfig.validateRequiredEnvVars();
  assert.strictEqual(valid, true, "Required environment variables must be present");
  assert.strictEqual(missingVars.length, 0);

  const openAiKey = EnvConfig.getApiKey("openai");
  assert(openAiKey.startsWith("sk-"), "EnvConfig must load valid OpenAI API key");
  console.log("  PASSED: Centralized EnvConfig loaded required keys from environment.\n");

  // ----------------------------------------------------------------
  // TEST 3: STARTUP ERROR ON MISSING REQUIRED VARIABLE
  // ----------------------------------------------------------------
  console.log("Test 3: Verify clear startup error displayed if required key is missing");
  const origKey = process.env.OPENAI_API_KEY;
  delete process.env.OPENAI_API_KEY;

  const missingCheck = EnvConfig.validateRequiredEnvVars();
  assert.strictEqual(missingCheck.valid, false);
  assert(missingCheck.missingVars.includes("OPENAI_API_KEY"));

  // Restore key
  process.env.OPENAI_API_KEY = origKey;
  console.log("  PASSED: Startup error correctly identified missing OPENAI_API_KEY.\n");

  // ----------------------------------------------------------------
  // TEST 4: AUTOMATIC HEALTH-BASED WORKER FAILOVER ROUTING
  // ----------------------------------------------------------------
  console.log("Test 4: Verify WorkerManager automatic failover when OpenAI is marked UNHEALTHY");

  const mockWorkers = {
    worker_openai_01: {
      provider: "openai",
      apiKey: process.env.OPENAI_API_KEY,
      enabled: true,
      busy: false,
      status: "idle",
      role: "WRITER",
      averageLatency: 100,
    },
    worker_gemini_01: {
      provider: "gemini",
      apiKey: process.env.GEMINI_API_KEY,
      enabled: true,
      busy: false,
      status: "idle",
      role: "WRITER",
      averageLatency: 150,
    },
  };

  const db = createMockFirestore(mockWorkers);

  // 1. Normal state: OpenAI is healthy -> selects worker_openai_01 (100ms < 150ms)
  EnvConfig.setProviderHealth("openai", true, 100);
  EnvConfig.setProviderHealth("gemini", true, 150);
  const worker1 = await WorkerManager.getAvailableWorker(db, "WRITER");
  assert.strictEqual(worker1.workerId, "worker_openai_01");

  // 2. Mark OpenAI UNHEALTHY -> WorkerManager automatically fails over to Gemini!
  EnvConfig.setProviderHealth("openai", false, 0, "429 Rate Limit");
  const worker2 = await WorkerManager.getAvailableWorker(db, "WRITER");
  assert.strictEqual(worker2.workerId, "worker_gemini_01", "WorkerManager must automatically failover to Gemini worker");

  // Restore OpenAI health
  EnvConfig.setProviderHealth("openai", true, 100);
  console.log("  PASSED: Automatic failover routed jobs from OpenAI -> Gemini seamlessly when OpenAI was marked UNHEALTHY.\n");

  // ----------------------------------------------------------------
  // TEST 5: FULL STARTUP REPORT PRODUCTION
  // ----------------------------------------------------------------
  console.log("Test 5: Verify Startup Report execution with all configured providers");
  await EnvConfig.runStartupVerificationAndReport();
  console.log("  PASSED: Startup Report printed successfully with all provider connections verified.\n");

  console.log("=================================================");
  console.log(" ALL 5 PRODUCTION INTEGRATION TESTS PASSED 100%! ");
  console.log("=================================================");
})();

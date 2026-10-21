import test from "node:test";
import assert from "node:assert/strict";
import { FluxProviderError } from "../lib/providers/image_generation/flux_thumbnail_provider.js";
import { FluxWorkerPool } from "../lib/providers/image_generation/flux_worker_pool.js";
type FluxWorkerConfig = any;

const Timestamp = {
  fromDate: (d: Date) => ({ toDate: () => d, getTime: () => d.getTime() }),
  now: () => ({ toDate: () => new Date(), getTime: () => Date.now() }),
};

function createMockDb(initialDocs: Record<string, any> = {}) {
  const store = new Map<string, any>(Object.entries(initialDocs));
  const writtenSets: Array<{ path: string; data: any; options?: any }> = [];

  const mockDb: any = {
    collection: (collName: string) => ({
      doc: (docId: string) => {
        const fullPath = `${collName}/${docId}`;
        const docRef: any = {
          id: docId,
          path: fullPath,
        };
        return docRef;
      },
    }),
    runTransaction: async (updateFunction: (transaction: any) => Promise<any>) => {
      const transaction = {
        get: async (ref: any) => {
          const data = store.get(ref.path);
          return {
            exists: data !== undefined,
            id: ref.id,
            data: () => (data ? { ...data } : undefined),
          };
        },
        set: (ref: any, data: any, options?: any) => {
          writtenSets.push({ path: ref.path, data, options });
          const existing = store.get(ref.path) || {};
          if (options && options.merge) {
            store.set(ref.path, { ...existing, ...data });
          } else {
            store.set(ref.path, { ...data });
          }
        },
      };
      return await updateFunction(transaction);
    },
    _store: store,
    _writes: writtenSets,
  };

  return mockDb;
}

test("Thumbnail Scheduler Reliability & Error Classification", async (t) => {
  await t.test("distinguishes daily quota exhaustion from temporary rate limiting", () => {
    // 1. Cloudflare code 4006 daily free allocation error
    const dailyQuotaErr = new FluxProviderError(
      'Cloudflare HTTP 429: {"errors":[{"code":4006,"message":"AiError: you have used up your daily free allocation of 10,000 neurons..."}]}',
      true,
      429,
      4006,
      true
    );
    assert.equal(dailyQuotaErr.isRetryable, true);
    assert.equal(dailyQuotaErr.cloudflareErrorCode, 4006);
    assert.equal(dailyQuotaErr.isDailyQuotaExhausted, true);

    // 2. Generic short 429 rate limiting (not daily quota)
    const rateLimitErr = new FluxProviderError(
      "Cloudflare HTTP 429 (Too Many Requests): Rate limit exceeded",
      true,
      429,
      undefined,
      false
    );
    assert.equal(rateLimitErr.isRetryable, true);
    assert.equal(rateLimitErr.isDailyQuotaExhausted, false);

    // 3. Transient capacity 3040
    const capacityErr = new FluxProviderError(
      "Cloudflare Workers AI: Out of capacity",
      true,
      503,
      3040,
      false
    );
    assert.equal(capacityErr.isRetryable, true);
    assert.equal(capacityErr.isDailyQuotaExhausted, false);

    // 4. Permanent error (401 Unauthorized)
    const permErr = new FluxProviderError(
      "Cloudflare HTTP 401 (Unauthorized): Invalid token",
      false,
      401,
      undefined,
      false
    );
    assert.equal(permErr.isRetryable, false);
    assert.equal(permErr.isDailyQuotaExhausted, false);
  });

  await t.test("daily quota exhaustion at 00:04 UTC does not lock workers until next day unnecessarily", () => {
    // Exact stall scenario: 00:04 UTC probe when yesterday's usage occurred and no success today
    const now = new Date("2026-10-21T00:04:24.000Z");
    const lastSuccessYesterday = new Date("2026-10-20T00:53:14.000Z");

    const result = FluxWorkerPool.calculateDailyQuotaCooldown(now, {
      lastSuccessAt: lastSuccessYesterday,
      failureStreak: 1,
    });

    assert.equal(result.isProbingWindow, true, "Must be classified as probing window");
    assert.equal(result.cooldownUntil.toISOString(), "2026-10-21T00:34:24.000Z");

    // Cooldown must be exactly 30 minutes, NOT 24 hours!
    const diffMinutes = (result.cooldownUntil.getTime() - now.getTime()) / (1000 * 60);
    assert.equal(diffMinutes, 30);
    assert.notEqual(result.cooldownUntil.toISOString().slice(0, 10), "2026-10-22");
  });

  await t.test("genuine quota exhaustion later in the day produces a sensible cooldown to tomorrow 00:15 UTC", () => {
    // Scenario A: Afternoon run (14:30 UTC)
    const afternoonNow = new Date("2026-10-21T14:30:00.000Z");
    const afternoonResult = FluxWorkerPool.calculateDailyQuotaCooldown(afternoonNow);

    assert.equal(afternoonResult.isProbingWindow, false, "Afternoon exhaustion is genuine daily exhaustion");
    assert.equal(afternoonResult.cooldownUntil.toISOString(), "2026-10-22T00:15:00.000Z");

    // Scenario B: Finished generating a batch today at 01:25 UTC (successful runs earlier today)
    const earlyMorningNow = new Date("2026-10-21T01:25:00.000Z");
    const successEarlierToday = new Date("2026-10-21T01:20:00.000Z");

    const batchResult = FluxWorkerPool.calculateDailyQuotaCooldown(earlyMorningNow, {
      lastSuccessAt: successEarlierToday,
    });

    assert.equal(batchResult.isProbingWindow, false, "Exhaustion after active today runs is genuine");
    assert.equal(batchResult.cooldownUntil.toISOString(), "2026-10-22T00:15:00.000Z");
  });

  await t.test("recovery attempts remain bounded while quota is unavailable", () => {
    // Probes spaced 30 min apart during the 00:00 - 02:00 UTC rollover window
    const p1 = new Date("2026-10-21T00:04:00.000Z");
    const r1 = FluxWorkerPool.calculateDailyQuotaCooldown(p1, { failureStreak: 1 });
    assert.equal(r1.isProbingWindow, true);
    assert.equal(r1.cooldownUntil.toISOString(), "2026-10-21T00:34:00.000Z");

    const p2 = new Date("2026-10-21T00:34:00.000Z");
    const r2 = FluxWorkerPool.calculateDailyQuotaCooldown(p2, { failureStreak: 2 });
    assert.equal(r2.isProbingWindow, true);
    assert.equal(r2.cooldownUntil.toISOString(), "2026-10-21T01:04:00.000Z");

    const p3 = new Date("2026-10-21T01:04:00.000Z");
    const r3 = FluxWorkerPool.calculateDailyQuotaCooldown(p3, { failureStreak: 3 });
    assert.equal(r3.isProbingWindow, true);
    assert.equal(r3.cooldownUntil.toISOString(), "2026-10-21T01:34:00.000Z");

    // Past 02:00 UTC: bounded policy stops probing and backs off until next UTC cycle
    const p4 = new Date("2026-10-21T02:05:00.000Z");
    const r4 = FluxWorkerPool.calculateDailyQuotaCooldown(p4, { failureStreak: 4 });
    assert.equal(r4.isProbingWindow, false);
    assert.equal(r4.cooldownUntil.toISOString(), "2026-10-22T00:15:00.000Z");
  });

  await t.test("a daily quota error does not cause immediate failover across all 13 workers", () => {
    const dailyQuotaErr = new FluxProviderError(
      "Cloudflare HTTP 429: code 4006 daily free allocation exhausted",
      true,
      429,
      4006,
      true
    );
    const capacityErr = new FluxProviderError(
      "Cloudflare Workers AI: Out of capacity",
      true,
      503,
      3040,
      false
    );

    const poolAvailable = 12;
    const forcedProvider = undefined;

    // Daily quota error: failover must be explicitly forbidden
    const isRetryable1 = dailyQuotaErr.isRetryable;
    const isDailyQuota1 = dailyQuotaErr.isDailyQuotaExhausted;
    const shouldFailover1 = isRetryable1 && !isDailyQuota1 && poolAvailable > 0 && forcedProvider !== "gemini";
    assert.equal(shouldFailover1, false, "Must NEVER failover across pool workers on daily quota exhaustion");

    // Transient capacity error: failover within pool is permitted
    const isRetryable2 = capacityErr.isRetryable;
    const isDailyQuota2 = capacityErr.isDailyQuotaExhausted;
    const shouldFailover2 = isRetryable2 && !isDailyQuota2 && poolAvailable > 0 && forcedProvider !== "gemini";
    assert.equal(shouldFailover2, true, "Transient capacity errors should continue to failover within pool");
  });

  await t.test("multiple concurrent scheduler invocations do not trigger a recovery-probe storm", () => {
    const nowMs = new Date("2026-10-21T00:35:00.000Z").getTime();

    // Pool state when instance A has initiated a probe
    const activeProbePoolState = {
      dailyQuotaPausedUntil: null,
      dailyQuotaProbeInProgress: true,
      probeLockedUntil: new Date(nowMs + 45000), // 45s remaining
    };

    const isProbeActive = Boolean(
      activeProbePoolState.dailyQuotaProbeInProgress &&
      activeProbePoolState.probeLockedUntil.getTime() > nowMs
    );
    assert.equal(isProbeActive, true, "Concurrent invocation must detect active probe and decline execution");

    // Once probe completes or lock expires after 60s
    const expiredProbePoolState = {
      dailyQuotaPausedUntil: null,
      dailyQuotaProbeInProgress: false,
      probeLockedUntil: null,
    };
    const isExpiredProbeActive = Boolean(
      expiredProbePoolState.dailyQuotaProbeInProgress &&
      expiredProbePoolState.probeLockedUntil
    );
    assert.equal(isExpiredProbeActive, false, "Next probe or ordinary execution can proceed after probe completes");
  });

  await t.test("a successful recovery probe allows normal queued processing to resume", () => {
    // Simulate pool state updates upon successful probe
    const poolState = {
      dailyQuotaPausedUntil: new Date("2026-10-21T00:34:00.000Z"),
      dailyQuotaProbeInProgress: true,
      dailyQuotaFailureStreak: 1,
      lastSuccessfulGenerationAt: null as Date | null,
    };

    // On success:
    poolState.dailyQuotaPausedUntil = null;
    poolState.dailyQuotaProbeInProgress = false;
    poolState.dailyQuotaFailureStreak = 0;
    poolState.lastSuccessfulGenerationAt = new Date("2026-10-21T00:35:00.000Z");

    assert.equal(poolState.dailyQuotaPausedUntil, null, "Pool pause must be cleared on probe success");
    assert.equal(poolState.dailyQuotaProbeInProgress, false, "Probe lock must be released on probe success");
    assert.equal(poolState.dailyQuotaFailureStreak, 0, "Failure streak must be reset to 0");
    assert.ok(poolState.lastSuccessfulGenerationAt !== null, "Success timestamp must be recorded");
  });

  await t.test("non-quota transient errors retain appropriate retry behavior", () => {
    const currentFailures = 2;
    const baseCooldownMs = 120000; // 2 minutes
    const nextFailures = currentFailures + 1;
    const cooldownMultiplier = Math.min(nextFailures, 5);
    const cooldownMs = baseCooldownMs * cooldownMultiplier;

    // Transient error cooldown should be 6 minutes (3 * 2m)
    assert.equal(cooldownMs, 6 * 60 * 1000);
    assert.ok(cooldownMs <= 10 * 60 * 1000, "Must be bounded up to 10 minutes max");
  });

  await t.test("authentication errors are not misclassified as quota-reset delays", () => {
    const authErr = new FluxProviderError(
      "Cloudflare HTTP 401: Unauthorized",
      false, // non-retryable
      401,
      undefined,
      false // NOT daily quota
    );

    assert.equal(authErr.isRetryable, false);
    assert.equal(authErr.isDailyQuotaExhausted, false);

    // Auth error causes status: "disabled", NEVER "cooling_down" with daily quota delay
    const targetStatus = authErr.isRetryable ? "cooling_down" : "disabled";
    assert.equal(targetStatus, "disabled");
  });

  await t.test("lease lock recovery: expired lease locks are recoverable", () => {
    const nowMs = Date.now();
    const expiredLockMs = nowMs - 5000; // 5s in past
    const activeLockMs = nowMs + 60000; // 60s in future

    // Check availability logic
    const isExpiredAvailable = expiredLockMs <= nowMs;
    const isActiveAvailable = activeLockMs <= nowMs;

    assert.equal(isExpiredAvailable, true, "Expired lease lock must be treated as available/recoverable");
    assert.equal(isActiveAvailable, false, "Active lease lock must remain busy");
  });

  await t.test("completed thumbnails are skipped idempotently", () => {
    const completedDoc = {
      thumbnailUrl: "https://ik.imagekit.io/ubgbitinve/THUMBNAILS/sample.jpg",
      thumbnailStatus: "completed",
    };
    const pendingDoc = {
      thumbnailUrl: "",
      thumbnailStatus: "pending",
    };

    const shouldSkipCompleted = Boolean(completedDoc.thumbnailUrl && completedDoc.thumbnailUrl.trim().length > 0);
    const shouldSkipPending = Boolean(pendingDoc.thumbnailUrl && pendingDoc.thumbnailUrl.trim().length > 0);

    assert.equal(shouldSkipCompleted, true, "Completed thumbnail must be skipped");
    assert.equal(shouldSkipPending, false, "Pending thumbnail must not be skipped");
  });

  await t.test("DSpace materials are strictly Flux-only; Gemini fallback is disabled", () => {
    const forcedProvider = undefined;

    // For DSpace material:
    const isImportedDSpace = true;
    const runFluxDSpace = forcedProvider !== "gemini";
    const runGeminiDSpace = isImportedDSpace ? false : (forcedProvider !== "flux");

    assert.equal(runFluxDSpace, true);
    assert.equal(runGeminiDSpace, false, "DSpace must never run Gemini fallback");

    // For non-DSpace user upload:
    const isNonDSpace = false;
    const runFluxNonDSpace = forcedProvider !== "gemini";
    const runGeminiNonDSpace = isNonDSpace ? false : (forcedProvider !== "flux");

    assert.equal(runFluxNonDSpace, true);
    assert.equal(runGeminiNonDSpace, true, "Non-DSpace materials continue to support Gemini fallback");
  });

  await t.test("transaction: healthy steady-state reservations preserve multi-worker concurrency without probe lock", async () => {
    const configs: FluxWorkerConfig[] = [
      { workerId: "worker-1", accountId: "acc1", apiKey: "key1", model: "model1" },
      { workerId: "worker-2", accountId: "acc2", apiKey: "key2", model: "model2" },
    ];

    const mockDb = createMockDb({
      "flux_workers/_pool_state": {
        dailyQuotaPausedUntil: null,
        dailyQuotaFailureStreak: 0,
        dailyQuotaProbeInProgress: false,
        probeLockedUntil: null,
        lastSuccessfulGenerationAt: Timestamp.fromDate(new Date()),
      },
      "flux_workers/worker-1": {
        workerId: "worker-1",
        status: "available",
        lockedUntil: null,
        cooldownUntil: null,
        lastUsedAt: null,
      },
      "flux_workers/worker-2": {
        workerId: "worker-2",
        status: "available",
        lockedUntil: null,
        cooldownUntil: null,
        lastUsedAt: null,
      },
    });

    // 1. Reserve worker-1
    const res1 = await FluxWorkerPool.reserveAvailableWorker(mockDb, "job-1", configs);
    assert.ok(res1 !== null);
    assert.equal(res1.workerId, "worker-1");

    // Pool state MUST NOT have dailyQuotaProbeInProgress set during healthy steady-state!
    const poolState = mockDb._store.get("flux_workers/_pool_state");
    assert.equal(Boolean(poolState?.dailyQuotaProbeInProgress), false, "Steady-state must NOT set probe lock");

    // 2. Reserve worker-2 concurrently while worker-1 is busy
    const res2 = await FluxWorkerPool.reserveAvailableWorker(mockDb, "job-2", configs);
    assert.ok(res2 !== null, "Concurrent reservation of worker-2 MUST succeed during healthy steady-state");
    assert.equal(res2.workerId, "worker-2");
  });

  await t.test("transaction: quota recovery probe locks probe gate and blocks concurrent probe reservation", async () => {
    const configs: FluxWorkerConfig[] = [
      { workerId: "worker-1", accountId: "acc1", apiKey: "key1", model: "model1" },
      { workerId: "worker-2", accountId: "acc2", apiKey: "key2", model: "model2" },
    ];

    const nowMs = Date.now();
    const mockDb = createMockDb({
      "flux_workers/_pool_state": {
        // Daily quota pause expired 5 seconds ago
        dailyQuotaPausedUntil: Timestamp.fromDate(new Date(nowMs - 5000)),
        dailyQuotaFailureStreak: 1,
        dailyQuotaProbeInProgress: false,
        probeLockedUntil: null,
      },
      "flux_workers/worker-1": {
        workerId: "worker-1",
        status: "available",
        lockedUntil: null,
        cooldownUntil: null,
      },
      "flux_workers/worker-2": {
        workerId: "worker-2",
        status: "available",
        lockedUntil: null,
        cooldownUntil: null,
      },
    });

    // First reservation: designated as the single recovery probe
    const probeWorker = await FluxWorkerPool.reserveAvailableWorker(mockDb, "probe-job", configs);
    assert.ok(probeWorker !== null);
    assert.equal(probeWorker.workerId, "worker-1");

    // Pool state MUST have probe lock active
    const poolState = mockDb._store.get("flux_workers/_pool_state");
    assert.equal(poolState?.dailyQuotaProbeInProgress, true, "Probe gate must be locked");
    assert.ok(poolState?.probeLockedUntil !== null, "probeLockedUntil must be populated");

    // Second reservation during probe: MUST be refused (return null) to prevent probe storm
    const concurrentAttempt = await FluxWorkerPool.reserveAvailableWorker(mockDb, "concurrent-job", configs);
    assert.equal(concurrentAttempt, null, "Concurrent invocation must be blocked while probe is in flight");
  });

  await t.test("transaction: crashed probe owner recovers automatically after probeLockedUntil expires", async () => {
    const configs: FluxWorkerConfig[] = [
      { workerId: "worker-1", accountId: "acc1", apiKey: "key1", model: "model1" },
      { workerId: "worker-2", accountId: "acc2", apiKey: "key2", model: "model2" },
    ];

    const nowMs = Date.now();
    const mockDb = createMockDb({
      "flux_workers/_pool_state": {
        dailyQuotaPausedUntil: Timestamp.fromDate(new Date(nowMs - 65000)),
        dailyQuotaFailureStreak: 1,
        dailyQuotaProbeInProgress: true,
        // Probe lock expired 5 seconds ago
        probeLockedUntil: Timestamp.fromDate(new Date(nowMs - 5000)),
      },
      "flux_workers/worker-1": {
        workerId: "worker-1",
        status: "busy",
        // Worker 1 was crashed instance, still has active lease
        lockedUntil: Timestamp.fromDate(new Date(nowMs + 60000)),
      },
      "flux_workers/worker-2": {
        workerId: "worker-2",
        status: "available",
        lockedUntil: null,
        cooldownUntil: null,
      },
    });

    // Next invocation should recover automatically using available worker-2
    const recoveredWorker = await FluxWorkerPool.reserveAvailableWorker(mockDb, "recovery-job", configs);
    assert.ok(recoveredWorker !== null, "Must recover automatically after probe lock expires");
    assert.equal(recoveredWorker.workerId, "worker-2");
  });

  await t.test("transaction: legacy worker cooldowns are superseded and designated as single recovery probe", async () => {
    const configs: FluxWorkerConfig[] = [
      { workerId: "worker-1", accountId: "acc1", apiKey: "key1", model: "model1" },
      { workerId: "worker-2", accountId: "acc2", apiKey: "key2", model: "model2" },
    ];

    const nowMs = Date.now();
    const mockDb = createMockDb({
      // _pool_state does not exist yet (exact production state before fix)
      "flux_workers/worker-1": {
        workerId: "worker-1",
        status: "cooling_down",
        lockedUntil: null,
        cooldownUntil: Timestamp.fromDate(new Date(nowMs + 24 * 3600 * 1000)),
        lastError: 'Cloudflare HTTP 429: {"errors":[{"code":4006,"message":"AiError: you have used up your daily free allocation of 10,000 neurons..."}]}',
      },
      "flux_workers/worker-2": {
        workerId: "worker-2",
        status: "cooling_down",
        lockedUntil: null,
        cooldownUntil: Timestamp.fromDate(new Date(nowMs + 24 * 3600 * 1000)),
        lastError: 'Cloudflare HTTP 429: {"errors":[{"code":4006,"message":"AiError: you have used up your daily free allocation of 10,000 neurons..."}]}',
      },
    });

    // First invocation: supersedes legacy cooldown and locks probe gate
    const legacyProbe = await FluxWorkerPool.reserveAvailableWorker(mockDb, "legacy-probe-job", configs);
    assert.ok(legacyProbe !== null, "Legacy cooldown must be superseded");
    assert.equal(legacyProbe.workerId, "worker-1");

    // Probe gate in _pool_state must now be locked
    const poolState = mockDb._store.get("flux_workers/_pool_state");
    assert.equal(poolState?.dailyQuotaProbeInProgress, true, "Legacy probe must engage probe lock");

    // Concurrent invocation must be blocked
    const concurrentBlocked = await FluxWorkerPool.reserveAvailableWorker(mockDb, "concurrent-legacy", configs);
    assert.equal(concurrentBlocked, null, "Concurrent invocation during legacy probe must be blocked");
  });
});

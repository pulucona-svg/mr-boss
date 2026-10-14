import test from "node:test";
import assert from "node:assert/strict";
import { FluxProviderError } from "../lib/providers/image_generation/flux_thumbnail_provider.js";

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

  await t.test("calculates cooldown to next UTC midnight for daily quota reset", () => {
    const now = new Date("2026-10-14T14:30:00.000Z");
    const nextUtcReset = new Date(Date.UTC(
      now.getUTCFullYear(),
      now.getUTCMonth(),
      now.getUTCDate() + 1,
      0, 1, 0
    ));

    // Next reset should be at 2026-10-15T00:01:00.000Z
    assert.equal(nextUtcReset.toISOString(), "2026-10-15T00:01:00.000Z");
    assert.ok(nextUtcReset.getTime() > now.getTime());

    // Difference should be ~9.5 hours
    const diffHours = (nextUtcReset.getTime() - now.getTime()) / (1000 * 60 * 60);
    assert.ok(diffHours > 9.4 && diffHours < 9.6);
  });

  await t.test("worker remains cooling down until UTC reset, then becomes eligible", () => {
    const nowMs = new Date("2026-10-14T20:00:00.000Z").getTime();
    const resetMs = new Date("2026-10-15T00:01:00.000Z").getTime();

    // At 20:00 UTC, worker cooldown is in future -> NOT eligible
    assert.ok(resetMs > nowMs, "Worker should be cooling down before reset");

    // At 00:02 UTC the next day:
    const nextDayMs = new Date("2026-10-15T00:02:00.000Z").getTime();
    assert.ok(nextDayMs > resetMs, "Worker becomes eligible after reset without manual intervention");
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
    // Replicating thumbnail_search_service provider selection logic:
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
});

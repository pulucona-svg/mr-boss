import assert from "node:assert";
import test from "node:test";
import {
  CAMPAIGN_STAGES,
  addCalendarMonthsClamped,
  calculateStageExpiry,
  hashUserEmail,
  isPaidSubscriptionRecord,
  PromotionalTrialService,
} from "./lib/services/promotional_trial_service.js";

test("Promotional Trials - Calendar Month Clamping", () => {
  // Test case 1: Dec 30, 2026 + 2 months should clamp to Feb 28, 2027 (non-leap year)
  const dec30 = new Date("2026-12-30T23:59:59.000Z");
  const febClamped = addCalendarMonthsClamped(dec30, 2);
  assert.strictEqual(febClamped.getUTCFullYear(), 2027);
  assert.strictEqual(febClamped.getUTCMonth(), 1); // February (0-indexed)
  assert.strictEqual(febClamped.getUTCDate(), 28);
  assert.strictEqual(febClamped.getUTCHours(), 23);
  assert.strictEqual(febClamped.getUTCMinutes(), 59);

  // Test case 2: Jan 31, 2027 + 1 month should clamp to Feb 28, 2027
  const jan31 = new Date("2027-01-31T12:00:00.000Z");
  const feb1Month = addCalendarMonthsClamped(jan31, 1);
  assert.strictEqual(feb1Month.getUTCFullYear(), 2027);
  assert.strictEqual(feb1Month.getUTCMonth(), 1); // February
  assert.strictEqual(feb1Month.getUTCDate(), 28);

  // Test case 3: Regular date addition (Oct 13, 2026 + 2 months -> Dec 13, 2026)
  const oct13 = new Date("2026-10-13T10:00:00.000Z");
  const dec13 = addCalendarMonthsClamped(oct13, 2);
  assert.strictEqual(dec13.getUTCFullYear(), 2026);
  assert.strictEqual(dec13.getUTCMonth(), 11); // December
  assert.strictEqual(dec13.getUTCDate(), 13);
});

test("Promotional Trials - Stage Expiry Calculation", () => {
  const start = new Date("2026-10-13T00:00:00.000Z");

  // Stage 1: 2 months
  const stage1Expiry = calculateStageExpiry(start, 1);
  assert.strictEqual(stage1Expiry.getUTCFullYear(), 2026);
  assert.strictEqual(stage1Expiry.getUTCMonth(), 11); // December
  assert.strictEqual(stage1Expiry.getUTCDate(), 13);

  // Stage 2: 1 month
  const stage2Expiry = calculateStageExpiry(start, 2);
  assert.strictEqual(stage2Expiry.getUTCFullYear(), 2026);
  assert.strictEqual(stage2Expiry.getUTCMonth(), 10); // November
  assert.strictEqual(stage2Expiry.getUTCDate(), 13);

  // Stage 3: 7 days exactly
  const stage3Expiry = calculateStageExpiry(start, 3);
  const diffDays = (stage3Expiry.getTime() - start.getTime()) / (1000 * 60 * 60 * 24);
  assert.strictEqual(diffDays, 7);
});

test("Promotional Trials - Email Hash Deduplication", () => {
  const email1 = "User.Test@Domain.COM";
  const email2 = "  user.test@domain.com ";
  const hash1 = hashUserEmail(email1);
  const hash2 = hashUserEmail(email2);

  assert.strictEqual(hash1, hash2, "Normalized email hash must be identical regardless of case/whitespace");
  assert.strictEqual(hash1.length, 64, "SHA-256 hex string should be 64 characters");
});

test("Promotional Trials - Campaign State Machine Stage 1 Active", () => {
  const campaignData = {
    stage1: { claimedCount: 10 },
    stage2: { claimedCount: 0 },
    stage3: { claimedCount: 0 },
  };

  const now = new Date("2026-11-01T00:00:00.000Z");
  const result = PromotionalTrialService.resolveActiveStage(campaignData, now);

  assert.strictEqual(result.activeStageNumber, 1, "Stage 1 should be active before 50 claims and before deadline");
  assert.strictEqual(result.stageCounts[1], 10);
});

test("Promotional Trials - Progression from Stage 1 to Stage 2 on 50 Claims Limit", () => {
  const campaignData = {
    stage1: { claimedCount: 50 }, // Max 50 reached
    stage2: { claimedCount: 5 },
    stage3: { claimedCount: 0 },
  };

  const now = new Date("2026-11-01T00:00:00.000Z");
  const result = PromotionalTrialService.resolveActiveStage(campaignData, now);

  assert.strictEqual(result.activeStageNumber, 2, "Should advance to Stage 2 when Stage 1 reaches 50 claims");
});

test("Promotional Trials - Progression from Stage 1 to Stage 2 on Deadline Expiry", () => {
  const campaignData = {
    stage1: { claimedCount: 20 }, // Only 20 claims, but deadline passed
    stage2: { claimedCount: 0 },
    stage3: { claimedCount: 0 },
  };

  // Stage 1 deadline is 2026-12-30T23:59:59.000Z
  const pastDeadline = new Date("2026-12-31T00:00:01.000Z");
  const result = PromotionalTrialService.resolveActiveStage(campaignData, pastDeadline);

  assert.strictEqual(result.activeStageNumber, 2, "Should advance to Stage 2 when Stage 1 deadline expires");
});

test("Promotional Trials - Progression from Stage 2 to Stage 3 on 45 Claims Limit", () => {
  const campaignData = {
    stage1: { claimedCount: 50 },
    stage2: { claimedCount: 45 }, // Max 45 reached
    stage3: { claimedCount: 10 },
  };

  const now = new Date("2027-01-15T00:00:00.000Z");
  const result = PromotionalTrialService.resolveActiveStage(campaignData, now);

  assert.strictEqual(result.activeStageNumber, 3, "Should advance to Stage 3 when Stage 2 reaches 45 claims");
});

test("Promotional Trials - Progression from Stage 2 to Stage 3 on Deadline Expiry", () => {
  const campaignData = {
    stage1: { claimedCount: 50 },
    stage2: { claimedCount: 15 }, // Only 15 claims, but deadline passed
    stage3: { claimedCount: 0 },
  };

  // Stage 2 deadline is 2027-03-01T23:59:59.000Z
  const pastDeadline = new Date("2027-03-02T00:00:01.000Z");
  const result = PromotionalTrialService.resolveActiveStage(campaignData, pastDeadline);

  assert.strictEqual(result.activeStageNumber, 3, "Should advance to Stage 3 when Stage 2 deadline expires");
});

test("Promotional Trials - Campaign Termination on Stage 3 1000 Claims Limit", () => {
  const campaignData = {
    stage1: { claimedCount: 50 },
    stage2: { claimedCount: 45 },
    stage3: { claimedCount: 1000 }, // Max 1000 reached
  };

  const now = new Date("2027-06-01T00:00:00.000Z");
  const result = PromotionalTrialService.resolveActiveStage(campaignData, now);

  assert.strictEqual(result.activeStageNumber, null, "Campaign should be closed once Stage 3 reaches 1000 claims");
});

test("Promotional Trials - Campaign Termination on Stage 3 Deadline Expiry", () => {
  const campaignData = {
    stage1: { claimedCount: 50 },
    stage2: { claimedCount: 45 },
    stage3: { claimedCount: 500 },
  };

  // Stage 3 deadline is 2027-12-30T23:59:59.000Z
  const pastDeadline = new Date("2027-12-31T00:00:01.000Z");
  const result = PromotionalTrialService.resolveActiveStage(campaignData, pastDeadline);

  assert.strictEqual(result.activeStageNumber, null, "Campaign should be closed after Stage 3 deadline passes");
});

// Import calculateSubscriptionChain from built lib
import { calculateSubscriptionChain } from "./lib/services/paystack_server_service.js";
import { SubscriptionReconciliationService } from "./lib/services/subscription_reconciliation_service.js";

test("Chaining - Daily Paid Pass followed by Weekly Paid Pass", () => {
  const now = new Date("2026-10-13T12:00:00.000Z");

  // Step 1: User buys Daily Pass (1 day)
  const chain1 = calculateSubscriptionChain([], 1, now);
  assert.strictEqual(chain1.newStatus, "active");
  assert.strictEqual(chain1.activationDate.toISOString(), now.toISOString());
  const expectedDailyExpiry = new Date(now.getTime() + 1 * 24 * 60 * 60 * 1000);
  assert.strictEqual(chain1.expiryDate.toISOString(), expectedDailyExpiry.toISOString());

  // Step 2: User buys Weekly Pass (7 days) immediately
  const existingHistory = [
    {
      status: "active",
      activationDate: chain1.activationDate,
      expiryDate: chain1.expiryDate,
    },
  ];
  const chain2 = calculateSubscriptionChain(existingHistory, 7, now);
  assert.strictEqual(chain2.newStatus, "queued");
  assert.strictEqual(chain2.activationDate.toISOString(), expectedDailyExpiry.toISOString());
  const expectedWeeklyExpiry = new Date(expectedDailyExpiry.getTime() + 7 * 24 * 60 * 60 * 1000);
  assert.strictEqual(chain2.expiryDate.toISOString(), expectedWeeklyExpiry.toISOString());
});

test("Chaining - Paid Purchase during Active Promotional Trial", () => {
  const now = new Date("2026-10-13T12:00:00.000Z");
  // User currently has active 2-month promotional trial expiring Dec 13, 2026
  const trialExpiry = new Date("2026-12-13T12:00:00.000Z");
  const existingHistory = [
    {
      status: "active",
      amount: 0,
      paymentChannel: "promotional_trial",
      activationDate: now,
      expiryDate: trialExpiry,
    },
  ];

  // User purchases Monthly Pass (30 days) via Paystack
  const chain = calculateSubscriptionChain(existingHistory, 30, now);
  assert.strictEqual(chain.newStatus, "queued");
  assert.strictEqual(chain.activationDate.toISOString(), trialExpiry.toISOString());
  const expectedMonthlyExpiry = new Date(trialExpiry.getTime() + 30 * 24 * 60 * 60 * 1000);
  assert.strictEqual(chain.expiryDate.toISOString(), expectedMonthlyExpiry.toISOString());
});

test("Chaining - Paid Purchase during Active Paid Entitlement", () => {
  const now = new Date("2026-10-13T12:00:00.000Z");
  const activeExpiry = new Date("2026-10-20T12:00:00.000Z"); // 7 days active
  const existingHistory = [
    {
      status: "active",
      amount: 30,
      activationDate: now,
      expiryDate: activeExpiry,
    },
  ];

  // User purchases Semester Pass (120 days)
  const chain = calculateSubscriptionChain(existingHistory, 120, now);
  assert.strictEqual(chain.newStatus, "queued");
  assert.strictEqual(chain.activationDate.toISOString(), activeExpiry.toISOString());
  const expectedExpiry = new Date(activeExpiry.getTime() + 120 * 24 * 60 * 60 * 1000);
  assert.strictEqual(chain.expiryDate.toISOString(), expectedExpiry.toISOString());
});

test("Chaining - Multiple Legitimate Queued Paid Purchases", () => {
  const now = new Date("2026-10-13T12:00:00.000Z");
  const passAExpiry = new Date("2026-10-14T12:00:00.000Z"); // 1 day
  const passBExpiry = new Date("2026-10-21T12:00:00.000Z"); // 7 days

  const existingHistory = [
    { status: "active", activationDate: now, expiryDate: passAExpiry },
    { status: "queued", activationDate: passAExpiry, expiryDate: passBExpiry },
  ];

  // User purchases Monthly Pass (30 days) - should chain behind pass B
  const chain = calculateSubscriptionChain(existingHistory, 30, now);
  assert.strictEqual(chain.newStatus, "queued");
  assert.strictEqual(chain.activationDate.toISOString(), passBExpiry.toISOString());
  const expectedExpiry = new Date(passBExpiry.getTime() + 30 * 24 * 60 * 60 * 1000);
  assert.strictEqual(chain.expiryDate.toISOString(), expectedExpiry.toISOString());
});

test("Chaining - Terminated, Refunded, or Revoked Entitlement does NOT extend chain", () => {
  const now = new Date("2026-10-13T12:00:00.000Z");
  const terminatedExpiry = new Date("2026-11-13T12:00:00.000Z"); // in future, but terminated

  const existingHistory = [
    { status: "terminated", activationDate: now, expiryDate: terminatedExpiry },
    { status: "refunded", activationDate: now, expiryDate: terminatedExpiry },
    { status: "cancelled", activationDate: now, expiryDate: terminatedExpiry },
    { status: "revoked", activationDate: now, expiryDate: terminatedExpiry },
  ];

  // Newly purchased pass should activate immediately at 'now', ignoring terminated entitlements
  const chain = calculateSubscriptionChain(existingHistory, 7, now);
  assert.strictEqual(chain.newStatus, "active");
  assert.strictEqual(chain.activationDate.toISOString(), now.toISOString());
  const expectedExpiry = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
  assert.strictEqual(chain.expiryDate.toISOString(), expectedExpiry.toISOString());
});

test("Promotional Trials - Calendar Month Clamping on Leap Year 2028 (Feb 29)", () => {
  // Dec 31, 2027 + 2 months should clamp to Feb 29, 2028 because 2028 is a leap year!
  const dec31 = new Date("2027-12-31T15:30:00.000Z");
  const febLeap = addCalendarMonthsClamped(dec31, 2);
  assert.strictEqual(febLeap.getUTCFullYear(), 2028);
  assert.strictEqual(febLeap.getUTCMonth(), 1); // February
  assert.strictEqual(febLeap.getUTCDate(), 29, "Must clamp to Feb 29 on leap year 2028");
  assert.strictEqual(febLeap.getUTCHours(), 15);
  assert.strictEqual(febLeap.getUTCMinutes(), 30);
});

test("Promotional Trials - UTC Campaign Deadline Boundaries", () => {
  const campaignData = {
    stage1: { claimedCount: 10 },
    stage2: { claimedCount: 0 },
    stage3: { claimedCount: 0 },
  };

  // Exact deadline instant: 2026-12-30T23:59:59.000Z (still valid for Stage 1)
  const exactDeadline = new Date("2026-12-30T23:59:59.000Z");
  const resultOn = PromotionalTrialService.resolveActiveStage(campaignData, exactDeadline);
  assert.strictEqual(resultOn.activeStageNumber, 1, "Should be active at exact deadline instant");

  // One millisecond past deadline: 2026-12-30T23:59:59.001Z (progresses to Stage 2)
  const pastDeadline = new Date("2026-12-30T23:59:59.001Z");
  const resultPast = PromotionalTrialService.resolveActiveStage(campaignData, pastDeadline);
  assert.strictEqual(resultPast.activeStageNumber, 2, "Must advance to Stage 2 past deadline");
});

test("Paid Entitlement Classification - Active Paid Purchases with Positive Amount", () => {
  // All standard Paystack packages have positive amounts and active status
  assert.strictEqual(isPaidSubscriptionRecord({ status: "active", amount: 5 }), true);
  assert.strictEqual(isPaidSubscriptionRecord({ status: "active", amount: 30 }), true);
  assert.strictEqual(isPaidSubscriptionRecord({ status: "active", amount: 100 }), true);
  assert.strictEqual(isPaidSubscriptionRecord({ status: "active", amount: 300 }), true);
  assert.strictEqual(isPaidSubscriptionRecord({ status: "active", amount: 500 }), true);

  // Queued pass with positive amount is also an unexpired paid entitlement
  assert.strictEqual(isPaidSubscriptionRecord({ status: "queued", amount: 30 }), true);
});

test("Paid Entitlement Classification - Inactive and Invalid Statuses Fail Closed", () => {
  // Even if amount > 0, invalid or inactive statuses must NOT count as active paid entitlements
  assert.strictEqual(isPaidSubscriptionRecord({ status: "expired", amount: 100 }), false);
  assert.strictEqual(isPaidSubscriptionRecord({ status: "terminated", amount: 100 }), false);
  assert.strictEqual(isPaidSubscriptionRecord({ status: "refunded", amount: 100 }), false);
  assert.strictEqual(isPaidSubscriptionRecord({ status: "cancelled", amount: 100 }), false);
  assert.strictEqual(isPaidSubscriptionRecord({ status: "revoked", amount: 100 }), false);
  assert.strictEqual(isPaidSubscriptionRecord({ status: "unknown", amount: 100 }), false);
});

test("Paid Entitlement Classification - Free and Gift Entitlements with Non-Standard Payment Channels", () => {
  // Non-standard payment channels with amount 0 must NOT be misclassified as paid
  assert.strictEqual(
    isPaidSubscriptionRecord({ status: "active", amount: 0, paymentChannel: "admin_gift" }),
    false,
    "Admin gift with amount 0 must not be treated as paid"
  );
  assert.strictEqual(
    isPaidSubscriptionRecord({ status: "active", amount: 0, paymentChannel: "complimentary" }),
    false,
    "Complimentary pass with amount 0 must not be treated as paid"
  );
  assert.strictEqual(
    isPaidSubscriptionRecord({ status: "active", amount: 0, paymentChannel: "legacy_free" }),
    false,
    "Legacy free pass with amount 0 must not be treated as paid"
  );
  assert.strictEqual(
    isPaidSubscriptionRecord({ status: "active", amount: 0, paymentChannel: "free_trial" }),
    false,
    "Generic free trial channel with amount 0 must not be treated as paid"
  );
});

test("Paid Entitlement Classification - Promotional Trial Entitlements Fail Closed", () => {
  assert.strictEqual(
    isPaidSubscriptionRecord({
      status: "active",
      amount: 0,
      paymentChannel: "promotional_trial",
      operatorReceiptNumber: "PROMO_FREE_TRIAL",
    }),
    false,
    "Promotional trial pass must not be treated as paid"
  );
});

test("Paid Entitlement Classification - Legacy Records with Verified Paystack Evidence", () => {
  // In the absence of an explicit amount field, verified Paystack transaction evidence qualifies as paid
  assert.strictEqual(
    isPaidSubscriptionRecord({
      status: "active",
      paystackTransactionId: 987654,
    }),
    true,
    "Presence of paystackTransactionId confirms paid status when amount is missing"
  );

  assert.strictEqual(
    isPaidSubscriptionRecord({
      status: "active",
      paystackReference: "T1234567890",
    }),
    true,
    "Presence of paystackReference confirms paid status when amount is missing"
  );

  assert.strictEqual(
    isPaidSubscriptionRecord({
      status: "active",
      paymentChannel: "mobile_money",
      transactionCode: "TXN_LEGACY_001",
    }),
    true,
    "Recognized Paystack payment channel paired with valid transactionCode confirms paid status"
  );
});

test("Paid Entitlement Classification - Legacy Records with Unverified or Promo Identifiers Fail Closed", () => {
  // If paystackReference or transactionCode starts with PROMO_, it must not be treated as paid
  assert.strictEqual(
    isPaidSubscriptionRecord({
      status: "active",
      paystackReference: "PROMO_STAGE1_1234",
    }),
    false
  );

  assert.strictEqual(
    isPaidSubscriptionRecord({
      status: "active",
      paymentChannel: "mobile_money",
      transactionCode: "PROMO_STAGE1_5678",
    }),
    false
  );

  // Unknown paymentChannel without amount and without Paystack ID/ref
  assert.strictEqual(
    isPaidSubscriptionRecord({
      status: "active",
      paymentChannel: "random_channel",
      transactionCode: "UNKNOWN_123",
    }),
    false
  );
});

test("Paid Entitlement Classification - Malformed or Missing Fields Fail Closed", () => {
  assert.strictEqual(isPaidSubscriptionRecord(null), false);
  assert.strictEqual(isPaidSubscriptionRecord(undefined), false);
  assert.strictEqual(isPaidSubscriptionRecord({}), false);
  assert.strictEqual(isPaidSubscriptionRecord({ status: "active", amount: -10 }), false);
  assert.strictEqual(isPaidSubscriptionRecord({ status: "active", amount: "not_a_number" }), false);
});


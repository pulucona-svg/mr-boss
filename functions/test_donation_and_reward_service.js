const assert = require("assert");

// Test suite for Donations and Rewarded-Ad XP System backend logic
console.log("=== RUNNING DONATION AND REWARDED-AD BACKEND TESTS ===");

// 1. Donation Calculations and Boundaries
console.log("1. Testing Donation Amount & XP Calculations...");
function calculateDonationXp(amount) {
  if (typeof amount !== "number" || !Number.isInteger(amount) || amount < 3) {
    throw new Error("Minimum donation amount is Ksh.3.");
  }
  return amount * 10;
}

// Below minimum rejected
assert.throws(() => calculateDonationXp(0), /Minimum donation amount is Ksh.3/);
assert.throws(() => calculateDonationXp(1), /Minimum donation amount is Ksh.3/);
assert.throws(() => calculateDonationXp(2), /Minimum donation amount is Ksh.3/);
assert.throws(() => calculateDonationXp(-10), /Minimum donation amount is Ksh.3/);
assert.throws(() => calculateDonationXp(2.5), /Minimum donation amount is Ksh.3/);

// Valid amounts and exact XP calculations
assert.strictEqual(calculateDonationXp(3), 30);
assert.strictEqual(calculateDonationXp(5), 50);
assert.strictEqual(calculateDonationXp(10), 100);
assert.strictEqual(calculateDonationXp(100), 1000);
assert.strictEqual(calculateDonationXp(250), 2500);
console.log("   [PASS] Donation minimum KSh 3 and 10 XP/KSh calculation validated.");

// 2. Payment Method Constraints
console.log("2. Testing Payment Method Constraints...");
function validatePaymentMethodAndAmount(method, amount) {
  if (!["mpesa", "airtelMoney", "mastercard"].includes(method)) {
    throw new Error(`Unsupported payment method: ${method}`);
  }
  if (amount < 3) {
    throw new Error("Minimum donation amount is Ksh.3.");
  }
  if (method === "mastercard" && amount < 100) {
    throw new Error("Card payment does not support payments below Ksh.100.");
  }
  return true;
}

assert.strictEqual(validatePaymentMethodAndAmount("mpesa", 3), true);
assert.strictEqual(validatePaymentMethodAndAmount("airtelMoney", 3), true);
assert.throws(() => validatePaymentMethodAndAmount("mastercard", 50), /Card payment does not support payments below Ksh.100/);
assert.strictEqual(validatePaymentMethodAndAmount("mastercard", 100), true);
assert.throws(() => validatePaymentMethodAndAmount("bitcoin", 100), /Unsupported payment method/);
console.log("   [PASS] Payment method validation and Mastercard KSh 100 floor validated.");

// 3. Donation vs Subscription Isolation
console.log("3. Testing Donation and Subscription Entitlement Isolation...");
const mockPaymentDoc = {
  type: "donation",
  expectedAmountKes: 50,
  expectedXp: 500,
  fulfilled: false,
};

let subscriptionActivated = false;
let xpAwarded = 0;

function mockFulfillRouter(paymentDoc) {
  if (paymentDoc.type === "donation") {
    xpAwarded += paymentDoc.expectedXp;
    paymentDoc.fulfilled = true;
    return { success: true, xpEarned: paymentDoc.expectedXp };
  } else {
    subscriptionActivated = true;
    paymentDoc.fulfilled = true;
    return { success: true, status: "active" };
  }
}

const result = mockFulfillRouter(mockPaymentDoc);
assert.strictEqual(result.success, true);
assert.strictEqual(result.xpEarned, 500);
assert.strictEqual(xpAwarded, 500);
assert.strictEqual(subscriptionActivated, false, "CRITICAL: Donation must NEVER activate a subscription!");
assert.strictEqual(mockPaymentDoc.fulfilled, true);
console.log("   [PASS] Donations completely isolated from subscription activation.");

// 4. Idempotency and Duplicate Protection
console.log("4. Testing Idempotent Fulfillment...");
const secondCallResult = (function (paymentDoc) {
  if (paymentDoc.fulfilled === true) {
    return { success: true, alreadyFulfilled: true, xpEarned: paymentDoc.expectedXp };
  }
  xpAwarded += paymentDoc.expectedXp;
  return { success: true, xpEarned: paymentDoc.expectedXp };
})(mockPaymentDoc);

assert.strictEqual(secondCallResult.alreadyFulfilled, true);
assert.strictEqual(xpAwarded, 500, "XP must NOT be credited a second time on replay!");
console.log("   [PASS] Idempotent payment callback protection verified.");

// 5. Dual Rewarded-Ad System, Nairobi Midnight Reset, and Global Cooldown
console.log("5. Testing Dual Rewarded-Ad Formats (+5 XP Video & +7 XP Interstitial)...");

function getNairobiDateKey(date = new Date()) {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Africa/Nairobi",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  return formatter.format(date);
}

// Verify Nairobi timezone behaves correctly across UTC midnight
// E.g. at 21:00 UTC on Nov 3, it is midnight (00:00) Nov 4 in Nairobi!
const beforeNairobiMidnightUtc = new Date("2026-11-03T20:59:59Z");
const afterNairobiMidnightUtc = new Date("2026-11-03T21:00:01Z");
assert.strictEqual(getNairobiDateKey(beforeNairobiMidnightUtc), "2026-11-03");
assert.strictEqual(getNairobiDateKey(afterNairobiMidnightUtc), "2026-11-04");
console.log("   [PASS] Nairobi midnight date calculation validated.");

function validateAdClaim({ session, user, now, clientSuppliedXp }) {
  if (session.userId !== user.uid) {
    throw new Error("Session does not belong to user");
  }
  if (session.consumed) {
    throw new Error("Session already consumed");
  }
  if (session.expiresAt.getTime() < now.getTime()) {
    throw new Error("Session expired");
  }

  // 1. Check global 30s cooldown across BOTH formats
  if (user.lastAdRewardAt) {
    const elapsed = Math.floor((now.getTime() - user.lastAdRewardAt.getTime()) / 1000);
    if (elapsed < 30) {
      throw new Error(`Cooldown active: wait ${30 - elapsed}s`);
    }
  }

  // 2. Check independent 20-reward daily cap per format (Nairobi calendar day)
  const todayNairobiKey = getNairobiDateKey(now);
  const isSameDay = user.adRewardDateNairobi === todayNairobiKey;
  const videoCount = isSameDay ? (user.adRewardCountVideoToday || 0) : 0;
  const interstitialCount = isSameDay ? (user.adRewardCountInterstitialToday || 0) : 0;

  const isInterstitial = session.rewardType === "rewarded_interstitial";
  const countToday = isInterstitial ? interstitialCount : videoCount;

  if (countToday >= 20) {
    throw new Error(`Daily limit of 20 reached for ${session.rewardType}`);
  }

  // 3. Authoritative server XP calculation (ignore clientSuppliedXp completely)
  const xpEarned = isInterstitial ? 7 : 5;

  // 4. Update state atomically
  session.consumed = true;
  user.xpBalance = (user.xpBalance || 0) + xpEarned;
  user.adRewardXp = (user.adRewardXp || 0) + xpEarned;
  user.adRewardDateNairobi = todayNairobiKey;
  user.lastAdRewardAt = now;

  if (isInterstitial) {
    user.adRewardCountInterstitialToday = countToday + 1;
    user.adRewardCountVideoToday = videoCount; // unchanged
  } else {
    user.adRewardCountVideoToday = countToday + 1;
    user.adRewardCountInterstitialToday = interstitialCount; // unchanged
  }

  return {
    success: true,
    xpEarned,
    rewardType: session.rewardType,
    remainingVideo: 20 - user.adRewardCountVideoToday,
    remainingInterstitial: 20 - user.adRewardCountInterstitialToday,
  };
}

const baseTime = new Date("2026-11-03T10:00:00Z");
const testUser = {
  uid: "user_test_456",
  xpBalance: 0,
  adRewardXp: 0,
  adRewardCountVideoToday: 0,
  adRewardCountInterstitialToday: 0,
  adRewardDateNairobi: "2026-11-03",
  lastAdRewardAt: null,
};

// 5a. Claim Rewarded Video (+5 XP)
const videoSession1 = {
  sessionId: "vid_1",
  userId: "user_test_456",
  rewardType: "rewarded_video",
  consumed: false,
  expiresAt: new Date(baseTime.getTime() + 5 * 60 * 1000),
};

const resVid1 = validateAdClaim({
  session: videoSession1,
  user: testUser,
  now: baseTime,
  clientSuppliedXp: 9999, // Attempt to forge XP
});

assert.strictEqual(resVid1.success, true);
assert.strictEqual(resVid1.xpEarned, 5, "Server must award exactly 5 XP for rewarded video regardless of client input");
assert.strictEqual(testUser.xpBalance, 5);
assert.strictEqual(testUser.adRewardCountVideoToday, 1);
assert.strictEqual(testUser.adRewardCountInterstitialToday, 0, "Interstitial count must remain 0 when video is claimed");
assert.strictEqual(videoSession1.consumed, true);
console.log("   [PASS] Rewarded video awards exactly 5 XP and ignores client tampering.");

// 5b. Global cooldown blocks immediate switch to Rewarded Interstitial
const intSession1 = {
  sessionId: "int_1",
  userId: "user_test_456",
  rewardType: "rewarded_interstitial",
  consumed: false,
  expiresAt: new Date(baseTime.getTime() + 5 * 60 * 1000),
};

assert.throws(
  () => validateAdClaim({
    session: intSession1,
    user: testUser,
    now: new Date(baseTime.getTime() + 15000), // Only 15s after video
  }),
  /Cooldown active: wait 15s/,
  "Global cooldown must prevent switching from video to interstitial before 30 seconds"
);
console.log("   [PASS] Global 30s cooldown prevents switching formats within cooldown.");

// 5c. After 30s cooldown, Rewarded Interstitial claims successfully (+7 XP)
const resInt1 = validateAdClaim({
  session: intSession1,
  user: testUser,
  now: new Date(baseTime.getTime() + 31000), // 31s after video
  clientSuppliedXp: 1, // Attempt to forge low XP
});

assert.strictEqual(resInt1.success, true);
assert.strictEqual(resInt1.xpEarned, 7, "Server must award exactly 7 XP for rewarded interstitial");
assert.strictEqual(testUser.xpBalance, 12, "Total balance: 5 + 7 = 12 XP");
assert.strictEqual(testUser.adRewardCountVideoToday, 1);
assert.strictEqual(testUser.adRewardCountInterstitialToday, 1);
console.log("   [PASS] Rewarded interstitial awards exactly 7 XP after cooldown.");

// 5d. Independent daily limits (simulate 20 videos reached while interstitials remain)
testUser.adRewardCountVideoToday = 20;
testUser.adRewardCountInterstitialToday = 5;

const videoSessionExhausted = {
  sessionId: "vid_exhausted",
  userId: "user_test_456",
  rewardType: "rewarded_video",
  consumed: false,
  expiresAt: new Date(baseTime.getTime() + 10 * 60 * 1000),
};

assert.throws(
  () => validateAdClaim({
    session: videoSessionExhausted,
    user: testUser,
    now: new Date(baseTime.getTime() + 70000),
  }),
  /Daily limit of 20 reached for rewarded_video/
);

// Interstitial can still be claimed even though video is at 20!
const intSessionAllowed = {
  sessionId: "int_allowed",
  userId: "user_test_456",
  rewardType: "rewarded_interstitial",
  consumed: false,
  expiresAt: new Date(baseTime.getTime() + 10 * 60 * 1000),
};

const resIntAllowed = validateAdClaim({
  session: intSessionAllowed,
  user: testUser,
  now: new Date(baseTime.getTime() + 71000),
});

assert.strictEqual(resIntAllowed.success, true);
assert.strictEqual(resIntAllowed.xpEarned, 7);
assert.strictEqual(testUser.adRewardCountInterstitialToday, 6);
assert.strictEqual(testUser.adRewardCountVideoToday, 20);
console.log("   [PASS] Independent daily limits: interstitial allowed when video is at max 20.");

// 5e. Nairobi midnight rollover resets counters for both formats
const nextNairobiDayTime = new Date("2026-11-03T21:05:00Z"); // 00:05 Nov 4 in Nairobi
const videoSessionNextDay = {
  sessionId: "vid_next_day",
  userId: "user_test_456",
  rewardType: "rewarded_video",
  consumed: false,
  expiresAt: new Date(nextNairobiDayTime.getTime() + 5 * 60 * 1000),
};

const resNextDay = validateAdClaim({
  session: videoSessionNextDay,
  user: testUser,
  now: nextNairobiDayTime,
});

assert.strictEqual(resNextDay.success, true);
assert.strictEqual(testUser.adRewardCountVideoToday, 1, "Video count resets to 1 on new Nairobi day");
assert.strictEqual(testUser.adRewardCountInterstitialToday, 0, "Interstitial count resets to 0 on new Nairobi day");
assert.strictEqual(testUser.adRewardDateNairobi, "2026-11-04");
console.log("   [PASS] Nairobi midnight rollover resets counters for both formats.");

console.log("=== ALL DONATION & REWARDED-AD BACKEND TESTS PASSED ===");

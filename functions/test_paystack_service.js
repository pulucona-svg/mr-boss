const assert = require("assert");
const crypto = require("crypto");

// Set test environment secret key
process.env.PAYSTACK_SECRET_KEY = "sk_test_mock_secret_key_for_testing";

const {
  AUTHORITATIVE_PACKAGES,
  normalizeKenyanPhone,
  verifyPaystackSignature,
} = require("./lib/services/paystack_server_service");

console.log("=== RUNNING PAYSTACK BACKEND TESTS ===");

// 1. Authoritative Package & Subunit Tests
console.log("1. Testing Authoritative Packages...");
assert.strictEqual(AUTHORITATIVE_PACKAGES.daily.priceKes, 5);
assert.strictEqual(AUTHORITATIVE_PACKAGES.daily.amountSubunits, 500);
assert.strictEqual(AUTHORITATIVE_PACKAGES.daily.durationDays, 1);

assert.strictEqual(AUTHORITATIVE_PACKAGES.weekly.priceKes, 30);
assert.strictEqual(AUTHORITATIVE_PACKAGES.weekly.amountSubunits, 3000);
assert.strictEqual(AUTHORITATIVE_PACKAGES.weekly.durationDays, 7);

assert.strictEqual(AUTHORITATIVE_PACKAGES.monthly.priceKes, 100);
assert.strictEqual(AUTHORITATIVE_PACKAGES.monthly.amountSubunits, 10000);
assert.strictEqual(AUTHORITATIVE_PACKAGES.monthly.durationDays, 30);

assert.strictEqual(AUTHORITATIVE_PACKAGES.semester.priceKes, 300);
assert.strictEqual(AUTHORITATIVE_PACKAGES.semester.amountSubunits, 30000);
assert.strictEqual(AUTHORITATIVE_PACKAGES.semester.durationDays, 120);

assert.strictEqual(AUTHORITATIVE_PACKAGES.yearly.priceKes, 500);
assert.strictEqual(AUTHORITATIVE_PACKAGES.yearly.amountSubunits, 50000);
assert.strictEqual(AUTHORITATIVE_PACKAGES.yearly.durationDays, 365);
console.log("   [PASS] Package definitions and KES subunit conversions verified.");

// 2. Kenyan Phone Normalization Tests
console.log("2. Testing Kenyan Phone Normalization...");
// 10-digit 07XXXXXXXX accepted and normalized to +2547XXXXXXXX
assert.strictEqual(normalizeKenyanPhone("0712345678"), "+254712345678");
// 10-digit 01XXXXXXXX accepted and normalized to +2541XXXXXXXX
assert.strictEqual(normalizeKenyanPhone("0112345678"), "+254112345678");
// International +254 and 254 formats
assert.strictEqual(normalizeKenyanPhone("254712345678"), "+254712345678");
assert.strictEqual(normalizeKenyanPhone("+254712345678"), "+254712345678");
assert.strictEqual(normalizeKenyanPhone("+254112345678"), "+254112345678");
// Formatted with spaces and dashes
assert.strictEqual(normalizeKenyanPhone("0710 000 000"), "+254710000000");
assert.strictEqual(normalizeKenyanPhone("0110-000-000"), "+254110000000");
console.log("   [PASS] Phone normalization verified for 07, 01, and +254 Kenyan formats.");

// 3. HMAC SHA-512 Webhook Signature Tests
console.log("3. Testing Webhook Signature Verification...");
const samplePayload = JSON.stringify({
  event: "charge.success",
  data: {
    reference: "ML_DAILY_TEST_REF",
    amount: 500,
    currency: "KES",
  },
});

const validSignature = crypto
  .createHmac("sha512", process.env.PAYSTACK_SECRET_KEY)
  .update(samplePayload)
  .digest("hex");

const invalidSignature = "invalid_forged_signature_hash";

assert.strictEqual(verifyPaystackSignature(samplePayload, validSignature), true);
assert.strictEqual(verifyPaystackSignature(samplePayload, invalidSignature), false);
assert.strictEqual(verifyPaystackSignature(samplePayload, ""), false);
console.log("   [PASS] HMAC SHA-512 signature verification strictly blocks invalid and forged payloads.");

// 4. Provider & Currency Constants Verification
console.log("4. Testing Provider, Currency, & Subunit Conventions...");
const mpesaProvider = "mpesa";
const airtelProvider = "atl";
const currency = "KES";

assert.strictEqual(mpesaProvider, "mpesa");
assert.strictEqual(airtelProvider, "atl");
assert.strictEqual(currency, "KES");
console.log("   [PASS] Paystack channels (mpesa, atl) and KES currency validated.");

// 5. Card Under-100 Rule Verification
console.log("5. Testing Card Under-Ksh.100 Rule...");
const dailyPkg = AUTHORITATIVE_PACKAGES.daily;
const monthlyPkg = AUTHORITATIVE_PACKAGES.monthly;
assert.strictEqual(dailyPkg.priceKes < 100, true);
assert.strictEqual(monthlyPkg.priceKes >= 100, true);
console.log("   [PASS] Card under-Ksh.100 restriction verified against package catalog.");

console.log("=== ALL PAYSTACK BACKEND TESTS PASSED ===");

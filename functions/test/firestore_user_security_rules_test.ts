import test from "node:test";
import assert from "node:assert/strict";

/**
 * Pure Unit Rule Engine replicating Firestore Security Rules for match /users/{userId}:
 *
 * function isAuthenticated() { return request.auth != null; }
 * function isOwner(userId) { return isAuthenticated() && request.auth.uid == userId; }
 * function isAdmin() { ... }
 * function isRestrictedUserField(keys) {
 *   return keys.hasAny([
 *     'deletionStatus', 'deletionScheduledAt', 'deletionRequestedAt',
 *     'deletionReason', 'deletionSurvey', 'restoredAt', 'isAnonymized',
 *     'anonymizedAt', 'authDeletePending',
 *     'role', 'isAdmin', 'admin',
 *     'isSubscribed', 'subscription', 'subscriptionStatus', 'subscriptionPlan',
 *     'tokens'
 *   ]);
 * }
 */

const RESTRICTED_USER_FIELDS = [
  "deletionStatus",
  "deletionScheduledAt",
  "deletionRequestedAt",
  "deletionReason",
  "deletionSurvey",
  "restoredAt",
  "isAnonymized",
  "anonymizedAt",
  "authDeletePending",
  "role",
  "isAdmin",
  "admin",
  "isSubscribed",
  "subscription",
  "subscriptionStatus",
  "subscriptionPlan",
  "tokens",
];

interface AuthContext {
  uid: string;
  token?: {
    admin?: boolean;
    role?: string;
    email_verified?: boolean;
    email?: string;
  };
}

function isAuthenticated(auth: AuthContext | null): boolean {
  return auth !== null && typeof auth.uid === "string" && auth.uid.length > 0;
}

function isOwner(userId: string, auth: AuthContext | null): boolean {
  return isAuthenticated(auth) && auth!.uid === userId;
}

function isAdmin(auth: AuthContext | null): boolean {
  if (!isAuthenticated(auth)) return false;
  const token = auth!.token || {};
  if (token.admin === true || token.role === "admin") return true;
  if (token.email_verified === true && token.email) {
    const adminEmails = [
      "pulucona@mail.com",
      "pulucona@gmail.com",
      "culucona@gmail.com",
      "admin@mirrorlaikipia.ac.ke",
      "testadmin@mirror.com",
      "admin@mirror.com",
    ];
    if (adminEmails.includes(token.email)) return true;
  }
  return false;
}

function isRestrictedUserField(keys: string[]): boolean {
  return keys.some((k) => RESTRICTED_USER_FIELDS.includes(k));
}

function getAffectedKeys(
  existingDoc: Record<string, any>,
  incomingDoc: Record<string, any>
): string[] {
  const allKeys = new Set([...Object.keys(existingDoc), ...Object.keys(incomingDoc)]);
  const affected: string[] = [];
  for (const k of allKeys) {
    if (!(k in existingDoc) || !(k in incomingDoc)) {
      affected.push(k);
    } else if (JSON.stringify(existingDoc[k]) !== JSON.stringify(incomingDoc[k])) {
      affected.push(k);
    }
  }
  return affected;
}

function evaluateCreate(
  userId: string,
  auth: AuthContext | null,
  data: Record<string, any>
): boolean {
  if (isAdmin(auth)) return true;
  return isOwner(userId, auth) && !isRestrictedUserField(Object.keys(data));
}

function evaluateUpdate(
  userId: string,
  auth: AuthContext | null,
  existingData: Record<string, any>,
  newData: Record<string, any>
): boolean {
  if (isAdmin(auth)) return true;
  const affectedKeys = getAffectedKeys(existingData, newData);
  return isOwner(userId, auth) && !isRestrictedUserField(affectedKeys);
}

test("Firestore Security Rules: User Profile Rules Verification", async (t) => {
  const validProfileData = {
    uid: "user-123",
    username: "Jane Doe",
    institution: "Laikipia University",
    universityLocation: "Main Campus",
    program: "Computer Science",
    programCode: "CS101",
    year: "Year 2",
    semester: "Sem 1",
    phone: "0712345678",
    email: "jane@example.com",
    onboardingComplete: true,
  };

  await t.test("1. Newly authenticated user can create their own valid profile", () => {
    const auth: AuthContext = { uid: "user-123" };
    const allowed = evaluateCreate("user-123", auth, validProfileData);
    assert.strictEqual(allowed, true, "Valid profile creation by owner must be allowed");
  });

  await t.test("2. User can update permitted profile fields on their own document", () => {
    const auth: AuthContext = { uid: "user-123" };
    const existing = { ...validProfileData, phone: "0700000000" };
    const updated = { ...validProfileData, phone: "0711111111", year: "Year 3" };
    const allowed = evaluateUpdate("user-123", auth, existing, updated);
    assert.strictEqual(allowed, true, "Permitted profile field updates by owner must be allowed");
  });

  await t.test("3. User cannot create or modify another user's profile document", () => {
    const auth: AuthContext = { uid: "attacker-666" };
    const createAllowed = evaluateCreate("victim-777", auth, validProfileData);
    assert.strictEqual(createAllowed, false, "Cross-user create must be denied");

    const updateAllowed = evaluateUpdate(
      "victim-777",
      auth,
      validProfileData,
      { ...validProfileData, phone: "0799999999" }
    );
    assert.strictEqual(updateAllowed, false, "Cross-user update must be denied");
  });

  await t.test("4. Unauthenticated users cannot write profiles", () => {
    const createAllowed = evaluateCreate("user-123", null, validProfileData);
    assert.strictEqual(createAllowed, false, "Unauthenticated create must be denied");

    const updateAllowed = evaluateUpdate("user-123", null, validProfileData, {
      ...validProfileData,
      phone: "0799999999",
    });
    assert.strictEqual(updateAllowed, false, "Unauthenticated update must be denied");
  });

  await t.test("5. Client writes cannot grant admin privileges or modify role", () => {
    const auth: AuthContext = { uid: "user-123" };
    const maliciousCreate1 = { ...validProfileData, role: "admin" };
    const maliciousCreate2 = { ...validProfileData, isAdmin: true };

    assert.strictEqual(evaluateCreate("user-123", auth, maliciousCreate1), false, "Self-assign role=admin must be denied");
    assert.strictEqual(evaluateCreate("user-123", auth, maliciousCreate2), false, "Self-assign isAdmin=true must be denied");

    const maliciousUpdate = { ...validProfileData, role: "admin" };
    assert.strictEqual(
      evaluateUpdate("user-123", auth, validProfileData, maliciousUpdate),
      false,
      "Escalating role via update must be denied"
    );
  });

  await t.test("6. Client writes cannot grant subscriptions or modify payment fields", () => {
    const auth: AuthContext = { uid: "user-123" };
    const maliciousCreate = { ...validProfileData, isSubscribed: true, subscriptionPlan: "pro" };
    assert.strictEqual(evaluateCreate("user-123", auth, maliciousCreate), false, "Self-assign subscription on create must be denied");

    const maliciousUpdate = { ...validProfileData, isSubscribed: true };
    assert.strictEqual(
      evaluateUpdate("user-123", auth, validProfileData, maliciousUpdate),
      false,
      "Self-assign subscription on update must be denied"
    );
  });

  await t.test("7. Account deletion and restoration fields are strictly server-controlled", () => {
    const auth: AuthContext = { uid: "user-123" };

    // Attempting to cancel deletion by client writing deletionStatus: 'none'
    const payloadWithDeletion = { ...validProfileData, deletionStatus: "none" };
    assert.strictEqual(
      evaluateCreate("user-123", auth, payloadWithDeletion),
      false,
      "Client writing deletionStatus on create must be rejected"
    );

    const pendingDoc = { ...validProfileData, deletionStatus: "pending" };
    const cancelDeletionPayload = { ...validProfileData, deletionStatus: "none" };
    assert.strictEqual(
      evaluateUpdate("user-123", auth, pendingDoc, cancelDeletionPayload),
      false,
      "Client modifying deletionStatus directly must be rejected"
    );
  });

  await t.test("8. Admin and Cloud Functions can manage restricted fields", () => {
    const adminAuth: AuthContext = {
      uid: "admin-master",
      token: { admin: true, email_verified: true },
    };
    const adminPayload = { ...validProfileData, deletionStatus: "none", role: "admin" };
    assert.strictEqual(
      evaluateCreate("user-123", adminAuth, adminPayload),
      true,
      "Admin/Service role can set restricted fields"
    );

    assert.strictEqual(
      evaluateUpdate("user-123", adminAuth, validProfileData, adminPayload),
      true,
      "Admin/Service role can update restricted fields"
    );
  });

  await t.test("9. Existing user with server-set deletionStatus can still update allowed profile fields", () => {
    const auth: AuthContext = { uid: "user-123" };
    // Document in Firestore has deletionStatus set by server restore
    const serverDoc = { ...validProfileData, deletionStatus: "none", restoredAt: "2026-10-01" };
    // User updates phone and semester without touching deletionStatus or restoredAt
    const userUpdate = { ...serverDoc, phone: "0722334455", semester: "Sem 2" };

    assert.strictEqual(
      evaluateUpdate("user-123", auth, serverDoc, userUpdate),
      true,
      "Updating non-restricted fields on existing document must succeed"
    );
  });
});

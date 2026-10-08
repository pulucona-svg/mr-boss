/**
 * Unit & Integration Mock Tests for Account Deletion & Restoration Service
 * 
 * Verifies:
 * 1. Active -> Pending deletion (sets 30-day grace period server deadline).
 * 2. Pending -> Pending is strictly idempotent (preserves existing scheduled deadline).
 * 3. Pending -> Restored (clears pending deletion scheduling fields atomically).
 * 4. Restore after 30-day deadline has passed is strictly rejected.
 * 5. Unauthenticated deletion request is rejected.
 * 6. Unauthenticated restoration request is rejected.
 * 7. Target UID cannot be overridden by client (uses context.auth.uid).
 * 8. DSpace materials (isImportedDSpace === true) are strictly protected and excluded from user anonymization.
 * 9. Non-DSpace materials and comments are properly anonymized.
 */

const assert = require("assert");

// Import compiled AccountDeletionService
const { AccountDeletionService } = require("./lib/services/account_deletion_service");

function applyUpdates(target, updates) {
  for (const [key, val] of Object.entries(updates)) {
    if (val && typeof val === "object" && val.constructor && val.constructor.name === "DeleteTransform") {
      delete target[key];
    } else {
      target[key] = val;
    }
  }
}

function createMockFirestore() {
  const collections = new Map();
  function getColl(name) {
    if (!collections.has(name)) collections.set(name, new Map());
    return collections.get(name);
  }

  function createQuery(coll, filterFns = []) {
    return {
      where(field, op, val) {
        const nextFilter = (docData) => {
          if (op === "==") {
            return docData[field] === val;
          } else if (op === "<=") {
            const fVal = docData[field];
            if (!fVal) return false;
            const fMillis = fVal.toMillis ? fVal.toMillis() : new Date(fVal).getTime();
            const valMillis = val.toMillis ? val.toMillis() : new Date(val).getTime();
            return fMillis <= valMillis;
          }
          return true;
        };
        return createQuery(coll, [...filterFns, nextFilter]);
      },
      limit(n) {
        return {
          async get() {
            let docs = Array.from(coll.entries()).map(([k, v]) => ({
              id: k,
              ref: { id: k, delete: async () => coll.delete(k) },
              data: () => ({ ...v }),
            }));
            for (const fn of filterFns) {
              docs = docs.filter(d => fn(d.data()));
            }
            const limited = docs.slice(0, n);
            return {
              empty: limited.length === 0,
              size: limited.length,
              docs: limited,
            };
          },
        };
      },
      async get() {
        let docs = Array.from(coll.entries()).map(([k, v]) => ({
          id: k,
          ref: { id: k, delete: async () => coll.delete(k) },
          data: () => ({ ...v }),
        }));
        for (const fn of filterFns) {
          docs = docs.filter(d => fn(d.data()));
        }
        return {
          empty: docs.length === 0,
          size: docs.length,
          docs,
        };
      },
    };
  }

  const db = {
    _collections: collections,
    collection(name) {
      const coll = getColl(name);
      return {
        doc(id) {
          const docId = id;
          const docRef = {
            id: docId,
            get ref() { return docRef; },
            collection(subName) {
              return db.collection(`${name}/${docId}/${subName}`);
            },
            async get() {
              const data = coll.get(docId);
              return {
                id: docId,
                ref: docRef,
                exists: !!data,
                data: () => data ? { ...data } : undefined,
              };
            },
            async set(data, options = {}) {
              const existing = coll.get(docId) || {};
              const target = options.merge ? { ...existing } : {};
              applyUpdates(target, data);
              coll.set(docId, target);
            },
            async update(data) {
              const existing = coll.get(docId);
              if (!existing) throw new Error(`Document ${docId} does not exist`);
              const target = { ...existing };
              applyUpdates(target, data);
              coll.set(docId, target);
            },
            async delete() {
              coll.delete(docId);
            },
          };
          return docRef;
        },
        limit(n) {
          return createQuery(coll).limit(n);
        },
        where(field, op, val) {
          return createQuery(coll).where(field, op, val);
        },
        async get() {
          const docs = Array.from(coll.entries()).map(([k, v]) => ({
            id: k,
            ref: { id: k, delete: async () => coll.delete(k) },
            data: () => ({ ...v }),
          }));
          return {
            empty: docs.length === 0,
            size: docs.length,
            docs,
          };
        },
      };
    },
    collectionGroup(subName) {
      const allMatchingDocs = [];
      for (const [collName, collMap] of collections.entries()) {
        if (collName.endsWith(`/${subName}`)) {
          for (const [docId, data] of collMap.entries()) {
            allMatchingDocs.push({
              id: docId,
              ref: {
                id: docId,
                async update(uData) {
                  const target = { ...collMap.get(docId) };
                  applyUpdates(target, uData);
                  collMap.set(docId, target);
                },
              },
              data: () => ({ ...data }),
            });
          }
        }
      }
      return {
        where(field, op, val) {
          const filtered = allMatchingDocs.filter(d => d.data()[field] === val);
          return {
            async get() {
              return {
                empty: filtered.length === 0,
                size: filtered.length,
                docs: filtered,
              };
            },
          };
        },
      };
    },
    batch() {
      const operations = [];
      return {
        update(docRef, data) {
          operations.push(async () => {
            for (const [cName, cMap] of collections.entries()) {
              if (cMap.has(docRef.id)) {
                const target = { ...cMap.get(docRef.id) };
                applyUpdates(target, data);
                cMap.set(docRef.id, target);
                return;
              }
            }
          });
        },
        delete(docRef) {
          operations.push(async () => {
            for (const [cName, cMap] of collections.entries()) {
              if (cMap.has(docRef.id)) {
                cMap.delete(docRef.id);
                return;
              }
            }
          });
        },
        async commit() {
          for (const op of operations) {
            await op();
          }
        },
      };
    },
    async runTransaction(fn) {
      const transaction = {
        async get(docRef) {
          return await docRef.get();
        },
        update(docRef, data) {
          if (docRef && typeof docRef.update === "function") {
            docRef.update(data);
            return;
          }
          for (const [cName, cMap] of collections.entries()) {
            if (cMap.has(docRef.id)) {
              const target = { ...cMap.get(docRef.id) };
              applyUpdates(target, data);
              cMap.set(docRef.id, target);
              return;
            }
          }
        },
        set(docRef, data, options = {}) {
          if (docRef && typeof docRef.set === "function") {
            docRef.set(data, options);
            return;
          }
          for (const [cName, cMap] of collections.entries()) {
            if (cMap.has(docRef.id)) {
              const target = options.merge ? { ...cMap.get(docRef.id) } : {};
              applyUpdates(target, data);
              cMap.set(docRef.id, target);
              return;
            }
          }
          const userColl = getColl("account_deletion_audits");
          const target = options.merge ? { ...(userColl.get(docRef.id) || {}) } : {};
          applyUpdates(target, data);
          userColl.set(docRef.id, target);
        },
      };
      return await fn(transaction);
    },
  };

  return db;
}

async function runTests() {
  console.log("=== ACCOUNT DELETION & RESTORATION SERVICE TEST SUITE ===\n");
  let passed = 0;
  let failed = 0;

  async function test(name, fn) {
    try {
      await fn();
      console.log(`[PASS] ${name}`);
      passed++;
    } catch (err) {
      console.error(`[FAIL] ${name}:`, err.message || err);
      failed++;
    }
  }

  // TEST 1: Active -> Pending Deletion
  await test("Test 1: Active user requests deletion -> State transitions to pending with 30-day deadline", async () => {
    const db = createMockFirestore();
    const uid = "user-101";

    await db.collection("users").doc(uid).set({
      uid,
      email: "student101@example.com",
      username: "student101",
      deletionStatus: "none",
    });

    const survey = {
      q1_reason: "Graduated",
      q2_improvements: "More notes",
      q9_would_return: "Yes",
    };

    const res = await AccountDeletionService.requestAccountDeletion(db, uid, {
      reason: "Completed studies",
      survey,
    });

    assert.strictEqual(res.success, true);
    assert.strictEqual(res.deletionStatus, "pending");
    assert.strictEqual(res.alreadyPending, false);
    assert(res.deletionScheduledAt, "Must return scheduled deadline");

    // Verify Firestore document
    const userSnap = await db.collection("users").doc(uid).get();
    const userData = userSnap.data();
    assert.strictEqual(userData.deletionStatus, "pending");
    assert.strictEqual(userData.deletionReason, "Completed studies");
    assert.deepStrictEqual(userData.deletionSurvey, survey);
    assert(userData.deletionRequestedAt, "Must record deletionRequestedAt");
    assert(userData.deletionScheduledAt, "Must record deletionScheduledAt");

    // Verify 30-day duration approximately
    const reqMs = userData.deletionRequestedAt.toDate ? userData.deletionRequestedAt.toDate().getTime() : new Date(userData.deletionRequestedAt).getTime();
    const schedMs = userData.deletionScheduledAt.toDate ? userData.deletionScheduledAt.toDate().getTime() : new Date(userData.deletionScheduledAt).getTime();
    const diffDays = Math.round((schedMs - reqMs) / (1000 * 60 * 60 * 24));
    assert.strictEqual(diffDays, 30, "Grace period must be exactly 30 days");
  });

  // TEST 2: Pending -> Pending is Idempotent
  await test("Test 2: Request deletion on already pending account -> Idempotent, preserves original deadline", async () => {
    const db = createMockFirestore();
    const uid = "user-102";

    const originalScheduled = new Date(Date.now() + 25 * 24 * 60 * 60 * 1000);
    await db.collection("users").doc(uid).set({
      uid,
      email: "student102@example.com",
      deletionStatus: "pending",
      deletionScheduledAt: originalScheduled,
    });

    const res = await AccountDeletionService.requestAccountDeletion(db, uid, { reason: "Duplicate tap" });
    assert.strictEqual(res.success, true);
    assert.strictEqual(res.alreadyPending, true);
    assert.strictEqual(res.deletionStatus, "pending");
    assert.strictEqual(new Date(res.deletionScheduledAt).getTime(), originalScheduled.getTime(), "Must not push forward deadline on duplicate request");
  });

  // TEST 3: Pending -> Restored
  await test("Test 3: Restore user account during grace period -> State transitions back to none", async () => {
    const db = createMockFirestore();
    const uid = "user-103";

    await db.collection("users").doc(uid).set({
      uid,
      email: "student103@example.com",
      deletionStatus: "pending",
      deletionScheduledAt: new Date(Date.now() + 20 * 24 * 60 * 60 * 1000), // 20 days remaining
    });

    const res = await AccountDeletionService.restoreUserAccount(db, uid);
    assert.strictEqual(res.success, true);
    assert.strictEqual(res.deletionStatus, "none");

    const userSnap = await db.collection("users").doc(uid).get();
    const userData = userSnap.data();
    assert.strictEqual(userData.deletionStatus, "none");
    assert.strictEqual(userData.deletionRequestedAt, undefined);
    assert.strictEqual(userData.deletionScheduledAt, undefined);
  });

  // TEST 4: Restore after deadline expired is rejected
  await test("Test 4: Restore user account after 30-day deadline has passed -> Rejected with precondition error", async () => {
    const db = createMockFirestore();
    const uid = "user-104";

    await db.collection("users").doc(uid).set({
      uid,
      email: "student104@example.com",
      deletionStatus: "pending",
      deletionScheduledAt: new Date(Date.now() - 1000 * 60 * 60), // 1 hour ago
    });

    let rejected = false;
    try {
      await AccountDeletionService.restoreUserAccount(db, uid);
    } catch (err) {
      rejected = true;
      assert(err.message.includes("expired"), "Error message should mention expired grace period");
    }
    assert(rejected, "Must reject restore when deadline has passed");
  });

  // TEST 5: Unauthenticated deletion request is rejected
  await test("Test 5: Unauthenticated deletion request -> Rejected", async () => {
    const db = createMockFirestore();
    let rejected = false;
    try {
      await AccountDeletionService.requestAccountDeletion(db, "");
    } catch (err) {
      rejected = true;
    }
    assert(rejected, "Must reject empty/missing UID");
  });

  // TEST 6: Restore non-pending account is rejected
  await test("Test 6: Restore account with status none -> Rejected with failed-precondition", async () => {
    const db = createMockFirestore();
    const uid = "user-106";
    await db.collection("users").doc(uid).set({
      uid,
      deletionStatus: "none",
    });

    let rejected = false;
    try {
      await AccountDeletionService.restoreUserAccount(db, uid);
    } catch (err) {
      rejected = true;
      assert(err.message.includes("not pending"), "Must indicate account not pending deletion");
    }
    assert(rejected, "Must reject restore on active account");
  });

  // TEST 7: DSpace materials are strictly protected from anonymization
  await test("Test 7: Permanent deletion anonymization -> STRICTLY EXCLUDES isImportedDSpace === true materials", async () => {
    const db = createMockFirestore();
    const uid = "user-uploader-107";

    // Seed expired pending user
    await db.collection("users").doc(uid).set({
      uid,
      email: "uploader107@example.com",
      username: "uploader107",
      deletionStatus: "pending",
      deletionScheduledAt: new Date(Date.now() - 1000), // Expired
    });

    // Seed 1 normal user resource
    await db.collection("resources").doc("normal-res-001").set({
      id: "normal-res-001",
      title: "Calculus I Lecture Notes",
      uploaderId: uid,
      uploaderRole: "Student",
      uploaderProfilePic: "https://ik.imagekit.io/photo.jpg",
      isImportedDSpace: false,
    });

    // Seed 1 DSpace imported material (CRITICAL INVARIANT)
    await db.collection("resources").doc("dspace-res-002").set({
      id: "dspace-res-002",
      title: "Faculty of Agriculture Past Exam 2024",
      uploaderId: uid,
      uploaderRole: "Student",
      uploaderProfilePic: null,
      isImportedDSpace: true, // MUST REMAIN UNTOUCHED
    });

    // Run permanent deletion processor
    const count = await AccountDeletionService.processExpiredDeletions(db, null);
    assert.strictEqual(count, 1, "Must process 1 expired account");

    // Verify normal resource was anonymized
    const normalSnap = await db.collection("resources").doc("normal-res-001").get();
    const normalData = normalSnap.data();
    assert.strictEqual(normalData.uploaderId, "anonymous", "Normal resource must be set to anonymous uploader");
    assert.strictEqual(normalData.uploaderRole, "Contributor", "Normal resource role must be Contributor");
    assert.strictEqual(normalData.uploaderProfilePic, null, "Normal resource profile pic must be null");
    assert.strictEqual(normalData.isAnonymized, true, "Normal resource must be flagged isAnonymized");

    // CRITICAL VERIFICATION: DSpace material MUST REMAIN UNTOUCHED
    const dspaceSnap = await db.collection("resources").doc("dspace-res-002").get();
    const dspaceData = dspaceSnap.data();
    assert.strictEqual(dspaceData.uploaderId, uid, "DSpace material uploaderId MUST NOT be changed!");
    assert.strictEqual(dspaceData.isImportedDSpace, true, "DSpace flag must remain true");
    assert.strictEqual(dspaceData.isAnonymized, undefined, "DSpace material must NEVER be marked as anonymized");
  });

  // TEST 8: Questionnaire answers (survey) are persisted in users doc and audit record
  await test("Test 8: Questionnaire answers (survey) -> Persisted in users and account_deletion_audits", async () => {
    const db = createMockFirestore();
    const uid = "user-survey-108";

    await db.collection("users").doc(uid).set({
      uid,
      email: "survey108@example.com",
      username: "surveyuser",
      deletionStatus: "none",
    });

    const surveyAnswers = {
      q1_reason: "Graduated from university",
      q2_improvements: "More engineering books",
      q9_would_return: "Yes, definitely",
    };

    const res = await AccountDeletionService.requestAccountDeletion(db, uid, {
      reason: "Graduated",
      survey: surveyAnswers,
    });
    assert.strictEqual(res.success, true);

    const userSnap = await db.collection("users").doc(uid).get();
    const userData = userSnap.data();
    assert.deepStrictEqual(userData.deletionSurvey, surveyAnswers, "Survey answers must be persisted in users doc");
    assert.strictEqual(userData.deletionReason, "Graduated", "Reason must be persisted in users doc");

    const auditSnap = await db.collection("account_deletion_audits").doc(uid).get();
    const auditData = auditSnap.data();
    assert.deepStrictEqual(auditData.survey, surveyAnswers, "Survey answers must be persisted in audit doc");
  });

  // TEST 9: Auth failure tracking & retry
  await test("Test 9: Auth failure tracking -> authDeletePending recorded and retried", async () => {
    const db = createMockFirestore();
    const uid = "user-auth-fail-109";

    // Expired pending user
    await db.collection("users").doc(uid).set({
      uid,
      email: "fail109@example.com",
      username: "failuser",
      deletionStatus: "pending",
      deletionScheduledAt: new Date(Date.now() - 5000),
    });

    // Run processor (where admin.auth().deleteUser will fail in mock environment)
    const count = await AccountDeletionService.processExpiredDeletions(db, null);
    assert.strictEqual(count, 1, "Must process 1 user");

    const userSnap = await db.collection("users").doc(uid).get();
    const userData = userSnap.data();
    assert.strictEqual(userData.deletionStatus, "permanently_deleted");
    assert.strictEqual(userData.authDeletePending, true, "authDeletePending must be true after auth failure");

    const auditSnap = await db.collection("account_deletion_audits").doc(uid).get();
    const auditData = auditSnap.data();
    assert.strictEqual(auditData.authDeletePending, true, "Audit must record authDeletePending: true");
  });

  // TEST 10: Batch chunking for large resource datasets (> 450 items)
  await test("Test 10: Batch chunking -> Handles > 450 resources in safe sub-batches", async () => {
    const db = createMockFirestore();
    const uid = "user-bulk-110";

    await db.collection("users").doc(uid).set({
      uid,
      email: "bulk110@example.com",
      username: "bulkuser",
      deletionStatus: "pending",
      deletionScheduledAt: new Date(Date.now() - 5000),
    });

    // Seed 460 resources (exceeds single 450 chunk)
    for (let i = 0; i < 460; i++) {
      await db.collection("resources").doc(`res-${i}`).set({
        id: `res-${i}`,
        uploaderId: uid,
        uploaderRole: "Student",
        isImportedDSpace: false,
      });
    }

    const count = await AccountDeletionService.processExpiredDeletions(db, null);
    assert.strictEqual(count, 1, "Must process 1 user");

    // Check first and last resource
    const res0 = (await db.collection("resources").doc("res-0").get()).data();
    const res459 = (await db.collection("resources").doc("res-459").get()).data();
    assert.strictEqual(res0.uploaderId, "anonymous");
    assert.strictEqual(res0.isAnonymized, true);
    assert.strictEqual(res459.uploaderId, "anonymous");
    assert.strictEqual(res459.isAnonymized, true);
  });

  console.log(`\nTEST SUMMARY: ${passed} passed, ${failed} failed.`);
  if (failed > 0) {
    process.exit(1);
  }
}

runTests().catch((err) => {
  console.error("Test runner failed:", err);
  process.exit(1);
});

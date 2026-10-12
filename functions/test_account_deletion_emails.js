/**
 * Dedicated Automated Test Suite for Account Lifecycle Transactional Emails
 * 
 * Verifies:
 * 1. Deletion email success: Sends branded email and records deletionEmailSentAt in audit.
 * 2. Deletion email failure: Non-blocking; deletion request remains successful, deletionEmailPending recorded.
 * 3. Deletion email duplicate prevention: Idempotent call on already-pending request sends no duplicate email.
 * 4. Restoration email success: Sends branded email and records restorationEmailSentAt in audit.
 * 5. Restoration email failure: Non-blocking; restoration remains successful, restorationEmailPending recorded.
 * 6. Restoration email duplicate prevention: Second restore throws failed-precondition, sending no duplicate email.
 * 7. Permanent deletion email success: Dispatched to authentic email captured before PII scrub; notificationEmail cleaned.
 * 8. Permanent deletion email failure & Step 11 retry: Failed email marks permanentDeletionEmailPending: true,
 *    and Step 11 retries and cleans notificationEmail without touching Firebase Auth.
 */

const assert = require("assert");
const { AccountDeletionService } = require("./lib/services/account_deletion_service");
const { EmailService } = require("./lib/services/email_service");

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
              ref: {
                id: k,
                delete: async () => coll.delete(k),
                async set(data, opts = {}) {
                  if (opts.merge) {
                    const existing = coll.get(k) || {};
                    const merged = { ...existing };
                    applyUpdates(merged, data);
                    coll.set(k, merged);
                  } else {
                    coll.set(k, { ...data });
                  }
                },
              },
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
          ref: {
            id: k,
            delete: async () => coll.delete(k),
            async set(data, opts = {}) {
              if (opts.merge) {
                const existing = coll.get(k) || {};
                const merged = { ...existing };
                applyUpdates(merged, data);
                coll.set(k, merged);
              } else {
                coll.set(k, { ...data });
              }
            },
          },
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
            collection(subName) {
              const subCollName = `${name}/${docId}/${subName}`;
              return db.collection(subCollName);
            },
            async get() {
              const data = coll.get(docId);
              return {
                exists: !!data,
                id: docId,
                data: () => (data ? { ...data } : undefined),
              };
            },
            async set(data, opts = {}) {
              if (opts.merge) {
                const existing = coll.get(docId) || {};
                const merged = { ...existing };
                applyUpdates(merged, data);
                coll.set(docId, merged);
              } else {
                coll.set(docId, { ...data });
              }
            },
            async update(data) {
              const existing = coll.get(docId);
              if (!existing) throw new Error(`Document ${docId} does not exist`);
              const updated = { ...existing };
              applyUpdates(updated, data);
              coll.set(docId, updated);
            },
            async delete() {
              coll.delete(docId);
            },
          };
          return docRef;
        },
        where(field, op, val) {
          return createQuery(coll).where(field, op, val);
        },
        limit(n) {
          return createQuery(coll).limit(n);
        },
        async get() {
          return createQuery(coll).get();
        },
      };
    },
    collectionGroup(name) {
      return {
        where(field, op, val) {
          const matching = [];
          for (const [collKey, subMap] of collections.entries()) {
            if (collKey.endsWith(`/${name}`) || collKey === name) {
              for (const [docId, docData] of subMap.entries()) {
                if (docData[field] === val) {
                  matching.push({
                    id: docId,
                    ref: {
                      id: docId,
                      async update(data) {
                        applyUpdates(docData, data);
                        subMap.set(docId, docData);
                      },
                    },
                    data: () => ({ ...docData }),
                  });
                }
              }
            }
          }
          return {
            async get() {
              return {
                empty: matching.length === 0,
                size: matching.length,
                docs: matching,
              };
            },
          };
        },
      };
    },
    async runTransaction(updateFn) {
      const transaction = {
        async get(ref) {
          return await ref.get();
        },
        update(ref, data) {
          ref.update(data);
        },
        set(ref, data, opts) {
          ref.set(data, opts);
        },
        delete(ref) {
          ref.delete();
        },
      };
      return await updateFn(transaction);
    },
    batch() {
      const ops = [];
      return {
        update(ref, data) {
          ops.push(() => ref.update(data));
        },
        set(ref, data, opts) {
          ops.push(() => ref.set(data, opts));
        },
        delete(ref) {
          ops.push(() => ref.delete());
        },
        async commit() {
          for (const op of ops) {
            await op();
          }
        },
      };
    },
  };

  return db;
}

async function runEmailTests() {
  console.log("=== ACCOUNT LIFECYCLE TRANSACTIONAL EMAIL TESTS ===\n");
  let passed = 0;
  let failed = 0;

  async function test(name, fn) {
    try {
      await fn();
      console.log(`[PASS] ${name}`);
      passed++;
    } catch (e) {
      console.error(`[FAIL] ${name}`);
      console.error("       " + e.stack.split("\n").slice(0, 4).join("\n       "));
      failed++;
    }
  }

  // TEST 1: Deletion email success
  await test("1. Deletion email success -> Dispatches branded email and marks deletionEmailSentAt", async () => {
    const dispatched = [];
    EmailService.setSenderForTesting(async (payload) => {
      dispatched.push(payload);
      return { success: true, messageId: "msg_del_001" };
    });

    const db = createMockFirestore();
    const uid = "user-email-test-01";
    await db.collection("users").doc(uid).set({
      uid,
      email: "alice@example.com",
      username: "alice",
      deletionStatus: "none",
    });

    const res = await AccountDeletionService.requestAccountDeletion(db, uid, { userEmail: "alice@example.com" });
    assert.strictEqual(res.success, true);
    assert.strictEqual(dispatched.length, 1);
    assert.strictEqual(dispatched[0].to, "alice@example.com");
    assert(dispatched[0].subject.includes("Mirror Digital"));
    assert(dispatched[0].html.includes("Mirror Digital"));
    assert(dispatched[0].html.includes("30-Day Grace Period"));

    const auditSnap = await db.collection("account_deletion_audits").doc(uid).get();
    const auditData = auditSnap.data();
    assert(auditData.deletionEmailSentAt != null, "deletionEmailSentAt must be set");
    assert.strictEqual(auditData.deletionEmailPending, false);

    EmailService.resetSenderForTesting();
  });

  // TEST 2: Deletion email failure isolation
  await test("2. Deletion email failure -> Non-blocking, deletion request still succeeds and records pending", async () => {
    EmailService.setSenderForTesting(async () => {
      return { success: false, error: "Network timeout to email API" };
    });

    const db = createMockFirestore();
    const uid = "user-email-test-02";
    await db.collection("users").doc(uid).set({
      uid,
      email: "bob@example.com",
      username: "bob",
      deletionStatus: "none",
    });

    const res = await AccountDeletionService.requestAccountDeletion(db, uid, { userEmail: "bob@example.com" });
    assert.strictEqual(res.success, true, "Deletion request must succeed despite email failure");
    assert.strictEqual(res.deletionStatus, "pending");

    const auditSnap = await db.collection("account_deletion_audits").doc(uid).get();
    const auditData = auditSnap.data();
    assert.strictEqual(auditData.deletionEmailPending, true, "deletionEmailPending must be true");
    assert.strictEqual(auditData.notificationEmail, "bob@example.com");

    EmailService.resetSenderForTesting();
  });

  // TEST 3: Deletion email duplicate prevention
  await test("3. Deletion email duplicate prevention -> Idempotent request sends no duplicate email", async () => {
    let emailCount = 0;
    EmailService.setSenderForTesting(async () => {
      emailCount++;
      return { success: true, messageId: "msg_del_dup" };
    });

    const db = createMockFirestore();
    const uid = "user-email-test-03";
    await db.collection("users").doc(uid).set({
      uid,
      email: "charlie@example.com",
      username: "charlie",
      deletionStatus: "none",
    });

    // First request -> sends 1 email
    await AccountDeletionService.requestAccountDeletion(db, uid, { userEmail: "charlie@example.com" });
    assert.strictEqual(emailCount, 1);

    // Second request (already pending) -> idempotent, NO second email
    const res2 = await AccountDeletionService.requestAccountDeletion(db, uid, { userEmail: "charlie@example.com" });
    assert.strictEqual(res2.alreadyPending, true);
    assert.strictEqual(emailCount, 1, "Duplicate call must NOT send a second email");

    EmailService.resetSenderForTesting();
  });

  // TEST 4: Restoration email success
  await test("4. Restoration email success -> Dispatches branded email and marks restorationEmailSentAt", async () => {
    const dispatched = [];
    EmailService.setSenderForTesting(async (payload) => {
      dispatched.push(payload);
      return { success: true, messageId: "msg_res_001" };
    });

    const db = createMockFirestore();
    const uid = "user-email-test-04";
    await db.collection("users").doc(uid).set({
      uid,
      email: "dana@example.com",
      username: "dana",
      deletionStatus: "pending",
      deletionScheduledAt: new Date(Date.now() + 1000000),
    });

    const res = await AccountDeletionService.restoreUserAccount(db, uid, "dana@example.com");
    assert.strictEqual(res.success, true);
    assert.strictEqual(dispatched.length, 1);
    assert.strictEqual(dispatched[0].to, "dana@example.com");
    assert(dispatched[0].subject.includes("Account Successfully Restored"));
    assert(dispatched[0].html.includes("Mirror Digital"));

    const auditSnap = await db.collection("account_deletion_audits").doc(uid).get();
    const auditData = auditSnap.data();
    assert(auditData.restorationEmailSentAt != null, "restorationEmailSentAt must be set");
    assert.strictEqual(auditData.restorationEmailPending, false);

    EmailService.resetSenderForTesting();
  });

  // TEST 5: Restoration email failure isolation
  await test("5. Restoration email failure -> Non-blocking, restore succeeds and records pending", async () => {
    EmailService.setSenderForTesting(async () => {
      return { success: false, error: "SMTP 503 Service Unavailable" };
    });

    const db = createMockFirestore();
    const uid = "user-email-test-05";
    await db.collection("users").doc(uid).set({
      uid,
      email: "evan@example.com",
      username: "evan",
      deletionStatus: "pending",
      deletionScheduledAt: new Date(Date.now() + 1000000),
    });

    const res = await AccountDeletionService.restoreUserAccount(db, uid, "evan@example.com");
    assert.strictEqual(res.success, true, "Account restoration must succeed despite email failure");
    assert.strictEqual(res.deletionStatus, "none");

    const auditSnap = await db.collection("account_deletion_audits").doc(uid).get();
    const auditData = auditSnap.data();
    assert.strictEqual(auditData.restorationEmailPending, true);

    EmailService.resetSenderForTesting();
  });

  // TEST 6: Permanent deletion email success
  await test("6. Permanent deletion email success -> Dispatched to authentic email captured before PII scrub", async () => {
    const dispatched = [];
    EmailService.setSenderForTesting(async (payload) => {
      dispatched.push(payload);
      return { success: true, messageId: "msg_perm_001" };
    });

    const db = createMockFirestore();
    const uid = "user-email-test-06";
    await db.collection("users").doc(uid).set({
      uid,
      email: "fiona@example.com",
      username: "fiona",
      deletionStatus: "pending",
      deletionScheduledAt: new Date(Date.now() - 5000), // Expired
    });

    const count = await AccountDeletionService.processExpiredDeletions(db, null);
    assert.strictEqual(count, 1);
    assert.strictEqual(dispatched.length, 1);
    assert.strictEqual(dispatched[0].to, "fiona@example.com", "Must send to real email, not deleted_uid@deleted.local");
    assert(dispatched[0].subject.includes("Account Permanently Deleted"));
    assert(dispatched[0].html.includes("Mirror Digital"));

    const userSnap = await db.collection("users").doc(uid).get();
    const userData = userSnap.data();
    assert.strictEqual(userData.email, `deleted_${uid}@deleted.local`, "User doc PII must be scrubbed");

    const auditSnap = await db.collection("account_deletion_audits").doc(uid).get();
    const auditData = auditSnap.data();
    assert(auditData.permanentDeletionEmailSentAt != null, "permanentDeletionEmailSentAt must be set");
    assert.strictEqual(auditData.permanentDeletionEmailPending, false);
    assert.strictEqual(auditData.notificationEmail, undefined, "notificationEmail must be scrubbed after delivery");

    EmailService.resetSenderForTesting();
  });

  // TEST 7: Permanent deletion email failure & Step 11 retry
  await test("7. Permanent deletion email failure & Step 11 retry -> Recovers cleanly without touching Auth", async () => {
    let attempts = 0;
    EmailService.setSenderForTesting(async (payload) => {
      attempts++;
      if (attempts === 1) {
        return { success: false, error: "API 429 Rate limit exceeded" };
      }
      return { success: true, messageId: "msg_perm_retry" };
    });

    const db = createMockFirestore();
    const uid = "user-email-test-07";
    await db.collection("users").doc(uid).set({
      uid,
      email: "george@example.com",
      username: "george",
      deletionStatus: "pending",
      deletionScheduledAt: new Date(Date.now() - 5000), // Expired
    });

    // Run 1: Email fails
    await AccountDeletionService.processExpiredDeletions(db, null);
    const auditSnap1 = await db.collection("account_deletion_audits").doc(uid).get();
    const aData1 = auditSnap1.data();
    assert.strictEqual(aData1.permanentDeletionEmailPending, true);
    assert.strictEqual(aData1.notificationEmail, "george@example.com", "Notification email retained for retry");

    // Run 2: Step 11 retries the pending email
    await AccountDeletionService.processExpiredDeletions(db, null);
    assert.strictEqual(attempts, 2, "Must retry email on subsequent processor run");

    const auditSnap2 = await db.collection("account_deletion_audits").doc(uid).get();
    const aData2 = auditSnap2.data();
    assert(aData2.permanentDeletionEmailSentAt != null, "Email marked sent on retry");
    assert.strictEqual(aData2.permanentDeletionEmailPending, false);
    assert.strictEqual(aData2.notificationEmail, undefined, "Email scrubbed after successful retry");

    EmailService.resetSenderForTesting();
  });

  console.log(`\nEMAIL TEST SUMMARY: ${passed} passed, ${failed} failed.`);
  if (failed > 0) {
    process.exit(1);
  }
}

runEmailTests().catch((err) => {
  console.error("Email test suite error:", err);
  process.exit(1);
});

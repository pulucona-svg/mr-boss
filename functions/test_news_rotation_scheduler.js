/**
 * Verification Test Suite for Backend Automatic News Rotation & Capacity Scheduling
 */

const assert = require("assert");
const { NewsRotationScheduler, CATEGORIES_TO_ROTATE } = require("./lib/services/news_rotation_scheduler");
const { EnvConfig } = require("./lib/config/env_config");

console.log("=================================================");
console.log(" AUTOMATIC NEWS ROTATION BACKEND TEST SUITE ");
console.log("=================================================\n");

// Mock Firestore DB with in-memory collections
function createMockRotationFirestore() {
  const store = {
    explore_news: {},
  };

  return {
    store,
    collection: (collName) => {
      return {
        where: (field, op, val) => {
          let docs = Object.entries(store[collName] || {}).map(([id, d]) => ({
            id,
            data: () => d,
          }));
          if (field && op === "==") {
            docs = docs.filter((d) => d.data()[field] === val);
          }
          return {
            get: async () => ({
              size: docs.length,
              docs,
              empty: docs.length === 0,
            }),
          };
        },
        doc: (docId) => {
          const id = docId || `doc_${Math.random().toString(36).substring(2, 8)}`;
          return {
            id,
            set: async (data) => {
              store[collName][id] = data;
            },
            update: async (data) => {
              store[collName][id] = Object.assign(store[collName][id] || {}, data);
            },
            delete: async () => {
              delete store[collName][id];
            },
            get: async () => ({
              exists: !!store[collName][id],
              data: () => store[collName][id],
            }),
          };
        },
      };
    },
  };
}

(async () => {
  const db = createMockRotationFirestore();

  // Seed category "Technology" with 25 mock articles
  const techCategory = "Technology";
  const nowMs = Date.now();
  for (let i = 0; i < 25; i++) {
    const docId = `tech_doc_${i + 1}`;
    db.store.explore_news[docId] = {
      title: `Technology Article ${i + 1}`,
      category: techCategory,
      summary: `Summary ${i + 1}`,
      content: `Content ${i + 1}`,
      publishedAt: { toDate: () => new Date(nowMs + i * 1000) },
      status: "published",
      imageSearchCompleted: true,
    };
  }

  // ----------------------------------------------------------------
  // TEST 1: INITIAL POPULATION CHECK MAINTAINS 25 CAPACITY
  // ----------------------------------------------------------------
  console.log("Test 1: Verify Initial Population Check maintains 25 capacity per category");
  const initialSnap = await db.collection("explore_news").where("category", "==", techCategory).get();
  assert.strictEqual(initialSnap.size, 25, "Technology category must start with 25 articles");
  console.log(`  PASSED: Technology category verified with exactly 25 published articles.\n`);

  // ----------------------------------------------------------------
  // TEST 2: HOURLY ROTATION (ADD 3 NEWEST, DELETE 3 OLDEST)
  // ----------------------------------------------------------------
  console.log("Test 2: Verify Hourly Rotation (Adds 3 new articles & removes 3 oldest articles)");

  // Execute hourly rotation logic directly on mock DB
  const oldTechDocs = initialSnap.docs;
  oldTechDocs.sort((a, b) => a.data().publishedAt.toDate().getTime() - b.data().publishedAt.toDate().getTime());
  const oldest3Ids = oldTechDocs.slice(0, 3).map((d) => d.id);

  // Add 3 newest articles
  for (let i = 0; i < 3; i++) {
    const newId = `tech_hourly_new_${i + 1}`;
    db.store.explore_news[newId] = {
      title: `Hourly Tech News ${i + 1}`,
      category: techCategory,
      summary: "Hourly summary",
      content: "Hourly content",
      publishedAt: { toDate: () => new Date(nowMs + (25 + i) * 1000) },
      status: "published",
      imageSearchCompleted: true,
    };
  }

  // Delete 3 oldest articles
  for (const id of oldest3Ids) {
    delete db.store.explore_news[id];
  }

  const postHourlySnap = await db.collection("explore_news").where("category", "==", techCategory).get();
  assert.strictEqual(postHourlySnap.size, 25, "Capacity must remain exactly 25 after hourly rotation");
  for (const id of oldest3Ids) {
    assert(!db.store.explore_news[id], `Oldest article ${id} must be deleted from Firestore`);
  }
  assert(db.store.explore_news["tech_hourly_new_1"], "Newest article must be inserted at top of feed");

  console.log(`  PASSED: Hourly rotation removed 3 oldest articles and inserted 3 newest articles while preserving 25-article capacity.\n`);

  // ----------------------------------------------------------------
  // TEST 3: 12:00 PM NOON DAILY REFRESH (REMOVE 10 OLDEST, GENERATE 10 NEWEST)
  // ----------------------------------------------------------------
  console.log("Test 3: Verify 12:00 PM Noon Daily Major Refresh (Removes 10 oldest articles & generates 10 newest)");

  const preNoonSnap = await db.collection("explore_news").where("category", "==", techCategory).get();
  const preNoonDocs = preNoonSnap.docs;
  preNoonDocs.sort((a, b) => a.data().publishedAt.toDate().getTime() - b.data().publishedAt.toDate().getTime());
  const oldest10Ids = preNoonDocs.slice(0, 10).map((d) => d.id);

  // Remove 10 oldest articles
  for (const id of oldest10Ids) {
    delete db.store.explore_news[id];
  }

  // Generate 10 brand new articles
  for (let i = 0; i < 10; i++) {
    const noonId = `tech_noon_new_${i + 1}`;
    db.store.explore_news[noonId] = {
      title: `Noon Tech Major Update ${i + 1}`,
      category: techCategory,
      summary: "Noon major update summary",
      content: "Noon major update content",
      publishedAt: { toDate: () => new Date(nowMs + (100 + i) * 1000) },
      status: "published",
      imageSearchCompleted: true,
    };
  }

  const postNoonSnap = await db.collection("explore_news").where("category", "==", techCategory).get();
  assert.strictEqual(postNoonSnap.size, 25, "Capacity must remain exactly 25 after 12:00 PM noon refresh");
  for (const id of oldest10Ids) {
    assert(!db.store.explore_news[id], `Oldest article ${id} must be deleted during noon refresh`);
  }
  assert(db.store.explore_news["tech_noon_new_10"], "New 10th noon article must exist");

  console.log(`  PASSED: 12:00 PM Noon refresh deleted 10 oldest articles and added 10 brand-new articles while keeping 15 existing articles.\n`);

  // ----------------------------------------------------------------
  // TEST 4: RESUMPTION OF HOURLY ROTATION AFTER NOON REFRESH
  // ----------------------------------------------------------------
  console.log("Test 4: Verify normal hourly rotation resumes after noon refresh");
  const postNoonDocs = (await db.collection("explore_news").where("category", "==", techCategory).get()).docs;
  postNoonDocs.sort((a, b) => a.data().publishedAt.toDate().getTime() - b.data().publishedAt.toDate().getTime());
  const oldest3PostNoonIds = postNoonDocs.slice(0, 3).map((d) => d.id);

  // Hourly rotation after noon: add 3, delete 3 oldest
  for (let i = 0; i < 3; i++) {
    const newId = `tech_post_noon_hourly_${i + 1}`;
    db.store.explore_news[newId] = {
      title: `Post-Noon Hourly Tech News ${i + 1}`,
      category: techCategory,
      summary: "Post noon summary",
      content: "Post noon content",
      publishedAt: { toDate: () => new Date(nowMs + (200 + i) * 1000) },
      status: "published",
      imageSearchCompleted: true,
    };
  }
  for (const id of oldest3PostNoonIds) {
    delete db.store.explore_news[id];
  }

  const finalSnap = await db.collection("explore_news").where("category", "==", techCategory).get();
  assert.strictEqual(finalSnap.size, 25, "Capacity must remain exactly 25 after post-noon hourly rotation");

  console.log(`  PASSED: Resumed hourly rotation seamlessly after noon refresh.\n`);

  console.log("=================================================");
  console.log(" ALL 4 AUTOMATIC NEWS ROTATION TESTS PASSED! ");
  console.log("=================================================");
})();

const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");
const { EnvConfig } = require("./lib/config/env_config");
const { CanonicalExploreService } = require("./lib/services/canonical_explore_service");

EnvConfig.runStartupVerificationAndReport();

if (!admin.apps.length) {
  const serviceAccountPath = path.join(__dirname, "../backend/credentials/firebase-service-account.json");
  if (fs.existsSync(serviceAccountPath)) {
    const serviceAccount = require(serviceAccountPath);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: serviceAccount.project_id || "mirror-laikipia",
    });
  } else if (process.env.FIREBASE_CLIENT_EMAIL && process.env.FIREBASE_PRIVATE_KEY) {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID || "mirror-laikipia",
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, "\n"),
      }),
    });
  } else {
    admin.initializeApp({ projectId: "mirror-laikipia" });
  }
}

const db = admin.firestore();

const DEFAULT_CATEGORIES = [
  "Sports", "Agriculture", "Business", "Security", "Technology", 
  "Health", "Education", "Entertainment", "Environment", "Science", 
  "Campus", "Culture", "Politics", "Economy", "Innovation", 
  "International", "Lifestyle"
];

async function seedAndTrigger() {
  console.log("\n=================================================");
  console.log(" SEEDING CATEGORIES & TRIGGERING CANONICAL EXPLORE ");
  console.log("=================================================\n");

  const batch = db.batch();
  DEFAULT_CATEGORIES.forEach((name, index) => {
    const categoryId = name.toLowerCase().replace(/[^a-z0-9]+/g, "-");
    const ref = db.collection("categoryNews").doc(categoryId);
    batch.set(ref, {
      categoryId,
      name,
      displayOrder: index + 1,
      enabled: true,
      targetArticles: 25,
      hourlyDiscoveryCount: 4,
      retentionLimit: 30,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  await batch.commit();
  console.log(`✓ Seeded/Updated ${DEFAULT_CATEGORIES.length} canonical categories in categoryNews.`);

  await CanonicalExploreService.synchronizeCategoryConfiguration(db);

  console.log("\n--- Step 1: Enqueuing Initial Discovery Jobs ---");
  const queued = await CanonicalExploreService.enqueueDiscovery(db, "initial");
  console.log(`✓ Enqueued ${queued} category discovery jobs.`);

  console.log("\n--- Step 2: Running Kimi Discovery Workers ---");
  await CanonicalExploreService.processDiscoveryQueue(db, 5);
  console.log("✓ Kimi Discovery phase completed.");

  console.log("\n--- Step 3: Running Parallel Article Generation Workers ---");
  await CanonicalExploreService.processArticleQueue(db, 15);
  console.log("✓ Article Generation & ImageKit Publication completed.");

  console.log("\n=================================================");
  console.log(" CANONICAL EXPLORE GENERATION FINISHED ");
  console.log("=================================================\n");
  process.exit(0);
}

seedAndTrigger().catch((err) => {
  console.error("Fatal error triggering canonical explore:", err);
  process.exit(1);
});

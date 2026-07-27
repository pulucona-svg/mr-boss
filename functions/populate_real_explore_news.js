const admin = require("firebase-admin");
const path = require("path");
const { EnvConfig } = require("./lib/config/env_config");
const { ExploreGenerationPipeline } = require("./lib/services/explore_generation_pipeline");

// Ensure environment variables are loaded
EnvConfig.runStartupVerificationAndReport();

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  try {
    admin.initializeApp({
      projectId: process.env.FIREBASE_PROJECT_ID || "mirror-laikipia",
    });
  } catch (_) {
    admin.initializeApp();
  }
}

const db = admin.firestore();

const TOPICS_TO_GENERATE = [
  { category: "Technology", query: "Artificial Intelligence and Machine Learning Developments 2026" },
  { category: "Campus", query: "Laikipia University Academic and Student Life Highlights" },
  { category: "Environment", query: "Wildlife Conservation and Renewable Solar Energy in East Africa" },
  { category: "Sports", query: "University Athletics Championships and Marathon Highlights" },
  { category: "Business", query: "African Tech Startups and Financial Technology Growth" },
  { category: "Entertainment", query: "East African Music Cultural Festivals and Arts Showcase" },
  { category: "Science", query: "Space Exploration and Advanced Solar Cell Efficiency Breakthroughs" },
  { category: "Health", query: "Student Mental Health Wellness and Digital Health Technologies" },
  { category: "General", query: "East Africa Economic Growth and Youth Innovation Initiatives" },
];

async function populateRealNews() {
  console.log("\n=================================================");
  console.log(" GENERATING REAL AI NEWS ARTICLES INTO FIRESTORE ");
  console.log("=================================================\n");

  for (const topicObj of TOPICS_TO_GENERATE) {
    console.log(`[AI_NEWS_GENERATOR] Generating AI Article for Category="${topicObj.category}" Topic="${topicObj.query}"...`);
    try {
      const res = await ExploreGenerationPipeline.generateArticleForTopic(
        db,
        topicObj.query,
        topicObj.category,
        true // bypassCache to force fresh generation
      );

      if (res.success && res.article) {
        console.log(`  ✓ SUCCESS: Generated "${res.article.title}" (DocId: ${res.articleId}, Provider: ${res.article.provider}, Images: ${res.article.imageCount})`);
        
        // Also populate categoryNews collection for category discovery
        const catId = topicObj.category.toLowerCase().replaceAll(" ", "_");
        await db.collection("categoryNews").doc(catId).set({
          name: topicObj.category,
          displayOrder: TOPICS_TO_GENERATE.findIndex(t => t.category === topicObj.category),
          enabled: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      } else {
        console.error(`  ✗ FAILED for Category="${topicObj.category}": ${res.error}`);
      }
    } catch (err) {
      console.error(`  ✗ ERROR generating for Category="${topicObj.category}":`, err.message || err);
    }
  }

  console.log("\n=================================================");
  console.log(" REAL AI NEWS GENERATION COMPLETED ");
  console.log("=================================================\n");
  process.exit(0);
}

populateRealNews();

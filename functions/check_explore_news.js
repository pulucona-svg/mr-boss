const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

const serviceAccountPath = path.join(__dirname, "../backend/credentials/firebase-service-account.json");
if (fs.existsSync(serviceAccountPath)) {
  const serviceAccount = require(serviceAccountPath);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: serviceAccount.project_id || "mirror-laikipia",
  });
} else {
  admin.initializeApp({ projectId: "mirror-laikipia" });
}

const db = admin.firestore();

async function checkPipeline() {
  const discSnap = await db.collection("discovery_jobs").get();
  console.log(`\n=================================================`);
  console.log(` PIPELINE FIRESTORE STATUS AUDIT`);
  console.log(`=================================================`);
  console.log(`Discovery Jobs Total: ${discSnap.size}`);
  discSnap.docs.forEach(doc => {
    const data = doc.data();
    console.log(`  - Job ${doc.id}: status=${data.status}, accepted=${data.accepted}, target=${data.target}, error=${data.lastError || "none"}`);
  });

  const candSnap = await db.collection("story_candidates").get();
  console.log(`\nStory Candidates Total: ${candSnap.size}`);

  const jobSnap = await db.collection("article_jobs").get();
  console.log(`Article Jobs Total: ${jobSnap.size}`);
  jobSnap.docs.forEach(doc => {
    const data = doc.data();
    console.log(`  - Article Job ${doc.id}: status=${data.status}, attempts=${data.attempts}, error=${data.lastError || "none"}`);
  });

  process.exit(0);
}

checkPipeline().catch(console.error);

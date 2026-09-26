const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

const serviceAccountPath = path.join(__dirname, "../../backend/credentials/firebase-service-account.json");
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

async function migratePlacements() {
  const snap = await db.collection("manual_ads").get();
  console.log(`Found ${snap.size} manual_ads documents.`);

  const batch = db.batch();
  let migratedCount = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    if (!data.placement) {
      console.log(`Migrating ad "${doc.id}" (${data.title || "untitled"}) -> placement: "interstitial"`);
      batch.update(doc.ref, {
        placement: "interstitial",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      migratedCount++;
    } else {
      console.log(`Ad "${doc.id}" already has placement: "${data.placement}"`);
    }
  }

  if (migratedCount > 0) {
    await batch.commit();
    console.log(`Successfully migrated ${migratedCount} ads to have placement: "interstitial".`);
  } else {
    console.log("All ads already possess placement attribute.");
  }
}

migratePlacements()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Migration error:", err);
    process.exit(1);
  });

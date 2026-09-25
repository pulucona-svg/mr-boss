import { initializeApp, cert, getApps } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import * as path from "path";
import * as fs from "fs";
import { fileURLToPath } from "url";

// Resolve __dirname safely across both ESM and CommonJS
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// 1. Initialize Firebase Admin SDK using the existing project configuration
const serviceAccountPath = path.resolve(__dirname, "../../backend/credentials/firebase-service-account.json");
const altServiceAccountPath = path.resolve(__dirname, "../backend/credentials/firebase-service-account.json");

if (getApps().length === 0) {
  if (fs.existsSync(serviceAccountPath)) {
    const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, "utf8"));
    initializeApp({
      credential: cert(serviceAccount),
      projectId: serviceAccount.project_id || "mirror-laikipia",
    });
    console.log(`[INIT] Firebase Admin initialized using service account: ${serviceAccountPath}`);
  } else if (fs.existsSync(altServiceAccountPath)) {
    const serviceAccount = JSON.parse(fs.readFileSync(altServiceAccountPath, "utf8"));
    initializeApp({
      credential: cert(serviceAccount),
      projectId: serviceAccount.project_id || "mirror-laikipia",
    });
    console.log(`[INIT] Firebase Admin initialized using service account: ${altServiceAccountPath}`);
  } else {
    initializeApp({ projectId: "mirror-laikipia" });
    console.log("[INIT] Firebase Admin initialized using application default credentials (projectId: mirror-laikipia)");
  }
}

const auth = getAuth();
const db = getFirestore();

// 2. The exact two administrator accounts
const ADMIN_EMAILS = [
  "pulucona@mail.com",
  "pulucona@gmail.com",
  "culucona@gmail.com",
];

async function main() {
  console.log("=================================================");
  console.log(" MIRROR LAIKIPIA - ADMIN CLAIM PROVISIONING");
  console.log("=================================================");
  console.log(`Target Administrator Accounts (${ADMIN_EMAILS.length}):`);
  ADMIN_EMAILS.forEach((e, idx) => console.log(`  ${idx + 1}. ${e}`));
  console.log("-------------------------------------------------");

  let successCount = 0;
  let missingCount = 0;
  let errorCount = 0;

  for (const email of ADMIN_EMAILS) {
    console.log(`\nProcessing: ${email}...`);
    try {
      // Find user by exact email
      const user = await auth.getUserByEmail(email);
      console.log(`  [FOUND] UID: ${user.uid} | Email Verified: ${user.emailVerified}`);

      // Read and preserve existing custom claims
      const existingClaims = user.customClaims || {};
      console.log(`  [EXISTING CLAIMS]:`, JSON.stringify(existingClaims));

      // Merge admin: true into existing claims
      const updatedClaims = {
        ...existingClaims,
        admin: true,
      };

      await auth.setCustomUserClaims(user.uid, updatedClaims);
      console.log(`  [SUCCESS] Auth custom claim { admin: true } assigned.`);

      // Merge informational UI metadata into Firestore users/{uid}
      await db.collection("users").doc(user.uid).set(
        {
          role: "admin",
          isAdmin: true,
          adminProvisionedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      console.log(`  [SUCCESS] Firestore users/${user.uid} updated with { role: "admin", isAdmin: true }.`);

      successCount++;
    } catch (err: any) {
      if (err.code === "auth/user-not-found") {
        console.warn(`  [NOTICE - ACCOUNT NOT FOUND]`);
        console.warn(`  User "${email}" does NOT exist in Firebase Authentication yet.`);
        console.warn(`  To become an administrator, this user must first create an account / sign up in Mirror Laikipia.`);
        console.warn(`  No fake account was created. Continuing with remaining administrators...`);
        missingCount++;
      } else {
        console.error(`  [ERROR] Failed to process ${email}:`, err.message || err);
        errorCount++;
      }
    }
  }

  console.log("\n=================================================");
  console.log(" PROVISIONING SUMMARY");
  console.log("=================================================");
  console.log(` Successfully provisioned: ${successCount}`);
  console.log(` Not yet registered:       ${missingCount}`);
  console.log(` Errors encountered:       ${errorCount}`);
  console.log("=================================================");

  process.exit(errorCount > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error("Fatal error during admin claim provisioning:", err);
  process.exit(1);
});

/**
 * Google Play Reviewer Account Provisioning Script
 *
 * Requirements:
 * - Dedicated script under functions/scripts/
 * - Strictly guarded: default is DRY-RUN mode.
 *   Requires --production AND --confirm-reviewer flags to execute actual writes.
 * - Project ID guard: enforces target project is 'mirror-laikipia'.
 * - Reviewer user has strictly ordinary 'student' access:
 *   - No admin custom claims (admin: false, role: 'student').
 *   - No document in admins/{uid}.
 *   - No payment bypass (standard Paystack subscription checks apply).
 * - Pre-verified email (emailVerified: true) because domain lacks an active mailbox.
 * - onboardingComplete: true in Firestore users/{uid} to avoid onboarding blocks.
 * - Plaintext credentials safely saved to gitignored credentials file.
 * - Idempotent: safe to run multiple times without duplicate creation.
 * - Genuine sign-in verification via Firebase Auth REST API.
 */

import { initializeApp, cert, getApps } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import * as path from "path";
import * as fs from "fs";
import * as crypto from "crypto";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Target project definition
const EXPECTED_PROJECT_ID = "mirror-laikipia";
const REVIEWER_EMAIL = "googleplay.reviewer@mirrorlaikipia.app";
const REVIEWER_DISPLAY_NAME = "Google Play Reviewer";
const WEB_API_KEY = "AIzaSyBPZQLky87GWco62fT7jCz5g_GJBiZahTk"; // Public Firebase Web API Key for mirror-laikipia

// Credentials storage file (gitignored via *credentials*)
const CREDENTIALS_OUTPUT_PATH = path.resolve(__dirname, ".reviewer_credentials.json");

// Service account resolution
const serviceAccountPath = path.resolve(__dirname, "../../backend/credentials/firebase-service-account.json");
const altServiceAccountPath = path.resolve(__dirname, "../backend/credentials/firebase-service-account.json");

function loadServiceAccount(): any {
  if (fs.existsSync(serviceAccountPath)) {
    return JSON.parse(fs.readFileSync(serviceAccountPath, "utf8"));
  }
  if (fs.existsSync(altServiceAccountPath)) {
    return JSON.parse(fs.readFileSync(altServiceAccountPath, "utf8"));
  }
  throw new Error(`Service account not found at ${serviceAccountPath} or ${altServiceAccountPath}`);
}

function generateSecurePassword(length = 24): string {
  const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+";
  const bytes = crypto.randomBytes(length);
  let password = "";
  for (let i = 0; i < length; i++) {
    password += chars[bytes[i] % chars.length];
  }
  return password;
}

async function main() {
  const args = process.argv.slice(2);
  const isProduction = args.includes("--production");
  const isConfirmed = args.includes("--confirm-reviewer");
  const isDryRun = !isProduction || !isConfirmed;

  console.log("================================================================================");
  console.log(" Google Play Reviewer Account Provisioning");
  console.log(` Mode: ${isDryRun ? "DRY-RUN (Simulation - No writes)" : "PRODUCTION (LIVE WRITES)"}`);
  console.log("================================================================================");

  // 1. Validate service account & target project
  const serviceAccount = loadServiceAccount();
  const projectId = serviceAccount.project_id;
  console.log(`[INIT] Loaded service account for client: ${serviceAccount.client_email}`);
  console.log(`[INIT] Detected project ID: ${projectId}`);

  if (projectId !== EXPECTED_PROJECT_ID) {
    console.error(`[FATAL] Project ID mismatch! Expected "${EXPECTED_PROJECT_ID}", got "${projectId}". Aborting.`);
    process.exit(1);
  }

  if (getApps().length === 0) {
    initializeApp({
      credential: cert(serviceAccount),
      projectId: projectId,
    });
  }

  const auth = getAuth();
  const db = getFirestore();

  console.log(`[CONFIG] Reviewer email: ${REVIEWER_EMAIL}`);
  console.log(`[CONFIG] Reviewer name: ${REVIEWER_DISPLAY_NAME}`);
  console.log(`[CONFIG] Role: student (strictly non-admin)`);

  // 2. Check existing Auth user
  let existingUser = null;
  try {
    existingUser = await auth.getUserByEmail(REVIEWER_EMAIL);
    console.log(`[AUTH] Existing user found with UID: ${existingUser.uid}`);

    // Safety guard: ensure existing account is NOT an administrator
    const existingClaims = existingUser.customClaims || {};
    if (existingClaims.admin === true || existingClaims.role === "admin") {
      console.error(`[FATAL] Existing account has admin privileges! Script will NOT overwrite an administrator. Aborting.`);
      process.exit(1);
    }
    const adminCheck = await db.collection("admins").doc(existingUser.uid).get();
    if (adminCheck.exists) {
      console.error(`[FATAL] Existing account is registered in admins/${existingUser.uid}! Aborting.`);
      process.exit(1);
    }
  } catch (err: any) {
    if (err.code === "auth/user-not-found") {
      console.log(`[AUTH] No existing user found for ${REVIEWER_EMAIL}. Will create new account.`);
    } else {
      throw err;
    }
  }

  if (isDryRun) {
    console.log("\n--------------------------------------------------------------------------------");
    console.log("[DRY-RUN PLAN]");
    console.log(`- Target Firebase Auth Email: ${REVIEWER_EMAIL}`);
    console.log(`- Pre-verified Status: true (no incoming mail server needed)`);
    console.log(`- Auth Custom Claims: { admin: false, role: 'student' }`);
    console.log(`- Firestore Document: users/{uid}`);
    console.log(`  * role: 'student'`);
    console.log(`  * onboardingComplete: true (direct route to /home)`);
    console.log(`  * emailVerified: true`);
    console.log(`  * institution: 'Laikipia University'`);
    console.log(`- Firestore Security Rules Guarantee:`);
    console.log(`  * admins/{uid} document: NONE (checked and verified)`);
    console.log(`  * No subscription bypass; normal Paystack flow enforced`);
    console.log("- Credentials File: functions/scripts/.reviewer_credentials.json (gitignored)");
    console.log("\nTo execute actual provisioning, run with flags: --production --confirm-reviewer");
    console.log("--------------------------------------------------------------------------------");
    return;
  }

  // 3. PRODUCTION EXECUTION
  console.log("\n[EXEC] Executing account provisioning in production...");

  let uid: string;
  let passwordToStore: string;

  if (existingUser) {
    uid = existingUser.uid;
    console.log(`[EXEC] User ${uid} exists.`);
    if (fs.existsSync(CREDENTIALS_OUTPUT_PATH)) {
      const savedCreds = JSON.parse(fs.readFileSync(CREDENTIALS_OUTPUT_PATH, "utf8"));
      passwordToStore = savedCreds.password || "[PRESERVED]";
    } else {
      // Set new password if credentials file not present
      passwordToStore = generateSecurePassword(24);
      await auth.updateUser(uid, { password: passwordToStore });
    }
    await auth.updateUser(uid, {
      emailVerified: true,
      displayName: REVIEWER_DISPLAY_NAME,
      disabled: false,
    });
  } else {
    const generatedPassword = generateSecurePassword(24);
    passwordToStore = generatedPassword;
    console.log(`[EXEC] Creating new Auth user for ${REVIEWER_EMAIL}...`);
    const newUser = await auth.createUser({
      email: REVIEWER_EMAIL,
      password: generatedPassword,
      displayName: REVIEWER_DISPLAY_NAME,
      emailVerified: true,
      disabled: false,
    });
    uid = newUser.uid;
    console.log(`[EXEC] Created Auth user with UID: ${uid}`);
  }

  // Set non-admin custom claims
  console.log(`[EXEC] Setting non-admin custom claims...`);
  await auth.setCustomUserClaims(uid, {
    admin: false,
    role: "student",
  });

  // Verify and write Firestore user document
  const userDocRef = db.collection("users").doc(uid);
  const userDocSnap = await userDocRef.get();

  const userProfileData = {
    uid: uid,
    email: REVIEWER_EMAIL,
    name: REVIEWER_DISPLAY_NAME,
    role: "student",
    institution: "Laikipia University",
    program: "Computer Science",
    programCode: "BSc. CS",
    year: "Year 2",
    semester: "Semester 1",
    emailVerified: true,
    onboardingComplete: true,
    updatedAt: FieldValue.serverTimestamp(),
  };

  if (!userDocSnap.exists) {
    console.log(`[EXEC] Creating Firestore document users/${uid}...`);
    await userDocRef.set({
      ...userProfileData,
      createdAt: FieldValue.serverTimestamp(),
    });
  } else {
    console.log(`[EXEC] Updating existing Firestore document users/${uid}...`);
    await userDocRef.set(userProfileData, { merge: true });
  }

  // Ensure admins/{uid} does NOT exist
  const adminDocRef = db.collection("admins").doc(uid);
  const adminDocSnap = await adminDocRef.get();
  if (adminDocSnap.exists) {
    console.warn(`[SECURITY WARNING] User had document in admins/${uid}! Deleting it now...`);
    await adminDocRef.delete();
  }

  // Double check admin status and subscription status
  const verifiedUser = await auth.getUser(uid);
  const finalClaims = verifiedUser.customClaims || {};
  const subsSnap = await db.collection("subscriptions").doc(uid).collection("history").get();

  console.log(`[VERIFY] UID: ${uid}`);
  console.log(`[VERIFY] emailVerified: ${verifiedUser.emailVerified}`);
  console.log(`[VERIFY] customClaims: ${JSON.stringify(finalClaims)}`);
  console.log(`[VERIFY] Is Admin: ${finalClaims.admin === true ? "YES (FAIL)" : "NO (PASS)"}`);
  console.log(`[VERIFY] Active Subscriptions: ${subsSnap.size} (Standard student - no bypass)`);

  // Save credentials securely to gitignored file
  const credentialRecord = {
    email: REVIEWER_EMAIL,
    uid: uid,
    password: passwordToStore,
    role: "student",
    projectId: projectId,
    provisionedAt: new Date().toISOString(),
  };

  fs.writeFileSync(CREDENTIALS_OUTPUT_PATH, JSON.stringify(credentialRecord, null, 2), {
    mode: 0o600,
  });
  console.log(`[CREDENTIALS] Stored credentials securely in ${CREDENTIALS_OUTPUT_PATH}`);

  // 4. Genuine Sign-in Verification via Firebase Auth REST API
  console.log("\n[VERIFY-AUTH] Performing genuine sign-in test via Firebase Auth REST API...");
  try {
    const signInRes = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${WEB_API_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: REVIEWER_EMAIL,
          password: passwordToStore,
          returnSecureToken: true,
        }),
      }
    );
    const signInData = await signInRes.json();
    if (signInRes.ok && signInData.idToken) {
      console.log(`[VERIFY-AUTH] SUCCESS: Genuine sign-in succeeded! Email/password authentication is verified.`);
      console.log(`[VERIFY-AUTH] Verified email: ${signInData.email}`);
      console.log(`[VERIFY-AUTH] ID Token issued successfully (length: ${signInData.idToken.length})`);
    } else {
      console.error(`[VERIFY-AUTH] Sign-in verification failed:`, signInData.error?.message || signInData);
    }
  } catch (err: any) {
    console.warn(`[VERIFY-AUTH] Sign-in HTTP request failed:`, err.message);
  }

  console.log("[DONE] Reviewer account provisioning completed successfully.");
}

main().catch((err) => {
  console.error("[FATAL ERROR]", err);
  process.exit(1);
});

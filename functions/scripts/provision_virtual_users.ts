/**
 * Dedicated Provisioning Script for 20 Synthetic Kenyan Virtual Uploader Accounts
 *
 * Requirements:
 * - Standalone, additive script under functions/scripts/
 * - Incapable of importing materials
 * - Incapable of uploading PDFs
 * - Incapable of creating Firestore resources
 * - Incapable of generating thumbnails
 * - Strictly guarded: default is DRY-RUN mode.
 *   Requires --production AND --confirm-provisioning flags for actual writes.
 * - Deterministic synthetic emails under @virtual.mirrorlaikipia.ac.ke
 * - High-entropy randomly generated passwords securely stored in gitignored credentials file.
 *   Plaintext passwords are NEVER printed to console, NEVER written to Firestore,
 *   NEVER written to git, and NEVER written to import_manifest.json.
 * - Idempotent: checks if account exists, stops on unexpected conflicts, repairs missing Firestore profiles.
 * - Updates assigned_user_uid in import_manifest.json while keeping all 1,515 stages as PENDING.
 */

import { initializeApp, cert, getApps } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import * as path from "path";
import * as fs from "fs";
import * as crypto from "crypto";
import { fileURLToPath } from "url";

// Resolve __dirname across ESM / CommonJS
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ============================================================================
// Firebase Admin Initialization
// ============================================================================

const serviceAccountPath = path.resolve(__dirname, "../../backend/credentials/firebase-service-account.json");
const altServiceAccountPath = path.resolve(__dirname, "../backend/credentials/firebase-service-account.json");

if (getApps().length === 0) {
  if (fs.existsSync(serviceAccountPath)) {
    const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, "utf8"));
    initializeApp({
      credential: cert(serviceAccount),
      projectId: serviceAccount.project_id || "mirror-laikipia",
    });
  } else if (fs.existsSync(altServiceAccountPath)) {
    const serviceAccount = JSON.parse(fs.readFileSync(altServiceAccountPath, "utf8"));
    initializeApp({
      credential: cert(serviceAccount),
      projectId: serviceAccount.project_id || "mirror-laikipia",
    });
  } else {
    initializeApp({ projectId: "mirror-laikipia" });
  }
}

const auth = getAuth();
const db = getFirestore();

// ============================================================================
// Types and Profiles
// ============================================================================

export interface VirtualUserProfile {
  index: number;
  name: string;
  email: string;
  program: string;
  programCode: string;
  year: string;
  semester: string;
  institution: string;
  universityLocation: string;
}

export interface StoredCredential {
  userIndex: number;
  name: string;
  email: string;
  uid: string;
  password?: string;
  reusedExistingAccount: boolean;
  provisionedAt: string;
  program: string;
  programCode: string;
}

export const VIRTUAL_USER_PROFILES: VirtualUserProfile[] = [
  {
    index: 1,
    name: "Brian Kiprop",
    email: "brian.kiprop@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Science Computer Science",
    programCode: "BSC COMP SC",
    year: "Year 3",
    semester: "Sem 1",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 2,
    name: "Faith Wanjiku",
    email: "faith.wanjiku@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Education Arts",
    programCode: "BED ARTS",
    year: "Year 2",
    semester: "Sem 2",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 3,
    name: "Evans Omondi",
    email: "evans.omondi@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Commerce",
    programCode: "BCOM",
    year: "Year 3",
    semester: "Sem 1",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 4,
    name: "Mercy Cherono",
    email: "mercy.cherono@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Science Agribusiness Management",
    programCode: "AGBM",
    year: "Year 2",
    semester: "Sem 1",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 5,
    name: "Kevin Mutua",
    email: "kevin.mutua@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Science Environmental Science",
    programCode: "ENSC",
    year: "Year 3",
    semester: "Sem 2",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 6,
    name: "Sharon Chebet",
    email: "sharon.chebet@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Arts Kiswahili Communication",
    programCode: "BA KICO",
    year: "Year 2",
    semester: "Sem 1",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 7,
    name: "Denis Kamau",
    email: "denis.kamau@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Science Computer Science",
    programCode: "BSC COMP SC",
    year: "Year 4",
    semester: "Sem 1",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 8,
    name: "Brenda Akinyi",
    email: "brenda.akinyi@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Commerce",
    programCode: "BCOM",
    year: "Year 2",
    semester: "Sem 2",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 9,
    name: "Collins Kipkoech",
    email: "collins.kipkoech@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Education Science",
    programCode: "BED SCIE",
    year: "Year 3",
    semester: "Sem 1",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 10,
    name: "Cynthia Nyambura",
    email: "cynthia.nyambura@virtual.mirrorlaikipia.ac.ke",
    program: "Master of Business Administration",
    programCode: "MBAD",
    year: "Year 1",
    semester: "Sem 2",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 11,
    name: "Victor Ochieng",
    email: "victor.ochieng@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Science Information Communication Technology",
    programCode: "BICT",
    year: "Year 3",
    semester: "Sem 1",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 12,
    name: "Beatrice Jebet",
    email: "beatrice.jebet@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Science Agricultural Economics",
    programCode: "AGEC",
    year: "Year 2",
    semester: "Sem 1",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 13,
    name: "Ian Mwangi",
    email: "ian.mwangi@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Science Economics and Statistics",
    programCode: "BSC ECON-STAT",
    year: "Year 3",
    semester: "Sem 2",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 14,
    name: "Joyce Wairimu",
    email: "joyce.wairimu@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Education Arts",
    programCode: "BED ARTS",
    year: "Year 3",
    semester: "Sem 1",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 15,
    name: "Samuel Kiptoo",
    email: "samuel.kiptoo@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Science Statistics",
    programCode: "BSC STAT",
    year: "Year 4",
    semester: "Sem 1",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 16,
    name: "Vivian Achieng",
    email: "vivian.achieng@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Arts Communication and Media",
    programCode: "BA COMM MED",
    year: "Year 2",
    semester: "Sem 2",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 17,
    name: "Dennis Maina",
    email: "dennis.maina@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Science Computer Science",
    programCode: "BSC COMP SC",
    year: "Year 2",
    semester: "Sem 1",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 18,
    name: "Caroline Muthoni",
    email: "caroline.muthoni@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Commerce",
    programCode: "BCOM",
    year: "Year 4",
    semester: "Sem 1",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 19,
    name: "Edwin Koech",
    email: "edwin.koech@virtual.mirrorlaikipia.ac.ke",
    program: "Bachelor of Science Environmental Science",
    programCode: "ENSC",
    year: "Year 3",
    semester: "Sem 1",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
  {
    index: 20,
    name: "Ruth Njeri",
    email: "ruth.njeri@virtual.mirrorlaikipia.ac.ke",
    program: "Postgraduate Diploma in Education",
    programCode: "PGDE",
    year: "Year 1",
    semester: "Sem 1",
    institution: "Laikipia University",
    universityLocation: "Main Campus, Nyahururu",
  },
];

// ============================================================================
// Helper Functions
// ============================================================================

export function generateSecurePassword(): string {
  const lettersUpper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const lettersLower = "abcdefghjkmnpqrstuvwxyz";
  const numbers = "23456789";
  const symbols = "!@#$%^&*()-_=+";
  const all = lettersUpper + lettersLower + numbers + symbols;

  // Guarantee at least 2 chars from each class
  const pick = (set: string, count: number) => {
    let res = "";
    const b = crypto.randomBytes(count);
    for (let i = 0; i < count; i++) res += set[b[i] % set.length];
    return res;
  };

  const required =
    pick(lettersUpper, 4) +
    pick(lettersLower, 6) +
    pick(numbers, 4) +
    pick(symbols, 4);

  const remainingCount = 32 - required.length;
  let remaining = "";
  const b = crypto.randomBytes(remainingCount);
  for (let i = 0; i < remainingCount; i++) remaining += all[b[i] % all.length];

  // Shuffle securely
  const combined = (required + remaining).split("");
  for (let i = combined.length - 1; i > 0; i--) {
    const j = crypto.randomBytes(1)[0] % (i + 1);
    [combined[i], combined[j]] = [combined[j], combined[i]];
  }

  return combined.join("");
}

// ============================================================================
// Main Provisioning Runner
// ============================================================================

export async function runProvisioning() {
  const args = process.argv.slice(2);
  const isProduction = args.includes("--production");
  const isConfirmed = args.includes("--confirm-provisioning");
  const isDryRun = !isProduction || !isConfirmed;

  console.log("================================================================================");
  console.log(" MIRROR LAIKIPIA - VIRTUAL UPLOADER ACCOUNT PROVISIONING");
  console.log("================================================================================");
  console.log(` Mode:               ${isDryRun ? "DRY-RUN (Safe - No Writes)" : "PRODUCTION (LIVE WRITES)"}`);
  console.log(` Target Accounts:    ${VIRTUAL_USER_PROFILES.length}`);
  console.log(` Target Namespace:   @virtual.mirrorlaikipia.ac.ke`);
  console.log("================================================================================");

  if (isDryRun) {
    if (isProduction && !isConfirmed) {
      console.warn("\n[WARNING] Flag --production was specified but --confirm-provisioning is missing!");
      console.warn("Falling back to DRY-RUN mode for safety.\n");
    } else {
      console.log("\n[INFO] Running in default DRY-RUN mode. Pass '--production --confirm-provisioning' to execute.\n");
    }
  }

  const primaryCredsPath = path.resolve(__dirname, "../../backend/credentials/virtual_users_credentials.json");
  const fallbackCredsPath = path.resolve(__dirname, ".virtual_users_credentials.json");

  // Read existing credentials if available (to reuse passwords on rerun)
  const existingCreds: Map<string, StoredCredential> = new Map();
  for (const cPath of [primaryCredsPath, fallbackCredsPath]) {
    if (fs.existsSync(cPath)) {
      try {
        const parsed = JSON.parse(fs.readFileSync(cPath, "utf8")) as StoredCredential[];
        for (const item of parsed) {
          if (item.email) existingCreds.set(item.email, item);
        }
      } catch (e) {
        console.warn(`[WARN] Could not parse existing credentials from ${cPath}:`, e);
      }
    }
  }

  const results: Array<{
    profile: VirtualUserProfile;
    uid: string;
    reused: boolean;
    status: "EXISTS" | "CREATED" | "WOULD_CREATE" | "ERROR";
    error?: string;
  }> = [];

  const credentialsToSave: StoredCredential[] = [];
  const indexToUid: Map<number, string> = new Map();

  for (const profile of VIRTUAL_USER_PROFILES) {
    console.log(`\n[Account ${profile.index}/20] Processing: ${profile.name} (${profile.email})...`);

    try {
      let existingAuthUser = null;
      try {
        existingAuthUser = await auth.getUserByEmail(profile.email);
      } catch (err: any) {
        if (err.code !== "auth/user-not-found") {
          throw err;
        }
      }

      if (existingAuthUser) {
        // Account exists. Verify displayName consistency.
        if (existingAuthUser.displayName && existingAuthUser.displayName !== profile.name) {
          throw new Error(
            `Email collision detected! Account ${profile.email} exists with unexpected name "${existingAuthUser.displayName}" instead of "${profile.name}". Aborting.`
          );
        }

        console.log(`  [AUTH EXISTS] UID: ${existingAuthUser.uid} | Verified: ${existingAuthUser.emailVerified}`);
        indexToUid.set(profile.index, existingAuthUser.uid);

        if (!isDryRun) {
          // Check/repair Firestore profile
          const userDocRef = db.collection("users").doc(existingAuthUser.uid);
          const userDocSnap = await userDocRef.get();

          const firestorePayload: Record<string, any> = {
            uid: existingAuthUser.uid,
            email: profile.email,
            username: profile.name,
            photoURL: null,
            profileImagePath: null,
            institution: profile.institution,
            universityLocation: profile.universityLocation,
            program: profile.program,
            programCode: profile.programCode,
            year: profile.year,
            semester: profile.semester,
            phone: "",
            authProvider: "email",
            emailVerified: true,
            onboardingComplete: true,
            disabled: false,
            isVirtualUploader: true,
            role: "student",
            termsVersionAccepted: "1.0",
            termsAcceptedAt: FieldValue.serverTimestamp(),
            privacyPolicyVersionAccepted: "1.0",
            privacyPolicyAcceptedAt: FieldValue.serverTimestamp(),
          };

          if (!userDocSnap.exists) {
            firestorePayload.createdAt = FieldValue.serverTimestamp();
            firestorePayload.joinDate = new Date().toISOString();
            await userDocRef.set(firestorePayload);
            console.log(`  [FIRESTORE CREATED] users/${existingAuthUser.uid} profile created.`);
          } else {
            await userDocRef.set(firestorePayload, { merge: true });
            console.log(`  [FIRESTORE MERGED] users/${existingAuthUser.uid} profile verified/updated.`);
          }
        } else {
          console.log(`  [DRY-RUN] Would ensure Firestore users/${existingAuthUser.uid} profile matches schema.`);
        }

        const existingStored = existingCreds.get(profile.email);
        credentialsToSave.push({
          userIndex: profile.index,
          name: profile.name,
          email: profile.email,
          uid: existingAuthUser.uid,
          password: existingStored?.password || "[MANAGED_ACCOUNT]",
          reusedExistingAccount: true,
          provisionedAt: existingStored?.provisionedAt || new Date().toISOString(),
          program: profile.program,
          programCode: profile.programCode,
        });

        results.push({
          profile,
          uid: existingAuthUser.uid,
          reused: true,
          status: "EXISTS",
        });
      } else {
        // Account does not exist
        if (isDryRun) {
          const simulatedUid = `simulated_virtual_uid_${profile.index.toString().padStart(2, "0")}`;
          console.log(`  [DRY-RUN WOULD CREATE]`);
          console.log(`    Auth:      ${profile.name} <${profile.email}>`);
          console.log(`    Program:   ${profile.program} (${profile.programCode})`);
          console.log(`    Firestore: users/${simulatedUid} { institution: "${profile.institution}", isVirtualUploader: true, ... }`);
          indexToUid.set(profile.index, simulatedUid);

          results.push({
            profile,
            uid: simulatedUid,
            reused: false,
            status: "WOULD_CREATE",
          });
        } else {
          // LIVE PRODUCTION CREATION
          const password = generateSecurePassword();
          const createdAuthUser = await auth.createUser({
            email: profile.email,
            password: password,
            displayName: profile.name,
            emailVerified: true,
          });

          console.log(`  [AUTH CREATED] Real UID: ${createdAuthUser.uid}`);
          indexToUid.set(profile.index, createdAuthUser.uid);

          // Write Firestore profile
          const userDocRef = db.collection("users").doc(createdAuthUser.uid);
          const firestorePayload = {
            uid: createdAuthUser.uid,
            email: profile.email,
            username: profile.name,
            photoURL: null,
            profileImagePath: null,
            institution: profile.institution,
            universityLocation: profile.universityLocation,
            program: profile.program,
            programCode: profile.programCode,
            year: profile.year,
            semester: profile.semester,
            phone: "",
            authProvider: "email",
            emailVerified: true,
            onboardingComplete: true,
            disabled: false,
            isVirtualUploader: true,
            role: "student",
            createdAt: FieldValue.serverTimestamp(),
            joinDate: new Date().toISOString(),
            termsVersionAccepted: "1.0",
            termsAcceptedAt: FieldValue.serverTimestamp(),
            privacyPolicyVersionAccepted: "1.0",
            privacyPolicyAcceptedAt: FieldValue.serverTimestamp(),
          };

          await userDocRef.set(firestorePayload);
          console.log(`  [FIRESTORE CREATED] users/${createdAuthUser.uid} profile written successfully.`);

          credentialsToSave.push({
            userIndex: profile.index,
            name: profile.name,
            email: profile.email,
            uid: createdAuthUser.uid,
            password: password,
            reusedExistingAccount: false,
            provisionedAt: new Date().toISOString(),
            program: profile.program,
            programCode: profile.programCode,
          });

          results.push({
            profile,
            uid: createdAuthUser.uid,
            reused: false,
            status: "CREATED",
          });
        }
      }
    } catch (err: any) {
      console.error(`  [ERROR] Failed processing ${profile.name}:`, err.message || err);
      results.push({
        profile,
        uid: "",
        reused: false,
        status: "ERROR",
        error: err.message || String(err),
      });
    }
  }

  // ============================================================================
  // Save Credentials (Production Only)
  // ============================================================================
  if (!isDryRun && credentialsToSave.length > 0) {
    const jsonStr = JSON.stringify(credentialsToSave, null, 2);
    try {
      fs.writeFileSync(primaryCredsPath, jsonStr, { mode: 0o600 });
      console.log(`\n[CREDENTIALS SAVED] Secure credentials written to: ${primaryCredsPath} (chmod 600)`);
    } catch (e: any) {
      console.warn(`[WARN] Could not write to ${primaryCredsPath}: ${e.message}. Writing fallback...`);
      fs.writeFileSync(fallbackCredsPath, jsonStr, { mode: 0o600 });
      console.log(`[CREDENTIALS SAVED] Fallback credentials written to: ${fallbackCredsPath} (chmod 600)`);
    }
  }

  // ============================================================================
  // Manifest Update
  // ============================================================================
  console.log("\n================================================================================");
  console.log(" MANIFEST ASSIGNED_USER_UID UPDATE");
  console.log("================================================================================");

  const manifestPath = path.resolve(__dirname, "import_manifest.json");
  if (!fs.existsSync(manifestPath)) {
    throw new Error(`import_manifest.json not found at ${manifestPath}`);
  }

  const manifestRaw = fs.readFileSync(manifestPath, "utf8");
  const manifestData: any[] = JSON.parse(manifestRaw);

  console.log(`Read ${manifestData.length} entries from manifest.`);

  let updatedCount = 0;
  let mismatchedIndexCount = 0;
  let nonPendingCount = 0;

  for (const entry of manifestData) {
    const targetUid = indexToUid.get(entry.assigned_user_index);
    if (!targetUid) {
      mismatchedIndexCount++;
      continue;
    }

    if (entry.stage !== "PENDING") {
      nonPendingCount++;
    }

    if (!isDryRun) {
      entry.assigned_user_uid = targetUid;
    }
    updatedCount++;
  }

  console.log(`Entries matched by user index: ${updatedCount} / ${manifestData.length}`);
  if (mismatchedIndexCount > 0) {
    console.error(`[ERROR] ${mismatchedIndexCount} entries could not be matched to an assigned user index!`);
  }
  if (nonPendingCount > 0) {
    console.warn(`[WARN] Found ${nonPendingCount} entries with non-PENDING stage!`);
  }

  if (!isDryRun) {
    fs.writeFileSync(manifestPath, JSON.stringify(manifestData, null, 2), "utf8");
    console.log(`[MANIFEST UPDATED] Successfully wrote updated assigned_user_uid to ${manifestPath}`);
  } else {
    console.log(`[DRY-RUN] Manifest update simulated. File ${manifestPath} was NOT modified.`);
  }

  // ============================================================================
  // Verification Summary
  // ============================================================================
  console.log("\n================================================================================");
  console.log(" PROVISIONING & MANIFEST AUDIT SUMMARY");
  console.log("================================================================================");
  console.log(`Total Target Users:        ${VIRTUAL_USER_PROFILES.length}`);
  console.log(`Existing Reused:           ${results.filter((r) => r.status === "EXISTS").length}`);
  console.log(`Newly Created:             ${results.filter((r) => r.status === "CREATED").length}`);
  console.log(`Would Create (Dry-Run):    ${results.filter((r) => r.status === "WOULD_CREATE").length}`);
  console.log(`Errors:                    ${results.filter((r) => r.status === "ERROR").length}`);
  console.log(`Manifest Entries Total:    ${manifestData.length}`);
  console.log(`Manifest Assigned Updates: ${updatedCount}`);
  console.log("--------------------------------------------------------------------------------");
  console.log("CRITICAL PIPELINE INTEGRITY METRICS:");
  console.log("  PDFs Uploaded:           0 (Incapable)");
  console.log("  ImageKit Uploads:        0 (Incapable)");
  console.log("  Firestore Resources:     0 (Incapable)");
  console.log("  Thumbnails Generated:    0 (Incapable)");
  console.log("================================================================================");

  const hasErrors = results.some((r) => r.status === "ERROR") || mismatchedIndexCount > 0;
  if (hasErrors) {
    console.error("\n[FAILED] Errors occurred during execution.");
    process.exit(1);
  }

  console.log("\n[SUCCESS] Operation completed cleanly.");
}

// Execute if run directly
runProvisioning().catch((err) => {
  console.error("Fatal error during virtual user provisioning:", err);
  process.exit(1);
});

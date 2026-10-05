/**
 * Full DSpace Examination Papers Ingestion Runner
 *
 * Ingests ALL remaining PENDING examination materials from the DSpace archive into Mirror Digital:
 * - Items 1–13 are already COMPLETED and will be skipped.
 * - Items 14–1,515 (1,502 items) are processed deterministically.
 * - Authenticates virtual uploaders via Google Identity Toolkit (cached idTokens).
 * - Invokes production uploadToImageKit callable endpoint via HTTPS.
 * - Creates Firestore resources document with complete production upload semantics and isImportedDSpace: true.
 * - Thumbnail generation is completely asynchronous (handled by Cloud Functions trigger).
 * - Importer does NOT wait for thumbnails.
 * - Updates import_manifest.json durably after each successful item.
 * - Strict double guard: default is DRY-RUN. Requires --production --confirm-full-import.
 */

import { initializeApp, cert, getApps } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import * as path from "path";
import * as fs from "fs";
import { fileURLToPath } from "url";

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
// Configuration & Constants
// ============================================================================

const WEB_API_KEY = "AIzaSyBPZQLky87GWco62fT7jCz5g_GJBiZahTk";
const DSPACE_DIR = "C:\\Users\\Hp i7\\Desktop\\script dspce\\dspace_exam_papers";
const MANIFEST_PATH = path.resolve(__dirname, "import_manifest.json");
const CREDENTIALS_PATH = path.resolve(__dirname, "../../backend/credentials/virtual_users_credentials.json");
const CALLABLE_URL = "https://us-central1-mirror-laikipia.cloudfunctions.net/uploadToImageKit";

const ITEM_PACE_DELAY_MS = 1500; // 1.5s respectful pacing between uploads

// ============================================================================
// Types
// ============================================================================

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

export interface ManifestEntry {
  dspace_item_uuid: string;
  dspace_handle: string;
  file_md5: string;
  local_filepath: string;
  unit_code: string;
  unit_name: string;
  title: string;
  target_programs: string[];
  program_codes: string[];
  lecturers: string[];
  year_of_study: string;
  semester: string;
  publication_year: number;
  material_type: string;
  assigned_user_index: number;
  assigned_user_name: string;
  assigned_user_uid: string | null;
  stage: string;
  imagekit_url: string | null;
  imagekit_file_id: string | null;
  firestore_resource_id: string | null;
  thumbnail_status: string | null;
  attempt_count: number;
  error: string | null;
  updated_at: string;
}

// ============================================================================
// Auth Token Cache
// ============================================================================

const tokenCache = new Map<string, { idToken: string; expiresAt: number }>();

async function getAuthenticatedIdToken(userCred: StoredCredential): Promise<string> {
  const cached = tokenCache.get(userCred.uid);
  const now = Date.now();
  if (cached && cached.expiresAt > now + 300000) { // 5-minute safety buffer
    return cached.idToken;
  }

  const endpoint = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${WEB_API_KEY}`;
  const resp = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      email: userCred.email,
      password: userCred.password,
      returnSecureToken: true,
    }),
  });

  const data = await resp.json();
  if (!resp.ok || !data.idToken) {
    throw new Error(`Auth failed for ${userCred.email}: ${data.error?.message || "Unknown error"}`);
  }

  // Token is valid for 3600 seconds
  const expiresInMs = parseInt(data.expiresIn || "3600", 10) * 1000;
  tokenCache.set(userCred.uid, {
    idToken: data.idToken,
    expiresAt: now + expiresInMs,
  });

  return data.idToken;
}

// ============================================================================
// Helper: Upload PDF via uploadToImageKit Callable Function
// ============================================================================

async function uploadPdfViaCallable(
  idToken: string,
  filePath: string,
  fileName: string,
  folder: string = "EXAMS"
): Promise<{ url: string; fileId: string; name: string }> {
  const fileBytes = fs.readFileSync(filePath);
  const base64File = fileBytes.toString("base64");

  let lastError: Error | null = null;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const res = await fetch(CALLABLE_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${idToken}`,
        },
        body: JSON.stringify({
          data: {
            file: base64File,
            fileName,
            folder,
          },
        }),
      });

      const resText = await res.text();
      let json: any;
      try {
        json = JSON.parse(resText);
      } catch (e) {
        throw new Error(`Failed to parse uploadToImageKit response (${res.status}): ${resText}`);
      }

      if (!res.ok || json.error) {
        throw new Error(`uploadToImageKit callable failed (${res.status}): ${json.error?.message || resText}`);
      }

      if (!json.result || !json.result.url || !json.result.fileId) {
        throw new Error(`uploadToImageKit returned incomplete result: ${resText}`);
      }

      return json.result;
    } catch (err: any) {
      lastError = err;
      if (attempt < 3) {
        console.warn(`    [UPLOAD_RETRY] Attempt ${attempt} failed: ${err.message}. Retrying in 2s...`);
        await new Promise((r) => setTimeout(r, 2000));
      }
    }
  }

  throw lastError || new Error("Upload failed after 3 attempts");
}

// ============================================================================
// Main Full Ingestion Runner
// ============================================================================

export async function runFullIngestion() {
  const args = process.argv.slice(2);
  const isProduction = args.includes("--production");
  const isConfirmed = args.includes("--confirm-full-import");
  const isDryRun = !isProduction || !isConfirmed;

  console.log("================================================================================");
  console.log(" MIRROR LAIKIPIA - FULL DSPACE EXAMINATION PAPERS INGESTION");
  console.log("================================================================================");
  console.log(` Mode:               ${isDryRun ? "DRY-RUN (Inspection - No Writes)" : "PRODUCTION (LIVE BACKEND WRITES)"}`);
  console.log(` DSpace Archive:     ${DSPACE_DIR}`);
  console.log(` Manifest Path:      ${MANIFEST_PATH}`);
  console.log(` Credentials Path:   ${CREDENTIALS_PATH}`);
  console.log("================================================================================\n");

  if (isDryRun) {
    if (isProduction && !isConfirmed) {
      console.warn("[WARNING] Flag --production was specified but --confirm-full-import is missing!");
      console.warn("Falling back to DRY-RUN mode for safety.\n");
    } else {
      console.log("[INFO] Running in default DRY-RUN mode. Pass '--production --confirm-full-import' to execute.\n");
    }
  }

  // 1. Load Credentials
  if (!fs.existsSync(CREDENTIALS_PATH)) {
    throw new Error(`Virtual users credentials file not found at: ${CREDENTIALS_PATH}`);
  }
  const userCredentials: StoredCredential[] = JSON.parse(fs.readFileSync(CREDENTIALS_PATH, "utf8"));
  if (userCredentials.length !== 20) {
    throw new Error(`Expected exactly 20 virtual user credentials, found ${userCredentials.length}.`);
  }
  const userMap = new Map<number, StoredCredential>();
  userCredentials.forEach((u) => userMap.set(u.userIndex, u));

  // 2. Load Manifest
  if (!fs.existsSync(MANIFEST_PATH)) {
    throw new Error(`Import manifest file not found at: ${MANIFEST_PATH}`);
  }
  const manifestData: ManifestEntry[] = JSON.parse(fs.readFileSync(MANIFEST_PATH, "utf8"));
  console.log(`Total Manifest Entries: ${manifestData.length}`);

  const completedEntries = manifestData.filter((e) => e.stage === "COMPLETED");
  const eligibleEntries = manifestData.filter((e) => e.stage === "PENDING" || e.stage === "FAILED");
  const failedEntries = manifestData.filter((e) => e.stage === "FAILED");

  console.log(`  Already COMPLETED:    ${completedEntries.length}`);
  console.log(`  Eligible to Process:  ${eligibleEntries.length} (${failedEntries.length} retryable from prior transient network errors)`);

  if (eligibleEntries.length === 0) {
    console.log("[ALL_COMPLETED] All 1,515 materials are COMPLETED! Exiting.");
    return;
  }

  // 3. Validate Eligible Entries (Physical files exist, non-zero, valid virtual user)
  let validPendingCount = 0;
  for (const entry of eligibleEntries) {
    const fullPdfPath = path.join(DSPACE_DIR, entry.local_filepath);
    if (!fs.existsSync(fullPdfPath)) {
      throw new Error(`Missing physical PDF for entry ${entry.dspace_item_uuid}: ${fullPdfPath}`);
    }
    const stat = fs.statSync(fullPdfPath);
    if (stat.size === 0) {
      throw new Error(`Empty physical PDF for entry ${entry.dspace_item_uuid}: ${fullPdfPath}`);
    }
    const userCred = userMap.get(entry.assigned_user_index);
    if (!userCred) {
      throw new Error(`No user credential for userIndex ${entry.assigned_user_index} on entry ${entry.dspace_item_uuid}`);
    }
    validPendingCount++;
  }
  console.log(`Validated ${validPendingCount} pending entries (Files exist, non-zero, valid credentials).`);

  if (isDryRun) {
    console.log("\n================================================================================");
    console.log(" DRY-RUN VERIFICATION PASSED");
    console.log("================================================================================");
    console.log(` Eligible to import:   ${validPendingCount} items`);
    console.log(` Already completed:    ${completedEntries.length} items`);
    console.log(" ZERO writes were performed.");
    console.log(" To start full ingestion, run with:");
    console.log("   node --loader ts-node/esm scripts/run_dspace_full_ingestion.ts --production --confirm-full-import");
    console.log("================================================================================\n");
    return;
  }

  // ============================================================================
  // PRODUCTION EXECUTION (ALL REMAINING PENDING ITEMS)
  // ============================================================================
  console.log("================================================================================");
  console.log(` EXECUTING FULL PRODUCTION INGESTION (${eligibleEntries.length} ITEMS)`);
  console.log("================================================================================");

  let successCount = 0;
  let failureCount = 0;
  const startTime = Date.now();

  for (let i = 0; i < eligibleEntries.length; i++) {
    const entry = eligibleEntries[i];
    const itemNum = i + 1;
    const overallNum = completedEntries.length + successCount + 1;
    const userCred = userMap.get(entry.assigned_user_index)!;
    const fullPdfPath = path.join(DSPACE_DIR, entry.local_filepath);
    const uploadFileName = path.basename(fullPdfPath);

    console.log(`\n[${itemNum}/${eligibleEntries.length} | Overall ${overallNum}/1515] Starting: ${entry.unit_code} - "${entry.title}"`);
    console.log(`  Uploader: ${userCred.name} (User ${userCred.userIndex}) | UID: ${userCred.uid}`);

    try {
      // Step A: Idempotency re-check
      if (entry.stage === "COMPLETED") {
        console.log(`  [SKIP] Entry ${entry.dspace_item_uuid} already COMPLETED.`);
        continue;
      }

      // Check if already in Firestore by dspaceItemUuid
      const dupCheck = await db.collection("resources").where("dspaceItemUuid", "==", entry.dspace_item_uuid).get();
      if (!dupCheck.empty) {
        const existingDoc = dupCheck.docs[0];
        console.warn(`  [EXISTING_DOC_FOUND] DSpace item already exists in Firestore as ${existingDoc.id}. Reconciling manifest.`);
        entry.stage = "COMPLETED";
        entry.firestore_resource_id = existingDoc.id;
        entry.assigned_user_uid = userCred.uid;
        entry.error = null;
        entry.updated_at = new Date().toISOString();
        fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifestData, null, 2), "utf8");
        successCount++;
        continue;
      }

      // Step B: Authenticate Virtual User (cached token)
      const idToken = await getAuthenticatedIdToken(userCred);

      // Step C: Upload PDF via uploadToImageKit Callable Function
      console.log(`  [UPLOAD] Invoking uploadToImageKit callable...`);
      const uploadRes = await uploadPdfViaCallable(idToken, fullPdfPath, uploadFileName, "EXAMS");
      console.log(`  [UPLOAD OK] URL: ${uploadRes.url} | FileId: ${uploadRes.fileId}`);

      entry.stage = "UPLOADED_IK";
      entry.imagekit_url = uploadRes.url;
      entry.imagekit_file_id = uploadRes.fileId;
      entry.attempt_count = (entry.attempt_count || 0) + 1;
      entry.updated_at = new Date().toISOString();

      // Step D: Create Firestore Resource Document
      console.log(`  [FIRESTORE] Creating resource document...`);
      const resourceDocData: Record<string, any> = {
        title: entry.title,
        fileName: uploadFileName,
        type: "Exams",
        materialType: "Exams",
        thumbnailUrl: "",
        thumbnailId: null,
        thumbnailStatus: "pending",
        fileUrl: uploadRes.url,
        fileId: uploadRes.fileId,
        unitName: entry.unit_name,
        unitCode: entry.unit_code,
        year: entry.publication_year.toString(),
        uploadYear: new Date().getFullYear().toString(),
        publicationYear: entry.publication_year.toString(),
        yearOfStudy: entry.year_of_study,
        semester: entry.semester,
        lecturers: entry.lecturers,
        uploadedBy: userCred.name,
        uploaderRole: "Student",
        uploaderId: userCred.uid,
        uploaderProfilePic: null,
        uploadDate: FieldValue.serverTimestamp(),
        targetPrograms: entry.target_programs,
        programCodes: entry.program_codes,
        materialFormat: "PDF",
        status: "approved",
        visibility: "public",
        isAnonymous: false,
        isPinned: false,
        approvedByAdmin: false,
        rejectedByAdmin: false,
        likedBy: [],
        views: 0,
        likes: 0,
        comments: 0,
        isImportedDSpace: true,
        dspaceItemUuid: entry.dspace_item_uuid,
        dspaceHandle: entry.dspace_handle,
      };

      const docRef = await db.collection("resources").add(resourceDocData);
      const resourceId = docRef.id;
      console.log(`  [FIRESTORE OK] Created document resources/${resourceId}`);

      // Step E: Finalize Manifest Entry (Ingestion Complete, Thumbnail Pending Asynchronously)
      entry.stage = "COMPLETED";
      entry.thumbnail_status = "pending";
      entry.firestore_resource_id = resourceId;
      entry.assigned_user_uid = userCred.uid;
      entry.error = null;
      entry.updated_at = new Date().toISOString();

      // Save manifest immediately for resume-safety
      fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifestData, null, 2), "utf8");

      successCount++;
      console.log(`  [INGESTED OK] Item ${overallNum}/1515 successfully ingested!`);

      // Progress milestone logging every 25 items
      if (successCount % 25 === 0) {
        const elapsedSec = Math.round((Date.now() - startTime) / 1000);
        const ratePerMin = ((successCount / elapsedSec) * 60).toFixed(1);
        const remaining = eligibleEntries.length - itemNum;
        const estRemainingMin = (remaining / (parseFloat(ratePerMin) || 1)).toFixed(1);
        console.log(`\n>>> MILESTONE: Ingested ${successCount}/${eligibleEntries.length} items (${elapsedSec}s elapsed, ~${ratePerMin} items/min, est. ${estRemainingMin}m remaining) <<<\n`);
      }

      // Safe pacing delay
      if (itemNum < eligibleEntries.length) {
        await new Promise((resolve) => setTimeout(resolve, ITEM_PACE_DELAY_MS));
      }
    } catch (err: any) {
      console.error(`\n[INGESTION ERROR on item ${overallNum}/1515]:`, err.message || err);
      entry.stage = "FAILED";
      entry.error = err.message || String(err);
      entry.updated_at = new Date().toISOString();
      fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifestData, null, 2), "utf8");
      failureCount++;
    }
  }

  const totalElapsedSec = Math.round((Date.now() - startTime) / 1000);
  console.log("\n================================================================================");
  console.log(" FULL DSPACE INGESTION FINISHED");
  console.log("================================================================================");
  console.log(` Successfully Ingested: ${successCount}`);
  console.log(` Failed:                 ${failureCount}`);
  console.log(` Total Elapsed Time:     ${Math.floor(totalElapsedSec / 60)}m ${totalElapsedSec % 60}s`);
  console.log("================================================================================\n");
}

if (process.argv[1] && process.argv[1].endsWith("run_dspace_full_ingestion.ts")) {
  runFullIngestion().catch((err) => {
    console.error("Fatal error:", err);
    process.exit(1);
  });
}

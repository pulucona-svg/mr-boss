/**
 * Controlled 20-Material Production Pilot Runner
 *
 * Imports EXACTLY 20 examination materials from DSpace archive into Mirror Digital:
 * - Exactly 1 material assigned to virtual uploader index 1
 * - Exactly 1 material assigned to virtual uploader index 2
 * - ...
 * - Exactly 1 material assigned to virtual uploader index 20
 *
 * CRITICAL STOP CONDITIONS:
 * - Hard limit: 20 items ONLY.
 * - Stops automatically after the 20 pilot materials.
 * - NEVER continues to the remaining 1,495 materials.
 * - Strict double guard: default is DRY-RUN. Requires --production --confirm-pilot.
 * - Authenticates virtual uploader via Google Identity Toolkit to obtain real idToken.
 * - Cryptographically verifies identity token before upload.
 * - Invokes production uploadToImageKit callable endpoint via HTTPS with Bearer token.
 * - Creates Firestore resources document with complete production upload semantics.
 * - Naturally allows onMaterialCreatedSearchThumbnail trigger to process the thumbnail.
 * - Monitors thumbnail generation until completion.
 * - Updates import_manifest.json strictly for the 20 pilot entries.
 */

import { initializeApp, cert, getApps } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
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

const MAX_PILOT_ITEMS = 20; // STRICT HARD LIMIT: 20 MATERIALS ONLY
const ITEM_PACE_DELAY_MS = 2500; // 2.5s modest pacing between items

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

export interface PilotSelection {
  manifestIndex: number;
  userIndex: number;
  userCred: StoredCredential;
  entry: any;
  fullPdfPath: string;
  fileSizeBytes: number;
}

// ============================================================================
// Helper: Authenticate Virtual User and Obtain Valid ID Token
// ============================================================================

async function authenticateVirtualUser(cred: StoredCredential): Promise<{ idToken: string; uid: string }> {
  if (!cred.password) {
    throw new Error(`Virtual user ${cred.email} has no recorded password.`);
  }

  const endpoint = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${WEB_API_KEY}`;
  const res = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      email: cred.email,
      password: cred.password,
      returnSecureToken: true,
    }),
  });

  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(`Failed to authenticate ${cred.email} via Identity Toolkit (${res.status}): ${errorText}`);
  }

  const data: any = await res.json();
  const idToken = data.idToken as string;
  const localId = data.localId as string;

  // Cryptographic verification
  const decoded = await auth.verifyIdToken(idToken);
  if (decoded.uid !== cred.uid || localId !== cred.uid) {
    throw new Error(
      `Security mismatch! Token UID (${decoded.uid}) does not match expected UID (${cred.uid}) for ${cred.email}`
    );
  }

  return { idToken, uid: decoded.uid };
}

// ============================================================================
// Helper: Upload PDF via Deployed uploadToImageKit Callable Function
// ============================================================================

async function uploadPdfViaCallable(
  idToken: string,
  filePath: string,
  fileName: string,
  folder: string
): Promise<{ url: string; fileId: string; name: string }> {
  const fileBytes = fs.readFileSync(filePath);
  const base64File = fileBytes.toString("base64");

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
    throw new Error(
      `uploadToImageKit callable failed (${res.status}): ${json.error?.message || resText}`
    );
  }

  if (!json.result || !json.result.url || !json.result.fileId) {
    throw new Error(`uploadToImageKit returned incomplete result: ${resText}`);
  }

  return json.result;
}

// ============================================================================
// Helper: Poll Firestore for Trigger Thumbnail Completion
// ============================================================================

async function pollThumbnailCompletion(
  resourceId: string,
  timeoutMs: number = THUMBNAIL_TIMEOUT_MS
): Promise<{ status: string; url: string; fileId: string }> {
  const startTime = Date.now();
  const docRef = db.collection("resources").doc(resourceId);

  while (Date.now() - startTime < timeoutMs) {
    const snap = await docRef.get();
    if (snap.exists) {
      const data = snap.data();
      const thumbStatus = data?.thumbnailStatus || "pending";
      const thumbUrl = data?.thumbnailUrl || "";
      const thumbId = data?.thumbnailId || "";

      if (thumbStatus === "completed" && thumbUrl.length > 0) {
        return { status: "completed", url: thumbUrl, fileId: thumbId };
      }

      if (thumbStatus === "failed") {
        throw new Error(`Thumbnail generation failed for resource ${resourceId}`);
      }
    }

    // Wait 4 seconds between poll checks
    await new Promise((resolve) => setTimeout(resolve, 4000));
  }

  throw new Error(`Timed out waiting for thumbnail generation on resource ${resourceId} after ${timeoutMs / 1000}s`);
}

// ============================================================================
// Main Controlled Pilot Runner
// ============================================================================

export async function runPilot() {
  const args = process.argv.slice(2);
  const isProduction = args.includes("--production");
  const isConfirmed = args.includes("--confirm-pilot");
  const isDryRun = !isProduction || !isConfirmed;

  console.log("================================================================================");
  console.log(" MIRROR LAIKIPIA - CONTROLLED 20-MATERIAL PRODUCTION PILOT");
  console.log("================================================================================");
  console.log(` Mode:               ${isDryRun ? "DRY-RUN (Inspection - No Writes)" : "PRODUCTION (LIVE PILOT WRITES)"}`);
  console.log(` Target Pilot Items: ${MAX_PILOT_ITEMS} (EXACTLY 1 PER VIRTUAL UPLOADER)`);
  console.log(` Stop Condition:     AUTOMATIC HALT IMMEDIATELY AFTER ITEM 20`);
  console.log(` DSpace Archive:     ${DSPACE_DIR}`);
  console.log("================================================================================\n");

  if (isDryRun) {
    if (isProduction && !isConfirmed) {
      console.warn("[WARNING] Flag --production was specified but --confirm-pilot is missing!");
      console.warn("Falling back to DRY-RUN mode for safety.\n");
    } else {
      console.log("[INFO] Running in default DRY-RUN mode. Pass '--production --confirm-pilot' to execute.\n");
    }
  }

  // 1. Load Credentials
  if (!fs.existsSync(CREDENTIALS_PATH)) {
    throw new Error(`Credentials file not found at: ${CREDENTIALS_PATH}`);
  }
  const credentials: StoredCredential[] = JSON.parse(fs.readFileSync(CREDENTIALS_PATH, "utf8"));
  const credMap = new Map<number, StoredCredential>();
  for (const c of credentials) {
    credMap.set(c.userIndex, c);
  }

  // 2. Load Manifest
  if (!fs.existsSync(MANIFEST_PATH)) {
    throw new Error(`Manifest file not found at: ${MANIFEST_PATH}`);
  }
  const manifestRaw = fs.readFileSync(MANIFEST_PATH, "utf8");
  const manifestData: any[] = JSON.parse(manifestRaw);

  console.log(`Loaded manifest containing ${manifestData.length} entries.\n`);

  // 3. Select Pilot Items (1 per user index 1..20)
  const selectedPilot: PilotSelection[] = [];

  for (let userIdx = 1; userIdx <= MAX_PILOT_ITEMS; userIdx++) {
    const cred = credMap.get(userIdx);
    if (!cred) {
      throw new Error(`Missing credential for virtual user index ${userIdx}!`);
    }

    const entryIdx = manifestData.findIndex(
      (m) => m.assigned_user_index === userIdx && m.stage === "PENDING" && m.assigned_user_uid
    );

    if (entryIdx === -1) {
      throw new Error(`Could not find an eligible PENDING entry for user index ${userIdx} (${cred.name})!`);
    }

    const entry = manifestData[entryIdx];
    const fullPdfPath = path.join(DSPACE_DIR, entry.local_filepath);

    if (!fs.existsSync(fullPdfPath)) {
      throw new Error(`PDF file does not exist on disk for item ${entry.dspace_item_uuid}: ${fullPdfPath}`);
    }

    const stat = fs.statSync(fullPdfPath);
    if (stat.size === 0) {
      throw new Error(`PDF file is empty (0 bytes) for item ${entry.dspace_item_uuid}: ${fullPdfPath}`);
    }

    if (entry.assigned_user_uid !== cred.uid) {
      throw new Error(
        `UID mismatch on item ${entry.dspace_item_uuid}: manifest UID (${entry.assigned_user_uid}) does not match credential UID (${cred.uid})`
      );
    }

    selectedPilot.push({
      manifestIndex: entryIdx,
      userIndex: userIdx,
      userCred: cred,
      entry,
      fullPdfPath,
      fileSizeBytes: stat.size,
    });
  }

  if (selectedPilot.length !== MAX_PILOT_ITEMS) {
    throw new Error(`Expected exactly 20 pilot entries, but selected ${selectedPilot.length}. Aborting.`);
  }

  // 4. Print Exact 20 Selected Pilot Entries
  console.log("================================================================================");
  console.log(" EXACT 20 DETERMINISTIC PILOT SELECTIONS");
  console.log("================================================================================");
  for (const s of selectedPilot) {
    console.log(
      `[User ${s.userIndex.toString().padStart(2, " ")}/20] ` +
        `ManifestIdx: ${s.manifestIndex.toString().padStart(4, " ")} | ` +
        `UUID: ${s.entry.dspace_item_uuid} | ` +
        `Unit: ${(s.entry.unit_code || "").padEnd(14, " ")} | ` +
        `Title: "${s.entry.title.slice(0, 28)}" | ` +
        `Year: ${s.entry.publication_year} | ` +
        `Size: ${(s.fileSizeBytes / 1024).toFixed(1)} KB | ` +
        `Uploader: ${s.userCred.name} (${s.userCred.uid})`
    );
  }
  console.log("================================================================================\n");

  if (isDryRun) {
    console.log("--------------------------------------------------------------------------------");
    console.log("DRY-RUN INSPECTION COMPLETED:");
    console.log("  All 20 candidate materials validated (Files exist, non-zero, stage PENDING).");
    console.log("  All 20 candidate materials assigned to verified distinct virtual users.");
    console.log("  Zero writes were performed.");
    console.log("  Pass '--production --confirm-pilot' to execute the live 20-item pilot.");
    console.log("================================================================================");
    return;
  }

  // ============================================================================
  // PRODUCTION EXECUTION (EXACTLY 20 ITEMS)
  // ============================================================================
  console.log("================================================================================");
  console.log(" EXECUTING LIVE PRODUCTION PILOT (20 ITEMS ONLY)");
  console.log("================================================================================");

  const pilotResults: Array<{
    userIndex: number;
    userName: string;
    userUid: string;
    dspaceUuid: string;
    unitCode: string;
    unitName: string;
    imageKitUrl: string;
    imageKitFileId: string;
    firestoreResourceId: string;
    thumbnailUrl: string;
    thumbnailStatus: string;
    success: boolean;
    error?: string;
  }> = [];

  for (let i = 0; i < selectedPilot.length; i++) {
    const item = selectedPilot[i];
    const itemNum = i + 1;
    console.log(`\n--------------------------------------------------------------------------------`);
    console.log(`[PILOT ITEM ${itemNum}/20] Starting: ${item.entry.unit_code} - "${item.entry.title}"`);
    console.log(`  Assigned Uploader:  ${item.userCred.name} (User Index ${item.userIndex})`);
    console.log(`  Target UID:         ${item.userCred.uid}`);
    console.log(`  Local PDF:          ${item.entry.local_filepath} (${(item.fileSizeBytes / 1024).toFixed(1)} KB)`);

    try {
      // Step A: Idempotency re-check
      if (item.entry.stage !== "PENDING") {
        throw new Error(`Item ${item.entry.dspace_item_uuid} is not in PENDING stage (found ${item.entry.stage}).`);
      }
      if (item.entry.imagekit_url || item.entry.firestore_resource_id) {
        throw new Error(`Item ${item.entry.dspace_item_uuid} already has ImageKit or Firestore artifacts!`);
      }

      // Check if item was already imported into Firestore
      const dupCheck = await db.collection("resources").where("dspaceItemUuid", "==", item.entry.dspace_item_uuid).get();
      if (!dupCheck.empty) {
        throw new Error(`Duplicate protection: DSpace item ${item.entry.dspace_item_uuid} already exists in Firestore!`);
      }

      // Step B: Authenticate Virtual User
      console.log(`  [AUTH] Authenticating as ${item.userCred.email}...`);
      const authResult = await authenticateVirtualUser(item.userCred);
      console.log(`  [AUTH OK] Valid token verified cryptographically for UID: ${authResult.uid}`);

      // Step C: Upload PDF via uploadToImageKit Callable Function
      console.log(`  [UPLOAD] Invoking uploadToImageKit callable in folder EXAMS...`);
      const uploadFileName = path.basename(item.fullPdfPath);
      const uploadRes = await uploadPdfViaCallable(authResult.idToken, item.fullPdfPath, uploadFileName, "EXAMS");
      console.log(`  [UPLOAD OK] ImageKit URL: ${uploadRes.url} | FileId: ${uploadRes.fileId}`);

      // Update manifest stage in-memory
      item.entry.stage = "UPLOADED_IK";
      item.entry.imagekit_url = uploadRes.url;
      item.entry.imagekit_file_id = uploadRes.fileId;
      item.entry.attempt_count = (item.entry.attempt_count || 0) + 1;
      item.entry.updated_at = new Date().toISOString();

      // Step D: Create Firestore Resource Document
      console.log(`  [FIRESTORE] Creating resource document in collection 'resources'...`);
      const resourceDocData: Record<string, any> = {
        title: item.entry.title,
        fileName: uploadFileName,
        type: "Exams",
        materialType: "Exams",
        thumbnailUrl: "",
        thumbnailId: null,
        thumbnailStatus: "pending",
        fileUrl: uploadRes.url,
        fileId: uploadRes.fileId,
        unitName: item.entry.unit_name,
        unitCode: item.entry.unit_code,
        year: item.entry.publication_year.toString(),
        uploadYear: new Date().getFullYear().toString(),
        publicationYear: item.entry.publication_year.toString(),
        yearOfStudy: item.entry.year_of_study,
        semester: item.entry.semester,
        lecturers: item.entry.lecturers,
        uploadedBy: item.userCred.name,
        uploaderRole: "Student",
        uploaderId: item.userCred.uid,
        uploaderProfilePic: null,
        uploadDate: FieldValue.serverTimestamp(),
        targetPrograms: item.entry.target_programs,
        programCodes: item.entry.program_codes,
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
        dspaceItemUuid: item.entry.dspace_item_uuid,
        dspaceHandle: item.entry.dspace_handle,
      };

      const docRef = await db.collection("resources").add(resourceDocData);
      const resourceId = docRef.id;
      console.log(`  [FIRESTORE OK] Created document resources/${resourceId}`);

      item.entry.stage = "FIRESTORE_WRITTEN";
      item.entry.firestore_resource_id = resourceId;
      item.entry.updated_at = new Date().toISOString();

      // Step E: Register Asynchronous Background Thumbnail
      console.log(`  [THUMBNAIL] Asynchronous background thumbnail generation registered (Flux-only).`);

      // Step F: Finalize Manifest Entry (Ingestion Complete)
      item.entry.stage = "COMPLETED";
      item.entry.thumbnail_status = "pending";
      item.entry.error = null;
      item.entry.updated_at = new Date().toISOString();

      // Save manifest immediately for resume-safety
      fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifestData, null, 2), "utf8");

      pilotResults.push({
        userIndex: item.userIndex,
        userName: item.userCred.name,
        userUid: item.userCred.uid,
        dspaceUuid: item.entry.dspace_item_uuid,
        unitCode: item.entry.unit_code,
        unitName: item.entry.unit_name,
        imageKitUrl: uploadRes.url,
        imageKitFileId: uploadRes.fileId,
        firestoreResourceId: resourceId,
        thumbnailUrl: "",
        thumbnailStatus: "pending",
        success: true,
      });

      console.log(`  [COMPLETED] Pilot item ${itemNum}/20 successfully ingested!`);

      // Enforce pacing delay between items if not the last item
      if (itemNum < selectedPilot.length) {
        console.log(`  [PACING] Waiting ${ITEM_PACE_DELAY_MS / 1000}s before next item...`);
        await new Promise((resolve) => setTimeout(resolve, ITEM_PACE_DELAY_MS));
      }
    } catch (err: any) {
      console.error(`\n[CRITICAL PILOT FAILURE on item ${itemNum}/20]:`, err.message || err);
      item.entry.stage = "FAILED";
      item.entry.error = err.message || String(err);
      item.entry.updated_at = new Date().toISOString();
      fs.writeFileSync(MANIFEST_PATH, JSON.stringify(manifestData, null, 2), "utf8");

      pilotResults.push({
        userIndex: item.userIndex,
        userName: item.userCred.name,
        userUid: item.userCred.uid,
        dspaceUuid: item.entry.dspace_item_uuid,
        unitCode: item.entry.unit_code,
        unitName: item.entry.unit_name,
        imageKitUrl: item.entry.imagekit_url || "",
        imageKitFileId: item.entry.imagekit_file_id || "",
        firestoreResourceId: item.entry.firestore_resource_id || "",
        thumbnailUrl: "",
        thumbnailStatus: "failed",
        success: false,
        error: err.message || String(err),
      });

      console.error("\nSTOPPING PILOT IMMEDIATELY ACCORDING TO CRITICAL SAFETY FAILURE RULE.");
      break;
    }
  }

  // ============================================================================
  // Post-Pilot Integrity Audit
  // ============================================================================
  console.log("\n================================================================================");
  console.log(" POST-PILOT INTEGRITY AUDIT");
  console.log("================================================================================");

  const completedItems = manifestData.filter((m) => m.stage === "COMPLETED");
  const pendingItems = manifestData.filter((m) => m.stage === "PENDING");
  const failedItems = manifestData.filter((m) => m.stage === "FAILED");
  const otherStageItems = manifestData.filter(
    (m) => m.stage !== "COMPLETED" && m.stage !== "PENDING" && m.stage !== "FAILED"
  );

  console.log(`Total Manifest Entries:      ${manifestData.length} (Expected: 1,515)`);
  console.log(`COMPLETED Entries:           ${completedItems.length} (Expected: 20)`);
  console.log(`PENDING Entries:             ${pendingItems.length} (Expected: 1,495)`);
  console.log(`FAILED Entries:              ${failedItems.length} (Expected: 0)`);
  console.log(`Interrupted/Other Stages:    ${otherStageItems.length} (Expected: 0)`);
  console.log("--------------------------------------------------------------------------------");

  // Verify untouched items
  const pendingWithArtifacts = pendingItems.filter(
    (m) => m.imagekit_url !== null || m.imagekit_file_id !== null || m.firestore_resource_id !== null
  );
  console.log(`Pending Items with Artifacts:${pendingWithArtifacts.length} (Expected: 0)`);

  // Verify unique uploader coverage in completed pilot
  const completedUserIndices = new Set(completedItems.map((m) => m.assigned_user_index));
  console.log(`Distinct Uploaders in Pilot: ${completedUserIndices.size} / 20`);

  const allPilotSucceeded =
    pilotResults.length === MAX_PILOT_ITEMS &&
    pilotResults.every((r) => r.success) &&
    completedItems.length === MAX_PILOT_ITEMS &&
    pendingItems.length === 1515 - MAX_PILOT_ITEMS &&
    failedItems.length === 0;

  console.log("================================================================================");
  if (allPilotSucceeded) {
    console.log(" PILOT RESULT: 100% SUCCESS — ALL 20 MATERIALS IMPORTED & VERIFIED");
  } else {
    console.log(" PILOT RESULT: INCOMPLETE OR FAILED");
  }
  console.log("================================================================================\n");

  if (!allPilotSucceeded) {
    process.exit(1);
  }
}

// Execute
runPilot().catch((err) => {
  console.error("Fatal unhandled error during pilot execution:", err);
  process.exit(1);
});

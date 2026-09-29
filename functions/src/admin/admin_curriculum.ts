import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

function requireAdmin(request: any) {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError(
      "permission-denied",
      "Access denied: Caller does not possess administrator privileges."
    );
  }
}

/**
 * Normalizes a string by stripping non-alphanumeric characters and lowercasing.
 */
function clean(s: string): string {
  return String(s || "").trim().toLowerCase().replace(/[^a-z0-9]/g, "");
}

function normYear(y: string): string {
  const match = String(y || "").match(/\d+/);
  return match ? match[0] : clean(y);
}

function normSem(s: string): string {
  const match = String(s || "").match(/\d+/);
  return match ? match[0] : clean(s);
}

/**
 * Generates the canonical deterministic ID for a curriculum record.
 */
export function generateCurriculumId(
  programCode: string,
  unitCode: string,
  yearOfStudy: string,
  semester: string
): string {
  const p = clean(programCode);
  const u = clean(unitCode);
  const y = normYear(yearOfStudy);
  const s = normSem(semester);
  return `${p}_${u}_y${y}_s${s}`;
}

/**
 * Checks whether all required core fields are present and non-blank.
 */
export function isValidForActivation(record: {
  programCode?: string;
  programName?: string;
  unitCode?: string;
  unitName?: string;
  yearOfStudy?: string;
  semester?: string;
}): boolean {
  return Boolean(
    record.programCode && String(record.programCode).trim().length > 0 &&
    record.programName && String(record.programName).trim().length > 0 &&
    record.unitCode && String(record.unitCode).trim().length > 0 &&
    record.unitName && String(record.unitName).trim().length > 0 &&
    record.yearOfStudy && String(record.yearOfStudy).trim().length > 0 &&
    record.semester && String(record.semester).trim().length > 0
  );
}

/**
 * CALLABLE FUNCTION: Fetches all curriculum records for the Admin Console.
 */
export const getAdminCurriculum = onCall(async (request) => {
  requireAdmin(request);
  const db = admin.firestore();

  const snapshot = await db.collection("curriculum").get();
  const records = snapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  }));

  return {
    success: true,
    count: records.length,
    records,
  };
});

/**
 * CALLABLE FUNCTION: Creates a new curriculum record with deterministic ID & validation.
 */
export const createCurriculumRecord = onCall(async (request) => {
  requireAdmin(request);
  const db = admin.firestore();
  const callerUid = request.auth?.uid;

  const data = request.data || {};
  const {
    programCode,
    programName,
    unitCode,
    unitName,
    yearOfStudy,
    semester,
    lecturerName,
    isActive = true,
  } = data;

  const pCode = String(programCode || "").trim();
  const pName = String(programName || "").trim();
  const uCode = String(unitCode || "").trim();
  const uName = String(unitName || "").trim();
  const yStudy = String(yearOfStudy || "").trim();
  const sem = String(semester || "").trim();
  const lName = String(lecturerName || "").trim();

  // If attempting to activate, strict required field validation
  if (isActive && !isValidForActivation({
    programCode: pCode,
    programName: pName,
    unitCode: uCode,
    unitName: uName,
    yearOfStudy: yStudy,
    semester: sem,
  })) {
    throw new HttpsError(
      "failed-precondition",
      "Cannot activate a curriculum record with missing required fields (Program Code, Program Name, Unit Code, Unit Name, Year, Semester)."
    );
  }

  const docId = generateCurriculumId(pCode, uCode, yStudy, sem);
  if (!docId || docId === "__y_s") {
    throw new HttpsError("invalid-argument", "Insufficient curriculum identity attributes to generate a record ID.");
  }

  const docRef = db.collection("curriculum").doc(docId);
  const existing = await docRef.get();
  if (existing.exists) {
    throw new HttpsError("already-exists", `A curriculum record for ${pCode} - ${uCode} (Year ${yStudy}, Sem ${sem}) already exists.`);
  }

  const newDoc = {
    id: docId,
    programCode: pCode,
    programName: pName,
    unitCode: uCode,
    unitName: uName,
    yearOfStudy: yStudy,
    semester: sem,
    lecturerName: lName,
    isActive: Boolean(isActive),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: callerUid || null,
  };

  await docRef.set(newDoc);
  logger.info(`[CURRICULUM_CREATED] Created curriculum record: ${docId} by ${callerUid}`);

  return {
    success: true,
    id: docId,
    record: newDoc,
  };
});

/**
 * CALLABLE FUNCTION: Updates an existing curriculum record.
 */
export const updateCurriculumRecord = onCall(async (request) => {
  requireAdmin(request);
  const db = admin.firestore();
  const callerUid = request.auth?.uid;

  const { id, updates } = request.data || {};
  if (!id || typeof id !== "string") {
    throw new HttpsError("invalid-argument", "Missing curriculum record id.");
  }

  const docRef = db.collection("curriculum").doc(id.trim());
  const existingSnap = await docRef.get();
  if (!existingSnap.exists) {
    throw new HttpsError("not-found", `Curriculum record with ID "${id}" does not exist.`);
  }

  const currentData = existingSnap.data() || {};
  const merged = { ...currentData, ...updates };

  // If active is true or being set to true, enforce required validation
  if (merged.isActive === true && !isValidForActivation(merged)) {
    throw new HttpsError(
      "failed-precondition",
      "Cannot activate a curriculum record with missing required fields."
    );
  }

  const cleanUpdates: Record<string, any> = {
    ...updates,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: callerUid || null,
  };
  delete cleanUpdates.id;
  delete cleanUpdates.createdAt;

  await docRef.update(cleanUpdates);
  logger.info(`[CURRICULUM_UPDATED] Updated curriculum record: ${id} by ${callerUid}`);

  return {
    success: true,
    id,
  };
});

/**
 * CALLABLE FUNCTION: Toggles the isActive state with strict server-side validation.
 */
export const toggleCurriculumActive = onCall(async (request) => {
  requireAdmin(request);
  const db = admin.firestore();
  const callerUid = request.auth?.uid;

  const { id, isActive } = request.data || {};
  if (!id || typeof id !== "string" || typeof isActive !== "boolean") {
    throw new HttpsError("invalid-argument", "Missing required id or isActive boolean parameter.");
  }

  const docRef = db.collection("curriculum").doc(id.trim());
  const docSnap = await docRef.get();
  if (!docSnap.exists) {
    throw new HttpsError("not-found", `Curriculum record with ID "${id}" not found.`);
  }

  const data = docSnap.data() || {};

  // If activating, validate all required core fields
  if (isActive === true && !isValidForActivation(data)) {
    throw new HttpsError(
      "failed-precondition",
      "Cannot activate curriculum record: one or more required fields are incomplete."
    );
  }

  await docRef.update({
    isActive,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: callerUid || null,
  });

  logger.info(`[CURRICULUM_TOGGLE] Toggled isActive to ${isActive} for ${id} by ${callerUid}`);

  return {
    success: true,
    id,
    isActive,
  };
});

/**
 * CALLABLE FUNCTION: Deletes or removes a curriculum record.
 */
export const deleteCurriculumRecord = onCall(async (request) => {
  requireAdmin(request);
  const db = admin.firestore();
  const callerUid = request.auth?.uid;

  const { id } = request.data || {};
  if (!id || typeof id !== "string") {
    throw new HttpsError("invalid-argument", "Missing curriculum record id.");
  }

  const cleanId = id.trim();
  const docRef = db.collection("curriculum").doc(cleanId);
  const docSnap = await docRef.get();
  if (!docSnap.exists) {
    throw new HttpsError("not-found", `Curriculum record with ID "${cleanId}" not found.`);
  }

  await docRef.delete();
  logger.info(`[CURRICULUM_DELETED] Deleted curriculum record: ${cleanId} by ${callerUid}`);

  return {
    success: true,
    id: cleanId,
  };
});

/**
 * CALLABLE FUNCTION: Idempotently migrates initial curriculum records into Firestore.
 * Receives records array (e.g. from bundled lessons.json) and commits in batches of 400.
 */
export const migrateCurriculumData = onCall(async (request) => {
  requireAdmin(request);
  const db = admin.firestore();
  const callerUid = request.auth?.uid;

  const { records } = request.data || {};
  if (!Array.isArray(records) || records.length === 0) {
    throw new HttpsError("invalid-argument", "Records array must be provided and non-empty.");
  }

  let writtenCount = 0;
  let batch = db.batch();
  let operationCount = 0;
  const now = admin.firestore.FieldValue.serverTimestamp();

  for (const raw of records) {
    const pCode = String(raw["Program Code"] || raw.programCode || raw["program Code"] || "").trim();
    const pName = String(raw["Program Name"] || raw.programName || raw["program Name"] || "").trim();
    const uCode = String(raw["Unit Code"] || raw.unitCode || raw["unit Code"] || "").trim();
    const uName = String(raw["Unit Name"] || raw.unitName || raw["unit Name"] || "").trim();
    const yStudy = String(raw["Year of Study"] || raw["Year of study"] || raw.yearOfStudy || "").trim();
    const sem = String(raw["Semester"] || raw.semester || "").trim();
    const lName = String(raw["Lecturer's Name"] || raw["lecturer's Name"] || raw.lecturerName || "").trim();

    const docId = generateCurriculumId(pCode, uCode, yStudy, sem);
    if (!docId || docId === "__y_s") continue;

    const docRef = db.collection("curriculum").doc(docId);
    batch.set(
      docRef,
      {
        id: docId,
        programCode: pCode,
        programName: pName,
        unitCode: uCode,
        unitName: uName,
        yearOfStudy: yStudy,
        semester: sem,
        lecturerName: lName,
        isActive: true,
        createdAt: now,
        updatedAt: now,
        updatedBy: callerUid || "migration",
      },
      { merge: true }
    );

    writtenCount++;
    operationCount++;

    if (operationCount >= 400) {
      await batch.commit();
      batch = db.batch();
      operationCount = 0;
    }
  }

  if (operationCount > 0) {
    await batch.commit();
  }

  logger.info(`[CURRICULUM_MIGRATION_COMPLETE] Successfully migrated ${writtenCount} curriculum records by ${callerUid}`);

  return {
    success: true,
    migratedCount: writtenCount,
  };
});

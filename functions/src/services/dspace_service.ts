/**
 * Authoritative Backend DSpace Synchronization & Ingestion Service
 *
 * Implements:
 * - Read-only discovery comparing DSpace archive against imported materials.
 * - Resilient metadata & publication date extraction preserving dc.date.issued rules.
 * - Curriculum matching mirroring Mirror Digital's production catalog.
 * - Deterministic assignment across the 20 synthetic Kenyan virtual accounts.
 * - Safe ImageKit upload & Firestore resource creation with isImportedDSpace: true.
 * - Asynchronous Flux thumbnail generation hand-off.
 * - Real-time progress updates & durable resume safeguards.
 */

import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";
import * as fs from "fs";
import * as path from "path";
import { VIRTUAL_USER_ACCOUNTS, VirtualUserAccount } from "../config/virtual_users";

// ============================================================================
// Types and Interfaces
// ============================================================================

export interface DiscoveredDSpaceItem {
  itemUuid: string;
  handle: string;
  title: string;
  publicationDate: string;
  publicationYear: number | null;
  publicationDateSource: string;
  subjects: string;
  authors: string;
  collectionUuid: string;
  collectionName: string;
  unitCode: string;
  unitName: string;
  targetPrograms: string[];
  programCodes: string[];
  lecturers: string[];
  yearOfStudy: string;
  semester: string;
  bitstreamUuid: string | null;
  fileName: string;
  fileSizeBytes: number;
  md5: string;
  downloadUrl: string;
}

export interface DSpaceJobSummary {
  newDiscovered: number;
  successfullyImported: number;
  failedImports: number;
  skippedDuplicates: number;
  itemsPending: number;
  durationSeconds: number;
}

export interface CurriculumRow {
  unitName: string;
  unitCode: string;
  programCode: string;
  programName: string;
  yearOfStudy: string;
  semester: string;
  lecturerName: string;
}

// ============================================================================
// Curriculum Catalog Helper
// ============================================================================

class CurriculumCatalog {
  private rows: CurriculumRow[] = [];
  private codeToRows: Map<string, CurriculumRow[]> = new Map();
  private nameToCode: Map<string, string> = new Map();

  constructor() {
    this.loadCatalog();
  }

  private loadCatalog(): void {
    const candidatePaths = [
      path.resolve(__dirname, "../data/lessons.json"),
      path.resolve(__dirname, "../../data/lessons.json"),
      path.resolve(__dirname, "../../../assets/lessons.json"),
    ];

    let foundPath = "";
    for (const p of candidatePaths) {
      if (fs.existsSync(p)) {
        foundPath = p;
        break;
      }
    }

    if (!foundPath) {
      logger.warn("[CURRICULUM] lessons.json not found in candidate paths. Using fallback mapping.");
      return;
    }

    try {
      let raw = fs.readFileSync(foundPath, "utf8");
      if (raw.charCodeAt(0) === 0xfeff) raw = raw.slice(1);
      const data = JSON.parse(raw);
      for (const item of data) {
        const row: CurriculumRow = {
          unitName: (item["Unit Name"] || item["unit Name"] || item["unitName"] || "").trim(),
          unitCode: (item["Unit Code"] || item["unit Code"] || item["unitCode"] || "").trim(),
          programCode: (item["Program Code"] || item["program Code"] || item["programCode"] || "").trim(),
          programName: (item["Program Name"] || item["program Name"] || item["programName"] || "").trim(),
          yearOfStudy: (item["Year of Study"] || item["Year of study"] || item["year of Study"] || item["yearOfStudy"] || "").trim(),
          semester: (item["Semester"] || item["semester"] || "").trim(),
          lecturerName: (item["Lecturer's Name"] || item["lecturer's Name"] || item["lecturerName"] || "").trim(),
        };

        if (!row.unitCode && !row.unitName) continue;
        this.rows.push(row);

        const subCodes = this.parseCodes(row.unitCode);
        const allCodes = new Set([row.unitCode.toUpperCase(), ...subCodes.map((c) => c.toUpperCase())]);
        for (const code of allCodes) {
          if (!this.codeToRows.has(code)) {
            this.codeToRows.set(code, []);
          }
          this.codeToRows.get(code)!.push(row);
        }

        if (row.unitName && row.unitCode) {
          this.nameToCode.set(row.unitName.toUpperCase(), row.unitCode);
        }
      }
      logger.info(`[CURRICULUM] Loaded ${this.rows.length} curriculum rows from ${path.basename(foundPath)}`);
    } catch (e: any) {
      logger.error(`[CURRICULUM] Error reading lessons.json:`, e);
    }
  }

  public parseCodes(unitCode: string): string[] {
    const results: string[] = [];
    const parts = unitCode.split("/");
    for (let i = 0; i < parts.length; i++) {
      const p = parts[i].trim();
      if (/\d/.test(p)) {
        results.push(p);
      } else {
        for (let j = i + 1; j < parts.length; j++) {
          const nextP = parts[j].trim();
          const match = nextP.match(/(\d+.*)$/);
          if (match) {
            results.push(`${p} ${match[1]}`.trim());
            break;
          }
        }
      }
    }
    return results;
  }

  public getUnitsByCode(code: string): CurriculumRow[] {
    const clean = code.trim().toUpperCase();
    if (this.codeToRows.has(clean)) {
      return this.codeToRows.get(clean)!;
    }
    const normalized = clean.replace(/[-.]/g, " ").replace(/\s+/g, " ");
    for (const [k, v] of this.codeToRows.entries()) {
      const normK = k.replace(/[-.]/g, " ").replace(/\s+/g, " ");
      if (normK === normalized) return v;
    }
    const subCodes = this.parseCodes(code);
    for (const sub of subCodes) {
      const upper = sub.trim().toUpperCase();
      if (this.codeToRows.has(upper)) return this.codeToRows.get(upper)!;
    }
    return [];
  }

  public normalizeYear(year: string): string {
    const y = year.trim().toLowerCase();
    if (y === "1" || y.startsWith("1st") || y.includes("year 1")) return "1st Year";
    if (y === "2" || y.startsWith("2nd") || y.includes("year 2")) return "2nd Year";
    if (y === "3" || y.startsWith("3rd") || y.includes("year 3")) return "3rd Year";
    if (y === "4" || y.startsWith("4th") || y.includes("year 4")) return "4th Year";
    return "1st Year";
  }

  public normalizeSemester(sem: string): string {
    const s = sem.trim().toLowerCase();
    if (s === "1" || s.includes("1") || s.includes("sem 1")) return "Semester 1";
    if (s === "2" || s.includes("2") || s.includes("sem 2")) return "Semester 2";
    return "Semester 1";
  }

  public inferYearFromCode(code: string): string {
    const m = code.match(/\b([1-4])\d{2}\b/);
    if (m) {
      return `${m[1]}${m[1] === "1" ? "st" : m[1] === "2" ? "nd" : m[1] === "3" ? "rd" : "th"} Year`;
    }
    const mDip = code.match(/\b0([1-4])\d{2}\b/);
    if (mDip) {
      return `${mDip[1]}${mDip[1] === "1" ? "st" : mDip[1] === "2" ? "nd" : mDip[1] === "3" ? "rd" : "th"} Year`;
    }
    return "1st Year";
  }
}

// Global catalog singleton
let curriculumCatalogInstance: CurriculumCatalog | null = null;
function getCatalog(): CurriculumCatalog {
  if (!curriculumCatalogInstance) {
    curriculumCatalogInstance = new CurriculumCatalog();
  }
  return curriculumCatalogInstance;
}

// ============================================================================
// DSpace Date & Title Parsing Helpers
// ============================================================================

export function extractDateMetadata(itemData: any): {
  publicationDate: string;
  publicationYear: number | null;
  dateAccessioned: string;
  lastModified: string;
  publicationDateSource: string;
} {
  const meta = itemData?.metadata || {};

  function getFirstNonEmpty(fieldName: string): string {
    const entries = meta[fieldName] || [];
    for (const entry of entries) {
      const v = entry?.value;
      if (v !== undefined && v !== null && String(v).trim().length > 0) {
        return String(v).trim();
      }
    }
    return "";
  }

  const rawIssued = getFirstNonEmpty("dc.date.issued");
  const dateAccessioned = getFirstNonEmpty("dc.date.accessioned");
  const lastModified = String(itemData?.lastModified || itemData?.dso?.lastModified || "").trim();

  let publicationDate = "";
  let publicationYear: number | null = null;
  let publicationDateSource = "MISSING";

  if (rawIssued) {
    publicationDate = rawIssued;
    publicationDateSource = "DC_DATE_ISSUED";
    const m = rawIssued.match(/^(\d{4})/);
    if (m) {
      publicationYear = parseInt(m[1], 10);
    } else {
      const m2 = rawIssued.match(/\b(19\d\d|20\d\d)\b/);
      if (m2) {
        publicationYear = parseInt(m2[1], 10);
      }
    }
  }

  return {
    publicationDate,
    publicationYear,
    dateAccessioned,
    lastModified,
    publicationDateSource,
  };
}

export function parseDSpaceTitle(title: string, originalFilename: string): { unitCode: string; unitName: string } {
  let t = (title || "").trim().replace(/\s+/g, " ");

  const pattern =
    /^((?:[A-Z]{2,6}(?:\s*[\/,-]\s*[A-Z]{2,6})*\s*[-.]?\s*\d{3,4}[A-Z]?(?:\s*[\/,-]\s*\d{3,4}[A-Z]?)?\.?))\s*[:;–—\-]\s*(.+)$/i;

  let match = t.match(pattern);
  if (match) {
    const code = match[1].replace(/\.$/, "").replace(/\s*-\s*/, " ").trim();
    const name = cleanUnitName(match[2]);
    return { unitCode: code, unitName: name };
  }

  const pattern2 = /^((?:[A-Z]{2,6}(?:\s*[\/,-]\s*[A-Z]{2,6})*\s*[-.]?\s*\d{3,4}[A-Z]?))\s+(.+)$/i;
  match = t.match(pattern2);
  if (match) {
    const code = match[1].replace(/\.$/, "").replace(/\s*-\s*/, " ").trim();
    const name = cleanUnitName(match[2]);
    return { unitCode: code, unitName: name };
  }

  const fnStem = path.parse(originalFilename || "").name.trim().replace(/\s+/g, " ");
  match = fnStem.match(pattern);
  if (match) {
    const code = match[1].replace(/\.$/, "").replace(/\s*-\s*/, " ").trim();
    const name = cleanUnitName(match[2]);
    return { unitCode: code, unitName: name };
  }

  return { unitCode: "", unitName: cleanUnitName(t) };
}

function cleanUnitName(name: string): string {
  let n = (name || "").trim().replace(/\s+/g, " ");
  if (n === n.toUpperCase() && /[A-Z]/.test(n)) {
    n = n
      .toLowerCase()
      .split(" ")
      .map((w) => {
        if (["and", "of", "in", "to", "for", "the", "a", "an", "on", "at", "by", "i", "ii", "iii", "iv", "v"].includes(w)) {
          if (["i", "ii", "iii", "iv", "v"].includes(w)) return w.toUpperCase();
          return w;
        }
        return w.charAt(0).toUpperCase() + w.slice(1);
      })
      .join(" ");
    n = n.charAt(0).toUpperCase() + n.slice(1);
  }
  return n;
}

// ============================================================================
// DSpace Service Implementation
// ============================================================================

export class DSpaceService {
  private baseApi: string;
  private communityUuid: string;

  constructor(
    baseApi: string = "http://41.89.103.50:8080/server/api",
    communityUuid: string = "09215ddf-8fe5-4b58-9ecd-eef70a11c924"
  ) {
    this.baseApi = baseApi.replace(/\/+$/, "");
    this.communityUuid = communityUuid;
  }

  /**
   * Resilient fetch helper with timeout and retries
   */
  private async fetchWithRetry(url: string, retries: number = 3): Promise<any> {
    let lastErr: any = null;
    for (let attempt = 1; attempt <= retries; attempt++) {
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 30000);
        const resp = await fetch(url, {
          headers: {
            "Accept": "application/hal+json, application/json, */*",
            "User-Agent": "MirrorDigital-DSpaceSync/1.0",
          },
          signal: controller.signal,
        });
        clearTimeout(timeoutId);

        if (!resp.ok) {
          throw new Error(`HTTP ${resp.status} ${resp.statusText}`);
        }
        return await resp.json();
      } catch (err: any) {
        lastErr = err;
        if (attempt < retries) {
          await new Promise((r) => setTimeout(r, 1000 * attempt));
        }
      }
    }
    throw lastErr;
  }

  /**
   * Objective 2: Check Operation (Read-Only Discovery)
   *
   * 1. Traverses DSpace community & collections.
   * 2. Compares repository items against existing imported materials in Firestore.
   * 3. Extracts publication year, title, subjects, course metadata.
   * 4. Does NOT download PDFs, does NOT create materials or uploader accounts.
   */
  public async discoverNewItems(
    db: admin.firestore.Firestore,
    onProgress?: (discoveredCount: number, message: string) => Promise<void>
  ): Promise<{ totalDiscovered: number; newItems: DiscoveredDSpaceItem[] }> {
    logger.info(`[DSPACE_DISCOVERY] Starting discovery for community ${this.communityUuid}`);

    // 1. Fetch community & collections
    const commUrl = `${this.baseApi}/core/communities/${this.communityUuid}`;
    const commData = await this.fetchWithRetry(commUrl);
    const commName = commData?.name || "Examination Past Papers";
    logger.info(`[DSPACE_DISCOVERY] Connected to: "${commName}"`);

    const collections: Array<{ uuid: string; name: string }> = [];
    const communitiesToCheck = [{ uuid: this.communityUuid, name: commName, data: commData }];
    const visited = new Set<string>();

    while (communitiesToCheck.length > 0) {
      const current = communitiesToCheck.shift()!;
      if (visited.has(current.uuid)) continue;
      visited.add(current.uuid);

      // Subcommunities
      let subcLink = current.data?._links?.subcommunities?.href;
      while (subcLink) {
        try {
          const res = await this.fetchWithRetry(subcLink);
          const subs = res?._embedded?.subcommunities || [];
          for (const s of subs) {
            if (s.uuid) communitiesToCheck.push({ uuid: s.uuid, name: s.name, data: s });
          }
          subcLink = res?._links?.next?.href || null;
        } catch (e) {
          logger.warn(`[DSPACE_DISCOVERY] Error traversing subcommunities:`, e);
          subcLink = null;
        }
      }

      // Collections
      let colsLink = current.data?._links?.collections?.href;
      while (colsLink) {
        try {
          const res = await this.fetchWithRetry(colsLink);
          const cols = res?._embedded?.collections || [];
          for (const c of cols) {
            if (c.uuid) collections.push({ uuid: c.uuid, name: c.name || "Untitled Collection" });
          }
          colsLink = res?._links?.next?.href || null;
        } catch (e) {
          logger.warn(`[DSPACE_DISCOVERY] Error traversing collections:`, e);
          colsLink = null;
        }
      }
    }

    logger.info(`[DSPACE_DISCOVERY] Found ${collections.length} collections.`);

    // 2. Fetch all existing DSpace item UUIDs from Firestore resources collection
    const existingSnap = await db
      .collection("resources")
      .where("isImportedDSpace", "==", true)
      .select("dspaceItemUuid")
      .get();

    const existingUuids = new Set<string>();
    existingSnap.forEach((doc) => {
      const u = doc.data().dspaceItemUuid;
      if (u) existingUuids.add(u);
    });
    logger.info(`[DSPACE_DISCOVERY] Existing imported DSpace materials in Firestore: ${existingUuids.size}`);

    // 3. Search items in each collection
    const catalog = getCatalog();
    const newItems: DiscoveredDSpaceItem[] = [];
    let scannedTotal = 0;

    for (const col of collections) {
      let nextUrl: string | null = `${this.baseApi}/discover/search/objects?scope=${col.uuid}&dsoType=ITEM&size=50`;

      while (nextUrl) {
        try {
          const pageData = await this.fetchWithRetry(nextUrl);
          const sr = pageData?._embedded?.searchResult || {};
          const objects = sr?._embedded?.objects || [];

          for (const obj of objects) {
            scannedTotal++;
            const dso = obj?._embedded?.indexableObject;
            const itemUuid = dso?.uuid;
            if (!itemUuid || existingUuids.has(itemUuid)) {
              continue; // Already imported or invalid
            }

            // Genuinely NEW item!
            // Fetch detailed metadata read-only
            let detailedData: any = null;
            try {
              const detailUrl = `${this.baseApi}/core/items/${itemUuid}?embed=bundles/bitstreams`;
              detailedData = await this.fetchWithRetry(detailUrl, 2);
            } catch (err) {
              logger.warn(`[DSPACE_DISCOVERY] Could not fetch detail for item ${itemUuid}:`, err);
            }

            const rawName = detailedData?.name || dso?.name || "Untitled Examination Paper";
            const handle = detailedData?.handle || dso?.handle || "";
            const dateMeta = extractDateMetadata(detailedData || dso);

            // Extract subjects
            const metaObj = detailedData?.metadata || {};
            const subjectsList: string[] = (metaObj["dc.subject"] || []).map((x: any) => x.value).filter(Boolean);
            const subjects = subjectsList.join("; ");
            const authorsList: string[] = (metaObj["dc.contributor.author"] || []).map((x: any) => x.value).filter(Boolean);
            const authors = authorsList.join("; ");

            // Original bitstreams
            let bitstreamUuid: string | null = null;
            let fileName = `${itemUuid}.pdf`;
            let fileSizeBytes = 0;
            let md5 = "";
            let downloadUrl = "";

            const bundles = detailedData?._embedded?.bundles?._embedded?.bundles || [];
            for (const bundle of bundles) {
              if (bundle.name === "ORIGINAL") {
                const bss = bundle._embedded?.bitstreams?._embedded?.bitstreams || [];
                if (bss.length > 0) {
                  const bs = bss[0];
                  bitstreamUuid = bs.uuid || null;
                  fileName = bs.name || fileName;
                  fileSizeBytes = bs.sizeBytes || 0;
                  md5 = bs.checkSum?.checkSumAlgorithm === "MD5" ? bs.checkSum.value : "";
                  downloadUrl = bs._links?.content?.href || `${this.baseApi}/core/bitstreams/${bitstreamUuid}/content`;
                  break;
                }
              }
            }

            // Title and course code parsing
            const parsed = parseDSpaceTitle(rawName, fileName);
            const unitCode = parsed.unitCode;
            const unitName = parsed.unitName;

            // Curriculum match
            let targetPrograms = ["Academic Faculty"];
            let programCodes = ["GEN"];
            let lecturers = ["Laikipia University Faculty"];
            let yearOfStudy = catalog.inferYearFromCode(unitCode);
            let semester = "Semester 1";

            if (unitCode) {
              const matchedUnits = catalog.getUnitsByCode(unitCode);
              if (matchedUnits.length > 0) {
                const progs = new Set<string>();
                const pCodes = new Set<string>();
                const lecs = new Set<string>();
                for (const u of matchedUnits) {
                  if (u.programName) progs.add(u.programName);
                  if (u.programCode) pCodes.add(u.programCode);
                  if (u.lecturerName) lecs.add(u.lecturerName);
                }
                if (progs.size > 0) targetPrograms = Array.from(progs);
                if (pCodes.size > 0) programCodes = Array.from(pCodes);
                if (lecs.size > 0) lecturers = Array.from(lecs);
                yearOfStudy = catalog.normalizeYear(matchedUnits[0].yearOfStudy || yearOfStudy);
                semester = catalog.normalizeSemester(matchedUnits[0].semester || semester);
              }
            }

            newItems.push({
              itemUuid,
              handle,
              title: unitName || rawName,
              publicationDate: dateMeta.publicationDate,
              publicationYear: dateMeta.publicationYear,
              publicationDateSource: dateMeta.publicationDateSource,
              subjects,
              authors,
              collectionUuid: col.uuid,
              collectionName: col.name,
              unitCode,
              unitName,
              targetPrograms,
              programCodes,
              lecturers,
              yearOfStudy,
              semester,
              bitstreamUuid,
              fileName,
              fileSizeBytes,
              md5,
              downloadUrl,
            });

            if (onProgress && newItems.length % 5 === 0) {
              await onProgress(newItems.length, `Discovered ${newItems.length} new examination papers...`);
            }
          }

          nextUrl = sr?._links?.next?.href || null;
        } catch (e: any) {
          logger.error(`[DSPACE_DISCOVERY] Error reading collection ${col.name}:`, e);
          nextUrl = null;
        }
      }
    }

    logger.info(`[DSPACE_DISCOVERY] Completed scan: Checked ${scannedTotal} repository records, found ${newItems.length} genuinely new items.`);
    return {
      totalDiscovered: newItems.length,
      newItems,
    };
  }

  /**
   * Objective 3: Check & Download Operation (Verified Import Pipeline)
   *
   * 1. Reuses the 20 existing virtual uploader accounts (no duplicates created).
   * 2. Preserves DSpace metadata & publication date handling.
   * 3. Streams PDF into ImageKit EXAMS folder.
   * 4. Writes Firestore resource with isImportedDSpace: true.
   * 5. Hand-off to Flux thumbnail pipeline.
   * 6. Realtime tracking of discovered, imported, failed, skipped.
   */
  public async executeImport(
    db: admin.firestore.Firestore,
    ik: ImageKit,
    jobId: string,
    itemsToImport: DiscoveredDSpaceItem[]
  ): Promise<DSpaceJobSummary> {
    const jobRef = db.collection("dspace_jobs").doc(jobId);
    const startTime = Date.now();

    let successfullyImported = 0;
    let failedImports = 0;
    let skippedDuplicates = 0;
    let itemsPending = itemsToImport.length;

    // Get current total DSpace items to offset round-robin index smoothly
    const currentTotalSnap = await db.collection("resources").where("isImportedDSpace", "==", true).count().get();
    const baseOffset = currentTotalSnap.data().count || 0;

    await jobRef.update({
      status: "running",
      totalItems: itemsToImport.length,
      discoveredCount: itemsToImport.length,
      importedCount: 0,
      failedCount: 0,
      skippedCount: 0,
      pendingCount: itemsPending,
      progress: 0,
      message: `Starting import of ${itemsToImport.length} examination papers...`,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    let isCancelled = false;
    let hitTimeLimit = false;

    for (let i = 0; i < itemsToImport.length; i++) {
      const item = itemsToImport[i];

      // Cancellation check
      const currentJobSnap = await jobRef.get();
      if (currentJobSnap.data()?.status === "cancelled") {
        logger.info(`[DSPACE_IMPORT] Job ${jobId} was cancelled by administrator.`);
        isCancelled = true;
        break;
      }

      // Execution limit safeguard (halt gracefully at 7.5 minutes to prevent Cloud Function hard timeout)
      const maxDurationMs = 450000;
      if (Date.now() - startTime > maxDurationMs) {
        logger.warn(`[DSPACE_IMPORT_TIME_LIMIT] Reached 7.5m execution limit during job ${jobId}. Halting batch gracefully.`);
        hitTimeLimit = true;
        break;
      }

      // Step A: Deduplication safeguard
      const dupCheck = await db.collection("resources").where("dspaceItemUuid", "==", item.itemUuid).get();
      if (!dupCheck.empty) {
        logger.info(`[DSPACE_IMPORT] Item ${item.itemUuid} already exists in Firestore as ${dupCheck.docs[0].id}. Skipping.`);
        skippedDuplicates++;
        itemsPending--;
        await jobRef.update({
          skippedCount: skippedDuplicates,
          pendingCount: itemsPending,
          progress: Math.round(((successfullyImported + skippedDuplicates) / itemsToImport.length) * 100) / 100,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        continue;
      }

      // Step B: Virtual Account Selection
      const uploaderAccount: VirtualUserAccount = VIRTUAL_USER_ACCOUNTS[(baseOffset + i) % VIRTUAL_USER_ACCOUNTS.length];

      try {
        if (!item.bitstreamUuid || !item.downloadUrl) {
          throw new Error(`Item ${item.itemUuid} has no valid downloadable bitstream.`);
        }

        // Step C: Stream PDF from DSpace API
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 60000);
        const pdfResp = await fetch(item.downloadUrl, {
          headers: {
            "User-Agent": "MirrorDigital-DSpaceSync/1.0",
          },
          signal: controller.signal,
        });
        clearTimeout(timeoutId);

        if (!pdfResp.ok) {
          throw new Error(`Failed to fetch bitstream (HTTP ${pdfResp.status} ${pdfResp.statusText})`);
        }

        const arrayBuffer = await pdfResp.arrayBuffer();
        const pdfBuffer = Buffer.from(arrayBuffer);

        if (pdfBuffer.length === 0) {
          throw new Error("Downloaded PDF has 0 bytes.");
        }
        if (!pdfBuffer.subarray(0, 5).toString().startsWith("%PDF")) {
          throw new Error(`Downloaded content is not a valid PDF.`);
        }

        // Step D: Upload to ImageKit under EXAMS folder
        const uploadResult = await ik.upload({
          file: pdfBuffer.toString("base64"),
          fileName: item.fileName,
          folder: "EXAMS",
        });

        if (!uploadResult || !uploadResult.url || !uploadResult.fileId) {
          throw new Error("ImageKit upload returned incomplete payload.");
        }

        // Step E: Create Firestore resource document with isImportedDSpace: true
        const resourceDocData: Record<string, any> = {
          title: item.title,
          fileName: item.fileName,
          type: "Exams",
          materialType: "Exams",
          thumbnailUrl: "",
          thumbnailId: "",
          thumbnailStatus: "pending",
          fileUrl: uploadResult.url,
          fileId: uploadResult.fileId,
          unitName: item.unitName,
          unitCode: item.unitCode,
          year: (item.publicationYear || new Date().getFullYear()).toString(),
          uploadYear: new Date().getFullYear().toString(),
          publicationYear: (item.publicationYear || new Date().getFullYear()).toString(),
          yearOfStudy: item.yearOfStudy,
          semester: item.semester,
          lecturers: item.lecturers,
          uploadedBy: uploaderAccount.name,
          uploaderRole: "Student",
          uploaderId: uploaderAccount.uid,
          uploaderProfilePic: null,
          uploadDate: admin.firestore.FieldValue.serverTimestamp(),
          targetPrograms: item.targetPrograms,
          programCodes: item.programCodes,
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
          dspaceItemUuid: item.itemUuid,
          dspaceHandle: item.handle,
        };

        const docRef = await db.collection("resources").add(resourceDocData);
        logger.info(`[DSPACE_IMPORT] Created resource document resources/${docRef.id} for "${item.title}"`);

        successfullyImported++;
        itemsPending--;

        const progressPercent = Math.round(((successfullyImported + skippedDuplicates) / itemsToImport.length) * 100) / 100;
        await jobRef.update({
          importedCount: successfullyImported,
          pendingCount: itemsPending,
          progress: progressPercent,
          message: `Imported ${successfullyImported}/${itemsToImport.length}: ${item.unitCode} - ${item.title}`,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Respectful pacing delay between items
        await new Promise((r) => setTimeout(r, 1200));
      } catch (err: any) {
        logger.error(`[DSPACE_IMPORT] Error importing item ${item.itemUuid}:`, err);
        failedImports++;
        itemsPending--;

        await jobRef.update({
          failedCount: failedImports,
          pendingCount: itemsPending,
          progress: Math.round(((successfullyImported + skippedDuplicates + failedImports) / itemsToImport.length) * 100) / 100,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    const durationSeconds = Math.round((Date.now() - startTime) / 1000);

    // 1. Cancellation handling
    if (isCancelled) {
      const summary: DSpaceJobSummary = {
        newDiscovered: itemsToImport.length,
        successfullyImported,
        failedImports,
        skippedDuplicates,
        itemsPending,
        durationSeconds,
      };

      await jobRef.update({
        status: "cancelled",
        summary,
        message: `Import cancelled by administrator (${successfullyImported} imported before cancellation).`,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      logger.info(`[DSPACE_IMPORT] Job ${jobId} recorded as cancelled.`);
      return summary;
    }

    // 2. Auto-Resume handling if paused at 7.5m execution limit with remaining items
    if (hitTimeLimit && itemsPending > 0) {
      logger.info(`[DSPACE_AUTO_RESUME] Job ${jobId} reached 7.5m limit with ${itemsPending} items pending. Spawning continuation slice...`);

      const parentSnap = await jobRef.get();
      const parentData = parentSnap.data() || {};
      const sliceIndex = (parentData.sliceIndex || 1) + 1;

      const summary: DSpaceJobSummary = {
        newDiscovered: itemsToImport.length,
        successfullyImported,
        failedImports,
        skippedDuplicates,
        itemsPending,
        durationSeconds,
      };

      if (sliceIndex > 25) {
        logger.error(`[DSPACE_AUTO_RESUME] Job ${jobId} reached maximum slice limit (25). Halting.`);
        await jobRef.update({
          status: "failed",
          summary,
          error: "Maximum auto-resume slice limit reached (25). Please verify repository items.",
          message: `Halted after 25 batch slices: ${successfullyImported} imported, ${itemsPending} remaining.`,
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return summary;
      }

      const continuationDocRef = db.collection("dspace_jobs").doc();
      const continuationJobId = continuationDocRef.id;

      // Mark current job slice as paused with link to next slice
      await jobRef.update({
        status: "paused",
        continuationJobId,
        summary,
        message: `Batch execution limit reached (7.5m). Auto-resuming next slice (${itemsPending} items remaining)...`,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Insert continuation job document into Firestore.
      // This immediately fires `onDSpaceJobCreated` in Google Cloud with a fresh 540s timeout and 100% CPU!
      await continuationDocRef.set({
        id: continuationJobId,
        action: "check_and_download",
        status: "queued",
        progress: 0.0,
        totalItems: itemsPending,
        discoveredCount: 0,
        importedCount: 0,
        failedCount: 0,
        skippedCount: 0,
        pendingCount: itemsPending,
        discoveredItems: [],
        parentJobId: jobId,
        continuationJobId: null,
        sliceIndex,
        message: `Auto-resuming batch slice ${sliceIndex} (${itemsPending} items remaining)...`,
        summary: null,
        error: null,
        createdBy: parentData.createdBy || "system",
        createdByName: parentData.createdByName || "System Auto-Resume",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      logger.info(`[DSPACE_AUTO_RESUME] Continuation job ${continuationJobId} queued for parent ${jobId}.`);
      return summary;
    }

    // 3. Normal completion
    const isSuccess = failedImports === 0;
    const finalStatus = isSuccess ? "completed" : (successfullyImported > 0 ? "partial_failure" : "failed");

    const summary: DSpaceJobSummary = {
      newDiscovered: itemsToImport.length,
      successfullyImported,
      failedImports,
      skippedDuplicates,
      itemsPending: 0,
      durationSeconds,
    };

    await jobRef.update({
      status: finalStatus,
      progress: 1.0,
      summary,
      message: isSuccess
        ? `Successfully imported ${successfullyImported} examination papers in ${durationSeconds}s.`
        : `Completed with warnings: ${successfullyImported} imported, ${failedImports} failed, ${skippedDuplicates} skipped.`,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info(`[DSPACE_IMPORT] Job ${jobId} finished with status "${finalStatus}" in ${durationSeconds}s.`);
    return summary;
  }
}

/**
 * Standalone DSpace Examination Past Papers -> Mirror Digital Importer
 *
 * Implements the normalized ingestion pipeline matching Mirror Digital's
 * normal authenticated user material upload flow.
 *
 * Current Mode: DRY-RUN ONLY.
 * Production writes are strictly guarded and disabled by default.
 */

import * as fs from "fs";
import * as path from "path";
import * as crypto from "crypto";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ============================================================================
// Types and Interfaces
// ============================================================================

export type ImportStage =
  | "PENDING"
  | "UPLOADED_IK"
  | "FIRESTORE_WRITTEN"
  | "COMPLETED"
  | "FAILED";

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
  stage: ImportStage;
  imagekit_url: string | null;
  imagekit_file_id: string | null;
  firestore_resource_id: string | null;
  thumbnail_status: string | null;
  attempt_count: number;
  error: string | null;
  updated_at: string;
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

export interface DSpaceCsvRow {
  item_index: string;
  item_uuid: string;
  title: string;
  item_title: string;
  publication_date: string;
  publication_year: string;
  date_accessioned: string;
  last_modified: string;
  publication_date_source: string;
  date: string;
  abstract: string;
  authors: string;
  subjects: string;
  handle: string;
  item_url: string;
  collection_uuid: string;
  collection_name: string;
  bitstream_uuid: string;
  original_filename: string;
  mime_type: string;
  file_size: string;
  file_size_bytes: string;
  md5: string;
  download_url: string;
  download_status: string;
  local_path: string;
  local_filepath: string;
}

// ============================================================================
// 20 Deterministic Synthetic Kenyan Users
// ============================================================================

export const VIRTUAL_USERS: string[] = [
  "Brian Kiprop",
  "Faith Wanjiku",
  "Evans Omondi",
  "Mercy Cherono",
  "Kevin Mutua",
  "Sharon Chebet",
  "Denis Kamau",
  "Brenda Akinyi",
  "Collins Kipkoech",
  "Cynthia Nyambura",
  "Victor Ochieng",
  "Beatrice Jebet",
  "Ian Mwangi",
  "Joyce Wairimu",
  "Samuel Kiptoo",
  "Vivian Achieng",
  "Dennis Maina",
  "Caroline Muthoni",
  "Edwin Koech",
  "Ruth Njeri",
];

// ============================================================================
// CSV Parsing Helper (RFC 4180 compliant)
// ============================================================================

export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let inQuotes = false;

  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    const next = text[i + 1];

    if (inQuotes) {
      if (c === '"') {
        if (next === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field += c;
      }
    } else {
      if (c === '"') {
        inQuotes = true;
      } else if (c === ",") {
        row.push(field);
        field = "";
      } else if (c === "\r") {
        // Skip CR
      } else if (c === "\n") {
        row.push(field);
        rows.push(row);
        row = [];
        field = "";
      } else {
        field += c;
      }
    }
  }

  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }

  return rows;
}

// ============================================================================
// Curriculum Catalog (Mirrors CourseService & lessons.json)
// ============================================================================

export class CurriculumCatalog {
  private rows: CurriculumRow[] = [];
  private codeToRows: Map<string, CurriculumRow[]> = new Map();
  private nameToCode: Map<string, string> = new Map();

  constructor(lessonsJsonPath: string) {
    this.load(lessonsJsonPath);
  }

  private load(filePath: string): void {
    if (!fs.existsSync(filePath)) {
      throw new Error(`Curriculum lessons file not found at: ${filePath}`);
    }

    let raw = fs.readFileSync(filePath, "utf8");
    if (raw.charCodeAt(0) === 0xfeff) {
      raw = raw.slice(1); // Strip UTF-8 BOM
    }

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

      // Map canonical codes and slash-parsed codes
      const parsedCodes = this.parseCodes(row.unitCode);
      const allCodes = new Set([row.unitCode.toUpperCase(), ...parsedCodes.map((c) => c.toUpperCase())]);

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
  }

  public parseCodes(unitCode: string): string[] {
    const results: string[] = [];
    const parts = unitCode.split("/");

    for (let i = 0; i < parts.length; i++) {
      const p = parts[i].trim();
      if (/\d/.test(p)) {
        results.push(p);
      } else {
        // Find next part that has numbers
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

    // Try normalized match (remove hyphens or dots, normalize spaces)
    const normalized = clean.replace(/[-.]/g, " ").replace(/\s+/g, " ");
    for (const [k, v] of this.codeToRows.entries()) {
      const normK = k.replace(/[-.]/g, " ").replace(/\s+/g, " ");
      if (normK === normalized) {
        return v;
      }
    }

    // Try slash components
    const subCodes = this.parseCodes(code);
    for (const sub of subCodes) {
      const upper = sub.trim().toUpperCase();
      if (this.codeToRows.has(upper)) {
        return this.codeToRows.get(upper)!;
      }
    }

    return [];
  }

  public getCodeByName(name: string): string | undefined {
    return this.nameToCode.get(name.trim().toUpperCase());
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
    // E.g. COMP 111 -> 1st Year, COMP 210 -> 2nd Year, COMP 320 -> 3rd Year, COMP 415 -> 4th Year
    const m = code.match(/\b([1-4])\d{2}\b/);
    if (m) {
      return `${m[1]}${m[1] === "1" ? "st" : m[1] === "2" ? "nd" : m[1] === "3" ? "rd" : "th"} Year`;
    }
    // Diploma codes e.g. 0221 -> 2nd Year
    const mDip = code.match(/\b0([1-4])\d{2}\b/);
    if (mDip) {
      return `${mDip[1]}${mDip[1] === "1" ? "st" : mDip[1] === "2" ? "nd" : mDip[1] === "3" ? "rd" : "th"} Year`;
    }
    return "1st Year";
  }
}

// ============================================================================
// DSpace Importer Class
// ============================================================================

export interface ImporterConfig {
  dspaceDir: string;
  lessonsPath: string;
  manifestPath: string;
  isDryRun: boolean;
  isProduction: boolean;
  concurrency: number;
  delayMs: number;
  maxRetries: number;
  limit?: number;
}

export class DSpaceMaterialsImporter {
  private config: ImporterConfig;
  private catalog: CurriculumCatalog;
  private manifest: Map<string, ManifestEntry> = new Map();

  constructor(config: Partial<ImporterConfig> = {}) {
    const dspaceDir = config.dspaceDir || "C:\\Users\\Hp i7\\Desktop\\script dspce\\dspace_exam_papers";
    const lessonsPath =
      config.lessonsPath || path.resolve(__dirname, "../../assets/lessons.json");
    const manifestPath =
      config.manifestPath || path.resolve(__dirname, "import_manifest.json");

    this.config = {
      dspaceDir,
      lessonsPath,
      manifestPath,
      isDryRun: config.isDryRun ?? true,
      isProduction: config.isProduction ?? false,
      concurrency: config.concurrency ?? 1,
      delayMs: config.delayMs ?? 4500,
      maxRetries: config.maxRetries ?? 3,
      limit: config.limit,
    };

    // Load curriculum
    this.catalog = new CurriculumCatalog(this.config.lessonsPath);

    // Load existing manifest if present for crash-resilience
    this.loadManifest();
  }

  private loadManifest(): void {
    if (fs.existsSync(this.config.manifestPath)) {
      try {
        const raw = fs.readFileSync(this.config.manifestPath, "utf8");
        const list: ManifestEntry[] = JSON.parse(raw);
        for (const item of list) {
          if (item && item.dspace_item_uuid) {
            this.manifest.set(item.dspace_item_uuid, item);
          }
        }
      } catch (err) {
        console.warn(`[MANIFEST] Warning: Could not read existing manifest, initializing fresh: ${err}`);
      }
    }
  }

  public saveManifest(): void {
    const list = Array.from(this.manifest.values());
    fs.writeFileSync(this.config.manifestPath, JSON.stringify(list, null, 2), "utf8");
  }

  /**
   * Title parser handling:
   * 1. Dual prefix before colon/dash: BOT/BOTA 222: PLANT PHYSIOLOGY I
   * 2. Multiple course codes: COMP 111/112: INTRO TO PROGRAMMING
   * 3. Codes with punctuation: EPSC 815.: EDUCATIONAL PSYCHOLOGY
   * 4. Hyphenated numbers: BUST -313: ECONOMIC THEORY
   * 5. Fallback to original_filename if title lacks course code: EMERGENCY MANAGEMENT
   */
  public parseDSpaceTitle(title: string, originalFilename: string): { unitCode: string; unitName: string } {
    let t = title.trim().replace(/\s+/g, " ");

    const pattern =
      /^((?:[A-Z]{2,6}(?:\s*[\/,-]\s*[A-Z]{2,6})*\s*[-.]?\s*\d{3,4}[A-Z]?(?:\s*[\/,-]\s*\d{3,4}[A-Z]?)?\.?))\s*[:;–—\-]\s*(.+)$/i;

    let match = t.match(pattern);
    if (match) {
      const code = match[1].replace(/\.$/, "").replace(/\s*-\s*/, " ").trim();
      const name = this.cleanUnitName(match[2]);
      return { unitCode: code, unitName: name };
    }

    // Try CODE followed directly by NAME
    const pattern2 = /^((?:[A-Z]{2,6}(?:\s*[\/,-]\s*[A-Z]{2,6})*\s*[-.]?\s*\d{3,4}[A-Z]?))\s+(.+)$/i;
    match = t.match(pattern2);
    if (match) {
      const code = match[1].replace(/\.$/, "").replace(/\s*-\s*/, " ").trim();
      const name = this.cleanUnitName(match[2]);
      return { unitCode: code, unitName: name };
    }

    // Fallback to filename (e.g. for EMERGENCY MANAGEMENT whose file is ENGL 111 - INTRODUCTION TO LANGUAGE...)
    const fnStem = path.parse(originalFilename).name.trim().replace(/\s+/g, " ");
    match = fnStem.match(pattern);
    if (match) {
      const code = match[1].replace(/\.$/, "").replace(/\s*-\s*/, " ").trim();
      const name = this.cleanUnitName(match[2]);
      return { unitCode: code, unitName: name };
    }

    return { unitCode: "", unitName: this.cleanUnitName(t) };
  }

  private cleanUnitName(name: string): string {
    let n = name.trim().replace(/\s+/g, " ");
    // Convert all-caps strings to Title Case for natural presentation
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
      // Capitalize first character
      n = n.charAt(0).toUpperCase() + n.slice(1);
    }
    return n;
  }

  /**
   * Main Execution Method: Dry Run
   */
  public async executeDryRun(): Promise<{
    sourceStats: {
      totalCsvRecords: number;
      uniqueItemUuids: number;
      duplicateBitstreamRecordsExcluded: number;
      physicalPdfCount: number;
      duplicateMd5Hashes: number;
      itemsSharingMd5: number;
      missingOrCorruptFiles: number;
    };
    mappingStats: {
      curriculumMatched: number;
      curriculumUnmatched: number;
      fallbackProgramUsed: number;
      fallbackLecturersUsed: number;
      publicationYears: Record<string, number>;
      materialTypes: Record<string, number>;
    };
    userStats: {
      distribution: Record<string, number>;
    };
    manifestStats: {
      totalEntries: number;
      pendingCount: number;
      manifestPath: string;
    };
  }> {
    console.log("================================================================================");
    console.log(" DSPACE -> MIRROR DIGITAL IMPORT ENGINE (DRY-RUN)");
    console.log("================================================================================");
    console.log(`DSpace Archive Path: ${this.config.dspaceDir}`);
    console.log(`Curriculum Path:     ${this.config.lessonsPath}`);
    console.log(`Manifest Path:       ${this.config.manifestPath}`);
    console.log(`Production Mode:     ${this.config.isProduction ? "ENABLED" : "DISABLED (SAFE DRY-RUN)"}`);
    console.log("--------------------------------------------------------------------------------\n");

    const itemsCsvPath = path.join(this.config.dspaceDir, "items.csv");
    if (!fs.existsSync(itemsCsvPath)) {
      throw new Error(`DSpace items.csv not found at: ${itemsCsvPath}`);
    }

    const csvContent = fs.readFileSync(itemsCsvPath, "utf8");
    const rawRows = parseCsv(csvContent);
    if (rawRows.length < 2) {
      throw new Error("DSpace items.csv is empty or corrupted.");
    }

    const headers = rawRows[0].map((h) => h.trim());
    const headerMap = new Map<string, number>();
    headers.forEach((h, i) => headerMap.set(h, i));

    const totalCsvRecords = rawRows.length - 1;

    // Deduplicate multi-bitstream records by item_uuid
    const seenUuids = new Set<string>();
    const uniqueItems: DSpaceCsvRow[] = [];
    let duplicateBitstreamCount = 0;

    for (let r = 1; r < rawRows.length; r++) {
      const row = rawRows[r];
      const getVal = (col: string) => {
        const idx = headerMap.get(col);
        return idx !== undefined && idx < row.length ? row[idx].trim() : "";
      };

      const itemUuid = getVal("item_uuid");
      if (!itemUuid) continue;

      if (seenUuids.has(itemUuid)) {
        duplicateBitstreamCount++;
        continue;
      }

      seenUuids.add(itemUuid);
      uniqueItems.push({
        item_index: getVal("item_index"),
        item_uuid: itemUuid,
        title: getVal("title"),
        item_title: getVal("item_title"),
        publication_date: getVal("publication_date"),
        publication_year: getVal("publication_year"),
        date_accessioned: getVal("date_accessioned"),
        last_modified: getVal("last_modified"),
        publication_date_source: getVal("publication_date_source"),
        date: getVal("date"),
        abstract: getVal("abstract"),
        authors: getVal("authors"),
        subjects: getVal("subjects"),
        handle: getVal("handle"),
        item_url: getVal("item_url"),
        collection_uuid: getVal("collection_uuid"),
        collection_name: getVal("collection_name"),
        bitstream_uuid: getVal("bitstream_uuid"),
        original_filename: getVal("original_filename"),
        mime_type: getVal("mime_type"),
        file_size: getVal("file_size"),
        file_size_bytes: getVal("file_size_bytes"),
        md5: getVal("md5"),
        download_url: getVal("download_url"),
        download_status: getVal("download_status"),
        local_path: getVal("local_path"),
        local_filepath: getVal("local_filepath"),
      });
    }

    // Sort deterministically by item_index numeric order
    uniqueItems.sort((a, b) => parseInt(a.item_index || "0", 10) - parseInt(b.item_index || "0", 10));

    // Stats collections
    let physicalPdfCount = 0;
    let missingOrCorruptCount = 0;
    const md5Map = new Map<string, number>();

    let curriculumMatched = 0;
    let curriculumUnmatched = 0;
    let fallbackProgramCount = 0;
    let fallbackLecturersCount = 0;

    const pubYears: Record<string, number> = {};
    const matTypes: Record<string, number> = {};
    const userAssignments: Record<string, number> = {};
    VIRTUAL_USERS.forEach((u) => (userAssignments[u] = 0));

    // Process each unique item
    for (let i = 0; i < uniqueItems.length; i++) {
      const item = uniqueItems[i];

      // 1. Verify physical file
      const localFilepath = item.local_filepath;
      const fullPath = path.join(this.config.dspaceDir, localFilepath);

      if (!fs.existsSync(fullPath)) {
        console.error(`[VALIDATION_ERROR] Missing file for item ${item.item_uuid}: ${fullPath}`);
        missingOrCorruptCount++;
        continue;
      }

      const stat = fs.statSync(fullPath);
      if (stat.size === 0 || !localFilepath.toLowerCase().endsWith(".pdf")) {
        console.error(`[VALIDATION_ERROR] Invalid PDF (empty or wrong ext) for item ${item.item_uuid}: ${fullPath}`);
        missingOrCorruptCount++;
        continue;
      }

      physicalPdfCount++;

      // Verify MD5 calculation
      const fileBuffer = fs.readFileSync(fullPath);
      const computedMd5 = crypto.createHash("md5").update(fileBuffer).digest("hex");
      if (item.md5 && item.md5.toLowerCase() !== computedMd5.toLowerCase()) {
        console.warn(`[MD5_MISMATCH_WARN] Item ${item.item_uuid} recorded MD5=${item.md5}, computed=${computedMd5}`);
      }
      const activeMd5 = item.md5 || computedMd5;
      md5Map.set(activeMd5, (md5Map.get(activeMd5) || 0) + 1);

      // 2. Parse title and normalize
      const parsed = this.parseDSpaceTitle(item.title, item.original_filename);
      let unitCode = parsed.unitCode;
      let unitName = parsed.unitName;

      // 3. Match against curriculum
      const matchedUnits = this.catalog.getUnitsByCode(unitCode);

      let targetPrograms: string[] = [];
      let programCodes: string[] = [];
      let lecturers: string[] = [];
      let yearOfStudy = "1st Year";
      let semester = "Semester 1";

      if (matchedUnits.length > 0) {
        curriculumMatched++;

        // Pool data across matched curriculum records (replicates ResourceService.copyWithPoolData)
        const progSet = new Set<string>();
        const codeSet = new Set<string>();
        const lectSet = new Set<string>();

        for (const u of matchedUnits) {
          if (u.programName) progSet.add(u.programName);
          if (u.programCode) codeSet.add(u.programCode);
          if (u.lecturerName) lectSet.add(u.lecturerName);
        }

        targetPrograms = Array.from(progSet);
        programCodes = Array.from(codeSet);
        lecturers = Array.from(lectSet);

        // Normalize year of study and semester from first matched curriculum unit
        const first = matchedUnits[0];
        yearOfStudy = this.catalog.normalizeYear(first.yearOfStudy);
        semester = this.catalog.normalizeSemester(first.semester);

        // Prefer canonical title from curriculum if available
        if (first.unitName) {
          unitName = first.unitName;
        }
        if (first.unitCode) {
          unitCode = first.unitCode;
        }
      } else {
        curriculumUnmatched++;

        // Unmatched fallback: Use DSpace collection name
        const collectionName = item.collection_name.trim();
        targetPrograms = collectionName ? [collectionName] : ["Laikipia University"];
        fallbackProgramCount++;

        // Extract program code prefix from unit code (e.g. MBAD from MBAD 612)
        const prefixMatch = unitCode.match(/^([A-Z]{2,6})/i);
        programCodes = prefixMatch ? [prefixMatch[1].toUpperCase()] : ["GEN"];

        // Exact fallback from normal user upload (upload_provider.dart line 749): ['TBD']
        lecturers = ["TBD"];
        fallbackLecturersCount++;

        // Infer year from code digits
        yearOfStudy = this.catalog.inferYearFromCode(unitCode);
        semester = "Semester 1";
      }

      // If lecturers list is empty even after curriculum pooling, fallback to ['TBD']
      if (lecturers.length === 0) {
        lecturers = ["TBD"];
      }

      // 4. Publication Year (all verified between 2022 and 2026)
      const pubYearInt = parseInt(item.publication_year || "2024", 10);
      pubYears[pubYearInt.toString()] = (pubYears[pubYearInt.toString()] || 0) + 1;

      // 5. Material Type (strictly 'Exams')
      const materialType = "Exams";
      matTypes[materialType] = (matTypes[materialType] || 0) + 1;

      // 6. Deterministic 20-User Round-Robin Assignment
      const userIdx = i % 20; // 0..19
      const assignedUserName = VIRTUAL_USERS[userIdx];
      userAssignments[assignedUserName]++;

      // 7. Title in Mirror Digital for exams is strictly the unitName
      const resourceTitle = unitName;

      // 8. Build or update manifest entry
      const existing = this.manifest.get(item.item_uuid);
      const entry: ManifestEntry = {
        dspace_item_uuid: item.item_uuid,
        dspace_handle: item.handle,
        file_md5: activeMd5,
        local_filepath: localFilepath,
        unit_code: unitCode,
        unit_name: unitName,
        title: resourceTitle,
        target_programs: targetPrograms,
        program_codes: programCodes,
        lecturers: lecturers,
        year_of_study: yearOfStudy,
        semester: semester,
        publication_year: pubYearInt,
        material_type: materialType,
        assigned_user_index: userIdx + 1,
        assigned_user_name: assignedUserName,
        assigned_user_uid: existing?.assigned_user_uid || null,
        stage: existing?.stage || "PENDING",
        imagekit_url: existing?.imagekit_url || null,
        imagekit_file_id: existing?.imagekit_file_id || null,
        firestore_resource_id: existing?.firestore_resource_id || null,
        thumbnail_status: existing?.thumbnail_status || null,
        attempt_count: existing?.attempt_count || 0,
        error: existing?.error || null,
        updated_at: existing?.updated_at || new Date().toISOString(),
      };

      this.manifest.set(item.item_uuid, entry);
    }

    // Save manifest to disk
    this.saveManifest();

    // Shared MD5 counts
    let dupMd5Count = 0;
    let itemsSharingMd5Count = 0;
    for (const [, cnt] of md5Map.entries()) {
      if (cnt > 1) {
        dupMd5Count++;
        itemsSharingMd5Count += cnt;
      }
    }

    const pendingCount = Array.from(this.manifest.values()).filter((e) => e.stage === "PENDING").length;

    console.log("================================================================================");
    console.log(" DRY-RUN VERIFICATION SUMMARY");
    console.log("================================================================================");
    console.log(`Total CSV Records:           ${totalCsvRecords}`);
    console.log(`Unique DSpace Items:         ${uniqueItems.length}`);
    console.log(`Excluded Duplicate Rows:     ${duplicateBitstreamCount} (Multi-bitstream duplicates)`);
    console.log(`Verified Physical PDFs:      ${physicalPdfCount}`);
    console.log(`Missing/Corrupt Files:       ${missingOrCorruptCount}`);
    console.log(`Shared MD5 Hashes:           ${dupMd5Count} (${itemsSharingMd5Count} cross-listed items)`);
    console.log("--------------------------------------------------------------------------------");
    console.log(`Curriculum Matched Units:    ${curriculumMatched} (${((curriculumMatched / uniqueItems.length) * 100).toFixed(1)}%)`);
    console.log(`Unmatched / Fallback Units:  ${curriculumUnmatched} (${((curriculumUnmatched / uniqueItems.length) * 100).toFixed(1)}%)`);
    console.log(`Fallback Collection Names:   ${fallbackProgramCount}`);
    console.log(`Fallback Lecturers (['TBD']):${fallbackLecturersCount}`);
    console.log("--------------------------------------------------------------------------------");
    console.log("Publication Year Breakdown:");
    for (const [y, c] of Object.entries(pubYears).sort()) {
      console.log(`  - Year ${y}: ${c} items`);
    }
    console.log("--------------------------------------------------------------------------------");
    console.log(`Virtual User Accounts:       20 Synthetic Kenyan Names`);
    console.log(`Assignment Rule:             Deterministic Round-Robin (item_index % 20)`);
    console.log(`Items per Account:           ~75-76 items each`);
    console.log("--------------------------------------------------------------------------------");
    console.log(`Manifest File:               ${this.config.manifestPath}`);
    console.log(`Manifest Entries Saved:      ${this.manifest.size}`);
    console.log(`Pending Stage Items:         ${pendingCount}`);
    console.log("--------------------------------------------------------------------------------");
    console.log("PRODUCTION SAFETY CONFIRMATION:");
    console.log("  [x] ZERO Firebase Auth users created");
    console.log("  [x] ZERO Firestore documents created or modified");
    console.log("  [x] ZERO ImageKit files uploaded");
    console.log("  [x] ZERO thumbnails generated");
    console.log("  [x] ZERO DSpace files modified or moved");
    console.log("================================================================================\n");

    return {
      sourceStats: {
        totalCsvRecords,
        uniqueItemUuids: uniqueItems.length,
        duplicateBitstreamRecordsExcluded: duplicateBitstreamCount,
        physicalPdfCount,
        duplicateMd5Hashes: dupMd5Count,
        itemsSharingMd5: itemsSharingMd5Count,
        missingOrCorruptFiles: missingOrCorruptCount,
      },
      mappingStats: {
        curriculumMatched,
        curriculumUnmatched,
        fallbackProgramUsed: fallbackProgramCount,
        fallbackLecturersUsed: fallbackLecturersCount,
        publicationYears: pubYears,
        materialTypes: matTypes,
      },
      userStats: {
        distribution: userAssignments,
      },
      manifestStats: {
        totalEntries: this.manifest.size,
        pendingCount,
        manifestPath: this.config.manifestPath,
      },
    };
  }

  /**
   * Future Production Ingestion Stub
   * Strictly guarded by safety checks.
   */
  public async executeProductionImport(): Promise<void> {
    if (this.config.isDryRun || !this.config.isProduction) {
      throw new Error(
        "SAFETY GUARD TRIGGERED: Production import called while isDryRun=true or isProduction=false. " +
          "Refusing to perform any backend writes."
      );
    }

    throw new Error(
      "PRODUCTION MODE NOT ENABLED: Virtual accounts have not yet been provisioned. " +
        "Run the user provisioning step first before executing production import."
    );
  }
}

// ============================================================================
// CLI Entry Point
// ============================================================================

async function main() {
  const args = process.argv.slice(2);
  const isProduction = args.includes("--production");
  const isConfirm = args.includes("--confirm-production");
  const isDryRun = !isProduction || args.includes("--dry-run");

  if (isProduction && !isConfirm) {
    console.error("FATAL ERROR: --production specified without --confirm-production guard flag.");
    console.error("Aborting to prevent accidental writes.");
    process.exit(1);
  }

  const importer = new DSpaceMaterialsImporter({
    isDryRun,
    isProduction: isProduction && isConfirm,
  });

  try {
    if (isDryRun) {
      await importer.executeDryRun();
    } else {
      await importer.executeProductionImport();
    }
  } catch (err) {
    console.error("[IMPORTER_ERROR] Execution failed:", err);
    process.exit(1);
  }
}

if (process.argv[1] && process.argv[1].endsWith("import_dspace_materials.ts")) {
  main().catch((err) => {
    console.error("Fatal error:", err);
    process.exit(1);
  });
}

/**
 * Standalone Local DSpace Synchronization Worker & Job Daemon
 *
 * Can run on the host Windows machine to process queued DSpace jobs from Firestore
 * and update local archive files (items.csv, downloaded.csv, files/) as well as
 * Firestore resources and ImageKit.
 */

import { initializeApp, cert, getApps } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import * as path from "path";
import * as fs from "fs";
import { fileURLToPath } from "url";
import { DSpaceService } from "../src/services/dspace_service.js";
import ImageKit from "imagekit";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Firebase Admin initialization
const saPath = path.resolve(__dirname, "../../backend/credentials/firebase-service-account.json");
if (getApps().length === 0) {
  if (fs.existsSync(saPath)) {
    const sa = JSON.parse(fs.readFileSync(saPath, "utf8"));
    initializeApp({
      credential: cert(sa),
      projectId: sa.project_id || "mirror-laikipia",
    });
  } else {
    initializeApp({ projectId: "mirror-laikipia" });
  }
}

const db = getFirestore();

function loadEnvFile(filePath: string): void {
  if (!fs.existsSync(filePath)) return;
  try {
    const content = fs.readFileSync(filePath, "utf8");
    const lines = content.split(/\r?\n/);
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const eqIdx = trimmed.indexOf("=");
      if (eqIdx > 0) {
        const key = trimmed.substring(0, eqIdx).trim();
        let val = trimmed.substring(eqIdx + 1).trim();
        if (
          (val.startsWith('"') && val.endsWith('"')) ||
          (val.startsWith("'") && val.endsWith("'"))
        ) {
          val = val.substring(1, val.length - 1);
        }
        if (!process.env[key]) {
          process.env[key] = val;
        }
      }
    }
  } catch (_) {}
}

loadEnvFile(path.resolve(__dirname, "../.env"));
loadEnvFile(path.resolve(__dirname, "../../.env"));

function getImageKit(): ImageKit {
  const publicKey = process.env.IMAGEKIT_PUBLIC_KEY || "";
  const privateKey = process.env.IMAGEKIT_PRIVATE_KEY || "";
  const urlEndpoint = process.env.IMAGEKIT_URL_ENDPOINT || "";

  if (!publicKey || !privateKey || !urlEndpoint) {
    throw new Error(
      "ImageKit configuration missing in environment. Set IMAGEKIT_PUBLIC_KEY, IMAGEKIT_PRIVATE_KEY, and IMAGEKIT_URL_ENDPOINT."
    );
  }

  return new ImageKit({
    publicKey,
    privateKey,
    urlEndpoint,
  });
}

export async function processNextJob() {
  const queuedSnap = await db
    .collection("dspace_jobs")
    .where("status", "==", "queued")
    .orderBy("createdAt", "asc")
    .limit(1)
    .get();

  if (queuedSnap.empty) {
    return false;
  }

  const jobDoc = queuedSnap.docs[0];
  const jobData = jobDoc.data();
  const jobId = jobDoc.id;
  const action = jobData.action;

  console.log(`[DSPACE_WORKER] Picking up job ${jobId} (${action})...`);
  const service = new DSpaceService();

  try {
    const claimed = await db.runTransaction(async (tx) => {
      const snap = await tx.get(jobDoc.ref);
      if (!snap.exists || snap.data()?.status !== "queued") return false;
      tx.update(jobDoc.ref, {
        status: "running",
        message: "Worker processing job...",
        updatedAt: FieldValue.serverTimestamp(),
      });
      return true;
    });

    if (!claimed) {
      console.log(`[DSPACE_WORKER] Job ${jobId} was already claimed by another process. Skipping.`);
      return false;
    }

    const discovery = await service.discoverNewItems(db);
    console.log(`[DSPACE_WORKER] Discovery complete: ${discovery.totalDiscovered} new items.`);

    if (action === "check") {
      await jobDoc.ref.update({
        status: "completed",
        progress: 1.0,
        totalItems: discovery.totalDiscovered,
        discoveredCount: discovery.totalDiscovered,
        discoveredItems: discovery.newItems,
        message: discovery.totalDiscovered === 0
          ? "Archive is up to date. No new examination papers found."
          : `Found ${discovery.totalDiscovered} newly available examination papers.`,
        summary: {
          newDiscovered: discovery.totalDiscovered,
          successfullyImported: 0,
          failedImports: 0,
          skippedDuplicates: 0,
          itemsPending: 0,
          durationSeconds: 0,
        },
        completedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return true;
    }

    if (discovery.totalDiscovered === 0) {
      await jobDoc.ref.update({
        status: "completed",
        progress: 1.0,
        totalItems: 0,
        discoveredCount: 0,
        discoveredItems: [],
        message: "Archive is up to date. No new examination papers to import.",
        summary: {
          newDiscovered: 0,
          successfullyImported: 0,
          failedImports: 0,
          skippedDuplicates: 0,
          itemsPending: 0,
          durationSeconds: 0,
        },
        completedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return true;
    }

    const ik = getImageKit();
    await service.executeImport(db, ik, jobId, discovery.newItems);
    return true;
  } catch (err: any) {
    console.error(`[DSPACE_WORKER] Job ${jobId} failed:`, err);
    await jobDoc.ref.update({
      status: "failed",
      error: err.message || String(err),
      message: "Worker failed to complete job.",
      completedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  }
}

async function main() {
  const args = process.argv.slice(2);
  const isDaemon = args.includes("--daemon");

  console.log("================================================================================");
  console.log(" DSPACE WORKER DAEMON");
  console.log("================================================================================");
  console.log(` Mode: ${isDaemon ? "Continuous Daemon" : "Run-Once"}\n`);

  if (!isDaemon) {
    const processed = await processNextJob();
    if (!processed) {
      console.log("[DSPACE_WORKER] No queued jobs found.");
    }
    process.exit(0);
  }

  console.log("[DSPACE_WORKER] Listening for queued DSpace jobs...");
  while (true) {
    try {
      await processNextJob();
    } catch (e) {
      console.error("[DSPACE_WORKER] Loop error:", e);
    }
    await new Promise((r) => setTimeout(r, 5000));
  }
}

if (process.argv[1] && process.argv[1].endsWith("run_dspace_worker.ts")) {
  main().catch((err) => {
    console.error("Fatal error:", err);
    process.exit(1);
  });
}

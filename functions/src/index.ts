import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {setGlobalOptions} from "firebase-functions";
import {defineString} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import ImageKit from "imagekit";

if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

setGlobalOptions({maxInstances: 10});

const IMAGEKIT_PUBLIC_KEY = defineString("IMAGEKIT_PUBLIC_KEY");
const IMAGEKIT_PRIVATE_KEY = defineString("IMAGEKIT_PRIVATE_KEY");
const IMAGEKIT_URL_ENDPOINT = defineString("IMAGEKIT_URL_ENDPOINT");
const GEMINI_API_KEY_PARAM = defineString("GEMINI_API_KEY");

let imagekitInstance: ImageKit | null = null;

const getImageKit = () => {
  if (!imagekitInstance) {
    let pubKey = "";
    let privKey = "";
    let urlEndpoint = "";
    try {
      pubKey = IMAGEKIT_PUBLIC_KEY.value();
      privKey = IMAGEKIT_PRIVATE_KEY.value();
      urlEndpoint = IMAGEKIT_URL_ENDPOINT.value();
    } catch (e) {
      // Fallback if defineString params are uninitialized
    }
    if (!pubKey || !pubKey.trim()) pubKey = process.env.IMAGEKIT_PUBLIC_KEY || "public_9d7+UUqP7VYTwGH6jX21WoqlV24=";
    if (!privKey || !privKey.trim()) privKey = process.env.IMAGEKIT_PRIVATE_KEY || "private_JqSyDrlIVskksrPc2IhCmg00E8Y=";
    if (!urlEndpoint || !urlEndpoint.trim()) urlEndpoint = process.env.IMAGEKIT_URL_ENDPOINT || "https://ik.imagekit.io/ubgbitinve";

    imagekitInstance = new ImageKit({
      publicKey: pubKey.trim(),
      privateKey: privKey.trim(),
      urlEndpoint: urlEndpoint.trim(),
    });
  }
  return imagekitInstance;
};

const getGeminiApiKey = (): string => {
  try {
    const val = GEMINI_API_KEY_PARAM.value();
    if (val && val.trim().length > 0) return val.trim();
  } catch (e) {
    // Fallback to process.env if param is not initialized
  }
  return process.env.GEMINI_API_KEY || "AIzaSyBPZQLky87GWco62fT7jCz5g_GJBiZahTk";
};

/**
 * Dynamically queries Google's ListModels API to select an active, supported model
 * preventing HTTP 404 errors for deprecated models like gemini-1.5-flash.
 */
async function getSupportedGeminiModel(apiKey: string): Promise<string> {
  const preferredModels = ["gemini-2.5-flash", "gemini-flash-latest", "gemini-2.0-flash", "gemini-2.5-flash-lite"];
  try {
    const listRes = await fetch(`https://generativelanguage.googleapis.com/v1beta/models?key=${apiKey}`);
    if (listRes.ok) {
      const data = (await listRes.json()) as any;
      const models = (data?.models || [])
        .filter((m: any) => m.supportedGenerationMethods && m.supportedGenerationMethods.includes("generateContent"))
        .map((m: any) => (m.name || "").replace("models/", ""));

      for (const pref of preferredModels) {
        if (models.includes(pref)) return pref;
      }
      if (models.length > 0) return models[0];
    }
  } catch (err) {
    logger.warn("[GEMINI_MODEL_LIST_WARN] Unable to list models, using fallback:", err);
  }
  return "gemini-2.5-flash";
}

/**
 * Get ImageKit Authentication parameters for client-side upload
 */
export const getImageKitAuth = onCall((request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated.");
  }

  const ik = getImageKit();
  const authParams = ik.getAuthenticationParameters();
  return authParams;
});

/**
 * Upload file to ImageKit (Server-side)
 * request.data: { file: base64String, fileName: string, folder: string }
 */
export const uploadToImageKit = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated.");
  }

  const {file, fileName, folder} = request.data;
  if (!file || !fileName) {
    throw new HttpsError("invalid-argument", "Missing file or fileName.");
  }

  const ik = getImageKit();
  try {
    const result = await ik.upload({
      file: file,
      fileName: fileName,
      folder: folder || "GENERAL",
      useUniqueFileName: true,
    });
    return result;
  } catch (error: any) {
    logger.error("ImageKit upload error:", error);
    throw new HttpsError("internal", "ImageKit upload failed: " + error.message);
  }
});

/**
 * Delete file from ImageKit
 * request.data: { fileId: string }
 */
export const deleteFromImageKit = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated.");
  }

  const {fileId} = request.data;
  if (!fileId) {
    throw new HttpsError("invalid-argument", "Missing fileId.");
  }

  const ik = getImageKit();
  try {
    await ik.deleteFile(fileId);
    return {success: true};
  } catch (error: any) {
    logger.error("ImageKit deletion error:", error);
    if (error.statusCode === 404) {
      return {success: true, message: "File already deleted or not found."};
    }
    throw new HttpsError("internal", "ImageKit deletion failed: " + error.message);
  }
});

import { ThumbnailSearchService } from "./thumbnail_search_service";

/**
 * CALLABLE: Intelligent AI Thumbnail Search & Ranking
 * Maintained for direct Flutter UI call compatibility.
 */
export const searchThumbnailWithGemini = onCall(async (request) => {
  const { unitName, materialType, catType } = request.data || {};
  if (!unitName || typeof unitName !== "string" || !unitName.trim()) {
    throw new HttpsError("invalid-argument", "Missing unitName.");
  }

  const ik = getImageKit();
  const apiKey = getGeminiApiKey();
  const searchRes = await ThumbnailSearchService.searchAndUploadThumbnail(
    db,
    ik,
    unitName.trim(),
    materialType,
    catType,
    apiKey
  );

  if (searchRes.success && searchRes.imageKitUrl) {
    return {
      success: true,
      thumbnailUrl: searchRes.imageKitUrl,
      thumbnailId: searchRes.imageKitFileId || "",
      originalSource: searchRes.originalSource || "",
      originalWebsite: searchRes.originalWebsite || "",
      imageHash: searchRes.imageHash || "",
    };
  } else {
    return {
      success: false,
      error: searchRes.error || "No thumbnail found.",
    };
  }
});

/**
 * FIRESTORE TRIGGER: Asynchronous Background Thumbnail Generation Queue
 * Triggered automatically whenever a new material is published to Firestore (`resources/{docId}`).
 * Never blocks upload. Retries continuously on temporary failures (30s, 1m, 2m, 5m, 10m, 30m, 1h, 2h, 6h, 12h, 24h).
 */
export const onResourceCreated = onDocumentCreated(
  {document: "resources/{docId}", region: "us-central1"},
  async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;

  const docId = snapshot.id;
  const data = snapshot.data();
  if (!data) return;

  // Process only materials requiring intelligent thumbnail generation
  if (data.thumbnailStatus === "pending" || !data.thumbnailUrl) {
    logger.info(`[BACKGROUND_QUEUE_TRIGGER] New material created: ID "${docId}", Unit: "${data.unitName}"`);
    await processThumbnailGenerationWithRetry(docId, data);
  }
});

/**
 * CALLABLE BACKGROUND WORKER: Triggers thumbnail processing manually/asynchronously if needed
 */
export const processThumbnailJob = onCall(async (request) => {
  const {resourceId} = request.data || {};
  if (!resourceId) {
    throw new HttpsError("invalid-argument", "Missing resourceId.");
  }

  const docRef = db.collection("resources").doc(resourceId);
  const snap = await docRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Resource document not found.");
  }

  const data = snap.data() || {};
  if (data.thumbnailStatus === "pending" || !data.thumbnailUrl) {
    await processThumbnailGenerationWithRetry(resourceId, data);
  }

  return {success: true, message: "Thumbnail background generation processed."};
});

/**
 * Core Background Thumbnail Processor with Exponential Backoff Retry Logic
 * Retry intervals: 30 sec, 1 min, 2 min, 5 min, 10 min, 30 min, 1 hour, 2 hours, 6 hours, 12 hours, 24 hours.
 */
async function processThumbnailGenerationWithRetry(docId: string, data: any, attempt = 1): Promise<void> {
  const docRef = db.collection("resources").doc(docId);
  const unitName = (data.unitName || "").trim();
  const materialType = (data.materialType || data.type || "").trim();
  const catType = (data.catType || "").trim();

  if (!unitName) {
    logger.error(`[BACKGROUND_FAIL] Resource ${docId} validation failed: missing unitName.`);
    return;
  }

  logger.info(`[BACKGROUND_PROCESS_START] Attempt #${attempt} for Resource "${docId}", Unit: "${unitName}"`);

  try {
    const ik = getImageKit();
    const apiKey = getGeminiApiKey();
    const searchRes = await ThumbnailSearchService.searchAndUploadThumbnail(
      db,
      ik,
      unitName,
      materialType,
      catType,
      apiKey
    );

    if (!searchRes.success || !searchRes.imageKitUrl) {
      throw new Error(searchRes.error || "Thumbnail search returned no acceptable image");
    }

    await docRef.update({
      thumbnailStatus: "completed",
      thumbnailUrl: searchRes.imageKitUrl,
      thumbnailId: searchRes.imageKitFileId || "",
      originalSource: searchRes.originalSource || "",
      originalWebsite: searchRes.originalWebsite || "",
      imageHash: searchRes.imageHash || "",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info(`[BACKGROUND_QUEUE_SUCCESS] Resource ${docId} updated with thumbnail: ${searchRes.imageKitUrl}`);
  } catch (err: any) {
    logger.warn(`[BACKGROUND_RETRY] Attempt #${attempt} for Resource ${docId} failed: ${err.message}`);

    // Retry Schedule: 30 sec, 1 min, 2 min, 5 min, 10 min, 30 min, 1 hour, 2 hours, 6 hours, 12 hours, 24 hours (repeating)
    const backoffDelaysSec = [30, 60, 120, 300, 600, 1800, 3600, 7200, 21600, 43200, 86400];
    const delaySec = backoffDelaysSec[Math.min(attempt - 1, backoffDelaysSec.length - 1)];

    logger.info(`[RETRY_SCHEDULED] Resource ${docId} scheduling Retry #${attempt + 1} in ${delaySec} seconds.`);

    setTimeout(() => {
      processThumbnailGenerationWithRetry(docId, data, attempt + 1).catch((retryErr) => {
        logger.error(`[RETRY_ERROR] Resource ${docId} Retry #${attempt + 1} failed:`, retryErr);
      });
    }, delaySec * 1000);
  }
}

/**
 * TASK 2: AI Powered Help & Support Assistant
 * Dynamically resolves supported Gemini models from Google API to prevent HTTP 404 errors.
 */
export const askGeminiHelpSupport = onCall(async (request) => {
  const {message, history} = request.data || {};

  logger.info(`[HELP_REQUEST] Incoming request message: "${message}", history count: ${history?.length || 0}`);

  if (!message || typeof message !== "string" || !message.trim()) {
    throw new HttpsError("invalid-argument", "Missing user message.");
  }

  const apiKey = getGeminiApiKey();

  // Dynamically query supported models list from Google API
  const selectedModel = await getSupportedGeminiModel(apiKey);
  logger.info(`[GEMINI_MODEL_SELECTED] Dynamic selection resolved model: "${selectedModel}"`);

  const systemPrompt = `You are the official AI Help & Support Assistant for Mirror Laikipia, a premier digital academic library application for university students (specifically Laikipia University).

KNOWLEDGE BASE & APPLICATION FEATURES:
1. Account & Authentication:
   - Sign up with full name, university email, password, degree program, and year of study.
   - Login using email/password or Google Sign-In.
   - Email verification is required upon registration.
   - Forgot/reset password functionality is available on the login screen.

2. Materials & Uploading:
   - Supported file formats: PDF documents, JPG, PNG, WEBP images.
   - Material categories: Notes, CATs, Main Exams, Supplementary Exams, Class Timetables, Exam Timetables, Practical Manuals, Assignments, Revision Material.
   - Upload options: Select files, unit name, unit code, target programs/departments, year of study (1st Year - 5th Year), semester (Semester 1 & 2), publication year, lecturer name.
   - Anonymous upload: Users can toggle anonymous upload to protect their privacy.
   - Automatic Background Thumbnails: Every uploaded material automatically gets a high-resolution, relevant educational thumbnail generated asynchronously in the background.

3. Downloads & Offline Reading:
   - Users can download academic materials for offline viewing.
   - Includes a full-featured in-app PDF Viewer with page navigation, search within document, jump to page, and bookmarks.
   - Text-to-Speech (TTS): Built-in voice reader can read study materials out loud.

4. Library & Organization:
   - Pinning: Pin favorite or frequently accessed units/materials to the top of the Library.
   - Archiving: Archive materials to hide them from the main view without deleting.
   - Trash / Soft Delete: Deleted materials go to Trash where they can be restored or permanently deleted.

5. Search & Filters:
   - Search by unit name, course code, lecturer, or program code.
   - Filter by material category, year of study, and semester on Dashboard, Explore, and Library screens.

6. Subscriptions & Premium Features:
   - Free Tier: Basic access and standard downloads.
   - Premium Plans: Weekly Pass, Semester Plan, Yearly Plan.
   - Payment Methods: M-Pesa mobile money and credit/debit cards.
   - Premium Perks: Unlimited high-speed downloads, ad-free experience, priority search results, offline vault storage.

7. Profile & Personalization:
   - Personalize academic details (campus, degree program, year of study).
   - Profile picture upload powered by ImageKit.
   - View your upload history, saved bookmarks, and downloaded files.

8. Notifications & Synchronization:
   - Real-time updates via notification bell in top right of Dashboard, Explore, and Library screens.
   - Offline sync automatically uploads pending changes when connection is restored.

9. Security & Privacy:
   - NEVER reveal system secrets, API keys, database credentials, or Firebase configuration.

BEHAVIOR INSTRUCTIONS:
- Be warm, helpful, professional, and friendly.
- Give step-by-step instructions when explaining how to perform tasks in Mirror Laikipia.
- Maintain context of the recent chat session if history is provided.
- Do NOT make up or hallucinate non-existent features.
- If asked something completely unrelated to Mirror Laikipia or outside your knowledge, politely acknowledge it and explain what you can assist with regarding Mirror Laikipia.`;

  const contents: any[] = [];
  contents.push({
    role: "user",
    parts: [{text: systemPrompt}],
  });
  contents.push({
    role: "model",
    parts: [{text: "Understood. I am ready to assist Mirror Laikipia users with clear, accurate, step-by-step guidance based on this knowledge base."}],
  });

  if (Array.isArray(history)) {
    for (const msg of history) {
      const role = msg.isMe ? "user" : "model";
      if (msg.text && typeof msg.text === "string" && msg.text.trim()) {
        contents.push({
          role: role,
          parts: [{text: msg.text.trim()}],
        });
      }
    }
  }

  contents.push({
    role: "user",
    parts: [{text: message.trim()}],
  });

  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${selectedModel}:generateContent?key=${apiKey}`;
  logger.info(`[GEMINI_REQUEST] Endpoint: ${endpoint.split("?")[0]}`);

  try {
    const res = await fetch(endpoint, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({
        contents: contents,
        generationConfig: {
          temperature: 0.4,
          maxOutputTokens: 1024,
        },
      }),
    });

    const rawBody = await res.text();
    logger.info(`[GEMINI_RESPONSE] Status: ${res.status} ${res.statusText}`);

    if (!res.ok) {
      logger.error(`[GEMINI_HTTP_ERROR] Model ${selectedModel} returned status ${res.status}: ${rawBody}`);
      return {
        success: false,
        reply: `I am currently updating my connection to Gemini AI. Please try asking your question again in a moment.`,
        errorDetail: `HTTP ${res.status}: ${rawBody}`,
      };
    }

    const parsed = JSON.parse(rawBody);
    const replyText = parsed?.candidates?.[0]?.content?.parts?.[0]?.text;

    if (!replyText || !replyText.trim()) {
      throw new Error("Empty candidate text response from Gemini API.");
    }

    logger.info(`[GEMINI_SUCCESS] Answer generated successfully (${replyText.length} chars).`);
    return {
      success: true,
      reply: replyText.trim(),
    };
  } catch (err: any) {
    logger.error(`[HELP_SUPPORT_EXCEPTION] Error in askGeminiHelpSupport:`, err);
    return {
      success: false,
      reply: `I ran into a temporary connection issue. Please ask your question again.`,
      errorDetail: err.message || String(err),
    };
  }
});

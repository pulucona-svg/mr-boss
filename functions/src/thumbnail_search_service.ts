import * as admin from "firebase-admin";
import * as crypto from "crypto";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";
import sharp from "sharp";
import { EnvConfig } from "./config/env_config";

export interface MaterialMetadata {
  title: string;
  description?: string;
  summary?: string;
  courseCode?: string;
  unitCode?: string;
  materialType?: string;
  type?: string;
  topic?: string;
  category?: string;
  targetPrograms?: string | string[];
}

export interface ThumbnailSearchResult {
  success: boolean;
  imageKitUrl?: string;
  imageKitFileId?: string;
  originalSource?: string;
  originalWebsite?: string;
  imageHash?: string;
  reason?: string;
  score?: number;
  modelUsed?: string;
  error?: string;
}

export class ThumbnailSearchService {
  /**
   * Main Entry Point: Directly generates an AI visual thumbnail from the material's metadata using Gemini Image Generation.
   * Uploads the generated high-quality image directly to ImageKit (/THUMBNAILS/) and updates Firestore resources.thumbnailUrl.
   *
   * Strictly NO screenshot capture, NO SVG templates, NO external image searching (Pixabay/Wikimedia/Bing).
   */
  public static async searchAndUploadThumbnail(
    db: admin.firestore.Firestore,
    ik: ImageKit,
    titleOrMetadata: string | MaterialMetadata,
    materialType?: string,
    catTypeOrCourseCode?: string,
    geminiApiKey?: string
  ): Promise<ThumbnailSearchResult> {
    const meta: MaterialMetadata =
      typeof titleOrMetadata === "object" && titleOrMetadata !== null
        ? titleOrMetadata
        : {
            title: titleOrMetadata || "",
            materialType: materialType || "Notes",
            courseCode: catTypeOrCourseCode || "",
            description: catTypeOrCourseCode || "",
            topic: materialType || "",
          };

    const cleanTitle = (meta.title || "").trim();
    if (!cleanTitle) {
      return { success: false, error: "Missing or invalid resource title in metadata" };
    }

    const cleanType = meta.materialType || meta.type || "Notes";
    const cleanCode = meta.courseCode || meta.unitCode || "";
    const cleanTopic = meta.topic || meta.description || meta.summary || meta.category || cleanTitle;
    const targetProgram = Array.isArray(meta.targetPrograms)
      ? meta.targetPrograms.join(", ")
      : meta.targetPrograms || "Academic Faculty";

    logger.info(
      `[AI_THUMBNAIL_START] Generating metadata-driven Gemini thumbnail for Title="${cleanTitle}", Course="${cleanCode}", Type="${cleanType}", Topic="${cleanTopic.slice(0, 60)}"`
    );

    try {
      // Step 1: Build the metadata-driven educational image generation prompt
      const prompt = this.buildImagePrompt({
        title: cleanTitle,
        courseCode: cleanCode,
        materialType: cleanType,
        topic: cleanTopic,
        description: meta.description,
        targetPrograms: targetProgram,
      });

      // Step 2: Directly call Gemini's image generation API (no intermediate screenshots, no SVG templates)
      const { imageBuffer, mimeType, modelUsed } = await this.generateGeminiImage(
        prompt,
        { title: cleanTitle },
        geminiApiKey
      );

      // Step 3: Minimal encoding verification (preserve visual quality, ensure compatible JPEG/WebP)
      let finalBuffer = imageBuffer;
      let finalMime = mimeType;
      try {
        if (imageBuffer.byteLength > 2 * 1024 * 1024) {
          finalBuffer = await sharp(imageBuffer)
            .jpeg({ quality: 90, progressive: true })
            .toBuffer();
          finalMime = "image/jpeg";
        }
      } catch (err: any) {
        logger.warn(`[AI_THUMBNAIL_ENCODING_WARN] Sharp optimization fallback: ${err.message}`);
        finalBuffer = imageBuffer;
      }

      // Step 4: Compute SHA-256 hash for deduplication tracking
      const imageHash = crypto.createHash("sha256").update(finalBuffer).digest("hex");

      // Step 5: Upload the generated image directly to ImageKit under /THUMBNAILS/
      const uploadRes = await this.uploadToImageKit(ik, finalBuffer, cleanTitle, finalMime);
      if (!uploadRes || !uploadRes.url) {
        throw new Error("Failed to upload Gemini-generated thumbnail to ImageKit");
      }

      // Step 6: Record into used_thumbnails in Firestore for audit & deduplication
      await this.recordUsedThumbnail(db, {
        imageHash: imageHash,
        imageKitUrl: uploadRes.url,
        originalSource: `gemini-image-gen://${encodeURIComponent(cleanTitle)}`,
        originalWebsite: "gemini-image-generation",
        unitName: cleanTitle,
      });

      logger.info(`[AI_THUMBNAIL_SUCCESS] Attached Gemini thumbnail for "${cleanTitle}": ${uploadRes.url} (Model: ${modelUsed})`);

      return {
        success: true,
        imageKitUrl: uploadRes.url,
        imageKitFileId: uploadRes.fileId,
        originalSource: `gemini-image-gen://${cleanTitle}`,
        originalWebsite: "gemini-image-generation",
        imageHash: imageHash,
        reason: `Gemini image generated from metadata for ${cleanTitle} (${cleanType})`,
        modelUsed: modelUsed,
        score: 100,
      };
    } catch (err: any) {
      logger.error(`[AI_THUMBNAIL_ERROR] Failed to generate Gemini image thumbnail for "${cleanTitle}":`, err.message);
      return {
        success: false,
        error: err.message || "Failed to generate Gemini image thumbnail",
      };
    }
  }

  /**
   * Constructs a subject-tailored, high-fidelity image generation prompt based strictly on material metadata.
   */
  public static buildImagePrompt(meta: {
    title: string;
    courseCode?: string;
    materialType?: string;
    topic?: string;
    description?: string;
    targetPrograms?: string;
  }): string {
    const isLab = /lab|practical|prac|manual|experiment/i.test(
      `${meta.materialType || ""} ${meta.title || ""} ${meta.topic || ""}`
    );

    const titleLower = meta.title.toLowerCase();
    const topicLower = (meta.topic || "").toLowerCase();
    const combined = `${titleLower} ${topicLower}`;

    let subjectScene = "";

    if (isLab) {
      if (/biochem|molecular/i.test(combined)) {
        subjectScene = "A realistic university biochemistry laboratory practical scene with laboratory equipment, micro-pipettes, test tube racks with biochemical assays, centrifuge, and scientific glassware on a clean lab bench.";
      } else if (/microbiol|bacteri|virol|fung/i.test(combined)) {
        subjectScene = "A realistic university microbiology laboratory practical scene with agar culture plates, petri dishes with bacterial cultures, sterile laminar flow workspace, and a high-grade laboratory microscope.";
      } else if (/chemist|organic|inorganic|titrat/i.test(combined)) {
        subjectScene = "A realistic academic chemistry laboratory practical setup with borosilicate glassware, Erlenmeyer flasks, burette titration apparatus, beakers with colorful chemical solutions, and lab safety equipment.";
      } else if (/anatom|physiol|med|nurs|clinic|dissect/i.test(combined)) {
        subjectScene = "A professional medical university anatomy laboratory practical session with detailed human anatomical models, medical bone specimens, diagnostic instruments, and clinical demonstration tables.";
      } else if (/agri|crop|soil|plant|hortic|animal|vet|livestock/i.test(combined)) {
        subjectScene = "An agricultural practical field study scene with crop trial plots, soil sample testing kits, healthy agricultural produce, and agronomic field instruments.";
      } else if (/physics|optics|circuit|electr/i.test(combined)) {
        subjectScene = "A university physics laboratory practical setup with optical benches, laser diffraction apparatus, oscilloscopes, and circuit measurement instrumentation.";
      } else {
        subjectScene = `A realistic university laboratory practical workstation tailored specifically to ${meta.title}, showing authentic scientific instrumentation, experimental setup, and educational lab equipment.`;
      }
    } else {
      if (/anatom|physiol|med|health/i.test(combined)) {
        subjectScene = `A high-end educational medical visual representing ${meta.title} (${meta.topic || "Human anatomical systems"}), showing accurate anatomical structures, physiological models, and clean medical context.`;
      } else if (/crop|agri|soil|farm|plant|agronom/i.test(combined)) {
        subjectScene = `A vibrant educational agricultural landscape representing ${meta.title} (${meta.topic || "Crop production and agriculture"}), showing flourishing green agricultural crops, fertile soil, and modern sustainable farming methods.`;
      } else if (/network|comput|software|cyber|code|program|database/i.test(combined)) {
        subjectScene = `A modern high-tech educational concept representing ${meta.title} (${meta.topic || "Computer systems and networks"}), showing stylized data flow, network topology diagrams, servers, and modern technological infrastructure.`;
      } else if (/econ|financ|business|account|market|commerce/i.test(combined)) {
        subjectScene = `A professional educational business and economics visual representing ${meta.title} (${meta.topic || "Financial and market dynamics"}), showing global financial market charts, analytics displays, and corporate economic concepts.`;
      } else {
        subjectScene = `A high-quality educational photograph or 3D illustration capturing the core academic concepts of ${meta.title}: ${meta.topic || meta.title}.`;
      }
    }

    const typeDesc = isLab ? "University Laboratory Practical Session" : (meta.materialType || "University Academic Lecture Notes");

    return [
      `Professional educational landscape thumbnail image for university academic resource: "${meta.title}".`,
      `Course Code: ${meta.courseCode || "Academic"}. Resource Type: ${typeDesc}.`,
      `Visual Subject: ${subjectScene}`,
      `Composition requirements: 16:9 landscape aspect ratio, sharp focus, cinematic educational lighting, balanced composition suitable for a mobile application resource card thumbnail.`,
      `Negative constraints: Strictly NO written words or text inside the image, no typography, no letters or numbers, no watermarks, no logos, no borders, no UI overlays, no fake document screenshots. Clean, high visual quality.`
    ].join(" ");
  }

  /**
   * Calls Gemini Image Generation API directly to produce an image from the prompt.
   * Iterates through available Gemini API keys and candidate image generation models with rotation.
   */
  private static async generateGeminiImage(
    prompt: string,
    meta: { title: string },
    providedApiKey?: string
  ): Promise<{ imageBuffer: Buffer; mimeType: string; modelUsed: string }> {
    const keys = providedApiKey ? [providedApiKey] : EnvConfig.getApiKeys("gemini");
    if (!keys || keys.length === 0) {
      throw new Error("No Gemini API keys configured");
    }

    // Candidate Gemini image generation models in order of priority
    const candidateModels = [
      "gemini-2.5-flash-image",
      "gemini-3.1-flash-image",
      "gemini-3-pro-image",
      "gemini-3.1-flash-lite-image",
      "nano-banana-pro-preview",
    ];

    let lastError: Error | null = null;

    for (let k = 0; k < keys.length; k++) {
      const apiKey = keys[k];
      const maskedKey = EnvConfig.maskSecret(apiKey);

      for (const model of candidateModels) {
        try {
          const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
          logger.info(`[GEMINI_IMAGE_GEN_START] Key=${maskedKey} Model=${model} Title="${meta.title}"`);

          const res = await fetch(endpoint, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            signal: AbortSignal.timeout(35000),
            body: JSON.stringify({
              contents: [
                {
                  parts: [{ text: prompt }],
                },
              ],
              generationConfig: {
                responseModalities: ["IMAGE"],
              },
            }),
          });

          if (res.status === 429 || res.status === 503) {
            const errBody = await res.text();
            logger.warn(
              `[GEMINI_IMAGE_GEN_QUOTA] Key=${maskedKey} Model=${model} Status=${res.status}: ${errBody.slice(0, 150)}. Rotating...`
            );
            lastError = new Error(`HTTP ${res.status}: ${errBody.slice(0, 150)}`);
            continue;
          }

          if (!res.ok) {
            const errBody = await res.text();
            logger.warn(
              `[GEMINI_IMAGE_GEN_WARN] Key=${maskedKey} Model=${model} Status=${res.status}: ${errBody.slice(0, 150)}`
            );
            lastError = new Error(`HTTP ${res.status}: ${errBody.slice(0, 150)}`);
            continue;
          }

          const data = (await res.json()) as any;
          const candidate = data.candidates?.[0];
          const part = candidate?.content?.parts?.find((p: any) => p.inlineData && p.inlineData.data);

          if (part && part.inlineData && part.inlineData.data) {
            const mimeType = part.inlineData.mimeType || "image/jpeg";
            const imageBuffer = Buffer.from(part.inlineData.data, "base64");
            logger.info(
              `[GEMINI_IMAGE_GEN_SUCCESS] Key=${maskedKey} Model=${model} Generated image: ${imageBuffer.byteLength} bytes, MIME: ${mimeType}`
            );
            return { imageBuffer, mimeType, modelUsed: model };
          }

          logger.warn(`[GEMINI_IMAGE_GEN_NOPART] Candidate returned but no image inlineData.`);
        } catch (err: any) {
          logger.warn(`[GEMINI_IMAGE_GEN_ATTEMPT_ERR] Key=${maskedKey} Model=${model}: ${err.message}`);
          lastError = err;
        }
      }
    }

    throw lastError || new Error("All Gemini image generation keys and models exhausted");
  }

  /**
   * Uploads image buffer directly to ImageKit under /THUMBNAILS/
   */
  private static async uploadToImageKit(
    ik: ImageKit,
    buffer: Buffer,
    unitName: string,
    mimeType: string = "image/jpeg"
  ): Promise<{ url: string; fileId: string } | null> {
    try {
      const ext = mimeType.includes("png") ? "png" : "jpg";
      const base64Image = buffer.toString("base64");
      const sanitizeName = unitName.replace(/[^a-zA-Z0-9]/g, "_").toLowerCase().slice(0, 40);
      const fileName = `thumb_${sanitizeName}_${Date.now()}.${ext}`;

      const uploadRes = await ik.upload({
        file: base64Image,
        fileName: fileName,
        folder: "THUMBNAILS",
        useUniqueFileName: true,
      });

      if (uploadRes && uploadRes.url) {
        logger.info(`[IMAGEKIT_UPLOAD_SUCCESS] ImageKit URL: ${uploadRes.url}, file ID: ${uploadRes.fileId}`);
        return {
          url: uploadRes.url,
          fileId: uploadRes.fileId,
        };
      }
    } catch (err: any) {
      logger.error("[IMAGEKIT_UPLOAD_ERROR] Failed to upload thumbnail to ImageKit:", err);
    }
    return null;
  }

  /**
   * Records image record into used_thumbnails in Firestore for audit & deduplication
   */
  private static async recordUsedThumbnail(
    db: admin.firestore.Firestore,
    data: {
      imageHash: string;
      imageKitUrl: string;
      originalSource: string;
      originalWebsite: string;
      unitName: string;
    }
  ): Promise<void> {
    try {
      await db.collection("used_thumbnails").add({
        imageHash: data.imageHash,
        imageKitUrl: data.imageKitUrl,
        originalSource: data.originalSource,
        originalWebsite: data.originalWebsite,
        unitName: data.unitName,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (e: any) {
      logger.warn(`[USED_THUMBNAIL_RECORD_WARN] Could not record used thumbnail: ${e.message}`);
    }
  }
}

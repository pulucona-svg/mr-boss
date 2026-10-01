import * as admin from "firebase-admin";
import * as crypto from "crypto";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";
import sharp from "sharp";
import {
  FluxThumbnailProvider,
  FluxProviderError,
} from "./providers/image_generation/flux_thumbnail_provider";
import {
  FluxWorkerPool,
  FluxWorkerConfig,
} from "./providers/image_generation/flux_worker_pool";
import { GeminiThumbnailProvider } from "./providers/image_generation/gemini_thumbnail_provider";

export interface MaterialMetadata {
  resourceId?: string;
  attemptCount?: number;
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
  provider?: string;
  workerId?: string;
  error?: string;
  retryScheduled?: boolean;
  nextRetryAt?: Date;
  attemptCount?: number;
  alreadyCompleted?: boolean;
}

export class ThumbnailSearchService {
  /**
   * Main Entry Point: Directly generates an AI visual thumbnail from the material's metadata.
   * Multi-provider orchestration:
   * 1. Primary: Flux.2 Dev (Cloudflare Workers AI @cf/black-forest-labs/flux-2-dev)
   *    - Follows strict NO-TEXT visual prompt rules.
   *    - If transient capacity/rate-limit error (429, 3040, timeout), schedules durable Firestore retry with backoff.
   * 2. Secondary fallback: Gemini Image Generation
   *    - Used only when Flux fails non-retryably or exhausts all retry attempts.
   * Common downstream pipeline: Sharp optimization -> ImageKit (/THUMBNAILS/) -> Firestore audit & attachment.
   *
   * Strictly NO screenshot capture, NO SVG templates, NO external image searching.
   */
  public static async searchAndUploadThumbnail(
    db: admin.firestore.Firestore,
    ik: ImageKit,
    titleOrMetadata: string | MaterialMetadata,
    materialType?: string,
    catTypeOrCourseCode?: string,
    geminiApiKey?: string,
    forcedProvider?: "flux" | "gemini",
    customWorkerConfigs?: FluxWorkerConfig[]
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

    const currentAttempt = meta.attemptCount || 1;
    const MAX_FLUX_ATTEMPTS = 4;

    logger.info(
      `[AI_THUMBNAIL_START] Generating metadata-driven thumbnail for Title="${cleanTitle}", Course="${cleanCode}", Type="${cleanType}", Topic="${cleanTopic.slice(0, 60)}" (Attempt ${currentAttempt})`
    );

    // Concurrency lease lock & Idempotency check if resourceId is provided
    if (meta.resourceId) {
      const docRef = db.collection("resources").doc(meta.resourceId);
      const snap = await docRef.get();
      if (snap.exists) {
        const d = snap.data() || {};
        if (d.thumbnailUrl && d.thumbnailUrl.trim().length > 0) {
          logger.info(`[THUMBNAIL_IDEMPOTENT_SKIP] Resource "${meta.resourceId}" already has a completed thumbnail. Skipping.`);
          return {
            success: true,
            imageKitUrl: d.thumbnailUrl,
            imageKitFileId: d.thumbnailId,
            provider: d.thumbnailGeneration?.provider || "flux",
            alreadyCompleted: true,
          };
        }

        const lockedUntil = d.thumbnailGeneration?.lockedUntil?.toDate
          ? d.thumbnailGeneration.lockedUntil.toDate().getTime()
          : d.thumbnailGeneration?.lockedUntil;
        if (lockedUntil && lockedUntil > Date.now()) {
          logger.info(`[THUMBNAIL_CONCURRENCY_LOCKED] Resource "${meta.resourceId}" is locked until ${new Date(lockedUntil).toISOString()}. Skipping.`);
          return {
            success: false,
            error: "Resource thumbnail generation is currently locked by another worker",
          };
        }

        // Acquire 2-minute lease lock
        await docRef.update({
          "thumbnailGeneration.lockedUntil": admin.firestore.Timestamp.fromDate(new Date(Date.now() + 120000)),
        });
      }
    }

    try {
      // Step 1: Build the metadata-driven educational image generation prompt with strict NO TEXT rules
      const prompt = this.buildImagePrompt({
        title: cleanTitle,
        courseCode: cleanCode,
        materialType: cleanType,
        topic: cleanTopic,
        description: meta.description,
        targetPrograms: targetProgram,
      });

      // Step 2: Multi-provider failover execution (Primary: Flux.2 Dev 4-Worker Pool, Secondary: Gemini)
      const geminiProvider = new GeminiThumbnailProvider(geminiApiKey);

      let generated: {
        imageBuffer: Buffer;
        mimeType: string;
        modelUsed: string;
        providerName: string;
        workerId?: string;
      } | null = null;

      let lastError: Error | null = null;
      let runFlux = forcedProvider !== "gemini";
      let runGemini = forcedProvider !== "flux";

      // --- PRIMARY PROVIDER: FLUX.2 DEV (4-WORKER POOL) ---
      if (runFlux) {
        // Reserve an available worker atomically from the 4-worker pool using Firestore transaction
        const reservedWorker = await FluxWorkerPool.reserveAvailableWorker(
          db,
          meta.resourceId || `adhoc_${Date.now()}`,
          customWorkerConfigs
        );

        if (reservedWorker) {
          const workerProvider = new FluxThumbnailProvider({
            accountId: reservedWorker.accountId,
            apiKey: reservedWorker.apiKey,
            model: reservedWorker.model,
          });

          try {
            logger.info(
              `[AI_THUMBNAIL_PROVIDER] Dispatching to "${reservedWorker.workerId}" for "${cleanTitle}" (Attempt ${currentAttempt})`
            );
            const startTime = Date.now();
            const result = await workerProvider.generateImage(prompt, meta);
            if (result && result.imageBuffer && result.imageBuffer.length > 0) {
              const duration = Date.now() - startTime;
              logger.info(
                `[AI_THUMBNAIL_PROVIDER_SUCCESS] Worker "${reservedWorker.workerId}" succeeded in ${duration}ms (Model: ${result.modelUsed}, ${result.imageBuffer.length} bytes)`
              );
              await FluxWorkerPool.releaseWorker(db, reservedWorker.workerId, {
                success: true,
                resourceId: meta.resourceId,
              });

              generated = {
                imageBuffer: result.imageBuffer,
                mimeType: result.mimeType,
                modelUsed: result.modelUsed,
                providerName: "flux",
                workerId: reservedWorker.workerId,
              };
            }
          } catch (err: any) {
            logger.warn(
              `[AI_THUMBNAIL_PROVIDER_ERROR] Worker "${reservedWorker.workerId}" failed: ${err.message}`
            );
            lastError = err;

            // Release worker (cooling_down if retryable, or disabled if permanent)
            await FluxWorkerPool.releaseWorker(db, reservedWorker.workerId, {
              success: false,
              error: err,
              resourceId: meta.resourceId,
            });

            const isRetryable = err instanceof FluxProviderError ? err.isRetryable : false;
            const poolStatus = await FluxWorkerPool.getPoolStatus(db, customWorkerConfigs);

            // If retryable and another worker is free right now, attempt immediate failover within pool
            if (isRetryable && poolStatus.available > 0 && forcedProvider !== "gemini") {
              logger.info(
                `[FLUX_POOL_FAILOVER] Another Flux worker is available (${poolStatus.available} free). Attempting immediate failover within pool...`
              );
              const failoverWorker = await FluxWorkerPool.reserveAvailableWorker(
                db,
                meta.resourceId || `adhoc_${Date.now()}`,
                customWorkerConfigs
              );

              if (failoverWorker) {
                const failoverProvider = new FluxThumbnailProvider({
                  accountId: failoverWorker.accountId,
                  apiKey: failoverWorker.apiKey,
                  model: failoverWorker.model,
                });

                try {
                  const startTime2 = Date.now();
                  const result2 = await failoverProvider.generateImage(prompt, meta);
                  if (result2 && result2.imageBuffer && result2.imageBuffer.length > 0) {
                    const duration2 = Date.now() - startTime2;
                    logger.info(
                      `[AI_THUMBNAIL_PROVIDER_SUCCESS] Failover worker "${failoverWorker.workerId}" succeeded in ${duration2}ms`
                    );
                    await FluxWorkerPool.releaseWorker(db, failoverWorker.workerId, {
                      success: true,
                      resourceId: meta.resourceId,
                    });

                    generated = {
                      imageBuffer: result2.imageBuffer,
                      mimeType: result2.mimeType,
                      modelUsed: result2.modelUsed,
                      providerName: "flux",
                      workerId: failoverWorker.workerId,
                    };
                  }
                } catch (err2: any) {
                  logger.warn(
                    `[AI_THUMBNAIL_PROVIDER_ERROR] Failover worker "${failoverWorker.workerId}" also failed: ${err2.message}`
                  );
                  lastError = err2;
                  await FluxWorkerPool.releaseWorker(db, failoverWorker.workerId, {
                    success: false,
                    error: err2,
                    resourceId: meta.resourceId,
                  });
                }
              }
            }

            // If still not generated and retryable, schedule retry without calling Gemini
            if (
              !generated &&
              isRetryable &&
              currentAttempt < MAX_FLUX_ATTEMPTS &&
              meta.resourceId &&
              forcedProvider !== "flux"
            ) {
              const backoffMs = this.calculateBackoffMs(currentAttempt);
              const nextRetryDate = new Date(Date.now() + backoffMs);

              logger.warn(
                `[FLUX_CAPACITY_RETRY_SCHEDULED] Resource "${meta.resourceId}" scheduled for Flux retry attempt ${currentAttempt + 1} at ${nextRetryDate.toISOString()} due to worker error: ${err.message}`
              );

              await db.collection("resources").doc(meta.resourceId).update({
                thumbnailStatus: "pending",
                thumbnailGeneration: {
                  attemptCount: currentAttempt,
                  maxAttempts: MAX_FLUX_ATTEMPTS,
                  provider: "flux",
                  workerId: reservedWorker.workerId,
                  lastError: err.message,
                  isRetryable: true,
                  lastAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
                  nextRetryAt: admin.firestore.Timestamp.fromDate(nextRetryDate),
                  lockedUntil: null,
                },
              });

              return {
                success: false,
                retryScheduled: true,
                nextRetryAt: nextRetryDate,
                attemptCount: currentAttempt,
                workerId: reservedWorker.workerId,
                error: `Flux worker temporary capacity error: ${err.message}. Retry scheduled for ${nextRetryDate.toISOString()}`,
              };
            }

            logger.info(
              `[FLUX_EXHAUSTED_OR_FATAL] Flux attempt ${currentAttempt}/${MAX_FLUX_ATTEMPTS} failed (retryable=${isRetryable}). Falling back to secondary provider (Gemini)...`
            );
          }
        } else {
          // No worker was available (all 4 are currently busy or in cooldown)
          logger.warn(
            `[FLUX_POOL_ALL_BUSY_OR_COOLDOWN] All 4 Flux workers are currently busy or cooling down for "${cleanTitle}".`
          );
          const poolStatus = await FluxWorkerPool.getPoolStatus(db, customWorkerConfigs);

          if (poolStatus.allDisabled) {
            logger.error(
              `[FLUX_POOL_ALL_DISABLED] All Flux workers are disabled. Proceeding to Gemini fallback.`
            );
          } else if (meta.resourceId && forcedProvider !== "flux") {
            const retryDelayMs = poolStatus.earliestCooldown
              ? Math.max(30000, poolStatus.earliestCooldown.getTime() - Date.now())
              : 60000;
            const nextRetryDate = new Date(Date.now() + retryDelayMs);

            await db.collection("resources").doc(meta.resourceId).update({
              thumbnailStatus: "pending",
              thumbnailGeneration: {
                attemptCount: currentAttempt,
                maxAttempts: MAX_FLUX_ATTEMPTS,
                provider: "flux",
                lastError: "All 4 Flux workers are currently busy or in cooldown",
                isRetryable: true,
                lastAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
                nextRetryAt: admin.firestore.Timestamp.fromDate(nextRetryDate),
                lockedUntil: null,
              },
            });

            return {
              success: false,
              retryScheduled: true,
              nextRetryAt: nextRetryDate,
              attemptCount: currentAttempt,
              error: `All 4 Flux workers busy/cooling down. Queued for retry at ${nextRetryDate.toISOString()}`,
            };
          }
        }
      }

      // --- SECONDARY FALLBACK PROVIDER: GEMINI ---
      if (!generated && runGemini) {
        try {
          logger.info(`[AI_THUMBNAIL_PROVIDER] Trying secondary provider "gemini" for "${cleanTitle}"`);
          const startTime = Date.now();
          const result = await geminiProvider.generateImage(prompt, meta);
          if (result && result.imageBuffer && result.imageBuffer.length > 0) {
            const duration = Date.now() - startTime;
            logger.info(
              `[AI_THUMBNAIL_PROVIDER_SUCCESS] Provider "gemini" succeeded in ${duration}ms (Model: ${result.modelUsed}, ${result.imageBuffer.length} bytes)`
            );
            generated = {
              imageBuffer: result.imageBuffer,
              mimeType: result.mimeType,
              modelUsed: result.modelUsed,
              providerName: "gemini",
            };
          }
        } catch (err: any) {
          logger.warn(`[AI_THUMBNAIL_PROVIDER_ERROR] Secondary provider "gemini" failed: ${err.message}`);
          lastError = err;
        }
      }

      if (!generated) {
        logger.error(`[AI_THUMBNAIL_ALL_PROVIDERS_FAILED] All thumbnail providers failed for "${cleanTitle}".`);
        if (meta.resourceId) {
          await db.collection("resources").doc(meta.resourceId).update({
            thumbnailStatus: "pending",
            "thumbnailGeneration.lockedUntil": null,
            "thumbnailGeneration.lastError": lastError?.message || "All image thumbnail providers failed",
            "thumbnailGeneration.isRetryable": false,
          });
        }
        return {
          success: false,
          error: lastError?.message || "All image thumbnail providers failed to generate an image",
        };
      }

      // Step 3: Minimal encoding verification (preserve visual quality, ensure compatible JPEG/WebP)
      let finalBuffer = generated.imageBuffer;
      let finalMime = generated.mimeType;
      try {
        if (generated.imageBuffer.byteLength > 2 * 1024 * 1024) {
          finalBuffer = await sharp(generated.imageBuffer)
            .jpeg({ quality: 92, progressive: true })
            .toBuffer();
          finalMime = "image/jpeg";
        }
      } catch (err: any) {
        logger.warn(`[AI_THUMBNAIL_ENCODING_WARN] Sharp optimization fallback: ${err.message}`);
        finalBuffer = generated.imageBuffer;
      }

      // Step 4: Compute SHA-256 hash for deduplication tracking
      const imageHash = crypto.createHash("sha256").update(finalBuffer).digest("hex");

      // Step 5: Upload the generated image directly to ImageKit under /THUMBNAILS/
      const uploadRes = await this.uploadToImageKit(ik, finalBuffer, cleanTitle, finalMime);
      if (!uploadRes || !uploadRes.url) {
        throw new Error(`Failed to upload ${generated.providerName}-generated thumbnail to ImageKit`);
      }

      // Step 6: Record into used_thumbnails in Firestore for audit & deduplication
      await this.recordUsedThumbnail(db, {
        imageHash: imageHash,
        imageKitUrl: uploadRes.url,
        originalSource: `${generated.providerName}-image-gen://${encodeURIComponent(cleanTitle)}`,
        originalWebsite: `${generated.providerName}-image-generation`,
        unitName: cleanTitle,
        provider: generated.providerName,
        modelUsed: generated.modelUsed,
        workerId: generated.workerId || null,
      });

      // Step 7: Atomically update Firestore resource document if resourceId is provided
      if (meta.resourceId) {
        await db.collection("resources").doc(meta.resourceId).update({
          thumbnailUrl: uploadRes.url,
          thumbnailId: uploadRes.fileId,
          thumbnailStatus: "completed",
          "thumbnailGeneration.lockedUntil": null,
          "thumbnailGeneration.completedAt": admin.firestore.FieldValue.serverTimestamp(),
          "thumbnailGeneration.provider": generated.providerName,
          "thumbnailGeneration.workerId": generated.workerId || null,
          "thumbnailGeneration.modelUsed": generated.modelUsed,
          "thumbnailGeneration.isRetryable": false,
        });
      }

      logger.info(`[AI_THUMBNAIL_SUCCESS] Attached ${generated.providerName} thumbnail for "${cleanTitle}": ${uploadRes.url} (Worker: ${generated.workerId || "primary"}, Model: ${generated.modelUsed})`);

      return {
        success: true,
        imageKitUrl: uploadRes.url,
        imageKitFileId: uploadRes.fileId,
        originalSource: `${generated.providerName}-image-gen://${cleanTitle}`,
        originalWebsite: `${generated.providerName}-image-generation`,
        imageHash: imageHash,
        reason: `${generated.providerName.toUpperCase()} image generated from metadata for ${cleanTitle} (${cleanType})`,
        modelUsed: generated.modelUsed,
        provider: generated.providerName,
        workerId: generated.workerId,
        score: 100,
      };
    } catch (err: any) {
      logger.error(`[AI_THUMBNAIL_ERROR] Failed thumbnail pipeline for "${cleanTitle}":`, err.message);

      if (meta.resourceId) {
        try {
          await db.collection("resources").doc(meta.resourceId).update({
            "thumbnailGeneration.lockedUntil": null,
          });
        } catch (_) {}
      }

      return {
        success: false,
        error: err.message || "Failed to generate image thumbnail",
      };
    }
  }

  /**
   * Calculates exponential backoff in milliseconds with randomized jitter.
   * Attempt 1: ~30s | Attempt 2: ~120s (2m) | Attempt 3: ~300s (5m) | Attempt 4: ~600s (10m)
   */
  public static calculateBackoffMs(attemptCount: number): number {
    const baseBackoffs = [30000, 120000, 300000, 600000];
    const base = baseBackoffs[Math.min(attemptCount - 1, baseBackoffs.length - 1)] || 30000;
    const jitter = Math.floor(Math.random() * (base * 0.25)); // + 0 to 25% jitter
    return base + jitter;
  }

  /**
   * Background processor: Drains pending retryable thumbnail generation tasks that are due.
   * Checks FluxWorkerPool availability before dispatching to avoid hammering cooling-down workers.
   */
  public static async processPendingRetries(
    db: admin.firestore.Firestore,
    ik: ImageKit,
    customWorkerConfigs?: FluxWorkerConfig[]
  ): Promise<number> {
    const now = admin.firestore.Timestamp.now();
    let processed = 0;

    try {
      const poolStatus = await FluxWorkerPool.getPoolStatus(db, customWorkerConfigs);
      if (poolStatus.allUnavailable && !poolStatus.allDisabled) {
        logger.info(
          `[THUMBNAIL_RETRY_PROCESSOR] All 4 Flux workers are currently busy or in cooldown (Cooling down: ${poolStatus.coolingDown}, Busy: ${poolStatus.busy}). Postponing batch until ${poolStatus.earliestCooldown?.toISOString() || "next cycle"}.`
        );
        return 0;
      }

      const snap = await db.collection("resources")
        .where("thumbnailStatus", "==", "pending")
        .where("thumbnailGeneration.isRetryable", "==", true)
        .where("thumbnailGeneration.nextRetryAt", "<=", now)
        .limit(10)
        .get();

      if (snap.empty) return 0;

      logger.info(`[THUMBNAIL_RETRY_PROCESSOR] Found ${snap.size} due thumbnail retries (Pool available workers: ${poolStatus.available}).`);

      for (const doc of snap.docs) {
        const data = doc.data();
        const resourceId = doc.id;
        const currentAttempt = (data.thumbnailGeneration?.attemptCount || 1) + 1;

        // Skip if already has thumbnail
        if (data.thumbnailUrl && data.thumbnailUrl.trim().length > 0) continue;

        try {
          await this.searchAndUploadThumbnail(
            db,
            ik,
            {
              resourceId,
              attemptCount: currentAttempt,
              title: data.title || data.unitName || "",
              description: data.description || "",
              courseCode: data.courseCode || data.unitCode || "",
              materialType: data.materialType || data.type || "Notes",
              topic: data.topic || data.category || data.title || "",
              targetPrograms: data.targetPrograms || [],
            },
            undefined,
            undefined,
            undefined,
            undefined,
            customWorkerConfigs
          );
          processed++;
        } catch (err: any) {
          logger.error(`[THUMBNAIL_RETRY_ERROR] Failed processing retry for "${resourceId}":`, err);
        }
      }
    } catch (err: any) {
      logger.error("[THUMBNAIL_RETRY_PROCESSOR_ERROR] Failed querying pending retries:", err);
    }

    return processed;
  }

  /**
   * Constructs a subject-tailored, high-fidelity visual prompt strictly derived from material metadata.
   * Converts metadata into concrete visual concepts and strictly forbids any written text, typography, or labels.
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

    let visualSubject = "";

    if (isLab) {
      if (/biochem|molecular/i.test(combined)) {
        visualSubject = "A realistic university biochemistry laboratory practical workstation with clean borosilicate glassware, precision micropipettes, test tube racks holding colorful enzymatic reaction assays, a centrifuge, and scientific analytical instruments on an immaculate stainless steel lab bench.";
      } else if (/microbiol|bacteri|virol|fung/i.test(combined)) {
        visualSubject = "A university microbiology laboratory practical workstation with agar culture plates exhibiting bacterial colonies, a sterile laminar airflow cabinet, precision inoculation loops, and a high-power optical compound microscope.";
      } else if (/chemist|organic|inorganic|titrat/i.test(combined)) {
        visualSubject = "An academic chemistry laboratory experimental setup with glass Erlenmeyer flasks, burette titration clamps, condensation columns, beaker glassware filled with luminous chemical solutions, and safety protective equipment.";
      } else if (/anatom|physiol|med|nurs|clinic|dissect/i.test(combined)) {
        visualSubject = "A professional medical university anatomy laboratory demonstration setting with detailed full-size anatomical human models, medical skeletal specimens, diagnostic medical instruments, and clinical demonstration tables.";
      } else if (/agri|crop|soil|plant|hortic|animal|vet|livestock/i.test(combined)) {
        visualSubject = "An agricultural agronomic research field study setup featuring experimental crop trial seedbeds, precision soil testing core tubes, healthy verdant botanical specimens, and agronomic field measurement apparatus.";
      } else if (/physics|optics|circuit|electr/i.test(combined)) {
        visualSubject = "A university physics laboratory experimental arrangement featuring optical laser refraction benches, glass prisms with spectrum separation, digital oscilloscopes displaying waveforms, and precision electrical test instrumentation.";
      } else {
        visualSubject = `An authentic university academic laboratory workstation configured with modern scientific analytical equipment, glassware, and educational experimental setup.`;
      }
    } else {
      if (/anatom|physiol|med|health/i.test(combined)) {
        visualSubject = `A high-end educational medical visual showing realistic human physiological systems, anatomical models, cellular structures, and clean clinical diagnostic context.`;
      } else if (/crop|agri|soil|farm|plant|agronom/i.test(combined)) {
        visualSubject = `A vibrant educational agricultural landscape showcasing healthy flourishing crops in fertile soil, modern sustainable agricultural technology, and agronomic field science.`;
      } else if (/network|comput|software|cyber|code|program|database|operating system|kernel/i.test(combined)) {
        visualSubject = `A modern, high-tech conceptual visualization of computer systems architecture, operating system kernel layers, microprocessor circuitry, memory modules, server hardware, and luminous data pathways connecting system components.`;
      } else if (/econ|financ|business|account|market|commerce/i.test(combined)) {
        visualSubject = `A professional educational economics and finance visual featuring a stylized 3D global economic sphere, financial market analytics curves, corporate growth geometry, and commerce concepts.`;
      } else if (/math|calculus|algebra|statist|geometry/i.test(combined)) {
        visualSubject = `A sophisticated mathematical visual visualization showcasing smooth 3D curved surfaces, geometric coordinate manifolds, topological calculus shapes, and analytical curves in a clean studio environment.`;
      } else {
        visualSubject = `A high-quality educational photograph and 3D scientific visualization capturing the core physical artifacts, instruments, and academic concepts of the subject matter.`;
      }
    }

    const typeDesc = isLab
      ? "University Laboratory Practical Session"
      : (meta.materialType || "University Academic Lecture Notes");

    const promptSections = [
      `[VISUAL SCENE & OBJECTS]: ${visualSubject}`,
      `[ACADEMIC RELEVANCE]: University educational context representing ${typeDesc}.`,
      `[COMPOSITION & LIGHTING]: 16:9 widescreen landscape framing, balanced focal composition suitable for a mobile application resource card, cinematic educational studio lighting, crisp optical depth of field.`,
      `[STYLE & RENDER QUALITY]: High-resolution educational photography and realistic 3D scientific visualization, clean modern aesthetic, natural color grading.`,
      `[MANDATORY NEGATIVE CONSTRAINTS - STRICTLY NO TEXT]: ABSOLUTELY ZERO TEXT. NO WRITTEN WORDS, NO LETTERS, NO NUMBERS, NO ALPHANUMERIC CHARACTERS, NO LABELS, NO HEADINGS, NO SUBTITLES, NO TITLES, NO CAPTIONS, NO TYPOGRAPHY, NO WRITTEN ANNOTATIONS, NO WATERMARKS, NO LOGOS, NO SYMBOLS WITH TEXT, NO FAKE BOOK COVERS, NO FAKE USER INTERFACES. THE ENTIRE IMAGE MUST BE 100% PURELY VISUAL WITH ZERO EMBEDDED TEXT.`
    ];

    return promptSections.join("\n\n");
  }

  /**
   * Backward-compatible delegation to GeminiThumbnailProvider.
   */
  public static async generateGeminiImage(
    prompt: string,
    meta: { title: string },
    providedApiKey?: string
  ): Promise<{ imageBuffer: Buffer; mimeType: string; modelUsed: string }> {
    const provider = new GeminiThumbnailProvider(providedApiKey);
    return provider.generateImage(prompt, { title: meta.title });
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
      provider?: string;
      modelUsed?: string;
      workerId?: string | null;
    }
  ): Promise<void> {
    try {
      await db.collection("used_thumbnails").add({
        imageHash: data.imageHash,
        imageKitUrl: data.imageKitUrl,
        originalSource: data.originalSource,
        originalWebsite: data.originalWebsite,
        unitName: data.unitName,
        provider: data.provider || "flux",
        modelUsed: data.modelUsed || "@cf/black-forest-labs/flux-2-dev",
        workerId: data.workerId || null,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (e: any) {
      logger.warn(`[USED_THUMBNAIL_RECORD_WARN] Could not record used thumbnail: ${e.message}`);
    }
  }
}

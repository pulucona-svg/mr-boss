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
   * Deterministically computes a stable index from metadata strings using 32-bit FNV-1a and numeric seed offsets.
   * Provides consistent, reproducible visual variety across similar courses without external services or state.
   */
  private static getDeterministicIndex(seed: string, count: number): number {
    if (count <= 1) return 0;
    const numMatch = seed.match(/(\d+)/g);
    let numVal = 0;
    if (numMatch) {
      numVal = numMatch.reduce((acc, curr) => acc + parseInt(curr, 10), 0);
    }
    let hash = 2166136261;
    for (let i = 0; i < seed.length; i++) {
      hash ^= seed.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    return Math.abs(numVal + hash) % count;
  }

  /**
   * Constructs a subject-tailored, natural editorial photographic prompt strictly derived from material metadata.
   * Replaces artificial AI-art tropes (neon, glowing screens, 3D renders, sci-fi effects) with authentic real-world photography.
   * Enforces controlled visual diversity for similar courses and strictly forbids any written text, typography, or labels.
   */
  public static buildImagePrompt(meta: {
    title: string;
    courseCode?: string;
    materialType?: string;
    topic?: string;
    description?: string;
    targetPrograms?: string;
  }): string {
    const isLab = /\blab\b|practical|\bprac\b|\bmanual\b|experiment/i.test(
      `${meta.materialType || ""} ${meta.title || ""} ${meta.topic || ""}`
    );

    const titleLower = (meta.title || "").toLowerCase();
    const codeLower = (meta.courseCode || "").toLowerCase();
    const topicLower = (meta.topic || "").toLowerCase();
    const descLower = (meta.description || "").toLowerCase();
    const combined = `${codeLower} ${titleLower} ${topicLower} ${descLower}`.trim();
    const seed = `${codeLower}_${titleLower}_${topicLower}`.trim();

    let visualSubject = "";

    if (isLab) {
      if (/biochem|molecular/i.test(combined)) {
        const variants = [
          "Authentic documentary photograph of a university biochemistry laboratory practical workstation; clean borosilicate glassware, calibrated micropipettes in a carousel rack, microcentrifuge tubes in an ice bath, and a centrifuge on an immaculate stainless steel lab bench under natural overhead lab lighting.",
          "Editorial photograph of a university biochemistry student in safety coat and protective eyewear carefully dispensing an enzymatic assay using a precision pipette, soft natural daylight from tall laboratory windows, authentic scientific setting.",
          "Detailed close-up photograph of laboratory glassware containing clear chemical reagents and a test tube rack beside an analytical digital balance on a clean laboratory bench, natural depth of field."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/microbiol|bacteri|virol|fung/i.test(combined)) {
        const variants = [
          "Authentic documentary photograph of a university microbiology practical workstation; sterile agar Petri dishes with cultured colonies, an inoculation loop stand, a laminar airflow cabinet, and a binocular optical compound microscope under clean laboratory fluorescent lighting.",
          "Realistic editorial photograph of a microbiology practical session; a researcher in white lab coat examining an agar culture plate held up to natural daylight from a laboratory window, realistic glass reflections and natural skin tones.",
          "Detailed macro photograph of a laboratory compound microscope stage with specimen slide, focus adjustment dials, and stained glass culture slides on a clean black lab surface."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/chemist|organic|inorganic|titrat/i.test(combined)) {
        const variants = [
          "Authentic photograph of an academic chemistry laboratory experiment setup; glass Erlenmeyer flasks, a glass burette mounted on a retort stand for volumetric titration, glass beakers with clear aqueous solutions, and safety goggles on a chemical-resistant black epoxy resin bench under balanced room lighting.",
          "Realistic documentary photograph of an organic chemistry synthesis workstation; round-bottom glass boiling flask, Liebig condenser column with rubber tubing, magnetic hotplate stirrer, and an open laboratory notebook with pen under natural daylight.",
          "Close-up photograph of volumetric chemistry glassware and graduated cylinders with liquid meniscus measurements on an organized university laboratory bench, crisp optical focus, soft ambient lighting."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/anatom|physiol|med|nurs|clinic|dissect/i.test(combined)) {
        const variants = [
          "Professional editorial photograph of a university medical anatomy demonstration room; life-size articulated anatomical skeleton model, detailed anatomical cross-section torso models, diagnostic medical reference charts, and stainless steel demonstration tables under neutral clinical lighting.",
          "Realistic documentary photograph of a medical practical training room; medical students gathered around a clinical examination table with stethoscope, diagnostic instruments, and anatomical reference atlas in soft daylight.",
          "Detailed photograph of medical diagnostic instruments including a classic acoustic stethoscope, blood pressure sphygmomanometer, and medical record folders on an examination desk."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/agri|crop|soil|plant|hortic|animal|vet|livestock/i.test(combined)) {
        const variants = [
          "Authentic agricultural field research photograph; an outdoor agronomic trial seedbed with healthy flourishing crop seedlings, a soil moisture probe, sample collection core tubes, and an agronomist's clipboard under natural morning daylight.",
          "Realistic editorial photograph of an agricultural university soil testing laboratory workbench; core soil profile cylinders, sample sieves, pH testing vials, and analytical scale on a wooden lab bench under soft daylight.",
          "Documentary photograph of an academic research greenhouse with potted crop trial cultivars on galvanized wire benches, mist irrigation nozzles, and warm natural sunlight filtering through greenhouse glass."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/circuit|electr|hardware|embedded|iot|robot/i.test(combined)) {
        const variants = [
          "Authentic photograph of a university electronics engineering practical workbench; a digital storage oscilloscope displaying clean sine waveforms, soldering iron in stand, breadboard with microcontroller and jumper wires, and digital multimeter under an adjustable desk lamp.",
          "Realistic documentary photograph of an engineering student testing a prototype circuit board on an electronics lab bench with diagnostic multimeter probes, wire cutters, and component organizer bins under balanced room lighting.",
          "Detailed macro photograph of a breadboard prototype with integrated circuit chips, resistors, capacitors, and colorful jumper wires connected to a USB interface on a wooden laboratory bench."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/physics|optics/i.test(combined)) {
        const variants = [
          "Authentic university physics laboratory experimental setup; an optical breadboard rail with precision optical lens mounts, a glass prism demonstrating white light refraction, and digital test meters under realistic academic laboratory lighting.",
          "Realistic documentary photograph of a physics mechanics experiment; air track with gliders, precision photogate sensors, digital counter, and laboratory notebook on a sturdy lab table under natural window light.",
          "Detailed photograph of physics analytical instrumentation; digital multimeters, signal generator, and neat coaxial cables on an academic physics workbench with realistic depth of field."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/network|comput|software|cyber|code|program/i.test(combined)) {
        const variants = [
          "Authentic photograph of a university computing practical laboratory; physical networking switch with patch cables, students working at clean desktop computer workstations with standard keyboards and mice, natural daylight through classroom windows.",
          "Realistic documentary photograph of a computer hardware laboratory; open desktop computer case on an antistatic workbench with motherboard components and diagnostic tools under clean overhead room lighting.",
          "Editorial photograph of a university computer programming lab with rows of dual-monitor workstations, comfortable chairs, and students quietly engaged in practical exercises under balanced ambient lighting."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else {
        const variants = [
          "Authentic documentary photograph of an academic university practical laboratory workstation; clean scientific glassware, analytical instruments, measuring apparatus, and an open student lab notebook on a durable laboratory bench under balanced natural lighting.",
          "Realistic editorial photograph of a university experimental laboratory setting; clean organized workstations, scientific apparatus, protective safety gear, and natural daylight filtering through large windows."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      }
    } else {
      // Non-lab academic units: Fine-grained semantic classification with rich photographic variety
      if (/cyber|security|cryptograph|forensic|ethical hack|penetration|firewall|infosec|vulnerab|malware|defense/i.test(combined)) {
        const variants = [
          "Authentic editorial photograph of a university cybersecurity training laboratory workstation; dual desktop monitors displaying network monitoring logs and terminal windows in a well-lit campus lab, a hardware security authentication key on the desk, natural daylight from adjacent windows.",
          "Realistic documentary photograph of a digital forensics laboratory workbench; a write-blocked storage drive dock, disassembled hardware components, diagnostic tools, and an investigator's reference logbook under clean overhead lighting.",
          "Editorial photograph of computer science students in smart-casual attire collaborating around a workstation conducting a security audit, discussing findings with a whiteboard in the background showing network defense topology.",
          "Realistic close-up photograph of a secure workstation environment; a smart card reader, physical hardware authentication token, encrypted external storage drive, and a technical reference notebook on an oak desk under soft daylight."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/network|telecom|cisco|switch\b|router|ethernet|tcp|ip\b|wireless|cloud\b|distributed system|packet|cabling|datacenter|data center|infrastructure/i.test(combined)) {
        const variants = [
          "Authentic professional photograph of a telecommunications equipment rack inside a university IT laboratory; organized blue and yellow Cat6 Ethernet patch cables connected into enterprise patch panels and network switches with subtle green indicator LEDs, realistic indoor fluorescent lighting.",
          "Documentary photograph of a university networking laboratory workbench; physical enterprise routers, coiled Ethernet cables, a cable crimping tool, a digital network cable tester, and a laptop showing a network configuration terminal under natural ambient room lighting.",
          "Editorial photograph of a network engineering student in practical attire carefully routing patch cables into an organized server cabinet, authentic documentary composition with realistic depth of field and plausible laboratory lighting.",
          "Detailed close-up photograph of high-density RJ45 Ethernet ports on a network switch rack with plugged-in patch cords, metallic hardware finishes, natural optical focus, believable server room ambient illumination and natural equipment shadows.",
          "Realistic photograph of an enterprise server room aisle; clean perforated metal equipment enclosures, overhead cable management trays, raised access flooring, and soft neutral commercial white lighting."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/database|sql\b|relational|data science|data mining|big data|analytics|business intelligence|information system|data warehouse/i.test(combined)) {
        const variants = [
          "Authentic professional photograph of a data analyst's desk; an open paper notebook with hand-sketched relational entity-relationship diagrams, beside a desktop monitor showing query tables and database schemas, a pen, and natural window daylight.",
          "Editorial photograph of an academic data science workstation; dual screens displaying statistical data charts and clean tabular datasets, with a notebook, pen, and coffee cup on a birch desk in a bright office.",
          "Documentary photograph of two academic researchers discussing data modeling around a study table with printed data charts and a laptop in a bright, modern university department room.",
          "Realistic photograph of an information systems management workstation with system architecture flowcharts on paper, a laptop, tablet, and filing folders under soft natural office lighting."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/hardware|architecture|microprocessor|circuit|embedded|iot\b|arduino|raspberry|sensor|pc assembly|electronic/i.test(combined)) {
        const variants = [
          "Authentic photograph of a university electronics engineering workbench; a digital oscilloscope, soldering station, breadboard with microcontroller and jumper wires, and digital multimeter under an adjustable desk lamp.",
          "Documentary photograph of an open desktop computer case on an antistatic workbench showing realistic motherboard components, heatsinks, RAM modules, and cooling fans in an academic hardware lab.",
          "Close-up macro photograph of a green printed circuit board with real soldered microchips, surface-mount components, and copper traces, photographed with natural optical depth of field under daylight.",
          "Realistic photograph of an embedded systems prototyping station with microcontrollers, sensor breakout modules, test probes, and an open notebook on a sturdy wooden workshop bench."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/operating system|kernel|unix|linux|sysadmin|system administration|process schedul|memory manage/i.test(combined)) {
        const variants = [
          "Authentic editorial photograph of a systems administrator's workstation; a desktop monitor displaying a Unix command terminal, a keyboard, and an open systems administration reference handbook on a wooden desk with soft natural window daylight.",
          "Documentary photograph of a university computer systems lab with students testing system builds at desktop workstations, natural fluorescent ceiling lighting and large windows.",
          "Realistic close-up photograph of hands typing at an ergonomic keyboard with a computer workstation tower in the background, believable indoor academic ambient lighting."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/python/i.test(combined)) {
        const variants = [
          "Authentic documentary photograph of a programmer's workstation in an academic computing lab; desktop monitor displaying an open Python script with clean indentation in a dark-themed editor, a mechanical keyboard, notebook with algorithmic flowcharts, and a ceramic coffee mug on a wooden desk with natural window daylight.",
          "Realistic editorial photograph of a student software developer testing a Python data processing script at a workstation, with an open Python reference handbook and a notebook on a birch desk in a brightly lit university computer lab.",
          "Documentary photograph of a graduate student working at a dual-monitor workstation running a Python interactive environment with data visualization charts, natural ambient daylight from campus windows."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/java\b|c\+\+|oop\b|object oriented/i.test(combined)) {
        const variants = [
          "Authentic professional photograph of a software engineering workstation; a modern monitor displaying an object-oriented class hierarchy in an enterprise IDE, an open notebook with hand-drawn UML class diagrams, and a keyboard on a walnut desk in natural daylight.",
          "Editorial photograph of two computer science students reviewing object-oriented software design patterns at a shared laboratory workbench, discussing interface architectures with a notebook under balanced room lighting.",
          "Realistic documentary photograph of an academic software architecture planning session; whiteboard displaying class inheritance diagrams and module boxes, with a laptop on a project table in a bright classroom."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/algorithm|data structure|tree|graph theory|sorting/i.test(combined)) {
        const variants = [
          "Authentic documentary photograph of an algorithms research study desk; an open notebook with precise handwritten binary search tree diagrams, algorithm pseudocode, a reference textbook, and a laptop on a wooden desk in soft window light.",
          "Realistic editorial photograph of computer science students analyzing algorithm time complexity around a seminar whiteboard with sketched sorting logic curves and network graph diagrams under balanced lighting.",
          "Close-up documentary photograph of a programmer's hands actively typing on a modern keyboard at an organized workstation, with an open notebook showing handwritten flowcharts and algorithmic logic, soft daylight from a side window."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/web dev|javascript|typescript|html|css|frontend|backend|full stack/i.test(combined)) {
        const variants = [
          "Authentic documentary photograph of a web developer's workspace; dual monitors displaying web application code and a clean browser layout, paper wireframe sketches with pencil annotations, and an ergonomic keyboard on an oak desk in natural daylight.",
          "Editorial photograph of a university web development practical session; students designing responsive user interfaces at clean laboratory workstations with modern monitors and natural light from large windows.",
          "Realistic photograph of a web programmer's desk with tablet device displaying mobile interface mockups, an open laptop with backend code, and a coffee mug under soft room lighting."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/mobile dev|android|flutter|react native|ios\b|swift\b|kotlin/i.test(combined)) {
        const variants = [
          "Authentic documentary photograph of a mobile software engineering workstation; physical smartphone test devices resting on a clean wooden desk beside a laptop displaying application workspace, warm morning daylight from a window.",
          "Editorial photograph of an academic mobile computing laboratory; students testing mobile application builds across multiple handheld devices and desktop workstations under realistic classroom lighting.",
          "Close-up photograph of a mobile developer's hands holding a test smartphone device running a prototype interface, beside a modern laptop and notebook on a wooden desk."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/program|code|coding|software|developer|compiler/i.test(combined)) {
        const variants = [
          "Authentic documentary photograph of a programmer debugging code in a realistic workstation environment; desktop monitor displaying code layout with unreadable blurred lines, mechanical keyboard, notebook with logic notes, and ceramic mug under natural window daylight.",
          "Realistic editorial photograph of collaborative software development with two university students at a shared laboratory workbench, discussing software logic and referring to a technical notebook in a naturally lit computing lab.",
          "Close-up documentary photograph of a developer's hands and physical workstation; typing on an ergonomic keyboard with an open notebook of handwritten logic flowcharts and a test device on a wooden desk.",
          "Editorial photograph of a university programming laboratory; neat rows of dual-monitor workstations, comfortable chairs, and students quietly engaged in practical exercises under soft natural light from large windows.",
          "Realistic photograph of an academic lecture hall with an instructor demonstrating software development concepts at a podium workstation beside a large projection screen, students seated at lecture desks.",
          "Documentary photograph of a software architecture team in a realistic collaborative planning scene; whiteboard in the background with sketched module boxes and connecting arrows, with a laptop on an oak conference table."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/comput|information tech|ict\b|bict|it application/i.test(combined)) {
        const variants = [
          "Authentic editorial photograph of an academic IT computer laboratory; students working diligently at modern desktop computer workstations, clean desks, comfortable chairs, illuminated by bright daylight from large side windows.",
          "Documentary photograph of an organized technology workstation with dual displays, keyboard, mouse, reference textbooks, and notes on a wooden desk under realistic room lighting.",
          "Realistic photograph of a university technology lecture hall with an instructor demonstrating software applications at a podium workstation beside a large presentation display, students seated at lecture desks."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/calculus|differen|integral|analysis|manifold/i.test(combined)) {
        const variants = [
          "Authentic documentary photograph of a university mathematics lecture hall; a large slate chalkboard filled with handwritten chalk calculus derivations, integral equations, and function curve sketches, photographed from an editorial perspective.",
          "Realistic photograph of an organized study desk with open calculus textbooks, handwritten notes showing differential equations on graph paper, a scientific calculator, and a ballpoint pen under warm natural window light.",
          "Editorial photograph of a graduate mathematics seminar with scholars gathered around a large whiteboard analyzing multivariable calculus proofs and continuous functions in natural daylight."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/linear algebra|matrix|\bvector space\b|eigen|discrete math/i.test(combined)) {
        const variants = [
          "Authentic documentary photograph of a mathematics lecture room showing a slate chalkboard with handwritten chalk matrix transformations, vector coordinate frames, and linear equation derivations, soft natural room lighting.",
          "Realistic photograph of a student study desk with an open grid-lined notebook displaying handwritten matrix computations and vector diagrams, a drafting ruler, mechanical pencil, and scientific calculator under warm daylight from a window.",
          "Editorial photograph of a university mathematics department seminar room with professors discussing discrete mathematics proofs on a whiteboard under balanced ambient lighting."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/statist|probability|actuarial|regression|econometric/i.test(combined)) {
        const variants = [
          "Authentic photograph of an actuarial and statistics workstation; printed statistical distribution curves, regression analysis charts, a financial calculator, and an open reference handbook on an oak desk under soft daylight.",
          "Editorial photograph of a statistics seminar room; a whiteboard displaying bell curve normal distributions and probability formulas, alongside a laptop displaying data tables on a conference table.",
          "Realistic documentary photograph of a graduate researcher's desk with demographic survey data sheets, statistical tables, notebook, and pen under balanced office lighting."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/math|algebra|geometry|trigono|numerical/i.test(combined)) {
        const variants = [
          "Authentic documentary photograph of a mathematics study desk with an open notebook of handwritten algebraic derivations, a steel drafting compass, protractor, ruler, and pencils under natural morning light.",
          "Realistic editorial photograph of a mathematics department classroom with geometric chalk drawings and algebraic formulas on a classic blackboard under gentle ambient lighting.",
          "Documentary photograph of a study table with wooden geometric polyhedral models, grid paper, and reference mathematical texts under soft daylight."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/account|audit|tax\b|bookkeep|ledger/i.test(combined)) {
        const variants = [
          "Authentic professional photograph of an accountant's wooden desk; printed financial balance sheets, a desktop adding calculator, ledger documents, fountain pen, and neatly organized quarterly report folders under soft natural office lighting.",
          "Editorial photograph of an auditing office desk with audit tickmark checklists, financial statement portfolios, highlighter pens, and a laptop on a polished walnut table under realistic room illumination.",
          "Documentary photograph of a corporate accounting workstation; dual monitors showing tabular financial spreadsheets, a calculator, physical paper receipts file, and a coffee mug under daylight."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/microecon|price theory|consumer behavior|firm theory/i.test(combined)) {
        const variants = [
          "Authentic editorial photograph of an economics study room; an open notebook with hand-sketched supply and demand curves, market equilibrium graphs, microeconomic textbooks, and a pen on an oak table in natural daylight.",
          "Realistic photograph of a university economics classroom; chalkboard displaying consumer utility curves and market elasticity diagrams, with seminar chairs arranged under balanced lighting.",
          "Documentary photograph of an economic research desk with commodity pricing data reports, market competition case studies, and a laptop under soft window light."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/macroecon|monetary|fiscal|gdp|inflation|central bank|international trade/i.test(combined)) {
        const variants = [
          "Authentic editorial photograph of an economic policy conference room; oak boardroom table with printed national GDP economic reports, global trade charts, leather portfolios, and pen under realistic conference room lighting.",
          "Realistic photograph of a university economics lecture room; whiteboard displaying macroeconomic aggregate demand curves, inflation trend charts, and fiscal policy diagrams under natural daylight.",
          "Documentary photograph of an economist's desk with central bank statistical bulletins, international exchange rate charts, notebook, and laptop under soft morning light."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/financ|bank|invest|portfolio|stock|capital/i.test(combined)) {
        const variants = [
          "Authentic photograph of a university financial trading laboratory workstation; desktop monitors displaying financial market charts and economic indicators, with a keyboard and financial newspaper on the desk under balanced commercial lighting.",
          "Editorial photograph of an investment management desk with portfolio asset allocation reports, corporate valuation summaries, a financial calculator, and pen on a dark wood desk under natural daylight.",
          "Documentary photograph of finance students discussing an investment case study around a conference table with printed financial reports and laptops in a modern business school."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/procure|logistic|supply chain|inventory|transport|warehouse/i.test(combined)) {
        const variants = [
          "Authentic photograph of a logistics management desk; clipboard inventory checklists, shipping distribution route maps, a tablet device, and supply chain flowcharts under believable office lighting.",
          "Editorial photograph of an operations management workstation with freight documentation, procurement tender files, calculator, and laptop on a clean wooden desk under natural daylight.",
          "Documentary photograph of supply chain analysts reviewing warehouse layout plans and distribution charts around a bright project table."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/econ|business|commerce|manage|entrepreneur|marketing|human resource|hr\b/i.test(combined)) {
        const variants = [
          "Authentic editorial photograph of a modern university business school conference room; leather armchairs around an oak table, paper agenda portfolios, water glasses, and a presentation display in realistic daylight.",
          "Realistic photograph of business students in smart-casual attire gathered around a project table reviewing marketing case studies and strategic planning documents, natural daylight through office windows.",
          "Documentary photograph of a business management desk with strategic planning binders, quarterly milestone charts, a laptop, and notebook on a birch desk under soft lighting.",
          "Editorial photograph of a marketing strategy workspace with consumer research reports, project moodboards, and sticky notes on a glass board in an open-plan office."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/nurs|patient care|ward|clinical practice/i.test(combined)) {
        const variants = [
          "Authentic documentary photograph of a modern university nursing simulation ward; clinical hospital beds with clean linens, diagnostic monitoring equipment, medication chart clipboard, and stethoscope in soft ambient ward lighting.",
          "Realistic editorial photograph of a nursing skills demonstration table; blood pressure cuff, medical thermometer, sterile dressing packs, and clinical procedure manuals under clean daylight.",
          "Documentary photograph of a nursing lecture room with students in clean clinical uniforms practicing diagnostic vital signs in a realistic hospital simulation setting."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/anatom|physiol|histol|pathol/i.test(combined)) {
        const variants = [
          "Authentic professional photograph of a medical lecture room; an articulated life-size human skeletal model, detailed anatomical organ models, and medical atlas charts on a demonstration table under natural clinical lighting.",
          "Editorial photograph of an academic medical study desk; an open full-color human anatomy atlas showing physiological systems, medical reference books, and notepad under warm desk lamp illumination.",
          "Realistic documentary photograph of a pathology demonstration desk with binocular microscope, slide staining rack, glass specimen slides, and diagnostic notebooks under clean laboratory daylight."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/pharmac|drug|medicinal|therapeut/i.test(combined)) {
        const variants = [
          "Authentic photograph of a university pharmacy demonstration counter; amber apothecary medicine bottles, precision chemical balance, ceramic mortar and pestle, and reference pharmacopeia under clean clinical lighting.",
          "Editorial photograph of a pharmaceutical research workbench with graduated medicine vials, blister pack inspection trays, and compounding notebooks under balanced fluorescent lighting.",
          "Documentary photograph of a pharmacology study desk with pharmacology textbooks, drug classification charts, prescription pads, and pen under natural daylight."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/med|health|epidemiol|public health|surg|clinic/i.test(combined)) {
        const variants = [
          "Authentic documentary photograph of a medical university clinical demonstration room; examination couch, diagnostic stethoscope, reflex hammer, and medical case history files on a stainless steel tray under neutral lighting.",
          "Realistic editorial photograph of a public health epidemiology study desk with global health demographic maps, printed disease surveillance charts, laptop, and notebook under soft window light.",
          "Documentary photograph of a medical seminar room with healthcare students discussing clinical case studies around a conference table with reference medical texts in natural daylight."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/soil|crop|agronom|hortic|plant science|seed/i.test(combined)) {
        const variants = [
          "Authentic agricultural documentary photograph of an outdoor experimental crop research field with thriving, verdant crop rows, an agronomist's clipboard with field data sheets, soil testing probe, and expansive sky under morning sunlight.",
          "Realistic photograph of an agricultural university soil testing laboratory workbench with core soil samples in clear cylinders, pH testing kits, drying oven, and sample sieve screens under realistic indoor daylight.",
          "Editorial photograph of an academic research glass greenhouse with potted botanical trial cultivars on galvanized benches, overhead drip irrigation lines, and soft diffused sunbeams."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/animal|vet|veterin|livestock|pasture|dairy|poultry/i.test(combined)) {
        const variants = [
          "Authentic photograph of a university veterinary demonstration room with a stainless steel examination table, veterinary diagnostic tools, animal anatomy charts, and clean clinical instruments under natural clinic lighting.",
          "Editorial photograph of an animal science research facility; pasture feed analysis samples, livestock nutrition charts, reference veterinary handbooks, and measuring calipers on a laboratory bench.",
          "Documentary photograph of an agricultural extension classroom with animal health demonstration kits, model livestock skeletons, and educational charts under bright natural daylight."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/agri|farm|forestr|agribusiness/i.test(combined)) {
        const variants = [
          "Authentic photograph of an agricultural field study station with agronomy reference binders, soil sampling auger, crop yield measurement scales, and clipboards on a wooden table overlooking green fields.",
          "Editorial photograph of an agricultural economics desk with grain market price bulletins, harvest logistics schedules, farm management folders, and a laptop in a bright rural office.",
          "Documentary photograph of forestry research students examining tree core ring samples with measuring loupes on a field workbench under natural forest canopy daylight."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/chemist|organic|inorganic|titrat|analytical chem/i.test(combined)) {
        const variants = [
          "Authentic documentary photograph of a university chemistry department study setup; molecular model ball-and-stick kits on a wooden desk, chemistry textbooks, chemical formula notes, and safety glasses under soft daylight.",
          "Realistic editorial photograph of a clean academic chemistry lecture demonstration table with Pyrex flasks, volumetric pipettes, and safety equipment under balanced room lighting.",
          "Documentary photograph of an analytical chemistry laboratory workstation with digital pH meters, calibration buffer solutions, analytical balance, and lab logbook under clean daylight."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/physics|mechanic|optics|thermodynamic|electromagnet/i.test(combined)) {
        const variants = [
          "Authentic documentary photograph of a physics study desk with an open textbook of classical mechanics derivations, vector force diagrams in a spiral notebook, a calculator, and brass weights under warm natural light.",
          "Realistic photograph of a university physics demonstration table with tuning forks, optical prisms, precision calipers, and digital meters under balanced classroom lighting.",
          "Editorial photograph of an academic physics research bench with oscilloscope displays, circuit test leads, and experiment calculation notes under natural window daylight."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/geolog|earth science|geograph|environ|meteorolog/i.test(combined)) {
        const variants = [
          "Authentic documentary photograph of a geology research workbench; rock and mineral hand specimens, geologist's crack hammer, magnifying loupe, streak plates, and topographical maps on a sturdy wooden table under warm desk lamp illumination.",
          "Realistic photograph of an environmental science field station with water sampling bottles, digital dissolved oxygen probe, and survey clipboards arranged on an outdoor field research table by a natural lake under open daylight.",
          "Editorial photograph of a geography cartography studio with large topographical survey maps, drafting compass, magnifying loupe, and aerial photographs on an oak drafting table under bright daylight."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/crimin|forensic|criminal justice/i.test(combined)) {
        const variants = [
          "Authentic photograph of a university criminology analysis table with forensic evidence markers, magnifying comparator, fingerprint reference cards, and investigative case files under direct desk illumination.",
          "Realistic documentary photograph of a criminal law study desk with legal statutes, case law volumes, case summary notes, and legal pads on a mahogany desk under warm ambient lighting.",
          "Editorial photograph of a criminology seminar room with students analyzing investigative case study files around a conference table in natural daylight."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/law|legal|constitut|court|justice|jurisprud|contract|tort|statute/i.test(combined)) {
        const variants = [
          "Authentic editorial photograph of a university moot court room; polished mahogany judge's bench, wooden counsel tables, leather-bound legal reporter volumes, and brass gavel under stately ambient room lighting.",
          "Documentary photograph of an academic law library study carrel flanked by tall wooden bookshelves of law reports, an open statute book with bookmark ribbon, reading lamp, and fountain pen under warm, quiet library lighting.",
          "Realistic photograph of a legal study desk with organized case file folders, tied legal briefs, drafting notepad, and brass scales of justice figurine on a dark walnut desk under soft natural window light."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/early child|primary educat|kindergarten|special educat/i.test(combined)) {
        const variants = [
          "Authentic photograph of a primary education teacher training table; colorful wooden educational manipulative blocks, illustrated children's storybooks, activity cards, and lesson plan organizers on a cheerful classroom table.",
          "Realistic editorial photograph of an early childhood pedagogy workshop with student teachers creating hands-on learning materials, scissors, colored paper, and curriculum guides under bright daylight.",
          "Documentary photograph of an elementary educational psychology setting with developmental assessment materials and learning tools arranged on a wooden table."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/educat|teach|pedagog|curriculum|instruction|school/i.test(combined)) {
        const variants = [
          "Authentic documentary photograph of a university education seminar room; arranged student desks, an instructor's lectern, clean whiteboard with curriculum planning diagrams, and textbooks under bright natural daylight.",
          "Realistic photograph of education students collaborating around a round library table with lesson plan binders, laptops, and instructional materials under natural window light.",
          "Editorial photograph of a teacher education lecture room with instructional design flowcharts on a demonstration board, textbooks, and grading rubrics on a wooden desk."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/psychol|counsel|sociol|social work|behavior/i.test(combined)) {
        const variants = [
          "Authentic editorial photograph of a psychology observation and counseling room; comfortable armchairs around a low wooden table with notebook, stopwatches, assessment questionnaires, and gentle ambient lamplight.",
          "Realistic photograph of a sociology research desk with demographic survey binders, qualitative interview transcripts, notebook, and laptop under soft natural window light.",
          "Documentary photograph of a behavioral science study room with psychological reference texts, testing cards, and research notes on a tidy oak desk under warm daylight."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/literature|poetry|drama|novel|creative writing/i.test(combined)) {
        const variants = [
          "Authentic editorial photograph of a university literature study room; stacks of classic books, an open hardcover volume on a wooden bookstand, reading spectacles, and a notepad on an antique oak library desk with warm sunlight through windows.",
          "Realistic photograph of a creative writing desk with a fountain pen, open leather journal, reference dictionary, and a ceramic mug on a weathered wooden table by a sunny window.",
          "Documentary photograph of an academic literature seminar room with paperbacks, critical essays, and reading notes arranged around a conference table under soft daylight."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/histor|archaeolog|archive|heritage/i.test(combined)) {
        const variants = [
          "Authentic documentary photograph of a university archival research room; vintage historical manuscripts, archival document boxes, magnifying glass, conservation cotton gloves, and reference history texts on an archival reading table under gentle lighting.",
          "Realistic photograph of a historian's study desk with historical map prints, archival folders, reference volumes, notebook, and reading lamp on a dark wood table.",
          "Editorial photograph of an archaeology laboratory bench with ceramic pottery sherds, measurement calipers, field documentation notebooks, and magnifying loupes under natural daylight."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/language|linguist|french|german|kiswahili|spanish|translation/i.test(combined)) {
        const variants = [
          "Authentic photograph of a university language learning lab; audio headsets, language learning workbooks, transcription notes, and desktop workstations in a well-lit academic setting.",
          "Realistic editorial photograph of a linguistics study desk with bilingual dictionaries, phonetic transcription charts, notebook, and pen under warm natural daylight.",
          "Documentary photograph of a language tutorial room with students practicing conversational language skills around a seminar table with vocabulary cards and reference textbooks."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/journalism|media|broadcast|communicat|mass comm/i.test(combined)) {
        const variants = [
          "Authentic photograph of a broadcast journalism production studio; professional cardioid studio microphone on boom arm, audio mixing console with illuminated VU meters, headphones, and a reporter's spiral notebook under warm acoustic studio lighting.",
          "Editorial photograph of a university media newsroom workstation; dual monitors showing editorial layout software, camera DSLR body with prime lens on desk, press pass, and notepad under natural office lighting.",
          "Documentary photograph of a communications seminar room with students editing video media at workstations in a bright multimedia academic lab."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else if (/philosoph|ethics|theolog|religio/i.test(combined)) {
        const variants = [
          "Authentic editorial photograph of a philosophy department reading room; armchairs around a low wooden coffee table with classic philosophical texts, journals, and a ceramic tea mug beside a large floor-to-ceiling bookshelf.",
          "Realistic photograph of an ethics scholar's study desk with classical philosophical treatises, handwritten reflection notes on parchment paper, spectacles, and fountain pen under soft afternoon window light.",
          "Documentary photograph of a philosophy seminar discussion room with chalkboards containing ethical dilemmas and logical syllogisms, surrounded by wooden seminar chairs in natural daylight."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      } else {
        const variants = [
          "Authentic editorial photograph of a bright, modern university library reading hall with expansive wooden communal study desks, open academic reference textbooks, study carrels, and students working quietly in the background under natural sunlight filtering through large glass facade windows.",
          "Realistic documentary photograph of an academic lecture hall viewed from the rear tier showing curved oak desks, warm ambient lighting, and an organized lecture podium at the front.",
          "Realistic photograph of a university scholar's study desk with organized ring binders, lecture notepads, reference volumes, ballpoint pen, and a laptop with natural daylight from an adjacent window.",
          "Editorial photograph of a campus outdoor study courtyard with students seated at stone benches with study notes and books under the gentle shade of mature campus trees in soft morning light."
        ];
        visualSubject = variants[this.getDeterministicIndex(seed, variants.length)];
      }
    }

    const typeDesc = isLab
      ? "University Laboratory Practical Session"
      : (meta.materialType || "University Academic Lecture Notes");

    const compositionVariants = [
      "16:9 widescreen landscape framing, eye-level editorial perspective, balanced natural composition suitable for a mobile application resource card, authentic ambient room lighting with soft natural shadows, realistic optical depth of field.",
      "16:9 widescreen landscape framing, slightly elevated documentary perspective, natural diffused daylight from large windows, realistic surface textures, restrained contrast, crisp professional lens focus.",
      "16:9 widescreen landscape framing, medium shot with shallow depth of field (f/2.8) focusing sharply on the primary academic artifacts, gentle natural background blur, authentic indoor ambient illumination.",
      "16:9 widescreen landscape framing, over-the-shoulder perspective of a realistic academic workspace, authentic natural daylight balance, subtle environmental details, professional photographic composition."
    ];
    const compIndex = this.getDeterministicIndex(seed + "_comp", compositionVariants.length);
    const composition = compositionVariants[compIndex];

    const styleDescription = "Authentic professional editorial photography, documentary photography aesthetic, realistic materials and natural textures, believable real-world environment, restrained natural color grading, shot on professional DSLR/mirrorless camera with real optical lens characteristics. Strictly photographic realism with natural depth and exposure; no 3D CGI rendering, no digital artwork, no neon glow, no surreal futuristic visual effects.";

    const negativeConstraints = "MANDATORY REQUIREMENT: ABSOLUTELY ZERO TEXT. NO WRITTEN WORDS, NO LETTERS, NO NUMBERS, NO ALPHANUMERIC CHARACTERS, NO LABELS, NO HEADINGS, NO SUBTITLES, NO TITLES, NO CAPTIONS, NO TYPOGRAPHY, NO WRITTEN ANNOTATIONS, NO WATERMARKS, NO LOGOS, NO SYMBOLS WITH TEXT, NO FAKE BOOK COVERS, NO FAKE USER INTERFACES. THE ENTIRE IMAGE MUST BE 100% PURELY VISUAL WITH ZERO EMBEDDED TEXT. NO NEON LIGHTING, NO PURPLE OR CYAN GLOW, NO CYBERPUNK AESTHETICS, NO FLOATING CODE, NO HOLOGRAMS, NO 3D RENDERED CGI, NO DIGITAL ARTWORK, NO CARTOON, NO SURREAL SCI-FI EFFECTS.";

    const promptSections = [
      `[VISUAL SCENE & OBJECTS]: ${visualSubject}`,
      `[ACADEMIC RELEVANCE]: University educational context representing ${typeDesc}.`,
      `[COMPOSITION & LIGHTING]: ${composition}`,
      `[STYLE & RENDER QUALITY]: ${styleDescription}`,
      `[MANDATORY NEGATIVE CONSTRAINTS - STRICTLY NO TEXT]: ${negativeConstraints}`
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

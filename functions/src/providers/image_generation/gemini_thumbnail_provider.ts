import * as logger from "firebase-functions/logger";
import { EnvConfig } from "../../config/env_config";
import {
  ThumbnailImageProvider,
  MaterialMetadata,
  GeneratedThumbnailResult,
} from "./thumbnail_image_provider";

export class GeminiThumbnailProvider implements ThumbnailImageProvider {
  public readonly name = "gemini";
  public readonly priority = 2;
  private readonly providedApiKey?: string;

  // Candidate Gemini image generation models in order of priority
  public static readonly CANDIDATE_MODELS = [
    "gemini-2.5-flash-image",
    "gemini-3.1-flash-image",
    "gemini-3-pro-image",
    "gemini-3.1-flash-lite-image",
    "nano-banana-pro-preview",
  ];

  constructor(providedApiKey?: string) {
    this.providedApiKey = providedApiKey;
  }

  /**
   * Calls Gemini Image Generation API directly to produce an image from the prompt.
   * Iterates through available Gemini API keys and candidate image generation models with rotation.
   */
  public async generateImage(
    prompt: string,
    metadata: MaterialMetadata
  ): Promise<GeneratedThumbnailResult> {
    const keys = this.providedApiKey
      ? [this.providedApiKey]
      : EnvConfig.getApiKeys("gemini");

    if (!keys || keys.length === 0) {
      throw new Error("No Gemini API keys configured");
    }

    const cleanTitle = (metadata.title || "Academic Resource").trim();
    let lastError: Error | null = null;

    for (let k = 0; k < keys.length; k++) {
      const apiKey = keys[k];
      const maskedKey = EnvConfig.maskSecret(apiKey);

      for (const model of GeminiThumbnailProvider.CANDIDATE_MODELS) {
        try {
          const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
          logger.info(
            `[GEMINI_IMAGE_GEN_START] Key=${maskedKey} Model=${model} Title="${cleanTitle}"`
          );

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
          const part = candidate?.content?.parts?.find(
            (p: any) => p.inlineData && p.inlineData.data
          );

          if (part && part.inlineData && part.inlineData.data) {
            const mimeType = part.inlineData.mimeType || "image/jpeg";
            const imageBuffer = Buffer.from(part.inlineData.data, "base64");
            logger.info(
              `[GEMINI_IMAGE_GEN_SUCCESS] Key=${maskedKey} Model=${model} Generated image: ${imageBuffer.byteLength} bytes, MIME: ${mimeType}`
            );
            return {
              imageBuffer,
              mimeType,
              modelUsed: model,
            };
          }

          logger.warn(`[GEMINI_IMAGE_GEN_NOPART] Candidate returned but no image inlineData.`);
        } catch (err: any) {
          logger.warn(
            `[GEMINI_IMAGE_GEN_ATTEMPT_ERR] Key=${maskedKey} Model=${model}: ${err.message}`
          );
          lastError = err;
        }
      }
    }

    throw lastError || new Error("All Gemini image generation keys and models exhausted");
  }
}

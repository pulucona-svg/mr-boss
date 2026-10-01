import * as https from "https";
import * as logger from "firebase-functions/logger";
import { EnvConfig } from "../../config/env_config";
import {
  ThumbnailImageProvider,
  MaterialMetadata,
  GeneratedThumbnailResult,
} from "./thumbnail_image_provider";

export class FluxProviderError extends Error {
  public readonly isRetryable: boolean;
  public readonly statusCode?: number;
  public readonly cloudflareErrorCode?: number;

  constructor(
    message: string,
    isRetryable: boolean,
    statusCode?: number,
    cloudflareErrorCode?: number
  ) {
    super(message);
    this.name = "FluxProviderError";
    this.isRetryable = isRetryable;
    this.statusCode = statusCode;
    this.cloudflareErrorCode = cloudflareErrorCode;
  }
}

export class FluxThumbnailProvider implements ThumbnailImageProvider {
  public readonly name = "flux";
  public readonly priority = 1;

  private customConfig?: {
    accountId?: string;
    apiKey?: string;
    model?: string;
  };

  constructor(customConfig?: {
    accountId?: string;
    apiKey?: string;
    model?: string;
  }) {
    this.customConfig = customConfig;
  }

  /**
   * Generates a high-quality 16:9 educational thumbnail using Cloudflare Workers AI Flux-2 Dev.
   * Sends explicit multipart/form-data with verified parameters (width 1024, height 576, steps 25).
   * Enforces zero-text constraints and classifies retryable errors (429, 3040 out of capacity, 5xx, timeouts).
   */
  public async generateImage(
    prompt: string,
    metadata: MaterialMetadata
  ): Promise<GeneratedThumbnailResult> {
    const keys = this.customConfig?.apiKey
      ? [this.customConfig.apiKey]
      : EnvConfig.getApiKeys("flux");
    if (!keys || keys.length === 0) {
      throw new FluxProviderError(
        "No Flux API keys configured (FLUX_API_KEY / FLUX_API_KEYS)",
        false
      );
    }

    const accountId =
      this.customConfig?.accountId || EnvConfig.getCloudflareAccountId();
    if (!accountId) {
      throw new FluxProviderError(
        "No Cloudflare Account ID configured (CLOUDFLARE_ACCOUNT_ID)",
        false
      );
    }

    const model = this.customConfig?.model || EnvConfig.getFluxModel();
    const cleanTitle = (metadata.title || "Academic Resource").trim();

    // Enforce structured, text-free prompt formatting
    const finalPrompt = this.formatFluxPrompt(prompt, metadata);

    let lastError: Error | null = null;

    for (let k = 0; k < keys.length; k++) {
      const apiKey = keys[k];
      const maskedKey = EnvConfig.maskSecret(apiKey);

      try {
        logger.info(
          `[FLUX_IMAGE_GEN_START] Key=${maskedKey} Model=${model} Title="${cleanTitle}"`
        );
        const startTime = Date.now();

        const result = await this.executeCloudflareRequest(
          accountId,
          model,
          apiKey,
          finalPrompt
        );

        const duration = Date.now() - startTime;
        logger.info(
          `[FLUX_IMAGE_GEN_SUCCESS] Key=${maskedKey} Model=${model} Generated image: ${result.imageBuffer.byteLength} bytes in ${duration}ms`
        );

        return {
          imageBuffer: result.imageBuffer,
          mimeType: result.mimeType,
          modelUsed: model,
        };
      } catch (err: any) {
        logger.warn(
          `[FLUX_IMAGE_GEN_ERROR] Key=${maskedKey} Model=${model}: ${err.message}`
        );
        lastError = err;

        // If error is retryable (like 429 or 3040 out of capacity), break out immediately
        // so the durable queue can handle backoff rather than burning all keys at once
        if (err instanceof FluxProviderError && err.isRetryable) {
          throw err;
        }
      }
    }

    throw lastError || new FluxProviderError("All Flux API keys exhausted or failed", false);
  }

  /**
   * Formats the prompt specifically for Flux diffusion model to eliminate text rendering.
   * Separates visual scene, composition, quality, and explicit negative text constraints.
   */
  public formatFluxPrompt(rawPrompt: string, metadata: MaterialMetadata): string {
    // If prompt is already structured, ensure the strict negative constraints are appended
    const strictNoTextConstraints = [
      "MANDATORY REQUIREMENT: ABSOLUTELY ZERO TEXT. NO WRITTEN WORDS, NO LETTERS, NO NUMBERS, NO ALPHANUMERIC CHARACTERS, NO LABELS, NO HEADINGS, NO SUBTITLES, NO TITLES, NO CAPTIONS, NO TYPOGRAPHY, NO WRITTEN ANNOTATIONS, NO WATERMARKS, NO LOGOS, NO SYMBOLS WITH TEXT, NO FAKE BOOK COVERS, NO FAKE USER INTERFACES. THE ENTIRE IMAGE MUST BE 100% PURELY VISUAL WITH ZERO EMBEDDED TEXT."
    ].join(" ");

    if (rawPrompt.includes("MANDATORY REQUIREMENT: ABSOLUTELY ZERO TEXT")) {
      return rawPrompt;
    }

    return `${rawPrompt}\n\n[STRICT NEGATIVE CONSTRAINTS]: ${strictNoTextConstraints}`;
  }

  /**
   * Executes the raw HTTPS multipart/form-data request to Cloudflare Workers AI.
   * Explicitly sets boundary and Content-Length to avoid chunked transfer issues.
   * Scoped to IPv4 (family: 4) to ensure deterministic network resolution across platforms.
   */
  private executeCloudflareRequest(
    accountId: string,
    model: string,
    apiKey: string,
    prompt: string
  ): Promise<{ imageBuffer: Buffer; mimeType: string }> {
    return new Promise((resolve, reject) => {
      const boundary = "----CloudflareBoundary" + Date.now().toString(16) + Math.random().toString(16).slice(2, 8);

      let payload = "";
      payload += `--${boundary}\r\n`;
      payload += `Content-Disposition: form-data; name="prompt"\r\n\r\n`;
      payload += `${prompt}\r\n`;

      payload += `--${boundary}\r\n`;
      payload += `Content-Disposition: form-data; name="steps"\r\n\r\n`;
      payload += `25\r\n`;

      payload += `--${boundary}\r\n`;
      payload += `Content-Disposition: form-data; name="width"\r\n\r\n`;
      payload += `1024\r\n`;

      payload += `--${boundary}\r\n`;
      payload += `Content-Disposition: form-data; name="height"\r\n\r\n`;
      payload += `576\r\n`;

      payload += `--${boundary}--\r\n`;

      const bodyBuffer = Buffer.from(payload, "utf8");

      const options: https.RequestOptions = {
        hostname: "api.cloudflare.com",
        port: 443,
        path: `/client/v4/accounts/${accountId}/ai/run/${model}`,
        method: "POST",
        family: 4, // Scoped IPv4 preference for Cloudflare edge routing
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": `multipart/form-data; boundary=${boundary}`,
          "Content-Length": bodyBuffer.length,
          "User-Agent": "MirrorDigital-ThumbnailService/1.0",
        },
        timeout: 60000, // 60 seconds
      };

      const req = https.request(options, (res) => {
        const statusCode = res.statusCode || 500;
        const contentType = res.headers["content-type"] || "";
        const chunks: Buffer[] = [];

        res.on("data", (chunk: Buffer) => {
          chunks.push(chunk);
        });

        res.on("end", () => {
          const responseBuffer = Buffer.concat(chunks);

          if (statusCode >= 400) {
            const errBody = responseBuffer.toString("utf8").slice(0, 300);
            let cfCode: number | undefined;
            let isRetryable = false;

            try {
              const parsed = JSON.parse(responseBuffer.toString("utf8"));
              if (parsed.errors && parsed.errors.length > 0) {
                cfCode = parsed.errors[0]?.code;
              }
            } catch (_) {}

            // Classify retryable vs permanent errors:
            // 429 = Rate Limit / Account limits
            // 3040 = Cloudflare Workers AI "Out of capacity"
            // 408 = Timeout
            // 5xx = Cloudflare / upstream gateway failures
            const lowerBody = errBody.toLowerCase();
            if (
              statusCode === 429 ||
              statusCode === 408 ||
              (statusCode >= 500 && statusCode <= 599) ||
              cfCode === 3040 ||
              cfCode === 4006 ||
              lowerBody.includes("out of capacity") ||
              lowerBody.includes("capacity") ||
              lowerBody.includes("rate limit") ||
              lowerBody.includes("allocation") ||
              lowerBody.includes("temporarily")
            ) {
              isRetryable = true;
            }

            return reject(
              new FluxProviderError(
                `Cloudflare HTTP ${statusCode} (${res.statusMessage}): ${errBody}`,
                isRetryable,
                statusCode,
                cfCode
              )
            );
          }

          if (contentType.includes("application/json")) {
            try {
              const json = JSON.parse(responseBuffer.toString("utf8"));
              if (!json.success && json.errors && json.errors.length > 0) {
                const firstErr = json.errors[0];
                const msg = json.errors.map((e: any) => e.message || e.code).join("; ");
                const code = firstErr?.code;
                const isRetryable =
                  code === 3040 ||
                  code === 4006 ||
                  msg.toLowerCase().includes("out of capacity") ||
                  msg.toLowerCase().includes("capacity") ||
                  msg.toLowerCase().includes("allocation") ||
                  msg.toLowerCase().includes("rate limit");

                return reject(
                  new FluxProviderError(
                    `Cloudflare AI error: ${msg}`,
                    isRetryable,
                    statusCode,
                    code
                  )
                );
              }

              if (json.result && json.result.image) {
                const imgBuf = Buffer.from(json.result.image, "base64");
                if (imgBuf.length === 0) {
                  return reject(
                    new FluxProviderError(
                      "Cloudflare returned empty base64 image data",
                      true, // retryable empty payload
                      statusCode
                    )
                  );
                }
                return resolve({
                  imageBuffer: imgBuf,
                  mimeType: "image/jpeg",
                });
              }

              return reject(
                new FluxProviderError(
                  "Cloudflare JSON response missing result.image",
                  false,
                  statusCode
                )
              );
            } catch (parseErr: any) {
              return reject(
                new FluxProviderError(
                  `Failed to parse Cloudflare JSON response: ${parseErr.message}`,
                  false,
                  statusCode
                )
              );
            }
          } else {
            // Direct binary image response
            if (responseBuffer.length === 0) {
              return reject(
                new FluxProviderError(
                  "Cloudflare returned empty binary image response",
                  true,
                  statusCode
                )
              );
            }
            const mime = contentType.includes("png") ? "image/png" : "image/jpeg";
            return resolve({
              imageBuffer: responseBuffer,
              mimeType: mime,
            });
          }
        });
      });

      req.on("error", (netErr: any) => {
        // Transient network errors are retryable
        reject(
          new FluxProviderError(
            `Network error connecting to Cloudflare: ${netErr.message}`,
            true
          )
        );
      });

      req.on("timeout", () => {
        req.destroy();
        // 60-second timeouts are retryable
        reject(
          new FluxProviderError(
            "Cloudflare request timed out after 60 seconds",
            true,
            408
          )
        );
      });

      req.write(bodyBuffer);
      req.end();
    });
  }
}

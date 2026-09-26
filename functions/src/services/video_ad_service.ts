import * as fs from "fs";
import * as path from "path";
import * as os from "os";
import ffmpeg from "fluent-ffmpeg";
import * as logger from "firebase-functions/logger";

let ffmpegConfigured = false;
function ensureFfmpegConfigured(): void {
  if (ffmpegConfigured) return;
  try {
    const ffmpegInstaller = require("@ffmpeg-installer/ffmpeg");
    if (ffmpegInstaller?.path) {
      ffmpeg.setFfmpegPath(ffmpegInstaller.path);
    }
  } catch (e) {
    logger.warn("[VIDEO_SERVICE] Could not load @ffmpeg-installer/ffmpeg:", e);
  }

  try {
    const ffprobeInstaller = require("@ffprobe-installer/ffprobe");
    if (ffprobeInstaller?.path) {
      ffmpeg.setFfprobePath(ffprobeInstaller.path);
    }
  } catch (e) {
    logger.warn("[VIDEO_SERVICE] Could not load @ffprobe-installer/ffprobe:", e);
  }
  ffmpegConfigured = true;
}

export interface VideoTrimResult {
  trimmed: boolean;
  buffer: Buffer;
  originalDuration: number;
  finalDuration: number;
}

export class VideoAdService {
  /**
   * Inspects a video buffer and trims it to maxDurationSeconds (default: 30s)
   * while strictly preserving audio.
   * If video <= maxDurationSeconds, returns original buffer.
   * If automatic trimming fails, throws an error.
   */
  static async processVideoAd(
    inputBuffer: Buffer,
    fileName: string = "video.mp4",
    maxDurationSeconds = 30
  ): Promise<VideoTrimResult> {
    ensureFfmpegConfigured();
    const timestamp = Date.now();
    const safeName = (fileName || "video.mp4").replace(/[^a-zA-Z0-9._-]/g, "_");
    const inputPath = path.join(os.tmpdir(), `ad_in_${timestamp}_${safeName}`);
    const outputPath = path.join(os.tmpdir(), `ad_out_${timestamp}_${safeName}`);

    try {
      // 1. Write incoming buffer to temporary file for FFmpeg
      await fs.promises.writeFile(inputPath, inputBuffer);

      // 2. Check duration using ffprobe
      const metadata = await new Promise<any>((resolve, reject) => {
        ffmpeg.ffprobe(inputPath, (err, data) => {
          if (err) return reject(err);
          resolve(data);
        });
      });

      const rawDuration = metadata?.format?.duration;
      const duration = typeof rawDuration === "number" ? rawDuration : parseFloat(rawDuration || "0");
      logger.info(`[VIDEO_AD_INSPECT] "${fileName}" duration: ${duration.toFixed(2)}s (Limit: ${maxDurationSeconds}s)`);

      // 3. Strict duration boundary: <= maxDurationSeconds (30.0s) preserved as-is.
      // Any duration > 30.0s (e.g. 30.01s, 30.5s) must be trimmed to the first 30.0s.
      if (duration <= maxDurationSeconds) {
        return {
          trimmed: false,
          buffer: inputBuffer,
          originalDuration: duration,
          finalDuration: duration,
        };
      }

      // 4. Exceeds limit: trim first maxDurationSeconds with audio preservation
      logger.info(`[VIDEO_AD_TRIMMING] Trimming "${fileName}" from ${duration.toFixed(2)}s down to ${maxDurationSeconds}s...`);

      await new Promise<void>((resolve, reject) => {
        // First try fast stream copy
        ffmpeg(inputPath)
          .setStartTime(0)
          .setDuration(maxDurationSeconds)
          .outputOptions([
            "-c:v copy",
            "-c:a copy",
          ])
          .output(outputPath)
          .on("end", () => resolve())
          .on("error", (err) => {
            logger.warn(`[VIDEO_AD_TRIM_STREAM_COPY_FAILED] Fast stream copy failed: ${err.message}. Retrying with transcode...`);
            // Fallback to fast transcode if stream copy fails (e.g. non-keyframe cut)
            ffmpeg(inputPath)
              .setStartTime(0)
              .setDuration(maxDurationSeconds)
              .outputOptions([
                "-c:v libx264",
                "-preset veryfast",
                "-c:a aac",
                "-b:a 128k",
                "-movflags +faststart",
              ])
              .output(outputPath)
              .on("end", () => resolve())
              .on("error", (reEncodeErr) => reject(reEncodeErr))
              .run();
          })
          .run();
      });

      if (!fs.existsSync(outputPath)) {
        throw new Error("Trimmed video output file was not produced.");
      }

      const trimmedBuffer = await fs.promises.readFile(outputPath);
      logger.info(`[VIDEO_AD_TRIMMED_SUCCESS] Successfully trimmed "${fileName}" (${trimmedBuffer.length} bytes). Audio preserved.`);

      return {
        trimmed: true,
        buffer: trimmedBuffer,
        originalDuration: duration,
        finalDuration: maxDurationSeconds,
      };
    } catch (err: any) {
      logger.error(`[VIDEO_AD_TRIM_ERROR] Failed to process/trim video "${fileName}":`, err);
      throw new Error(`Automatic trimming failed. Please provide a video under 30 seconds. (${err.message})`);
    } finally {
      // Cleanup temp files
      try {
        if (fs.existsSync(inputPath)) await fs.promises.unlink(inputPath);
      } catch (_) {}
      try {
        if (fs.existsSync(outputPath)) await fs.promises.unlink(outputPath);
      } catch (_) {}
    }
  }
}

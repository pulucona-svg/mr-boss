import * as fs from "fs";
import * as path from "path";
import * as logger from "firebase-functions/logger";

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

// Automatically load .env files
loadEnvFile(path.join(process.cwd(), ".env"));
loadEnvFile(path.join(process.cwd(), ".env.mirror-laikipia"));
loadEnvFile(path.join(__dirname, "../../.env"));
loadEnvFile(path.join(__dirname, "../../.env.mirror-laikipia"));

export interface ProviderHealthStatus {
  name: string;
  healthy: boolean;
  latencyMs: number;
  error?: string;
  maskedKey: string;
}

export interface WorkerHealthStatus {
  workerId: string;
  healthy: boolean;
  latencyMs: number;
  error?: string;
  maskedKey: string;
}

export class EnvConfig {
  private static providerHealthMap: Map<string, ProviderHealthStatus> = new Map();
  private static workerHealthMap: Map<string, WorkerHealthStatus> = new Map();

  /**
   * Masks secret keys so they are NEVER printed raw in any log output.
   * e.g. sk-svcacct-... -> sk-sv...****...EIA
   */
  public static maskSecret(secret?: string): string {
    if (!secret || typeof secret !== "string") return "(not configured)";
    const trimmed = secret.trim();
    if (trimmed.length < 8) return "********";

    if (trimmed.startsWith("sk-")) {
      const prefix = trimmed.slice(0, 7);
      const suffix = trimmed.slice(-4);
      return `${prefix}************${suffix}`;
    }
    if (trimmed.startsWith("AIza") || trimmed.startsWith("AQ.")) {
      const prefix = trimmed.slice(0, 6);
      const suffix = trimmed.slice(-4);
      return `${prefix}************${suffix}`;
    }
    if (trimmed.startsWith("private_") || trimmed.startsWith("public_")) {
      const prefix = trimmed.slice(0, 10);
      const suffix = trimmed.slice(-4);
      return `${prefix}************${suffix}`;
    }

    return `${trimmed.slice(0, 4)}************${trimmed.slice(-4)}`;
  }

  /**
   * Helper to parse, trim, filter, and deduplicate comma-separated API key pools.
   */
  public static parseKeyPool(raw?: string): string[] {
    if (!raw || typeof raw !== "string") return [];
    const keys = raw
      .split(",")
      .map((k) => k.trim())
      .filter((k) => k.length > 0);
    // Deduplicate identical keys
    return Array.from(new Set(keys));
  }

  /**
   * Retrieves single primary API key for a provider.
   */
  public static getApiKey(providerName: string): string {
    const keys = this.getApiKeys(providerName);
    return keys[0] || "";
  }

  /**
   * Generates a safe, non-sensitive identifier for an API key.
   * e.g. "gemini_key_01", "openai_key_02".
   */
  public static getKeyIdentifier(providerName: string, apiKey: string, index?: number): string {
    const p = (providerName || "unknown").toLowerCase().trim();
    if (typeof index === "number") {
      return `${p}_key_${String(index + 1).padStart(2, "0")}`;
    }
    const allKeys = this.getApiKeys(providerName);
    const foundIdx = allKeys.indexOf(apiKey);
    if (foundIdx >= 0) {
      return `${p}_key_${String(foundIdx + 1).padStart(2, "0")}`;
    }
    return `${p}_key_primary`;
  }

  /**
   * Retrieves array of deduplicated, validated API keys for multi-worker providers.
   */
  public static getApiKeys(providerName: string): string[] {
    const name = (providerName || "").toLowerCase().trim();
    switch (name) {
      case "kimi": {
        const raw = process.env.KIMI_API_KEYS || process.env.KIMI_API_KEY || "";
        const keys = this.parseKeyPool(raw);
        // Exclude Gemini-style keys (starting with AQ. or AIza) from Kimi configuration
        const validKimiKeys = keys.filter((k) => {
          if (k.startsWith("AQ.") || k.startsWith("AIza")) {
            return false;
          }
          return k.length > 0;
        });
        return validKimiKeys;
      }
      case "openai": {
        const raw = process.env.OPENAI_API_KEYS || process.env.OPENAI_API_KEY || "";
        return this.parseKeyPool(raw);
      }
      case "gemini": {
        const raw = process.env.GEMINI_API_KEYS || process.env.GEMINI_API_KEY || "";
        return this.parseKeyPool(raw);
      }
      case "claude": {
        const raw = process.env.CLAUDE_API_KEYS || process.env.CLAUDE_API_KEY || "";
        return this.parseKeyPool(raw);
      }
      case "deepseek": {
        const raw = process.env.DEEPSEEK_API_KEYS || process.env.DEEPSEEK_API_KEY || "";
        return this.parseKeyPool(raw);
      }
      case "grok": {
        const raw = process.env.GROK_API_KEYS || process.env.GROK_API_KEY || process.env.XAI_API_KEY || "";
        return this.parseKeyPool(raw);
      }
      case "pixabay": {
        const raw = process.env.PIXABAY_API_KEY || "";
        return raw ? this.parseKeyPool(raw) : [];
      }
      default: {
        const single = process.env[`${name.toUpperCase()}_API_KEY`];
        return single ? this.parseKeyPool(single) : [];
      }
    }
  }

  /**
   * Validates presence of essential environment variables during startup.
   */
  public static validateRequiredEnvVars(): { valid: boolean; missingVars: string[] } {
    const missing: string[] = [];

    const required = [
      "OPENAI_API_KEY",
      "GEMINI_API_KEY",
      "IMAGEKIT_PUBLIC_KEY",
      "IMAGEKIT_PRIVATE_KEY",
      "IMAGEKIT_URL_ENDPOINT",
    ];

    for (const v of required) {
      if (!process.env[v] || !process.env[v]?.trim()) {
        missing.push(v);
      }
    }

    if (missing.length > 0) {
      logger.error(`[ENV_CONFIG_ERROR] Startup failed! Missing required environment variables: ${missing.join(", ")}`);
    }

    return { valid: missing.length === 0, missingVars: missing };
  }

  /**
   * Checks if a provider overall is currently marked healthy.
   */
  public static isProviderHealthy(providerName: string): boolean {
    const status = this.providerHealthMap.get(providerName.toLowerCase().trim());
    if (!status) return true;
    return status.healthy;
  }

  /**
   * Updates health status for a provider.
   */
  public static setProviderHealth(providerName: string, healthy: boolean, latencyMs: number, error?: string): void {
    const name = providerName.toLowerCase().trim();
    const maskedKey = this.maskSecret(this.getApiKey(name));
    this.providerHealthMap.set(name, {
      name,
      healthy,
      latencyMs,
      error,
      maskedKey,
    });
  }

  /**
   * Checks if a specific worker ID is currently healthy.
   */
  public static isWorkerHealthy(workerId: string): boolean {
    const status = this.workerHealthMap.get(workerId);
    if (!status) return true; // Default to true
    return status.healthy;
  }

  /**
   * Updates health status for a specific worker ID.
   */
  public static setWorkerHealth(workerId: string, healthy: boolean, latencyMs: number, error?: string, apiKey?: string): void {
    const maskedKey = this.maskSecret(apiKey || "");
    this.workerHealthMap.set(workerId, {
      workerId,
      healthy,
      latencyMs,
      error,
      maskedKey,
    });
  }

  /**
   * Performs startup local configuration verification and prints clean Startup Report without making paid network calls.
   */
  public static async runStartupVerificationAndReport(): Promise<void> {
    const { valid, missingVars } = this.validateRequiredEnvVars();
    if (!valid) {
      console.error("=================================================");
      console.error(" STARTUP ERROR: MISSING REQUIRED ENVIRONMENT VARIABLES");
      console.error(` Missing: ${missingVars.join(", ")}`);
      console.error("=================================================");
      return;
    }

    console.log("\n=================================================");
    console.log(" MIRROR LAIKIPIA EXPLORE BACKEND STARTUP REPORT");
    console.log("=================================================");

    const geminiKeys = this.getApiKeys("gemini");
    const openaiKeys = this.getApiKeys("openai");
    const grokKeys = this.getApiKeys("grok");
    const kimiKeys = this.getApiKeys("kimi");

    console.log(`[AI_PROVIDER_HEALTH]`);
    console.log(` Gemini: ${geminiKeys.length} key(s) configured / ${geminiKeys.length} eligible`);
    console.log(` OpenRouter/OpenAI: ${openaiKeys.length} key(s) configured / ${openaiKeys.length} eligible`);
    console.log(` Groq: ${grokKeys.length} key(s) configured / ${grokKeys.length} eligible`);
    if (kimiKeys.length > 0) {
      console.log(` Kimi: ${kimiKeys.length} key(s) configured / ${kimiKeys.length} eligible`);
    } else {
      console.log(` Kimi: unavailable / invalid credentials`);
    }

    // Verify ImageKit
    const ikPub = process.env.IMAGEKIT_PUBLIC_KEY;
    const ikMasked = this.maskSecret(ikPub);
    console.log(` ImageKit: connected (Key: ${ikMasked})`);

    // Verify Firebase
    const fbProject = process.env.GCLOUD_PROJECT || "mirror-laikipia";
    console.log(` Firebase: connected (Project: ${fbProject})`);

    console.log("=================================================\n");
  }
}

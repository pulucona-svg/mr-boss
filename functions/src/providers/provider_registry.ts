import * as logger from "firebase-functions/logger";
import { IAIProvider } from "../types/worker";
import { OpenAIProvider } from "./openai_provider";
import { KimiProvider } from "./kimi_provider";
import { GeminiProvider } from "./gemini_provider";
import { ClaudeProvider } from "./claude_provider";
import { GrokProvider } from "./grok_provider";
import { DeepSeekProvider } from "./deepseek_provider";

export class AIProviderRegistry {
  private static providers: Map<string, IAIProvider> = new Map();
  private static initialized = false;

  private static initializeDefaults() {
    if (this.initialized) return;
    this.registerProvider(new OpenAIProvider());
    this.registerProvider(new KimiProvider());
    this.registerProvider(new GeminiProvider());
    this.registerProvider(new ClaudeProvider());
    this.registerProvider(new GrokProvider());
    this.registerProvider(new DeepSeekProvider());
    this.initialized = true;
    logger.info("[PROVIDER_REGISTRY] Default providers registered: openai, kimi, gemini, claude, grok, deepseek");
  }

  /**
   * Registers a new AI provider implementation dynamically.
   */
  static registerProvider(provider: IAIProvider): void {
    const key = provider.name.toLowerCase().trim();
    this.providers.set(key, provider);
    logger.info(`[PROVIDER_REGISTRY] Registered provider: "${key}"`);
  }

  /**
   * Retrieves a registered provider by name.
   */
  static getProvider(providerName: string): IAIProvider {
    this.initializeDefaults();
    const key = (providerName || "").toLowerCase().trim();
    const provider = this.providers.get(key);

    if (!provider) {
      throw new Error(
        `AI provider "${providerName}" is not registered in AIProviderRegistry. Available providers: ${Array.from(
          this.providers.keys()
        ).join(", ")}`
      );
    }

    return provider;
  }

  /**
   * Checks if a provider name is registered.
   */
  static hasProvider(providerName: string): boolean {
    this.initializeDefaults();
    return this.providers.has((providerName || "").toLowerCase().trim());
  }

  /**
   * Returns list of all registered provider names.
   */
  static listRegisteredProviders(): string[] {
    this.initializeDefaults();
    return Array.from(this.providers.keys());
  }
}

export const ProviderRegistry = AIProviderRegistry;


import * as logger from "firebase-functions/logger";
import { IImageProvider } from "../../types/image_worker";
import { PixabayImageProvider } from "./pixabay_image_provider";
import { WikimediaImageProvider } from "./wikimedia_image_provider";
import { BingImageProvider } from "./bing_image_provider";
import { GoogleImageProvider } from "./google_image_provider";
import { UnsplashImageProvider } from "./unsplash_image_provider";

export class ImageProviderRegistry {
  private static providers: Map<string, IImageProvider> = new Map();
  private static initialized = false;

  private static initializeDefaults() {
    if (this.initialized) return;
    this.registerProvider(new PixabayImageProvider());
    this.registerProvider(new WikimediaImageProvider());
    this.registerProvider(new BingImageProvider());
    this.registerProvider(new GoogleImageProvider());
    this.registerProvider(new UnsplashImageProvider());
    this.initialized = true;
    logger.info(
      "[IMAGE_PROVIDER_REGISTRY] Default image providers registered: pixabay, wikimedia, bing, google, unsplash"
    );
  }

  /**
   * Registers a new image provider implementation dynamically.
   */
  static registerProvider(provider: IImageProvider): void {
    const key = provider.name.toLowerCase().trim();
    this.providers.set(key, provider);
    logger.info(`[IMAGE_PROVIDER_REGISTRY] Registered image provider: "${key}"`);
  }

  /**
   * Retrieves a registered image provider by name.
   */
  static getProvider(providerName: string): IImageProvider {
    this.initializeDefaults();
    const key = (providerName || "").toLowerCase().trim();
    const provider = this.providers.get(key);

    if (!provider) {
      // Fallback: return Pixabay or Wikimedia if requested provider is unknown
      const fallbackKey = this.providers.has("pixabay") ? "pixabay" : Array.from(this.providers.keys())[0];
      logger.warn(
        `[IMAGE_PROVIDER_REGISTRY] Image provider "${providerName}" not registered. Falling back to "${fallbackKey}".`
      );
      return this.providers.get(fallbackKey)!;
    }

    return provider;
  }

  /**
   * Checks if an image provider name is registered.
   */
  static hasProvider(providerName: string): boolean {
    this.initializeDefaults();
    return this.providers.has((providerName || "").toLowerCase().trim());
  }

  /**
   * Returns list of all registered image provider names.
   */
  static listRegisteredProviders(): string[] {
    this.initializeDefaults();
    return Array.from(this.providers.keys());
  }
}

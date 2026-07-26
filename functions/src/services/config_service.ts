import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { ExploreConfig } from "../types/explore";

const DEFAULT_CONFIG: ExploreConfig = {
  workerCount: 5,
  articlesPerCategory: 25,
  refreshMinutes: 60,
  maxRetries: 3,
  searchModel: "gpt-4o",
};

export class ConfigService {
  /**
   * Reads system configuration from system/exploreConfig in Firestore.
   * Falls back to standard defaults for any missing fields.
   */
  static async getExploreConfig(db: admin.firestore.Firestore): Promise<ExploreConfig> {
    try {
      const docRef = db.collection("system").doc("exploreConfig");
      const snap = await docRef.get();

      if (!snap.exists) {
        logger.info("[CONFIG_SERVICE] system/exploreConfig document does not exist. Using defaults.");
        return { ...DEFAULT_CONFIG };
      }

      const data = snap.data() || {};
      const config: ExploreConfig = {
        workerCount: typeof data.workerCount === "number" ? data.workerCount : DEFAULT_CONFIG.workerCount,
        articlesPerCategory:
          typeof data.articlesPerCategory === "number" ? data.articlesPerCategory : DEFAULT_CONFIG.articlesPerCategory,
        refreshMinutes:
          typeof data.refreshMinutes === "number" ? data.refreshMinutes : DEFAULT_CONFIG.refreshMinutes,
        maxRetries: typeof data.maxRetries === "number" ? data.maxRetries : DEFAULT_CONFIG.maxRetries,
        searchModel: typeof data.searchModel === "string" && data.searchModel.trim() ? data.searchModel.trim() : DEFAULT_CONFIG.searchModel,
        openAiApiKey: typeof data.openAiApiKey === "string" && data.openAiApiKey.trim() ? data.openAiApiKey.trim() : undefined,
      };

      logger.info("[CONFIG_SERVICE] Loaded system/exploreConfig:", JSON.stringify(config));
      return config;
    } catch (err: any) {
      logger.error("[CONFIG_SERVICE_ERROR] Failed to fetch system/exploreConfig, falling back to defaults:", err);
      return { ...DEFAULT_CONFIG };
    }
  }
}

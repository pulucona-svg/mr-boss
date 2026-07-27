import OpenAI from "openai";
import * as logger from "firebase-functions/logger";
import { BaseAIProvider } from "./base_provider";
import { AIWorker, DiscoveredArticle } from "../types/worker";
import { EnvConfig } from "../config/env_config";

export class DeepSeekProvider extends BaseAIProvider {
  readonly name = "deepseek";

  async discoverNews(
    categoryName: string,
    targetArticles: number,
    worker: AIWorker
  ): Promise<DiscoveredArticle[]> {
    const apiKey = worker.apiKey || EnvConfig.getApiKey("deepseek");
    if (!apiKey) {
      throw new Error(`DeepSeek API key missing for worker ${worker.workerId}`);
    }

    const maskedKey = EnvConfig.maskSecret(apiKey);


    const client = new OpenAI({
      apiKey,
      baseURL: worker.baseUrl || "https://api.deepseek.com/v1",
    });

    const model = worker.model || "deepseek-chat";

    logger.info(`[DEEPSEEK_PROVIDER] Worker="${worker.workerId}" Key="${maskedKey}" Category="${categoryName}" Model="${model}"`);

    const response = await client.chat.completions.create({
      model,
      messages: [
        {
          role: "system",
          content: "You are an automated real-time news discovery engine powered by DeepSeek.",
        },
        {
          role: "user",
          content: `Discover breaking news for category "${categoryName}". Target: ${targetArticles} articles. Return JSON with articles array.`,
        },
      ],
      response_format: { type: "json_object" },
      temperature: 0.3,
    });

    const content = response.choices[0]?.message?.content;
    if (!content) {
      throw new Error(`DeepSeek worker ${worker.workerId} returned empty response.`);
    }

    return this.parseNewsJson(content, categoryName);
  }
}

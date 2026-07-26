import OpenAI from "openai";
import * as logger from "firebase-functions/logger";
import { BaseAIProvider } from "./base_provider";
import { AIWorker, DiscoveredArticle } from "../types/worker";

export class GrokProvider extends BaseAIProvider {
  readonly name = "grok";

  async discoverNews(
    categoryName: string,
    targetArticles: number,
    worker: AIWorker
  ): Promise<DiscoveredArticle[]> {
    const apiKey = worker.apiKey;
    if (!apiKey) {
      throw new Error(`Grok API key missing for worker ${worker.workerId}`);
    }

    const client = new OpenAI({
      apiKey,
      baseURL: worker.baseUrl || "https://api.x.ai/v1",
    });

    const model = worker.model || "grok-beta";

    logger.info(`[GROK_PROVIDER] Worker="${worker.workerId}" Category="${categoryName}" Model="${model}"`);

    const response = await client.chat.completions.create({
      model,
      messages: [
        {
          role: "system",
          content: "You are an automated real-time news discovery engine powered by Grok.",
        },
        {
          role: "user",
          content: `Discover latest breaking news for category "${categoryName}". Return JSON with articles array.`,
        },
      ],
      temperature: 0.3,
    });

    const content = response.choices[0]?.message?.content;
    if (!content) {
      throw new Error(`Grok worker ${worker.workerId} returned empty response.`);
    }

    return this.parseNewsJson(content, categoryName);
  }
}

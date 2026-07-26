import OpenAI from "openai";
import * as logger from "firebase-functions/logger";
import { BaseAIProvider } from "./base_provider";
import { AIWorker, DiscoveredArticle } from "../types/worker";

export class KimiProvider extends BaseAIProvider {
  readonly name = "kimi";

  async discoverNews(
    categoryName: string,
    targetArticles: number,
    worker: AIWorker
  ): Promise<DiscoveredArticle[]> {
    const apiKey = worker.apiKey;
    if (!apiKey) {
      throw new Error(`Kimi API key missing for worker ${worker.workerId}`);
    }

    const client = new OpenAI({
      apiKey,
      baseURL: worker.baseUrl || "https://api.moonshot.cn/v1",
    });

    const model = worker.model || "moonshot-v1-8k";

    const systemPrompt =
      "You are an automated news discovery engine powered by Kimi. Extract latest breaking news stories in JSON format.";

    const userPrompt = `
Discover breaking news for category "${categoryName}".
Target: ${targetArticles} articles.
Return JSON with key "articles" containing title, source, sourceUrl, publishedAt, summary.
`;

    logger.info(`[KIMI_PROVIDER] Worker="${worker.workerId}" Category="${categoryName}" Model="${model}"`);

    const response = await client.chat.completions.create({
      model,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      temperature: 0.3,
    });

    const content = response.choices[0]?.message?.content;
    if (!content) {
      throw new Error(`Kimi worker ${worker.workerId} returned empty response.`);
    }

    return this.parseNewsJson(content, categoryName);
  }
}

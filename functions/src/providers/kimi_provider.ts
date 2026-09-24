import OpenAI from "openai";
import * as logger from "firebase-functions/logger";
import { BaseAIProvider } from "./base_provider";
import { AIWorker, DiscoveredArticle } from "../types/worker";
import { EnvConfig } from "../config/env_config";

export class KimiProvider extends BaseAIProvider {
  readonly name = "kimi";

  private getClient(worker: AIWorker): { client: OpenAI; model: string; maskedKey: string } {
    const apiKey = worker.apiKey || EnvConfig.getApiKey("kimi");
    if (!apiKey || apiKey.startsWith("AQ.") || apiKey.startsWith("AIza")) {
      throw new Error(`Invalid Kimi API key for worker ${worker.workerId} (Gemini credential or missing key detected). Kimi provider unavailable.`);
    }

    const maskedKey = EnvConfig.maskSecret(apiKey);
    const client = new OpenAI({
      apiKey,
      baseURL: worker.baseUrl || "https://api.moonshot.cn/v1",
    });

    const model = worker.model || "moonshot-v1-8k";
    return { client, model, maskedKey };
  }

  async discoverNews(
    categoryName: string,
    targetArticles: number,
    worker: AIWorker
  ): Promise<DiscoveredArticle[]> {
    const { client, model, maskedKey } = this.getClient(worker);

    const systemPrompt =
      "You are a news research engine. Return only verifiable, recent reporting from legitimate organisations; never invent a source, URL, date, quote, or event.";

    const userPrompt = `
Research at least ${targetArticles} DISTINCT recent news events for category "${categoryName}".
Prefer reporting from BBC, CNN, Reuters, Associated Press, Al Jazeera, The Guardian and other established outlets. Use available web/news search grounding. Different outlets covering the same event count once.
Return strictly JSON with key "articles". Each item must contain title, source, sourceUrl (a direct real article URL), publishedAt (ISO timestamp when available), and summary. Omit any item whose URL or date cannot be verified.
`;

    logger.info(`[KIMI_PROVIDER] Worker="${worker.workerId}" Key="${maskedKey}" Category="${categoryName}" Model="${model}"`);

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

  async generateMetadata(prompt: string, worker: AIWorker): Promise<any> {
    const { client, model, maskedKey } = this.getClient(worker);
    logger.info(`[KIMI_METADATA] Worker="${worker.workerId}" Key="${maskedKey}" Model="${model}"`);

    const response = await client.chat.completions.create({
      model,
      messages: [
        { role: "system", content: "You are Kimi, an AI assistant generating structured news metadata in valid JSON format." },
        { role: "user", content: prompt },
      ],
      temperature: 0.3,
    });

    const content = response.choices[0]?.message?.content;
    if (!content) {
      throw new Error(`Kimi worker ${worker.workerId} returned empty metadata content.`);
    }

    try {
      const match = content.match(/\{[\s\S]*\}/);
      if (match) return JSON.parse(match[0]);
      return JSON.parse(content);
    } catch (_) {
      return { content };
    }
  }

  async summarize(text: string, worker: AIWorker): Promise<string> {
    const { client, model } = this.getClient(worker);
    const response = await client.chat.completions.create({
      model,
      messages: [
        { role: "system", content: "Summarize the following text in 2-3 clear, factual sentences." },
        { role: "user", content: text },
      ],
      temperature: 0.3,
    });
    return response.choices[0]?.message?.content || text;
  }

  async rewrite(text: string, worker: AIWorker): Promise<string> {
    const { client, model } = this.getClient(worker);
    const response = await client.chat.completions.create({
      model,
      messages: [
        { role: "system", content: "Rewrite the following text into professional journalism style." },
        { role: "user", content: text },
      ],
      temperature: 0.3,
    });
    return response.choices[0]?.message?.content || text;
  }
}

import * as logger from "firebase-functions/logger";
import { BaseAIProvider } from "./base_provider";
import { AIWorker, DiscoveredArticle } from "../types/worker";

export class GeminiProvider extends BaseAIProvider {
  readonly name = "gemini";

  async discoverNews(
    categoryName: string,
    targetArticles: number,
    worker: AIWorker
  ): Promise<DiscoveredArticle[]> {
    const apiKey = worker.apiKey || process.env.GEMINI_API_KEY;
    if (!apiKey) {
      throw new Error(`Gemini API key missing for worker ${worker.workerId}`);
    }

    const model = worker.model || "gemini-1.5-flash";
    const url = `${worker.baseUrl || "https://generativelanguage.googleapis.com/v1beta"}/models/${model}:generateContent?key=${apiKey}`;

    const promptText = `
You are a real-time news discovery engine.
Discover latest breaking news stories for category: "${categoryName}".
Target Article Count: ${targetArticles} stories.

Output MUST be strictly valid JSON format matching:
{
  "articles": [
    {
      "title": "Headline",
      "source": "Publisher Name",
      "sourceUrl": "https://...",
      "publishedAt": "2026-07-26T12:00:00Z",
      "summary": "Factual 2-3 sentence summary"
    }
  ]
}
`;

    logger.info(`[GEMINI_PROVIDER] Worker="${worker.workerId}" Category="${categoryName}" Model="${model}"`);

    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: promptText }] }],
        generationConfig: {
          temperature: 0.3,
          responseMimeType: "application/json",
        },
      }),
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`Gemini API HTTP ${res.status}: ${errText}`);
    }

    const json = await res.json();
    const content = json.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!content) {
      throw new Error(`Gemini worker ${worker.workerId} returned empty content.`);
    }

    return this.parseNewsJson(content, categoryName);
  }
}

import * as logger from "firebase-functions/logger";
import { BaseAIProvider } from "./base_provider";
import { AIWorker, DiscoveredArticle } from "../types/worker";
import { EnvConfig } from "../config/env_config";

export class ClaudeProvider extends BaseAIProvider {
  readonly name = "claude";

  async discoverNews(
    categoryName: string,
    targetArticles: number,
    worker: AIWorker
  ): Promise<DiscoveredArticle[]> {
    const apiKey = worker.apiKey || EnvConfig.getApiKey("claude");
    if (!apiKey) {
      throw new Error(`Claude API key missing for worker ${worker.workerId}`);
    }

    const maskedKey = EnvConfig.maskSecret(apiKey);
    const model = worker.model || "claude-3-5-sonnet-20241022";

    const url = `${worker.baseUrl || "https://api.anthropic.com/v1"}/messages`;

    const promptText = `
You are an automated real-time news discovery engine. Discover breaking news for category: "${categoryName}".
Target Article Count: ${targetArticles} stories.
Return valid JSON only matching:
{
  "articles": [
    {
      "title": "Headline",
      "source": "Publisher Name",
      "sourceUrl": "https://...",
      "publishedAt": "2026-07-26T12:00:00Z",
      "summary": "Factual summary"
    }
  ]
}
`;

    logger.info(`[CLAUDE_PROVIDER] Worker="${worker.workerId}" Key="${maskedKey}" Category="${categoryName}" Model="${model}"`);

    const res = await fetch(url, {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model,
        max_tokens: 4000,
        messages: [{ role: "user", content: promptText }],
      }),
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`Claude API HTTP ${res.status}: ${errText}`);
    }

    const json = await res.json();
    const content = json.content?.[0]?.text;
    if (!content) {
      throw new Error(`Claude worker ${worker.workerId} returned empty content.`);
    }

    return this.parseNewsJson(content, categoryName);
  }
}

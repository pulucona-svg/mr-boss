import OpenAI from "openai";
import * as logger from "firebase-functions/logger";
import { BaseAIProvider } from "./base_provider";
import { AIWorker, DiscoveredArticle } from "../types/worker";

export class OpenAIProvider extends BaseAIProvider {
  readonly name = "openai";

  async discoverNews(
    categoryName: string,
    targetArticles: number,
    worker: AIWorker
  ): Promise<DiscoveredArticle[]> {
    const apiKey = worker.apiKey || process.env.OPENAI_API_KEY;
    if (!apiKey) {
      throw new Error(`OpenAI API key missing for worker ${worker.workerId}`);
    }

    const openai = new OpenAI({ apiKey, baseURL: worker.baseUrl });
    const model = worker.model || "gpt-4o";

    const systemPrompt =
      "You are an automated real-time news discovery engine. Your responsibility is to discover, extract, and return verified breaking news stories and major current events.";

    const isOpinionCategory = categoryName.toLowerCase().includes("opinion");

    const userPrompt = `
Discover latest breaking news stories for category: "${categoryName}".
Target Article Count: Approximately ${targetArticles} stories.

STRICT CRITERIA:
1. Search and source from reputable international, national, and regional news publishers.
2. Prioritize articles published within the last 24 hours.
3. Return approximately ${targetArticles} unique stories.
4. Strictly AVOID sponsored content, marketing material, advertisements, or promotional press releases.
5. ${isOpinionCategory ? "Include high quality opinion pieces." : "Strictly AVOID opinion pieces, editorials, or blog posts. Focus ONLY on objective factual reporting."}
6. Provide real, accurate, and non-duplicate news items.

Output format MUST be valid JSON:
{
  "articles": [
    {
      "title": "Headline of the article",
      "source": "Publisher or News Outlet Name",
      "sourceUrl": "Direct URL or canonical source link",
      "publishedAt": "ISO-8601 formatted date-time string (e.g. 2026-07-26T12:00:00Z)",
      "summary": "Clear, factual 2-3 sentence summary of the news story"
    }
  ]
}
`;

    logger.info(
      `[OPENAI_PROVIDER] Worker="${worker.workerId}" Category="${categoryName}" Model="${model}"`
    );

    const response = await openai.chat.completions.create({
      model,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      response_format: { type: "json_object" },
      temperature: 0.3,
    });

    const content = response.choices[0]?.message?.content;
    if (!content) {
      throw new Error(`OpenAI worker ${worker.workerId} returned empty response.`);
    }

    return this.parseNewsJson(content, categoryName);
  }
}

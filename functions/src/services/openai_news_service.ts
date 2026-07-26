import OpenAI from "openai";
import * as logger from "firebase-functions/logger";
import { DiscoveredArticle, ExploreConfig } from "../types/explore";
import { DuplicateDetector } from "./duplicate_detector";

export class OpenAiNewsService {
  /**
   * Asks OpenAI to discover real-time news stories for a specific category.
   */
  static async discoverNewsForCategory(
    categoryName: string,
    targetArticles: number,
    config: ExploreConfig
  ): Promise<DiscoveredArticle[]> {
    const apiKey = process.env.OPENAI_API_KEY || config.openAiApiKey;

    if (!apiKey) {
      throw new Error(
        "OpenAI API key is missing. Please set OPENAI_API_KEY in environment variables or system/exploreConfig."
      );
    }

    const openai = new OpenAI({ apiKey });
    const model = config.searchModel || "gpt-4o";

    const systemPrompt =
      "You are an automated real-time news discovery engine. Your responsibility is to discover, extract, and return verified breaking news stories and major current events.";

    const isOpinionCategory = categoryName.toLowerCase().includes("opinion");

    const userPrompt = `
Discover latest breaking news stories for the category: "${categoryName}".

Target Article Count: Approximately ${targetArticles} stories.

STRICT CRITERIA:
1. Search and source from reputable international, national, and regional news publishers.
2. Prioritize articles published within the last 24 hours.
3. Return approximately ${targetArticles} unique stories.
4. Strictly AVOID sponsored content, marketing material, advertisements, or promotional press releases.
5. ${isOpinionCategory ? "Include high quality opinion pieces." : "Strictly AVOID opinion pieces, editorials, or blog posts. Focus ONLY on objective factual reporting."}
6. Provide real, accurate, and non-duplicate news items.

Output format MUST be valid JSON matching this exact structure:
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
      `[OPENAI_SEARCH_REQUEST] Category="${categoryName}" targetArticles=${targetArticles} model="${model}"`
    );

    try {
      const response = await openai.chat.completions.create({
        model: model,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        response_format: { type: "json_object" },
        temperature: 0.3,
      });

      const content = response.choices[0]?.message?.content;
      if (!content) {
        throw new Error("OpenAI returned empty response content.");
      }

      const parsed = JSON.parse(content);
      const rawArticles = Array.isArray(parsed.articles)
        ? parsed.articles
        : Array.isArray(parsed)
        ? parsed
        : [];

      const validatedArticles: DiscoveredArticle[] = [];
      const nowIso = new Date().toISOString();

      for (const item of rawArticles) {
        if (!item || typeof item !== "object") continue;

        const title = typeof item.title === "string" ? item.title.trim() : "";
        const source = typeof item.source === "string" ? item.source.trim() : "News Source";
        const sourceUrl = typeof item.sourceUrl === "string" ? item.sourceUrl.trim() : "";
        const summary = typeof item.summary === "string" ? item.summary.trim() : "";
        let publishedAt = typeof item.publishedAt === "string" ? item.publishedAt.trim() : nowIso;

        if (!publishedAt || isNaN(Date.parse(publishedAt))) {
          publishedAt = nowIso;
        }

        if (title && summary) {
          const articleHash = DuplicateDetector.generateArticleHash(title, source);
          const clusterId = DuplicateDetector.generateClusterId(articleHash);

          validatedArticles.push({
            clusterId,
            title,
            source,
            sourceUrl: sourceUrl || "https://news.google.com",
            publishedAt,
            summary,
            category: categoryName,
          });
        }
      }

      logger.info(
        `[OPENAI_SEARCH_RESPONSE] Category="${categoryName}" Stories returned=${rawArticles.length} Validated=${validatedArticles.length}`
      );

      return validatedArticles;
    } catch (err: any) {
      logger.error(`[OPENAI_SEARCH_ERROR] Failed news discovery for category "${categoryName}":`, err);
      throw err;
    }
  }
}

import { IAIProvider, AIWorker, DiscoveredArticle, JobExecutionResult } from "../types/worker";
import { DuplicateDetector } from "../services/duplicate_detector";

export abstract class BaseAIProvider implements IAIProvider {
  abstract readonly name: string;

  abstract discoverNews(
    categoryName: string,
    targetArticles: number,
    worker: AIWorker
  ): Promise<DiscoveredArticle[]>;

  async publishArticle(job: any, worker: AIWorker): Promise<JobExecutionResult> {
    return {
      success: false,
      error: `Publishing not implemented for provider ${this.name} yet (Phase 2 feature).`,
    };
  }

  async generateMetadata(prompt: string, worker: AIWorker): Promise<any> {
    return { summary: "Metadata generation placeholder", tags: [] };
  }

  async healthCheck(worker: AIWorker): Promise<boolean> {
    try {
      const res = await this.discoverNews("General", 1, worker);
      return Array.isArray(res);
    } catch (_) {
      return false;
    }
  }

  async estimateCost(tokens: number, worker: AIWorker): Promise<number> {
    return (tokens / 1000) * 0.002;
  }

  supportsFeature(feature: string): boolean {
    const supported = ["discovery", "metadata", "healthcheck"];
    return supported.includes(feature.toLowerCase());
  }

  protected parseNewsJson(content: string, categoryName: string): DiscoveredArticle[] {
    let cleanContent = content.trim();
    if (cleanContent.startsWith("```json")) {
      cleanContent = cleanContent.replace(/^```json/, "").replace(/```$/, "").trim();
    } else if (cleanContent.startsWith("```")) {
      cleanContent = cleanContent.replace(/^```/, "").replace(/```$/, "").trim();
    }

    const parsed = JSON.parse(cleanContent);
    const rawArticles = Array.isArray(parsed.articles)
      ? parsed.articles
      : Array.isArray(parsed)
      ? parsed
      : [];

    const validated: DiscoveredArticle[] = [];
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

        validated.push({
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
    return validated;
  }
}

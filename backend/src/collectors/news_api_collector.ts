import { BaseCollector } from './base_collector';
import { NewsApiArticle, NewsApiResponse } from '../models/news_article.model';
import { Logger } from '../utils/logger';

export class NewsApiCollector implements BaseCollector<NewsApiArticle> {
  public readonly name = 'NewsAPI.org';
  private readonly apiKey: string;
  private readonly baseUrl = 'https://newsapi.org/v2';

  constructor(apiKey: string) {
    this.apiKey = apiKey;
  }

  public async fetchArticles(query: string = 'Kenya OR Africa OR Technology OR Sports OR Business OR Politics'): Promise<NewsApiArticle[]> {
    if (!this.apiKey) {
      Logger.warn(`[${this.name}] API key is missing or empty. Skipping fetch.`);
      return [];
    }

    try {
      const url = `${this.baseUrl}/everything?q=${encodeURIComponent(query)}&sortBy=publishedAt&pageSize=100&language=en`;
      Logger.info(`[${this.name}] Fetching news with query: "${query}"`);

      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'X-Api-Key': this.apiKey,
          'User-Agent': 'MirrorLaikipia-NewsCollector/1.0',
        },
      });

      if (!response.ok) {
        throw new Error(`HTTP Error ${response.status}: ${response.statusText}`);
      }

      const data = (await response.json()) as NewsApiResponse;
      if (data.status !== 'ok' || !Array.isArray(data.articles)) {
        throw new Error(`API returned non-ok status: ${data.status}`);
      }

      Logger.info(`[${this.name}] Successfully fetched ${data.articles.length} raw articles.`);
      return data.articles;
    } catch (error: any) {
      Logger.error(`[${this.name}] Failed to fetch news articles:`, error.message || error);
      // Fail-safe: return empty array so other collectors can proceed
      return [];
    }
  }
}

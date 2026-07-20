import { BaseCollector } from './base_collector';
import { NewsDataArticle, NewsDataResponse } from '../models/news_article.model';
import { Logger } from '../utils/logger';

export class NewsDataCollector implements BaseCollector<NewsDataArticle> {
  public readonly name = 'NewsData.io';
  private readonly apiKey: string;
  private readonly baseUrl = 'https://newsdata.io/api/1/news';

  constructor(apiKey: string) {
    this.apiKey = apiKey;
  }

  public async fetchArticles(query: string = 'Kenya'): Promise<NewsDataArticle[]> {
    if (!this.apiKey) {
      Logger.warn(`[${this.name}] API key is missing or empty. Skipping fetch.`);
      return [];
    }

    try {
      const url = `${this.baseUrl}?apikey=${encodeURIComponent(this.apiKey)}&q=${encodeURIComponent(query)}&language=en`;
      Logger.info(`[${this.name}] Fetching news with query: "${query}"`);

      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'User-Agent': 'MirrorLaikipia-NewsCollector/1.0',
        },
      });

      if (!response.ok) {
        throw new Error(`HTTP Error ${response.status}: ${response.statusText}`);
      }

      const data = (await response.json()) as NewsDataResponse;
      if (data.status !== 'success' || !Array.isArray(data.results)) {
        throw new Error(`API returned non-success status: ${data.status}`);
      }

      Logger.info(`[${this.name}] Successfully fetched ${data.results.length} raw articles.`);
      return data.results;
    } catch (error: any) {
      Logger.error(`[${this.name}] Failed to fetch news articles:`, error.message || error);
      // Fail-safe: return empty array so other collectors can proceed
      return [];
    }
  }
}

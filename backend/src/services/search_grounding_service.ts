import { Logger } from '../utils/logger';

export interface GroundedResearchItem {
  headline: string;
  summary: string;
  publication: string;
  source: string;
  publishedDate: string;
  url: string;
}

export interface GroundedResearchResult {
  query: string;
  items: GroundedResearchItem[];
  sourcesUsed: string[];
  durationMs: number;
}

export class SearchGroundingService {
  private static readonly TRUSTED_DOMAINS = [
    'bbc.com',
    'bbc.co.uk',
    'cnn.com',
    'aljazeera.com',
    'reuters.com',
    'apnews.com',
    'theguardian.com',
    'nytimes.com',
    'who.int',
    'un.org',
    'nasa.gov',
    'gov.ke',
    'gov.uk',
    'gov',
    'wikipedia.org',
    'standardmedia.co.ke',
    'nation.africa',
    'the-star.co.ke',
    'capitalfm.co.ke',
  ];

  private static readonly BLOCKED_DOMAINS = [
    'reddit.com',
    'medium.com',
    'blogspot.com',
    'wordpress.com',
    'quora.com',
    'buzzfeed.com',
    'facebook.com',
    'twitter.com',
    'x.com',
    'tiktok.com',
    'pinterest.com',
  ];

  /**
   * Performs trusted search grounding to gather factual context from verified high-authority sources.
   */
  public static async performGroundingSearch(
    title: string,
    category: string,
    keywords: string[] = [],
    region: string = 'Kenya'
  ): Promise<GroundedResearchResult> {
    const startTime = Date.now();
    const cleanTitle = title.replaceAll(/[^\w\s]/g, '').trim();
    const query = `${cleanTitle} ${category} ${region}`.trim();

    Logger.info(`[GROUNDING_START] Initiating trusted search grounding for query: "${query}"`);

    const items: GroundedResearchItem[] = [];
    const sourcesSet = new Set<string>();

    try {
      // 1. Fetch search context from Wikipedia REST API for trusted encyclopedic/background facts
      const wikiItems = await SearchGroundingService.fetchWikipediaSearch(cleanTitle);
      for (const item of wikiItems) {
        items.push(item);
        sourcesSet.add(item.publication);
      }

      // 2. Fetch context from DuckDuckGo / Public News Search API
      const searchItems = await SearchGroundingService.fetchPublicNewsSearch(query);
      for (const item of searchItems) {
        if (SearchGroundingService.isTrustedSource(item.url)) {
          items.push(item);
          sourcesSet.add(item.publication);
        }
      }
    } catch (err: any) {
      Logger.warn(`[GROUNDING_WARN] Grounding search note: ${err.message || err}`);
    }

    const durationMs = Date.now() - startTime;
    const sourcesUsed = Array.from(sourcesSet);

    Logger.info(
      `[GROUNDING_COMPLETE] Gathered ${items.length} grounded research items from ${sourcesUsed.length} trusted sources (${sourcesUsed.join(', ') || 'Wikipedia/Public Feeds'}) in ${durationMs}ms.`
    );

    return {
      query,
      items: items.slice(0, 5), // Keep top 5 verified research items
      sourcesUsed,
      durationMs,
    };
  }

  private static isTrustedSource(url: string): boolean {
    if (!url) return false;
    const lowerUrl = url.toLowerCase();

    // Reject blocked domains
    if (SearchGroundingService.BLOCKED_DOMAINS.some((b) => lowerUrl.includes(b))) {
      return false;
    }

    // Check trusted domains or .gov TLDs
    return (
      SearchGroundingService.TRUSTED_DOMAINS.some((t) => lowerUrl.includes(t)) ||
      lowerUrl.includes('.gov')
    );
  }

  private static async fetchWikipediaSearch(cleanTitle: string): Promise<GroundedResearchItem[]> {
    const results: GroundedResearchItem[] = [];
    const searchTerms = cleanTitle.split(/\s+/).slice(0, 4).join(' ');
    const url = `https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=${encodeURIComponent(
      searchTerms
    )}&utf8=&format=json&origin=*`;

    try {
      const response = await fetch(url, {
        headers: {
          'User-Agent': 'MirrorLaikipia-NewsBackend/1.0 (https://mirrorlaikipia.com)',
        },
      });

      if (!response.ok) return results;

      const data = (await response.json()) as any;
      if (data?.query?.search && Array.isArray(data.query.search)) {
        for (const item of data.query.search.slice(0, 2)) {
          const cleanSnippet = (item.snippet || '')
            .replaceAll(/<[^>]*>/g, '')
            .replaceAll(/&quot;/g, '"')
            .trim();

          if (cleanSnippet.length > 30) {
            results.push({
              headline: item.title || searchTerms,
              summary: cleanSnippet,
              publication: 'Wikipedia Reference',
              source: 'Wikipedia',
              publishedDate: new Date().toISOString(),
              url: `https://en.wikipedia.org/wiki/${encodeURIComponent(item.title)}`,
            });
          }
        }
      }
    } catch (e) {
      /* ignore */
    }

    return results;
  }

  private static async fetchPublicNewsSearch(query: string): Promise<GroundedResearchItem[]> {
    const results: GroundedResearchItem[] = [];
    const url = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`;

    try {
      const response = await fetch(url, {
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      });

      if (!response.ok) return results;

      const html = await response.text();
      // Match result snippets from DuckDuckGo HTML
      const snippetRegex = /<a class="result__url" href="([^"]+)".*?>\s*(.*?)\s*<\/a>[\s\S]*?<a class="result__snippet".*?>\s*(.*?)\s*<\/a>/gi;
      let match: RegExpExecArray | null;
      let count = 0;

      while ((match = snippetRegex.exec(html)) !== null && count < 3) {
        const link = match[1];
        const rawTitle = match[2].replaceAll(/<[^>]*>/g, '').trim();
        const snippet = match[3].replaceAll(/<[^>]*>/g, '').trim();

        if (link && snippet.length > 20) {
          const pubName = SearchGroundingService.extractDomainName(link);
          results.push({
            headline: rawTitle || query,
            summary: snippet,
            publication: pubName,
            source: pubName,
            publishedDate: new Date().toISOString(),
            url: link,
          });
          count++;
        }
      }
    } catch (e) {
      /* ignore */
    }

    return results;
  }

  private static extractDomainName(url: string): string {
    try {
      const parsed = new URL(url);
      let host = parsed.hostname.replace(/^www\./i, '');
      return host.charAt(0).toUpperCase() + host.slice(1);
    } catch {
      return 'Trusted Publisher';
    }
  }
}

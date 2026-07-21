import { NormalizedNews } from '../models/news_article.model';
import { Logger } from '../utils/logger';

export interface GeminiMagazineOutput {
  headline: string;
  summary: string;
  article: string;
  background: string;
  analysis: string;
  whyItMatters: string;
  whatNext: string;
}

export class GeminiService {
  private static readonly MAX_RETRIES = 3;
  private static readonly INITIAL_BACKOFF_MS = 1000;
  private static readonly TIMEOUT_MS = 20000;

  /**
   * Enriches a classified news article into an AI-powered magazine article using Google's Gemini API.
   * If Gemini is unavailable, times out, or fails after retries, returns the original article intact.
   */
  public static async generateMagazineArticle(
    article: NormalizedNews
  ): Promise<NormalizedNews> {
    // 1. Performance check: Never process already enriched articles
    if (article.aiGenerated === true) {
      Logger.info(`[GEMINI] Article ID ${article.id} is already AI-generated. Skipping regeneration.`);
      return article;
    }

    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey || apiKey.trim().length === 0) {
      Logger.warn(
        `[GEMINI_WARN] GEMINI_API_KEY is missing in process.env. Skipping AI enrichment for article ID ${article.id}.`
      );
      return article;
    }

    const startTime = Date.now();
    Logger.info(`[GEMINI_START] Starting Gemini AI enrichment for article ID: ${article.id} ("${article.title}")`);

    const prompt = GeminiService.buildPrompt(article);

    let attempt = 0;
    let delayMs = GeminiService.INITIAL_BACKOFF_MS;

    while (attempt < GeminiService.MAX_RETRIES) {
      attempt++;
      try {
        const result = await GeminiService.callGeminiApi(prompt, apiKey.trim());
        const durationMs = Date.now() - startTime;

        Logger.info(`[GEMINI_COMPLETE] Successfully enriched article ID ${article.id} in ${durationMs}ms (Attempt ${attempt}).`);
        if (result.tokenUsage) {
          Logger.info(
            `[GEMINI_TOKENS] Token usage for ${article.id} - Prompt: ${result.tokenUsage.promptTokens}, Candidates: ${result.tokenUsage.candidatesTokens}, Total: ${result.tokenUsage.totalTokens}`
          );
        }

        const parsed = result.output;

        return {
          ...article,
          headline: parsed.headline || article.title,
          summary: parsed.summary || article.summary,
          editorialSummary: parsed.summary || article.editorialSummary || article.summary,
          content: parsed.article || article.content,
          article: parsed.article || article.content,
          background: parsed.background || '',
          analysis: parsed.analysis || '',
          whyItMatters: parsed.whyItMatters || '',
          whatNext: parsed.whatNext || '',
          aiGenerated: true,
        };
      } catch (err: any) {
        const errorMsg = err.message || String(err);
        const isAuthError = errorMsg.includes('400') || errorMsg.includes('403') || errorMsg.includes('API key');

        Logger.warn(
          `[GEMINI_RETRY] Attempt ${attempt}/${GeminiService.MAX_RETRIES} failed for article ${article.id}: ${errorMsg}`
        );

        if (isAuthError || attempt >= GeminiService.MAX_RETRIES) {
          Logger.error(
            `[GEMINI_FAIL] Gemini enrichment failed for article ID ${article.id} (${isAuthError ? 'Authentication / API Key Error' : `after ${attempt} attempts`}): ${errorMsg}. Falling back to original article.`
          );
          return article;
        }

        await GeminiService.delay(delayMs);
        delayMs *= 2; // Exponential backoff
      }
    }

    return article;
  }

  private static buildPrompt(article: NormalizedNews): string {
    return `You are an elite, award-winning international magazine journalist and senior editor writing for a high-end digital publication.

CRITICAL INSTRUCTIONS:
1. Preserve absolute factual accuracy based on the source material provided below.
2. NEVER fabricate facts, invent quotes, or create false statistics.
3. NEVER copy copyrighted wording verbatim; rewrite with original, elegant editorial prose.
4. Expand on the core facts using well-established public context, background knowledge, and expert analysis.
5. Explain the historical or strategic background clearly.
6. Explain why this story matters to readers, stakeholders, and the broader region.
7. Outline likely future consequences, developments, or next steps ("What Next").
8. Write in an engaging, sophisticated magazine style, producing between 300 and 500 words total across all section fields.
9. Use natural, highly readable paragraphs that hook the reader immediately while maintaining a neutral, authoritative journalistic tone.

SOURCE MATERIAL:
- Title: "${article.title}"
- Category: "${article.category}"
- Region: "${article.regionPriority}"
- Source Publisher: "${article.sourceName}"
- Summary: "${article.summary}"
- Existing Content / Details: "${article.content || article.editorialSummary || article.summary}"

OUTPUT REQUIREMENT:
Return STRICT JSON ONLY. Do NOT use markdown code fences (no \`\`\`json). Do NOT include HTML tags. Return a single JSON object matching this exact schema:

{
  "headline": "A captivating, magazine-style headline for the article",
  "summary": "A polished 2-sentence executive summary hooking the reader",
  "article": "The main feature story written in elegant, engaging magazine prose (2 to 3 paragraphs)",
  "background": "Historical context, strategic backdrop, or key factors leading up to this development",
  "analysis": "In-depth expert analysis explaining the broader economic, social, or policy implications",
  "whyItMatters": "Clear breakdown of why this event is significant for readers and regional stakeholders",
  "whatNext": "Forward-looking assessment of anticipated upcoming actions, key decisions, or developments"
}`;
  }

  private static async callGeminiApi(
    prompt: string,
    apiKey: string
  ): Promise<{
    output: GeminiMagazineOutput;
    tokenUsage?: { promptTokens: number; candidatesTokens: number; totalTokens: number };
  }> {
    // Supported Gemini models hierarchy
    const models = ['gemini-2.5-flash', 'gemini-2.0-flash', 'gemini-1.5-flash', 'gemini-1.5-pro'];
    let lastError: Error | null = null;

    for (const model of models) {
      const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), GeminiService.TIMEOUT_MS);

      try {
        const response = await fetch(endpoint, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            contents: [
              {
                parts: [
                  {
                    text: prompt,
                  },
                ],
              },
            ],
            generationConfig: {
              responseMimeType: 'application/json',
              temperature: 0.3,
              maxOutputTokens: 2048,
            },
          }),
          signal: controller.signal,
        });

        clearTimeout(timeoutId);

        if (!response.ok) {
          const errText = await response.text().catch(() => '');
          throw new Error(`HTTP Error ${response.status} (${response.statusText}): ${errText}`);
        }

        const data = (await response.json()) as any;
        const candidate = data?.candidates?.[0];

        if (!candidate || !candidate.content?.parts?.[0]?.text) {
          throw new Error('Gemini API returned empty candidate response.');
        }

        const rawText = candidate.content.parts[0].text as string;
        const parsedOutput = GeminiService.parseJsonText(rawText);

        const tokenUsage = data?.usageMetadata
          ? {
              promptTokens: data.usageMetadata.promptTokenCount || 0,
              candidatesTokens: data.usageMetadata.candidatesTokenCount || 0,
              totalTokens: data.usageMetadata.totalTokenCount || 0,
            }
          : undefined;

        return { output: parsedOutput, tokenUsage };
      } catch (err: any) {
        clearTimeout(timeoutId);
        lastError = err;
        // If 404 model not found, try next model immediately
        if (err.message && err.message.includes('404')) {
          continue;
        }
        throw err;
      }
    }

    throw lastError || new Error('All Gemini model endpoints failed.');
  }

  private static parseJsonText(rawText: string): GeminiMagazineOutput {
    let cleanText = rawText.trim();

    // Strip markdown code fences if present
    if (cleanText.startsWith('```')) {
      cleanText = cleanText.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '');
    }

    const json = JSON.parse(cleanText);

    return {
      headline: String(json.headline || '').trim(),
      summary: String(json.summary || '').trim(),
      article: String(json.article || '').trim(),
      background: String(json.background || '').trim(),
      analysis: String(json.analysis || '').trim(),
      whyItMatters: String(json.whyItMatters || '').trim(),
      whatNext: String(json.whatNext || '').trim(),
    };
  }

  private static delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}

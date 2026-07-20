import { NormalizedNews, StoryCluster } from '../models/news_article.model';
import {
  ArticleViewerDocument,
  RelatedArticleSummary,
  ViewerContentBlock,
  ViewerImageItem,
  ViewerSection,
} from '../models/magazine_viewer.model';

export class ViewerDocumentBuilder {
  /**
   * Generates a complete ArticleViewerDocument ready to be stored on ImageKit as JSON.
   */
  public static buildViewerDocument(
    article: NormalizedNews,
    imageKitUrl: string,
    cluster?: StoryCluster
  ): ArticleViewerDocument {
    const rawParagraphs = article.content
      .split(/\n\n|\r\n\r\n/)
      .map((p) => p.trim())
      .filter((p) => p.length > 0);

    const paragraphs =
      rawParagraphs.length > 0 ? rawParagraphs : [article.editorialSummary || article.summary];

    // Images list
    const images: ViewerImageItem[] = [
      {
        url: imageKitUrl || article.imageUrl,
        caption: `Photo: ${article.sourceName} / ${article.title}`,
      },
    ];

    // Build structured Content Blocks (paragraphs & images positioned between paragraphs)
    const contentBlocks: ViewerContentBlock[] = [];

    // Lead paragraph
    contentBlocks.push({
      type: 'paragraph',
      text: article.editorialSummary || article.summary,
    });

    // Cover image positioned after lead paragraph
    contentBlocks.push({
      type: 'image',
      url: imageKitUrl || article.imageUrl,
      caption: `Photo: ${article.sourceName} / ${article.title}`,
    });

    contentBlocks.push({
      type: 'heading',
      level: 1,
      text: 'Full Story & Coverage',
    });

    // Paragraphs interspaced
    paragraphs.forEach((p, idx) => {
      contentBlocks.push({
        type: 'paragraph',
        text: p,
      });

      // Insert section divider or secondary heading if multiple paragraphs
      if (idx === 1 && paragraphs.length > 2) {
        contentBlocks.push({
          type: 'heading',
          level: 2,
          text: 'Key Context & Background',
        });
      }
    });

    // Build Sections
    const sections: ViewerSection[] = [
      {
        heading: "What's New?",
        paragraphs: [article.editorialSummary || article.summary],
      },
      {
        heading: 'Key Impact & Context',
        paragraphs: [
          `This ${article.category} report was published by ${article.sourceName} with regional priority on ${article.regionPriority}.`,
        ],
      },
      {
        heading: 'Detailed Coverage',
        paragraphs: paragraphs,
      },
    ];

    // Related Articles from Story Cluster
    const relatedArticles: RelatedArticleSummary[] = [];
    if (cluster && cluster.relatedArticles.length > 0) {
      cluster.relatedArticles.forEach((r) => {
        relatedArticles.push({
          id: r.id,
          title: r.title,
          source: r.sourceName,
          category: r.category,
          imageUrl: r.imageUrl,
        });
      });
    }

    const subtitleText = `Category: ${article.category} | Region: ${article.regionPriority}`;
    const subtitlesList = [
      subtitleText,
      `Published by ${article.sourceName} • ${article.readingTime || 2} min read`,
    ];

    const nowIso = new Date().toISOString();

    return {
      articleId: article.id,
      title: article.title,
      subtitle: subtitleText,
      subtitles: subtitlesList,
      category: article.category,
      secondaryCategories: article.secondaryCategories || [],
      source: article.sourceName,
      author: article.author,
      publishedAt: article.publishedAt,
      readingTime: article.readingTime || 2,
      editorialSummary: article.editorialSummary || article.summary,
      fullStory: article.content || article.summary,
      paragraphs,
      content: contentBlocks,
      images,
      sections,
      relatedArticles,
      keywords: article.keywords || [],
      isTopStory: article.isTopStory || false,
      isTrending: article.isTrending || false,
      qualityScore: article.qualityScore || 0,
      importanceScore: article.importanceScore || 0,
      expiresAt: article.expiresAt,
      originalSourceUrl: article.sourceUrl,
      generatedAt: nowIso,
    };
  }
}

import { NormalizationService } from './services/normalization_service';
import { DeduplicationService } from './services/deduplication_service';
import { QualityFilterService } from './services/quality_filter_service';
import { Logger } from './utils/logger';
import { NewsApiArticle, NewsDataArticle, NormalizedNews } from './models/news_article.model';

async function testPipeline() {
  Logger.logHeader('TESTING INTELLIGENT NEWS PIPELINE ALGORITHMS');

  const sampleNewsApiArticles: NewsApiArticle[] = [
    // High quality Kenya Education + Tech story
    {
      source: { id: 'daily-nation', name: 'Daily Nation' },
      author: 'John Doe',
      title: 'AI Introduced in Kenyan Universities to Boost Tech Education',
      description: 'Kenyan universities are introducing artificial intelligence curricula across Nairobi campuses to prepare students for tech careers.',
      url: 'https://nation.africa/kenya/news/ai-introduced-in-kenyan-universities-12345',
      urlToImage: 'https://nation.africa/images/ai-education-kenya.jpg',
      publishedAt: new Date(Date.now() - 3600 * 1000 * 2).toISOString(), // 2 hrs ago
      content: 'Kenyan universities have today announced full adoption of AI and machine learning courses.',
    },
    // Duplicate story from another outlet with slightly different title (lower score)
    {
      source: { id: 'the-star', name: 'The Star Kenya' },
      author: 'Jane Smith',
      title: 'Kenyan Universities Introduce AI to Boost Technology Education',
      description: 'Kenyan higher education institutions adopt artificial intelligence tools in Nairobi.',
      url: 'https://the-star.co.ke/news/2026-07-20-kenyan-universities-ai',
      urlToImage: 'https://the-star.co.ke/img/ai.png',
      publishedAt: new Date(Date.now() - 3600 * 1000 * 4).toISOString(), // 4 hrs ago
      content: 'Institutions across Kenya are introducing AI courses.',
    },
    // Low quality clickbait article (should be rejected)
    {
      source: { id: 'junk-news', name: 'Junk News' },
      author: 'Clickbaiter',
      title: 'YOU WON\'T BELIEVE WHAT HAPPENED IN NAIROBI TODAY!!!',
      description: 'Click here to find out the shocking truth about what happened.',
      url: 'https://junknews.com/clickbait',
      urlToImage: 'https://junknews.com/placeholder.jpg',
      publishedAt: new Date().toISOString(),
      content: 'Advertisement content removed.',
    },
    // Article with missing/placeholder image (should be rejected)
    {
      source: { id: 'fake-news', name: 'Fake News' },
      author: 'Unknown',
      title: 'Global Economy Reports Steady Growth in Q2 Financial Review',
      description: 'International financial markets record positive trends.',
      url: 'https://fakenews.com/economy',
      urlToImage: 'https://fakenews.com/default_image.png',
      publishedAt: new Date().toISOString(),
      content: 'Financial review details.',
    },
  ];

  const sampleNewsDataArticles: NewsDataArticle[] = [
    // Africa regional sports story
    {
      article_id: 'nd_1',
      title: 'Uganda and Kenya Prepare Joint Football Bid for Africa Cup of Nations',
      link: 'https://newsdata.io/article/1',
      description: 'East African nations Kenya and Uganda align sports infrastructure for major tournament.',
      content: 'East African nations prepare joint bid for AFCON.',
      pubDate: new Date(Date.now() - 3600 * 1000 * 5).toISOString(),
      image_url: 'https://images.unsplash.com/photo-1508098682722-e99c43a406b2',
      source_id: 'sports_africa',
      language: 'english',
    },
  ];

  const candidateArticles: NormalizedNews[] = [];
  let filteredIncomplete = 0;
  let filteredLowQuality = 0;

  for (const raw of sampleNewsApiArticles) {
    const norm = NormalizationService.normalizeNewsApiArticle(raw);
    if (norm) {
      candidateArticles.push(norm);
    } else {
      filteredLowQuality++;
    }
  }

  for (const raw of sampleNewsDataArticles) {
    const norm = NormalizationService.normalizeNewsDataArticle(raw);
    if (norm) {
      candidateArticles.push(norm);
    } else {
      filteredLowQuality++;
    }
  }

  const { uniqueArticles, duplicatesRemovedCount } = DeduplicationService.deduplicate(candidateArticles);

  Logger.info(`Candidate valid articles before deduplication: ${candidateArticles.length}`);
  Logger.info(`Duplicates intelligently removed: ${duplicatesRemovedCount}`);
  Logger.info(`Filtered low quality/clickbait/placeholder: ${filteredLowQuality}`);
  Logger.info(`Final Clean NormalizedNews count: ${uniqueArticles.length}`);

  console.log('\n--- SAMPLE CLEAN PIPELINE OUTPUT (NormalizedNews) ---');
  for (const art of uniqueArticles) {
    console.log({
      id: art.id,
      title: art.title,
      sourceName: art.sourceName,
      category: art.category,
      secondaryCategories: art.secondaryCategories,
      regionPriority: art.regionPriority,
      regionScore: art.regionScore,
      qualityScore: art.qualityScore,
      freshnessScore: art.freshnessScore,
      createdAt: art.createdAt,
      expiresAt: art.expiresAt,
    });
  }
}

testPipeline();

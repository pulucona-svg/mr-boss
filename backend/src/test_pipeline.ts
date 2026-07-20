import { NewsAggregatorService } from './services/news_aggregator_service';
import { NormalizationService } from './services/normalization_service';
import { DeduplicationService } from './services/deduplication_service';
import { RankingService } from './services/ranking_service';
import { ClusteringService } from './services/clustering_service';
import { Logger } from './utils/logger';
import { NewsApiArticle, NewsDataArticle, NormalizedNews, StoryCluster } from './models/news_article.model';

async function testEditorialEngine() {
  Logger.logHeader('TESTING EDITORIAL & RANKING ENGINE PIPELINE');

  const sampleNewsApiArticles: NewsApiArticle[] = [
    // 1. Kenya Government & Education Story (Publisher A)
    {
      source: { id: 'daily-nation', name: 'Daily Nation' },
      author: 'John Doe',
      title: 'State House Announces National AI Curriculum for All Kenyan Universities',
      description: 'The Government of Kenya has launched a nationwide artificial intelligence degree program across all public universities in Nairobi.',
      url: 'https://nation.africa/kenya/news/state-house-announces-ai-curriculum-1001',
      urlToImage: 'https://images.unsplash.com/photo-1516321318423-f06f85e504b3',
      publishedAt: new Date(Date.now() - 3600 * 1000 * 1).toISOString(), // 1 hr ago
      content: 'State House Nairobi has officially launched a nationwide AI degree program across public universities.',
    },
    // 2. Same story reported by Publisher B (Cluster match)
    {
      source: { id: 'the-star', name: 'The Star Kenya' },
      author: 'Jane Smith',
      title: 'Kenyan Universities Adopt National Artificial Intelligence Curriculum',
      description: 'Higher education institutions in Kenya adopt national AI degree program.',
      url: 'https://the-star.co.ke/news/2026-07-20-kenyan-universities-ai-curriculum',
      urlToImage: 'https://images.unsplash.com/photo-1522202176988-66273c2fd55f',
      publishedAt: new Date(Date.now() - 3600 * 1000 * 2).toISOString(),
      content: 'Kenyan universities are adopting AI curriculum.',
    },
    // 3. Breaking Emergency Disaster Alert
    {
      source: { id: 'capital-fm', name: 'Capital FM' },
      author: 'Alert Desk',
      title: 'BREAKING: Heavy Floods Trigger Emergency Evacuations in Tana River County',
      description: 'Emergency response teams have deployed boats as rising river levels flood villages in Tana River county.',
      url: 'https://capitalfm.co.ke/news/breaking-heavy-floods-tana-river-1002',
      urlToImage: 'https://images.unsplash.com/photo-1547683905-f686c993aae5',
      publishedAt: new Date(Date.now() - 3600 * 1000 * 0.5).toISOString(), // 30 mins ago
      content: 'Heavy flooding has forced hundreds of families to evacuate higher ground in Tana River.',
    },
    // 4. Technology Breakthrough Story
    {
      source: { id: 'techcrunch', name: 'TechCrunch' },
      author: 'Alex Wilhelm',
      title: 'Global Tech Breakthrough: Quantum Chip Achieves Record Processing Speeds',
      description: 'Scientists announce a major breakthrough in quantum computing architecture.',
      url: 'https://techcrunch.com/2026/07/20/quantum-chip-breakthrough',
      urlToImage: 'https://images.unsplash.com/photo-1518770660439-4636190af475',
      publishedAt: new Date(Date.now() - 3600 * 1000 * 5).toISOString(),
      content: 'Researchers have built a room-temperature quantum processor.',
    },
    // 5. Health Alert Story
    {
      source: { id: 'business-daily', name: 'Business Daily' },
      author: 'Mary Wanjiku',
      title: 'Ministry of Health Issues National Advisory on Cholera Outbreak',
      description: 'Health officials in Kenya urge strict sanitation standards across hospitals and food establishments.',
      url: 'https://businessdailyafrica.com/bd/news/moh-advisory-cholera-1003',
      urlToImage: 'https://images.unsplash.com/photo-1584515979956-d9f6e5d09982',
      publishedAt: new Date(Date.now() - 3600 * 1000 * 3).toISOString(),
      content: 'The Ministry of Health has released safety directives for all counties.',
    },
  ];

  const candidateArticles: NormalizedNews[] = [];

  for (const raw of sampleNewsApiArticles) {
    const norm = NormalizationService.normalizeNewsApiArticle(raw);
    if (norm) {
      candidateArticles.push(norm);
    }
  }

  // Calculate Importance Scores
  for (const art of candidateArticles) {
    art.importanceScore = RankingService.calculateImportanceScore(art);
  }

  // Story Clustering
  const clusters = ClusteringService.clusterArticles(candidateArticles);

  // Top Stories (Top 5)
  const topStories = RankingService.selectTopStories(candidateArticles);

  // Trending Topics (Top 10)
  const { trendingPackageTopics } = RankingService.detectTrending(candidateArticles, clusters);

  console.log('--- EDITORIAL ENGINE OUTPUT SUMMARY ---');
  console.log(`- Total Candidate Articles : ${candidateArticles.length}`);
  console.log(`- Total Clusters Formed    : ${clusters.length}`);
  console.log(`- Top Stories Selected     : ${topStories.length}`);
  console.log(`- Trending Topics Detected : ${trendingPackageTopics.length}`);

  console.log('\n--- TOP 5 TOP STORIES ---');
  topStories.forEach((art, i) => {
    console.log(`[#${i + 1}] Importance: ${art.importanceScore} | ${art.title} (${art.sourceName})`);
    console.log(`     Category: ${art.category} | Region: ${art.regionPriority} | ReadingTime: ${art.readingTime} min`);
    console.log(`     ExpiresAt: ${art.expiresAt}`);
    console.log(`     Keywords: ${art.keywords.join(', ')}`);
    console.log(`     Summary (${art.editorialSummary.split(' ').length} words): ${art.editorialSummary}`);
    console.log('---');
  });

  console.log('\n--- STORY CLUSTERS & MORE COVERAGE ---');
  clusters.forEach((cluster: StoryCluster) => {
    console.log(`Cluster ID: ${cluster.clusterId} | Size: ${cluster.clusterSize}`);
    console.log(`  Main Story: ${cluster.mainArticle.title} (${cluster.mainArticle.sourceName})`);
    if (cluster.relatedArticles.length > 0) {
      console.log(`  Related Coverage:`);
      cluster.relatedArticles.forEach((r: NormalizedNews) => {
        console.log(`    - ${r.title} (${r.sourceName})`);
      });
    }
  });
}

testEditorialEngine();

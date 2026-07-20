import { CollectionStats } from '../models/news_article.model';

export class Logger {
  private static formatTime(): string {
    return new Date().toISOString();
  }

  public static info(message: string, ...args: any[]): void {
    console.log(`[${Logger.formatTime()}] [INFO] ${message}`, ...args);
  }

  public static warn(message: string, ...args: any[]): void {
    console.warn(`[${Logger.formatTime()}] [WARN] ${message}`, ...args);
  }

  public static error(message: string, ...args: any[]): void {
    console.error(`[${Logger.formatTime()}] [ERROR] ${message}`, ...args);
  }

  public static logHeader(title: string): void {
    const border = '='.repeat(64);
    console.log(`\n${border}\n ${title}\n${border}`);
  }

  public static logSummary(stats: CollectionStats): void {
    Logger.logHeader('NEWS RANKING & EDITORIAL ENGINE SUMMARY');
    console.log(`- Articles received from NewsAPI  : ${stats.receivedFromNewsApi}`);
    console.log(`- Articles received from NewsData : ${stats.receivedFromNewsData}`);
    console.log(`- Total raw articles fetched      : ${stats.totalFetched}`);
    console.log(`- Articles filtered (incomplete)  : ${stats.filteredIncomplete}`);
    console.log(`- Articles filtered (low quality) : ${stats.filteredLowQuality}`);
    console.log(`- Duplicate articles removed      : ${stats.duplicatesRemoved}`);
    console.log(`- Final NormalizedNews produced   : ${stats.finalCount}`);
    console.log(`- Selected Top Stories (Max 5)    : ${stats.topStoriesCount}`);
    console.log(`- Detected Trending Topics (Top 10): ${stats.trendingCount}`);
    console.log(`- Total Story Clusters Formed     : ${stats.clustersCount}`);
    
    console.log('\n- Regional Priority Breakdown:');
    for (const [region, count] of Object.entries(stats.regionBreakdown)) {
      console.log(`    * ${region.padEnd(15)} : ${count}`);
    }

    console.log('\n- Category Breakdown:');
    for (const [cat, count] of Object.entries(stats.categoryBreakdown)) {
      if ((count as number) > 0) {
        console.log(`    * ${cat.padEnd(15)} : ${count}`);
      }
    }
    console.log('='.repeat(64) + '\n');
  }
}

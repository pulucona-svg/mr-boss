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
    const border = '='.repeat(60);
    console.log(`\n${border}\n ${title}\n${border}`);
  }

  public static logSummary(stats: any): void {
    Logger.logHeader('NEWS COLLECTION SUMMARY');
    console.log(`- Articles received from NewsAPI  : ${stats.receivedFromNewsApi}`);
    console.log(`- Articles received from NewsData : ${stats.receivedFromNewsData}`);
    console.log(`- Total raw articles fetched      : ${stats.totalFetched}`);
    console.log(`- Articles filtered (incomplete)  : ${stats.filteredIncomplete}`);
    console.log(`- Duplicate articles removed      : ${stats.duplicatesRemoved}`);
    console.log(`- Final clean articles produced   : ${stats.finalCount}`);
    console.log('- Category Breakdown:');
    for (const [cat, count] of Object.entries(stats.categoryBreakdown)) {
      if ((count as number) > 0) {
        console.log(`    * ${cat.padEnd(15)} : ${count}`);
      }
    }
    console.log('='.repeat(60) + '\n');
  }
}

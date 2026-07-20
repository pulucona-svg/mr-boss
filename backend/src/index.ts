import { NewsAggregatorService } from './services/news_aggregator_service';
import { NewsScheduler } from './scheduler/news_scheduler';
import { Logger } from './utils/logger';

async function main() {
  const aggregatorService = new NewsAggregatorService();
  const isRunOnce = process.argv.includes('--run-once');

  if (isRunOnce) {
    Logger.info('Running news collector once...');
    const result = await aggregatorService.collectAndProcess();
    Logger.info(`Run-once complete. ${result.articles.length} clean articles ready.`);
    process.exit(0);
  }

  // Automated 15-minute background scheduler
  const scheduler = new NewsScheduler(async () => {
    await aggregatorService.collectAndProcess();
  });

  scheduler.start();

  // Graceful shutdown listeners
  const shutdown = () => {
    Logger.info('Received shutdown signal. Stopping scheduler...');
    scheduler.stop();
    process.exit(0);
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((err) => {
  Logger.error('Fatal error in News Collector Service:', err);
  process.exit(1);
});

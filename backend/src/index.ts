import { SyncScheduler } from './scheduler/sync_scheduler';
import { NewsPublishingPipeline } from './services/news_publishing_pipeline';
import { Logger } from './utils/logger';

async function main() {
  const args = process.argv.slice(2);
  const isRunOnce = args.includes('--run-once');

  if (isRunOnce) {
    Logger.info('Running Mirror Laikipia News Publishing Pipeline in single-run mode...');
    const pipeline = new NewsPublishingPipeline();
    await pipeline.executePipeline();
    process.exit(0);
  } else {
    Logger.info('Starting Mirror Laikipia News Background Scheduler Daemon...');
    const scheduler = new SyncScheduler();
    scheduler.start();

    // Trigger immediate run on startup
    await scheduler.triggerImmediateRun();
  }
}

main().catch((error) => {
  Logger.error('Fatal error in News Collector & Publisher service:', error);
  process.exit(1);
});

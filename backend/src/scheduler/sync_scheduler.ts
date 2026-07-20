import cron from 'node-cron';
import { NewsPublishingPipeline } from '../services/news_publishing_pipeline';
import { Logger } from '../utils/logger';
import { config } from '../config/environment';

export class SyncScheduler {
  private pipeline: NewsPublishingPipeline;
  private task: cron.ScheduledTask | null = null;
  private isRunning: boolean = false;

  constructor() {
    this.pipeline = new NewsPublishingPipeline();
  }

  /**
   * Starts the 30-minute automated synchronization scheduler.
   */
  public start(): void {
    // Default to every 30 minutes if unspecified ('*/30 * * * *')
    const schedule = config.cronSchedule || '*/30 * * * *';
    Logger.logHeader(`INITIALIZING AUTOMATIC SYNCHRONIZATION SCHEDULER (${schedule})`);

    this.task = cron.schedule(schedule, async () => {
      if (this.isRunning) {
        Logger.warn('[SCHEDULER] Pipeline already executing. Skipping cron trigger.');
        return;
      }

      this.isRunning = true;
      try {
        Logger.info('[SCHEDULER] 30-minute sync timer triggered. Executing pipeline...');
        await this.pipeline.executePipeline();
        Logger.info('[SCHEDULER] Pipeline execution completed successfully.');
      } catch (error: any) {
        Logger.error('[SCHEDULER] Error during scheduled sync cycle:', error.message || error);
      } finally {
        this.isRunning = false;
      }
    });

    Logger.info(`[SCHEDULER] SyncScheduler active. Next run scheduled according to cron: "${schedule}"`);
  }

  /**
   * Triggers an immediate one-off synchronization run.
   */
  public async triggerImmediateRun(query?: string): Promise<void> {
    if (this.isRunning) {
      Logger.warn('[SCHEDULER] Synchronization pipeline is currently running. Request ignored.');
      return;
    }

    this.isRunning = true;
    try {
      Logger.info('[SCHEDULER] Triggering immediate synchronization run...');
      await this.pipeline.executePipeline(query);
    } catch (error: any) {
      Logger.error('[SCHEDULER] Error during manual sync trigger:', error.message || error);
    } finally {
      this.isRunning = false;
    }
  }

  /**
   * Stops the background scheduler task.
   */
  public stop(): void {
    if (this.task) {
      this.task.stop();
      Logger.info('[SCHEDULER] SyncScheduler stopped.');
    }
  }
}

// Alias NewsScheduler for backward compatibility
export const NewsScheduler = SyncScheduler;
export type NewsScheduler = SyncScheduler;

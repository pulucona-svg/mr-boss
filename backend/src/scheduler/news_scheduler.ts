import cron, { ScheduledTask } from 'node-cron';
import { Logger } from '../utils/logger';
import { config } from '../config/environment';

export type JobCallback = () => Promise<void>;

export class NewsScheduler {
  private cronSchedule: string;
  private task: ScheduledTask | null = null;
  private jobCallback: JobCallback;
  private isRunning = false;

  constructor(jobCallback: JobCallback, customCronSchedule?: string) {
    this.jobCallback = jobCallback;
    this.cronSchedule = customCronSchedule || config.cronSchedule;
  }

  /**
   * Starts the automated background scheduler
   */
  public start(): void {
    if (this.isRunning) {
      Logger.warn('Scheduler is already running.');
      return;
    }

    Logger.info(`Starting News Scheduler with cron pattern: "${this.cronSchedule}"`);

    // Execute immediately on startup
    this.executeJob();

    // Schedule recurring job
    this.task = cron.schedule(this.cronSchedule, () => {
      this.executeJob();
    });

    this.isRunning = true;
    Logger.info('News Scheduler initialized successfully.');
  }

  /**
   * Stops the background scheduler
   */
  public stop(): void {
    if (this.task) {
      this.task.stop();
      this.task = null;
      this.isRunning = false;
      Logger.info('News Scheduler stopped.');
    }
  }

  /**
   * Triggers a single manual execution of the job
   */
  public async executeJob(): Promise<void> {
    Logger.info('Executing scheduled news collection job...');
    try {
      await this.jobCallback();
    } catch (error: any) {
      Logger.error('Error occurred while executing scheduled news job:', error.message || error);
    }
  }
}

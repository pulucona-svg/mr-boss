import dotenv from 'dotenv';
import path from 'path';

// Load environment variables from .env file
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

export interface EnvironmentConfig {
  newsApiKey: string;
  newsDataApiKey: string;
  fetchIntervalMinutes: number;
  cronSchedule: string;
  defaultQuery: string;
  defaultExpiryHours: number;
  minDescriptionLength: number;
  minQualityScore: number;
}

export const config: EnvironmentConfig = {
  newsApiKey: process.env.NEWS_API_KEY || '',
  newsDataApiKey: process.env.NEWSDATA_API_KEY || '',
  fetchIntervalMinutes: parseInt(process.env.FETCH_INTERVAL_MINUTES || '15', 10),
  cronSchedule: process.env.CRON_SCHEDULE || '*/15 * * * *',
  defaultQuery: process.env.DEFAULT_QUERY || 'Kenya OR Africa',
  defaultExpiryHours: parseInt(process.env.DEFAULT_EXPIRY_HOURS || '24', 10),
  minDescriptionLength: parseInt(process.env.MIN_DESCRIPTION_LENGTH || '50', 10),
  minQualityScore: parseInt(process.env.MIN_QUALITY_SCORE || '30', 10),
};

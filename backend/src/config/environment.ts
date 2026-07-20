import dotenv from 'dotenv';
import path from 'path';

// Load environment variables from .env file
dotenv.config({ path: path.resolve(process.cwd(), '.env') });

export interface EnvironmentConfig {
  newsApiKey: string;
  newsDataApiKey: string;
  imagekitPublicKey: string;
  imagekitPrivateKey: string;
  imagekitUrlEndpoint: string;
  imagekitImageFolder: string;
  imagekitViewerFolder: string;
  firebaseProjectId: string;
  googleApplicationCredentials?: string;
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
  imagekitPublicKey: process.env.IMAGEKIT_PUBLIC_KEY || 'public_9d7+UUqP7VYTwGH6jX21WoqlV24=',
  imagekitPrivateKey: process.env.IMAGEKIT_PRIVATE_KEY || 'private_JqSyDrlIVskksrPc2IhCmg00E8Y=',
  imagekitUrlEndpoint: process.env.IMAGEKIT_URL_ENDPOINT || 'https://ik.imagekit.io/ubgbitinve',
  imagekitImageFolder: process.env.IMAGEKIT_IMAGE_FOLDER || '/mirror_laikipia/news/images/',
  imagekitViewerFolder: process.env.IMAGEKIT_VIEWER_FOLDER || '/mirror_laikipia/news/viewers/',
  firebaseProjectId: process.env.FIREBASE_PROJECT_ID || 'mirror-laikipia',
  googleApplicationCredentials: process.env.GOOGLE_APPLICATION_CREDENTIALS || undefined,
  fetchIntervalMinutes: parseInt(process.env.FETCH_INTERVAL_MINUTES || '15', 10),
  cronSchedule: process.env.CRON_SCHEDULE || '*/15 * * * *',
  defaultQuery: process.env.DEFAULT_QUERY || 'Kenya OR Africa',
  defaultExpiryHours: parseInt(process.env.DEFAULT_EXPIRY_HOURS || '24', 10),
  minDescriptionLength: parseInt(process.env.MIN_DESCRIPTION_LENGTH || '50', 10),
  minQualityScore: parseInt(process.env.MIN_QUALITY_SCORE || '30', 10),
};

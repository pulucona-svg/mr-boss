import { Timestamp } from "firebase-admin/firestore";

export type WorkerRole =
  | "DISCOVERY"
  | "WRITER"
  | "IMAGE"
  | "discovery"
  | "writer"
  | "publishing"
  | "image"
  | "any";

export type WorkerStatus = "idle" | "busy" | "cooldown" | "disabled";

export interface AIWorker {
  workerId: string;
  provider: string; // "openai" | "kimi" | "gemini" | "claude" | "grok" | "deepseek" | string
  model: string;
  apiKey: string;
  apiKeyReference?: string;
  baseUrl?: string;
  role: WorkerRole;
  supportsWebSearch: boolean;
  supportsImages: boolean;
  enabled: boolean;
  busy: boolean;
  priority: number; // 1 (highest) to 100
  status: WorkerStatus;
  currentJobId: string | null;
  requestsPerMinute: number;
  minuteLimit: number;
  dailyLimit: number;
  requestsToday: number;
  requestsThisMinute: number;
  remainingQuota: number;
  lastUsed: Timestamp | null;
  lastRequest: Timestamp | null;
  lastError: string | null;
  averageLatency: number; // in ms
  failureCount: number;
  successCount: number;
  successRate?: number;
  failureRate?: number;
  lastHeartbeat?: Timestamp | null;
  cooldownUntil: Timestamp | null;
}

export interface WorkersConfig {
  maxConcurrentWorkers: number;
  discoveryQueueThreshold: number;
  publisherQueueThreshold: number;
  retryLimit: number;
  cooldownMinutes: number;
  maxArticlesPerWorker: number;
  healthCheckInterval: number;
}

export interface DiscoveredArticle {
  clusterId: string;
  title: string;
  source: string;
  sourceUrl: string;
  publishedAt: string;
  summary: string;
  category?: string;
}

export interface JobExecutionResult {
  success: boolean;
  data?: any;
  error?: string;
  latencyMs?: number;
}

export interface IAIProvider {
  readonly name: string;
  discoverNews(
    categoryName: string,
    targetArticles: number,
    worker: AIWorker
  ): Promise<DiscoveredArticle[]>;
  publishArticle(job: any, worker: AIWorker): Promise<JobExecutionResult>;
  generateMetadata(prompt: string, worker: AIWorker): Promise<any>;
  healthCheck(worker: AIWorker): Promise<boolean>;
  estimateCost(tokens: number, worker: AIWorker): Promise<number>;
  supportsFeature(feature: string): boolean;
}

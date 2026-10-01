export interface MaterialMetadata {
  resourceId?: string;
  attemptCount?: number;
  title: string;
  description?: string;
  summary?: string;
  courseCode?: string;
  unitCode?: string;
  materialType?: string;
  type?: string;
  topic?: string;
  category?: string;
  targetPrograms?: string | string[];
}

export interface GeneratedThumbnailResult {
  imageBuffer: Buffer;
  mimeType: string;
  modelUsed: string;
}

export interface ThumbnailImageProvider {
  readonly name: string;
  readonly priority?: number;

  generateImage(
    prompt: string,
    metadata: MaterialMetadata
  ): Promise<GeneratedThumbnailResult>;
}

import ImageKit from 'imagekit';
import { ArticleViewerDocument, ImageKitUploadResult } from '../models/magazine_viewer.model';
import { Logger } from '../utils/logger';
import { config } from '../config/environment';

export class ImageKitUploadService {
  private static instance: ImageKit | null = null;

  private static getClient(): ImageKit | null {
    if (!ImageKitUploadService.instance) {
      if (!config.imagekitPrivateKey || !config.imagekitPublicKey) {
        Logger.warn('[ImageKitUploadService] Keys missing in env. Operating in simulated mode.');
        return null;
      }

      ImageKitUploadService.instance = new ImageKit({
        publicKey: config.imagekitPublicKey,
        privateKey: config.imagekitPrivateKey,
        urlEndpoint: config.imagekitUrlEndpoint,
      });
    }
    return ImageKitUploadService.instance;
  }

  /**
   * Downloads an external image and uploads it to ImageKit (/mirror_laikipia/news/images/).
   * Returns ImageKitUploadResult or null if download/upload fails (never publishes broken images).
   */
  public static async uploadArticleImage(
    imageUrl: string,
    articleId: string
  ): Promise<ImageKitUploadResult | null> {
    Logger.info(`[UPLOAD_IMAGE] Downloading & uploading cover image for article: ${articleId}`);

    const client = ImageKitUploadService.getClient();

    // Fallback simulation mode for environment testing
    if (!client) {
      Logger.warn(`[UPLOAD_IMAGE] ImageKit client unavailable. Simulating upload for ${articleId}`);
      return {
        fileId: `ik_img_${articleId}`,
        url: `${config.imagekitUrlEndpoint.replace(/\/$/, '')}${config.imagekitImageFolder}${articleId}.jpg`,
        size: 154200,
        width: 1200,
        height: 800,
        mimeType: 'image/jpeg',
      };
    }

    try {
      // 1. Download highest quality image into buffer
      const fetchResponse = await fetch(imageUrl, {
        headers: { 'User-Agent': 'MirrorLaikipia-NewsCollector/1.0' },
      });

      if (!fetchResponse.ok) {
        throw new Error(`HTTP ${fetchResponse.status} downloading external image`);
      }

      const arrayBuffer = await fetchResponse.arrayBuffer();
      const buffer = Buffer.from(arrayBuffer);

      if (buffer.length < 2000) {
        throw new Error('Downloaded buffer too small (< 2KB), likely broken image');
      }

      const fileName = `img_${articleId}.jpg`;

      // 2. Upload buffer to ImageKit
      const uploadResponse = await new Promise<any>((resolve, reject) => {
        client.upload(
          {
            file: buffer,
            fileName,
            folder: config.imagekitImageFolder,
            useUniqueFileName: false,
          },
          (err, result) => {
            if (err) reject(err);
            else resolve(result);
          }
        );
      });

      Logger.info(`[UPLOAD_IMAGE] Successfully uploaded image to ImageKit: ${uploadResponse.url}`);

      return {
        fileId: uploadResponse.fileId,
        url: uploadResponse.url,
        size: uploadResponse.size || buffer.length,
        width: uploadResponse.width || 1200,
        height: uploadResponse.height || 800,
        mimeType: uploadResponse.fileType || 'image/jpeg',
      };
    } catch (error: any) {
      Logger.error(`[UPLOAD_IMAGE] Image upload failed for article ${articleId}:`, error.message || error);
      return null; // Return null so article is safely skipped
    }
  }

  /**
   * Uploads Article Viewer JSON Document to ImageKit (/mirror_laikipia/news/viewers/).
   */
  public static async uploadViewerDocument(
    viewerDoc: ArticleViewerDocument
  ): Promise<ImageKitUploadResult | null> {
    Logger.info(`[UPLOAD_VIEWER] Uploading viewer JSON document to ImageKit for ID: ${viewerDoc.articleId}`);

    const client = ImageKitUploadService.getClient();
    const jsonString = JSON.stringify(viewerDoc, null, 2);
    const buffer = Buffer.from(jsonString, 'utf-8');
    const fileName = `viewer_${viewerDoc.articleId}.json`;

    if (!client) {
      Logger.warn(`[UPLOAD_VIEWER] ImageKit client unavailable. Simulating viewer upload for ${viewerDoc.articleId}`);
      return {
        fileId: `ik_doc_${viewerDoc.articleId}`,
        url: `${config.imagekitUrlEndpoint.replace(/\/$/, '')}${config.imagekitViewerFolder}${fileName}`,
        size: buffer.length,
      };
    }

    try {
      const uploadResponse = await new Promise<any>((resolve, reject) => {
        client.upload(
          {
            file: buffer,
            fileName,
            folder: config.imagekitViewerFolder,
            useUniqueFileName: false,
          },
          (err, result) => {
            if (err) reject(err);
            else resolve(result);
          }
        );
      });

      Logger.info(`[UPLOAD_VIEWER] Successfully uploaded viewer document: ${uploadResponse.url}`);

      return {
        fileId: uploadResponse.fileId,
        url: uploadResponse.url,
        size: uploadResponse.size || buffer.length,
      };
    } catch (error: any) {
      Logger.error(`[UPLOAD_VIEWER] Viewer document upload failed for ${viewerDoc.articleId}:`, error.message || error);
      return null;
    }
  }

  /**
   * Deletes a file from ImageKit by file ID.
   */
  public static async deleteFile(fileId: string): Promise<boolean> {
    if (!fileId) return true;
    Logger.info(`[CLEANUP / ROLLBACK] Deleting file from ImageKit: ${fileId}`);

    const client = ImageKitUploadService.getClient();
    if (!client) {
      Logger.info(`[CLEANUP] Simulated deletion of ImageKit file: ${fileId}`);
      return true;
    }

    try {
      await new Promise<void>((resolve, reject) => {
        client.deleteFile(fileId, (err) => {
          if (err) reject(err);
          else resolve();
        });
      });
      Logger.info(`[CLEANUP] Successfully deleted ImageKit file: ${fileId}`);
      return true;
    } catch (error: any) {
      Logger.error(`[CLEANUP] Failed to delete ImageKit file ${fileId}:`, error.message || error);
      return false;
    }
  }
}

import { ImageKitUploadService } from './imagekit_upload_service';
import { FirestorePublisher } from './firestore_publisher';
import { Logger } from '../utils/logger';

export interface CleanupStats {
  expiredFound: number;
  documentsDeleted: number;
  imagekitFilesDeleted: number;
  errors: number;
}

export class CleanupService {
  /**
   * Scans Firestore for expired news documents (expiresAt <= now)
   * and deletes associated ImageKit files and Firestore metadata documents.
   * Runs automatically before every synchronization cycle.
   */
  public static async executeCleanup(): Promise<CleanupStats> {
    Logger.logHeader('STARTING AUTOMATIC EXPIRATION CLEANUP ROUTINE');

    const nowIso = new Date().toISOString();
    const stats: CleanupStats = {
      expiredFound: 0,
      documentsDeleted: 0,
      imagekitFilesDeleted: 0,
      errors: 0,
    };

    try {
      const db = FirestorePublisher.getFirestore();

      if (!db) {
        Logger.info('[CLEANUP] Operating in simulation mode. 0 expired items.');
        return stats;
      }

      // Query latestNews where expiresAt <= nowIso
      const snapshot = await db
        .collection('latestNews')
        .where('expiresAt', '<=', nowIso)
        .get();

      stats.expiredFound = snapshot.size;
      Logger.info(`[CLEANUP] Found ${stats.expiredFound} expired article documents in Firestore.`);

      for (const doc of snapshot.docs) {
        const data = doc.data();
        const articleId = doc.id;
        const category = data.category;
        const imageKitFileId = data.imageKitFileId;
        const viewerDocumentId = data.viewerDocumentId;

        Logger.info(`[CLEANUP] Deleting expired article assets & metadata for ID: ${articleId}`);

        try {
          // 1. Delete ImageKit Cover Image
          if (imageKitFileId) {
            const imgDeleted = await ImageKitUploadService.deleteFile(imageKitFileId);
            if (imgDeleted) stats.imagekitFilesDeleted++;
          }

          // 2. Delete ImageKit Viewer JSON Document
          if (viewerDocumentId && viewerDocumentId !== imageKitFileId) {
            const docDeleted = await ImageKitUploadService.deleteFile(viewerDocumentId);
            if (docDeleted) stats.imagekitFilesDeleted++;
          }

          // 3. Delete Firestore Document across all collections
          const fsDeleted = await FirestorePublisher.deleteArticleDocument(articleId, category);
          if (fsDeleted) stats.documentsDeleted++;
        } catch (err: any) {
          Logger.error(`[CLEANUP] Error cleaning expired article ${articleId}:`, err.message || err);
          stats.errors++;
        }
      }

      Logger.info(
        `[CLEANUP] Cleanup complete. Deleted ${stats.documentsDeleted} Firestore docs & ${stats.imagekitFilesDeleted} ImageKit files.`
      );
    } catch (error: any) {
      Logger.warn('[CLEANUP] Cleanup note:', error.message || error);
    }

    return stats;
  }
}

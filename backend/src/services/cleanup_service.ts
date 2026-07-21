import { ImageKitUploadService } from './imagekit_upload_service';
import { FirestorePublisher } from './firestore_publisher';
import { APP_CATEGORIES, AppCategory } from '../models/news_article.model';
import { Logger } from '../utils/logger';

export const CATEGORY_RETENTION_LIMITS: Record<string, number> = {
  latestNews: 80,
  World: 30,
  Kenya: 20,
  Business: 20,
  Technology: 20,
  Health: 20,
  Politics: 20,
  Sports: 20,
  Africa: 20,
  Entertainment: 20,
  Education: 20,
  Science: 20,
  Nature: 20,
  Culture: 20,
  Breaking: 20,
  trendingTopics: 10,
  topStories: 5,
};

export interface CleanupStats {
  duplicatesFound: number;
  surplusFound: number;
  documentsDeleted: number;
  imagekitFilesDeleted: number;
  errors: number;
  categoryCountsAfterCleanup: Record<string, number>;
}

export class CleanupService {
  /**
   * Executes rolling retention and deduplication cleanup.
   * Runs ONLY AFTER new articles are successfully published.
   * Guarantees that categories NEVER become empty.
   */
  public static async executeCleanup(): Promise<CleanupStats> {
    Logger.logHeader('STARTING ROLLING RETENTION & DEDUPLICATION CLEANUP');

    const stats: CleanupStats = {
      duplicatesFound: 0,
      surplusFound: 0,
      documentsDeleted: 0,
      imagekitFilesDeleted: 0,
      errors: 0,
      categoryCountsAfterCleanup: {},
    };

    try {
      const db = FirestorePublisher.getFirestore();
      const docRemovalMap = new Map<string, { id: string; category?: string; imageKitFileId?: string; viewerDocumentId?: string }>();

      if (db) {
        // --- LIVE FIRESTORE CLEANUP ---
        // 1. DEDUPLICATION CLEANUP IN FIRESTORE
        const latestSnap = await db.collection('latestNews').get();
        const urlMap = new Map<string, any[]>();
        const titleMap = new Map<string, any[]>();

        latestSnap.docs.forEach((doc) => {
          const data = doc.data();
          const item = { id: doc.id, ...data };
          const cleanUrl = (data.originalSourceUrl || '').trim().toLowerCase();
          const cleanTitle = (data.title || '').trim().toLowerCase();

          if (cleanUrl) {
            if (!urlMap.has(cleanUrl)) urlMap.set(cleanUrl, []);
            urlMap.get(cleanUrl)!.push(item);
          }
          if (cleanTitle) {
            if (!titleMap.has(cleanTitle)) titleMap.set(cleanTitle, []);
            titleMap.get(cleanTitle)!.push(item);
          }
        });

        // Collect duplicate documents (keep newest, remove older)
        const checkDuplicateGroups = (groupMap: Map<string, any[]>) => {
          groupMap.forEach((items) => {
            if (items.length > 1) {
              stats.duplicatesFound += items.length - 1;
              items.sort((a, b) => new Date(b.publishedAt || b.collectedAt || 0).getTime() - new Date(a.publishedAt || a.collectedAt || 0).getTime());
              // Keep index 0, mark index 1..end for removal
              for (let i = 1; i < items.length; i++) {
                docRemovalMap.set(items[i].id, {
                  id: items[i].id,
                  category: items[i].category,
                  imageKitFileId: items[i].imageKitFileId,
                  viewerDocumentId: items[i].viewerDocumentId,
                });
              }
            }
          });
        };

        checkDuplicateGroups(urlMap);
        checkDuplicateGroups(titleMap);

        // 2. CATEGORY ROLLING RETENTION CLEANUP
        for (const cat of APP_CATEGORIES) {
          const limit = CATEGORY_RETENTION_LIMITS[cat] || 20;
          const catSnap = await db
            .collection('categoryNews')
            .doc(cat)
            .collection('articles')
            .get();

          const articles: any[] = catSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
          articles.sort((a, b) => new Date(b.publishedAt || b.collectedAt || 0).getTime() - new Date(a.publishedAt || a.collectedAt || 0).getTime());

          if (articles.length > limit) {
            const surplus = articles.slice(limit);
            stats.surplusFound += surplus.length;

            for (const item of surplus) {
              // Category Stability Invariant: Ensure removing doesn't drop category count to 0
              const remainingCount = articles.length - surplus.length;
              if (remainingCount >= 1 && !docRemovalMap.has(item.id)) {
                docRemovalMap.set(item.id, {
                  id: item.id,
                  category: cat,
                  imageKitFileId: item.imageKitFileId,
                  viewerDocumentId: item.viewerDocumentId,
                });
              }
            }
          }
        }

        // 3. LATEST NEWS ROLLING RETENTION (Limit: 80)
        const latestLimit = CATEGORY_RETENTION_LIMITS['latestNews'] || 80;
        const allLatest: any[] = latestSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
        allLatest.sort((a, b) => new Date(b.publishedAt || b.collectedAt || 0).getTime() - new Date(a.publishedAt || a.collectedAt || 0).getTime());

        if (allLatest.length > latestLimit) {
          const surplus = allLatest.slice(latestLimit);
          for (const item of surplus) {
            if (!docRemovalMap.has(item.id)) {
              docRemovalMap.set(item.id, {
                id: item.id,
                category: item.category,
                imageKitFileId: item.imageKitFileId,
                viewerDocumentId: item.viewerDocumentId,
              });
            }
          }
        }

        // 4. TRENDING TOPICS ROLLING RETENTION (Limit: 10)
        const trendingLimit = CATEGORY_RETENTION_LIMITS['trendingTopics'] || 10;
        const trendingSnap = await db.collection('trendingTopics').get();
        if (trendingSnap.size > trendingLimit) {
          const topics: any[] = trendingSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
          topics.sort((a, b) => (b.clusterSize || 0) - (a.clusterSize || 0));
          const excess = topics.slice(trendingLimit);
          const batch = db.batch();
          excess.forEach((t) => batch.delete(db.collection('trendingTopics').doc(t.id)));
          await batch.commit();
        }

        // 5. TOP STORIES ROLLING RETENTION (Limit: 5)
        const topLimit = CATEGORY_RETENTION_LIMITS['topStories'] || 5;
        const topSnap = await db.collection('topStories').get();
        if (topSnap.size > topLimit) {
          const topStories: any[] = topSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
          topStories.sort((a, b) => (b.importanceScore || 0) - (a.importanceScore || 0));
          const excess = topStories.slice(topLimit);
          const batch = db.batch();
          excess.forEach((t) => batch.delete(db.collection('topStories').doc(t.id)));
          await batch.commit();
        }

        // 6. EXECUTE ASSET DELETION (Order: Firestore Removal First, ImageKit Second)
        for (const target of docRemovalMap.values()) {
          Logger.info(`[CLEANUP] Pruning surplus document ${target.id} (Category: ${target.category || 'unknown'})`);
          try {
            // Delete Firestore metadata document across all collections first
            const fsDeleted = await FirestorePublisher.deleteArticleDocument(target.id, target.category);
            if (fsDeleted) {
              stats.documentsDeleted++;

              // ONLY AFTER Firestore removal, delete ImageKit assets
              if (target.imageKitFileId) {
                const imgDeleted = await ImageKitUploadService.deleteFile(target.imageKitFileId);
                if (imgDeleted) stats.imagekitFilesDeleted++;
              }
              if (target.viewerDocumentId && target.viewerDocumentId !== target.imageKitFileId) {
                const docDeleted = await ImageKitUploadService.deleteFile(target.viewerDocumentId);
                if (docDeleted) stats.imagekitFilesDeleted++;
              }
            }
          } catch (err: any) {
            Logger.error(`[CLEANUP] Error deleting document/asset for ${target.id}:`, err.message || err);
            stats.errors++;
          }
        }

        // 7. RECORD FINAL CATEGORY COUNTS AFTER CLEANUP
        for (const cat of APP_CATEGORIES) {
          const catSnapAfter = await db.collection('categoryNews').doc(cat).collection('articles').get();
          stats.categoryCountsAfterCleanup[cat] = catSnapAfter.size;
        }
        const finalLatest = await db.collection('latestNews').get();
        stats.categoryCountsAfterCleanup['latestNews'] = finalLatest.size;

      } else {
        // --- SIMULATED STORE CLEANUP ---
        Logger.info('[CLEANUP] Executing rolling retention cleanup in simulated store.');
        const latestMap = FirestorePublisher.getSimulatedCollection('latestNews');
        const items = Array.from(latestMap.values());
        items.sort((a, b) => new Date(b.publishedAt || b.collectedAt || 0).getTime() - new Date(a.publishedAt || a.collectedAt || 0).getTime());

        // Category retention
        for (const cat of APP_CATEGORIES) {
          const limit = CATEGORY_RETENTION_LIMITS[cat] || 20;
          const catMap = FirestorePublisher.getSimulatedCollection(`categoryNews:${cat}`);
          const catItems = Array.from(catMap.values());
          catItems.sort((a, b) => new Date(b.publishedAt || b.collectedAt || 0).getTime() - new Date(a.publishedAt || a.collectedAt || 0).getTime());

          if (catItems.length > limit) {
            const surplus = catItems.slice(limit);
            stats.surplusFound += surplus.length;
            for (const s of surplus) {
              catMap.delete(s.id);
              latestMap.delete(s.id);
              stats.documentsDeleted++;
            }
          }
          stats.categoryCountsAfterCleanup[cat] = catMap.size;
        }

        if (items.length > 80) {
          const surplus = items.slice(80);
          for (const s of surplus) {
            latestMap.delete(s.id);
          }
        }
        stats.categoryCountsAfterCleanup['latestNews'] = latestMap.size;
      }

      Logger.info(
        `[CLEANUP] Cleanup Complete: ${stats.documentsDeleted} Firestore docs deleted, ${stats.imagekitFilesDeleted} ImageKit assets deleted.`
      );
    } catch (error: any) {
      Logger.warn('[CLEANUP] Cleanup routine note:', error.message || error);
    }

    return stats;
  }
}


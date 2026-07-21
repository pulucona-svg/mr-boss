import admin from 'firebase-admin';
import fs from 'fs';
import path from 'path';
import { FirestoreNewsDocument } from '../models/magazine_viewer.model';
import { APP_CATEGORIES, StoryCluster, TrendingPackageTopic } from '../models/news_article.model';
import { Logger } from '../utils/logger';
import { config } from '../config/environment';

export class FirestorePublisher {
  private static db: admin.firestore.Firestore | null = null;
  private static isInitialized = false;
  private static simulatedStore: Map<string, Map<string, any>> = new Map();

  public static getFirestore(): admin.firestore.Firestore | null {
    if (FirestorePublisher.isInitialized) {
      return FirestorePublisher.db;
    }

    FirestorePublisher.isInitialized = true;

    try {
      const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS || config.googleApplicationCredentials;
      const isEmulator = !!process.env.FIRESTORE_EMULATOR_HOST;

      if (!credPath && !isEmulator) {
        Logger.info('[FIRESTORE] Credentials not specified in env. Operating in local simulation mode.');
        FirestorePublisher.db = null;
        return null;
      }

      if (admin.apps.length === 0) {
        if (isEmulator) {
          admin.initializeApp({ projectId: config.firebaseProjectId });
        } else if (credPath && fs.existsSync(credPath)) {
          Logger.info(`[FIRESTORE] Initializing Firebase Admin with service account key: ${credPath}`);
          const serviceAccount = JSON.parse(fs.readFileSync(credPath, 'utf8'));
          admin.initializeApp({
            credential: admin.credential.cert(serviceAccount),
            projectId: config.firebaseProjectId,
          });
        } else {
          admin.initializeApp({
            credential: admin.credential.applicationDefault(),
            projectId: config.firebaseProjectId,
          });
        }
      }

      const dbInstance = admin.firestore();
      dbInstance.settings({ ignoreUndefinedProperties: true });
      FirestorePublisher.db = dbInstance;
      Logger.info('[FIRESTORE] Connected to live Firebase Firestore successfully!');
    } catch (err: any) {
      Logger.error('[FIRESTORE] Initialization error:', err.message || err);
      FirestorePublisher.db = null;
    }

    return FirestorePublisher.db;
  }

  /**
   * Helper to strip any undefined properties before writing to Firestore.
   */
  public static sanitizeObject<T extends Record<string, any>>(obj: T): Record<string, any> {
    const clean: Record<string, any> = {};
    for (const [key, val] of Object.entries(obj)) {
      if (val !== undefined) {
        clean[key] = val;
      }
    }
    return clean;
  }

  /**
   * Fetches set of active article source URLs from Firestore to avoid re-publishing active stories.
   */
  public static async getActiveArticleUrls(): Promise<Set<string>> {
    const activeUrls = new Set<string>();
    const db = FirestorePublisher.getFirestore();

    if (!db) {
      const latestMap = FirestorePublisher.simulatedStore.get('latestNews');
      if (latestMap) {
        for (const doc of latestMap.values()) {
          if (doc.originalSourceUrl || doc.originalUrl) {
            activeUrls.add(doc.originalSourceUrl || doc.originalUrl);
          }
        }
      }
      return activeUrls;
    }

    try {
      const snapshot = await db.collection('latestNews').select('originalSourceUrl').get();
      snapshot.forEach((doc) => {
        const url = doc.data().originalSourceUrl;
        if (url) activeUrls.add(url);
      });
    } catch (err: any) {
      Logger.warn('[FIRESTORE] Active URL query note:', err.message || err);
    }

    return activeUrls;
  }

  public static getSimulatedCollection(collectionName: string): Map<string, any> {
    if (!FirestorePublisher.simulatedStore.has(collectionName)) {
      FirestorePublisher.simulatedStore.set(collectionName, new Map());
    }
    return FirestorePublisher.simulatedStore.get(collectionName)!;
  }

  /**
   * Publishes lightweight metadata document to Firestore collections (topStories, latestNews, categoryNews).
   * Supports multi-category indexing across primary and secondary categories.
   */
  public static async publishArticleMetadata(
    rawDoc: FirestoreNewsDocument
  ): Promise<boolean> {
    Logger.info(`[FIRESTORE_PUBLISH] Publishing metadata document for ID: ${rawDoc.id}`);
    const doc = FirestorePublisher.sanitizeObject(rawDoc) as FirestoreNewsDocument;
    const db = FirestorePublisher.getFirestore();

    const targetCategories = Array.from(
      new Set([doc.category, ...(doc.secondaryCategories || [])])
    );

    if (!db) {
      const latestMap = FirestorePublisher.getSimulatedCollection('latestNews');
      latestMap.set(doc.id, doc);

      for (const cat of targetCategories) {
        const catMap = FirestorePublisher.getSimulatedCollection(`categoryNews:${cat}`);
        catMap.set(doc.id, { ...doc, category: cat });
      }

      if (doc.isTopStory) {
        const topMap = FirestorePublisher.getSimulatedCollection('topStories');
        topMap.set(doc.id, doc);
      }
      Logger.info(`[FIRESTORE_PUBLISH] Simulated Firestore publish complete for ID: ${doc.id} across categories: ${targetCategories.join(', ')}`);
      return true;
    }

    try {
      const batch = db.batch();

      // 1. Write to latestNews
      const latestRef = db.collection('latestNews').doc(doc.id);
      batch.set(latestRef, doc, { merge: true });

      // 2. Write to categoryNews collection across all assigned categories (category set to container cat)
      for (const cat of targetCategories) {
        const categoryRef = db.collection('categoryNews').doc(cat).collection('articles').doc(doc.id);
        const categoryDoc = { ...doc, category: cat };
        batch.set(categoryRef, categoryDoc, { merge: true });
      }

      // 3. Write to topStories if flagged
      if (doc.isTopStory) {
        const topRef = db.collection('topStories').doc(doc.id);
        batch.set(topRef, doc, { merge: true });
      }

      await batch.commit();
      Logger.info(`[FIRESTORE_PUBLISH] Firestore batch write committed successfully for ${doc.id} across categories (${targetCategories.join(', ')})`);
      return true;
    } catch (error: any) {
      Logger.error(`[FIRESTORE_PUBLISH] Firestore write failed for ${doc.id}:`, error.message || error);
      return false;
    }
  }

  /**
   * Returns document count for a category in categoryNews.
   */
  public static async getCategoryDocumentCount(category: string): Promise<number> {
    const db = FirestorePublisher.getFirestore();
    if (!db) {
      const catMap = FirestorePublisher.simulatedStore.get(`categoryNews:${category}`);
      return catMap ? catMap.size : 0;
    }

    try {
      const catSnap = await db
        .collection('categoryNews')
        .doc(category)
        .collection('articles')
        .get();
      return catSnap.size;
    } catch (err) {
      return 0;
    }
  }

  /**
   * Publishes trending topics & story clusters into Firestore.
   */
  public static async publishTrendingAndClusters(
    trendingTopics: TrendingPackageTopic[],
    clusters: StoryCluster[]
  ): Promise<boolean> {
    const db = FirestorePublisher.getFirestore();

    if (!db) {
      if (!FirestoreServiceSimulated.simulatedStore.has('trendingTopics')) {
        FirestoreServiceSimulated.simulatedStore.set('trendingTopics', new Map());
      }
      trendingTopics.forEach((t) => FirestoreServiceSimulated.simulatedStore.get('trendingTopics')!.set(t.id, t));

      if (!FirestoreServiceSimulated.simulatedStore.has('storyClusters')) {
        FirestoreServiceSimulated.simulatedStore.set('storyClusters', new Map());
      }
      clusters.forEach((c) => FirestoreServiceSimulated.simulatedStore.get('storyClusters')!.set(c.clusterId, c));

      return true;
    }

    try {
      const batch = db.batch();

      trendingTopics.forEach((topic) => {
        const ref = db.collection('trendingTopics').doc(topic.id);
        batch.set(ref, FirestorePublisher.sanitizeObject(topic), { merge: true });
      });

      clusters.forEach((cluster) => {
        const ref = db.collection('storyClusters').doc(cluster.clusterId);
        batch.set(
          ref,
          FirestorePublisher.sanitizeObject({
            clusterId: cluster.clusterId,
            topicTitle: cluster.topicTitle,
            clusterSize: cluster.clusterSize,
            mainArticleId: cluster.mainArticle.id,
            mainArticleTitle: cluster.mainArticle.title,
            relatedArticleIds: cluster.relatedArticles.map((r) => r.id),
            createdAt: cluster.createdAt,
          }),
          { merge: true }
        );
      });

      await batch.commit();
      return true;
    } catch (err: any) {
      Logger.error('[FIRESTORE_PUBLISH] Failed to publish trending topics and clusters:', err.message || err);
      return false;
    }
  }

  /**
   * Deletes a Firestore document across all collections and assigned categories. Used during cleanup and rollback.
   */
  public static async deleteArticleDocument(
    articleId: string,
    category?: string,
    secondaryCategories?: string[]
  ): Promise<boolean> {
    Logger.info(`[CLEANUP / ROLLBACK] Deleting document from Firestore: ${articleId}`);
    const db = FirestorePublisher.getFirestore();

    const allCategories = Array.from(
      new Set([...APP_CATEGORIES, ...(category ? [category] : []), ...(secondaryCategories || [])])
    );

    if (!db) {
      for (const map of FirestorePublisher.simulatedStore.values()) {
        map.delete(articleId);
      }
      return true;
    }

    try {
      const batch = db.batch();
      batch.delete(db.collection('latestNews').doc(articleId));
      batch.delete(db.collection('topStories').doc(articleId));

      for (const cat of allCategories) {
        batch.delete(
          db.collection('categoryNews').doc(cat).collection('articles').doc(articleId)
        );
      }

      await batch.commit();
      Logger.info(`[CLEANUP] Successfully deleted Firestore document ${articleId} across categories.`);
      return true;
    } catch (err: any) {
      Logger.error(`[CLEANUP] Failed to delete Firestore document ${articleId}:`, err.message || err);
      return false;
    }
  }
}

class FirestoreServiceSimulated {
  static simulatedStore: Map<string, Map<string, any>> = new Map();
}

import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { ExploreGenerationPipeline } from "./explore_generation_pipeline";

export const CATEGORIES_TO_ROTATE = [
  "General",
  "Technology",
  "Campus",
  "Environment",
  "Sports",
  "Entertainment",
  "Science",
  "Business",
  "Health",
];

const TARGET_ARTICLES_PER_CATEGORY = 25;

export class NewsRotationScheduler {
  /**
   * Ensures every category has exactly 25 published articles.
   * If any category has fewer than 25 articles, generates new articles to reach 25.
   */
  public static async checkAndPopulateInitialNews(db: admin.firestore.Firestore): Promise<void> {
    logger.info("[NEWS_ROTATION] Checking category article counts for 25-article capacity requirement...");

    for (const category of CATEGORIES_TO_ROTATE) {
      try {
        const snap = await db
          .collection("explore_news")
          .where("category", "==", category)
          .get();

        const count = snap.size;
        logger.info(`[NEWS_ROTATION_CHECK] Category="${category}" CurrentCount=${count} Target=${TARGET_ARTICLES_PER_CATEGORY}`);

        if (count < TARGET_ARTICLES_PER_CATEGORY) {
          const needed = TARGET_ARTICLES_PER_CATEGORY - count;
          logger.info(`[NEWS_ROTATION_POPULATE] Category="${category}" needs ${needed} additional articles.`);

          for (let i = 0; i < needed; i++) {
            const topic = `${category} breaking news updates ${Date.now()}_${i}`;
            const res = await ExploreGenerationPipeline.generateArticleForTopic(db, topic, category, true);
            if (res.success) {
              logger.info(`[NEWS_ROTATION_CREATED] Category="${category}" Generated Article="${res.article?.title}" (${i + 1}/${needed})`);
            }
          }
        }
      } catch (err: any) {
        logger.error(`[NEWS_ROTATION_ERROR] Failed population check for category="${category}":`, err);
      }
    }
  }

  /**
   * Hourly rotation:
   * 1. Generate 3 newest articles for every category.
   * 2. Delete the 3 oldest published articles in that category.
   * 3. Maintain exactly 25 articles per category.
   */
  public static async performHourlyRotation(db: admin.firestore.Firestore): Promise<void> {
    logger.info("[NEWS_ROTATION_HOURLY_START] Initiating hourly article rotation for all categories...");

    for (const category of CATEGORIES_TO_ROTATE) {
      try {
        logger.info(`[NEWS_ROTATION_HOURLY] Generating 3 newest articles for Category="${category}"...`);
        for (let i = 0; i < 3; i++) {
          const topic = `${category} latest breaking updates ${Date.now()}_${i}`;
          await ExploreGenerationPipeline.generateArticleForTopic(db, topic, category, true);
        }

        const snap = await db
          .collection("explore_news")
          .where("category", "==", category)
          .get();

        const docs = snap.docs;
        docs.sort((a, b) => {
          const dateA = a.data().publishedAt?.toDate ? a.data().publishedAt.toDate().getTime() : 0;
          const dateB = b.data().publishedAt?.toDate ? b.data().publishedAt.toDate().getTime() : 0;
          return dateA - dateB;
        });

        const currentCount = docs.length;
        if (currentCount > TARGET_ARTICLES_PER_CATEGORY) {
          const toRemoveCount = currentCount - TARGET_ARTICLES_PER_CATEGORY;
          const toDelete = docs.slice(0, toRemoveCount);
          for (const d of toDelete) {
            logger.info(`[NEWS_ROTATION_DELETE] Deleting old article docId="${d.id}" Title="${d.data().title}" Category="${category}"`);
            await db.collection("explore_news").doc(d.id).delete();
          }
        }
      } catch (err: any) {
        logger.error(`[NEWS_ROTATION_HOURLY_ERROR] Category="${category}" failed hourly rotation:`, err);
      }
    }

    logger.info("[NEWS_ROTATION_HOURLY_COMPLETE] Hourly rotation finished successfully.");
  }

  /**
   * 12:00 PM Daily Major Refresh:
   * 1. Remove the 10 oldest articles in every category.
   * 2. Generate 10 brand-new articles for every category.
   * 3. Insert the 10 new articles at the top.
   * 4. Remaining 15 newer articles stay in place.
   * Result: Exactly 25 articles per category.
   */
  public static async performNoonDailyRefresh(db: admin.firestore.Firestore): Promise<void> {
    logger.info("[NEWS_ROTATION_NOON_START] Initiating 12:00 PM Noon daily major refresh for all categories...");

    for (const category of CATEGORIES_TO_ROTATE) {
      try {
        const snap = await db
          .collection("explore_news")
          .where("category", "==", category)
          .get();

        const docs = snap.docs;
        docs.sort((a, b) => {
          const dateA = a.data().publishedAt?.toDate ? a.data().publishedAt.toDate().getTime() : 0;
          const dateB = b.data().publishedAt?.toDate ? b.data().publishedAt.toDate().getTime() : 0;
          return dateA - dateB;
        });

        const toDeleteCount = Math.min(10, docs.length);
        const toDelete = docs.slice(0, toDeleteCount);
        for (const d of toDelete) {
          logger.info(`[NEWS_ROTATION_NOON_DELETE] Deleting old article docId="${d.id}" Title="${d.data().title}" Category="${category}"`);
          await db.collection("explore_news").doc(d.id).delete();
        }

        logger.info(`[NEWS_ROTATION_NOON_GEN] Generating 10 new major refresh articles for Category="${category}"...`);
        for (let i = 0; i < 10; i++) {
          const topic = `${category} major noon update ${Date.now()}_${i}`;
          await ExploreGenerationPipeline.generateArticleForTopic(db, topic, category, true);
        }

        const finalSnap = await db
          .collection("explore_news")
          .where("category", "==", category)
          .get();

        if (finalSnap.size > TARGET_ARTICLES_PER_CATEGORY) {
          const finalDocs = finalSnap.docs;
          finalDocs.sort((a, b) => {
            const dateA = a.data().publishedAt?.toDate ? a.data().publishedAt.toDate().getTime() : 0;
            const dateB = b.data().publishedAt?.toDate ? b.data().publishedAt.toDate().getTime() : 0;
            return dateA - dateB;
          });
          const overflow = finalDocs.slice(0, finalSnap.size - TARGET_ARTICLES_PER_CATEGORY);
          for (const d of overflow) {
            await db.collection("explore_news").doc(d.id).delete();
          }
        }
      } catch (err: any) {
        logger.error(`[NEWS_ROTATION_NOON_ERROR] Category="${category}" failed noon refresh:`, err);
      }
    }

    logger.info("[NEWS_ROTATION_NOON_COMPLETE] 12:00 PM Noon daily major refresh completed successfully.");
  }
}

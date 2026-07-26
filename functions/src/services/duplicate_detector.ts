import * as crypto from "crypto";
import * as admin from "firebase-admin";

export class DuplicateDetector {
  /**
   * Generates a deterministic SHA-256 hash from normalized title and source.
   */
  static generateArticleHash(title: string, source: string): string {
    const cleanTitle = (title || "")
      .toLowerCase()
      .replace(/[^\w\s]/gi, "")
      .replace(/\s+/g, " ")
      .trim();

    const cleanSource = (source || "")
      .toLowerCase()
      .replace(/[^\w\s]/gi, "")
      .replace(/\s+/g, " ")
      .trim();

    const combined = `${cleanTitle}||${cleanSource}`;
    return crypto.createHash("sha256").update(combined).digest("hex");
  }

  /**
   * Generates a unique cluster ID from the article hash.
   */
  static generateClusterId(articleHash: string): string {
    return `cluster_${articleHash.substring(0, 16)}`;
  }

  /**
   * Checks whether an article hash already exists in Firestore in job_queue, explore_news, or storyClusters.
   */
  static async isDuplicate(
    db: admin.firestore.Firestore,
    articleHash: string
  ): Promise<boolean> {
    if (!articleHash) return false;

    // Check job_queue
    const queueSnap = await db
      .collection("job_queue")
      .where("articleHash", "==", articleHash)
      .limit(1)
      .get();

    if (!queueSnap.empty) {
      return true;
    }

    // Check storyClusters
    const clusterSnap = await db
      .collection("storyClusters")
      .where("articleHash", "==", articleHash)
      .limit(1)
      .get();

    if (!clusterSnap.empty) {
      return true;
    }

    // Check explore_news
    const newsSnap = await db
      .collection("explore_news")
      .where("articleHash", "==", articleHash)
      .limit(1)
      .get();

    if (!newsSnap.empty) {
      return true;
    }

    return false;
  }
}

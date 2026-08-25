import * as crypto from "crypto";
import * as admin from "firebase-admin";

export class DuplicateDetector {
  /**
   * Generates an event fingerprint.  The publisher is deliberately not part of
   * the fingerprint: Reuters and the BBC reporting the same event must not
   * become two Explore stories.
   */
  static generateArticleHash(title: string, source: string): string {
    const cleanTitle = (title || "")
      .toLowerCase()
      .replace(/[^\w\s]/gi, "")
      .replace(/\s+/g, " ")
      .trim();

    // Keep the argument for backwards-compatible callers, but do not use it
    // in the event identity. Source provenance is retained on the candidate.
    void source;
    return crypto.createHash("sha256").update(cleanTitle).digest("hex");
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

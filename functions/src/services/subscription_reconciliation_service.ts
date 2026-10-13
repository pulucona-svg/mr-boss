import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

export class SubscriptionReconciliationService {
  /**
   * Reconciles subscription history document statuses for a specific user.
   * - Transitions 'queued' to 'active' if activationDate <= now < expiryDate.
   * - Transitions 'active' to 'expired' if now >= expiryDate.
   * Preserves terminated, cancelled, refunded, and revoked records.
   * Strictly bounded to this user's history collection; completely idempotent.
   */
  public static async reconcileUserSubscriptions(
    db: FirebaseFirestore.Firestore,
    userId: string,
    now: Date = new Date()
  ): Promise<{ updatedCount: number; changedDocIds: string[] }> {
    if (!userId) return { updatedCount: 0, changedDocIds: [] };

    const historyRef = db.collection("subscriptions").doc(userId).collection("history");
    const historySnap = await historyRef.get();
    if (historySnap.empty) return { updatedCount: 0, changedDocIds: [] };

    const batch = db.batch();
    let updatedCount = 0;
    const changedDocIds: string[] = [];

    for (const doc of historySnap.docs) {
      const data = doc.data();
      const status = data.status;

      // Do not touch terminated, refunded, cancelled, or revoked records
      if (
        status === "terminated" ||
        status === "refunded" ||
        status === "cancelled" ||
        status === "revoked"
      ) {
        continue;
      }

      const actDate = data.activationDate instanceof admin.firestore.Timestamp
        ? data.activationDate.toDate()
        : new Date(data.activationDate);

      const expDate = data.expiryDate instanceof admin.firestore.Timestamp
        ? data.expiryDate.toDate()
        : new Date(data.expiryDate);

      if (isNaN(expDate.getTime())) continue;

      const actTime = isNaN(actDate.getTime()) ? 0 : actDate.getTime();
      const expTime = expDate.getTime();
      const nowTime = now.getTime();

      if (status === "queued" && nowTime >= actTime && nowTime < expTime) {
        batch.update(doc.ref, {
          status: "active",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        updatedCount++;
        changedDocIds.push(doc.id);
      } else if (status === "active" && nowTime >= expTime) {
        batch.update(doc.ref, {
          status: "expired",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        updatedCount++;
        changedDocIds.push(doc.id);
      }
    }

    if (updatedCount > 0) {
      await batch.commit();
      logger.info(
        `[RECONCILE_USER_SUBSCRIPTIONS] Reconciled ${updatedCount} subscription(s) for user ${userId}. Docs: ${changedDocIds.join(", ")}`
      );
    }

    return { updatedCount, changedDocIds };
  }
}

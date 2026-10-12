import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";
import { HttpsError } from "firebase-functions/v2/https";
import { EmailService } from "./email_service";

export interface DeletionSurvey {
  q1_reason?: string;
  q2_improvements?: string;
  q3_disappointed_feature?: string;
  q4_usability_issues?: string;
  q5_academic_value?: string;
  q6_material_availability?: string;
  q7_ads_rating?: string;
  q8_payment_feedback?: string;
  q9_would_return?: string;
  q10_comments?: string;
  [key: string]: any;
}

export interface RequestDeletionParams {
  reason?: string;
  survey?: DeletionSurvey;
  userEmail?: string;
}

export class AccountDeletionService {
  /**
   * Request account deletion with 30-day grace period.
   * Transactional and idempotent.
   */
  static async requestAccountDeletion(
    db: FirebaseFirestore.Firestore,
    uid: string,
    params: RequestDeletionParams = {}
  ): Promise<{
    success: boolean;
    deletionStatus: string;
    deletionScheduledAt: string;
    alreadyPending?: boolean;
    message: string;
  }> {
    if (!uid || typeof uid !== "string") {
      throw new HttpsError("unauthenticated", "Invalid or missing user authentication.");
    }

    const userRef = db.collection("users").doc(uid);
    const auditRef = db.collection("account_deletion_audits").doc(uid);

    let scheduledDate: Date;
    let alreadyPending = false;
    let resolvedEmail = params.userEmail || "";

    await db.runTransaction(async (transaction) => {
      const userSnap = await transaction.get(userRef);
      if (!userSnap.exists) {
        throw new HttpsError("not-found", "User profile not found.");
      }

      const userData = userSnap.data() || {};
      if (!resolvedEmail && userData.email) {
        resolvedEmail = userData.email;
      }

      // If already pending, return existing deadline idempotently
      if (userData.deletionStatus === "pending" && userData.deletionScheduledAt) {
        alreadyPending = true;
        const existingTimestamp = userData.deletionScheduledAt as admin.firestore.Timestamp;
        scheduledDate = existingTimestamp.toDate ? existingTimestamp.toDate() : new Date(existingTimestamp as any);
        logger.info(`[DELETION_REQUEST_IDEMPOTENT] User ${uid} already pending deletion until ${scheduledDate.toISOString()}`);
        return;
      }

      const now = new Date();
      scheduledDate = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);

      const updateData: Record<string, any> = {
        deletionStatus: "pending",
        deletionRequestedAt: admin.firestore.Timestamp.fromDate(now),
        deletionScheduledAt: admin.firestore.Timestamp.fromDate(scheduledDate),
        isAnonymized: false,
      };

      if (params.reason) {
        updateData.deletionReason = params.reason;
      }
      if (params.survey && Object.keys(params.survey).length > 0) {
        updateData.deletionSurvey = params.survey;
      }

      transaction.update(userRef, updateData);

      transaction.set(
        auditRef,
        {
          uid,
          status: "pending",
          requestedAt: admin.firestore.Timestamp.fromDate(now),
          scheduledPurgeAt: admin.firestore.Timestamp.fromDate(scheduledDate),
          notificationEmail: resolvedEmail || null,
          survey: params.survey || null,
          reason: params.reason || null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    });

    // Invalidate active device sessions under users/{uid}/sessions
    try {
      const sessionsSnap = await userRef.collection("sessions").get();
      if (!sessionsSnap.empty) {
        const batch = db.batch();
        sessionsSnap.docs.forEach((doc) => {
          batch.update(doc.ref, { isActive: false, invalidatedAt: admin.firestore.FieldValue.serverTimestamp() });
        });
        await batch.commit();
      }
    } catch (sessionErr: any) {
      logger.warn(`[DELETION_SESSIONS_INVALIDATE_WARN] Could not deactivate sessions for ${uid}:`, sessionErr.message);
    }

    // EMAIL #1: Account Deletion Request Confirmation
    // Dispatched ONLY after deletion transaction commits successfully.
    // Failure to send email NEVER rolls back deletion or changes deletionStatus.
    if (!alreadyPending && resolvedEmail) {
      try {
        const auditSnap = await auditRef.get();
        const auditData = auditSnap.data() || {};
        if (!auditData.deletionEmailSentAt) {
          const emailRes = await EmailService.sendDeletionRequestedEmail(resolvedEmail, scheduledDate!);
          if (emailRes.success) {
            await auditRef.set(
              {
                deletionEmailSentAt: admin.firestore.FieldValue.serverTimestamp(),
                deletionEmailPending: false,
                notificationEmail: resolvedEmail,
              },
              { merge: true }
            );
          } else if (!emailRes.skipped) {
            logger.warn(`[DELETION_EMAIL_WARN] Could not send deletion confirmation to ${resolvedEmail}:`, emailRes.error);
            await auditRef.set(
              {
                deletionEmailPending: true,
                notificationEmail: resolvedEmail,
              },
              { merge: true }
            );
          }
        }
      } catch (emailErr: any) {
        logger.warn(`[DELETION_EMAIL_ERROR] Error dispatching deletion email to ${resolvedEmail}:`, emailErr.message || emailErr);
        await auditRef.set(
          {
            deletionEmailPending: true,
            notificationEmail: resolvedEmail,
          },
          { merge: true }
        );
      }
    }

    return {
      success: true,
      deletionStatus: "pending",
      deletionScheduledAt: scheduledDate!.toISOString(),
      alreadyPending,
      message: alreadyPending
        ? "Account is already scheduled for deletion."
        : "Account deletion requested successfully. Grace period expires in 30 days.",
    };
  }

  /**
   * Restore an account in pending deletion state.
   * Transactional and verifies deadline has not elapsed.
   */
  static async restoreUserAccount(
    db: FirebaseFirestore.Firestore,
    uid: string,
    callerEmail?: string
  ): Promise<{
    success: boolean;
    deletionStatus: string;
    message: string;
  }> {
    if (!uid || typeof uid !== "string") {
      throw new HttpsError("unauthenticated", "Invalid or missing user authentication.");
    }

    const userRef = db.collection("users").doc(uid);
    const auditRef = db.collection("account_deletion_audits").doc(uid);
    let targetEmail = callerEmail || "";

    await db.runTransaction(async (transaction) => {
      const userSnap = await transaction.get(userRef);
      if (!userSnap.exists) {
        throw new HttpsError("not-found", "User profile not found.");
      }

      const userData = userSnap.data() || {};
      if (!targetEmail && userData.email) {
        targetEmail = userData.email;
      }

      if (userData.deletionStatus !== "pending") {
        throw new HttpsError("failed-precondition", "Account is not pending deletion.");
      }

      const scheduledTimestamp = userData.deletionScheduledAt as admin.firestore.Timestamp | undefined;
      const scheduledDate = scheduledTimestamp && scheduledTimestamp.toDate
        ? scheduledTimestamp.toDate()
        : new Date((scheduledTimestamp as any) || 0);

      const now = new Date();
      if (scheduledDate.getTime() <= now.getTime()) {
        throw new HttpsError(
          "failed-precondition",
          "The 30-day grace period for this account has expired and it cannot be restored."
        );
      }

      transaction.update(userRef, {
        deletionStatus: "none",
        deletionRequestedAt: admin.firestore.FieldValue.delete(),
        deletionScheduledAt: admin.firestore.FieldValue.delete(),
        deletionReason: admin.firestore.FieldValue.delete(),
        deletionSurvey: admin.firestore.FieldValue.delete(),
        restoredAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      transaction.set(
        auditRef,
        {
          status: "restored",
          restoredAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          notificationEmail: targetEmail || null,
        },
        { merge: true }
      );
    });

    logger.info(`[DELETION_RESTORE_SUCCESS] Account ${uid} successfully restored.`);

    // EMAIL #2: Account Restoration Confirmation
    // Dispatched ONLY after restore transaction commits successfully.
    // Failure to send email NEVER rolls back restoration or alters status.
    if (targetEmail) {
      try {
        const auditSnap = await auditRef.get();
        const auditData = auditSnap.data() || {};
        if (!auditData.restorationEmailSentAt) {
          const emailRes = await EmailService.sendAccountRestoredEmail(targetEmail);
          if (emailRes.success) {
            await auditRef.set(
              {
                restorationEmailSentAt: admin.firestore.FieldValue.serverTimestamp(),
                restorationEmailPending: false,
              },
              { merge: true }
            );
          } else if (!emailRes.skipped) {
            logger.warn(`[RESTORE_EMAIL_WARN] Could not send restoration confirmation to ${targetEmail}:`, emailRes.error);
            await auditRef.set(
              {
                restorationEmailPending: true,
                notificationEmail: targetEmail,
              },
              { merge: true }
            );
          }
        }
      } catch (emailErr: any) {
        logger.warn(`[RESTORE_EMAIL_ERROR] Error dispatching restore email to ${targetEmail}:`, emailErr.message || emailErr);
        await auditRef.set(
          {
            restorationEmailPending: true,
            notificationEmail: targetEmail,
          },
          { merge: true }
        );
      }
    }

    return {
      success: true,
      deletionStatus: "none",
      message: "Account restored successfully.",
    };
  }

  /**
   * Daily processor: Purges and anonymizes accounts whose 30-day grace period has expired,
   * and retries any accounts whose Firebase Auth deletion previously failed.
   */
  static async processExpiredDeletions(
    db: FirebaseFirestore.Firestore,
    ik: ImageKit | null,
    batchLimit: number = 50
  ): Promise<number> {
    const now = admin.firestore.Timestamp.now();

    const expiredSnap = await db
      .collection("users")
      .where("deletionStatus", "==", "pending")
      .where("deletionScheduledAt", "<=", now)
      .limit(batchLimit)
      .get();

    const processedUids = new Set<string>();
    let processedCount = 0;

    if (!expiredSnap.empty) {
      logger.info(`[ACCOUNT_DELETION_PROCESSOR] Found ${expiredSnap.size} accounts pending permanent deletion.`);

      for (const doc of expiredSnap.docs) {
        const uid = doc.id;
        processedUids.add(uid);
        const userRef = db.collection("users").doc(uid);
        const userData = doc.data() || {};

        // Capture authentic email address in memory BEFORE scrub/deletion
        const authenticEmail = (userData.email && !userData.email.endsWith("@deleted.local"))
          ? userData.email
          : null;

        try {
          // 1. Double-check status atomically
          let shouldProceed = false;
          await db.runTransaction(async (transaction) => {
            const freshSnap = await transaction.get(userRef);
            if (freshSnap.exists) {
              const fData = freshSnap.data() || {};
              const schedMillis = AccountDeletionService._getMillis(fData.deletionScheduledAt);
              if (fData.deletionStatus === "pending" && schedMillis <= now.toMillis()) {
                transaction.update(userRef, {
                  deletionStatus: "permanently_deleted",
                  isAnonymized: true,
                  anonymizedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                shouldProceed = true;
              }
            }
          });

          if (!shouldProceed) {
            logger.info(`[ACCOUNT_DELETION_PROCESSOR] Account ${uid} was restored or already processed. Skipping.`);
            continue;
          }

          // 2. Profile Photo cleanup from ImageKit
          const photoFileId = userData.photoFileId as string | undefined;
          if (ik && photoFileId) {
            try {
              await ik.deleteFile(photoFileId);
              logger.info(`[ACCOUNT_DELETION_IMAGEKIT] Deleted profile photo ${photoFileId} for ${uid}`);
            } catch (ikErr: any) {
              logger.warn(`[ACCOUNT_DELETION_IMAGEKIT_WARN] Failed to delete profile photo ${photoFileId}:`, ikErr.message);
            }
          }

          // 3. Purge subcollections: sessions and notifications
          await this._deleteSubcollection(userRef.collection("sessions"));
          await this._deleteSubcollection(userRef.collection("notifications"));

          // 4. Purge private conversations
          const convRef = db.collection("conversations").doc(uid);
          const convSnap = await convRef.get();
          if (convSnap.exists) {
            await this._deleteSubcollection(convRef.collection("messages"));
            await convRef.delete();
          }

          // 5. Anonymize user-uploaded academic materials in chunks <= 450
          // CRITICAL INVARIANT: NEVER MODIFY isImportedDSpace === true MATERIALS
          const userResourcesSnap = await db.collection("resources").where("uploaderId", "==", uid).get();
          if (!userResourcesSnap.empty) {
            const resOps: Array<{ ref: FirebaseFirestore.DocumentReference; data: Record<string, any> }> = [];
            for (const resDoc of userResourcesSnap.docs) {
              const resData = resDoc.data();
              // ABSOLUTE PROTECTION FOR DSPACE MATERIALS
              if (resData.isImportedDSpace === true) {
                logger.info(`[DSPACE_PROTECTION] Preserving DSpace imported material ${resDoc.id} from anonymization.`);
                continue;
              }

              resOps.push({
                ref: resDoc.ref,
                data: {
                  uploaderId: "anonymous",
                  uploaderRole: "Contributor",
                  uploaderProfilePic: null,
                  isAnonymized: true,
                  anonymizedAt: admin.firestore.FieldValue.serverTimestamp(),
                },
              });
            }
            if (resOps.length > 0) {
              await this._batchUpdateInChunks(db, resOps, 450);
              logger.info(`[ACCOUNT_DELETION_ANONYMIZED_RESOURCES] Anonymized ${resOps.length} resources for user ${uid}.`);
            }
          }

          // 6. Anonymize user comments across resources in chunks <= 450
          try {
            const commentsSnap = await db.collectionGroup("comments").where("authorId", "==", uid).get();
            if (!commentsSnap.empty) {
              const commentOps: Array<{ ref: FirebaseFirestore.DocumentReference; data: Record<string, any> }> = commentsSnap.docs.map((cDoc) => ({
                ref: cDoc.ref,
                data: {
                  author: "Anonymous User",
                  authorProfileImage: null,
                  authorId: null,
                  isAnonymized: true,
                },
              }));
              await this._batchUpdateInChunks(db, commentOps, 450);
              logger.info(`[ACCOUNT_DELETION_ANONYMIZED_COMMENTS] Anonymized ${commentsSnap.size} comments for user ${uid}.`);
            }
          } catch (cgErr: any) {
            logger.warn(`[ACCOUNT_DELETION_COMMENTS_WARN] Error anonymizing collectionGroup comments for ${uid}:`, cgErr.message);
          }

          // 7. Scrub personally identifying information from users/{uid}
          await userRef.set(
            {
              email: `deleted_${uid}@deleted.local`,
              username: `deleted_user_${uid.slice(0, 6)}`,
              photoURL: null,
              photoFileId: null,
              phone: "",
              institution: "",
              universityLocation: "",
              program: "",
              programCode: "",
              deletionStatus: "permanently_deleted",
              isAnonymized: true,
              anonymizedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );

          // 8. Delete user from Firebase Authentication with failure retry recording
          let authDeleteSuccess = false;
          try {
            await admin.auth().deleteUser(uid);
            authDeleteSuccess = true;
            logger.info(`[ACCOUNT_DELETION_AUTH_SUCCESS] Deleted Firebase Auth user ${uid}.`);
          } catch (authErr: any) {
            if (authErr?.code === "auth/user-not-found") {
              authDeleteSuccess = true;
              logger.info(`[ACCOUNT_DELETION_AUTH_INFO] Auth user ${uid} was already not found.`);
            } else {
              logger.warn(`[ACCOUNT_DELETION_AUTH_WARN] Could not delete Auth user ${uid}:`, authErr?.message || authErr);
            }
          }

          // Update authDeletePending status on user document
          await userRef.set(
            {
              authDeletePending: !authDeleteSuccess,
            },
            { merge: true }
          );

          // 9. Update audit record
          await db.collection("account_deletion_audits").doc(uid).set(
            {
              status: "purged",
              authDeletePending: !authDeleteSuccess,
              authDeletedAt: authDeleteSuccess ? admin.firestore.FieldValue.serverTimestamp() : null,
              purgedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );

          // EMAIL #3: Final Permanent Deletion Confirmation
          // Dispatched after permanent deletion & anonymization operations successfully complete.
          // Failure to send email NEVER rolls back deletion and NEVER recreates the deleted Auth user.
          if (authenticEmail) {
            try {
              const auditSnap = await db.collection("account_deletion_audits").doc(uid).get();
              const auditData = auditSnap.data() || {};
              if (!auditData.permanentDeletionEmailSentAt) {
                const emailRes = await EmailService.sendPermanentDeletionEmail(authenticEmail);
                if (emailRes.success) {
                  await db.collection("account_deletion_audits").doc(uid).set(
                    {
                      permanentDeletionEmailSentAt: admin.firestore.FieldValue.serverTimestamp(),
                      permanentDeletionEmailPending: false,
                      notificationEmail: admin.firestore.FieldValue.delete(), // Minimizes retention of PII
                    },
                    { merge: true }
                  );
                } else if (!emailRes.skipped) {
                  logger.warn(`[PERMANENT_DELETION_EMAIL_WARN] Could not send permanent deletion email to ${authenticEmail}:`, emailRes.error);
                  await db.collection("account_deletion_audits").doc(uid).set(
                    {
                      permanentDeletionEmailPending: true,
                      notificationEmail: authenticEmail, // Retained strictly for durable email retry
                    },
                    { merge: true }
                  );
                }
              }
            } catch (emailErr: any) {
              logger.warn(`[PERMANENT_DELETION_EMAIL_ERROR] Error sending permanent deletion email to ${authenticEmail}:`, emailErr.message || emailErr);
              await db.collection("account_deletion_audits").doc(uid).set(
                {
                  permanentDeletionEmailPending: true,
                  notificationEmail: authenticEmail,
                },
                { merge: true }
              );
            }
          }

          processedCount++;
        } catch (err: any) {
          logger.error(`[ACCOUNT_DELETION_ERROR] Failed to permanently delete account ${uid}:`, err);
        }
      }
    } else {
      logger.info("[ACCOUNT_DELETION_PROCESSOR] No expired accounts pending permanent deletion.");
    }

    // 10. Process retry for accounts where Auth deletion previously failed
    try {
      const retryAuthSnap = await db
        .collection("users")
        .where("authDeletePending", "==", true)
        .limit(batchLimit)
        .get();

      if (!retryAuthSnap.empty) {
        logger.info(`[ACCOUNT_DELETION_AUTH_RETRY] Found ${retryAuthSnap.size} accounts needing Auth deletion retry.`);
        for (const rDoc of retryAuthSnap.docs) {
          const rUid = rDoc.id;
          if (processedUids.has(rUid)) continue;

          let retrySuccess = false;
          try {
            await admin.auth().deleteUser(rUid);
            retrySuccess = true;
            logger.info(`[ACCOUNT_DELETION_AUTH_RETRY_SUCCESS] Deleted Firebase Auth user on retry: ${rUid}`);
          } catch (retryErr: any) {
            if (retryErr?.code === "auth/user-not-found") {
              retrySuccess = true;
              logger.info(`[ACCOUNT_DELETION_AUTH_RETRY_INFO] Auth user ${rUid} already gone.`);
            } else {
              logger.warn(`[ACCOUNT_DELETION_AUTH_RETRY_FAILED] Auth delete retry failed for ${rUid}:`, retryErr?.message || retryErr);
            }
          }

          if (retrySuccess) {
            await rDoc.ref.set({ authDeletePending: false }, { merge: true });
            await db.collection("account_deletion_audits").doc(rUid).set(
              {
                authDeletePending: false,
                authDeletedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true }
            );
          }
        }
      }
    } catch (retryQueryErr: any) {
      logger.warn("[ACCOUNT_DELETION_AUTH_RETRY_QUERY_WARN] Error querying authDeletePending accounts:", retryQueryErr?.message || retryQueryErr);
    }

    // 11. Process retry for accounts where permanent deletion email previously failed
    // (Never touches or recreates Firebase Auth)
    try {
      const retryEmailSnap = await db
        .collection("account_deletion_audits")
        .where("permanentDeletionEmailPending", "==", true)
        .limit(batchLimit)
        .get();

      if (!retryEmailSnap.empty) {
        logger.info(`[ACCOUNT_DELETION_EMAIL_RETRY] Found ${retryEmailSnap.size} accounts needing permanent deletion email retry.`);
        for (const aDoc of retryEmailSnap.docs) {
          if (processedUids.has(aDoc.id)) continue;
          const aData = aDoc.data() || {};
          const retryEmail = aData.notificationEmail;
          if (retryEmail && !aData.permanentDeletionEmailSentAt) {
            try {
              const emailRes = await EmailService.sendPermanentDeletionEmail(retryEmail);
              if (emailRes.success) {
                await aDoc.ref.set(
                  {
                    permanentDeletionEmailSentAt: admin.firestore.FieldValue.serverTimestamp(),
                    permanentDeletionEmailPending: false,
                    notificationEmail: admin.firestore.FieldValue.delete(), // Minimizes personal data retention
                  },
                  { merge: true }
                );
                logger.info(`[ACCOUNT_DELETION_EMAIL_RETRY_SUCCESS] Sent permanent deletion email on retry for ${aDoc.id}`);
              }
            } catch (retryErr: any) {
              logger.warn(`[PERMANENT_DELETION_EMAIL_RETRY_FAILED] Email retry failed for ${aDoc.id}:`, retryErr.message || retryErr);
            }
          }
        }
      }
    } catch (retryQueryErr: any) {
      logger.warn("[ACCOUNT_DELETION_EMAIL_RETRY_QUERY_WARN] Error querying pending email audits:", retryQueryErr?.message || retryQueryErr);
    }

    return processedCount;
  }

  /**
   * Commits updates in batches of at most chunkSize (default 450) to prevent hitting Firestore 500-write limits.
   */
  private static async _batchUpdateInChunks(
    db: FirebaseFirestore.Firestore,
    operations: Array<{ ref: FirebaseFirestore.DocumentReference; data: Record<string, any> }>,
    chunkSize: number = 450
  ): Promise<void> {
    for (let i = 0; i < operations.length; i += chunkSize) {
      const chunk = operations.slice(i, i + chunkSize);
      const batch = db.batch();
      for (const op of chunk) {
        batch.update(op.ref, op.data);
      }
      await batch.commit();
    }
  }

  private static async _deleteSubcollection(collectionRef: FirebaseFirestore.CollectionReference): Promise<void> {
    const snap = await collectionRef.limit(100).get();
    if (snap.empty) return;

    const batch = collectionRef.firestore.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    if (snap.size >= 100) {
      await this._deleteSubcollection(collectionRef);
    }
  }

  public static _getMillis(val: any): number {
    if (!val) return 0;
    if (typeof val.toMillis === "function") return val.toMillis();
    if (typeof val.toDate === "function") return val.toDate().getTime();
    if (val instanceof Date) return val.getTime();
    return new Date(val).getTime();
  }
}

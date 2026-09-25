import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

/**
 * Immutable backend allowlist of authorized administrator accounts.
 * This list resides exclusively on the server.
 */
export const ADMIN_ALLOWLIST = [
  "pulucona@mail.com",
  "pulucona@gmail.com",
  "culucona@gmail.com",
] as const;

/**
 * Validates whether an email belongs to the administrator allowlist.
 * @param {string | null} [email] The email to validate.
 * @return {boolean} True if allowlisted.
 */
export function isAllowlistedAdminEmail(email?: string | null): boolean {
  if (!email) return false;
  const normalized = email.toLowerCase().trim();
  return ADMIN_ALLOWLIST.includes(normalized as typeof ADMIN_ALLOWLIST[number]);
}

/**
 * CALLABLE FUNCTION: Synchronizes admin claims for allowlisted accounts.
 */
export const syncAdminClaim = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "Authentication required to sync administrative claims."
    );
  }

  const uid = request.auth.uid;
  const callerEmail = (request.auth.token.email || "").toLowerCase().trim();

  // Strict allowlist validation using token email only
  if (!isAllowlistedAdminEmail(callerEmail)) {
    logger.warn(`[SYNC_ADMIN_DENIED] UID="${uid}" email="${callerEmail}"`);
    throw new HttpsError(
      "permission-denied",
      "Access denied: Caller email is not an authorized administrator."
    );
  }

  // Ensure email is verified
  if (request.auth.token.email_verified !== true) {
    logger.warn(`[SYNC_ADMIN_UNVERIFIED] Unverified email: "${callerEmail}"`);
    throw new HttpsError(
      "failed-precondition",
      "Administrator email must be verified before activation."
    );
  }

  try {
    const userRecord = await admin.auth().getUser(uid);
    const currentClaims = userRecord.customClaims || {};

    const updatedClaims = {
      ...currentClaims,
      admin: true,
    };

    await admin.auth().setCustomUserClaims(uid, updatedClaims);

    // Merge informational/UI metadata into Firestore
    await admin.firestore().collection("users").doc(uid).set({
      role: "admin",
      isAdmin: true,
      claimsSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    logger.info(`[SYNC_ADMIN_SUCCESS] Admin claim synced for "${callerEmail}"`);

    return {
      success: true,
      admin: true,
      email: callerEmail,
      uid,
      message: "Administrator claims synchronized successfully.",
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    logger.error(`[SYNC_ADMIN_ERROR] Failed for ${callerEmail}:`, err);
    throw new HttpsError(
      "internal",
      message || "Failed to synchronize administrator claims."
    );
  }
});

/**
 * CALLABLE FUNCTION: Returns backend-authorized capabilities and menu.
 */
export const getAdminCapabilities = onCall(async (request) => {
  // Authorization boundary: Require authentication AND custom claim admin === true
  if (!request.auth || request.auth.token.admin !== true) {
    const callerId = request.auth?.uid || "unauthenticated";
    logger.warn(`[ADMIN_CAPABILITIES_DENIED] Caller="${callerId}"`);
    throw new HttpsError(
      "permission-denied",
      "Access denied: Caller does not possess administrator privileges."
    );
  }

  logger.info(`[ADMIN_CAPABILITIES_SERVED] UID="${request.auth.uid}"`);

  return {
    authorized: true,
    role: "admin",
    adminUid: request.auth.uid,
    menu: [
      {
        id: "manual_ads",
        title: "Manual Ads",
        subtitle: "Manage manual advertisements",
        icon: "campaign_outlined",
        enabled: true,
      },
      {
        id: "news_articles",
        title: "News Articles",
        subtitle: "Manage Explore articles",
        icon: "explore_outlined",
        enabled: true,
      },
      {
        id: "materials",
        title: "Materials",
        subtitle: "Manage academic materials",
        icon: "menu_book_outlined",
        enabled: true,
      },
      {
        id: "users",
        title: "Users",
        subtitle: "Manage users and restrictions",
        icon: "people_outline",
        enabled: true,
      },
      {
        id: "vouchers",
        title: "Vouchers",
        subtitle: "Coming Soon",
        icon: "confirmation_number_outlined",
        enabled: false,
        badge: "Coming Soon",
      },
      {
        id: "notifications",
        title: "Notifications",
        subtitle: "Send targeted announcements",
        icon: "notifications_active_outlined",
        enabled: true,
      },
      {
        id: "admin_messages",
        title: "Admin Messages",
        subtitle: "Manage user conversations",
        icon: "chat_outlined",
        enabled: true,
      },
    ],
  };
});

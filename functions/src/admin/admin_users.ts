import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { isAllowlistedAdminEmail } from "./admin_capabilities";

function requireAdmin(request: any) {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError(
      "permission-denied",
      "Access denied: Caller does not possess administrator privileges."
    );
  }
}

export interface AdminUserSummary {
  uid: string;
  username: string;
  email: string;
  photoURL: string | null;
  institution: string;
  program: string;
  programCode: string;
  year: string;
  semester: string;
  phone: string;
  createdAt: string | null;
  lastLogin: string | null;
  emailVerified: boolean;
  disabled: boolean;
  isAdmin: boolean;
  hasActiveSubscription: boolean;
}

/**
 * CALLABLE FUNCTION: Returns a paginated and filterable list of registered users.
 */
export const getAdminUsersList = onCall(async (request) => {
  requireAdmin(request);
  const db = admin.firestore();

  const data = request.data || {};
  const requestedPageSize = typeof data.pageSize === "number" ? data.pageSize : 25;
  const pageSize = Math.min(Math.max(requestedPageSize, 5), 100);
  const pageToken = typeof data.pageToken === "string" ? data.pageToken : null;
  const searchQuery = typeof data.searchQuery === "string" ? data.searchQuery.trim().toLowerCase() : "";
  const roleFilter = typeof data.roleFilter === "string" ? data.roleFilter.trim().toLowerCase() : "all";

  try {
    // 1. Fetch user profile documents from Firestore
    let query: FirebaseFirestore.Query = db.collection("users");

    // Order by createdAt desc if no specific search query
    query = query.orderBy("createdAt", "desc").limit(pageSize * 3); // Overfetch slightly to allow client-side role filtering

    if (pageToken) {
      const startDoc = await db.collection("users").doc(pageToken).get();
      if (startDoc.exists) {
        query = query.startAfter(startDoc);
      }
    }

    const snapshot = await query.get();
    const docs = snapshot.docs;

    if (docs.length === 0) {
      return {
        success: true,
        users: [],
        nextPageToken: null,
        totalEstimated: 0,
      };
    }

    // 2. Extract UIDs to fetch corresponding Firebase Auth metadata in batch
    const uids = docs.map((d) => d.id);
    const authMap = new Map<string, admin.auth.UserRecord>();

    try {
      // admin.auth().getUsers takes an array of { uid: string }
      const authResult = await admin.auth().getUsers(uids.map((uid) => ({ uid })));
      for (const authUser of authResult.users) {
        authMap.set(authUser.uid, authUser);
      }
    } catch (authErr) {
      logger.warn("[GET_ADMIN_USERS_AUTH_WARN] Batch auth fetch failed:", authErr);
    }

    // 3. Check active subscriptions in parallel for these users
    const activeSubMap = new Map<string, boolean>();
    const now = new Date();
    await Promise.all(
      uids.map(async (uid) => {
        try {
          const subSnap = await db
            .collection("subscriptions")
            .doc(uid)
            .collection("history")
            .where("status", "==", "active")
            .get();
          
          let hasActive = false;
          for (const sDoc of subSnap.docs) {
            const exp = sDoc.data().expiryDate;
            const expDate = exp?.toDate ? exp.toDate() : (exp ? new Date(exp) : null);
            if (expDate && expDate > now) {
              hasActive = true;
              break;
            }
          }
          activeSubMap.set(uid, hasActive);
        } catch (_) {
          activeSubMap.set(uid, false);
        }
      })
    );

    // 4. Construct user summaries and filter
    const summaries: AdminUserSummary[] = [];

    for (const doc of docs) {
      const uData = doc.data();
      const authUser = authMap.get(doc.id);

      const username = String(uData.username || authUser?.displayName || "User").trim();
      const email = String(uData.email || authUser?.email || "").trim();
      const phone = String(uData.phone || authUser?.phoneNumber || "").trim();
      const program = String(uData.program || "").trim();
      const programCode = String(uData.programCode || "").trim();
      const institution = String(uData.institution || "").trim();
      const year = String(uData.year || "").trim();
      const semester = String(uData.semester || "").trim();
      const disabled = authUser?.disabled === true || uData.disabled === true;
      const isAdmin = authUser?.customClaims?.admin === true || uData.role === "admin" || uData.isAdmin === true;
      const hasActiveSubscription = activeSubMap.get(doc.id) === true;

      // Text search matching
      if (searchQuery.length > 0) {
        const matchesUsername = username.toLowerCase().includes(searchQuery);
        const matchesEmail = email.toLowerCase().includes(searchQuery);
        const matchesPhone = phone.toLowerCase().includes(searchQuery);
        const matchesProgram = program.toLowerCase().includes(searchQuery) || programCode.toLowerCase().includes(searchQuery);
        const matchesUid = doc.id.toLowerCase().includes(searchQuery);

        if (!matchesUsername && !matchesEmail && !matchesPhone && !matchesProgram && !matchesUid) {
          continue;
        }
      }

      // Role filter matching
      if (roleFilter === "active_subscribers" && !hasActiveSubscription) continue;
      if (roleFilter === "admins" && !isAdmin) continue;
      if (roleFilter === "disabled" && !disabled) continue;

      const createdAt = authUser?.metadata?.creationTime
        ? new Date(authUser.metadata.creationTime).toISOString()
        : uData.createdAt?.toDate
        ? uData.createdAt.toDate().toISOString()
        : null;

      const lastLogin = uData.lastLogin?.toDate
        ? uData.lastLogin.toDate().toISOString()
        : authUser?.metadata?.lastSignInTime
        ? new Date(authUser.metadata.lastSignInTime).toISOString()
        : null;

      summaries.push({
        uid: doc.id,
        username,
        email,
        photoURL: uData.photoURL || authUser?.photoURL || null,
        institution,
        program,
        programCode,
        year,
        semester,
        phone,
        createdAt,
        lastLogin,
        emailVerified: authUser?.emailVerified ?? uData.emailVerified ?? false,
        disabled,
        isAdmin,
        hasActiveSubscription,
      });

      if (summaries.length >= pageSize) {
        break;
      }
    }

    const lastDoc = docs[docs.length - 1];
    const nextPageToken = docs.length >= pageSize && lastDoc ? lastDoc.id : null;

    logger.info(`[ADMIN_USERS_LIST] Returning ${summaries.length} users (pageSize=${pageSize})`);

    return {
      success: true,
      users: summaries,
      nextPageToken,
      totalEstimated: summaries.length,
    };
  } catch (err: any) {
    logger.error("[GET_ADMIN_USERS_LIST_ERROR] Failed:", err);
    throw new HttpsError("internal", err.message || "Failed to retrieve users list.");
  }
});

/**
 * CALLABLE FUNCTION: Aggregates complete administrative details, subscription history,
 * safe payment logs, and uploaded material history for a specific user.
 */
export const getAdminUserDetail = onCall(async (request) => {
  requireAdmin(request);
  const db = admin.firestore();

  const { targetUid } = request.data || {};
  if (!targetUid || typeof targetUid !== "string" || targetUid.trim().length === 0) {
    throw new HttpsError("invalid-argument", "Missing required targetUid parameter.");
  }

  const cleanUid = targetUid.trim();

  try {
    // 1. Fetch Firebase Auth record
    let authUser: admin.auth.UserRecord | null = null;
    try {
      authUser = await admin.auth().getUser(cleanUid);
    } catch (e: any) {
      if (e.code !== "auth/user-not-found") {
        logger.warn(`[GET_USER_DETAIL_AUTH_WARN] ${cleanUid}:`, e);
      }
    }

    // 2. Fetch Firestore /users/{targetUid} document
    const userDocRef = db.collection("users").doc(cleanUid);
    const userSnap = await userDocRef.get();
    const uData = userSnap.exists ? userSnap.data() || {} : {};

    // 3. Fetch device sessions from /users/{targetUid}/sessions
    const sessionsSnap = await userDocRef.collection("sessions").get();
    const sessions = sessionsSnap.docs.map((d) => {
      const sData = d.data();
      return {
        deviceId: d.id,
        platform: sData.platform || "Unknown",
        isActive: sData.isActive === true,
        lastLogin: sData.lastLogin?.toDate ? sData.lastLogin.toDate().toISOString() : null,
      };
    });

    // 4. Fetch subscription history from /subscriptions/{targetUid}/history
    const subSnap = await db.collection("subscriptions").doc(cleanUid).collection("history").get();
    const subscriptions = subSnap.docs.map((d) => {
      const s = d.data();
      return {
        id: d.id,
        packageTitle: s.packageTitle || "Pass",
        amount: Number(s.amount || 0),
        transactionCode: s.transactionCode || "",
        paystackReference: s.paystackReference || null,
        paymentChannel: s.paymentChannel || null,
        operatorReceiptNumber: s.operatorReceiptNumber || null,
        purchaseDate: s.purchaseDate?.toDate ? s.purchaseDate.toDate().toISOString() : (s.purchaseDate || null),
        activationDate: s.activationDate?.toDate ? s.activationDate.toDate().toISOString() : (s.activationDate || null),
        expiryDate: s.expiryDate?.toDate ? s.expiryDate.toDate().toISOString() : (s.expiryDate || null),
        status: s.status || "active",
        downloadCount: Number(s.downloadCount || 0),
      };
    });

    // Sort subscriptions newest purchase date first
    subscriptions.sort((a, b) => {
      const dateA = a.purchaseDate ? new Date(a.purchaseDate).getTime() : 0;
      const dateB = b.purchaseDate ? new Date(b.purchaseDate).getTime() : 0;
      return dateB - dateA;
    });

    // 5. Fetch safe payment records from /payments
    let payments: any[] = [];
    try {
      const paySnap = await db
        .collection("payments")
        .where("userId", "==", cleanUid)
        .limit(30)
        .get();

      payments = paySnap.docs.map((d) => {
        const p = d.data();
        let maskedPhone = p.phoneNumber;
        if (typeof maskedPhone === "string" && maskedPhone.length > 6) {
          maskedPhone = maskedPhone.slice(0, 7) + "***";
        }

        return {
          reference: d.id,
          packageName: p.packageName || "Subscription",
          expectedAmountKes: Number(p.expectedAmountKes || 0),
          paymentMethod: p.paymentMethod || "mobile_money",
          phoneNumber: maskedPhone || null,
          status: p.status || "pending",
          fulfilled: p.fulfilled === true,
          failureReason: p.failureReason || p.errorMessage || null,
          operatorReceiptNumber: p.operatorReceiptNumber || null,
          createdAt: p.createdAt?.toDate ? p.createdAt.toDate().toISOString() : null,
          updatedAt: p.updatedAt?.toDate ? p.updatedAt.toDate().toISOString() : null,
        };
      });

      // Sort payments newest first
      payments.sort((a, b) => {
        const dateA = a.createdAt ? new Date(a.createdAt).getTime() : 0;
        const dateB = b.createdAt ? new Date(b.createdAt).getTime() : 0;
        return dateB - dateA;
      });
    } catch (payErr) {
      logger.warn("[GET_USER_DETAIL_PAYMENTS_WARN] Error fetching payments:", payErr);
    }

    // 6. Fetch uploaded materials from /resources
    const matSnap = await db.collection("resources").where("uploaderId", "==", cleanUid).get();
    let totalUploads = matSnap.size;
    let approvedCount = 0;
    let pendingCount = 0;
    let rejectedCount = 0;
    let modifiedCount = 0;
    let archivedCount = 0;
    let totalViews = 0;
    let totalLikes = 0;
    let totalComments = 0;

    const materials = matSnap.docs.map((d) => {
      const m = d.data();
      const status = String(m.status || m.verificationStatus || "pending").toLowerCase();

      if (status === "approved") approvedCount++;
      else if (status === "pending" || status === "waiting") pendingCount++;
      else if (status === "rejected" || status === "declined") rejectedCount++;
      else if (status === "modified") modifiedCount++;
      else if (status === "archived" || status === "trash") archivedCount++;

      totalViews += Number(m.views || 0);
      totalLikes += Number(m.likes || 0);
      totalComments += Number(m.comments || 0);

      return {
        id: d.id,
        title: m.title || "Academic Resource",
        fileName: m.fileName || "",
        type: m.type || "Notes",
        unitName: m.unitName || "",
        unitCode: m.unitCode || "",
        materialFormat: m.materialFormat || "PDF",
        uploadDate: m.uploadDate?.toDate ? m.uploadDate.toDate().toISOString() : (m.uploadDate || null),
        status: m.status || m.verificationStatus || "pending",
        approvedAt: m.approvedAt?.toDate ? m.approvedAt.toDate().toISOString() : null,
        rejectedAt: m.rejectedAt?.toDate ? m.rejectedAt.toDate().toISOString() : null,
        declineReason: m.declineReason || null,
        rejectionReasons: Array.isArray(m.rejectionReasons) ? m.rejectionReasons : null,
        adminRemark: m.adminRemark || null,
        views: Number(m.views || 0),
        likes: Number(m.likes || 0),
        comments: Number(m.comments || 0),
        thumbnailUrl: m.thumbnailUrl || null,
        isAnonymous: m.isAnonymous === true,
      };
    });

    // Sort materials newest upload date first
    materials.sort((a, b) => {
      const dateA = a.uploadDate ? new Date(a.uploadDate).getTime() : 0;
      const dateB = b.uploadDate ? new Date(b.uploadDate).getTime() : 0;
      return dateB - dateA;
    });

    const createdAt = authUser?.metadata?.creationTime
      ? new Date(authUser.metadata.creationTime).toISOString()
      : uData.createdAt?.toDate
      ? uData.createdAt.toDate().toISOString()
      : null;

    const lastLogin = uData.lastLogin?.toDate
      ? uData.lastLogin.toDate().toISOString()
      : authUser?.metadata?.lastSignInTime
      ? new Date(authUser.metadata.lastSignInTime).toISOString()
      : null;

    const disabled = authUser?.disabled === true || uData.disabled === true;
    const isAdmin = authUser?.customClaims?.admin === true || uData.role === "admin" || uData.isAdmin === true;

    return {
      success: true,
      user: {
        uid: cleanUid,
        username: uData.username || authUser?.displayName || "User",
        email: uData.email || authUser?.email || "",
        photoURL: uData.photoURL || authUser?.photoURL || null,
        institution: uData.institution || "",
        universityLocation: uData.universityLocation || "",
        program: uData.program || "",
        programCode: uData.programCode || "",
        year: uData.year || "",
        semester: uData.semester || "",
        phone: uData.phone || authUser?.phoneNumber || "",
        authProvider: uData.authProvider || (authUser?.providerData?.[0]?.providerId === "google.com" ? "google" : "email"),
        emailVerified: authUser?.emailVerified ?? uData.emailVerified ?? false,
        onboardingComplete: uData.onboardingComplete === true,
        disabled,
        isAdmin,
        createdAt,
        joinDate: uData.joinDate || null,
        lastLogin,
        activeDeviceId: uData.activeDeviceId || null,
      },
      sessions,
      subscriptions,
      payments,
      materialsSummary: {
        totalUploads,
        approvedCount,
        pendingCount,
        rejectedCount,
        modifiedCount,
        archivedCount,
        totalViews,
        totalLikes,
        totalComments,
      },
      materials,
    };
  } catch (err: any) {
    logger.error(`[GET_ADMIN_USER_DETAIL_ERROR] Failed for ${cleanUid}:`, err);
    throw new HttpsError("internal", err.message || "Failed to retrieve user details.");
  }
});

/**
 * CALLABLE FUNCTION: Toggles account disabled state in Firebase Authentication and Firestore.
 * Strictly protected against self-disabling and disabling super-administrators.
 */
export const toggleAdminUserDisabled = onCall(async (request) => {
  requireAdmin(request);
  const db = admin.firestore();
  const callerUid = request.auth?.uid;

  const { targetUid, disabled } = request.data || {};
  if (!targetUid || typeof targetUid !== "string" || targetUid.trim().length === 0) {
    throw new HttpsError("invalid-argument", "Missing required targetUid parameter.");
  }
  if (typeof disabled !== "boolean") {
    throw new HttpsError("invalid-argument", "disabled parameter must be a boolean.");
  }

  const cleanUid = targetUid.trim();

  // Self-disable guard
  if (callerUid === cleanUid) {
    throw new HttpsError("failed-precondition", "Administrators cannot disable their own account.");
  }

  // Allowlisted super-admin guard
  try {
    const targetUser = await admin.auth().getUser(cleanUid);
    if (isAllowlistedAdminEmail(targetUser.email)) {
      throw new HttpsError("failed-precondition", "Allowlisted super administrators cannot be disabled.");
    }
  } catch (err: any) {
    if (err instanceof HttpsError) throw err;
  }

  try {
    // 1. Update Firebase Authentication disabled flag
    await admin.auth().updateUser(cleanUid, { disabled });

    // 2. Record audit trail in Firestore /users/{targetUid}
    await db.collection("users").doc(cleanUid).set(
      {
        disabled,
        disabledAt: admin.firestore.FieldValue.serverTimestamp(),
        disabledBy: callerUid || null,
      },
      { merge: true }
    );

    logger.info(`[ADMIN_USER_DISABLED_TOGGLE] Caller ${callerUid} set disabled=${disabled} for target ${cleanUid}`);

    return {
      success: true,
      targetUid: cleanUid,
      disabled,
      message: disabled ? "User account has been disabled." : "User account has been enabled.",
    };
  } catch (err: any) {
    logger.error(`[TOGGLE_USER_DISABLED_ERROR] Failed for ${cleanUid}:`, err);
    throw new HttpsError("internal", err.message || "Failed to update user account status.");
  }
});

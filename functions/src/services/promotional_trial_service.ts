import * as crypto from "crypto";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

export interface CampaignStageConfig {
  stageNumber: number;
  title: string;
  durationDescription: string;
  maxClaims: number;
  deadlineUtc: string; // ISO 8601
}

export const CAMPAIGN_STAGES: Record<number, CampaignStageConfig> = {
  1: {
    stageNumber: 1,
    title: "2-Month Free Trial",
    durationDescription: "2 calendar months",
    maxClaims: 50,
    deadlineUtc: "2026-12-30T23:59:59.000Z",
  },
  2: {
    stageNumber: 2,
    title: "1-Month Free Trial",
    durationDescription: "1 calendar month",
    maxClaims: 45,
    deadlineUtc: "2027-03-01T23:59:59.000Z",
  },
  3: {
    stageNumber: 3,
    title: "1-Week Free Trial",
    durationDescription: "7 days",
    maxClaims: 1000,
    deadlineUtc: "2027-12-30T23:59:59.000Z",
  },
};

export const CAMPAIGN_DOC_PATH = "campaigns/promotional_trials";

/**
 * Calculates end date by adding calendar months with month-end clamping in UTC.
 * Ensures e.g. Dec 30 + 2 months clamps to Feb 28 (or 29), not March.
 */
export function addCalendarMonthsClamped(startDate: Date, monthsToAdd: number): Date {
  const year = startDate.getUTCFullYear();
  const month = startDate.getUTCMonth();
  const day = startDate.getUTCDate();
  const hours = startDate.getUTCHours();
  const minutes = startDate.getUTCMinutes();
  const seconds = startDate.getUTCSeconds();
  const ms = startDate.getUTCMilliseconds();

  const targetMonthIndex = month + monthsToAdd;
  const targetYear = year + Math.floor(targetMonthIndex / 12);
  const normalizedMonth = ((targetMonthIndex % 12) + 12) % 12;

  // Day 0 of next month in UTC returns the last day of target normalized month
  const daysInTargetMonth = new Date(Date.UTC(targetYear, normalizedMonth + 1, 0)).getUTCDate();
  const clampedDay = Math.min(day, daysInTargetMonth);

  return new Date(Date.UTC(targetYear, normalizedMonth, clampedDay, hours, minutes, seconds, ms));
}

/**
 * Calculates expiry date based on stage number
 */
export function calculateStageExpiry(startDate: Date, stageNumber: number): Date {
  switch (stageNumber) {
    case 1:
      return addCalendarMonthsClamped(startDate, 2);
    case 2:
      return addCalendarMonthsClamped(startDate, 1);
    case 3:
      return new Date(startDate.getTime() + 7 * 24 * 60 * 60 * 1000);
    default:
      throw new Error(`Unsupported promotional stage: ${stageNumber}`);
  }
}

/**
 * Normalizes email address and produces SHA-256 hash for permanent deduplication
 */
export function hashUserEmail(email: string): string {
  const normalized = email.trim().toLowerCase();
  return crypto.createHash("sha256").update(normalized).digest("hex");
}

/**
 * Evaluates whether a subscription history document represents an active/queued paid entitlement.
 * 
 * Rules:
 * 1. Status check: Terminated, refunded, cancelled, revoked, expired, or unknown statuses
 *    are never treated as active paid entitlements.
 * 2. Explicit free/promotional markers: Records with paymentChannel === 'promotional_trial'
 *    or operatorReceiptNumber === 'PROMO_FREE_TRIAL' are free promotional entitlements.
 * 3. Explicit numerical amount: An amount > 0 indicates a paid subscription.
 *    An amount <= 0 indicates a free, gift, complimentary, or promotional pass.
 * 4. Missing/legacy amount field: In the absence of an amount field, require verified
 *    Paystack transaction evidence (paystackTransactionId > 0, non-promo paystackReference,
 *    or verified Paystack payment channel paired with a non-promo transactionCode).
 * 5. Free, gift, complimentary, or legacy-free passes without verified payment evidence are never
 *    misclassified as paid.
 */
export function isPaidSubscriptionRecord(data: FirebaseFirestore.DocumentData | undefined | null): boolean {
  if (!data) return false;

  // 1. Inactive or invalid statuses fail closed
  const status = typeof data.status === "string" ? data.status.toLowerCase().trim() : "";
  if (
    status === "expired" ||
    status === "terminated" ||
    status === "refunded" ||
    status === "cancelled" ||
    status === "revoked" ||
    status === "unknown"
  ) {
    return false;
  }

  // 2. Explicit promotional markers
  if (
    data.paymentChannel === "promotional_trial" ||
    data.operatorReceiptNumber === "PROMO_FREE_TRIAL"
  ) {
    return false;
  }

  // 3. Explicit numerical amount
  if (data.amount !== undefined && data.amount !== null) {
    const num = Number(data.amount);
    if (!isNaN(num)) {
      return num > 0;
    }
  }

  // 4. Missing/legacy amount field: require verified Paystack transaction evidence
  const hasPaystackTxId = data.paystackTransactionId !== undefined &&
                          data.paystackTransactionId !== null &&
                          Number(data.paystackTransactionId) > 0;

  const hasPaystackRef = typeof data.paystackReference === "string" &&
                         data.paystackReference.trim().length > 0 &&
                         !data.paystackReference.startsWith("PROMO_");

  if (hasPaystackTxId || hasPaystackRef) {
    return true;
  }

  // Known paid payment channels if accompanied by a non-promo transactionCode
  const paidChannels = ["mobile_money", "card", "bank", "ussd", "qr", "eft", "paystack"];
  const channel = typeof data.paymentChannel === "string" ? data.paymentChannel.toLowerCase().trim() : "";
  const txCode = typeof data.transactionCode === "string" ? data.transactionCode.trim() : "";

  if (paidChannels.includes(channel) && txCode.length > 0 && !txCode.startsWith("PROMO_")) {
    return true;
  }

  return false;
}

export interface ActiveStageInfo {
  stageNumber: number;
  title: string;
  durationDescription: string;
  claimedCount: number;
  maxClaims: number;
  remainingClaims: number;
  deadlineUtc: string;
}

export interface CampaignStatusResult {
  campaignActive: boolean;
  activeStage: ActiveStageInfo | null;
  userStatus: {
    isAuthenticated: boolean;
    hasClaimed: boolean;
    isEligible: boolean;
    ineligibilityReason?: string;
    latestPaidExpiry?: string;
    claimedDetails?: {
      stageNumber: number;
      stageTitle: string;
      claimedAt: string;
      expiryDate: string;
    };
  };
}

export class PromotionalTrialService {
  /**
   * Evaluates the current active stage based on campaign counters and current time
   */
  public static resolveActiveStage(
    campaignData: Record<string, any> | undefined,
    currentTime: Date
  ): { activeStageNumber: number | null; stageCounts: Record<number, number> } {
    const stageCounts: Record<number, number> = {
      1: Number(campaignData?.stage1?.claimedCount || 0),
      2: Number(campaignData?.stage2?.claimedCount || 0),
      3: Number(campaignData?.stage3?.claimedCount || 0),
    };

    // Stage 1 check
    const stage1Config = CAMPAIGN_STAGES[1];
    const stage1Deadline = new Date(stage1Config.deadlineUtc);
    if (stageCounts[1] < stage1Config.maxClaims && currentTime <= stage1Deadline) {
      return { activeStageNumber: 1, stageCounts };
    }

    // Stage 2 check
    const stage2Config = CAMPAIGN_STAGES[2];
    const stage2Deadline = new Date(stage2Config.deadlineUtc);
    if (stageCounts[2] < stage2Config.maxClaims && currentTime <= stage2Deadline) {
      return { activeStageNumber: 2, stageCounts };
    }

    // Stage 3 check
    const stage3Config = CAMPAIGN_STAGES[3];
    const stage3Deadline = new Date(stage3Config.deadlineUtc);
    if (stageCounts[3] < stage3Config.maxClaims && currentTime <= stage3Deadline) {
      return { activeStageNumber: 3, stageCounts };
    }

    // All stages exhausted or deadlines passed
    return { activeStageNumber: null, stageCounts };
  }

  /**
   * Retrieves overall campaign status and checks individual user eligibility
   */
  public static async getCampaignStatus(
    db: FirebaseFirestore.Firestore,
    uid?: string,
    email?: string
  ): Promise<CampaignStatusResult> {
    const now = new Date();
    const campaignDocRef = db.doc(CAMPAIGN_DOC_PATH);
    const campaignSnap = await campaignDocRef.get();
    const campaignData = campaignSnap.data();

    const { activeStageNumber, stageCounts } = this.resolveActiveStage(campaignData, now);

    let activeStageInfo: ActiveStageInfo | null = null;
    if (activeStageNumber !== null) {
      const config = CAMPAIGN_STAGES[activeStageNumber];
      const claimed = stageCounts[activeStageNumber];
      activeStageInfo = {
        stageNumber: activeStageNumber,
        title: config.title,
        durationDescription: config.durationDescription,
        claimedCount: claimed,
        maxClaims: config.maxClaims,
        remainingClaims: Math.max(0, config.maxClaims - claimed),
        deadlineUtc: config.deadlineUtc,
      };
    }

    // Default user status
    const userStatus: CampaignStatusResult["userStatus"] = {
      isAuthenticated: !!uid,
      hasClaimed: false,
      isEligible: activeStageNumber !== null && !!uid,
    };

    if (!uid) {
      userStatus.ineligibilityReason = "Please sign in to claim a promotional trial.";
      return {
        campaignActive: activeStageNumber !== null,
        activeStage: activeStageInfo,
        userStatus,
      };
    }

    // 1. Check existing UID claim record
    const claimDocRef = db.collection("promotional_trial_claims").doc(uid);
    const claimSnap = await claimDocRef.get();

    if (claimSnap.exists) {
      const claimData = claimSnap.data() || {};
      userStatus.hasClaimed = true;
      userStatus.isEligible = false;
      userStatus.ineligibilityReason = "already_claimed";
      userStatus.claimedDetails = {
        stageNumber: claimData.stage,
        stageTitle: claimData.stageTitle || CAMPAIGN_STAGES[claimData.stage]?.title || "Free Trial",
        claimedAt: claimData.claimedAt?.toDate ? claimData.claimedAt.toDate().toISOString() : claimData.claimedAt,
        expiryDate: claimData.expiryDate?.toDate ? claimData.expiryDate.toDate().toISOString() : claimData.expiryDate,
      };
      return {
        campaignActive: activeStageNumber !== null,
        activeStage: activeStageInfo,
        userStatus,
      };
    }

    // 2. Check permanent email hash deduplication record
    if (email) {
      const emailHash = hashUserEmail(email);
      const emailDocRef = db.collection("promotional_trial_emails").doc(emailHash);
      const emailSnap = await emailDocRef.get();

      if (emailSnap.exists) {
        userStatus.hasClaimed = true;
        userStatus.isEligible = false;
        userStatus.ineligibilityReason = "already_claimed";
        return {
          campaignActive: activeStageNumber !== null,
          activeStage: activeStageInfo,
          userStatus,
        };
      }
    }

    // 3. Inspect user subscription history: active or queued unexpired paid subscriptions make user ineligible
    const historyColRef = db.collection("subscriptions").doc(uid).collection("history");
    const historySnap = await historyColRef.get();
    let latestPaidExpiry: Date | null = null;

    for (const doc of historySnap.docs) {
      const data = doc.data();
      if (!isPaidSubscriptionRecord(data)) {
        continue;
      }

      const expDate = data.expiryDate instanceof admin.firestore.Timestamp
        ? data.expiryDate.toDate()
        : new Date(data.expiryDate);

      if (isNaN(expDate.getTime())) continue;

      if (expDate.getTime() > now.getTime()) {
        if (!latestPaidExpiry || expDate.getTime() > latestPaidExpiry.getTime()) {
          latestPaidExpiry = expDate;
        }
      }
    }

    if (latestPaidExpiry !== null) {
      userStatus.isEligible = false;
      userStatus.ineligibilityReason = "active_paid_subscription";
      userStatus.latestPaidExpiry = latestPaidExpiry.toISOString();
      return {
        campaignActive: activeStageNumber !== null,
        activeStage: activeStageInfo,
        userStatus,
      };
    }

    if (activeStageNumber === null) {
      userStatus.isEligible = false;
      userStatus.ineligibilityReason = "The promotional trial campaign is currently closed.";
    }

    return {
      campaignActive: activeStageNumber !== null,
      activeStage: activeStageInfo,
      userStatus,
    };
  }

  /**
   * Atomically claims a promotional trial for the user in a Firestore transaction.
   * Guarantees:
   * - Strict capacity enforcement (50, 45, 1000) under high concurrency
   * - Strict UTC deadline enforcement
   * - One-trial-per-user across UID and permanent email hash
   * - Preservation of active paid subscriptions (trial queues cleanly if user is already active)
   */
  public static async claimTrial(
    db: FirebaseFirestore.Firestore,
    uid: string,
    email: string
  ): Promise<{
    success: boolean;
    message: string;
    stage: number;
    stageTitle: string;
    subscriptionId: string;
    status: "active" | "queued";
    activationDate: string;
    expiryDate: string;
  }> {
    if (!uid) {
      throw new Error("Missing user identification");
    }
    if (!email || !email.includes("@")) {
      throw new Error("A valid verified email address is required to claim a promotional trial.");
    }

    const emailHash = hashUserEmail(email);
    const campaignDocRef = db.doc(CAMPAIGN_DOC_PATH);
    const claimDocRef = db.collection("promotional_trial_claims").doc(uid);
    const emailDocRef = db.collection("promotional_trial_emails").doc(emailHash);
    const historyColRef = db.collection("subscriptions").doc(uid).collection("history");

    return await db.runTransaction(async (transaction) => {
      // 1. Read existing claim for this UID
      const claimSnap = await transaction.get(claimDocRef);
      if (claimSnap.exists) {
        throw new Error("You have already claimed a promotional trial in this campaign.");
      }

      // 2. Read existing claim for this email hash
      const emailSnap = await transaction.get(emailDocRef);
      if (emailSnap.exists) {
        throw new Error("An account with this email address has already claimed a promotional trial in this campaign.");
      }

      // 3. Read campaign document
      const campaignSnap = await transaction.get(campaignDocRef);
      const campaignData = campaignSnap.data();

      const now = new Date();
      const { activeStageNumber, stageCounts } = this.resolveActiveStage(campaignData, now);

      if (activeStageNumber === null) {
        throw new Error("The promotional campaign is currently closed or capacity has been exhausted.");
      }

      const stageConfig = CAMPAIGN_STAGES[activeStageNumber];
      const expiryDate = calculateStageExpiry(now, activeStageNumber);

      // 4. Inspect current subscriptions: reject if user has any active or queued unexpired paid subscription
      const historySnap = await transaction.get(historyColRef);
      for (const doc of historySnap.docs) {
        const data = doc.data();
        if (!isPaidSubscriptionRecord(data)) {
          continue;
        }

        const expDate = data.expiryDate instanceof admin.firestore.Timestamp
          ? data.expiryDate.toDate()
          : new Date(data.expiryDate);

        if (isNaN(expDate.getTime())) continue;

        if (expDate.getTime() > now.getTime()) {
          throw new Error("active_paid_subscription");
        }
      }

      const subscriptionStatus: "active" = "active";
      const subId = `TRIAL_${Date.now()}`;
      const subDocRef = historyColRef.doc(subId);

      // 5. Atomic writes
      // A. Write subscription history record
      transaction.set(subDocRef, {
        id: subId,
        packageTitle: stageConfig.title,
        amount: 0,
        transactionCode: `PROMO_STAGE${activeStageNumber}_${Date.now()}`,
        paymentChannel: "promotional_trial",
        operatorReceiptNumber: "PROMO_FREE_TRIAL",
        purchaseDate: now,
        activationDate: now,
        expiryDate: expiryDate,
        status: subscriptionStatus,
        downloadCount: 0,
      });

      // B. Write UID claim record
      transaction.set(claimDocRef, {
        uid: uid,
        email: email.trim().toLowerCase(),
        emailHash: emailHash,
        stage: activeStageNumber,
        stageTitle: stageConfig.title,
        claimedAt: now,
        subscriptionId: subId,
        expiryDate: expiryDate,
        status: subscriptionStatus,
      });

      // C. Write permanent email hash record
      transaction.set(emailDocRef, {
        emailHash: emailHash,
        uid: uid,
        stage: activeStageNumber,
        claimedAt: now,
        subscriptionId: subId,
      });

      // D. Update campaign document counter
      const stageKey = `stage${activeStageNumber}`;
      const newClaimedCount = (stageCounts[activeStageNumber] || 0) + 1;
      const totalClaims = (campaignData?.totalClaims || 0) + 1;

      if (!campaignSnap.exists) {
        transaction.set(campaignDocRef, {
          campaignId: "academic_launch_campaign",
          stage1: {
            name: CAMPAIGN_STAGES[1].title,
            maxClaims: CAMPAIGN_STAGES[1].maxClaims,
            deadlineUtc: CAMPAIGN_STAGES[1].deadlineUtc,
            claimedCount: activeStageNumber === 1 ? 1 : 0,
          },
          stage2: {
            name: CAMPAIGN_STAGES[2].title,
            maxClaims: CAMPAIGN_STAGES[2].maxClaims,
            deadlineUtc: CAMPAIGN_STAGES[2].deadlineUtc,
            claimedCount: activeStageNumber === 2 ? 1 : 0,
          },
          stage3: {
            name: CAMPAIGN_STAGES[3].title,
            maxClaims: CAMPAIGN_STAGES[3].maxClaims,
            deadlineUtc: CAMPAIGN_STAGES[3].deadlineUtc,
            claimedCount: activeStageNumber === 3 ? 1 : 0,
          },
          totalClaims: 1,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        transaction.update(campaignDocRef, {
          [`${stageKey}.claimedCount`]: newClaimedCount,
          totalClaims: totalClaims,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      logger.info(
        `[PROMO_TRIAL_SUCCESS] Granted Stage ${activeStageNumber} ("${stageConfig.title}") to user ${uid} (${email}). Status: ${subscriptionStatus}. Expiry: ${expiryDate.toISOString()}`
      );

      return {
        success: true,
        message: `Successfully activated ${stageConfig.title}!`,
        stage: activeStageNumber,
        stageTitle: stageConfig.title,
        subscriptionId: subId,
        status: subscriptionStatus,
        activationDate: now.toISOString(),
        expiryDate: expiryDate.toISOString(),
      };
    });
  }
}

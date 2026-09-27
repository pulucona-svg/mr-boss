import * as crypto from "crypto";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

export interface AuthoritativePackage {
  id: string;
  title: string;
  priceKes: number;
  amountSubunits: number;
  durationDays: number;
}

/**
 * Authoritative Server-Side Package Catalog.
 * 100% synchronized with existing SubscriptionScreen & SubscriptionService.
 * KES amounts are strictly in cents (subunits: 1 KES = 100 cents).
 */
export const AUTHORITATIVE_PACKAGES: Record<string, AuthoritativePackage> = {
  daily: {
    id: "daily",
    title: "Daily Pass",
    priceKes: 5,
    amountSubunits: 500,
    durationDays: 1,
  },
  weekly: {
    id: "weekly",
    title: "Weekly Pass",
    priceKes: 30,
    amountSubunits: 3000,
    durationDays: 7,
  },
  monthly: {
    id: "monthly",
    title: "Monthly Pass",
    priceKes: 100,
    amountSubunits: 10000,
    durationDays: 30,
  },
  semester: {
    id: "semester",
    title: "Semester Pass",
    priceKes: 300,
    amountSubunits: 30000,
    durationDays: 120,
  },
  yearly: {
    id: "yearly",
    title: "Yearly Pass",
    priceKes: 500,
    amountSubunits: 50000,
    durationDays: 365,
  },
};

export function getPaystackSecretKey(): string {
  const key = process.env.PAYSTACK_SECRET_KEY || "";
  if (!key) {
    throw new Error("Paystack secret key is not configured in backend environment");
  }
  return key;
}

/**
 * Normalizes Kenyan MSISDNs to international format (+254XXXXXXXXX) required by Paystack
 */
export function normalizeKenyanPhone(phone: string): string {
  let cleaned = phone.replace(/[\s-]/g, "").trim();
  if (cleaned.startsWith("+254")) {
    return cleaned;
  }
  if (cleaned.startsWith("254")) {
    return `+${cleaned}`;
  }
  if (cleaned.startsWith("0")) {
    return `+254${cleaned.substring(1)}`;
  }
  if (cleaned.startsWith("7") || cleaned.startsWith("1")) {
    return `+254${cleaned}`;
  }
  return cleaned;
}

/**
 * Verifies Paystack HMAC SHA-512 webhook signature against raw request body
 */
export function verifyPaystackSignature(rawBody: Buffer | string, signature: string): boolean {
  if (!signature) return false;
  const secretKey = getPaystackSecretKey();
  const computedHash = crypto
    .createHmac("sha512", secretKey)
    .update(rawBody)
    .digest("hex");
  return computedHash === signature;
}

export interface PaystackInitResult {
  success: boolean;
  paystackStatus: string;
  reference: string;
  displayText?: string;
  message?: string;
  authorizationUrl?: string;
  accessCode?: string;
  rawResponse?: any;
}

/**
 * Initializes or charges a payment transaction through Paystack API
 */
export async function initializePaymentOnPaystack(params: {
  packageId: string;
  paymentMethod: "mpesa" | "airtelMoney" | "mastercard";
  phoneNumber?: string;
  userEmail: string;
  userId: string;
  reference: string;
}): Promise<PaystackInitResult> {
  const pkg = AUTHORITATIVE_PACKAGES[params.packageId];
  if (!pkg) {
    throw new Error(`Invalid package identifier: ${params.packageId}`);
  }

  // Enforce minimum KES 100 for card payments
  if (params.paymentMethod === "mastercard" && pkg.priceKes < 100) {
    throw new Error("Card payment does not support payments below Ksh.100.");
  }

  const secretKey = getPaystackSecretKey();
  const safeEmail = params.userEmail?.trim() || "customer@mirrorlaikipia.app";

  if (params.paymentMethod === "mpesa" || params.paymentMethod === "airtelMoney") {
    if (!params.phoneNumber) {
      throw new Error("Phone number is required for mobile money payments");
    }
    const normalizedPhone = normalizeKenyanPhone(params.phoneNumber);
    const provider = params.paymentMethod === "mpesa" ? "mpesa" : "atl";

    const payload = {
      email: safeEmail,
      amount: pkg.amountSubunits,
      currency: "KES",
      reference: params.reference,
      metadata: {
        userId: params.userId,
        packageId: pkg.id,
        packageName: pkg.title,
        paymentMethod: params.paymentMethod,
        internalReference: params.reference,
      },
      mobile_money: {
        phone: normalizedPhone,
        provider: provider,
      },
    };

    const response = await fetch("https://api.paystack.co/charge", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${secretKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const data: any = await response.json();
    logger.info(`[PAYSTACK_CHARGE_RESPONSE] Method=${params.paymentMethod}, Status=${data?.status}, Message=${data?.message}`);

    const isSuccess = data?.status === true;
    const paystackStatus = data?.data?.status || (isSuccess ? "pay_offline" : "failed");
    const displayText = data?.data?.display_text || (isSuccess ? "Please complete the authorization on your phone." : (data?.message || "Charge initiation failed"));
    const message = data?.message || displayText;

    return {
      success: isSuccess,
      paystackStatus,
      reference: params.reference,
      displayText,
      message,
      rawResponse: data,
    };
  } else {
    // Mastercard / Card payment initialization
    const payload = {
      email: safeEmail,
      amount: pkg.amountSubunits,
      currency: "KES",
      reference: params.reference,
      channels: ["card"],
      metadata: {
        userId: params.userId,
        packageId: pkg.id,
        packageName: pkg.title,
        paymentMethod: "mastercard",
        internalReference: params.reference,
      },
    };

    const response = await fetch("https://api.paystack.co/transaction/initialize", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${secretKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const data: any = await response.json();
    logger.info(`[PAYSTACK_INIT_CARD_RESPONSE] Status=${data?.status}, Message=${data?.message}`);

    if (data?.status !== true || !data?.data) {
      return {
        success: false,
        paystackStatus: "failed",
        reference: params.reference,
        message: data?.message || "Failed to initialize Paystack card transaction",
        rawResponse: data,
      };
    }

    return {
      success: true,
      paystackStatus: "initialized",
      reference: params.reference,
      authorizationUrl: data.data.authorization_url,
      accessCode: data.data.access_code,
      message: "Card transaction initialized",
      rawResponse: data,
    };
  }
}

/**
 * Server-side verification with Paystack API
 */
export async function verifyTransactionWithPaystack(reference: string): Promise<any> {
  const secretKey = getPaystackSecretKey();
  const response = await fetch(`https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`, {
    method: "GET",
    headers: {
      "Authorization": `Bearer ${secretKey}`,
    },
  });

  const data: any = await response.json();
  return data;
}

export interface FulfillResult {
  success: boolean;
  status: string;
  paystackStatus?: string;
  message: string;
  displayText?: string;
  isPending?: boolean;
  alreadyFulfilled?: boolean;
}

/**
 * Idempotently fulfills a verified transaction and activates the existing subscription
 */
export async function fulfillSubscription(
  db: FirebaseFirestore.Firestore,
  reference: string,
  source: "webhook" | "verify"
): Promise<FulfillResult> {
  const paymentRef = db.collection("payments").doc(reference);
  const paymentSnap = await paymentRef.get();

  if (!paymentSnap.exists) {
    logger.error(`[FULFILL_ERROR] Payment record not found for reference: ${reference}`);
    return { success: false, status: "not_found", message: "Payment record not found" };
  }

  const paymentData = paymentSnap.data() || {};
  if (paymentData.fulfilled === true) {
    logger.info(`[FULFILL_IDEMPOTENT] Reference ${reference} already fulfilled. Skipping duplicate activation.`);
    return { success: true, status: "success", paystackStatus: "success", message: "Already fulfilled", alreadyFulfilled: true };
  }

  // 1. Verify transaction with Paystack server-to-server
  const verifyResult = await verifyTransactionWithPaystack(reference);
  const verifyData = verifyResult?.data;
  const psStatus = verifyData?.status;

  if (verifyResult?.status !== true || !verifyData) {
    logger.warn(`[FULFILL_VERIFY_API_ERROR] Paystack verify failed for ${reference}: ${verifyResult?.message}`);
    return {
      success: false,
      status: "pending",
      paystackStatus: "pending",
      isPending: true,
      message: verifyResult?.message || "Waiting for payment confirmation...",
    };
  }

  // Handle in-flight states (pay_offline, pending, ongoing)
  if (psStatus === "pay_offline" || psStatus === "pending" || psStatus === "ongoing") {
    logger.info(`[FULFILL_IN_FLIGHT] Transaction ${reference} is in state "${psStatus}". Awaiting user authorization.`);
    return {
      success: false,
      status: "pending",
      paystackStatus: psStatus,
      isPending: true,
      displayText: verifyData.display_text || "Please complete the authorization on your phone.",
      message: verifyData.gateway_response || "Waiting for payment confirmation...",
    };
  }

  // Handle terminal failures (failed, abandoned, reversed)
  if (psStatus === "failed" || psStatus === "abandoned" || psStatus === "reversed") {
    const failureReason = verifyData.gateway_response || verifyResult.message || `Payment ${psStatus}`;
    logger.warn(`[FULFILL_TERMINAL_FAILURE] Reference ${reference} ended with status "${psStatus}": ${failureReason}`);
    await paymentRef.update({
      status: psStatus,
      paystackStatus: psStatus,
      failureReason: failureReason,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {
      success: false,
      status: psStatus,
      paystackStatus: psStatus,
      isPending: false,
      message: failureReason,
    };
  }

  if (psStatus !== "success") {
    logger.warn(`[FULFILL_UNKNOWN_STATUS] Unhandled status for ${reference}: ${psStatus}`);
    return {
      success: false,
      status: psStatus || "failed",
      paystackStatus: psStatus || "failed",
      isPending: false,
      message: verifyData.gateway_response || "Payment was not successful",
    };
  }

  // 2. Strict validation of amount, currency, and reference
  if (verifyData.currency !== "KES") {
    logger.error(`[FULFILL_SECURITY] Currency mismatch: expected KES, got ${verifyData.currency}`);
    return { success: false, status: "security_error", message: "Currency mismatch" };
  }

  if (verifyData.amount !== paymentData.expectedAmountSubunits) {
    logger.error(`[FULFILL_SECURITY] Amount mismatch for ${reference}: expected ${paymentData.expectedAmountSubunits}, got ${verifyData.amount}`);
    return { success: false, status: "security_error", message: "Amount mismatch" };
  }

  // 3. Connect into the existing subscription activation logic
  const userId = paymentData.userId;
  const pkg = AUTHORITATIVE_PACKAGES[paymentData.packageId];
  if (!pkg) {
    return { success: false, status: "error", message: "Unknown package" };
  }

  const historyRef = db.collection("subscriptions").doc(userId).collection("history");
  const historySnap = await historyRef.get();

  const now = new Date();
  let hasActiveSubscription = false;

  for (const doc of historySnap.docs) {
    const data = doc.data();
    if (data.status === "active") {
      const expDate = data.expiryDate instanceof admin.firestore.Timestamp
        ? data.expiryDate.toDate()
        : new Date(data.expiryDate);
      if (expDate > now) {
        hasActiveSubscription = true;
        break;
      }
    }
  }

  const newStatus = hasActiveSubscription ? "queued" : "active";
  const activationDate = now;
  const expiryDate = new Date(now.getTime() + pkg.durationDays * 24 * 60 * 60 * 1000);
  const newSubId = `${Date.now()}`;

  // Execute in a transaction to guarantee strict idempotency under concurrency
  return await db.runTransaction(async (transaction) => {
    const currentPaymentSnap = await transaction.get(paymentRef);
    if (!currentPaymentSnap.exists) {
      return { success: false, status: "not_found", message: "Payment record not found" };
    }
    const currentPaymentData = currentPaymentSnap.data() || {};
    if (currentPaymentData.fulfilled === true) {
      logger.info(`[FULFILL_IDEMPOTENT_TX] Reference ${reference} already fulfilled. Skipping duplicate activation.`);
      return { success: true, status: "success", paystackStatus: "success", message: "Already fulfilled", alreadyFulfilled: true };
    }

    const subDocRef = historyRef.doc(newSubId);
    transaction.set(subDocRef, {
      id: newSubId,
      packageTitle: pkg.title,
      amount: pkg.priceKes,
      transactionCode: reference, // Paystack transaction reference
      paystackTransactionId: verifyData.id ?? null, // Paystack numeric transaction ID
      paystackReference: reference,
      paymentChannel: verifyData.channel || paymentData.paymentMethod || "mobile_money",
      operatorReceiptNumber: verifyData.receipt_number || verifyData.order_id || null,
      purchaseDate: activationDate,
      activationDate: activationDate,
      expiryDate: expiryDate,
      status: newStatus,
      downloadCount: 0,
    });

    transaction.update(paymentRef, {
      status: "success",
      paystackStatus: "success",
      fulfilled: true,
      fulfilledAt: admin.firestore.FieldValue.serverTimestamp(),
      fulfillmentSource: source,
      subscriptionId: newSubId,
      paystackTransactionId: verifyData.id ?? null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info(`[FULFILL_SUCCESS] Successfully fulfilled package "${pkg.title}" (${newStatus}) for user ${userId}. Ref: ${reference}`);
    return { success: true, status: "success", paystackStatus: "success", message: "Subscription activated successfully" };
  });
}

import * as logger from "firebase-functions/logger";
import { EnvConfig } from "../config/env_config";

export interface EmailPayload {
  to: string;
  subject: string;
  html: string;
  text: string;
  from?: string;
}

export interface EmailSendResult {
  success: boolean;
  messageId?: string;
  error?: string;
  skipped?: boolean;
}

export type CustomEmailSender = (payload: EmailPayload) => Promise<EmailSendResult>;

export class EmailService {
  private static mockSender: CustomEmailSender | null = null;

  /**
   * Inject a custom sender for automated testing to prevent real network calls.
   */
  public static setSenderForTesting(sender: CustomEmailSender | null): void {
    this.mockSender = sender;
  }

  public static resetSenderForTesting(): void {
    this.mockSender = null;
  }

  /**
   * Retrieves the configured Resend API key safely without exposing it.
   */
  private static getApiKey(): string {
    return (process.env.RESEND_API_KEY || "").trim();
  }

  /**
   * Retrieves the sender address for Mirror Digital system notifications.
   */
  private static getFromAddress(): string {
    return (process.env.SYSTEM_EMAIL_FROM || "Mirror Digital <notifications@mirrorlaikipia.app>").trim();
  }

  /**
   * Core HTTPS dispatcher to Resend REST API (https://api.resend.com/emails).
   */
  public static async sendEmail(payload: EmailPayload): Promise<EmailSendResult> {
    if (!payload.to || typeof payload.to !== "string" || !payload.to.includes("@")) {
      logger.warn(`[EMAIL_DISPATCH_INVALID] Invalid recipient email address: "${payload.to}"`);
      return { success: false, error: "Invalid recipient email address" };
    }

    // Use test mock if registered
    if (this.mockSender) {
      return await this.mockSender(payload);
    }

    const apiKey = this.getApiKey();
    if (!apiKey) {
      logger.warn(
        `[EMAIL_SERVICE_NOT_CONFIGURED] RESEND_API_KEY is not set in environment. Skipping email to ${payload.to}.`
      );
      return { success: false, skipped: true, error: "RESEND_API_KEY not configured" };
    }

    const from = payload.from || this.getFromAddress();
    const maskedKey = EnvConfig.maskSecret(apiKey);

    try {
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from,
          to: [payload.to],
          subject: payload.subject,
          html: payload.html,
          text: payload.text,
        }),
      });

      const responseData: any = await response.json().catch(() => ({}));

      if (!response.ok) {
        const errorMsg = responseData?.message || responseData?.error || `HTTP ${response.status}`;
        logger.warn(
          `[EMAIL_DISPATCH_FAILED] Resend API error for ${payload.to} (Status ${response.status}): ${errorMsg}`
        );
        return { success: false, error: errorMsg };
      }

      const messageId = responseData?.id || "sent";
      logger.info(
        `[EMAIL_DISPATCH_SUCCESS] Sent email "${payload.subject}" to ${payload.to} (ID: ${messageId}, Key: ${maskedKey})`
      );
      return { success: true, messageId };
    } catch (err: any) {
      logger.warn(`[EMAIL_DISPATCH_ERROR] Network error dispatching email to ${payload.to}:`, err.message || err);
      return { success: false, error: err.message || "Network error" };
    }
  }

  /**
   * EMAIL #1: ACCOUNT DELETION CONFIRMATION
   * Dispatched after requestAccountDeletion commits its Firestore transaction.
   */
  public static async sendDeletionRequestedEmail(toEmail: string, scheduledDate: Date): Promise<EmailSendResult> {
    const formattedDate = scheduledDate.toUTCString();
    const subject = "Account Deletion Request Received - Mirror Digital";

    const html = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${subject}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #0A0E1A; margin: 0; padding: 24px 16px; color: #FFFFFF; }
    .card { max-width: 580px; margin: 0 auto; background-color: #121829; border: 1px solid #1E2742; border-radius: 16px; overflow: hidden; }
    .header { background: linear-gradient(135deg, #0A0E1A 0%, #151D33 100%); padding: 28px 32px; border-bottom: 1px solid #1E2742; text-align: center; }
    .header h1 { margin: 0; font-size: 22px; color: #20C8FF; letter-spacing: 0.5px; }
    .header p { margin: 6px 0 0; font-size: 13px; color: #8F9CAE; }
    .content { padding: 32px; line-height: 1.6; color: #D1D7E0; font-size: 15px; }
    .status-badge { display: inline-block; background-color: #FFF3E0; color: #BF360C; padding: 6px 14px; border-radius: 20px; font-size: 13px; font-weight: bold; margin-bottom: 16px; }
    .info-box { background-color: #1A2238; border-left: 4px solid #20C8FF; padding: 16px 20px; border-radius: 8px; margin: 20px 0; }
    .info-box p { margin: 4px 0; font-size: 14px; }
    .info-label { color: #8F9CAE; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
    .info-val { color: #FFFFFF; font-weight: 600; font-size: 15px; }
    .notice { font-size: 13px; color: #8F9CAE; margin-top: 24px; padding-top: 16px; border-top: 1px solid #1E2742; }
    .footer { text-align: center; padding: 20px 32px; font-size: 12px; color: #64748B; background-color: #0D1220; }
  </style>
</head>
<body>
  <div class="card">
    <div class="header">
      <h1>Mirror Digital</h1>
      <p>Educational Resource Platform</p>
    </div>
    <div class="content">
      <div class="status-badge">&#9888; 30-Day Grace Period Active</div>
      <h2 style="margin-top: 0; color: #FFFFFF; font-size: 18px;">Account Deletion Request Confirmation</h2>
      <p>We received a request to delete your <strong>Mirror Digital</strong> account.</p>
      <p>Your account is now in a <strong>30-day grace period</strong>. During this window, your active login sessions have been deactivated, but your profile remains recoverable.</p>
      
      <div class="info-box">
        <div class="info-label">Scheduled Permanent Deletion (UTC)</div>
        <div class="info-val">${formattedDate}</div>
      </div>

      <p><strong>Want to keep your account?</strong><br>
      You can restore your account at any time before the scheduled permanent deletion date. Simply open the Mirror Digital app and sign in. You will be prompted to restore your account immediately with a single tap.</p>

      <p>If you take no action, all your personal identifying details, authentication credentials, and active data will be permanently purged after the grace period ends.</p>

      <div class="notice">
        <strong>Important:</strong> This is a confirmation of your deletion request, not a password reset email. If you did not initiate this request, please sign in to the Mirror Digital app immediately to restore and secure your account.
      </div>
    </div>
    <div class="footer">
      &copy; ${new Date().getFullYear()} Mirror Digital. All rights reserved.<br>
      Automated notification &bull; Please do not reply directly to this email.
    </div>
  </div>
</body>
</html>
`;

    const text = `Mirror Digital - Account Deletion Request Confirmation

We received a request to delete your Mirror Digital account.

Your account is now in a 30-day grace period.

Scheduled Permanent Deletion: ${formattedDate}

If you change your mind, you can restore your account at any time within the 30-day grace period simply by opening the Mirror Digital app and signing in.

If you take no action, your personal identifying data and credentials will be permanently purged after the grace period.

Important: This is a confirmation of your deletion request, not a password reset email. If you did not initiate this request, sign in to the Mirror Digital app immediately to restore your account.

- Mirror Digital Team
`;

    return await this.sendEmail({ to: toEmail, subject, html, text });
  }

  /**
   * EMAIL #2: ACCOUNT RESTORATION CONFIRMATION
   * Dispatched after restoreUserAccount commits its Firestore transaction.
   */
  public static async sendAccountRestoredEmail(toEmail: string): Promise<EmailSendResult> {
    const subject = "Account Successfully Restored - Mirror Digital";

    const html = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${subject}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #0A0E1A; margin: 0; padding: 24px 16px; color: #FFFFFF; }
    .card { max-width: 580px; margin: 0 auto; background-color: #121829; border: 1px solid #1E2742; border-radius: 16px; overflow: hidden; }
    .header { background: linear-gradient(135deg, #0A0E1A 0%, #151D33 100%); padding: 28px 32px; border-bottom: 1px solid #1E2742; text-align: center; }
    .header h1 { margin: 0; font-size: 22px; color: #20C8FF; letter-spacing: 0.5px; }
    .header p { margin: 6px 0 0; font-size: 13px; color: #8F9CAE; }
    .content { padding: 32px; line-height: 1.6; color: #D1D7E0; font-size: 15px; }
    .status-badge { display: inline-block; background-color: #E8F5E9; color: #2E7D32; padding: 6px 14px; border-radius: 20px; font-size: 13px; font-weight: bold; margin-bottom: 16px; }
    .info-box { background-color: #1A2238; border-left: 4px solid #2E7D32; padding: 16px 20px; border-radius: 8px; margin: 20px 0; }
    .notice { font-size: 13px; color: #8F9CAE; margin-top: 24px; padding-top: 16px; border-top: 1px solid #1E2742; }
    .footer { text-align: center; padding: 20px 32px; font-size: 12px; color: #64748B; background-color: #0D1220; }
  </style>
</head>
<body>
  <div class="card">
    <div class="header">
      <h1>Mirror Digital</h1>
      <p>Educational Resource Platform</p>
    </div>
    <div class="content">
      <div class="status-badge">&#10004; Account Restored &amp; Active</div>
      <h2 style="margin-top: 0; color: #FFFFFF; font-size: 18px;">Welcome Back to Mirror Digital</h2>
      <p>Your <strong>Mirror Digital</strong> account has been successfully restored.</p>
      
      <div class="info-box">
        <p style="margin: 0; color: #FFFFFF; font-weight: 500;">
          The pending deletion schedule has been cancelled. Your profile, settings, and library access are fully active.
        </p>
      </div>

      <p>You can now sign in and use Mirror Digital normally on all your devices.</p>
      <p>If you encounter any issues or have questions regarding your account, our support team is here to help.</p>

      <div class="notice">
        <strong>Security Notice:</strong> If you did not authorize this restoration, please secure your credentials immediately or contact support.
      </div>
    </div>
    <div class="footer">
      &copy; ${new Date().getFullYear()} Mirror Digital. All rights reserved.<br>
      Automated notification &bull; Please do not reply directly to this email.
    </div>
  </div>
</body>
</html>
`;

    const text = `Mirror Digital - Account Successfully Restored

Welcome back to Mirror Digital!

Your account has been successfully restored. The pending deletion schedule has been cancelled, and your profile and library access are active again.

You can now sign in and use Mirror Digital normally.

Security Notice: If you did not authorize this restoration, please secure your credentials immediately or contact support.

- Mirror Digital Team
`;

    return await this.sendEmail({ to: toEmail, subject, html, text });
  }

  /**
   * EMAIL #3: FINAL PERMANENT DELETION CONFIRMATION
   * Dispatched after scheduledAccountDeletionProcessor purges and anonymizes the account.
   */
  public static async sendPermanentDeletionEmail(toEmail: string): Promise<EmailSendResult> {
    const subject = "Account Permanently Deleted - Mirror Digital";

    const html = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${subject}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #0A0E1A; margin: 0; padding: 24px 16px; color: #FFFFFF; }
    .card { max-width: 580px; margin: 0 auto; background-color: #121829; border: 1px solid #1E2742; border-radius: 16px; overflow: hidden; }
    .header { background: linear-gradient(135deg, #0A0E1A 0%, #151D33 100%); padding: 28px 32px; border-bottom: 1px solid #1E2742; text-align: center; }
    .header h1 { margin: 0; font-size: 22px; color: #20C8FF; letter-spacing: 0.5px; }
    .header p { margin: 6px 0 0; font-size: 13px; color: #8F9CAE; }
    .content { padding: 32px; line-height: 1.6; color: #D1D7E0; font-size: 15px; }
    .status-badge { display: inline-block; background-color: #2D1A1A; color: #FF6B6B; padding: 6px 14px; border-radius: 20px; font-size: 13px; font-weight: bold; margin-bottom: 16px; }
    .info-box { background-color: #1A2238; border-left: 4px solid #FF6B6B; padding: 16px 20px; border-radius: 8px; margin: 20px 0; }
    .notice { font-size: 13px; color: #8F9CAE; margin-top: 24px; padding-top: 16px; border-top: 1px solid #1E2742; }
    .footer { text-align: center; padding: 20px 32px; font-size: 12px; color: #64748B; background-color: #0D1220; }
  </style>
</head>
<body>
  <div class="card">
    <div class="header">
      <h1>Mirror Digital</h1>
      <p>Educational Resource Platform</p>
    </div>
    <div class="content">
      <div class="status-badge">&#10006; Deletion Complete</div>
      <h2 style="margin-top: 0; color: #FFFFFF; font-size: 18px;">Account Permanently Deleted</h2>
      <p>This email confirms that the 30-day grace period for your <strong>Mirror Digital</strong> account has ended, and your account has been permanently deleted and anonymized.</p>
      
      <div class="info-box">
        <p style="margin: 0; color: #FFFFFF; font-size: 14px;">
          All private personal data, login credentials, and session tokens have been permanently removed. Restoration is no longer possible.
        </p>
      </div>

      <p>In accordance with our data policy, any shared educational materials and public comments remain available to the student community under an anonymized identity to preserve educational context.</p>

      <p>Thank you for having been part of Mirror Digital. You are always welcome to create a fresh account in the future if you ever wish to return.</p>

      <div class="notice">
        This is the final confirmation email regarding this account.
      </div>
    </div>
    <div class="footer">
      &copy; ${new Date().getFullYear()} Mirror Digital. All rights reserved.<br>
      Automated notification &bull; Please do not reply directly to this email.
    </div>
  </div>
</body>
</html>
`;

    const text = `Mirror Digital - Account Permanently Deleted

The 30-day grace period for your Mirror Digital account has ended.

Your account has now been permanently deleted and anonymized. All private credentials, personal information, and session data have been permanently erased. Restoration is no longer possible.

Shared educational resources and comments remain preserved for the student community under an anonymized contributor identity.

Thank you for having been part of Mirror Digital.

- Mirror Digital Team
`;

    return await this.sendEmail({ to: toEmail, subject, html, text });
  }
}

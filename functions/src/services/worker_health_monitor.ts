import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { WorkerManager } from "./worker_manager";
import { AIProviderRegistry } from "../providers/provider_registry";

export class WorkerHealthMonitor {
  /**
   * Scans all workers in workers collection:
   * 1. Resets expired minute rate limits & cooldowns
   * 2. Calculates successRate, failureRate, averageLatency metrics
   * 3. Runs health checks on idle workers
   * 4. Updates lastHeartbeat in Firestore
   */
  static async checkAllWorkersHealth(db: admin.firestore.Firestore): Promise<{
    scanned: number;
    healthy: number;
    cooldownCleared: number;
    cooldownSet: number;
  }> {
    const now = Date.now();
    logger.info("[HEALTH_MONITOR_START] Starting distributed worker health scan...");

    let scanned = 0;
    let healthy = 0;
    let cooldownCleared = 0;
    let cooldownSet = 0;

    try {
      const snap = await db.collection("workers").get();
      scanned = snap.docs.length;

      for (const doc of snap.docs) {
        const d = doc.data() || {};
        const workerId = doc.id;
        const enabled = d.enabled !== false;
        const providerName = d.provider || "openai";
        let status = d.status || "idle";

        // Always update lastHeartbeat and metrics for each document
        const successCount = typeof d.successCount === "number" ? d.successCount : 0;
        const failureCount = typeof d.failureCount === "number" ? d.failureCount : 0;
        const totalReqs = successCount + failureCount;
        const successRate = totalReqs > 0 ? Number((successCount / totalReqs).toFixed(4)) : 1.0;
        const failureRate = totalReqs > 0 ? Number((failureCount / totalReqs).toFixed(4)) : 0.0;

        const updateData: any = {
          lastHeartbeat: admin.firestore.FieldValue.serverTimestamp(),
          successRate,
          failureRate,
          requestsThisMinute: 0, // Reset minute counter on health pulse
        };

        if (!enabled) {
          await db.collection("workers").doc(workerId).update(updateData);
          continue;
        }

        // Clear expired cooldowns
        if (d.cooldownUntil) {
          const cooldownTime = d.cooldownUntil.toDate ? d.cooldownUntil.toDate().getTime() : new Date(d.cooldownUntil).getTime();
          if (cooldownTime <= now) {
            logger.info(`[HEALTH_MONITOR] Cooldown expired for worker "${workerId}". Resetting to idle.`);
            updateData.busy = false;
            updateData.status = "idle";
            updateData.cooldownUntil = admin.firestore.FieldValue.delete();
            updateData.failureCount = 0;
            cooldownCleared++;
            status = "idle";
          }
        }

        await db.collection("workers").doc(workerId).update(updateData);

        // Perform active health check for idle workers
        if (status === "idle" && AIProviderRegistry.hasProvider(providerName)) {
          try {
            const provider = AIProviderRegistry.getProvider(providerName);
            const isHealthy = await provider.healthCheck({
              workerId,
              provider: providerName,
              model: d.model || "gpt-4o",
              apiKey: d.apiKey || d.apiKeyReference || "",
              apiKeyReference: d.apiKeyReference || d.apiKey || "",
              baseUrl: d.baseUrl || undefined,
              role: d.role || "DISCOVERY",
              supportsWebSearch: d.supportsWebSearch !== false,
              supportsImages: d.supportsImages === true,
              enabled: true,
              busy: false,
              priority: d.priority || 50,
              status: "idle",
              currentJobId: null,
              requestsPerMinute: d.minuteLimit || d.requestsPerMinute || 60,
              minuteLimit: d.minuteLimit || d.requestsPerMinute || 60,
              dailyLimit: d.dailyLimit || 1000,
              requestsToday: d.requestsToday || 0,
              requestsThisMinute: 0,
              remainingQuota: d.remainingQuota || 1000,
              lastUsed: d.lastUsed || d.lastRequest || null,
              lastRequest: d.lastRequest || d.lastUsed || null,
              lastError: null,
              averageLatency: d.averageLatency || 500,
              failureCount: d.failureCount || 0,
              successCount: d.successCount || 0,
              cooldownUntil: null,
            });

            if (isHealthy) {
              healthy++;
            } else {
              const newFailures = (d.failureCount || 0) + 1;
              if (newFailures >= 3) {
                await WorkerManager.putWorkerInCooldown(db, workerId, 15, "Failed 3 consecutive health checks");
                cooldownSet++;
              } else {
                await db.collection("workers").doc(workerId).update({
                  failureCount: newFailures,
                });
              }
            }
          } catch (checkErr: any) {
            logger.warn(`[HEALTH_MONITOR] Health check exception for worker "${workerId}": ${checkErr.message}`);
          }
        }
      }

      logger.info(
        `[HEALTH_MONITOR_FINISH] Scanned=${scanned} Healthy=${healthy} CooldownCleared=${cooldownCleared} CooldownSet=${cooldownSet}`
      );

      return { scanned, healthy, cooldownCleared, cooldownSet };
    } catch (err: any) {
      logger.error("[HEALTH_MONITOR_ERROR] Failed health scan:", err);
      return { scanned, healthy, cooldownCleared, cooldownSet };
    }
  }
}

import { safeNotificationPayload } from './alert_logic.js';

async function supervisorTokensFor(database, alert) {
  const supervisors = (await database.ref(`sites/${alert.siteId}/supervisors`).get()).val() ?? {};
  const result = [];
  for (const uid of Object.keys(supervisors).sort()) {
    if (supervisors[uid] !== true) continue;
    const user = (await database.ref(`users/${uid}`).get()).val();
    if (!user ||
        user.active !== true ||
        user.role !== 'supervisor' ||
        user.siteIds?.[alert.siteId] !== true ||
        user.authorizedHelmetIds?.[alert.helmetId] !== true ||
        user.pushAlertsEnabled === false ||
        (user.criticalAlertsOnly === true && alert.severity !== 'critical')) {
      continue;
    }
    const tokenRecords = (await database.ref(`notificationTokens/${uid}`).get()).val() ?? {};
    for (const [tokenHash, tokenRecord] of Object.entries(tokenRecords)) {
      if (typeof tokenRecord?.token === 'string' && tokenRecord.token.length > 0) {
        result.push({ uid, tokenHash, token: tokenRecord.token });
      }
    }
  }
  return result;
}

async function updateDeliveryAudit(database, alertId, patch, now) {
  await database.ref(`alerts/${alertId}/notificationDelivery`).update({
    ...patch,
    lastAttemptAt: now,
  });
}

export function createAlertDelivery({ database, messaging, clock = () => Date.now() }) {
  return async function deliverAlert(alert) {
    const targets = await supervisorTokensFor(database, alert);
    if (targets.length === 0) {
      await updateDeliveryAudit(database, alert.alertId, {
        successCount: 0,
        failureCount: 0,
        lastErrorCode: 'NO_AUTHORIZED_TOKENS',
      }, clock());
      return (await database.ref(`alerts/${alert.alertId}`).get()).val();
    }
    const safePayload = safeNotificationPayload(alert);
    try {
      const response = await messaging.sendEachForMulticast({
        tokens: targets.map((target) => target.token),
        ...safePayload,
        android: {
          priority: 'high',
          notification: {
            channelId: 'safehelmet_alerts',
            visibility: 'private',
          },
        },
        apns: {
          headers: { 'apns-priority': '10' },
          payload: { aps: { sound: 'default' } },
        },
      });
      const cleanup = {};
      let lastErrorCode = null;
      response.responses.forEach((item, index) => {
        const code = item.error?.code;
        if (code) lastErrorCode = code;
        if (code === 'messaging/invalid-registration-token' ||
            code === 'messaging/registration-token-not-registered') {
          const target = targets[index];
          cleanup[`notificationTokens/${target.uid}/${target.tokenHash}`] = null;
          cleanup[`users/${target.uid}/fcmTokenRefs/${target.tokenHash}`] = null;
          cleanup[`notificationTokenOwners/${target.tokenHash}`] = null;
        }
      });
      if (Object.keys(cleanup).length > 0) await database.ref().update(cleanup);
      const deliveredAt = clock();
      if (response.successCount > 0) {
        await database.ref(`alerts/${alert.alertId}`).transaction((current) => {
          if (!current) return current;
          return {
            ...current,
            status: current.status === 'created' ? 'delivered' : current.status,
            deliveredAt: current.deliveredAt ?? deliveredAt,
          };
        });
      }
      await updateDeliveryAudit(database, alert.alertId, {
        successCount: response.successCount,
        failureCount: response.failureCount,
        lastErrorCode,
      }, clock());
    } catch (error) {
      await updateDeliveryAudit(database, alert.alertId, {
        successCount: 0,
        failureCount: targets.length,
        lastErrorCode: error?.code ?? 'MESSAGING_ERROR',
      }, clock());
    }
    return (await database.ref(`alerts/${alert.alertId}`).get()).val();
  };
}

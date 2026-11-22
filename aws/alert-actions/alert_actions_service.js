import {
  AlertValidationError,
  acknowledgeTransition,
  registrationTokenHash,
  resolveTransition,
  sanitizeResolutionNote,
  tokenAssociationUpdates,
  tokenRemovalUpdates,
  userCanAccessAlert,
  viewedTransition,
} from '../../functions/src/alert_logic.js';
import { createAlertDelivery } from '../../functions/src/alert_delivery.js';

const ALERT_ID = /^[A-Za-z0-9_-]{1,128}$/;
const PLATFORMS = new Set(['android', 'ios', 'macos', 'web', 'windows', 'linux']);

export class AlertActionError extends Error {
  constructor(statusCode, code, message) {
    super(message);
    this.name = 'AlertActionError';
    this.statusCode = statusCode;
    this.code = code;
  }
}

function fail(statusCode, code, message) {
  throw new AlertActionError(statusCode, code, message);
}

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: {
      'content-type': 'application/json',
      'cache-control': 'no-store',
      'access-control-allow-origin': '*',
    },
    body: JSON.stringify(body),
  };
}

function bearerToken(headers = {}) {
  const authorization = Object.entries(headers)
    .find(([key]) => key.toLowerCase() === 'authorization')?.[1];
  const match = typeof authorization === 'string'
    ? /^Bearer\s+([^\s]+)$/i.exec(authorization.trim()) : null;
  if (!match) fail(401, 'unauthenticated', 'Authentication is required.');
  return match[1];
}

function parseBody(event) {
  if (typeof event?.body !== 'string') fail(400, 'invalid-argument', 'Request body is required.');
  try {
    const text = event.isBase64Encoded
      ? Buffer.from(event.body, 'base64').toString('utf8') : event.body;
    const body = JSON.parse(text);
    if (body === null || typeof body !== 'object' || Array.isArray(body)) {
      fail(400, 'invalid-argument', 'Request body must be a JSON object.');
    }
    return body;
  } catch (error) {
    if (error instanceof AlertActionError) throw error;
    fail(400, 'invalid-argument', 'Request body must be valid JSON.');
  }
}

function routeOf(event) {
  // HTTP API payload v2: routeKey is the matched route ("POST /v1/alerts/acknowledge")
  // without the stage name. rawPath includes the stage on named stages
  // ("/staging/v1/..."), so it is only a fallback, with the stage prefix removed.
  if (typeof event?.routeKey === 'string' && event.routeKey.includes(' /')) {
    return event.routeKey;
  }
  const method = event?.requestContext?.http?.method ?? event?.httpMethod ?? '';
  let path = event?.rawPath ?? event?.path ?? '';
  const stage = event?.requestContext?.stage;
  if (stage && stage !== '$default' && path.startsWith(`/${stage}/`)) {
    path = path.slice(stage.length + 1);
  }
  return `${method.toUpperCase()} ${path}`;
}

function statusForCode(code) {
  return {
    'invalid-argument': 400,
    unauthenticated: 401,
    'permission-denied': 403,
    'not-found': 404,
    'failed-precondition': 409,
  }[code] ?? 500;
}

async function authenticate(event, auth, database, allowedRoles) {
  let decoded;
  try {
    decoded = await auth.verifyIdToken(bearerToken(event?.headers), true);
  } catch (error) {
    if (error instanceof AlertActionError) throw error;
    fail(401, 'unauthenticated', 'The sign-in session is invalid or expired.');
  }
  const uid = decoded?.uid;
  if (typeof uid !== 'string' || uid.length === 0) {
    fail(401, 'unauthenticated', 'The sign-in session is invalid or expired.');
  }
  const user = (await database.ref(`users/${uid}`).get()).val();
  if (!user || user.active !== true) {
    fail(403, 'permission-denied', 'The account is disabled or unavailable.');
  }
  const effectiveRole = decoded.role ?? (user.role === 'worker' ? 'worker' : null);
  if (!effectiveRole || user.role !== effectiveRole || !allowedRoles.includes(effectiveRole)) {
    fail(403, 'permission-denied', 'Trusted role authorization is missing.');
  }
  return { uid, user, role: effectiveRole };
}

async function alertAccess(event, body, auth, database, allowedRoles) {
  const actor = await authenticate(event, auth, database, allowedRoles);
  if (typeof body.alertId !== 'string' || !ALERT_ID.test(body.alertId)) {
    fail(400, 'invalid-argument', 'A valid alertId is required.');
  }
  const reference = database.ref(`alerts/${body.alertId}`);
  const alert = (await reference.get()).val();
  if (!alert) fail(404, 'not-found', 'Alert not found.');
  if (!userCanAccessAlert(actor.user, alert, actor.uid, actor.role)) {
    fail(403, 'permission-denied', 'The alert is outside the assigned scope.');
  }
  return { ...actor, alert, reference };
}

function validToken(body) {
  const token = body.token;
  if (typeof token !== 'string' || token.length < 16 || token.length > 4096) {
    fail(400, 'invalid-argument', 'A valid FCM registration token is required.');
  }
  return token;
}

// Schema 2.0 telemetry (helmets/{id}/current) carries raw readings only; the
// safe/unsafe verdict lives in helmets/{id}/currentAssessment. Build the state
// that resolveTransition()/isHazardCleared() expect from both records. Legacy
// records that already carry severity/fallState are passed through unchanged.
export function resolutionStateFrom(telemetry, assessment) {
  if (telemetry && typeof telemetry.severity === 'string') return telemetry;
  if (!telemetry && !assessment) return null;
  const overall = assessment?.overallRisk;
  const sameEvent = !telemetry || !assessment ||
    typeof telemetry.eventId !== 'string' || telemetry.eventId === assessment.eventId;
  const severity = overall === 'safe' && sameEvent ? 'safe' : (overall ?? 'unknown');
  return {
    ...(telemetry ?? {}),
    serverReceivedAt: Number.isSafeInteger(telemetry?.serverReceivedAt)
      ? telemetry.serverReceivedAt
      : assessment?.sourceServerReceivedAt,
    severity,
    fallState: severity === 'safe' ? 'normal' : 'not cleared',
    gasWarmUp: telemetry?.mq7WarmUp === true || telemetry?.mq135WarmUp === true,
  };
}

export function createAlertActionsHandler({
  auth,
  database,
  messaging,
  clock = () => Date.now(),
}) {
  const deliverAlert = createAlertDelivery({ database, messaging, clock });
  return async function handle(event) {
    try {
      const body = parseBody(event);
      let result;
      switch (routeOf(event)) {
        case 'POST /v1/alerts/viewed': {
          const actor = await alertAccess(
            event, body, auth, database, ['worker', 'supervisor', 'administrator'],
          );
          result = await actor.reference.transaction((current) =>
            current ? viewedTransition(current, actor.uid, clock()) : current);
          return jsonResponse(200, { alert: result.snapshot.val() });
        }
        case 'POST /v1/alerts/acknowledge': {
          const actor = await alertAccess(
            event, body, auth, database, ['supervisor', 'administrator'],
          );
          result = await actor.reference.transaction((current) =>
            current ? acknowledgeTransition(current, actor.uid, clock()) : current);
          return jsonResponse(200, { alert: result.snapshot.val() });
        }
        case 'POST /v1/alerts/resolve': {
          const actor = await alertAccess(
            event, body, auth, database, ['supervisor', 'administrator'],
          );
          const note = sanitizeResolutionNote(body.resolutionNote);
          const helmetPath = `helmets/${actor.alert.helmetId}`;
          const [telemetry, assessment] = await Promise.all([
            database.ref(`${helmetPath}/current`).get().then((snapshot) => snapshot.val()),
            database.ref(`${helmetPath}/currentAssessment`).get().then((snapshot) => snapshot.val()),
          ]);
          const current = resolutionStateFrom(telemetry, assessment);
          // Validate before the transaction: an AlertValidationError thrown
          // inside an RTDB transaction does not reach the error mapper intact,
          // so the client only saw a generic "could not be completed".
          resolveTransition(actor.alert, actor.uid, note, current, clock());
          result = await actor.reference.transaction((alert) =>
            alert ? resolveTransition(alert, actor.uid, note, current, clock()) : alert);
          return jsonResponse(200, { alert: result.snapshot.val() });
        }
        case 'POST /v1/alerts/retry-delivery': {
          const actor = await alertAccess(
            event, body, auth, database, ['supervisor', 'administrator'],
          );
          return jsonResponse(200, { alert: await deliverAlert(actor.alert) });
        }
        case 'POST /v1/fcm-token': {
          const actor = await authenticate(event, auth, database, ['supervisor']);
          const token = validToken(body);
          if (!PLATFORMS.has(body.platform)) {
            fail(400, 'invalid-argument', 'Unsupported notification platform.');
          }
          const tokenHash = registrationTokenHash(token);
          const existing = (await database.ref(`notificationTokens/${actor.uid}/${tokenHash}`).get()).val();
          const previousOwner = (await database.ref(`notificationTokenOwners/${tokenHash}`).get()).val();
          const association = tokenAssociationUpdates({
            uid: actor.uid,
            token,
            platform: body.platform,
            now: clock(),
            existingCreatedAt: existing?.createdAt,
            previousOwner,
          });
          await database.ref().update(association.updates);
          return jsonResponse(200, { tokenRef: association.tokenHash });
        }
        case 'DELETE /v1/fcm-token': {
          const actor = await authenticate(event, auth, database, ['supervisor']);
          const token = validToken(body);
          const tokenHash = registrationTokenHash(token);
          const owner = (await database.ref(`notificationTokenOwners/${tokenHash}`).get()).val();
          const removal = tokenRemovalUpdates({ uid: actor.uid, token, owner });
          await database.ref().update(removal.updates);
          return jsonResponse(200, { removed: true });
        }
        default:
          fail(404, 'not-found', 'Route not found.');
      }
    } catch (error) {
      if (error instanceof AlertActionError) {
        return jsonResponse(error.statusCode, { error: { code: error.code, message: error.message } });
      }
      if (error instanceof AlertValidationError) {
        return jsonResponse(statusForCode(error.code), {
          error: { code: error.code, message: error.message },
        });
      }
      return jsonResponse(500, {
        error: { code: 'internal', message: 'The alert operation could not be completed.' },
      });
    }
  };
}

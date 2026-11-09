/**
 * Room pushes, sent straight to APNs when something is written — what
 * CloudKit's query subscriptions used to do.
 *
 * A phone registers the rooms it wants to hear about and the alert copy for
 * each kind (`format` plus which fields fill it). The copy stays the app's:
 * the Worker sends it as `loc-key`/`loc-args`, and iOS formats it on the
 * phone exactly as it formatted CloudKit's.
 *
 * Nobody is pushed about their own record; a poke reaches only its target.
 * Only the deployed Worker can reach APNs — `wrangler dev` has no HTTP/2.
 */
import { bad, json, readJson, roomCode, str } from './http.js';

const KINDS = ['clip', 'comment', 'reaction', 'poke'];
const ARG_FIELDS = new Set(['authorName', 'text']);
/** APNs refuses payloads over 4KB; a chat line is cut well before that. */
const MAX_ALERT_TEXT = 500;

function list(value) {
  return String(value ?? '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function readAlerts(value) {
  if (!value || typeof value !== 'object') throw bad();
  const alerts = {};
  for (const kind of KINDS) {
    const alert = value[kind];
    if (!alert) continue;
    const format = str(alert.format, 300);
    const args = alert.args ?? [];
    if (!Array.isArray(args) || args.length > 4 || !args.every((a) => ARG_FIELDS.has(a))) throw bad();
    alerts[kind] = { format, args };
  }
  return alerts;
}

/**
 * Replaces everything this phone asked for. An empty room list removes the
 * phone: notifications off has to mean nothing arrives, since a pushed alert
 * can't check a setting on the phone.
 */
async function putDevice(request, env, { me }) {
  const b = await readJson(request);
  const token = str(b.token, 200);
  if (!/^[0-9a-f]{32,200}$/i.test(token)) throw bad('bad_token');
  const topic = str(b.topic, 200);
  if (!list(env.APPLE_AUDIENCES).includes(topic)) throw bad('bad_topic');
  if (!Array.isArray(b.rooms) || b.rooms.length > 300) throw bad();
  const rooms = b.rooms.map((r) => ({ code: roomCode(r?.code), title: str(r?.title, 200) }));
  const alerts = readAlerts(b.alerts);

  const statements = [
    env.DB.prepare('DELETE FROM device_rooms WHERE token = ?1').bind(token),
    env.DB.prepare('DELETE FROM devices WHERE token = ?1').bind(token),
  ];
  if (rooms.length) {
    statements.push(
      env.DB.prepare(
        'INSERT INTO devices (token, user_id, topic, sandbox, alerts, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)'
      ).bind(token, me, topic, b.sandbox ? 1 : 0, JSON.stringify(alerts), Date.now()),
      ...rooms.map((r) =>
        env.DB.prepare('INSERT OR REPLACE INTO device_rooms (token, room_code, title) VALUES (?1, ?2, ?3)').bind(
          token,
          r.code,
          r.title
        )
      )
    );
  }
  await env.DB.batch(statements);
  return json({ ok: true, rooms: rooms.length });
}

async function deleteDevice(request, env) {
  const b = await readJson(request);
  const token = str(b.token, 200);
  await env.DB.batch([
    env.DB.prepare('DELETE FROM device_rooms WHERE token = ?1').bind(token),
    env.DB.prepare('DELETE FROM devices WHERE token = ?1').bind(token),
  ]);
  return json({ ok: true });
}

export async function pushRoutes(request, env, who, segments) {
  if (segments[0] !== 'push' || segments[1] !== 'device' || segments.length !== 2) return null;
  if (request.method === 'PUT') return putDevice(request, env, who);
  if (request.method === 'DELETE') return deleteDevice(request, env);
  return null;
}

// MARK: - Sending

/**
 * @param event {{ kind, code, authorID, authorName, day, text?, targetAuthorID?, recordName }}
 * Never throws: a push that can't go out must not fail the write behind it.
 */
export async function notifyRoom(env, event, { send = sendToAPNs } = {}) {
  try {
    const { results } = await env.DB.prepare(
      `SELECT d.token, d.user_id, d.topic, d.sandbox, d.alerts, r.title
         FROM device_rooms r JOIN devices d ON d.token = r.token
        WHERE r.room_code = ?1 AND d.user_id <> ?2`
    )
      .bind(event.code, event.authorID)
      .all();
    for (const device of results ?? []) {
      if (event.kind === 'poke' && device.user_id !== event.targetAuthorID) continue;
      const alert = JSON.parse(device.alerts)[event.kind];
      if (!alert) continue;
      const payload = buildPayload(event, alert, device.title);
      const { status, reason } = await send(env, device, payload, event);
      // The phone uninstalled, or the token belongs to another app or environment.
      if (status === 410 || (status === 400 && /BadDeviceToken|DeviceTokenNotForTopic/.test(reason))) {
        await env.DB.batch([
          env.DB.prepare('DELETE FROM device_rooms WHERE token = ?1').bind(device.token),
          env.DB.prepare('DELETE FROM devices WHERE token = ?1').bind(device.token),
        ]);
      }
    }
  } catch (error) {
    console.error('push failed', event.kind, error?.message ?? 'error');
  }
}

export function buildPayload(event, alert, title) {
  const values = {
    authorName: event.authorName ?? '',
    text: (event.text ?? '').slice(0, MAX_ALERT_TEXT),
  };
  return {
    aps: {
      alert: { title, 'loc-key': alert.format, 'loc-args': alert.args.map((a) => values[a] ?? '') },
      sound: 'default',
      category: 'ROOM_ACTIVITY',
      'thread-id': event.code,
      // So an open app hears about it and refreshes the room.
      'content-available': 1,
    },
    oneday: {
      roomCode: event.code,
      kind: event.kind,
      day: Math.max(event.day ?? 1, 1),
      authorID: event.authorID,
      recordName: event.recordName,
    },
  };
}

let cachedJwt = null;

async function providerToken(env, now = Math.floor(Date.now() / 1000)) {
  // Apple wants a new one at most every 20 minutes and refuses one over an hour old.
  if (cachedJwt && now - cachedJwt.iat < 40 * 60) return cachedJwt.token;
  const pem = String(env.APNS_PRIVATE_KEY ?? '')
    .replace(/-----[^-]+-----/g, '')
    .replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const enc = (obj) =>
    btoa(JSON.stringify(obj)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const head = `${enc({ alg: 'ES256', kid: env.APNS_KEY_ID })}.${enc({ iss: env.APNS_TEAM_ID, iat: now })}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(head))
  );
  const sig = btoa(String.fromCharCode(...signature)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  cachedJwt = { token: `${head}.${sig}`, iat: now };
  return cachedJwt.token;
}

async function sendToAPNs(env, device, payload, event) {
  if (!env.APNS_PRIVATE_KEY || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) return { status: 0, reason: '' };
  const host = device.sandbox ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
  const headers = {
    authorization: `bearer ${await providerToken(env)}`,
    'apns-topic': device.topic,
    'apns-push-type': 'alert',
    'apns-priority': '10',
  };
  // Several uploads or reactions are one piece of news per room; messages and
  // pokes are each for someone, so they don't collapse.
  if (event.kind === 'clip' || event.kind === 'reaction') headers['apns-collapse-id'] = event.code;
  const response = await fetch(`https://${host}/3/device/${device.token}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(payload),
  });
  let reason = '';
  if (!response.ok) {
    reason = await response.text().catch(() => '');
    console.warn('apns', response.status, reason.slice(0, 120));
  }
  return { status: response.status, reason };
}

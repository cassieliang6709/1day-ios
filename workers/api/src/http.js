/**
 * Small pieces every route uses: JSON in and out, the signed-in caller, and
 * the checks on ids and strings that come from the app.
 */
import { AuthError, verifySessionToken } from './auth.js';

export function json(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', ...headers },
  });
}

/** Thrown inside a route; `index.js` turns it into the response. */
export class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

export const bad = (code = 'bad_request') => new HttpError(400, code);
export const forbidden = () => new HttpError(403, 'forbidden');
export const notFound = () => new HttpError(404, 'not_found');

/** JSON bodies here are a room, a clip's captions, a batch of names. */
const MAX_JSON_BYTES = 256 * 1024;

export async function readJson(request) {
  const length = Number(request.headers.get('content-length') ?? 0);
  if (length > MAX_JSON_BYTES) throw bad();
  let text;
  try {
    text = await request.text();
  } catch {
    throw bad();
  }
  if (text.length > MAX_JSON_BYTES) throw bad();
  try {
    const body = JSON.parse(text);
    if (body === null || typeof body !== 'object' || Array.isArray(body)) throw bad();
    return body;
  } catch {
    throw bad();
  }
}

/**
 * The author id the app uses for this person. An Apple account is its bare
 * `sub` in the app and in every record CloudKit holds, so `apple:` comes off;
 * a Google account is `google:<sub>` everywhere already.
 */
export function authorIdFor(userId) {
  return userId.startsWith('apple:') ? userId.slice('apple:'.length) : userId;
}

/** @returns {{ userId: string, me: string }} or throws 401 */
export async function caller(request, env) {
  const header = request.headers.get('authorization') ?? '';
  const match = /^Bearer\s+(\S+)$/i.exec(header);
  if (!match) throw new HttpError(401, 'unauthorized');
  try {
    const userId = await verifySessionToken(match[1], env.SESSION_SECRET);
    return { userId, me: authorIdFor(userId) };
  } catch (error) {
    if (error instanceof AuthError && error.reason === 'no_session_secret') {
      throw new HttpError(503, 'unavailable');
    }
    throw new HttpError(401, 'unauthorized');
  }
}

// MARK: - Field checks

/** A string field, trimmed of nothing, at most `max` characters. */
export function str(value, max, { optional = false } = {}) {
  if (value === undefined || value === null) {
    if (optional) return null;
    throw bad();
  }
  if (typeof value !== 'string' || value.length > max) throw bad();
  return value;
}

export function int(value, { optional = false, min = -Infinity, max = Infinity } = {}) {
  if (value === undefined || value === null) {
    if (optional) return null;
    throw bad();
  }
  if (!Number.isInteger(value) || value < min || value > max) throw bad();
  return value;
}

/** Milliseconds since 1970. */
export function time(value, options) {
  return int(value, { min: 0, max: 8_640_000_000_000_000, ...options });
}

/** Room codes are six of `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`; older and debug
 * rooms are let through as long as they are short and plain. */
export function roomCode(value) {
  if (typeof value !== 'string' || !/^[A-Z0-9]{4,12}$/.test(value)) throw bad('bad_code');
  return value;
}

/** Record names the app derives. Nothing exotic gets into an id. */
export function recordName(value) {
  if (typeof value !== 'string' || value.length === 0 || value.length > 400) throw bad('bad_id');
  if (/[\u0000-\u001f/\\]/.test(value)) throw bad('bad_id');
  return value;
}

const UUID = /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/;
export const isUUID = (value) => typeof value === 'string' && UUID.test(value);

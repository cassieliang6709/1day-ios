import { AuthError, verifySessionToken } from './auth.js';

export function json(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', ...headers },
  });
}

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

export function authorIdFor(userId) {
  return userId.startsWith('apple:') ? userId.slice('apple:'.length) : userId;
}

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

export function time(value, options) {
  return int(value, { min: 0, max: 8_640_000_000_000_000, ...options });
}

export function roomCode(value) {
  if (typeof value !== 'string' || !/^[A-Z0-9]{4,12}$/.test(value)) throw bad('bad_code');
  return value;
}

export function recordName(value) {
  if (typeof value !== 'string' || value.length === 0 || value.length > 400) throw bad('bad_id');
  if (/[\u0000-\u001f/\\]/.test(value)) throw bad('bad_id');
  return value;
}

const UUID = /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/;
export const isUUID = (value) => typeof value === 'string' && UUID.test(value);

import { bad, HttpError, json, notFound } from './http.js';

export const MAX_MEDIA_BYTES = 80 * 1024 * 1024;

const ALLOWED_TYPES = new Set(['video/mp4', 'video/quicktime', 'image/png', 'image/jpeg']);

export function mediaPrefix(me) {
  return `u/${hexPrefix(me)}/`;
}

function hexPrefix(text) {
  let h1 = 0x811c9dc5;
  let h2 = 0x01000193;
  for (const byte of new TextEncoder().encode(text)) {
    h1 = Math.imul(h1 ^ byte, 0x01000193) >>> 0;
    h2 = Math.imul(h2 ^ byte, 0x811c9dc5) >>> 0;
  }
  return h1.toString(16).padStart(8, '0') + h2.toString(16).padStart(8, '0');
}

async function upload(request, env, { me }) {
  if (!env.MEDIA) throw new HttpError(503, 'unavailable');
  const type = (request.headers.get('content-type') ?? '').split(';')[0].trim().toLowerCase();
  if (!ALLOWED_TYPES.has(type)) throw bad('bad_type');
  const length = Number(request.headers.get('content-length') ?? NaN);
  if (!Number.isFinite(length) || length <= 0) throw new HttpError(411, 'length_required');
  if (length > MAX_MEDIA_BYTES) throw new HttpError(413, 'too_large');
  const extension = { 'video/mp4': 'mp4', 'video/quicktime': 'mov', 'image/png': 'png', 'image/jpeg': 'jpg' }[type];
  const key = `${mediaPrefix(me)}${crypto.randomUUID()}.${extension}`;
  await env.MEDIA.put(key, request.body, { httpMetadata: { contentType: type } });
  return json({ key }, 201);
}

async function download(env, key) {
  if (!env.MEDIA) throw new HttpError(503, 'unavailable');
  if (!/^u\/[0-9a-f]{16}\/[0-9a-f-]{36}\.(mp4|mov|png|jpg)$/.test(key)) throw notFound();
  const object = await env.MEDIA.get(key);
  if (!object) throw notFound();
  return new Response(object.body, {
    headers: {
      'content-type': object.httpMetadata?.contentType ?? 'application/octet-stream',
      'content-length': String(object.size),
      'cache-control': 'private, max-age=31536000, immutable',
      etag: object.httpEtag ?? '',
    },
  });
}

export async function mediaRoutes(request, env, who, segments) {
  if (segments[0] !== 'media') return null;
  if (segments.length === 1 && request.method === 'POST') return upload(request, env, who);
  if (segments.length > 1 && request.method === 'GET') {
    return download(env, segments.slice(1).map(decodeURIComponent).join('/'));
  }
  return null;
}

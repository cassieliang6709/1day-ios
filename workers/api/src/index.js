/**
 * 1Day's own backend, replacing CloudKit.
 *
 *   POST /auth/apple | /auth/google   { identityToken }  → { token, userId, expiresAt }
 *   POST /auth/refresh                (bearer)           → a fresh token, same user
 *
 * Everything else needs `Authorization: Bearer <token>` — see README.md for
 * the full list. Rooms and clips are in `rooms.js`, files in `media.js`, the
 * mood diary in `moods.js`, pushes in `push.js`.
 *
 * The app never sends a user id of its own. The id comes out of a token
 * Apple or Google signed, so nobody can claim to be someone else by typing a
 * different string. Tokens are never logged.
 */
import {
  AuthError,
  issueSessionToken,
  userIdFor,
  verifyIdentityToken,
} from './auth.js';
import { caller, HttpError, json } from './http.js';
import { mediaRoutes } from './media.js';
import { moodRoutes } from './moods.js';
import { pushRoutes } from './push.js';
import { roomRoutes } from './rooms.js';

/** Identity tokens are ~1KB. Anything much bigger isn't one. */
const MAX_BODY_BYTES = 8 * 1024;

/** Comma-separated in `wrangler.toml`, so adding a client ID is a config edit. */
function list(value) {
  return String(value ?? '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

const AUDIENCES = {
  apple: (env) => list(env.APPLE_AUDIENCES),
  google: (env) => list(env.GOOGLE_AUDIENCES),
};

async function signIn(provider, request, env) {
  if (!env.SESSION_SECRET) return json({ error: 'unavailable' }, 503);

  const length = Number(request.headers.get('content-length') ?? 0);
  if (length > MAX_BODY_BYTES) return json({ error: 'bad_request' }, 400);

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad_request' }, 400);
  }
  const identityToken = body?.identityToken;
  if (typeof identityToken !== 'string' || !identityToken || identityToken.length > MAX_BODY_BYTES) {
    return json({ error: 'bad_request' }, 400);
  }

  try {
    const claims = await verifyIdentityToken(provider, identityToken, {
      audiences: AUDIENCES[provider](env),
    });
    const userId = userIdFor(provider, claims);
    const session = await issueSessionToken(userId, env.SESSION_SECRET);
    return json({ token: session.token, userId, expiresAt: session.expiresAt });
  } catch (error) {
    if (error instanceof AuthError) {
      // The reason, never the token.
      console.warn('sign-in rejected', provider, error.reason);
      if (error.reason === 'jwks_unavailable') return json({ error: 'unavailable' }, 502);
      if (error.reason === 'no_audience_configured' || error.reason === 'no_session_secret') {
        return json({ error: 'unavailable' }, 503);
      }
      return json({ error: 'invalid_token' }, 401);
    }
    console.error('sign-in failed', provider, error?.name ?? 'error');
    return json({ error: 'unavailable' }, 502);
  }
}

/** A still-valid session buys a new one, so someone who opens the app at
 * least once every 90 days never has to sign in again. */
async function refresh(request, env) {
  const { userId } = await caller(request, env);
  const session = await issueSessionToken(userId, env.SESSION_SECRET);
  return json({ token: session.token, userId, expiresAt: session.expiresAt });
}

const SIGN_IN = {
  '/auth/apple': (request, env) => signIn('apple', request, env),
  '/auth/google': (request, env) => signIn('google', request, env),
  '/auth/refresh': refresh,
};

const API_HEADS = new Set([
  'rooms', 'me', 'records', 'clips', 'reactions', 'comments', 'pokes', 'media', 'moods', 'push',
]);

async function route(request, env, ctx) {
  const { pathname } = new URL(request.url);
  const signIn = SIGN_IN[pathname];
  if (signIn) {
    if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, { allow: 'POST' });
    return signIn(request, env);
  }

  const segments = pathname.split('/').filter(Boolean);
  if (!API_HEADS.has(segments[0])) return json({ error: 'not_found' }, 404);
  if (!env.DB) return json({ error: 'unavailable' }, 503);
  const who = await caller(request, env);
  const response =
    (await roomRoutes(request, env, ctx, who, segments)) ??
    (await mediaRoutes(request, env, who, segments)) ??
    (await moodRoutes(request, env, who, segments)) ??
    (await pushRoutes(request, env, who, segments));
  return response ?? json({ error: 'not_found' }, 404);
}

export default {
  async fetch(request, env, ctx) {
    try {
      return await route(request, env, ctx ?? { waitUntil() {} });
    } catch (error) {
      if (error instanceof HttpError) return json({ error: error.code }, error.status);
      console.error('request failed', error?.name ?? 'error', error?.message ?? '');
      return json({ error: 'unavailable' }, 500);
    }
  },
};

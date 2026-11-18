
export const PROVIDERS = {
  apple: {
    jwksUrl: 'https://appleid.apple.com/auth/keys',
    issuers: ['https://appleid.apple.com'],
  },
  google: {
    jwksUrl: 'https://www.googleapis.com/oauth2/v3/certs',
    issuers: ['https://accounts.google.com', 'accounts.google.com'],
  },
};

const CLOCK_SKEW_S = 60;

const JWKS_TTL_MS = 60 * 60 * 1000;

const JWKS_REFETCH_GAP_MS = 60 * 1000;

const SESSION_ISSUER = 'oneday-api';
export const SESSION_TTL_S = 90 * 24 * 60 * 60;

export class AuthError extends Error {
  constructor(reason) {
    super(reason);
    this.reason = reason;
  }
}


const encoder = new TextEncoder();
const decoder = new TextDecoder();

export function base64UrlEncode(bytes) {
  const data = typeof bytes === 'string' ? encoder.encode(bytes) : new Uint8Array(bytes);
  let binary = '';
  for (const byte of data) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlDecode(text) {
  if (!/^[A-Za-z0-9_-]*$/.test(text)) throw new AuthError('malformed');
  const padded = text.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (text.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function decodeJson(part) {
  try {
    const value = JSON.parse(decoder.decode(base64UrlDecode(part)));
    if (value && typeof value === 'object' && !Array.isArray(value)) return value;
  } catch (error) {
    if (error instanceof AuthError) throw error;
  }
  throw new AuthError('malformed');
}

function splitToken(token) {
  if (typeof token !== 'string') throw new AuthError('malformed');
  const parts = token.split('.');
  if (parts.length !== 3 || parts.some((part) => part.length === 0)) {
    throw new AuthError('malformed');
  }
  return parts;
}


export function createKeySource(jwksUrl, { fetchImpl } = {}) {
  let keys = null;
  let fetchedAt = -Infinity;

  async function load(now) {
    const doFetch = fetchImpl ?? globalThis.fetch;
    const response = await doFetch(jwksUrl);
    if (!response.ok) {
      console.warn('jwks fetch', jwksUrl, response.status);
      throw new AuthError('jwks_unavailable');
    }
    const body = await response.json();
    if (!Array.isArray(body?.keys)) throw new AuthError('jwks_unavailable');
    keys = body.keys;
    fetchedAt = now;
  }

  return async function keyFor(kid, now = Date.now()) {
    if (!keys || now - fetchedAt > JWKS_TTL_MS) await load(now);
    let jwk = keys.find((key) => key.kid === kid);
    if (!jwk && now - fetchedAt > JWKS_REFETCH_GAP_MS) {
      await load(now);
      jwk = keys.find((key) => key.kid === kid);
    }
    return jwk ?? null;
  };
}

const defaultKeySources = {};

function defaultKeySource(provider) {
  defaultKeySources[provider] ??= createKeySource(PROVIDERS[provider].jwksUrl);
  return defaultKeySources[provider];
}


export async function verifyIdentityToken(provider, token, options) {
  const config = PROVIDERS[provider];
  if (!config) throw new AuthError('unknown_provider');
  const { audiences, now = Math.floor(Date.now() / 1000) } = options;
  const keyFor = options.keyFor ?? defaultKeySource(provider);
  if (!Array.isArray(audiences) || audiences.length === 0) {
    throw new AuthError('no_audience_configured');
  }

  const [headerPart, payloadPart, signaturePart] = splitToken(token);
  const header = decodeJson(headerPart);
  if (header.alg !== 'RS256') throw new AuthError('bad_alg');
  if (typeof header.kid !== 'string' || !header.kid) throw new AuthError('no_kid');

  const jwk = await keyFor(header.kid, now * 1000);
  if (!jwk || jwk.kty !== 'RSA') throw new AuthError('unknown_kid');

  const key = await crypto.subtle.importKey(
    'jwk',
    { kty: 'RSA', n: jwk.n, e: jwk.e },
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify']
  );
  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    base64UrlDecode(signaturePart),
    encoder.encode(`${headerPart}.${payloadPart}`)
  );
  if (!valid) throw new AuthError('bad_signature');

  const claims = decodeJson(payloadPart);
  if (!config.issuers.includes(claims.iss)) throw new AuthError('bad_issuer');
  const tokenAudiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (tokenAudiences.length === 0 || !tokenAudiences.every((aud) => audiences.includes(aud))) {
    throw new AuthError('bad_audience');
  }
  if (typeof claims.exp !== 'number' || claims.exp + CLOCK_SKEW_S <= now) {
    throw new AuthError('expired');
  }
  if (typeof claims.iat === 'number' && claims.iat - CLOCK_SKEW_S > now) {
    throw new AuthError('issued_in_future');
  }
  if (typeof claims.sub !== 'string' || !claims.sub) throw new AuthError('no_subject');
  return claims;
}

export function userIdFor(provider, claims) {
  return `${provider}:${claims.sub}`;
}


async function hmacKey(secret) {
  if (typeof secret !== 'string' || secret.length < 32) {
    throw new AuthError('no_session_secret');
  }
  return crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify']
  );
}

export async function issueSessionToken(userId, secret, now = Math.floor(Date.now() / 1000)) {
  const header = base64UrlEncode(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const exp = now + SESSION_TTL_S;
  const payload = base64UrlEncode(
    JSON.stringify({ iss: SESSION_ISSUER, sub: userId, iat: now, exp })
  );
  const signature = await crypto.subtle.sign(
    'HMAC',
    await hmacKey(secret),
    encoder.encode(`${header}.${payload}`)
  );
  return { token: `${header}.${payload}.${base64UrlEncode(signature)}`, expiresAt: exp };
}

export async function verifySessionToken(token, secret, now = Math.floor(Date.now() / 1000)) {
  const [headerPart, payloadPart, signaturePart] = splitToken(token);
  const header = decodeJson(headerPart);
  if (header.alg !== 'HS256') throw new AuthError('bad_alg');

  const valid = await crypto.subtle.verify(
    'HMAC',
    await hmacKey(secret),
    base64UrlDecode(signaturePart),
    encoder.encode(`${headerPart}.${payloadPart}`)
  );
  if (!valid) throw new AuthError('bad_signature');

  const claims = decodeJson(payloadPart);
  if (claims.iss !== SESSION_ISSUER) throw new AuthError('bad_issuer');
  if (typeof claims.exp !== 'number' || claims.exp <= now) throw new AuthError('expired');
  if (typeof claims.sub !== 'string' || !claims.sub) throw new AuthError('no_subject');
  return claims.sub;
}

/**
 * Sign-in has one job: an identity token gets in only if Apple or Google
 * really issued it, to this app, and it hasn't expired. Most of these tests
 * are the ways a token can fail that, each of which must end in a rejection.
 *
 * Real Apple/Google keys can't sign test tokens, so each test makes its own
 * RSA key pair and serves it as the provider's key set.
 *
 *   npm test
 */
import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/index.js';
import {
  AuthError,
  base64UrlEncode,
  createKeySource,
  issueSessionToken,
  SESSION_TTL_S,
  verifyIdentityToken,
  verifySessionToken,
} from '../src/auth.js';

const APPLE_AUD = 'com.cassie.AISetlog';
const GOOGLE_AUD = 'prod-client.apps.googleusercontent.com';
const SECRET = 'x'.repeat(48);
const NOW = 1_800_000_000;

async function makeKeyPair(kid) {
  const { privateKey, publicKey } = await crypto.subtle.generateKey(
    {
      name: 'RSASSA-PKCS1-v1_5',
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: 'SHA-256',
    },
    true,
    ['sign', 'verify']
  );
  const jwk = await crypto.subtle.exportKey('jwk', publicKey);
  return { privateKey, jwk: { kty: 'RSA', kid, alg: 'RS256', use: 'sig', n: jwk.n, e: jwk.e } };
}

async function sign(privateKey, header, claims) {
  const head = base64UrlEncode(JSON.stringify(header));
  const body = base64UrlEncode(JSON.stringify(claims));
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(`${head}.${body}`)
  );
  return `${head}.${body}.${base64UrlEncode(signature)}`;
}

const appleClaims = (overrides = {}) => ({
  iss: 'https://appleid.apple.com',
  aud: APPLE_AUD,
  sub: '001234.abcd',
  iat: NOW - 10,
  exp: NOW + 600,
  ...overrides,
});

const googleClaims = (overrides = {}) => ({
  iss: 'https://accounts.google.com',
  aud: GOOGLE_AUD,
  azp: GOOGLE_AUD,
  sub: '1098765',
  iat: NOW - 10,
  exp: NOW + 3600,
  ...overrides,
});

let provider; // { privateKey, jwk } served as the provider's only key
let attacker; // a key pair nobody published

beforeEach(async () => {
  provider = await makeKeyPair('real-kid');
  attacker = await makeKeyPair('real-kid');
});

const keyFor = async (kid) => (kid === provider.jwk.kid ? provider.jwk : null);
const verify = (which, token, overrides = {}) =>
  verifyIdentityToken(which, token, {
    audiences: [which === 'apple' ? APPLE_AUD : GOOGLE_AUD],
    now: NOW,
    keyFor,
    ...overrides,
  });

async function rejects(promise, reason) {
  await assert.rejects(promise, (error) => {
    assert.ok(error instanceof AuthError, `expected AuthError, got ${error}`);
    assert.equal(error.reason, reason);
    return true;
  });
}

const header = { alg: 'RS256', kid: 'real-kid' };

// MARK: - Accepted

test('a genuine Apple token is accepted', async () => {
  const token = await sign(provider.privateKey, header, appleClaims());
  const claims = await verify('apple', token);
  assert.equal(claims.sub, '001234.abcd');
});

test('a genuine Google token is accepted, with either issuer spelling', async () => {
  for (const iss of ['https://accounts.google.com', 'accounts.google.com']) {
    const token = await sign(provider.privateKey, header, googleClaims({ iss }));
    const claims = await verify('google', token);
    assert.equal(claims.sub, '1098765');
  }
});

test('a token a few seconds past exp still passes inside the clock skew', async () => {
  const token = await sign(provider.privateKey, header, appleClaims({ exp: NOW - 30 }));
  assert.equal((await verify('apple', token)).sub, '001234.abcd');
});

// MARK: - Rejected: not really from Apple/Google

test('forged: signed by a key nobody published, same kid', async () => {
  const token = await sign(attacker.privateKey, header, appleClaims());
  await rejects(verify('apple', token), 'bad_signature');
});

test('forged: a genuine token with the subject swapped', async () => {
  const token = await sign(provider.privateKey, header, appleClaims());
  const [head, , sig] = token.split('.');
  const swapped = base64UrlEncode(JSON.stringify(appleClaims({ sub: 'someone-else' })));
  await rejects(verify('apple', `${head}.${swapped}.${sig}`), 'bad_signature');
});

test('forged: alg none with no signature', async () => {
  const head = base64UrlEncode(JSON.stringify({ alg: 'none', kid: 'real-kid' }));
  const body = base64UrlEncode(JSON.stringify(appleClaims()));
  await rejects(verify('apple', `${head}.${body}.x`), 'bad_alg');
});

test('forged: HS256 signed with the public key as the secret', async () => {
  const hsKey = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(provider.jwk.n),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const head = base64UrlEncode(JSON.stringify({ alg: 'HS256', kid: 'real-kid' }));
  const body = base64UrlEncode(JSON.stringify(appleClaims()));
  const sig = await crypto.subtle.sign('HMAC', hsKey, new TextEncoder().encode(`${head}.${body}`));
  await rejects(verify('apple', `${head}.${body}.${base64UrlEncode(sig)}`), 'bad_alg');
});

test('a kid the provider never published', async () => {
  const token = await sign(provider.privateKey, { alg: 'RS256', kid: 'made-up' }, appleClaims());
  await rejects(verify('apple', token), 'unknown_kid');
});

test('no kid at all', async () => {
  const token = await sign(provider.privateKey, { alg: 'RS256' }, appleClaims());
  await rejects(verify('apple', token), 'no_kid');
});

// MARK: - Rejected: real, but not for us or not now

test('expired', async () => {
  const token = await sign(provider.privateKey, header, appleClaims({ exp: NOW - 120 }));
  await rejects(verify('apple', token), 'expired');
});

test('no exp claim', async () => {
  const token = await sign(provider.privateKey, header, appleClaims({ exp: undefined }));
  await rejects(verify('apple', token), 'expired');
});

test('issued in the future', async () => {
  const token = await sign(provider.privateKey, header, appleClaims({ iat: NOW + 3600 }));
  await rejects(verify('apple', token), 'issued_in_future');
});

test('wrong aud: issued to another app', async () => {
  const token = await sign(provider.privateKey, header, appleClaims({ aud: 'com.someone.else' }));
  await rejects(verify('apple', token), 'bad_audience');
});

test('wrong aud: an array that includes us and someone else', async () => {
  const token = await sign(
    provider.privateKey,
    header,
    appleClaims({ aud: [APPLE_AUD, 'com.someone.else'] })
  );
  await rejects(verify('apple', token), 'bad_audience');
});

test('wrong issuer: a Google token sent to the Apple check', async () => {
  const token = await sign(provider.privateKey, header, googleClaims({ aud: APPLE_AUD }));
  await rejects(verify('apple', token), 'bad_issuer');
});

test('no subject', async () => {
  const token = await sign(provider.privateKey, header, appleClaims({ sub: '' }));
  await rejects(verify('apple', token), 'no_subject');
});

test('malformed tokens', async () => {
  for (const bad of ['', 'abc', 'a.b', 'a.b.c.d', '!!.??.**', `${base64UrlEncode('[]')}.e30.x`]) {
    await rejects(verify('apple', bad), 'malformed');
  }
  await rejects(verify('apple', 42), 'malformed');
});

test('no audiences configured refuses everything', async () => {
  const token = await sign(provider.privateKey, header, appleClaims());
  await rejects(verify('apple', token, { audiences: [] }), 'no_audience_configured');
});

// MARK: - Key set fetching

test('key source caches, and refetches once for an unknown kid', async () => {
  let fetches = 0;
  const keys = [provider.jwk];
  const source = createKeySource('https://example.test/keys', {
    fetchImpl: async () => {
      fetches++;
      return new Response(JSON.stringify({ keys }));
    },
  });
  const t0 = 1_000_000;
  assert.equal((await source('real-kid', t0)).kid, 'real-kid');
  assert.equal((await source('real-kid', t0 + 1000)).kid, 'real-kid');
  assert.equal(fetches, 1);

  // A rotation: the new key appears after the first fetch.
  keys.push({ ...provider.jwk, kid: 'rotated' });
  assert.equal((await source('rotated', t0 + 2 * 60 * 1000)).kid, 'rotated');
  assert.equal(fetches, 2);

  // Made-up kids right after a fetch don't trigger another one.
  assert.equal(await source('made-up', t0 + 2 * 60 * 1000 + 10), null);
  assert.equal(fetches, 2);
});

test('key source failure is reported, not treated as "no such key"', async () => {
  const source = createKeySource('https://example.test/keys', {
    fetchImpl: async () => new Response('nope', { status: 500 }),
  });
  await rejects(source('real-kid'), 'jwks_unavailable');
});

// MARK: - 1Day session tokens

test('session token round trip', async () => {
  const { token, expiresAt } = await issueSessionToken('apple:001234.abcd', SECRET, NOW);
  assert.equal(expiresAt, NOW + SESSION_TTL_S);
  assert.equal(await verifySessionToken(token, SECRET, NOW + 60), 'apple:001234.abcd');
});

test('session token: tampered subject is rejected', async () => {
  const { token } = await issueSessionToken('apple:me', SECRET, NOW);
  const [head, , sig] = token.split('.');
  const body = base64UrlEncode(JSON.stringify({ iss: 'oneday-api', sub: 'apple:you', iat: NOW, exp: NOW + 999 }));
  await rejects(verifySessionToken(`${head}.${body}.${sig}`, SECRET, NOW), 'bad_signature');
});

test('session token: wrong secret is rejected', async () => {
  const { token } = await issueSessionToken('apple:me', SECRET, NOW);
  await rejects(verifySessionToken(token, 'y'.repeat(48), NOW), 'bad_signature');
});

test('session token: expired is rejected', async () => {
  const { token } = await issueSessionToken('apple:me', SECRET, NOW);
  await rejects(verifySessionToken(token, SECRET, NOW + SESSION_TTL_S), 'expired');
});

test('session token: an Apple identity token is not a session token', async () => {
  const token = await sign(provider.privateKey, header, appleClaims());
  await rejects(verifySessionToken(token, SECRET, NOW), 'bad_alg');
});

test('a short session secret is refused', async () => {
  await rejects(issueSessionToken('apple:me', 'short', NOW), 'no_session_secret');
});

// MARK: - The endpoints

const env = (overrides = {}) => ({
  SESSION_SECRET: SECRET,
  APPLE_AUDIENCES: `${APPLE_AUD}, com.cassie.AISetlog.dev`,
  GOOGLE_AUDIENCES: GOOGLE_AUD,
  ...overrides,
});

const post = (path, body, init = {}) =>
  new Request(`https://example.test${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: typeof body === 'string' ? body : JSON.stringify(body),
    ...init,
  });

// The endpoints use the real key sources, which fetch the provider's key set
// once per isolate and cache it. So they get one key pair for the whole file,
// served at whichever provider URL is asked for.
let endpointKey;
const realFetch = globalThis.fetch;
const realWarn = console.warn;
let rejections;
beforeEach(async () => {
  endpointKey ??= await makeKeyPair('endpoint-kid');
  globalThis.fetch = async () => new Response(JSON.stringify({ keys: [endpointKey.jwk] }));
  rejections = [];
  console.warn = (_label, _provider, reason) => rejections.push(reason);
});
afterEach(() => {
  globalThis.fetch = realFetch;
  console.warn = realWarn;
});

const endpointHeader = { alg: 'RS256', kid: 'endpoint-kid' };

// The endpoints check against the real clock.
const nowClaims = (claims) => {
  const now = Math.floor(Date.now() / 1000);
  return { ...claims, iat: now - 10, exp: now + 600 };
};

test('POST /auth/apple with a genuine token returns a working session token', async () => {
  const token = await sign(
    endpointKey.privateKey,
    endpointHeader,
    nowClaims(appleClaims({ aud: 'com.cassie.AISetlog.dev' }))
  );
  const response = await worker.fetch(post('/auth/apple', { identityToken: token }), env());
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.userId, 'apple:001234.abcd');
  assert.equal(await verifySessionToken(body.token, SECRET), 'apple:001234.abcd');
});

test('POST /auth/google with a genuine token signs in as google:<sub>', async () => {
  const token = await sign(endpointKey.privateKey, endpointHeader, nowClaims(googleClaims()));
  const response = await worker.fetch(post('/auth/google', { identityToken: token }), env());
  assert.equal(response.status, 200);
  assert.equal((await response.json()).userId, 'google:1098765');
});

test('POST /auth/apple with a forged token is 401 and issues nothing', async () => {
  const token = await sign(attacker.privateKey, endpointHeader, nowClaims(appleClaims()));
  const response = await worker.fetch(post('/auth/apple', { identityToken: token }), env());
  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: 'invalid_token' });
  assert.deepEqual(rejections, ['bad_signature']);
});

test('POST /auth/google with an expired token is 401', async () => {
  const now = Math.floor(Date.now() / 1000);
  const token = await sign(
    endpointKey.privateKey,
    endpointHeader,
    googleClaims({ iat: now - 7200, exp: now - 3600 })
  );
  const response = await worker.fetch(post('/auth/google', { identityToken: token }), env());
  assert.equal(response.status, 401);
  assert.deepEqual(rejections, ['expired']);
});

test('POST /auth/google with another app\'s client id is 401', async () => {
  const token = await sign(
    endpointKey.privateKey,
    endpointHeader,
    nowClaims(googleClaims({ aud: 'someone-else.apps.googleusercontent.com' }))
  );
  const response = await worker.fetch(post('/auth/google', { identityToken: token }), env());
  assert.equal(response.status, 401);
  assert.deepEqual(rejections, ['bad_audience']);
});

test('bad requests', async () => {
  assert.equal((await worker.fetch(post('/auth/apple', '{not json'), env())).status, 400);
  assert.equal((await worker.fetch(post('/auth/apple', {}), env())).status, 400);
  assert.equal((await worker.fetch(post('/auth/apple', { identityToken: 7 }), env())).status, 400);
  assert.equal(
    (await worker.fetch(post('/auth/apple', { identityToken: 'x'.repeat(9000) }), env())).status,
    400
  );
});

test('routing: unknown path is 404, GET is 405', async () => {
  assert.equal((await worker.fetch(post('/auth/facebook', {}), env())).status, 404);
  const get = await worker.fetch(new Request('https://example.test/auth/apple'), env());
  assert.equal(get.status, 405);
  assert.equal(get.headers.get('allow'), 'POST');
});

test('no session secret configured is 503, not a token signed with nothing', async () => {
  const response = await worker.fetch(
    post('/auth/apple', { identityToken: 'a.b.c' }),
    env({ SESSION_SECRET: undefined })
  );
  assert.equal(response.status, 503);
});

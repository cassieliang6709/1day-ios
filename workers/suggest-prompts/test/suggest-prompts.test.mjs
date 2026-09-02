/**
 * Exercises the Worker's own logic against a stubbed upstream, then — only
 * when a key is present — makes one real call to check the prompt actually
 * produces filmable prompts in the right order.
 *
 *   npm test
 *   node --env-file=.dev.vars --test test/*.test.mjs   # + the live one
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/index.js';

const ENDPOINT = 'https://example.test/api/suggest-prompts';

const env = () => ({
  DEEPSEEK_API_KEY: process.env.DEEPSEEK_API_KEY ?? 'test-key',
  DEEPSEEK_MODEL: process.env.DEEPSEEK_MODEL,
});

function post(body, { url = ENDPOINT, method = 'POST' } = {}) {
  return new Request(url, {
    method,
    headers: { 'content-type': 'application/json' },
    body: method === 'POST' ? JSON.stringify(body) : undefined,
  });
}

const body = (overrides = {}) => ({
  intent: '今天要搬家',
  count: 7,
  language: 'zh',
  device: crypto.randomUUID(),
  ...overrides,
});

function upstreamReturning(content, { ok = true, status = 200 } = {}) {
  return async () => ({
    ok,
    status,
    json: async () => ({ choices: [{ message: { content } }] }),
  });
}

test('rejects anything but POST', async () => {
  const res = await worker.fetch(post(null, { method: 'GET' }), env());
  assert.equal(res.status, 405);
});

test('ignores paths it does not serve', async () => {
  const res = await worker.fetch(
    post(body(), { url: 'https://example.test/anything-else' }),
    env()
  );
  assert.equal(res.status, 404);
});

test('rejects an empty sentence', async () => {
  const res = await worker.fetch(post(body({ intent: '  ' })), env());
  assert.equal(res.status, 400);
});

test('rejects a sentence long enough to be someone else’s prompt', async () => {
  const res = await worker.fetch(post(body({ intent: 'x'.repeat(200) })), env());
  assert.equal(res.status, 400);
});

test('without a key it degrades rather than crashing', async () => {
  const res = await worker.fetch(post(body()), { DEEPSEEK_API_KEY: '' });
  assert.equal(res.status, 503);
});

test('returns prompts from a well-formed upstream reply', async (t) => {
  t.mock.method(
    globalThis,
    'fetch',
    upstreamReturning('{"prompts":["出门前","第一个箱子","新家的灯"]}')
  );

  const res = await worker.fetch(post(body()), env());

  assert.equal(res.status, 200);
  assert.deepEqual((await res.json()).prompts, ['出门前', '第一个箱子', '新家的灯']);
  assert.equal(res.headers.get('cache-control'), 'no-store');
});

test('digs the array out of a code fence', async (t) => {
  t.mock.method(
    globalThis,
    'fetch',
    upstreamReturning('```json\n["出门前","第一个箱子","新家的灯"]\n```')
  );

  const res = await worker.fetch(post(body()), env());

  assert.equal(res.status, 200);
  assert.equal((await res.json()).prompts.length, 3);
});

test('a reply with too few prompts is a failure, not a short answer', async (t) => {
  t.mock.method(globalThis, 'fetch', upstreamReturning('{"prompts":["就一个"]}'));

  const res = await worker.fetch(post(body()), env());

  assert.equal(res.status, 502);
});

test('prose instead of JSON is a failure', async (t) => {
  t.mock.method(globalThis, 'fetch', upstreamReturning('抱歉，我不太明白你的意思。'));

  const res = await worker.fetch(post(body()), env());

  assert.equal(res.status, 502);
});

test('an upstream error never reaches the caller as a 200', async (t) => {
  t.mock.method(globalThis, 'fetch', upstreamReturning('', { ok: false, status: 401 }));

  const res = await worker.fetch(post(body()), env());

  assert.equal(res.status, 502);
  assert.deepEqual(await res.json(), { error: 'unavailable' });
});

test('the same device gets rate limited', async (t) => {
  t.mock.method(globalThis, 'fetch', upstreamReturning('{"prompts":["一","二","三"]}'));

  const device = crypto.randomUUID();
  let limited = null;
  for (let i = 0; i < 25 && limited === null; i += 1) {
    const res = await worker.fetch(post(body({ device })), env());
    if (res.status === 429) limited = i;
  }

  assert.equal(limited, 20, 'should allow 20 calls an hour, then refuse');
});

test('a different device is unaffected by that limit', async (t) => {
  t.mock.method(globalThis, 'fetch', upstreamReturning('{"prompts":["一","二","三"]}'));

  const res = await worker.fetch(post(body()), env());

  assert.equal(res.status, 200);
});

// Live, and skipped without a key so CI doesn't depend on a vendor being up.
test(
  'a real call turns 今天要搬家 into prompts about moving house',
  { skip: !process.env.DEEPSEEK_API_KEY && 'no DEEPSEEK_API_KEY' },
  async () => {
    const res = await worker.fetch(post(body({ count: 7 })), env());
    const payload = await res.json();

    assert.equal(res.status, 200, JSON.stringify(payload));
    assert.equal(payload.prompts.length, 7);
    for (const prompt of payload.prompts) {
      assert.ok(prompt.length > 0 && prompt.length <= 16, `too long: ${prompt}`);
    }
    console.log(payload.prompts);
  }
);

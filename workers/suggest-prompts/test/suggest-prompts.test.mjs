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

test('answers a HEAD warm-up without touching the model or the key', async (t) => {
  const upstream = t.mock.method(globalThis, 'fetch', upstreamReturning('{}'));

  const res = await worker.fetch(post(null, { method: 'HEAD' }), { DEEPSEEK_API_KEY: '' });

  assert.equal(res.status, 204);
  assert.equal(upstream.mock.callCount(), 0);
});

test('drops prompts long enough to be sentences, keeps near misses', async (t) => {
  t.mock.method(
    globalThis,
    'fetch',
    upstreamReturning(
      '{"prompts":["出门前","背包里装好水和零食","关上卧室的灯然后最后拍一下空房间","第一个箱子","新家的灯"]}'
    )
  );

  const res = await worker.fetch(post(body()), env());

  assert.equal(res.status, 200);
  assert.deepEqual((await res.json()).prompts, [
    '出门前', '背包里装好水和零食', '第一个箱子', '新家的灯',
  ]);
});

test('counts English length in words', async (t) => {
  t.mock.method(
    globalThis,
    'fetch',
    upstreamReturning(
      '{"prompts":["The first box","Turning off every light in the old flat one last time","New keys","Dinner on the floor"]}'
    )
  );

  const res = await worker.fetch(post(body({ language: 'en' })), env());

  assert.deepEqual((await res.json()).prompts, ['The first box', 'New keys', 'Dinner on the floor']);
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
    const res = await worker.fetch(post(body({ device, intent: `day ${i}` })), env());
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

test('concurrent identical calls and a retry reuse one valid response', async (t) => {
  let release, started;
  const gate = new Promise(resolve => { release = resolve; });
  const began = new Promise(resolve => { started = resolve; });
  const upstream = t.mock.method(globalThis, 'fetch', async () => {
    started();
    await gate;
    return upstreamReturning('{"prompts":["a","b","c"]}')();
  });
  const input = body();
  const first = worker.fetch(post(input), env());
  await began;
  const second = worker.fetch(post(input), env());
  await new Promise(resolve => setTimeout(resolve, 20));
  assert.equal(upstream.mock.callCount(), 1);
  release();
  const responses = await Promise.all([first, second]);
  for (const response of responses) assert.deepEqual(await response.json(), { prompts: ['a', 'b', 'c'] });
  assert.equal((await worker.fetch(post(input), env())).status, 200);
  assert.equal(upstream.mock.callCount(), 1);
});

test('cache expires and keys separate device, count, language, intent and model', async (t) => {
  const upstream = t.mock.method(globalThis, 'fetch', upstreamReturning('{"prompts":["a","b","c"]}'));
  const input = body();
  const now = Date.now();
  const clock = t.mock.method(Date, 'now', () => now);
  await worker.fetch(post(input), env());
  await worker.fetch(post({ ...input, intent: `  ${input.intent}  ` }), env());
  assert.equal(upstream.mock.callCount(), 1);
  for (const change of [{ device: crypto.randomUUID() }, { count: 3 }, { language: 'en' }, { intent: 'another day' }]) {
    await worker.fetch(post({ ...input, ...change }), env());
  }
  await worker.fetch(post(input), { ...env(), DEEPSEEK_MODEL: 'other-model' });
  assert.equal(upstream.mock.callCount(), 6);
  clock.mock.mockImplementation(() => now + 60_001);
  await worker.fetch(post(input), env());
  assert.equal(upstream.mock.callCount(), 7);
});

test('failed generation is evicted so an explicit retry can succeed', async (t) => {
  const upstream = t.mock.method(globalThis, 'fetch', async () => { throw new DOMException('timeout', 'TimeoutError'); });
  const input = body();
  assert.equal((await worker.fetch(post(input), env())).status, 502);
  upstream.mock.mockImplementation(upstreamReturning('{"prompts":["a","b","c"]}'));
  assert.equal((await worker.fetch(post(input), env())).status, 200);
  assert.equal(upstream.mock.callCount(), 2);
});

test('cache hits do not consume the generation allowance', async (t) => {
  const upstream = t.mock.method(globalThis, 'fetch', upstreamReturning('{"prompts":["a","b","c"]}'));
  const input = body();
  for (let i = 0; i < 25; i++) assert.equal((await worker.fetch(post(input), env())).status, 200);
  assert.equal(upstream.mock.callCount(), 1);
});

test('rotating device IDs cannot bypass the per-IP generation allowance', async (t) => {
  const upstream = t.mock.method(globalThis, 'fetch', upstreamReturning('{"prompts":["a","b","c"]}'));
  for (let i = 0; i < 101; i++) {
    const request = post(body());
    request.headers.set('cf-connecting-ip', '192.0.2.10');
    const response = await worker.fetch(request, env());
    assert.equal(response.status, i < 100 ? 200 : 429);
  }
  assert.equal(upstream.mock.callCount(), 100);
});

test('oversized bodies without Content-Length and oversized device IDs never reach upstream', async (t) => {
  const upstream = t.mock.method(globalThis, 'fetch', upstreamReturning('{}'));
  for (const input of [body({ extra: 'x'.repeat(4096) }), body({ device: 'x'.repeat(129) })]) {
    assert.equal((await worker.fetch(post(input), env())).status, 400);
  }
  assert.equal(upstream.mock.callCount(), 0);
});

test('limits concurrent upstream work and releases capacity after completion', async (t) => {
  let release, started;
  const gate = new Promise(resolve => { release = resolve; });
  const began = new Promise(resolve => { started = resolve; });
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async () => {
    if (++calls === 32) started();
    await gate;
    return upstreamReturning('{"prompts":["a","b","c"]}')();
  });
  const inFlight = Array.from({ length: 32 }, () => worker.fetch(post(body()), env()));
  await began;
  try {
    assert.equal((await worker.fetch(post(body()), env())).status, 503);
    assert.equal(calls, 32);
  } finally { release(); }
  for (const response of await Promise.all(inFlight)) assert.equal(response.status, 200);
  assert.equal((await worker.fetch(post(body()), env())).status, 200);
});

test('one action retries reuse output; an explicit Another action generates again', async (t) => {
  const upstream = t.mock.method(globalThis, 'fetch', upstreamReturning('{"prompts":["a","b","c"]}'));
  const input = body({ requestID: crypto.randomUUID() });
  assert.equal((await worker.fetch(post(input), env())).status, 200);
  assert.equal((await worker.fetch(post(input), env())).status, 200);
  assert.equal(upstream.mock.callCount(), 1);
  assert.equal((await worker.fetch(post({ ...input, requestID: crypto.randomUUID() }), env())).status, 200);
  assert.equal(upstream.mock.callCount(), 2);
  assert.equal((await worker.fetch(post({ ...input, requestID: 'x'.repeat(129) }), env())).status, 400);
});


const DEEPSEEK_URL = 'https://api.deepseek.com/chat/completions';
const DEFAULT_MODEL = 'deepseek-v4-flash';

const MAX_INTENT = 140;
const MIN_COUNT = 3;
const MAX_COUNT = 7;

const MAX_PROMPT_CHARS = 12;
const MAX_PROMPT_WORDS = 8;

const UPSTREAM_TIMEOUT_MS = 7000;

const RATE_LIMIT = 20;
const RATE_WINDOW_MS = 60 * 60 * 1000;

const recentCalls = new Map();

function overRateLimit(deviceKey, now, calls = recentCalls, limit = RATE_LIMIT) {
  const window = (calls.get(deviceKey) ?? []).filter(
    (t) => now - t < RATE_WINDOW_MS
  );
  window.push(now);
  calls.set(deviceKey, window);

  if (calls.size > 5000) {
    for (const [key, times] of calls) {
      if (times.every((t) => now - t >= RATE_WINDOW_MS)) calls.delete(key);
    }
  }
  return window.length > limit;
}


function systemPrompt(count, language) {
  const inChinese = language !== 'en';
  return [
    'You write a short to-do list for one day, for a video diary app: the person films a few seconds of each item as they do it.',
    `The user says what their day holds. Answer with exactly ${count} items.`,
    'Rules:',
    '- Each item is something they will do today, in the order it happens through the day. A to-do list, not a shot list.',
    `- Nothing performed for the camera: no poses, no staging, no words like ${inChinese ? '"拍", "镜头", "特写"' : '"film", "shot", "close-up"'}. ${inChinese ? '"吃早饭" is right; "拍早饭特写" is wrong.' : '"Breakfast" is right; "Close-up of breakfast" is wrong.'}`,
    '- Present or future tense, never past: the day has not happened yet.',
    `- Short. ${inChinese ? 'At most 8 Chinese characters each — count them. "下班路上" is right; "下班以后走路回家的路上" is too long.' : 'At most 5 words each — count them. "Walk home" is right; "Walking home after work in the evening" is too long.'}`,
    '- Concrete: something that happens, not a feeling. "搬第一个箱子" beats "感受搬家".',
    `- Write them in ${inChinese ? 'Simplified Chinese' : 'English'}.`,
    '- No numbering, no trailing punctuation, no commentary.',
    `- Also write a short story title in ${inChinese ? 'Simplified Chinese (at most 12 characters)' : 'English (at most 6 words)'}.`,
    'Reply with json in exactly this shape: {"title": "…", "prompts": ["…", "…"]}',
  ].join('\n');
}

export function parsePrompts(text, count, language = 'zh') {
  const candidates = [
    sliceBetween(text, '{', '}'),
    sliceBetween(text, '[', ']'),
  ].filter(Boolean);

  for (const candidate of candidates) {
    let parsed;
    try {
      parsed = JSON.parse(candidate);
    } catch {
      continue;
    }
    const list = Array.isArray(parsed) ? parsed : parsed?.prompts;
    if (!Array.isArray(list)) continue;

    const prompts = list
      .filter((p) => typeof p === 'string')
      .map((p) => p.trim())
      .filter(Boolean)
      .filter((p) => !tooLong(p, language))
      .slice(0, count);

    if (prompts.length >= MIN_COUNT) return prompts;
  }
  return null;
}

export function parseStory(text, count, language = 'zh') {
  const prompts = parsePrompts(text, count, language);
  if (!prompts) return null;
  let title;
  try {
    const object = JSON.parse(sliceBetween(text, '{', '}'));
    if (typeof object?.title === 'string') {
      title = [...object.title.trim()].slice(0, 80).join('') || undefined;
    }
  } catch {                                      }
  return title ? { title, prompts } : { prompts };
}

function tooLong(prompt, language) {
  return language === 'en'
    ? prompt.split(/\s+/).length > MAX_PROMPT_WORDS
    : [...prompt].length > MAX_PROMPT_CHARS;
}

function sliceBetween(text, open, close) {
  const start = text.indexOf(open);
  const end = text.lastIndexOf(close);
  return start >= 0 && end > start ? text.slice(start, end + 1) : null;
}

function clamp(n, lo, hi) {
  return Math.min(Math.max(Math.round(n), lo), hi);
}

function json(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
  });
}

async function hash(value) {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value)
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== '/api/suggest-prompts' && url.pathname !== '/') {
      return json({ error: 'not_found' }, 404);
    }
    if (request.method === 'HEAD') {
      return new Response(null, { status: 204, headers: { 'cache-control': 'no-store' } });
    }
    if (request.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'method_not_allowed' }), {
        status: 405,
        headers: { 'content-type': 'application/json', allow: 'POST' },
      });
    }
    const key = env.DEEPSEEK_API_KEY;
    if (!key) return json({ error: 'unavailable' }, 503);

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: 'bad_request' }, 400);
    }

    const intent = typeof body?.intent === 'string' ? body.intent.trim() : '';
    const language = body?.language === 'en' ? 'en' : 'zh';
    const count = clamp(Number(body?.count) || MAX_COUNT, MIN_COUNT, MAX_COUNT);
    const device = typeof body?.device === 'string' ? body.device : '';

    if (!intent || intent.length > MAX_INTENT) {
      return json({ error: 'bad_request' }, 400);
    }

    const deviceKey = await hash(
      device || request.headers.get('cf-connecting-ip') || 'anonymous'
    );
    if (overRateLimit(deviceKey, Date.now())) {
      return json({ error: 'rate_limited' }, 429);
    }

    try {
      const upstream = await fetch(DEEPSEEK_URL, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          authorization: `Bearer ${key}`,
        },
        body: JSON.stringify({
          model: env.DEEPSEEK_MODEL || DEFAULT_MODEL,
          thinking: { type: 'disabled' },
          max_tokens: 1200,
          temperature: 0.8,
          response_format: { type: 'json_object' },
          messages: [
            { role: 'system', content: systemPrompt(count, language) },
            { role: 'user', content: intent },
          ],
        }),
        signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
      });

      if (!upstream.ok) {
        console.error('upstream', upstream.status);
        return json({ error: 'unavailable' }, 502);
      }

      const payload = await upstream.json();
      const story = parseStory(
        String(payload?.choices?.[0]?.message?.content ?? ''),
        count,
        language
      );
      if (!story) return json({ error: 'unavailable' }, 502);

      return json(story);
    } catch (error) {
      console.error('failed', error?.name ?? 'error');
      return json({ error: 'unavailable' }, 502);
    }
  },
};

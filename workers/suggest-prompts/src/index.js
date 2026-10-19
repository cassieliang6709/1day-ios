/**
 * Turn one sentence about today into a handful of filming prompts.
 *
 * This is the whole server. It is deliberately not a general LLM proxy: it
 * accepts one sentence and returns N short strings, and there is no parameter
 * that lets a caller change what the model is asked to do. A key shipped inside
 * the app would be extracted within a week; this Worker exists so the key can
 * live somewhere the user's phone never sees.
 *
 * It does not log the request body. "今天要去医院" is not something to leave
 * lying around in a log aggregator.
 */

/**
 * DeepSeek, whose API is OpenAI-shaped. The model id is a var rather than a
 * constant because model names move faster than deploys do — renaming one
 * shouldn't need a code change.
 */
const DEEPSEEK_URL = 'https://api.deepseek.com/chat/completions';
const DEFAULT_MODEL = 'deepseek-v4-flash';

/** One sentence. Anything longer is either a mistake or someone else's idea. */
const MAX_INTENT = 140;
const MIN_COUNT = 3;
const MAX_COUNT = 7;

/**
 * Past these a "prompt" is a sentence, which reads badly on a recording
 * screen. The model is asked for 8 characters / 5 words; this is the backstop
 * for when it doesn't listen, loose enough not to throw away near misses.
 */
const MAX_PROMPT_CHARS = 12;
const MAX_PROMPT_WORDS = 8;

/**
 * Under the app's own timeout, so a slow model comes back as a 502 the app can
 * retry, rather than as a client-side timeout with nothing left to retry in.
 */
const UPSTREAM_TIMEOUT_MS = 7000;

/** Per device, per hour. Making a story is a once-a-day act; 20 is generous. */
const RATE_LIMIT = 20;
const RATE_WINDOW_MS = 60 * 60 * 1000;

/**
 * Best-effort, in-memory, per-isolate. Cloudflare runs many isolates and
 * recycles them freely, so the real ceiling is well above `RATE_LIMIT` and the
 * counter resets whenever an isolate does — enough to stop a runaway loop in a
 * script, not enough to stop someone determined. Anything stronger wants a
 * Durable Object, which is a bigger thing than this endpoint.
 */
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
    'You write short filming prompts for a one-day video diary app.',
    `The user says what their day holds. Answer with exactly ${count} prompts.`,
    'Rules:',
    '- Each prompt is a thing to point a camera at, in the order it would happen through the day.',
    '- Present or future tense, never past: the day has not happened yet.',
    `- Short. ${inChinese ? 'At most 8 Chinese characters each — count them. "关灯拍空房间" is right; "关上灯最后拍一下空房间" is too long.' : 'At most 5 words each — count them. "The empty room" is right; "Turning off the lights in the empty room" is too long.'}`,
    '- Concrete and filmable. "The first box" beats "reflect on the move".',
    `- Write them in ${inChinese ? 'Simplified Chinese' : 'English'}.`,
    '- No numbering, no trailing punctuation, no commentary.',
    `- Also write a short story title in ${inChinese ? 'Simplified Chinese (at most 12 characters)' : 'English (at most 6 words)'}.`,
    'Reply with json in exactly this shape: {"title": "…", "prompts": ["…", "…"]}',
  ].join('\n');
}

/**
 * JSON mode should make this boring, but a model writing free text is exactly
 * the input that arrives malformed eventually — so accept the object, accept a
 * bare array, and dig either out of surrounding prose or a code fence.
 */
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
  } catch { /* Legacy bare arrays still work. */ }
  return title ? { title, prompts } : { prompts };
}

/** Dropped rather than cut: half a sentence is worse than one fewer prompt. */
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

/** Hashed so the raw device identifier isn't sitting in memory in the clear. */
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
    // The app sends this when the composer opens, so the TLS handshake — the
    // slow part on a phone network — is done before anyone taps the button.
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

    // Falling back to the IP so a caller can't skip the limit by omitting it.
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
          // Reasoning off: v4-flash otherwise spends its whole budget thinking
          // and returns an empty message. Nothing here needs deliberation, and
          // somebody is watching a spinner — 2s with it off, 5s with it on.
          thinking: { type: 'disabled' },
          // Generous, because the failure mode of being wrong about this is a
          // truncated reply, and unused tokens cost nothing.
          max_tokens: 1200,
          // Lower than the default so the length rule is followed more often;
          // still loose enough that two days of moving house don't read alike.
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
        // Status only. The upstream error body can echo the prompt back.
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

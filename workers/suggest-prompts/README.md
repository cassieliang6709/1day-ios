# suggest-prompts

A Cloudflare Worker that turns one sentence about today into a few filming
prompts. It exists so a DeepSeek API key doesn't have to ship inside the iOS
app, where it would be extracted within a week.

Deployed at
`https://oneday-suggest-prompts.oneday-cassie.workers.dev/api/suggest-prompts`,
which is what `RemotePromptSuggestionService.defaultEndpoint` points at.

## The contract

`POST /api/suggest-prompts`

```json
{ "intent": "今天要搬家", "count": 7, "language": "zh", "device": "<opaque uuid>" }
```

```json
{ "prompts": ["最后看一眼老房子", "第一个箱子", "…"] }
```

Anything other than `200` means the app falls back to hand-writing, silently.
`429` is the rate limiter and gets its own message; everything else is
`{"error": "unavailable"}` and says nothing to the user beyond one quiet line.

## Setup

The key is a secret, not a var — it never belongs in a committed file:

```bash
wrangler secret put DEEPSEEK_API_KEY
```

Until it's set the Worker answers `503`, which the app treats as "write your
own". `DEEPSEEK_MODEL` is a plain var in `wrangler.toml`, so changing models is
a config edit rather than a code change.

## Working on it

```bash
npm test                                          # stubbed upstream
node --env-file=.dev.vars --test test/*.test.mjs  # + one real DeepSeek call
npm run dev                                       # wrangler dev, needs .dev.vars
npm run deploy
```

`.dev.vars` is gitignored. Copy `.dev.vars.example` to make one.

DeepSeek is reachable from mainland China without a proxy, which is part of why
it's the vendor here.

## Things it deliberately doesn't do

- **Log request bodies.** "今天要去医院" is not something to leave in a log
  aggregator. Failures log a status code or an error name, nothing else.
- **Accept arbitrary prompts.** The system prompt is fixed in the Worker; a
  request can only supply the sentence, a count, and a language. It is not a
  general LLM proxy, so a leaked endpoint is worth very little to whoever finds
  it.
- **Authenticate callers or guarantee global quotas.** Device IDs are caller
  supplied, not proof of identity. Generation is limited to 20/hour/device and
  100/hour/Cloudflare-provided IP, per isolate. Distributed abuse and isolate
  recycling can still exceed these limits. Production cost guarantees need a
  shared limiter (for example a Durable Object), verified identity/App Attest
  compatible with guest creation, and a provider-side spending cap.
- **Send CORS headers.** The only caller is a native app. A browser calling this
  would need them added.

## Why the model doesn't think

`deepseek-v4-flash` reasons by default and will spend its entire token budget
doing it, returning an empty message — which showed up as a 502 the first time
this was wired up for real. `thinking: { type: 'disabled' }` fixes it and takes
the round trip from ~5s to ~2s. Nothing here needs deliberation, and somebody is
watching a spinner.

## Repeat requests and resource bounds

The iOS client sends one `requestID` per user action and keeps it across its
transport retry. “Another” gets a new ID and generates fresh output. Legacy
clients without an ID fall back to content-based deduplication.

Same request ID, normalized intent, count, language, model/config and device coalesce while
in flight, then reuse successful output for 60 seconds. Keys are SHA-256 hashes;
raw diary text is not logged. Replies remain `Cache-Control: no-store`; this is
bounded process memory, not a public HTTP cache. Failures are evicted so an
explicit retry can work. Cache hits do not consume generation quota.

At most 32 upstream calls run per isolate, and counters/results each have a
5,000-entry ceiling. Bodies are limited to 4 KiB even without Content-Length;
device IDs to 128 characters. Saturation returns 503 and rate limits return 429.
The upstream still has a 7-second timeout; no new provider or paid live test is
introduced. This is best-effort deduplication, **not** durable exactly-once
billing: separate isolates, expiry, restarts, and an ambiguous upstream timeout
can still produce another billed call. No deployment is implied by these tests.

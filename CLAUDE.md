<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **1day-ios**.

> Index stale? Run `node .gitnexus/run.cjs analyze --index-only` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? Bootstrap with `npx`, `bunx`, or `pnpm dlx` — e.g. `bunx gitnexus@latest analyze` (npm 11 npx crash; #1939).

## Always Do

- **MUST run impact before editing.** Use `impact({target: "symbolName", direction: "upstream"})` or `node .gitnexus/run.cjs impact "symbolName" --direction upstream --repo .`; report callers, processes, and risk. Never substitute grep for graph analysis.
- **MUST analyze graph changes before committing.** Use `detect_changes({scope: "all"})` (MCP) or `node .gitnexus/run.cjs detect-changes --scope all --repo .` (CLI fallback). `partial: true` or `truncated: true` is not a clean check — a zero means unseen, not unaffected; re-run it. For regression review: `detect_changes({scope: "compare", base_ref: "main"})` or `node .gitnexus/run.cjs detect-changes --scope compare --base-ref "main" --repo .`.
- MUST warn on HIGH/CRITICAL `risk` pre-edit; never use `riskSharedAxes` to waive a HIGH/CRITICAL `risk` warning. Compare File/symbol: MCP File omits axes; Graph-RAG expands File.
- **MUST treat `risk: UNKNOWN` as unresolved, not as low.** An empty caller set is not evidence the symbol is unused — it can also mean the callers are not resolvable by the index (plain-object property access, dynamic dispatch, cross-language calls). `impact` pairs `UNKNOWN` with a `riskNote` saying so. Confirm with a text search before treating the symbol as safe to change or delete; do not proceed on the strength of a zero.
- **MUST use `query({search_query: "concept"})` for concepts/flows, `context({name: "symbolName"})` for a named symbol, or `impact` for blast radius, on read-only callers, dependencies, imports, or execution flow.** Graph first; text search only for empty/`UNKNOWN`/literals.
- For security review, `explain({target: "fileOrSymbol"})` lists taint findings (source→sink flows; needs `analyze --pdg`).

## Never Do

- NEVER edit a function, class, or method before MCP/CLI impact analysis.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis, and never read `UNKNOWN` as an all-clear — it means the walk could not answer, which is the one verdict that requires confirming by other means.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit before MCP/CLI graph change analysis.

## Resources

| Resource | Use for |
| --- | --- |
| `gitnexus://repo/1day-ios/context` | Codebase overview, check index freshness |
| `gitnexus://repo/1day-ios/clusters` | All functional areas |
| `gitnexus://repo/1day-ios/processes` | All execution flows |
| `gitnexus://repo/1day-ios/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
| --- | --- |
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->

## GitNexus blind spots in this repo (audited 2026-09-07)

Two truncation warnings fire on every `analyze` of this repo. Both were audited
against the source; neither is a defect and neither has a config knob. Don't
re-derive this.

### The cross-language property names are a name collision, not a broken link

`analyze` warns that ~67 property read/write sites name a field defined only in
Swift, so per-language inference declined to link them — 21 distinct names.
`context`/`impact` on those names returns nothing from the JS side. That is
correct behaviour, and for 16 of the 21 it is pure coincidence: `length`, `size`,
`name`, `status`, `url`, `content` are JS-internal (`window.length`,
`recentCalls.size`, `error?.name`, `upstream.status`, `request.url`,
`message.content`), and `id`, `title`, `back`, `compact`, `footer`, `host`,
`image`, `lang`, `steps`, `locale` are landing-page copy keys. None of them
touches Swift.

The repo's only real Swift↔JS surface is the `suggest-prompts` HTTP call, and it
is five fields:

| Field | Swift | JS |
| --- | --- | --- |
| `intent`, `count`, `language`, `device` | `RemotePromptSuggestionService.Request` — `ios/AISetlog/Services/PromptSuggestionService.swift` | `body?.<field>` — `workers/suggest-prompts/src/index.js` |
| `prompts` | `Response.prompts`, same file | `json({ prompts })`, same file |

All five are already pinned by tests at both ends: `PromptSuggestionServiceTests`
decodes the raw `httpBody` and asserts the four JSON key strings, and
`suggest-prompts.test.mjs` posts them literally and reads `prompts` back. A
rename on either side fails a test even though the graph cannot see the edge —
so the blind spot is covered, just not by GitNexus.

The app has no `WKWebView`, `evaluateJavaScript`, or `JSContext`, and the landing
page calls no API. If either changes, this table is what needs updating.

### The flow truncation is a hard-coded ceiling, not a setting

`maxTraceDepth: 10`, `maxBranching: 4`, the per-entry trace budget of 12, and
`ENTRY_POINT_CANDIDATE_LIMIT = 200` are constants in the installed package
(`core/ingestion/process-processor.js`). No CLI flag and no `.gitnexusrc` key
reaches them, so `entryPointCandidatesDropped: 5` cannot be tuned away.

A `.gitnexusignore` does not help either. Of the ~205 scored candidates, 199 are
`ios/AISetlog/` functions; `landing-page/` and `workers/` contribute 3 between
them, and `ios/AISetlogTests/`'s 361 call-making functions are already excluded
by the scorer's own test-file filter. The candidates *are* the product code.

The coverage gap worth knowing is larger than the 5 the cap drops: **66 of the
199 product functions that make calls are a step in no flow at all.** The cap
explains at most 5 of those; the rest fall out of `minSteps: 3` (a trace shorter
than three hops is not recorded) and flow dedup. Notable ones:
`AccountStore.completeSignIn`, `AccountStore.revalidate`,
`VideoStitcher.addWatermark` / `addTitleCard` / `buildFriendsTogether`,
`FilmView.saveToPhotos`, `ClipPreviewView.saveCaption`,
`PlansHomeView.openPendingNotificationRoute`.

For any symbol, `query` returning no flow is not evidence about that symbol. Fall
back to `context` / `impact`, or read the file. Regenerate the uncovered list
with:

```bash
gitnexus cypher "MATCH (n) WHERE (label(n)='Function' OR label(n)='Method') AND n.filePath STARTS WITH 'ios/AISetlog/' AND EXISTS { MATCH (n)-[r:CodeRelation]->() WHERE r.type='CALLS' } AND NOT EXISTS { MATCH (n)-[s:CodeRelation]->(p:Process) WHERE s.type='STEP_IN_PROCESS' } RETURN n.filePath AS fp, n.name AS nm ORDER BY fp" -l 500
```

### The `.claude/skills/` table in the generated block is locally produced

`analyze` writes `.claude/skills/gitnexus-*` into the working tree, and this
repo's `.gitignore` excludes `.claude/`. So the CLI table above points at files a
fresh clone does not have — run `npx gitnexus analyze` once and they appear.
Don't "correct" those paths: everything between the `gitnexus:start`/`end`
markers is regenerated on every analyze, and only text outside them survives
(this section does). `.gitnexusrc` pins `noStats` so the block stops churning the
symbol counts into every diff.

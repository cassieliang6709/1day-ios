---
name: dayday-swift-performance
description: Use when changing 1Day's Swift concurrency, media playback/export, image caches, room synchronization, or responsiveness. Requires a user-visible hypothesis, ownership analysis, and honest before/after evidence.
---

# Swift and media performance

Use [dayday-verify](../dayday-verify/SKILL.md) for commands and evidence limits.

## Establish the hypothesis

Write the affected action and one measurable signal: scroll hitch duration, time to first visible room content, peak memory, export duration, or idle CPU after leaving playback. Capture a baseline with Instruments on the same device, build configuration, fixture, and settings when available. Separate simulator/software-renderer costs from device costs.

Without runtime access, classify source findings as risks or correctness defects. Implement a narrow justified repair if useful, but do not report a performance delta or call the native validation complete.

## Trace the ownership

- SwiftUI owns view-lifetime tasks. Prefer `.task(id:)` for replaceable work; an unstructured `Task` needs an explicit owner and cancellation path.
- UI and observable state changes belong on MainActor. Do not move an entire service there to silence a compiler warning, or add `@unchecked Sendable` without a demonstrated synchronization invariant.
- Keep capture graph mutations on the existing serial session queue. Main-thread callers must not block on hardware configuration. Gate recording and competing graph changes until completion.
- A room result needs the same account identity revision, room generation, and request revision that launched it. Cancellation alone does not prove that a late response cannot publish.
- Prefer immutable per-operation temporary files over shared writable paths. Stage complete downloads before replacing a usable local file.

## Inspect the expensive boundaries

- Decoding: reuse immutable decoded images, include media revision in identity, bound cache cost, and invalidate replacement/deletion. NSCache limits are eviction targets, not a hard process-memory ceiling.
- Playback: URL changes must update the real AVPlayer. Release loopers, observations and queues. Pause when invisible or inactive. Separate UI selection from asynchronous composition completion.
- Export: Swift task cancellation must reach AVAssetExportSession. Do not swallow CancellationError in fallback paths. Clean partial and intermediate outputs.
- Rendering: reuse CIContext; avoid allocating a context per frame. Inspect queued-frame cancellation and object lifetimes before increasing concurrency.
- Synchronization: independent metadata should not wait for large videos. Bound parallel media downloads and preserve stable ordering. Do not parallelize writes into the same manifest.
- SwiftUI: scope observations and work to their owner. Preserve Reduce Motion and accessibility behavior while optimizing. Do not call every blur, shadow, or VStack a bottleneck without a trace.

Prefer removing duplicate work to adding scheduling or caching machinery. Change one cause, run the affected journey, and compare the same signal. Persist a benchmark only when its measurement is repeatable and relevant.

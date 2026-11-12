---
name: dayday-mode
description: Use for nontrivial Swift, SwiftUI, UI polish, or performance work in 1Day. Routes to a small, project-specific implementation and verification workflow inspired by poteto's pstack.
---

# 1Day engineering workflow

Read the repository's AGENTS.md and inspect the current diff before editing. Use the existing checkout. Preserve unrelated work.

1. Name the user's action and observable outcome. Start from the current Camera / Rooms flow in README.md, rather than an older proposed information architecture.
2. Read the real entry point, state owner, and side-effect boundary. Name the data being shared before changing its concurrency.
3. Pick one unit:
   - Swift, media, cache, synchronization: read [dayday-swift-performance](../dayday-swift-performance/SKILL.md).
   - UI polish: read [dayday-design-system](../dayday-design-system/SKILL.md). Preserve current visual identity unless redesign is requested. Capture the affected native screen first when available. Check one primary action, content visibility, 44-point targets, Dynamic Type, Reduce Motion, and error recovery. Code inspection without native capture supports hypotheses, not a visual audit.
4. Read [dayday-verify](../dayday-verify/SKILL.md), choose the affected journey, and establish what can actually run before implementation.
5. Make the smallest coherent change. Avoid speculative layers, unrelated rewrites, and tests that merely repeat the implementation. Add a regression only for observable failure or a meaningful boundary.
6. Run the selected check. Report executed, failed, skipped, and unavailable separately. A static check is never proof that an iOS feature works.
7. Keep a short decision record for multi-step work: hypothesis, evidence, chosen change, rejected alternative, result. Update the relevant journey when behavior changes.

Preserve current user authorization for commits and external actions. Do not invent access to a Mac, simulator, trace, or screenshot. This workflow does not grant permission to publish or contact others.

## Provenance

Original project-specific adaptation of [poteto/plugins pstack](https://github.com/poteto/plugins/tree/74dd2291e8e37b12fd6dc49b2acbd655c6bdaf12/pstack), especially `prove-it-works`, `build-the-lever`, `subtract-before-you-add`, and `encode-lessons-in-structure`. It does not install pstack or depend on Cursor-only commands, model roles, or automatic agent delegation.

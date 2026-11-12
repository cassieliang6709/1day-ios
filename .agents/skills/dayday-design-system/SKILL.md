---
name: dayday-design-system
description: Use when designing or changing 1Day UI, controls, copy, colors, typography, layout, or accessibility. Applies the existing camera and rooms identity, semantic tokens, state rules, and native verification boundaries.
---

# Design 1Day

Read [the design system](../../../docs/design-system.md) and the current screen before editing. Separate implemented tokens, proposed rules, and verified behavior. Treat Setlog and Snapchat as reference directions until the relevant current screens have actually been inspected; do not invent competitor details.

1. Name the user action and the intended visible result. Preserve Camera / Rooms and the existing personal timeline entry unless the task calls for changing navigation.
2. Reuse `OneDay`, `OneDay.Font`, `OneDay.Radius`, and the existing shared controls. Keep cream and blue skins and both color schemes working. New spacing rules are a proposal, not a reason to rewrite every screen.
3. Make footage and people primary. Use one main action, readable secondary labels, and restrained decoration. On video, use the existing contrast backing and test bright and dark footage.
4. Keep local-save and room-share feedback tied to their actual completion boundaries. Preserve footage on failure and expose a relevant retry. All new user copy belongs in bilingual `Strings`.
5. Check 44-point targets, selected traits, VoiceOver labels, semantic text sizes, contrast, and Reduce Motion. Fix large-text layout together with bottom clearance; do not just remove the Dynamic Type cap or shrink essential text.
6. State the smallest coherent change and its evidence. A source finding can justify a narrow correction; a visual review requires current native screenshots and interaction. Follow [dayday-verify](../dayday-verify/SKILL.md), including its unavailable results on Linux.
7. For media or responsiveness changes, also apply [dayday-swift-performance](../dayday-swift-performance/SKILL.md). Fewer visual effects alone are not a measured performance gain.

This is a project-specific application of pstack's practice of encoding lessons in reusable structure; see [provenance](../dayday-mode/SKILL.md#provenance). It grants no additional publication permission and requires no parallel agents.

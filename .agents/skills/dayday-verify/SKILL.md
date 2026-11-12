---
name: dayday-verify
description: Use before claiming 1Day Swift/UI changes work. Provides environment diagnostics, static checks, selected native XCTest commands, and behavior-level verification journeys with explicit unavailable results on Linux.
---

# Verify 1Day

Run from the checkout root:

```bash
python3 .agents/skills/dayday-verify/scripts/verify.py doctor
python3 .agents/skills/dayday-verify/scripts/verify.py static
```

`doctor` exits 2 if macOS/Xcode 26.2/XcodeGen is unavailable. This is a prerequisite failure, not a skipped pass. `static` checks the diff and layer boundaries, and reports existing boundary debt separately; it does not compile or run the app.

On a suitable Mac, select only the affected suite:

```bash
python3 .agents/skills/dayday-verify/scripts/verify.py test --target avatar
python3 .agents/skills/dayday-verify/scripts/verify.py test --target media
python3 .agents/skills/dayday-verify/scripts/verify.py test --target rooms
python3 .agents/skills/dayday-verify/scripts/verify.py test --target ui
```

The script regenerates the ignored project, selects an existing available iPhone, uses a dedicated DerivedData/result directory, preserves xcodebuild's exit code, and rejects zero-executed-test results. Supply `--device <UDID>` to use a particular available simulator. It does not create or erase simulators, deploy, or push code.

Read only the relevant [journey](references/journeys.md). Exercise success, cancel, retry and persistence paths affected by the change. Accept native screenshots only after inspecting the saved image and confirming the intended screen and state. Do not substitute a web mockup or an old repository image for current iOS evidence.

For performance claims, attach comparable before/after Instruments artifacts. For UI claims, include current native evidence at normal and accessibility settings. A source-level finding, syntax parser, PID, or build success alone does not prove the behavior.

Report artifact paths and exact checks. Never describe unexecuted tests as passed. The native test branch of this helper itself needs a first macOS run; Linux validation covers only its CLI, static mode, and prerequisite rejection.

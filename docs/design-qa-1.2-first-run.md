# Design QA — Home “new story” A+

## Visual target

- Source visual truth: `/var/folders/kh/kk9f74w92_lchtzd85d64cvc0000gn/T/codex-clipboard-9c0076aa-7953-46e3-bd89-a4ef423afa67.png`
- Source board dimensions: 2300 × 1738 px
- Selected target: scheme A, first phone; blue new-story control before the invite control
- Normalized source crop: `/Users/cassie/Developer/01_Career_Portfolio/1day/ios/build/qa/source-scheme-a-phone.png`
- Source phone crop: 660 × 1434 px, normalized to 1320 × 2868 px for comparison

## Implementation evidence

- Simulator: `1DAY-QA-V12`, iPhone 17 Pro Max, iOS 26.5
- Native viewport: 440 × 956 pt (1320 × 2868 px at 3×)
- State: Simplified Chinese, light appearance, no active story
- Full implementation screenshot: `/Users/cassie/Developer/01_Career_Portfolio/1day/ios/build/qa/home-a-plus-iphone17pro.png`
- Focused side-by-side header comparison: `/Users/cassie/Developer/01_Career_Portfolio/1day/ios/build/qa/header-source-vs-implementation.png`
- Comparison image: 2640 × 700 px; normalized 1320 px-wide source and implementation header regions placed side by side

The source shows an active-story state while the implementation capture shows the empty state. Full views were reviewed for overall composition, but fidelity judgments are limited to the shared header region. The focused comparison is therefore the authoritative evidence for this change.

## Findings

- No actionable P0/P1/P2 mismatch in the shared header region.
- Fonts and typography: the production rounded greeting hierarchy and brand lockup match the mock’s intended weight and scale. The morning/afternoon word changes dynamically and is an expected content difference.
- Spacing and layout rhythm: the new-story button is before invite and avatar, with comfortable separation and no overlap. Its 44 pt visual size and 48 pt hit target are intentionally slightly larger than the mock as the approved A+ refinement.
- Colors and visual tokens: the button uses the existing OneDay blue-to-cyan brand gradient and glow; secondary controls retain the white material treatment.
- Image quality and asset fidelity: the existing OneDay logo and avatar assets are used directly; no placeholder or code-drawn replacement was introduced.
- Copy and content: the redundant `新建故事` text link beside `今天的故事` was removed. The empty-state CTA remains because it is the primary explanation/action when no story exists.

## Interaction and responsive evidence

- `CreationFlowUITests`: 2 passed, 0 failed, including the new header-entry test and the time-only creation flow.
- Result bundle: `/Users/cassie/Developer/01_Career_Portfolio/1day/ios/build/DerivedData/Logs/Test/Test-AISetlog-2026.09.01_11-58-37-+0800.xcresult`
- Simulator build succeeded for the iOS 26.5 SDK.
- A fresh iPhone SE simulator was started for a second visual pass, but CoreSimulator remained in first-boot system data migration. This is a simulator-environment gap, not an observed app-layout defect.

## Comparison history

### Pass 1

- Compared the selected scheme A header and the rendered A+ implementation in one normalized image.
- No P0/P1/P2 issue was found, so no visual-fix iteration was required.

## Follow-up polish

- Recheck the same header on a compact physical device when one is available; the layout already uses flexible spacing and fixed 48/38/38 pt controls.

final result: passed

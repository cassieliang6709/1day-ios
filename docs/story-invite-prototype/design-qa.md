# Design QA — 2026-09-26

## Scope and reference

Isolated HTML/React concept prototype for 1Day / AISetlog. Direction: the user names a story, captures freely, and chooses when to watch a short film. Shared stories and optional inspiration extend this flow. Existing project blue-and-white branding, logo, and scenic landing-page photos supplied visual grounding; this is an adapted product direction, not a pixel-identical recreation of a selected mockup. No native App code was changed by this prototype work.

## Verified in the Codex browser

- Rendered and visually inspected home, caption input with keyboard, invitation sheet, Free plan, and the standalone strategy document.
- Created “周六和朋友散步”; simulated capture, added a caption, retained one clip, opened preview, started playback, and simulated saving. The UI explicitly states that no MP4 or camera access is provided.
- Opened the sharing notice, enabled the story code, previewed the recipient page, simulated joining and a first contribution, received one coupon, and redeemed it. Story membership displayed 2/4 afterward.
- Opened account and Free details. Browser warning/error log was empty at the end of this flow.
- Fixed a keyboard-obscured caption action by compacting the image while typing; visually confirmed input and save controls above the keyboard.
- Fixed unintended focus scrolling of the device viewport with an application-scoped overflow rule. Protected runtime files remain unchanged; runtime integrity check passed for 28 files.
- Production build (`npm run build`) passed, including TypeScript, Vite, and runtime integrity.

## Design decisions

Primary home action is “新故事”. Inspiration is secondary; invitations belong inside a story. Capture has no required checklist or minimum clip count. Personal stories default to private, and sharing explains existing and future story visibility. Pricing preserves basic recording and standard export. Invitation rewards follow actual contribution.

## Limits

State is in browser memory and resets on refresh. Authentication, uploads, account storage, real AI, video encoding, payment, coupon expiry, and server-side quota enforcement are not implemented. Quotas are proposals, not cost-validated entitlements. Recipient simulation uses one example friend; that friend can trigger the new-user reward only once per session. Native iOS behavior, Android device mode, actual billing costs, and production security have not been validated. Clipboard and invalid-code branches were not exercised in the final browser pass. No deployment or external invitations were performed.


## Existing-App visual alignment revision

User requested an evolution of the existing UI, not a newly designed App. Compared against 1.4 `02-home.png` and `05-timeline.png`, plus `Theme.swift`, `OneDaySurfaces.swift`, and `PlansHomeView.swift`. Restored navy #0F2E6B, blue #1677FF → #38B6FF, pale canvas #F5F8FF with restrained blue/lavender blooms, 24/32px cards, capsule buttons, existing mascot and illustrated template assets. Kept 计划 / 我的 / 拍摄 navigation; avatar opens account. Replaced the photo tile grid with the existing vertical timeline visual vocabulary, displaying captured moments rather than required tasks.

Rendered home, plan/inspiration, and story timeline; checked naming a story from Plan, capturing and retaining a sample, and opening the camera story chooser. Preserved separate photo preview, invitation, and Free flows. This is still a browser approximation of SwiftUI, not a pixel-identical native implementation. The original App source was not changed. The GitNexus index could not resolve this isolated prototype; a text reference check confirmed `src/App.tsx` imports it only inside the prototype directory.

## Optional AI story brainstorming

Added an optional “AI 帮我构思” entry within story creation. Verified in-browser: enter an idea → receive three preset demonstration directions → choose one → edit its title → create “我们走过的海边”. Shared AI allowance decreased from 10 to 9; the already-generated submit action disables to prevent repeated deduction for the same results. Editing the prompt allows another request. Responses are explicitly simulated and no real AI endpoint was added. Production build and runtime checks passed.

## Media library visual polish

Refined the existing fragment selection / vlog journey in the browser prototype: date-grouped two-column image library, restrained filters, 片段 / 故事 tabs within 我的, blue selected outlines, contextual selection dock, photo-stack composition sheet, and quieter film preview. Existing three-tab navigation and 1Day colors remain. Camera from the library saves a loose clip; story capture retains its story context. Media are reused from local project assets.

Browser checks: today filter showed two clips; selected both; composition showed two clips / four seconds; edited title to 和朋友的一个下午 and generated the mock sequence; returning showed 4 original clips and 3 stories, confirming reuse without duplication or removal. Visually inspected library, selection and film view. Browser warning/error log was empty. Runtime integrity and production build passed. Date groups and video durations remain example metadata, and the prototype still does not encode a real video or call a real AI service.

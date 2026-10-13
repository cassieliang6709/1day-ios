# 1Day 1.4 — App Store copy

Prepared 2026-09-20, for the `1.4 准备提交` version record in App Store Connect.
Build 24. (Build 23 was archived and never uploaded — a third fix landed on
review the same night, and the drafts list is the screen it is on, so it went
into the same version rather than waiting.)

## 1.3 never shipped — that changes what these notes are

Checked in ASC on 2026-09-21: 历史记录 shows one line under 版本 1.3,
「准备提交」on 2026-09-17, and nothing after it. TestFlight's build list tops
out at **1.2 (10)**, uploaded 2026-09-07. So no 1.3 build was ever uploaded,
1.3 was never submitted, and the live version is **1.2**.

Everyone updating to 1.4 is coming from 1.2. The 1.3 kit's copy is therefore
not "already delivered" — it is unread, and 1.4's own three fixes are
corrections to behaviour nobody outside this machine has seen. Writing them up
as fixes would describe a bug the reader never met.

So 此版本的新增内容 below covers 1.2 → 1.4 as one release: 1.3's five beats,
with the accent-colour one rewritten to what the app actually does now, plus
the one thing from 1.4 that is a feature rather than a correction.

| Field | Where it lives in ASC | Action |
| --- | --- | --- |
| 版本号 | 版本页 | **The record still says 1.3.** Change it to 1.4 or the 1.4 (24) build can't attach. |
| 名称 | App 信息 → 可本地化信息 | Being changed this round — see below. |
| 副标题 | App 信息 → 可本地化信息 | Unchanged. |
| 关键词 | 版本页 | Unchanged. |
| 推广文本 | 版本页 | Unchanged. Can be edited later without review if you want to. |
| 描述 | 版本页 | **Check** — see below. |
| 此版本的新增内容 | 版本页 | **New.** Text below. |

### 名称

Being edited this round. The live name is `1_Day`; the 1.3 kit's zh-Hans name
(`1Day · 视频日记与生活记录`) was never applied, since 1.3 never shipped. A name
change only takes effect with the next released version, so whatever is saved
in App 信息 goes live with 1.4.

### The accent-colour description section: probably nothing to remove

1.3's kit offered an optional description section built around the accent
colour following your avatar, and 1.4 takes that behaviour out. But the live
description is 1.2's — 1.3 never shipped, so the section was almost certainly
never added to it.

Still worth one look, because the 1.3 版本页 draft was edited by hand and its
description field carries forward into 1.4. If either of these is in there,
delete the whole section:

```text
A LOOK THAT IS YOURS
Pick your avatar color and the whole app follows it. …
```

```text
一眼就是你的样子
挑一个头像颜色，整个 App 的主色跟着变。…
```

Covers and replay captions — the other two things that section mentioned — are
unchanged, so if you want to keep a section there, keep only those two
sentences and drop the accent-colour one.

## en-US

### What's New (367 characters)

```text
• Pick your avatar colour — your avatar follows it.
• Zoom while you film: 0.5x, 1x, 2x, or pinch to anything in between.
• Give each story its own cover: pull a frame, pick a photo, or use a poster.
• Rebuilt replay, with captions you can pinch, rotate, and recolour.
• Blue now opens your film and signs its corner.
• A clip you filmed but haven't put in a story yet now tells you why it can't go in, when you tap it.
```

## zh-Hans

### What's New (154 characters)

```text
• 挑一个头像颜色，你的头像跟着变。
• 拍摄时能变焦：0.5x、1x、2x，也能捏合到任意倍数。
• 每个故事有自己的封面：抽一帧、传照片，或用海报。
• 回看页重做，字幕能捏能转能换色。
• 小蓝出现在成片的片头和角标上。
• 拍好但还没放进故事的片段，现在点一下会说清楚为什么放不进去。
```

## Screenshots

**Re-shot for 1.4** — `store-kit/en-US/` and `store-kit/zh-Hans/`, six each,
1320×2868.

The 1.3 kit could not be reused, and the reason had nothing to do with 1.4.
Those shots show a **two-tab bar (Plans / Camera) and a `+` in the top-right
corner of the home header** — the shape the app had before 新建 became the
middle tab. That change shipped *in* 1.3, after the kit was captured, and
since 1.3 never went to the store nobody caught it. Anyone comparing the
product page against the app would have been looking at a different app.

Nothing else in the old set was wrong: the accent was already blue (they
predate anyone picking a colour), and no shot had a clip waiting to be filed.

| # | File | Screen |
| --- | --- | --- |
| 01 | `01-hero.png` | Onboarding: the 3-moments-to-1-film promise, sample film playing |
| 02 | `02-home.png` | Home with three stories going — a shared room part-filmed, a film ready, one from yesterday (en-US only; zh-Hans is still the empty state) |
| 03 | `03-themes.png` | The poster rack: you don't have to think of anything yourself |
| 04 | `04-setup.png` | One settings page: moments, who's filming, clip length, frame |
| 05 | `05-timeline.png` | A story just created, nothing filmed yet |
| 06 | `06-film.png` | The day full, real footage in every slot, 看成片 / See the film |

**Upload order** is not file order. Only the first three reach the install
sheet, so lead with the promise and the payoff:

```
01-hero  →  06-film  →  03-themes  →  04-setup  →  05-timeline  →  02-home
```

`02-home.png` in the English set is the one shot `capture.sh` does not
produce. Straight after onboarding the home screen is empty — a mascot and
"No story yet today" — which is the least interesting screen in the app. So
`seed_home.py` runs after the capture and adds two stories beside the finished
one, in the two states the list exists to show: a part-filmed shared room and
a solo story from yesterday. Then shoot home again by hand and overwrite 02:

```bash
xcrun simctl terminate "$SIM" com.cassie.AISetlog
python3 store-kit/seed_home.py "$SIM" en
xcrun simctl bootstatus "$SIM" -b && sleep 5
xcrun simctl launch --terminate-running-process "$SIM" com.cassie.AISetlog \
  -onboarding.completed.v1 YES -appLanguage english
sleep 9 && xcrun simctl io "$SIM" screenshot store-kit/en-US/02-home.png
```

The data is the app's own: `Challenge.isShared` is `roomCode != nil`, and the
moment keys are copied from the real templates so each story's cover, title
and moment names agree. The zh-Hans 02 is still the empty state — only the
English one was asked for.

Re-shoot with `store-kit/capture.sh english en-US` (and `chinese zh-Hans`).
Needs a booted `1day-shots` simulator, a Debug build at
`/tmp/1day-dd/Build/Products/Debug-iphonesimulator/AISetlog.app`, and the idb
client — see the header of that script. Every tap and every screen is asserted
now; the 1.3 script shot whatever was on screen when a tap missed, which is
how a stale set got committed looking complete.

## Privacy questionnaire

**No change.** 1.4 adds no network call, no new stored field and no new
permission. The answers filed for 1.3 still hold.

Do still re-read `docs/app-store-submission.md` before submitting — that
document carries its own warning that it predates the optional remote prompt
suggestions, so it is not a safe copy-paste source for the questionnaire.

## Review notes

Nothing new to explain. The demo-room launch arguments added in this branch are
inside `#if DEBUG || LOCAL_ROOM_CHAT_DEMO` and are not compiled into a Release
build; a reviewer cannot reach them.

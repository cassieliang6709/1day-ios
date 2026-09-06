# 1Day 1.2 App Store metadata

Prepared for the 1.2 release. Character counts include spaces and punctuation.

## Why this changes

The live U.S. listing was checked on 2026-08-31:

- Version 1.1 is live as `1_Day`, which uses only the generic word `Day` in the
  30-character name field.
- The first three U.S. screenshots show a Simplified Chinese interface. This is
  a conversion problem even if search visibility improves.
- ASO Scout reports that `day` has popularity 5, competition 57, and no top-200
  position. It also suggests fitness terms based on incidental rankings. Those
  terms are not relevant to the product and must not be added.

The 1.2 positioning is deliberately specific: **a private video diary that turns
short daily clips into a film, alone or with friends**.

## English (U.S.)

### Search metadata

- Name (27/30): `1Day: Video Diary & Journal`
- Subtitle (29/30): `Daily Vlog Maker with Friends`
- Keywords (100/100):
  `memory,moments,story,camera,clips,cinematic,challenge,recap,private,collage,record,life,shared,group`

Do not repeat `1Day`, `video`, `diary`, `journal`, `daily`, `vlog`, `maker`, or
`friends` in the keyword field: Apple already indexes them from the name and
subtitle. Do not use `workout tracker`, `home fitness`, `gym log`, competitor
names, or `AI`; they misdescribe the app.

### Promotional text (142/170)

`Film three tiny moments and get one daily movie—made privately on your iPhone. Record solo or invite friends to capture the same day together.`

### Description

```text
1Day turns three tiny moments into a daily film worth keeping.

Record a few 2, 5, or 10-second clips as your day happens. 1Day puts them in order and makes one finished video diary on your iPhone—no editing timeline and no endless camera-roll cleanup.

START SMALL
Choose a ready-made story such as Perfect Day, Soft Reset, or Little Adventure. Your prompts tell you what to capture next, so you can stay present instead of planning a vlog.

MAKE A DAILY FILM
When the last moment is ready, 1Day combines your clips with sound, captions, dates, title cards, and smooth transitions. Preview the film, adjust it, then save it to Photos or share the MP4.

FILM WITH FRIENDS
Create a shared room, share its six-character invitation code, and capture the same day from different places. Friends can add reactions and comments that become part of the finished story.

WRITE YOUR OWN STORY
Build a custom sequence of moments, choose portrait or landscape, and make it a one-day story or a seven-day challenge.

PRIVATE BY DEFAULT
Solo stories stay on your device and work without an account or network connection. Films are rendered on-device. Sign in with Apple is only needed when you choose to create or join a shared room.

Everyday life goes quickly. A few seconds is enough to remember it.
```

### What's New

```text
Your first film now starts with just three two-second moments.

• A redesigned first experience gets you from open to filming faster.
• New Story is easier to find.
• Record solo or invite friends to capture the same day together.
```

## Simplified Chinese

### 搜索元数据

- 名称（16/30）：`1Day · 视频日记与生活记录`
- 副标题（13/30）：`三个瞬间，自动生成每日短片`
- 关键词（77/100）：
  `Vlog,相机,回忆,影像,打卡,挑战,朋友,合拍,日常,成长,自律,习惯,相册,胶片,时间轴,故事,拍摄,剪辑,电影,私密,本地,共同创作,朋友圈,治愈`

### 推广文本

`拍下三个短短的瞬间，自动留成一支每日影片。可以独自记录，也可以邀请朋友从不同地方一起拍同一天。单人故事只留在你的 iPhone。`

### 描述

```text
1Day 把三个短短的瞬间，留成一支值得重看的每日影片。

在一天自然发生的时候，拍下几段 2 秒、5 秒或 10 秒的片段。1Day 会按顺序整理它们，并直接在 iPhone 上生成一支完整的视频日记——不需要学习剪辑，也不用留下满相册的素材。

从一个小故事开始
选择「完美的一天」「慢慢重启」「小小冒险」等现成主题。每个瞬间都有提示，你只管生活，不必先写好脚本。

自动生成每日影片
拍完最后一个瞬间后，1Day 会加入声音、字幕、日期、片头和转场，完成一支短片。你可以预览、调整，再保存到照片或直接分享。

和朋友一起拍
创建房间并分享六位邀请码，即使身处不同地方，也能记录同一天。朋友可以留下回应和评论，让彼此的片段成为同一个故事。

写自己的故事
自定义想记录的瞬间，选择横屏或竖屏，完成一日故事，也可以开始七日挑战。

默认保护隐私
单人故事只保存在你的设备上，不需要账号，也不需要联网；影片在本机生成。只有当你主动创建或加入朋友房间时，才需要「通过 Apple 登录」。

日常过得很快，几秒钟就足够记住今天。
```

### 此版本更新

```text
第一支影片，现在只需要三个 2 秒瞬间。

• 全新的首次体验，让你打开后更快开始拍摄。
• 「新建故事」现在更容易找到。
• 可以独自记录，也可以邀请朋友一起拍下同一天。
```

## Screenshot localization and order

Do not reuse the current Chinese screenshots for the U.S. localization. Capture
the app with its language set to English and use benefit-led artwork. The first
three matter most because they can appear in search results.

| Order | English headline | Chinese headline | Required screen |
| --- | --- | --- | --- |
| 1 | `3 moments. 1 daily film.` | `三个瞬间，一支每日影片` | First-run promise plus a visible finished-film preview |
| 2 | `Film your day in 2-second clips` | `用 2 秒片段，拍下这一天` | Populated story timeline |
| 3 | `Your video diary edits itself` | `不用剪辑，自动成片` | Finished film player, not another planning screen |
| 4 | `Capture the same day together` | `相隔再远，也能合拍同一天` | A real shared room with multiple people |
| 5 | `Private by default. Made on iPhone.` | `默认私密，只在本机生成` | Save/share result with a concise privacy callout |

Requirements:

- Export separate English and Simplified Chinese sets at 1320×2868.
- Keep the app UI truthful; marketing headlines may sit outside the device UI.
- Use large, short headlines and keep important text away from rounded corners.
- Show the blue mascot and the finished-film payoff in the first screenshot.
- Add a 15–20 second App Preview later: moments → recording → automatic film.

## Category and experiment plan

- Primary category: `Lifestyle`
- Secondary category: `Photo & Video`
- Do not change all fields repeatedly. Ship this set, record the date, then give
  search indexing 2–4 weeks before evaluating keyword movement.
- Track App Store Connect impressions → product page views → downloads by
  territory. Search rank without conversion is not the goal.
- Once traffic is sufficient, run Product Page Optimization on the first three
  screenshots. Keep metadata fixed during that test so the result is readable.

## Release identifiers

- App ID: `6794565199`
- Bundle ID: `com.cassie.AISetlog`
- Version: `1.2`
- Build: `6`

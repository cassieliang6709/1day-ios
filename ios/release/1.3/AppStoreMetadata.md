# 1Day 1.3 — App Store copy

Prepared 2026-09-17, for the `1.3 准备提交` version record in App Store Connect.

## What actually changes in the store listing

1.2 shipped on 2026-09-09 under the store name **`1_Day`** — the underscore was
never replaced with the name prepared in `../1.2/AppStoreMetadata.md`. That name
is still the right one, so 1.3 is the version that finally applies it.

| Field | Where it lives in ASC | Action |
| --- | --- | --- |
| 名称 | App 信息 → 可本地化信息 | **Change.** `1_Day` → the name below. Locked unless an editable version exists, which is why 1.3 had to be created first. |
| 副标题 | App 信息 → 可本地化信息 | **Set.** Never filled in for 1.2. |
| 关键词 | 版本页 | Unchanged from 1.2. |
| 推广文本 | 版本页 | **Replace.** New text below. This field alone can be edited later without review. |
| 描述 | 版本页 | Unchanged from 1.2, plus one optional new section (below). |
| 此版本的新增内容 | 版本页 | **New.** Empty on the 1.3 record. |
| 截屏 | 版本页 | **Re-shoot.** The three carried over from 1.2 predate the theme-color, cover, and replay work. |

Do not repeat words across 名称 / 副标题 / 关键词 — App Store search indexes all
three, so a repeat wastes characters that could carry another term.

## en-US

### Name (27 characters)

```text
1Day: Video Diary & Journal
```

### Subtitle (26 characters)

```text
Pick a Theme. Make a Vlog.
```

### Keywords (90 characters)

```text
memory,moments,camera,clips,recap,private,record,life,shared,friends,daily,travel,captions
```

### Promotional text (147 characters)

```text
New: pick your avatar color and the whole app follows it. Zoom while you film, give each story a cover, and restyle captions when you watch back.
```

### What's New (321 characters)

```text
Make it yours.

• Pick your avatar color — the whole app follows it.
• Zoom while you film: 0.5x, 1x, 2x, or pinch to anything in between.
• Give each story its own cover: pull a frame, pick a photo, or use a poster.
• Rebuilt replay, with captions you can pinch, rotate, and recolor.
• Blue now opens your film and signs its corner.
```

### Optional new description section

Insert after `A THEME TO GET YOU STARTED`, only if you want 1.3's theme reflected
in the description. Everything else in the 1.2 description stays as written.

```text
A LOOK THAT IS YOURS
Pick your avatar color and the whole app follows it. Give each story its own
cover, and set captions the way you want them in replay.
```

## zh-Hans

### Name (16 characters)

```text
1Day · 视频日记与生活记录
```

### Subtitle (15 characters)

```text
选个主题，把日常拍成 Vlog
```

### Keywords (53 characters)

```text
拍摄,剪辑,回忆,相机,影像,朋友,合拍,成长,相册,时间轴,故事,私密,本地,共同创作,旅行,片段,字幕
```

### Promotional text (62 characters)

```text
新增：挑一个头像颜色，整个 App 的主色跟着变。拍摄时能变焦，每个故事有自己的封面，回看时字幕能换色换样式。
```

### What's New (142 characters)

```text
让它变成你的样子。

• 挑一个头像颜色，整个 App 的主色跟着变。
• 拍摄时能变焦：0.5x、1x、2x，也能捏合到任意倍数。
• 每个故事有自己的封面：抽一帧、传照片，或用海报。
• 回看页重做，字幕能捏能转能换色。
• 小蓝出现在成片的片头和角标上。
```

### Optional new description section

```text
一眼就是你的样子
挑一个头像颜色，整个 App 的主色跟着变。每个故事有自己的封面，回看时字幕怎么放由你决定。
```

## Screenshots

Same five beats as the 1.2 kit (`../1.2/store-kit/`), re-shot on the current
build. 1320×2868, iPhone 6.9-inch, one set per language, English first three for
the US storefront.

| # | Screen | Why it is in the set |
| --- | --- | --- |
| 01 | Home / first-film entry | The 3 moments → 1 film promise, stated in one line |
| 02 | Theme or composer | Shows you do not have to think of anything yourself |
| 03 | Timeline mid-story | Shows progress and how little each step costs |
| 04 | Finished film | The payoff, and the best-converting frame |
| 05 | Replay or personalisation | What 1.3 added, and the reason to update |

The app accepts `-onboarding.completed.v1 YES` and `-appLanguage english|chinese`
as launch arguments (see `ios/AISetlogUITests/`), so both language sets come from
one harness rather than from resetting the simulator by hand.

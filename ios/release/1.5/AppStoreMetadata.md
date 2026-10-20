# 1Day 1.5 — App Store 文案草稿

2026-10-17 起草，对应构建版本 **1.5 (30)**。线上版本是 **1.4**（App Store Connect 首页显示「iOS 1.4 可分发」），所以「新增内容」写的是 1.4 → 1.5。

| 字段 | 在 App Store Connect 哪里 | 要不要改 |
| --- | --- | --- |
| 版本号 | 版本页 | 新建 1.5 |
| 构建版本 | 版本页 | 选 1.5 (30) |
| 副标题 | App 信息 → 可本地化信息 | **改**（见下） |
| 关键词 | 版本页 | **改**（见下） |
| 描述 | 版本页 | **改**：1.4 的描述还在讲「故事」和「一日 / 七日」 |
| 此版本的新增内容 | 版本页 | **新写**（见下） |
| 截图 | 版本页 | **重拍**：底栏、相机、我的页都换了 |
| App 隐私 | App 隐私 | **要改**（见文末） |
| 审核备注 | 版本页 → App 审核信息 | **重写**（见文末） |

## 副标题（≤ 30 字符）

- zh-Hans：`和朋友拍同一天的视频日记`（12 字）
- en-US：`Film one day, with friends`（26）

## 关键词（≤ 100 字符，逗号分隔，不加空格）

不放竞品名字：审核指南 2.3.7 禁止在关键词里用其他 App 的名字。

zh-Hans（49 字）：

```text
视频日记,vlog,一秒日记,每日视频,朋友,一起拍,共享相册,胶片相机,拍立得,复古,DV,心情日记,生活记录,剪辑
```

en-US（96 字符）：

```text
video diary,vlog,1 second,daily,friends,shared,film camera,polaroid,retro,dv,mood journal,journal
```

## 此版本的新增内容

### zh-Hans

```text
• 拍摄是主角：底栏中间一个圆钮，点一下拍 2 秒。
• 三台相机：DV 机、胶片机、拍立得，画幅、边框和日期直接拍进片子里。
• 前后摄同时拍：白边相纸小窗，可以拖动、缩放。
• 横拍按钮：点一下，边框、日期、变焦一起转过来。
• 「我的」改版：所有片段按天排好，完整显示每一格；点一段直接播这一天，还能改字幕。
• 今天的心情：选个表情、写一句或直接说，再和小方块聊两句，还能给它起名字。
• 成片配乐：原声 / 音乐 / 混合，换一首，也能自己录旁白。
• 和朋友的房间：每人一格，自动播大家今天的最新一段，爱心、回复、拍一拍。
```

### en-US

```text
• The camera comes first: one button in the middle, tap once for a 2-second clip.
• Three cameras — DV, film and instant — with frame, border and date filmed right in.
• Film front and back at once, with a draggable white-border inset.
• A landscape button that turns the frame, date and zoom with it.
• A new Mine tab: every clip by day, shown in full. Tap one to play that day and edit its caption.
• Today's mood: pick a face, write or say one line, then chat with the mascot — and give it a name.
• Music for your film: original sound, music or both, swap songs, or record a voiceover.
• Rooms with friends: one tile each, playing everyone's latest clip today, with likes, replies and nudges.
```

## 描述

要把 1.4 描述里的「故事」「一日 / 七日计划」删掉，改成「选题」和「房间」。结构建议：

1. 一句话：点一下拍 2 秒，1Day 把你的一天拼成一支片。
2. 三台相机
3. 和朋友一起拍（房间）
4. 我的：片段、心情、和小方块聊
5. 成片：配乐和旁白
6. 隐私：片段只在手机上，只有发到房间才上传

全文等截图定了再写，保证截图和描述说的是同一个东西。

## 截图（你来拍）

6.9 寸（1320×2868），中英文各一套。建议顺序（只有前 3 张会出现在下载弹窗里）：

1. 相机页（胶片机取景框 + 快门）
2. 成片页（播放器 + 声音面板）
3. 「我的」（心情卡 + 按天的片段网格）
4. 朋友房间（一人一格）
5. 三台相机选择
6. 和小方块聊天

## App 隐私：要改的

1.5 新增了一条上传路径：**和小方块聊天**会把当天的心情、那句话和聊天内容发到 `oneday-api.liangyue.site`，再转给 AI 生成回复。服务端不存聊天内容。

在原来申报的基础上，确认这些：

- **用户内容 → 其他用户内容：** 已经勾过（房间字幕、评论）。用途里**加上「App 功能」**之外不用加别的，说明里提到心情聊天。
- **是否用于追踪：** 否。
- **是否关联到身份：** 聊天请求只带一个随机的安装 ID（`DeviceIdentity.installID`），不带 Apple ID。可以对这类数据单独选「不关联」，但问卷是按类别填的，「其他用户内容」因为房间已经选了「关联」，保持「关联」即可（多报不会被拒）。
- **心情同步到 iCloud 私有数据库**：用户自己的私有库，不算开发者收集，不用申报。

## 审核备注（en-US）

```text
1Day records 2-second clips and stitches them into a short film on-device.

NO DEMO ACCOUNT NEEDED for the core loop:
  1. Launch → "Try it on my own first" (skips sign-in)
  2. Tap the round camera button in the middle of the tab bar
  3. Tap the shutter once — it films 2 seconds and stops by itself
  4. Tap "Save to Mine". The clip appears in the Mine tab
  5. In Mine, tap "Select", pick a few clips, tap "Make vlog"
     — the film plays with music; Original / Music / Mix and voiceover sit under it

Mood chat: in Mine → Today's mood, pick a face, then "Chat with ...".
The mood and the short chat are sent to our server to generate one reply
(no account, no storage). It replies with a fixed line when offline.

Shared rooms ("With friends") need two devices signed in with two Apple IDs
via Sign in with Apple.

Permissions: camera and microphone to film; speech recognition only when the
user taps the mic to dictate (on-device when supported).
```

## 上架前还要做的（不在这份文案里）

1. **CloudKit 正式环境部署**：相机字段、拍一拍、心情同步的新字段。不部署，正式版的房间相机、心情同步会失效。
2. **配乐**：现在 6 首是合成的占位曲，换成正式授权的音乐（同名文件替换 `ios/AISetlog/Resources/Music/`）。
3. **中国大陆区**：小方块聊天是生成式 AI，确认是否需要备案；不确定就先在中国区关掉聊天。

# 1Day 1.6 — App Store 提交清单

2026-11-25 起草，对应构建版本 **1.6 (37)**，已上传 TestFlight。线上版本是 **1.5**（2026-11-02 上架），「新增内容」写的是 1.5 → 1.6。

## 按顺序做

1. App Store Connect → 1Day → 左上角「+」新建 iOS 版本 `1.6`
2. 「构建版本」选 **1.6 (37)**（处理完才会出现，通常 10–30 分钟）
3. 填「此版本的新增内容」（见下）
4. 截图：房间页改了（日期条、头像行、3:4 片子），第 4 张房间截图要重拍
5. 左侧「App 隐私」→ 编辑（见下，这是这次最大的改动）
6. 「App 审核信息」→ 审核备注换成下面的版本
7. 点「添加以供审核」→「提交审核」

## 此版本的新增内容

### zh-Hans

```text
• 房间换了新样子：一条日期，点哪天看哪天，有人拍的日子下面有个点。
• 片子完整显示，不再被裁掉。
• 点朋友的头像只看 TA 今天的，长按看 TA 的全部，双击拍一拍。
• 给片子回个表情，回过的表情和回的人显示在片子右上角。
• 用 Apple 或 Google 账号登录，换手机也能找回房间。
• 「我的」右上角日历：点一天，只看那天的片子。
• 「帮我挑」：AI 帮你从一天里挑几段做成 vlog，还会起个标题。
• 朋友拍了、拍了拍你、给你留言时会收到通知。
```

### en-US

```text
• A new room page: one row of dates — tap a day to see it, and days with clips get a dot.
• Clips are shown in full, never cropped.
• Tap a friend to see just their clip today, long-press to see all of theirs, double-tap to nudge.
• React to a clip with an emoji; reactions and who sent them sit in the top corner.
• Sign in with Apple or Google and get your rooms back on a new phone.
• "Pick for me": AI picks a few clips from your day for a vlog and gives it a title.
• Get a notification when a friend films, nudges you or leaves a comment.
```

## App 隐私：要改的

1.5 的数据存在 CloudKit。1.6 起房间数据存在我们自己的服务器（Cloudflare，`oneday-api.liangyue.site`），所以要按「开发者收集」重新申报。下面每一项都是「用于 App 功能」「关联到用户身份」「不用于追踪」。

| 问卷里的类别 | 收的是什么 | 依据 |
| --- | --- | --- |
| 联系信息 → 姓名 | 房间里显示的名字 | `members.display_name` |
| 用户内容 → 照片或视频 | 发到房间的片段 | `clips` 表 + 媒体存储 |
| 用户内容 → 其他用户内容 | 字幕、留言、表情回应、拍一拍、心情和心情备注 | `clips.overlay_text`、`comments`、`reactions`、`pokes`、`moods.note` |
| 标识符 → 用户 ID | Apple / Google 登录后的账号 ID | `members.user_id` |
| 标识符 → 设备 ID | 推送 token | `devices.token` |

要你确认的两点（代码里没查到，别猜）：

- 登录时有没有存邮箱：登录走 `auth.liangyue.site`，这个服务不在本仓库里。存了就加「联系信息 → 电子邮件地址」。
- 「帮我挑」和 AI 标题会把片段的**文字标签**（时间、字幕这类文字，不是视频）发到 DeepSeek，服务端不存。问卷里这属于「其他用户内容」，上面已经勾了；在隐私政策里要写明会发给第三方 AI 服务。

## 审核备注（en-US）

```text
1Day records short clips and stitches them into a film on-device.

No sign-in is needed to try the app. On the first screen tap
"Try it on my own first". Filming, Mine and making a vlog all work without
an account, and clips stay on the device.

Sign-in is asked for only when a feature shares with friends: creating a room,
joining with an invite code or link, and sending a clip to a room. Sign in with
Apple and Sign in with Google are offered; your own Apple ID works, and no demo
account is needed. After signing in, the action you tapped continues.

Core loop, no account:
  1. Tap the Camera tab, tap the shutter once (it films a short clip)
  2. Tap "Done". The clip appears in Mine
  3. In Mine, tap "Make vlog" → "Make" to stitch the day's clips
Rooms with friends need two signed-in accounts on two devices:
  create a room, send the invite code, join with the code on the second device.
  In a room: tap a date to see that day, tap a friend's avatar to see only
  their clip, long-press for all of theirs, double-tap the avatar to send a
  nudge (a push notification to that friend). Double-tap a friend's clip to
  send a heart; long-press it for more reactions.

"Pick for me" sends the text labels of the user's clips (times and captions,
not the video) to our server, which asks DeepSeek to choose clips and suggest
a title. Nothing is stored. It falls back to an on-device pick when offline.
```

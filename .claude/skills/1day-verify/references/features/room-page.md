# 房间里面

点开一个房间之后看到的页面：每个人的片段、日历、视图切换、单人页、改房间名、右上角菜单。

## 子功能

- 一人一格（默认视图）：每个成员一格 `room-frame`，格子上的人 `room-frame-person`，片段小图 `room-clip-tile`。竖拍房间按人数排成网格，横拍房间每人一张 16:9 卡片上下排。
- 成员头像排：标题下面一排小头像 `room-story-face`。当天拍了的人显示头像加圈，没拍的是灰点。点一个人只看这个人，其他人变淡。
- 瀑布流视图：`room-column`。在「视图」菜单 `room-layout` 里切换「默认」和「瀑布流」。
- 单人页：点一个人的格子进去，看这个人的所有片段 `room-person-clip`，点 `room-person-back` 回来。
- 拍一段：格子上的 `room-feed-film`（「拍一段」）直接进相机，拍完发到这个房间。
- 日历：`room-calendar` 或 `room-feed-calendar` 选某一天，`room-calendar-all`（「看全部日期」）回到全部。选了某天时日历按钮会变色。
- 时刻条（计划类房间）：`diary-film-<n>`（「开拍」）、`diary-play-<n>`、`filmstrip-add-yours-<n>` / `timeline-add-yours-<n>`（「加上你的」）、`filmstrip-cta`。
- 改房间名：点标题 `room-title`，出现输入框 `room-title-field`，输入后确认。
- 顶部按钮：`room-back` 返回、`room-chat` 聊天、`room-invite` 邀请、`room-more` 更多。
- 「更多」菜单里有：预览成片、生成 vlog `room-make-vlog`、视图、改计划、退出房间（自己一个人的计划显示删除）、同步失败时的重试。
- 没登录时：`room-sign-in`、`room-frame-sign-in`。

## 用户怎么找到它

房间页点一张房间卡片。也可以点推送通知进来。

## 怎么操作

- 直接打开某个房间：`scripts/agent/open-link.sh story/<uuid>`。现在没有直接列出 uuid 的办法：`dump-state` 只输出数量。要 uuid 时用 `scripts/agent/debug.sh` 在 `ChallengeStore` 里打断点看 `challenges`，或者直接点卡片进去。
- 片段不同步时：`scripts/agent/open-link.sh sync`，同时开 `scripts/agent/worker-tail.sh --search /rooms` 看请求。
- 模拟器上要多人房间：启动参数 `-demoEntries YES -demoRoomMembers 小蓝,小白`，见 [driving.md](driving.md)。

## 验证

| 编号 | 功能 | 入口 | 怎么走 | 屏幕上算成功 | 服务器证据 | 要真人 | 对外写 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F7 | 打开房间看片段 | `room-clip-tile` / `room-frame` | 点一个有片段的房间 | 片段小图有画面，点开能播放，有声音 | `room <CODE>`：`clips` 数和屏幕上一致 | 否 | 否 |
| F22 | 日历选一天 | `room-calendar` | 选一天 → 再点 `room-calendar-all` | 只剩那天的片段；回到全部后片段数恢复 | — | 否 | 否 |

## 容易出错的地方

- `room-clip-tile`、`room-feed-film`、`room-tile-poke` 在默认视图和瀑布流视图里都有，切了视图后 `phone_elements` 读到的位置会变。
- 改房间名对房间里所有人可见，只在测试房间里做。
- 「更多」是 SwiftUI `Menu`，弹出来的菜单项没有 identifier，用 `phone_tap_label` 按文字点。

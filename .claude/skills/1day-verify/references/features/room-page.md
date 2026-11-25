# 房间里面

点开一个房间之后看到的页面：日期条、头像行、片子、单人页、聊天栏、改房间名、右上角菜单。

## 子功能

- 日期条：`room-date-strip`，一周 7 天，有人拍的日子下面有点。左右滑换周；标题行 `room-month`（「11月 ⌄」）展开整月；翻到别处时出现 `room-back-to-today`（「今天」）。
- 头像行：`room-people`。自己的头像 `room-people-me`（今天点了直接拍）；别人的头像 `room-people-filmed`（选中那天拍了）或 `room-people-person`（没拍），点了都进这个人的单人页。
- 片子：`room-frame`，里面的片子 `room-clip-tile`。格子固定 3:4（横拍房间 4:3），按剩余空间等比缩放，整条视频不裁切。今天还没人拍时是 `room-film-today`（「拍一段」）。
- 单人页：这个人所有日子的片段，新的在前，`room-person-back` 返回。这个人今天没拍时右上角有 `room-person-poke`（「拍一拍」）。
- 底部：表情按钮、`room-chat-field`（「说点什么…」）、`room-chat`（「聊天」）。今天没有别人的片子时，在输入框按发送会把字带进聊天页，再点发送。
- 改房间名：点标题，出现输入框，输入后确认。
- 顶部按钮：返回、「做 vlog」、`room-more` 更多。邀请在头像行最后 `room-invite`。
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
| F22 | 日期条选一天 | `room-date-strip` | 点有点的过去一天 → 点「今天」 | 只剩那天的片段；回到今天 | — | 否 | 否 |
| F27 | 看一个人的全部片段 | `room-people-filmed` / `room-people-person` | 点别人的头像 | 进单人页，所有日子的片段都在；点头像不会发拍一拍 | — | 否 | 否 |

## 容易出错的地方

- 拍一拍只在单人页的 `room-person-poke` 和长按片子的菜单里，会真的推送给朋友：只在测试房间里点。
- 改房间名对房间里所有人可见，只在测试房间里做。
- 「更多」是 SwiftUI `Menu`，弹出来的菜单项没有 identifier，用 `phone_tap_label` 按文字点。

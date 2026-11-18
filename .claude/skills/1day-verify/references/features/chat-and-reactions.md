# 聊天、回应、拍一拍、推送

房间里和朋友互动的几种方式。全部会被房间里其他人看到。

## 子功能

- 聊天：房间顶部 `room-chat`（「聊天」）打开，`chat-input` 输入，`chat-send` 发送，`chat-done` 关闭。
  - `chat-clip`：聊天里显示的「某人发了一段」事件
  - `chat-moment-about` / `chat-moment-quote`：针对某个片段聊，引用那段
  - `chat-local-demo-banner`：示例房间里的提示条，说明消息不会发出去
- 表情回应：片段回看页的 `add-reaction`，`any-emoji` 输入任意表情。
- 拍一拍：成员格子上的 `room-tile-poke`（「拍一拍」），拍过之后格子变灰，显示已拍。
- 推送：朋友发片段或消息时收到通知，点开进到那个房间。

## 用户怎么找到它

进房间 → 右上角聊天气泡。表情回应要先点开一段片段。拍一拍在还没拍片段的成员格子上。

## 怎么操作

- 消息没发出去：`scripts/agent/app-logs.sh --category api` 和 `scripts/agent/worker-tail.sh --errors` 同时看。
- 推送没到：`scripts/agent/worker-tail.sh --errors` 看 Worker 发推送时有没有报错（`workers/api/src/push.js`），再用 `sql` 查 `device_rooms`。

## 验证

| 编号 | 功能 | 入口 | 怎么走 | 屏幕上算成功 | 服务器证据 | 要真人 | 对外写 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F12 | 聊天 | `room-chat` → `chat-input` → `chat-send` | 发一句「测试」 | 消息出现，不再显示发送中 | `recent 5`：一条 `comment` 行 | 否 | **是**，只在测试房间做 |
| F13 | 回应 | `add-reaction` | 给一段片段点一个表情，再点掉 | 表情出现又消失 | `recent 5`：`reaction` 行出现；点掉后 `sql` 查不到 | 否 | **是**，只在测试房间做 |
| F14 | 拍一拍 | `room-tile-poke` | 拍一个成员 | 那格变灰，显示已拍 | `recent 5`：一条 `poke` 行 | 否 | **是**（对方会收到推送），先问用户 |
| F15 | 收到推送 | — | 另一个账号在同一房间发消息 | 锁屏出现通知，点开进到那个房间 | `sql`：`device_rooms` 有这个房间 | **是**（要第二个账号或朋友配合） | 是 |

## 容易出错的地方

- 拍一拍会给对方发真的推送。测试房间里只有自己时没有可拍的人，所以 F14 一定要先问用户。
- 模拟器收不到真推送，F15 只能在真机上验。
- 示例房间（`-demoEntries`）里的聊天只存在本机，有 `chat-local-demo-banner`，不能当服务器证据。

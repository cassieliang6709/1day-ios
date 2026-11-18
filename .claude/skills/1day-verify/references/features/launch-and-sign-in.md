# 启动与登录

打开 App 到能用为止：冷启动、第一次打开的引导、权限说明、登录。

## 子功能

- 首次引导：新装、而且没有任何房间或计划时才出现。已有房间的老用户永远不会看到。
- 权限说明：在系统弹相机、麦克风、通知权限之前，先出一页说明，按 `permission-ok` 继续。
- Apple 登录：`rooms-sign-in`（房间页）、`settings-sign-in`（设置）、`room-sign-in`（房间页里）、`room-frame-sign-in`（没登录时房间格子上）。
- Google 登录：登录页里的 `google-sign-in`。

## 用户怎么找到它

没登录时，房间页顶部有登录提示，点它出登录页。也可以点左上角头像进设置，从设置里登录。

## 怎么操作

- 重看首次引导：`scripts/agent/open-link.sh reset-onboarding`，然后杀掉 App 重开。前提是 App 里没有任何房间或计划。
- 登录这一步 agent 做不了，见下面「要真人」。

## 验证

| 编号 | 功能 | 入口 | 怎么走 | 屏幕上算成功 | 服务器证据 | 要真人 | 对外写 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F1 | 冷启动 | 桌面图标 | 杀掉 App 再启动 | 3 秒内出现首屏，没有黑屏或白屏 | — | 否 | 否 |
| F2 | Apple 登录 | `rooms-sign-in` / `settings-sign-in` | 点登录 → 通过 Apple 登录 | 「没登录」提示消失，设置里显示名字 | `recent`：出现本人的 `device` 行（开了通知时） | **是**（Face ID / 密码） | 否 |
| F3 | Google 登录 | `google-sign-in` | 点 Google 按钮 | 同 F2 | 同 F2 | **是** | 否 |

## 容易出错的地方

- Apple 和 Google 在服务器上是两个不同的人。验证老房间时用 Apple 登录。
- 冷启动的耗时要在真机上看，模拟器上的数字是 Mac 的。要数字就用 `scripts/agent/trace.sh --device --launch`。
- 系统权限弹窗只弹一次。想再看一次要删掉 App 重装。

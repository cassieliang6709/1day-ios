# 设置和头像

设置是一个 sheet：头像、名字、皮肤、语言、登录状态、退出登录、删除账号。头像设置流程登录后出现一次，之后在设置里点头像可以重新做。

## 子功能

- 头像：`settings-avatar`（「点一下重画头像」）打开头像设置流程，`avatar-retake` 重拍。
- 名字：`your-name` 输入框。
- 皮肤：奶油黄 / 经典蓝。换皮肤后 App 会重新打开设置页。
- 语言：跟随系统、中文、英文。
- 登录：`settings-sign-in`；已登录时显示用 Apple 登录的账号、退出登录、删除账号。
- Debug 构建才有：`settings-debug-create-test-room`（「创建测试房间」），建一个带两个假朋友片段的真房间。
- 头像设置流程（三步：给我看看你 → 正在画你 → 画好了）：
  - 来源：`avatar-take-photo`（拍一张）、`avatar-pick-photo`（从相册挑）、`avatar-memoji`（用我的 Memoji）、`avatar-builtin-<name>`（用这个小人）
  - 生成方式：`avatar-genmoji`（做成 emoji）、`avatar-image-playground`（让苹果画一张）
  - 结果：`avatar-result`，`avatar-redraw` 重画，`avatar-new-photo` 换照片，`avatar-confirm` 确认，`avatar-done` 完成
  - 第一步的 `avatar-skip`（「先不用头像」）只在登录后那次出现；从设置进来的是关闭按钮
  - `avatar-debug-path`：Debug 构建才有

## 用户怎么找到它

房间页**左上角自己的头像**，点一下打开设置。这个按钮没有 identifier，accessibility label 是「设置」，用 `phone_tap_label` 点。

## 怎么操作

- 直接打开头像流程：`scripts/agent/open-link.sh avatar`，或启动参数 `-debugAvatarFlow YES`。
- 头像相关的其他 Debug 启动参数：`-debugAvatarSample`、`-debugAvatarPath`、`-debugAvatarForceFallback`，含义看 `AvatarSetupFlow.swift` 和 `AvatarStore.swift`。

## 验证

| 编号 | 功能 | 入口 | 怎么走 | 屏幕上算成功 | 服务器证据 | 要真人 | 对外写 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F18 | 换头像 / 改名字 | `settings-avatar` / `your-name` | 设置里改 | 房间里我的头像或名字跟着变 | `recent 5`：本人的 `member` 行更新 | 否 | 是（朋友看得到），先问用户 |
| F19 | 退出登录 | 设置 → 退出登录 | 退出 | 房间页出现「没登录」 | `sql`：本人的 `devices` 行没了 | 否 | 否 |
| F26 | 头像流程走完 | `open-link.sh avatar` → `avatar-builtin-<name>` → `avatar-confirm` | 选一个内置小人 → 确认 | 回到原页面，设置里的头像换成这个小人 | 同 F18 | 否 | 是（朋友看得到），先问用户 |

## 容易出错的地方

- 拍的照片只在头像流程里用，关掉就丢了，只保存画好的头像。
- Genmoji 和「让苹果画一张」要系统支持 Apple Intelligence，不支持的设备上可能不出现。
- **删除账号不在验证范围里。** 它会删掉云端的真实数据，只在用户明确要求、并且用测试账号时才做。
- 退出登录后再登录要用户本人操作（Face ID），F19 做完要提醒用户登回去。

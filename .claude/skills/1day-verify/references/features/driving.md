# 不点屏幕就能操作 App 的工具

下面这些只在 **Debug 构建**（1Day Dev，`com.cassie.AISetlog.dev`）里有效。脚本都在仓库根目录的 `scripts/agent/`，不带参数运行会打印用法。

## 直接跳到某个页面：调试深链

路由定义在 `ios/AISetlog/App/DebugDeepLink.swift`。

| 路径 | 作用 |
| --- | --- |
| `surface/plans` | 「我的」 |
| `surface/friends` | 房间页 |
| `surface/compose` | 新建 |
| `surface/camera` | 相机 |
| `story/<uuid>` | 在「我的」里打开这个房间或计划 |
| `avatar` | 在当前页面上打开头像设置流程 |
| `reset-onboarding` | 下次启动重新走首次引导（只在没有任何房间或计划时出现） |
| `seed-library` | 重新塞一遍「我的」里的示例片段 |
| `sync` | 立刻同步所有房间 |
| `dump-state` | 把房间数、草稿数、登录状态写进日志 |

三种发法：

```bash
scripts/agent/open-link.sh surface/camera            # 模拟器，不用点确认
scripts/agent/open-link.sh --device surface/camera   # 真机，iOS 会问「在 1Day Dev 中打开？」，要点「打开」
xcrun simctl launch --terminate-running-process booted com.cassie.AISetlog.dev -debugLink surface/camera   # 启动时直接到
```

真机上用 iphone-use 时，系统弹窗用 `phone_tap_label` 点「打开」。

## 启动参数

用 `xcrun simctl launch ... -参数 值` 或 `devicectl ... process launch` 传进去。

| 参数 | 作用 |
| --- | --- |
| `-demoEntries YES` | 塞示例房间和片段 |
| `-demoRoomTitle` / `-demoRoomMembers` / `-demoRoomMoments` / `-demoRoomOrientation` | 示例房间的名字、成员（逗号分隔）、时刻、竖拍横拍，见 `LocalRoomRuntime.swift` |
| `-simulatedCamera YES` | 模拟器上假装有相机，按快门会出一段示例片段 |
| `-debugAvatarFlow YES` | 启动后直接打开头像设置流程 |
| `-debugSeedLibrary YES` | 启动时塞「我的」示例片段，只塞一次；再塞用深链 `seed-library` |
| `-debugLink <路径>` | 启动后发一条调试深链 |

### 本地示例房间（Debug 或 `LOCAL_ROOM_CHAT_DEMO` 构建）

`-demoEntries YES` 塞进来的房间用的是正式的房间页、回看、成片和聊天界面，只是数据只在本机。相关 identifier：

- `local-formal-room`：示例房间本身
- `local-room-members`：示例成员
- `local-room-notice`：提示数据只在本机
- `local-room-import`：从相册导入一段视频当示例片段，失败时显示 `local-room-import-error`

在这里做的任何操作都不会出现在 D1，不能当服务器证据。

## 看 App 自己的日志

日志分类在 `ios/AISetlog/Services/Log.swift`：api、sync、app、debug。

```bash
scripts/agent/app-logs.sh --url oneday://debug/dump-state   # 发一条深链再看 20 秒
scripts/agent/app-logs.sh --last 5m --category api          # 最近 5 分钟的网络请求
```

真机加 `--device`，需要 sudo，会提示怎么做。

## 断点：lldb

```bash
scripts/agent/debug.sh --break OneDayAPI.swift:140
scripts/agent/debug.sh --break 'ChallengeStore.syncRoom' --url oneday://debug/sync
```

停在断点后打印调用栈和变量，然后自动退出。

## 性能：xctrace

```bash
scripts/agent/trace.sh --seconds 30 --url oneday://debug/surface/camera
scripts/agent/trace.sh --device --launch    # 真机，包含启动，数字才准
```

模拟器上的耗时是 Mac 的耗时，判断卡不卡要用 `--device`。

## 后端：Worker 实时日志

```bash
scripts/agent/worker-tail.sh --errors
scripts/agent/worker-tail.sh --search /rooms --seconds 120
```

需要先 `wrangler login` 一次。服务器证据（数据库里的行）还是用 `scripts/d1_read.py`。

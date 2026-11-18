# scripts/agent — 给 agent 用的调试工具

改完代码后，agent 用这几个脚本自己看 App 在干什么，不用人去点、去看。默认目标是已经启动的模拟器，加 `--device` 换成配对的 iPhone。每个脚本都支持 `-h`。产物写到 `/tmp/1day-agent/`。

| 想知道什么 | 脚本 | 例子 |
| --- | --- | --- |
| App 内部走到哪一步、请求返回什么 | `app-logs.sh` | `app-logs.sh --seconds 30`、`app-logs.sh --last 5m --category api` |
| 直接跳到某个页面或状态 | `open-link.sh` | `open-link.sh surface/camera`、`open-link.sh dump-state` |
| 某一行代码执行时变量是什么 | `debug.sh` | `debug.sh --break OneDayAPI.swift:140 --url sync` |
| 哪里慢、启动花了多久 | `trace.sh` | `trace.sh --launch --seconds 10` |
| 后端报了什么错 | `worker-tail.sh` | `worker-tail.sh --seconds 60 --errors` |

## App 日志（Log.swift）

subsystem 是 `com.cassie.AISetlog`，分 4 个 category：

- `api`：每个 Worker 请求一行，包括方法、路径、状态码、毫秒数。不记 query、header 和 token。
- `sync`：房间同步的开始、结束和跳过原因。
- `app`：回到前台、深链。
- `debug`：调试深链收到了什么、`dump-state` 的结果。

新加日志用 `Log.api.info(...)` 这种写法。值要标 `privacy: .public`，不然真机上会显示成 `<private>`。token、邮箱、聊天内容不要写进日志。

## 调试深链（DebugDeepLink.swift，只在 Debug 构建里有）

| 路由 | 作用 |
| --- | --- |
| `surface/plans` `friends` `compose` `camera` | 切到这个页面 |
| `story/<uuid>` | 打开这个故事的时间线 |
| `avatar` | 打开头像流程 |
| `reset-onboarding` | 下次重新走首次引导（没有故事时才会显示） |
| `seed-library` | 往「我的」里塞示例数据，已经跑过也会再跑一次 |
| `sync` | 马上同步所有房间 |
| `dump-state` | 把故事、房间、草稿数量和登录状态写进日志 |

发送方式有三种：

1. **模拟器（推荐）**：`open-link.sh <路由>`。脚本把路由写进 App 沙盒的 `Library/Caches/debug-link.txt`，再发 Darwin 通知 `com.cassie.AISetlog.debug.link`。不会弹框，但 App 要在运行。
2. **启动参数**：`xcrun simctl launch --terminate-running-process booted com.cassie.AISetlog.dev -debugLink surface/camera`。真机用 `devicectl ... launch` 加同样的参数。代价是 App 会重启。
3. **URL** `oneday://debug/<路由>`：iOS 每次都会弹「在 1Day Dev 中打开？」，要点「打开」。真机上的 `open-link.sh --device` 走的是这条。

相机和麦克风的权限框可以先授权掉：

```bash
xcrun simctl privacy booted grant camera com.cassie.AISetlog.dev
xcrun simctl privacy booted grant microphone com.cassie.AISetlog.dev
```

## 已知限制

- **真机都没测过。** `debug.sh --device` 用的是 Xcode 16 以后 lldb 的 `device process attach`。`app-logs.sh --device` 要 `sudo log collect`，agent 没有 sudo 时改用 iphone-use 的 `phone_logs`。
- 模拟器上 `trace.sh` 测出来的是 Mac 的速度，看相对占比可以，绝对耗时以真机为准。
- `trace.sh` 挂到空闲的 App 上，会显示 no samples。这时加 `--launch`，或者用 `--url` 让 App 做点事。
- `debug.sh` 的断点要等 `AISetlog.debug.dylib` 加载后才解析，日志里先出现 `pending`，之后出现 `1 location added`，这是正常的。
- `worker-tail.sh` 需要先 `wrangler login`。每个请求一行的 JSON 日志要等 `workers/api` 部署后才会出现，部署前只有 wrangler 自带的那一行。

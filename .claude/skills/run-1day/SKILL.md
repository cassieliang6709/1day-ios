---
name: run-1day
description: 编译、安装、启动 1Day iOS App（AISetlog），装到 Cassie 的 iPhone 上截图看效果；手机连不上时退到模拟器。用户说「跑起来」「装到手机上」「截个图」「看看现在什么样」「开模拟器」，或改完代码要确认界面真的渲染出来、不只是编译过时使用。不用于：逐项验证功能并查 D1（用 1day-verify）。
---

# run-1day

| | |
|---|---|
| Xcode 工程 | `ios/AISetlog.xcodeproj`（由 `ios/project.yml` 生成，不在 git 里） |
| Scheme | `AISetlog` |
| Bundle ID | `com.cassie.AISetlog` |
| 最低系统 | iOS 17.0，只支持竖屏、只支持 iPhone（`TARGETED_DEVICE_FAMILY: "1"`） |

**Cassie 的规则（2026-10-30）：在模拟器上做的事（看页面、点流程、截图）都改到她的 iPhone 上，用 `iphone-use` MCP 做。** 按下面「真机（Path B）」第 1～4 步安装，用第 6 步的 `phone_*` 工具操作。手机连不上（调一次 `phone_reconnect` 后 `phone_status` 还没就绪）时，才按 [references/simulator.md](references/simulator.md) 用模拟器（Path A），并告诉用户换成了模拟器，不悄悄换。项目没有自动化测试（2026-11-21 全部删除）。

## 开始前：有没有别人在这个目录里写代码

```bash
git -C . status --short | wc -l          # 干净的起点应该是 0
ps aux | grep -c "[c]laude --dangerously-skip-permissions"
```

编译错误出在你没碰过的文件里，就说明有别人在写。这个仓库出过两次事：见 `progress.md` §1 的「并发事故记录」；还有 2026-09-15，会话中途 28 个文件变成已修改，`DayClip` 上一个写了一半的 `captionSticker` 字段把 `LocalRoomRuntime.swift` 编译搞坏了，而当时正在验证的是一个无关的配色改动。

**不要绕过去编译，也不要顺手修好它。** 那是别人写了一半的功能，替人写完只会让冲突更大。

不碰别人的改动也能验证自己的改动：在 `HEAD` 建一个临时 worktree，只把自己改的文件拷进去。

```bash
git worktree add /tmp/1day-verify HEAD --detach
cp ios/AISetlog/<你改的每个文件> /tmp/1day-verify/ios/AISetlog/<同样的路径>
cd /tmp/1day-verify
xcodegen generate --spec ios/project.yml --project ios   # .xcodeproj 不在 git 里
xcodebuild -project ios/AISetlog.xcodeproj -scheme AISetlog -configuration Debug \
  -destination 'id=<SIM_UDID>' -derivedDataPath /tmp/1day-dd-verify build 2>&1 \
  | grep -E "error:|BUILD"
# 用完：git worktree remove /tmp/1day-verify --force
```

`xcodegen` 这一步不能省：`.gitignore` 排除了 `ios/AISetlog.xcodeproj`，新 worktree 里根本没有工程文件。

装到真机的包也从这个 worktree 编，不从被污染的目录编，否则装到她手机上的包里带着别人没写完的东西。

## 真机（Path B，已验证到安装）

### 1. 找到设备

```bash
xcrun devicectl list devices
```

取标着 `available (paired)` 的那一行。Cassie 的是 `00008150-000A082A3A68C01C`（iPhone 17 Pro Max，有线；2026-10-13 之前是 `6BAD8B60-…`，现在 `devicectl` 列的是硬件 UDID）。同一台硬件有几行过期的 `unavailable` 是正常的，忽略。

### 2. 手机要解锁，并且保持亮屏

锁屏时下面每一步都会失败，报错不同，意思一样：

| 步骤 | 锁屏时的报错 |
|---|---|
| 用 `-destination 'id=…'` 编译 | `The developer disk image could not be mounted on this device.`，然后 `Timed out waiting for all destinations` |
| `devicectl device install app` | `kAMDMobileImageMounterDeviceLocked: The device is locked.` |
| `devicectl device process launch` | `FBSOpenApplicationErrorDomain error 7 … Locked` |

手机会按自动锁定时间自己锁屏，动作慢了就会在安装和启动**之间**锁上。请她把「设置 → 显示与亮度 → 自动锁定」改成「永不」，或者用第 5 步轮询。

`devicectl device info lockState` 报的 `passcodeRequired` / `unlockedSinceBoot` 都不能说明手机**现在**锁没锁。不用查，直接执行操作看报错。

### 3. 编译：不要按设备 id 指定目标

```bash
cd ios
xcodebuild -project AISetlog.xcodeproj -scheme AISetlog -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/1day-dd-dev \
  -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD"
```

关键是 `-destination 'generic/platform=iOS'`。按设备 id 指定时，`xcodebuild` 要先解析目标设备，这一步要挂载 DDI，挂载要求手机解锁。所以手机一锁，连**编译**也会在 60 秒超时后失败。用 generic 就分开了：编译总能成功，只有安装和启动要求解锁。

`-allowProvisioningUpdates` 让 Xcode 自动生成 team 的 provisioning profile。签名身份是 `Apple Development: liang.yue@northeastern.edu`，team `M7BPQ88622`。

产物在 `/tmp/1day-dd-dev/Build/Products/Debug-iphoneos/AISetlog.app`。

`grep` 不能省：完整编译日志约 5000 行，读它是这里最浪费时间的事。`error:` 加 `BUILD` 就是全部有用的信息。

### 4. 安装并启动

**用 `&&` 连在一条命令里。** 分两次调用，中间的空档里手机会自动锁屏：安装成功了，启动返回 `Locked`，又得重新轮询。2026-09-15 出现过两次。

```bash
DEV=00008150-000A082A3A68C01C
APP=/tmp/1day-dd-dev/Build/Products/Debug-iphoneos/AISetlog.app
xcrun devicectl device install app --device $DEV "$APP" && \
xcrun devicectl device process launch --device $DEV --terminate-existing com.cassie.AISetlog
```

成功时会看到 `installationURL: file:///private/var/containers/...` 和一个 `processIdentifier`。

安装成功、只有启动失败时，**就算完成**：包已经在她手机上，她点图标就能打开。不要花三分钟轮询启动，说「已经装上」然后继续。

### 5. 轮询，不要一直催

她不在手机旁边时，让它自己装上，不要问了再等：

```bash
for i in $(seq 1 12); do
  out=$(xcrun devicectl device install app --device $DEV "$APP" 2>&1)
  echo "$out" | grep -q "installationURL" && { echo "INSTALLED (try $i)"; break; }
  echo "try $i: locked"; sleep 15
done
```

`process launch` 也是一样的写法，匹配 `processIdentifier`。最多约 3 分钟，超过就说超时了，不要一直悄悄循环。

### 6. 看屏幕和点击：`iphone-use` MCP

开源项目 [leeguooooo/iphone-use](https://github.com/leeguooooo/iphone-use)：Mac 上一个 daemon，加上手机上它自己的 XCTest runner（USB 或 Wi-Fi）。装在 `~/Applications/iPhoneUse.app`，MCP server 名字是 `iphone-use`（user scope）。

| 要做的事 | 工具 |
|---|---|
| 能不能用 | `phone_status`；不行就调一次 `phone_reconnect` |
| 截图 | `phone_screenshot`（截完要真的看图，黑屏就是失败） |
| 把屏幕读成文字 | `phone_elements`（用 `query` 过滤） |
| 点击 | 先用 `phone_tap_label`；只能按位置点的控件用 `phone_tap`（x/y 取 0～1） |
| 输入 / 滚动 | `phone_type`、`phone_scroll` |
| 崩溃 / 日志 | `phone_crashes`、`phone_logs`（`process: "AISetlog"`） |
| 录一段操作 | `phone_record` 开始/停止，MP4 存在 Mac 上 |

用 `devicectl` 安装启动（第 4 步），再用这些工具操作。手机还是要解锁；在终端跑 `iphone-use doctor` 会说缺什么。装上了不等于能用，要截图看。

启动返回了 PID 只说明程序起来了，不说明画面渲染出来了。这个 App 的历史里全是黑屏 bug（`progress.md` §3，build 13–19）。黑屏、白屏都算失败。

## 跳页面、看日志、断点、性能：`scripts/agent/`

一路点过去之前，先看 `scripts/agent/README.md`：

- `open-link.sh surface/camera`（还有 `story/<uuid>`、`seed-library`、`dump-state` 等）在运行中的 Debug 版里直接切页面，不弹确认。`simctl openurl oneday://...` 也行，但 iOS 每次都会问「在 1Day Dev 中打开？」。
- `app-logs.sh --seconds 20` 输出 App 自己的日志（每个 Worker 请求的状态码和耗时、房间同步、调试链接）。
- `debug.sh --break File.swift:LINE --url <route>` 在 lldb 里停在那一行，打印 `bt` 和 `frame variable` 后断开。
- `trace.sh --launch` 录 Time Profiler，列出最重的 1Day 函数。

## 重新生成 Xcode 工程

改了 `ios/project.yml`，或者新加的 `.swift` 文件没被编译时：

```bash
xcodegen generate --spec ios/project.yml --project ios
```

**参数顺序不能换。** `xcodegen --project ios/AISetlog.xcodeproj` 会把 `--project` 当成**输出目录**，生成一个嵌套的 `AISetlog.xcodeproj/AISetlog.xcodeproj/`，真正的工程没变。2026-09-11 02:09 到修复之间，每一次「编译通过」编的都是旧工程（`progress.md` §1）。刚改的东西没效果时，先查有没有这个嵌套目录，再去调别的。

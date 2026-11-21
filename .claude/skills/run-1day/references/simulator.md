# 模拟器（Path A，已端到端验证）

只在 iPhone 连不上时用（见 SKILL.md 开头的规则），用了要告诉用户。

## 1. 选设备并启动

```bash
xcrun simctl list devices available | grep -A20 "iOS 2"
xcrun simctl boot <SIM_UDID>
open -a Simulator
```

这台机器上：`iPhone 17 Pro Max` = `7F09FED5-12E4-4875-B27C-2629AF67CE97`，`iPhone SE (2nd generation)` = `2612ECE6-9957-4CBF-933F-2002C5D493D4`。重装运行时后 UDID 会变，用前重新列一遍，不要直接信这两个。

## 2. 编译

```bash
cd ios
xcodebuild -project AISetlog.xcodeproj -scheme AISetlog -configuration Debug \
  -destination 'id=<SIM_UDID>' -derivedDataPath /tmp/1day-dd build 2>&1 \
  | grep -E "error:|BUILD"
```

`-derivedDataPath` 不放默认位置：Xcode 里索引卡住时不会影响命令行编译，而且 `rm -rf /tmp/1day-dd` 是安全的彻底重置。

## 3. 安装：第一次会卡住

```bash
xcrun simctl install <SIM_UDID> /tmp/1day-dd/Build/Products/Debug-iphonesimulator/AISetlog.app
```

症状：没有输出、没有报错，进程 CPU 约 0%，一直不结束。`bootstatus` 会说「Device already booted, nothing to do」：它说的开机状态是对的，但设备其实还没准备好。

解决办法，重试每次都成功：

```bash
pkill -f "simctl install"
xcrun simctl shutdown all
killall Simulator
killall -9 com.apple.CoreSimulator.CoreSimulatorService
sleep 4
xcrun simctl boot <SIM_UDID> && open -a Simulator && sleep 5
# 再装一次
```

## 4. 启动并截图

```bash
xcrun simctl launch --terminate-running-process <SIM_UDID> com.cassie.AISetlog
sleep 5
xcrun simctl io <SIM_UDID> screenshot /tmp/1day-shot.png
```

然后**读这张 PNG**。启动返回了 PID 只说明程序起来了，不说明画面渲染出来了。黑屏或空白都算失败。

首屏应该是：「把今天，留成一支片」、一段循环播放的示例视频（`RoomDemoPlaybackSurface`）和「开始我的第一支片」。

先给相机和麦克风权限，免得权限弹窗挡住屏幕：
`xcrun simctl privacy booted grant camera com.cassie.AISetlog.dev`。

## 5. 点击

首选 iOS Simulator MCP（`mcp__Claude_Code_iOS_Simulator__control`），按设备点坐标点击（17 Pro Max 是 440×956）。点击加 `duration: 0.15`，时长为 0 的点击有时会丢。

没有 `simctl tap`。其他两个办法都不太好用：

**AppleScript**：要把终端加到「系统设置 → 隐私与安全性 → 辅助功能」，否则每次点击都返回 `-25204`。

```bash
# 设备屏幕是 Simulator 窗口的第 5 个 UI 元素
osascript -e 'tell application "Simulator" to activate' \
          -e 'tell application "System Events" to tell process "Simulator" \
              to tell window 1 to get {position, size} of UI element 5'
```

把 1320×2868 的 `simctl` 截图上的点换算到屏幕：`x = gx + px * gw / 1320`，`y = gy + py * gh / 2868`，再 `tell application "System Events" to click at {x, y}`。

要**先**激活 Simulator：窗口不在最前面时查它会返回 `-1719`（invalid index）。

**`idb`**（`brew install facebook/fb/idb-companion`）好用一些，但这台机器没装。要点很多次时再装。

## 6. 相机

iOS 26 模拟器上相机显示「相机不可用」（没有采集设备）。要截相机页面，用 Debug 版才有的假相机启动：

```bash
xcrun simctl launch --terminate-running-process <SIM_UDID> com.cassie.AISetlog \
  -onboarding.completed.v1 YES -appLanguage chinese -simulatedCamera YES
```

取景框是一个标着 SIMULATOR 的动画画面，按住快门会生成一段 `DemoClipFactory` 片段，所以拍摄到回看能完整走通。这个开关故意默认关闭：UI 测试要用「相机不可用」页面上的「示例片段」按钮。

跳页面、看日志等工具和真机通用，见 SKILL.md 的 `scripts/agent/` 一节。

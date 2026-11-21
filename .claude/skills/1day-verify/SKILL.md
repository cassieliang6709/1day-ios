---
name: 1day-verify
description: 在 Cassie 的 iPhone 上逐项验证 1Day App 的功能真的能用，并到线上 D1 数据库查证据，最后给出「哪项过了、证据是什么、哪项没验」的报告。用户说「验证一下」「测一下能不能用」「上线前走一遍」「这个功能好了吗」，或改完代码要证明它在真机上工作时使用。不用于：只编译（直接用 xcodebuild）；只装上看一眼（用 run-1day）；界面统不统一（用 1day-design-system）；删除账号、给朋友发消息这类会留下真实痕迹的操作（先问用户）。
---

# 1day-verify

证明 1Day 在真机上能用。证据分两种，每项功能至少要有一种：**屏幕证据**（iPhone 截图或 `phone_elements` 读到的状态）和**服务器证据**（D1 里出现了对应的行）。

功能地图在 [references/features/README.md](references/features/README.md)。先在 README 里按关键词找到功能文件，每个文件写了子功能、用户怎么找到、怎么操作、验证表（编号、入口、什么算成功、服务器证据）和容易出错的地方。不点屏幕就能跳页面、看日志、打断点、录性能的工具在 [driving.md](references/features/driving.md)。

## 第 1 步：定范围

1. 看这次改了什么：`git status --short` 和 `git diff --stat`。
2. 从功能清单里挑出受影响的编号。
3. 用户说「全走一遍」或要打 TestFlight 时，选全部编号。
4. 把要验证的编号列给用户，不用等回复，直接开始。

## 第 2 步：装到手机上

1. 按 run-1day 的 Path B 编译、安装、启动 Debug 版。
2. 调 `phone_status`。`drivable` 不是 true 时，调一次 `phone_reconnect`（`wait_secs: 180`）。
3. 还是连不上时停下，告诉用户手机上要做什么（通常是解锁）。不改用模拟器冒充真机。

## 第 3 步：准备测试房间

清单里「对外写」标着「是」的功能，只在测试房间里做：

1. 先找有没有名字以「测试」开头、只有本人在的房间。
2. 没有就按 F5 建一个，名字是「测试」加当前时间。
3. 拍一拍（F14）、改头像名字（F18）、收推送（F15）会影响朋友或要别人配合：先问用户。

## 第 4 步：逐项验证

对每个编号：

1. 按「怎么走」操作。点按钮优先用 `phone_tap_label`；同名的元素先 `phone_elements` 查到再点。
2. 用 `phone_screenshot` 截图，确认「屏幕上算成功」那一条。黑屏、白屏、一直转圈都算失败。
3. 有服务器证据的，跑脚本查：

   ```bash
   python3 .claude/skills/1day-verify/scripts/d1_read.py recent 5
   python3 .claude/skills/1day-verify/scripts/d1_read.py room <邀请码>
   ```

   脚本只能读，不能写。退出码 1 是 wrangler 出错，看它打印的最后几行。
4. 记下结果：通过 / 失败 / 没验（写原因）。
5. 失败时，用 `phone_logs`（`process: "AISetlog"`）抓日志，`phone_crashes` 看有没有崩溃。App 自己的日志在 subsystem `com.cassie.AISetlog`（api / sync / app / debug），每个请求有一行状态码和耗时。后端那边用 `scripts/agent/worker-tail.sh --seconds 60` 边操作边看。只记录，不在本 Skill 里改代码。

「要真人」标着「是」的步骤（Face ID、密码、第二个账号）：停在那一步，告诉用户要做什么，用户做完再继续。不替用户输入密码。

## 第 5 步：收尾

1. 测试房间里本次发的消息和片段，留着还是退房删掉，问用户一次。
2. 调 `phone_release_owner` 把手机交还。

## 报告格式

一张表，每行一个编号：

| 编号 | 结果 | 证据 |
| --- | --- | --- |
| F6 | 通过，加入用了 2 秒 | 截图 + `members` 多 1 行 |

表后写：没验的项和原因；失败的项附日志里的关键一行。

## 维护功能清单

App 加了功能、改了入口或 identifier 时，同一次改动里更新 `references/features/` 里对应的功能文件。验证时发现 identifier 找不到，先查代码里它是不是改名了，改的是地图就修地图，改的是代码就报告给用户。

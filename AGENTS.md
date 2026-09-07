# 1day — 给 agent 的工作规矩

写给在这个仓库里干活的 AI agent。每条都是从踩过的坑里来的，附了为什么。

## 分层铁律（CI 会卡）

- `ios/AISetlog/Models/` 里不许出现 `Strings.`。CI 用 `grep -rn` 直接卡这条，展示文案属于 `ChallengePresenter` 或视图层。
- `ios/AISetlog/Presentation/` 必须纯：不 `import SwiftUI`，不读 `.now`。时间当参数传进来——**不是为了好看，是为了能测**。读了 `.now` 的函数没法钉住行为。
- 文案走 `Strings` enum 的计算属性（不是 `.strings` 文件），中英双语都要写。
- 加、删、改名任何源文件之后必须 `xcodegen generate`。`.xcodeproj` 在 `.gitignore` 里，不重新生成新文件根本不进编译。

## CI

工作流在 `.github/workflows/ios-tests.yml`，`macos-15` runner，Xcode 钉在 26.2。

**读失败先看它挂在哪一步，别先怀疑代码。** 这个仓库的 CI 挂过五种，没有一种是测试真的发现了 bug：

| 症状 | 真因 |
|---|---|
| `Assets.xcassets: error:` | 镜像漂移：Xcode 版本和镜像上的模拟器 runtime 对不上，`actool` 把它报成资源错误 |
| `Unable to find a device matching the destination specifier` | 写死设备型号名，靠 xcodebuild 现场造，只在某些 job 上成功 |
| 每次固定几十秒必挂 | 某个自检自己成了故障点 |
| 老 PR 上的红叉 | `gh run rerun` **重放的是旧的 workflow 定义**，修复不生效 |
| `background assertion timed out` | 模拟器启动握手抖动 |

具体规矩：

- **模拟器：问 `simctl` 要一台现成的，别造。** 现在的做法是按 SDK 版本从 available 设备里挑，实在没有才 `simctl create`。runner 镜像自带 iPhone 16 到 17 Pro Max。
- **绝不用 `xcodebuild -showdestinations` 当门禁。** 它漏列的模拟器，把 udid 直接递给 `-destination` 照样跑得动（本地开发机上它一台具体模拟器都不列，测试却全过）。曾经拿它做自检，结果每次构建卡死在 55 秒——**挡掉的全是本来会通过的构建**。
- **一个会让构建失败的诊断，必须比它检查的东西更可靠**，否则它只是多了一个故障点。
- **修了 workflow 之后不能靠 `gh run rerun` 验证**，得把 main 合进分支重新触发，否则跑的还是旧定义。
- 四个 CloudKit 套件在 CI 里 `-skip-testing:`。原因不是它们会失败，是 `CODE_SIGNING_ALLOWED=NO` 下没有 iCloud 权限，`accountStatus()` 会**直接打死 test host**，连 skip 都来不及。

## 怎么判断一个红叉是不是真的

**先看失败的形状，再决定要不要重跑。**「重跑试试」不是诊断。

- 三个 UI 测试全挂在启动握手、单元测试一个没挂 → 基础设施，不可能是业务改动引起的
- 某个测试崩了 test host，导致字母序在它之后的套件全部没跑 → 多半是模拟器争抢
- 只有一两个断言失败、位置和你改的东西对得上 → 这才值得当真

**测试失败先怀疑环境，重跑一次再下结论**——但要说清你为什么认为是环境。

## 并行 agent

- **每个 agent 一台专属模拟器 + 一个专属 `-derivedDataPath`。** 抢同一台会产生假失败——曾经 6 个 agent 抢一台，跑出 3 个假红，差点被写进报告。
- **限制同时编译的数量。** 6 个并行跑到过负载 500、磁盘 97%。
- **靠指令维持的约定不是锁。** 发过一个「请走闸门脚本」的约定，有 agent 直接绕过去了。真要限并发，得是锁本身拒绝，不是靠对方自觉。
- 活干完把临时模拟器删掉。`CoreSimulator/Devices` 很容易堆到几十 G。

## 提交

- **只 `git add <具体文件>`，绝不 `git add -A`。** 这个 workspace 里有 gitignore 的密钥文件（`workers/suggest-prompts/.dev.vars`）。
- 提交前必查 `git diff --cached | grep -cE "sk-[a-zA-Z0-9]{20,}"`，必须是 0。
- 仓库是 **public**，推分支等于发布。
- build 号（`ios/project.yml` 的 `CURRENT_PROJECT_VERSION`）用过就不能再用，App Store Connect 会拒。合并带 build 号的分支时留意会不会退回一个已经导出过的值。

## 汇报

- **先跑命令，再下结论。** 曾经断言某个组件没人用，实际上 main 上还在被引用——不是信息不足，是没把手上已有的事实和正在写的判断对上。
- 没验的事要说没验。模拟器上验不了的东西（成片叠加层被 `#if !targetEnvironment(simulator)` 编译掉了）不能说验过。
- 报告里的每个数字都要有对应的命令。

# 1day — 实施进度与执行流水 (Execution Progress)

> **最新更新时间**：2026-09-11 16:55:00 CST  
> **职责定位**：本文件记录项目的**最新事实真相、构建与真机状态、已解决/仍阻断问题、各模块执行进展与下一步行动**。

---

## 1. 恢复与交接检查点 (Ground Truth Checkpoint)

| 核心维度 | 当前状态真相 (Ground Truth) |
|:---|:---|
| **代码基线** | 分支 `feat/room-chat`，最新 commit `700865786c1387bf8778ce2f7632fc74ee7720e7`，含未提交的本地改进。 |
| **手机当前安装包** | **1.2 (build 21)**。Release 真机构建通过，已由 `devicectl` 安装到 `6BAD8B60`；含 P3 无裁切合拍、P1 三参数调色、P2 双人各自字幕、C3 journal 化注销。 |
| **构建命令修正** | 之前的 `xcodegen --project ios/AISetlog.xcodeproj` 把参数当成**输出目录**，生成了嵌套的 `AISetlog.xcodeproj/AISetlog.xcodeproj/`，真正的工程从未被更新——2026-09-11 之前所有「构建通过」编的都是 09-11 02:09 的旧工程。正确写法是 `xcodegen generate --spec ios/project.yml --project ios`。 |
| **黑屏阻断状态** | **已彻底解除真机全黑阻断**。build 19/20 证实原片及合拍正常循环出画，数字进度平滑递增。 |
| **文档架构状态** | **三权分立管理体系已就绪**：`tech_plan.md`（技术方案）、`product_requirements.md`（深度结构化 PRD v3.0）、`progress.md`（当前执行流水）。桌面均已建快捷方式。 |
| **核心产品决策状态** | **全部确认关闭**：P1 采用 Apple 官方 `CIFilter` 三参数（曝光/色温/对比度，`-50~+50` 物理回中）；P3 采用方案 A（Aspect-Fit 全视场等比 + 素材高斯模糊铺底）。 |
| **夜间 Agent 运行结论** | 2026-09-10 夜间执行了 22 轮有效迭代，在 02:11 因触发平台额度上限安全停止；无失控操作，无自动提交，产出已全部盘点留存。 |
| **当前发布阻断项** | **无代码级阻断**。C3 已接通：`AccountDeletionService` 把设置页的注销按钮接到 journal 化协调器上，云端删除逐条确认、本地数据留到最后才擦、失败明确报错并可续删（7 项测试）。剩下的是真机双端验收，不是待写的代码。 |
| **并发事故记录** | 2026-09-11 15:51–16:02 另有一个 `claude --dangerously-skip-permissions` session（PID 23474）在同一工作树写 P1，一度留下编不过的半成品（`GentleLookFilter` 引用了尚未建立的 `PersonalEffectParameters`）。其 `PersonalEffectParameters` 草稿被采纳并补全，其余由本 session 接管。**同一 checkout 不要开两个 agent。** |

---

## 2. 核心需求完成度全景 (Requirement Progress Matrix)

依据 `product_requirements.md` (v3.0 PRD) 的六大用户旅程阶段对齐：

| 模块 / ID | 需求名称 | 当前技术与代码就绪状态 | 验证情况 |
|:---|:---|:---|:---:|
| **D1 / D4** | 单机免登录房间演示 | 首页入口已切换为 `LocalRoomDemoView`，正式 `StoryTimelineView` 已通过 `LocalRoomRuntime` 注入隔离运行时。 | 模拟器 Debug 构建通过；正式 UI 端到端待运行验证 |
| **A1** | 意图置顶 AI 故事生成 | 客户端与 Worker 可选 `title` 协议已向后兼容实现，20s 超时兜底就绪。 | 单元与 Mock 测试通过 |
| **U1** | 两步向导创建流 | 创建步骤文案（1/2 选拍法，2/2 设置故事）及空标题高亮指引已编码。 | 模拟器交互通过 |
| **V1** | 6位邀请码防呆加入 | `InviteCode` 正则与规范化已修复，杜绝截取畸变邀请码的前 6 位误加入。 | 边界测试通过，待真机双端 |
| **V2** | 七日连续挑战跨日推进 | 模式切换 hit-testing 遮挡已修复；跨时区/夏令时日历计算单测已通过。 | 14 项日历单测通过 |
| **P5** | 倒计时快门中轴对齐 | 倒计时容器改用绝对几何中轴对齐，18 组不同语言/字号渲染断言通过。 | 像素渲染断言通过 |
| **P4** | 重力旋转与真实角度 | 录制端 `RotationCoordinator` 联动已就绪，元数据注入 `preferredTransform`。 | 待结合真机拍摄复验 |
| **P6** | 纯净中英双语体验 | 系统字典收敛中，消除硬编码机翻混排，保护用户自建文本原貌。 | 持续集成中 |
| **P1** | 官方 CIFilter 三参数微调 | **已落地**。`GentleLook`（smoothing/brightness/warmth，0…1，四个写死预设）整体删除，换成 `PersonalEffectParameters`（曝光/色温/对比，-50…+50，0=原样）；`PersonalEffectFilter` 走 `CIExposureAdjust`/`CITemperatureAndTint`/`CIColorControls`；`LookPanel` 删预设改三滚轮＋中位刻度＋复位；设置页改为复位入口。旧 `gentleLook.v1` 键**不迁移**（smoothing 无对应维度，硬映射等于擅自改变别人的画面），老用户开在「原样」。 | 28 项测试通过（含色温符号方向、extent 不漂移、原片不被改写） |
| **P1b** | 调色只作用于自己的素材 | **已落地**。`VideoStitcher.Options.lookAuthorID`：合拍时只对自己 authorID 的片段跑调色。此前你的滤镜会被烤进朋友的画面里。 | 2 项端到端像素测试通过 |
| **P2** | 独立作者字幕防抢占 | 模型层 `DayClip.overlayText` 隔离已就绪，预览清空回退机制已通过。 | 基础修复通过 |
| **C1 / C5** | 房间级统一聊天与 Outbox | 全房间单会话流、2000 字符限制、本地 Outbox 持久化与租约隔离已实现。 | 离线排队与去重测试通过 |
| **C2** | 仅作者撤回与持久防复活 | 仅本人长按删除、本地 Tombstones (`deletedIDs`) 物理防复活机制已就绪。 | 本地状态机测试通过 |
| **D3** | 演示素材相册视频替换 | 截取前 3 秒转码（`AVAssetExportSession` 960x540）替换指定成员功能已实现。 | 单元与取消交互通过 |
| **build20** | 互补反转画幅默认规则 | 竖拍合横版 16:9，横拍合竖版 9:16，方形合 1:1，显式选择优先已就绪。 | 21 项画幅回归通过 |
| **P3** | Aspect-Fit 无裁切毛玻璃合拍 | **已落地**。`AVMutableVideoCompositionLayerInstruction` 只能 transform/crop/opacity，做不了模糊，所以换成自定义 `AVVideoCompositing`：新增 `FriendsTogetherCompositor`，每人两层——aspect-fill＋`CIGaussianBlur` 铺底、aspect-fit 完整前景居中。`cellTransform` 的裁剪逻辑已删除。`preferredTransform` 收敛成 `CGImagePropertyOrientation` 交给 `CIImage.oriented()`，避开 top-left/bottom-left 坐标系镜像。 | 5 项测试通过，**并做过反证**：把前景改回 fill（等价旧裁剪）测试立刻 FAILED |
| **P2** | 独立作者字幕防抢占 | **已落地**。此前整帧底部只有一个 caption pill，合拍时先打字的人占住、第二个人的字没地方显示。新增 `AuthorCaptionWindow` + `addAuthorCaption`，按 cell 几何单独排版，每人的字在自己画面下方。 | 真机 Release 构建通过；出画效果待真机肉眼验收 |
| **D2** | 硬件级平滑循环播放 | `RoomDemoPlaybackSurface` 像素直出，彻底杜绝系统图层黑屏，数字滚动正常。 | **真机实测出画验收通过** |
| **C3** | 账号注销五阶段状态机 | Freeze $\rightarrow$ Drain $\rightarrow$ Cloud Purge $\rightarrow$ Local Wipe 协调器就绪。 | Mock 弱网重试通过 |
| **C4** | 旧版评论无损平滑迁移 | `LegacyCommentMigrationPlanner` 原子迁移与幂等防复活已就绪。 | 迁移断言通过 |

---

## 3. 构建与交付历史流水 (Build History)

* **build 13 (2026-09-10 12:52)**：
  * 内容：修复七日封面图越界遮挡模式切换按钮；首页增加房间演示入口。
  * 结论：**失败（真机全黑屏）**。证明单纯测试文件尺寸与时长无法保证屏幕可见渲染。
* **build 14 ~ build 17 (诊断排查阶段)**：
  * 内容：提取手机沙盒文件证实生成的 MOV/MP4 抽帧完全正常、彩色、有内容；去掉 SwiftUI `clipShape`；加入原生诊断浮层。
  * 结论：证实系统原生 `AVPlayerLayer` 在特定场景存在图层冻结呈现黑色。
* **build 18 ~ build 19 (2026-09-10 17:16)**：
  * 内容：改用 `RoomDemoPlaybackSurface`（`AVPlayerItemVideoOutput` 像素直显），彻底绕开硬件层冻结；示例画面中央增加递增动态数字（如 `26% -> 97% -> 75%`）。
  * 结论：**重大突破，真机视频黑屏彻底解决**，循环播放稳定顺畅。
* **build 20 (2026-09-10 20:09)**：
  * 内容：落地用户最新确立的默认画幅规则（竖拍默认合横版，横拍默认合竖版，方形保持 1:1，手动优先）。
  * 结论：`DefaultFilmAspectTests` 7 项新增测试及既有合成测试全部通过；包已安装到真机。
* **夜间运行产出 (2026-09-10 23:29 ~ 02:11)**：
  * 完成 22 轮深度迭代，完成了 `LocalRoomDemoStorage` 沙盒隔离、注销事务协调器、AI 可选标题向后兼容契约、录制倒计时几何居中等核心底层，留存大量模拟器与单元回归测试日志。

---

## 4. 本轮落地记录 (2026-09-11 下午)

### 修掉的一个隐性错误：构建的一直是旧工程

`xcodegen generate --project ios/AISetlog.xcodeproj` 里的 `--project` 是**输出目录**，不是输出文件。所以那条命令生成的是 `ios/AISetlog.xcodeproj/AISetlog.xcodeproj/`，而 `xcodebuild` 打开的外层工程从 09-11 02:09 起就没变过。新增文件不会进 target，"BUILD SUCCEEDED" 只证明旧快照能编译。正确命令写在第 1 节。

### P3：换成自定义 compositor，而不是改几何

`AVMutableVideoCompositionLayerInstruction` 的能力只有 transform / crop / opacity —— 没有模糊。所以方案 A 不是改 `cellTransform` 算法能做到的，必须接管合成：

```text
FriendsTogetherCompositor : AVVideoCompositing
每个成员一个 cell：
├── 铺底：aspect-fill → clampedToExtent → CIGaussianBlur(cell 短边 × 5%) → 压暗 0.08 → 裁到 cell
└── 前景：aspect-fit 完整画面居中
```

两个坑，都已处理：

1. **坐标系**。`preferredTransform` 是 top-left 空间的显示变换，直接喂给 bottom-left 的 `CIImage` 会把每个旋转镜像掉。这里把它收敛成四种 `CGImagePropertyOrientation` 之一交给 `CIImage.oriented()`，由系统连 extent 一起修正。
2. **自定义 compositor 是全局的**。它会接管整个 composition，包括片头那条无源黑场 instruction。`startRequest` 对不认识的 instruction 返回纯黑帧，而不是崩掉。

`customVideoCompositorClass` 只在 `.friendsTogether` 时设置，顺序播放的成片仍走系统路径。

### P1：删掉旧模型，不做有损桥接

上一轮在 `GentleLook` 上加过一个 `fromProductDials` 桥，用 `max(0, ...)` 把负值吃掉——等于三个滚轮只有正半轴有效，-50 和 0 渲染完全一样。这次把 `GentleLook` 整个删除，`PersonalEffectParameters` 成为唯一模型。

一个要记住的符号方向：`CITemperatureAndTint` 是**朝目标白点校正**，所以画面要更暖，`targetTemperature` 必须更低。写反了在算术上看不出来，在脸上一眼就是蓝的——`testWarmthGoesWarmNotBlue` 专门盯这个。

存储键从 `gentleLook.v1` 换到 `personalEffect.v2`，**不迁移**：旧值是 0…1 的 smoothing/brightness/warmth，smoothing 在新模型里根本没有对应维度，硬映射等于不打招呼就改变了别人片子的样子。老用户开在「原样」。

### C3：入口早就在，问题是它在说谎

`progress.md` 之前写的是「待接正式入口」，但设置页的注销按钮一直是接好的——接的是 `ChallengeStore.deleteAccountAndAllData()`，那条路径把云端删除包在 `try?` 里，然后**无论成败都擦本地、登出、报成功**。断网注销的结果是：CloudKit 上的记录还在，手机上什么都没了，界面说删干净了。

改成 `AccountDeletionService`：接 journal 化的 `AccountDeletionCoordinator`，云端逐条确认删除（`deleteRecordsConfirmingEachOne`，把 `.unknownItem` 当成功以便续删），**本地数据留到最后一步**才擦。这个顺序是全部意义所在——失败时 journal 还在、片子还在、可以接着删。失败弹窗明说「你的东西都还在」。

创建的房间不进删除清单：房间里有朋友的片子，「删除我的账号」不该毁掉别人的故事，只把 owner 名字抹掉。

### P6：内置文案是干净的，泄漏不在这里

`ChineseCopyPurityTests` 把 94 条内置 moment、全部内置模板名/简介、以及所有模板引用的 key 整个扫了一遍——没有一条会在中文机上显示英文，也没有悬空的 key（悬空 key 会退化成显示原始英文键名，这是另一条泄漏路径）。AI 生成那条链路的 language 参数也是对的，Worker 明确要求简体中文。

**所以你截图里看到的英文，不是内置预设。** 剩下三种可能：模型没听话的 AI 输出、你自己建的模板文本（这个按设计不翻译，是对的）、或者某个我没认出来的界面。要定位得有那张图。测试已留下，以后任何新增的未翻译内置文案会直接挂测试。

---

## 5. 下一步 (Next Actions)

代码侧本轮清单已做完，剩下的都是**只能在真机上做的验收**：

1. **P3 合拍出画**：开多人房间演示，确认两个人都完整出画、没有切头、边缘是自己画面的模糊铺底而不是黑边。
2. **P1 三滚轮手感**：`-50…+50`、中位有刻度、按住看原片、复位。确认 ±1.5 EV 和 ±2000K 的范围在真实光线下够用又不过火。
3. **P2 双人字幕**：两个人在同一个 moment 各写一句，确认各自显示在自己画面下方、长句被截断而不是溢出 cell。
4. **C3 双机注销**：A 机注销，B 机确认 A 的片子和留言消失、房间本身还在、owner 名字已抹掉。再试一次飞行模式注销，确认报错、本地数据完好、联网后能续删。
5. **P6**：下次再看到中文里混英文，**把那张截图留下来**——内置文案已排除，需要图才能定位。


---

## 5.5 UX 审计落地 (2026-09-11 晚)

`docs/ux-audit-2026-09-09.md` 的三个 🔴 已经做掉，都是「用户东西没了 / 功能
打不开」级别，不是打磨：

| # | 问题 | 做法 |
|:--|:--|:--|
| 5.1 | 回看页点 X，拍好的片段无声消失 | modal 录制路径接上自由拍那套守卫：保留（进草稿）/ 丢弃 / 取消，文案完全复用。没东西可丢时不弹 |
| 5.2 | 相机权限拒了以后是死循环 | `denied` 和 `unavailable` 分开：前者给「打开系统设置」。判断用计算属性每次读，不存状态——从设置授权回来不会自动重跑 `configure()` |
| X.1 | 删除故事 / 退出房间没有二次确认 | 两处入口都加确认，**删除和退出文案分开**：删除是永久删片段，退出只是本地清房间、你的片段留给其他人（对着 `ChallengeStore.delete` 核对过） |

顺带两处一行文案（audit 2.1 / 4.4）：写死的「七个瞬间」改成带数量，
「加入今日房间」改成「加入房间」。

`DestructiveActionGuardTests` 钉住删除 / 退出两套文案不能相同、退出的文案
不许出现「找不回来」。

**审计里剩下的 🟡 / 🔵 没做**，清单还在 `docs/ux-audit-2026-09-09.md` 的优先级
汇总表里，下一批按它的建议顺序走：4.1（join 入口可发现性）+ 4.2（取消登录
丢邀请码）是裂变链路，优先级最高。

---

## 6. 测试方案 (Test Plan)

### 先说清楚模拟器上那几个"随机失败"是什么

不是随机，也不是断言写错，是**测试宿主进程被杀掉**。

原因 `.github/workflows/ios-tests.yml` 里早就写清楚了：`CloudKitIdempotencyTests`、
`CloudKitPaginationTests`、`RoomSyncIntegrationTests`、`JoinedRoomTests` 这四个套件
要连真实 CloudKit 开发库。它们都写了「没登录 iCloud 就 XCTSkip」的保护——但
`CODE_SIGNING_ALLOWED=NO` 的构建**没有 iCloud entitlement**，而在没有 entitlement 的
container 上调 `accountStatus()` 会直接杀掉测试宿主，不是返回错误。进程都没了，
自然也就没人来执行那个 skip。

日志里的特征是 `[CK] Significant issue at CKContainer.m:748: ... must have a
com.apple.developer.icloud-services entitlement`，紧接着 `Restarting after unexpected
exit`。`xcodebuild` 会重启进程继续跑，但**崩溃那一刻正在排队的 case 会被记成
failed**，重跑时通过。所以 `Failing tests:` 列的是「谁运气不好轮到了」。

CI 的做法是直接跳过这四个套件。本地也应该这么跑。这四个要验，得在一台
**登录了 iCloud 的模拟器**上单独跑。

**判断标准**：看有没有 `Test Suite '<名字>' failed at`，以及
`Executed N tests, with M failures` 里的 M。只看末尾的 `** TEST FAILED **` 会被
崩溃重启误导。

已验证：加上这四个 `-skip-testing` 之后，**450 个 case 全过，0 失败，0 次进程
重启**。抖动完全来自 entitlement，不是媒体测试压力。

### 怎么跑

**全量（本地，跟 CI 一致）**——跳过四个需要 iCloud entitlement 的套件：

```bash
xcodebuild -project ios/AISetlog.xcodeproj -scheme AISetlog \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  test -only-testing:AISetlogTests \
  -skip-testing:AISetlogTests/CloudKitIdempotencyTests \
  -skip-testing:AISetlogTests/CloudKitPaginationTests \
  -skip-testing:AISetlogTests/RoomSyncIntegrationTests \
  -skip-testing:AISetlogTests/JoinedRoomTests \
  CODE_SIGNING_ALLOWED=NO
```

**改了某一块时只跑那一块**，比如媒体管线：

```bash
  -only-testing:AISetlogTests/FriendsTogetherCompositorTests \
  -only-testing:AISetlogTests/PersonalEffectFilterTests \
  -only-testing:AISetlogTests/PersonalEffectScopeTests \
  -only-testing:AISetlogTests/SharedRoomFilmTests \
  -only-testing:AISetlogTests/DefaultFilmAspectTests
```

**那四个 CloudKit 套件**：需要一台登录了 iCloud 的模拟器，并且不能用
`CODE_SIGNING_ALLOWED=NO`。CI 永远跳过它们，所以这部分只能人工跑。

### 真机验收清单

模拟器跑不了的部分——字幕和片头用 `AVVideoCompositionCoreAnimationTool`，在模拟器软件渲染路径下会崩，所以代码里是 `#if !targetEnvironment(simulator)` 包着的。**这几项只能上手机看**：

| # | 验什么 | 怎么算过 |
|:--|:--|:--|
| 1 | P3 合拍无裁切 | 两人竖拍合成横版：两个人都完整出画，没切到头；左右留白是各自画面的模糊铺底，不是黑边 |
| 2 | P3 不串台 | 两个 cell 之间的缝是黑的，谁的画面都没溢出到对方格子里 |
| 3 | P1 三滚轮 | 曝光/色温/对比，-50…+50，中位有刻度；按住看原片；"复位"一次归零三个 |
| 4 | P1 色温方向 | 往右拧画面变**暖**（不是变蓝）——这是最容易写反的一个 |
| 5 | P1b 只动自己 | 合拍成片里朋友的画面跟他拍的时候一样，没被你的滤镜染色 |
| 6 | P2 双人字幕 | 两人在同一 moment 各写一句，各自显示在自己画面下方；长句截断不溢出 cell |
| 7 | C3 正常注销 | A 机注销后，B 机看不到 A 的片子和留言；房间还在；owner 名字已抹掉 |
| 8 | C3 断网注销 | 飞行模式注销 → 明确报错「你的东西都还在」→ 本地故事完好、仍登录 → 联网重试能续删完成 |

第 8 项是这轮改动的重点。旧代码在这个场景下会擦光本地、登出、报成功。

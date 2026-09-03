# PRD — 首页 header 重排 & 新建故事题目可见性

- 日期：2026-09-01
- 提出人：Cassie
- 状态：**已实施**（PR-0 ~ PR-3 全部落地，验收见 §5；真机 iPhone SE 回归见 §8）
- 设计稿：[docs/mockups/home-composer-v2.html](../mockups/home-composer-v2.html)
- 采用方案：header **方案 A**；新建故事 **方案 A 打底 + 借方案 C 的网格副标题**

---

## 1. 背景

两块问题来自 2026-09-01 的真机截图 review：

**首页 header** 左侧是 1day logo + 一句问候，右侧是 44pt 渐变 `+`（带 `oneDayGlow`）、加入房间、头像。
- logo 在自己 app 的首页里是零信息，它已经出现在 App 图标、启动页、录制水印上；
- `+` 比旁边两颗控件大 25% 还发光，是全屏最亮的元素，抢走了本该属于「继续今天的故事」主按钮的视觉主导权；
- 左侧没有日期。这直接导致 review 里那个「9.1 的内容在首页找不到」——首页从头到尾没有任何时间坐标。

**新建故事页**（`MoodStep`）有两套互相打架的选择器：
- 顶部「按时间记录 / 主题挑战」双卡是一套；
- 底部「推荐题目」网格是另一套。选中「按时间记录」时网格仍可点，点一张会静默改写 `selectedTemplateID` 并把用户踢出时间模式；而顶部「主题挑战」的选中态是从 `selectedTemplate?.isTimeOnly != true` 反推的，于是界面自己跳。
- 最关键：`PromptTemplateTile` 只渲染模板名 + blurb，**7 个题目在这一屏完全不出现**，要到第二步的折叠卡才看得到。用户在「选之前」无法知道会被要求拍什么。

## 2. 目标

1. header 左侧承载「你是谁 + 今天是哪天 + 今天拍了几个」，右侧只放动作；`+` 与其他控件等重。
2. 新建故事页只保留**一套**选择器，状态机自洽、不静默跳变。
3. 用户在提交前能看见**具体题目**，而不只是模板名和一句情绪文案。

## 3. 非目标（本次不做，另开）

- 首页「今天的故事」的 hero 选择逻辑（`RootShellView.swift:31` 按 `recordedCount` 最小挑选，会让旧空故事霸占今日位）——见 §7 待办。
- 「拍摄」tab 自由拍摄不落盘的问题（`RootShellView.swift:77` `onSave` 为空闭包）。
- 首页按日期分组 / 日历视图。
- 引导式写题目（`GuidedMomentsView`）的时态问题。

---

## 4. 范围内需求

### 4.1 首页 header（方案 A）

改 `PlansHomeView.header`（[ios/AISetlog/Views/Plans/PlansHomeView.swift:143](../../ios/AISetlog/Views/Plans/PlansHomeView.swift)）。

自左至右：

| 位置 | 元素 | 规格 |
|---|---|---|
| 左 | `AvatarDot` | 42pt，点击进设置（原头像的行为） |
| 左 | 主行 | `Strings.greeting(...)`，16.5pt heavy rounded，`OneDay.ink` |
| 左 | 副行 | `9月1日 星期一 · 今天 1/7` + 7 颗 `MomentPips`，11.5pt bold，`OneDay.inkSoft` |
| 右 | `IconBubble("person.2.badge.plus")` | 36pt（当前默认 38 → 传 `size: 36`） |
| 右 | `+` 新建故事 | **36pt** 圆形，`OneDay.brandHorizontal` 填充，**移除 `oneDayGlow`**，保留 44pt `contentShape` 热区 |

其他：
- **移除 `OneDayBrandLogo`**（header 里的那处）。
- 副行的进度部分仅在存在 hero 故事时显示；无故事时副行只有日期。
- `+` 与加入房间的先后顺序：加入房间在左、`+` 在右（`+` 最靠边，拇指最好够）。

新增可测类型 `HomeHeaderSummary`（放 `Presentation/`）：

```swift
struct HomeHeaderSummary {
    let dateLine: String      // "9月1日 星期一"
    let recorded: Int?        // nil = 今天没有进行中的故事
    let total: Int?
}
```

日期用 `AppLanguage.effective.locale` 格式化，与 `StorySchedule` 现有做法一致。

### 4.2 新建故事：状态机修正（方案 A 的交互部分）

改 `MoodStep`（[ios/AISetlog/Views/Compose/ComposerSteps.swift:11](../../ios/AISetlog/Views/Compose/ComposerSteps.swift)）。

1. **左右交换**：`主题挑战` 在左，`按时间记录` 在右。
2. **默认选中主题挑战**，并默认选中推荐列表第一个模板（`完美的一天`）。
3. **时间模式下禁用推荐网格**：选中「按时间记录」时，`推荐题目` 整个 section（含 SectionLabel、「更多模板」、网格）`.disabled(true)` 且 `.opacity(0.4)`，并加一句说明「按时间记录不需要题目」。
4. **修 `selectPromptMode()` 的提前返回**（`ComposerSteps.swift:162`）：

   ```swift
   if selectedTemplate?.isTimeOnly != true, selectedTemplate != nil { return }
   ```

   当前在七日模式下已选模板时点「主题挑战」完全无反馈。改为：若当前选中的已是带题目的模板则保持不变（这是对的），但仍要触发一次选中态刷新；若无选中或选中的是 time-only，则回落到当前 `mode` 下第一个带题目的模板。

新增可测类型 `ComposerSelection`（放 `Presentation/`），把「当前选了什么 / 点某张卡之后变成什么」从 View 里抽出来：

```swift
struct ComposerSelection {
    enum Style { case timeOnly, prompted }
    var style: Style
    var templateID: UUID?
    var mode: Challenge.Mode

    mutating func selectTimeOnly(in: [ChallengeTemplate])
    mutating func selectPrompted(in: [ChallengeTemplate])
    mutating func select(_ template: ChallengeTemplate, oneDay: [ChallengeTemplate], sevenDay: [ChallengeTemplate])
    var promptGridEnabled: Bool { style == .prompted }
}
```

View 只持有它并渲染，逻辑全部可单测。

### 4.3 新建故事：题目可见性（方案 A 的预览条 + 方案 C 的网格副标题）

1. **题目预览条**：双卡正下方新增 `PromptPreviewStrip`。
   - 主题挑战态：`完美的一天 · 7 个题目` + 序号 chip 流（`1 起床`、`2 咖啡`…），右上「换一个 ›」滚动到推荐网格。
   - 时间记录态：文案换成「没有题目 · 拍到的每一段按时间排好」，chip 区隐藏。
   - chip 文案走 `MomentCatalog.localize(_:)`，不新增字符串常量。
2. **推荐网格副标题换成真题目**：`PromptTemplateTile` 的 `template.displayBlurb` → 前三个题目拼接 `起床 · 咖啡 · 收拾出门…`。blurb 移到「更多模板」库页面里继续用。

新增本地化字符串（`Localization.swift`，中英双语）：

| key | 中文 | English |
|---|---|---|
| `promptCountLabel(_:)` | `7 个题目` | `7 prompts` |
| `swapTemplate` | `换一个` | `Swap` |
| `timeOnlyPreviewBody` | `没有题目 · 拍到的每一段按时间排好` | `No prompts · every clip lands in time order` |
| `promptsNotNeeded` | `按时间记录不需要题目` | `Recording by time needs no prompts` |
| `headerDateProgress(_:_:)` | `今天 1/7` | `Today 1/7` |

---

## 5. PR 拆分

四个 PR 依次落地，每个都能独立 review、独立回滚。前三个是本次范围，`PR-0` 是前置清理。

| PR | 标题 | 触碰文件 | 依赖 |
|---|---|---|---|
| **PR-0** | `chore: 把 migration/2026-08-24 的散改拆出可 review 的基线` | 见 §6 | — |
| **PR-1** | `feat: 首页 header 让位给今天` | `PlansHomeView.swift`、新增 `Presentation/HomeHeaderSummary.swift`、`Localization.swift`、`AISetlogTests/HomeHeaderSummaryTests.swift` | PR-0 |
| **PR-2** | `fix: 新建故事只留一套选择器` | `ComposerSteps.swift`、新增 `Presentation/ComposerSelection.swift`、`StoryComposerView.swift`、`AISetlogTests/ComposerSelectionTests.swift` | PR-0 |
| **PR-3** | `feat: 选题目之前先看见题目` | `ComposerSteps.swift`、`Localization.swift`、`LocalizationTests.swift` | PR-2 |

落地分支与 commit：

| PR | 分支 | commit |
|---|---|---|
| PR-0 | `migration/2026-08-24` | `bb27b2d` `38bc0da` `db428c4` `9b3e0e1` `6ebd009` `eabf0eb` |
| PR-1 | `feat/home-header-today` | `49ec680` |
| PR-2 | `fix/composer-single-selector` | `373be03` |
| PR-3 | `feat/prompts-visible-first` | `dc1e215` |

PR-2 与 PR-3 都改 `ComposerSteps.swift`，但分工明确：PR-2 只动选择逻辑与 disabled 态，PR-3 只加预览条与替换 tile 副标题。顺序执行不冲突。

### 各 PR 的验收标准

**PR-1**
- [x] header 无 `OneDayBrandLogo`；头像在最左且可进设置。
- [x] 副行显示日期；有进行中故事时显示 `今天 n/m` 与 pips，无故事时只显示日期。
- [x] `+` 视觉直径 36pt、无 glow；热区 ≥ 44pt（`contentShape`）。
- [x] `HomeHeaderSummaryTests`：中英两种语言下日期串正确；无故事时 `recorded == nil`；有故事时数字与 `challenge.recordedCount / cards.count` 一致。

**PR-2**
- [x] 主题挑战在左且为默认选中，同时默认选中「完美的一天」。
- [x] 选中「按时间记录」时推荐网格不可点、透明度 0.4，并显示 `promptsNotNeeded`。
- [x] 七日模式下已选模板时点「主题挑战」有明确反馈，不再静默无响应。
- [x] `ComposerSelectionTests`：覆盖 time-only ↔ prompted 互切、点网格卡片自动切 mode、`promptGridEnabled` 在两种态下的取值。

**PR-3**
- [x] 预览条在主题挑战态展示该模板全部题目（序号 + 名称），在时间记录态展示 `timeOnlyPreviewBody`。
- [x] 推荐网格每张卡副标题为前三个题目，不再是 blurb。
- [x] 「更多模板」库页面仍显示 blurb（`PromptTemplateTile.Subtitle.blurb`）。
- [x] `LocalizationTests`：新增 5 个 key 的中英文均非空且互不相同。

## 6. PR-0：先把现在这堆改动理干净

现状：`migration/2026-08-24` 上有 **33 个未提交文件、约 +1393/−506 行**，混着上一位 agent 的 composer 重构、录制改动、本地化扩充、测试更新和一批文档/素材。在这上面继续叠 PR 会 review 不动。

PR-0 的动作（不改任何行为，只做归档）：
1. 按主题拆成 3~4 个 commit：`composer 重构`、`录制与时间线`、`本地化与测试`、`文档与素材`。
2. `docs/mockups/`、`docs/audit-2026-08-31-live/`、`design-qa.md`、`.playwright-cli/` 归位或加 `.gitignore`（`.playwright-cli/` 与 `ios/build/` 应当忽略）。
   - 实施结果：`design-qa.md` → `docs/design-qa-1.2-first-run.md`；根目录 `.playwright-cli/` 加入 `.gitignore`；`ios/build/` 原本已忽略。
3. 跑一次全量 `AISetlogTests` 建立基线。

## 7. 待办（本次不做，单独排期）

| 项 | 位置 | 说明 |
|---|---|---|
| hero 选错 | `RootShellView.swift:31` | `.min { $0.recordedCount < $1.recordedCount }` 让「拍得最少」的旧故事霸占「今天的故事」，今天真正在拍的被挤到下面。PR-1 的日期只是缓解，不是根治。 |
| 自由拍摄丢视频 | `RecordClipView.swift:255`、`ClipRecorder.swift:215` | ~~`onSave` 是空闭包~~ —— 更正：自由拍摄走的是 `showSavePicker` → `store.saveClip`，`CameraTabView` 那个空 `onSave` 在这条路径上从不被调用。真正的问题是**没有草稿箱**：片子先写进 `temporaryDirectory`，只有归档成功才落盘；而「一个计划都没有」和「画幅不匹配」两种情况只弹一句 toast，用户除了重拍就只能离开，一离开这一屏片子就没了。**严重度最高。** |
| 封面重复 | `ChallengeTemplate.swift:56,60` | 「和我过一天」与「我的主角日」共用 `TemplateMainCharacter`，在网格里长得一样。 |
| 首页无日期维度 | `PlansHomeView` | 只按「进行中/已完成」分组，没有按天回看的入口。 |
| 引导题目时态混乱 | `GuidedMomentsView.swift:170` | 「今天吃了什么？」是过去时，但填写时机在一天开始之前。 |

## 8. 风险

- `ComposerSteps.swift` 已被上一位 agent 大改（+418 行）且未提交。PR-2/PR-3 必须建立在 PR-0 之后，否则改动会和未提交内容纠缠。
- 新增 `Presentation/` 类型需同步 `ios/project.yml` 与 XcodeGen 生成，注意 `project.pbxproj` 的冲突。
- header 副行在 iPhone SE（375pt）宽度下 `日期 + 今天 n/m + 7 颗 pips` 可能挤，需要 `minimumScaleFactor` 或在窄屏隐藏 pips —— 实施时以 SE 为准回归一次。
  - **回归结果（2026-09-01，iPhone SE 2nd gen 真机模拟器）**：`9月1日 周二 · 今天 0/3` + pips 一行放得下且有余量；pips 已加 `layoutPriority(-1)`，7 颗的故事在更窄的屏上会先让位，日期与数字始终完整。

## 9. 已知环境问题（与本次改动无关）

`CloudKitIdempotencyTests` / `CloudKitPaginationTests` 直接写真实 CloudKit
development 容器，本机跑会报 `CKError 10/2007 "CREATE operation not permitted"
(iCloud.com.cassie.AISetlog)`。这是容器权限/schema 的问题，不是代码问题——PR-1
基线那次它们是整体 skip 的，之后 iCloud 一旦可达就会失败。本次验收用
`-skip-testing:` 排除这两个类，其余 78 个测试全绿。要根治需要单独查 CloudKit
Dashboard 的 development schema 权限。

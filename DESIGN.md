---
name: 1Day
skins: [cream, blue]
colors:
  ink: "OneDay.ink"
  ink-soft: "OneDay.inkSoft"
  ink-faint: "OneDay.inkFaint"
  brand-fill: "Color.oneDayBrand"      # cream #FFCB45
  brand-text: "OneDay.brandText"       # cream #8A5A00
  on-brand: "OneDay.onBrand"
  canvas: "OneDay.canvas"              # cream #FFF8E8
  surface: "OneDay.surface"
typography:
  title: "title2 · rounded · bold"
  headline: "headline · rounded · bold"
  body: "body · rounded"
  callout: "callout · rounded · semibold"
  subhead: "subheadline · rounded · semibold"
  caption: "caption · rounded · semibold"
  micro: "caption2 · rounded · semibold"
rounded: { tile: 12, chip: 14, card: 24, hero: 32 }
spacing: { xs: 4, s: 8, m: 12, l: 16, xl: 20, xxl: 28 }
hit-target: 44
---

# 1Day 设计规范

TL;DR：改 1Day 界面时照这份文件做。

1. 数值：上面 YAML 里的 token 是唯一可用的值，页面代码只写 `OneDay.xxx`。
2. 组件：§3 每个组件的尺寸和状态都是定值，照抄，不自己调。
3. 页面：§4 写了每个页面长什么样，§5 是不许做的事，§6 记了每个取舍为什么这样定。

代码位置：token 在 `ios/AISetlog/Resources/Theme.swift`，组件在 `ios/AISetlog/Views/DesignSystem/`。没定的写 **【待定】**。

## 1. 原则

1. 画面：片段画面在屏幕上占的面积最大，按钮、文字、卡片不盖在画面上。竖拍放进横框不裁脸，空处用同一段画面的模糊图补满。
2. 入口：一个操作只有一个按钮、一个名字；一段片段在一屏里只显示一次。
3. 文字：砍掉标语、提示文字和次要标签。页面非得靠这些才看得懂，就改布局。能从画面看出来的信息不写成字。
4. 取舍：每个决定同时提升用户体验（UX）、开发者体验（DX）和智能体体验（AX），而且不弄坏任何东西。
5. 验收：在 iPhone 上截图看。

## 2. 颜色和字的用法

1. 品牌色：黄色只当填充（主按钮、选中描边、序号底）。黄色上的字用 `on-brand`，浅底上的品牌色字用 `brand-text`。
2. 文字层级：一屏最多三种文字颜色：`ink` 标题和正文，`ink-soft` 次要信息，`ink-faint` 占位图标。
3. 字号：一屏最多三档字号。页面标题 `title`，日期这类分组标题 `headline`，按钮 `callout`。

## 3. 组件

所有可点的东西点击区域至少 44 × 44。

### 主按钮 `PrimaryActionStyle`

- 尺寸：整行宽，上下内边距 17，胶囊形。
- 样子：品牌色渐变底，`headline` 字，`on-brand` 颜色。
- 按下：缩到 0.975。禁用：整体透明度 0.4。
- 数量：一屏最多一个。

### 胶囊小按钮（标题栏里的「做 vlog」「帮我挑」）

- 尺寸：高 38，左右内边距 `m`，胶囊形。
- 普通：`oneDayBrand` 18% 底，`callout` 字，`ink` 颜色。
- 强调（「生成 · N 段」）：`oneDayBrand` 实心底，`on-brand` 字。禁用：透明度 0.45。
- 加载：图标位置换成小号 `ProgressView`，按钮不可点。

### 文字按钮（「取消」「全选」）

- 样子：`callout` 字，`brand-text` 颜色，没有底色。
- 尺寸：最小高度 44。

### 圆形图标按钮 `IconBubble`

- 尺寸：圆 38，点击区域 44。
- 用在：日历、关闭。图标旁边没有字时必须有 `accessibilityLabel`。

### 片段小图 `ClipTile`

- 尺寸：宽高比 3:4，圆角 `tile`（12），格子之间 `xs`（4），一行三个。
- 角标：右下角拍摄时间，`ClipTileLabel`，24 小时制。
- 选中：内侧 3pt 品牌色描边；右上角直径 24 的圆，品牌色底，里面写序号。
- 选择中没选：右上角直径 24 的空心白圈，画面不变暗。
- 空格子「拍一段」：同样 3:4 和 `tile` 圆角，`oneDayBrand` 18% 底，`camera.fill` 加「拍一段」，`brand-text` 颜色。

### 心情表情 `MoodTodayBadge`

- 尺寸：图 22，点击区域 44。
- 没选：`face.dashed`，`ink-faint`。选了：当天表情。
- 点开：5 个表情的弹框，选完自动关。

### 登录按钮

- Apple：系统按钮，黑底。Google：白底，1pt 细边，官方 G 图标 18。
- 两个同高（设置页 46，登录页 50），都是胶囊形。

### 底部 tab `FloatingTabBar`

- 两个 tab：相机、房间。选中的 tab 是品牌色实心胶囊。
- 选择模式和全屏弹窗里隐藏。

## 4. 页面

### 「我的」·浏览

1. 标题栏：头像 48、「我的」（`title`）、日历 `IconBubble`、「做 vlog」胶囊小按钮。
2. 列表：按天分组，从新到旧。每组是日期（`headline`，今天写「今天」）+ 心情 + 三列 `ClipTile`。组和组之间 `xxl`，不包卡片。
3. 今天：永远是第一组。没拍时放一个「拍一段」空格子。
4. 组内顺序：同一天里按拍摄时间从早到晚。

### 「我的」·选择

1. 进入：点「做 vlog」，自动勾选今天所有片段。
2. 标题栏：左「取消」文字按钮；右「帮我挑」胶囊 +「生成 · N 段」强调胶囊。不显示头像和标题。标题栏固定在顶部。
3. 每组右侧：「全选 / 取消全选」文字按钮。空的一天不显示。
4. 底部 tab 隐藏，屏幕底部不放任何栏。

### 成片页（「我的」vlog、房间成片）

1. 标题：一行，`title`，放不下缩小、不换行。内容依次取 AI 标题、房间名、「我的 vlog」。
2. 画面：成片播放器，占标题下方剩余空间。
3. 按钮：【待定】，见 §6 第 6 条。

### 设置·没登录

1. 卡片：宝宝图 64、「还没登录」（`headline`）、Apple 按钮、Google 按钮，间距 10。
2. 不写说明句。

## 5. 不要做

1. 不在每天的卡片上放「做 vlog」：右上角已经有一个。
2. 不在顶部再列一遍已选片段：格子上的序号已经说明了。
3. 不写「· 4 段」「这周拍了 3 天」「今天 2/2 人拍了」这种计数。
4. 不写「片子好了」这种状态行，也不在标题下写段数、时长、人数。
5. 不把没选的片段调暗或盖白：看起来像坏了。
6. 不在卡片里再套卡片，也不给分组包白底卡片。
7. 不让两条浮动栏叠在一起（选择栏 + tab）。
8. 不在房间页放心情入口：心情只给自己看。
9. 不用 Google SDK 自带的方块登录按钮：和 Apple 按钮长得不一样。
10. 不写 `.system(size:)`、`cornerRadius: 16`、十六进制颜色。例外只有：相机取景叠加层、画进视频的字、头像和图标的固定尺寸、Google 登录按钮的字号。代码里不加注释说明。

## 6. 取舍记录

每条写：定了什么、比过哪些、为什么。

1. 选择模式的生成按钮：放在右上角（方案 A）。比过底部深色托盘（B）和顶部一行小图（C）。A 屏幕全留给片段，也和 iOS 相册的「选择」一样，用户不用学；代价是选择页不能拖动换顺序，换顺序放到成片页。样稿：`docs/design/selection-mode-options.html`。
2. 已选片段的卡片：删掉。它占了近半屏，片段在卡片和格子里各出现一次。
3. 心情入口：从房间页挪到「我的」页「今天」旁边。房间页是给朋友看的，心情只给自己看；原来「我的」页的心情卡片因为条件写反，从来没显示过。
4. AI 帮我挑：只传文字标签，画面不出手机。比过传缩略图（效果好，但要改隐私政策、按图片计费）和不做 AI。方案：`docs/design/ai-pick-options.md`。
5. 横竖拍：建房间时不再选「怎么拍」，竖拍和横拍都能进同一个房间，成片方向跟多数片段走，少数方向用模糊铺底。比过「改成选成片方向」和「保持不混」。【待做】
6. 成片页按钮组：【待定】。`feat/app-uncommitted-work` 上定的是「一个主按钮（保存）+ 一行图标按钮（换顺序、调整、分享）」（`2f32016`），还没合进来；当前分支是 2×2 四个胶囊。

## 7. 改界面的步骤

1. 选方案：有两种以上做法时，做 2–3 个 HTML 样稿放 `docs/design/`，用 `mockups` 服务（4321 端口）打开给 Cassie 选，选完记进 §6。
2. 提交前：跑 `python3 .claude/skills/1day-design-system/scripts/design_lint.py --baseline docs/design/design-lint-baseline.json`，有文件比基线差就不提交。
3. 基线：按文件记数。拆文件只搬代码时，只更新搬过的那几个文件的条目，不整体重写。
4. 截图：先用 `phone_status` 看 iPhone 能不能连；连不上就用自己专属的模拟器，并说明截图来自模拟器。

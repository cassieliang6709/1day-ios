# 1Day 设计规范

这份文件是 1Day 界面长什么样的唯一依据。改界面、加组件、评审截图，都对照这里。代码里的落点是 `ios/AISetlog/Resources/Theme.swift`（`OneDay` 里的 token）和 `ios/AISetlog/Views/DesignSystem/`（共用组件）。

以后再有没拍板的条目，标 **【待定】**，拍板前照代码现状写。

## 1. 原则

1. **视频是主角。** 界面元素让位给画面：卡片、按钮、文字都比画面安静。竖拍放进横框时不裁人脸，用并排或模糊铺底补满。
2. **同一个东西只有一种样子。** 片段小图、房间卡片、按钮、分区标题，全 App 各只有一个组件。新页面先找现成组件，没有才加，加了写进第 6 节。
3. **用 token，不写数字。** 字号、圆角、间距、颜色在页面代码里只写 `OneDay.xxx`，不写 `.system(size: 13)`、`cornerRadius: 16` 这种数字。例外写在第 7 节。
4. **以真机为准。** 好不好看、统不统一，看 iPhone 上的截图，不看代码。

## 2. 颜色

只用 `OneDay` 里的语义色，不在页面里直接用 `Color.oneDayNavy` 之类的原始色，更不写十六进制。App 有两套皮肤（奶油黄 / 蓝），语义色会自动跟着换。

| Token | 用途 |
| --- | --- |
| `OneDay.ink` | 正文、标题 |
| `OneDay.inkSoft` | 次要文字、分区标题 |
| `OneDay.inkFaint` | 时间戳、占位提示这类可以不读的字 |
| `OneDay.brandText` | 品牌色的**文字**（奶油黄皮肤下是深琥珀色，黄色本身不能当字） |
| `OneDay.onBrand` | 画在品牌色底上的字和图标 |
| `Color.oneDayBrand` | 品牌色的**填充**：主按钮、选中的 tab、拍摄键 |
| `OneDay.canvas` | 页面底色 |
| `OneDay.surface` / `OneDay.surfaceSoft` | 卡片底 / 小标签底 |
| `OneDay.hairline` | 玻璃卡片的细边 |
| `OneDay.scrim` | 视频上方压字用的渐变 |

身份色（每个人头像的颜色）由 `Identity+Color.swift` 按人分配，页面不自己挑。

## 3. 文字

只用 `OneDay.Font` 的 7 档。它们都是圆体，并且跟着系统字号设置（动态字体）放大缩小。

| Token | 用途 |
| --- | --- |
| `title` | 页面大标题（「房间」） |
| `headline` | 卡片标题（房间名） |
| `body` | 正文、聊天内容 |
| `callout` | 按钮文字 |
| `subhead` | 卡片副标题（「你 · 12:29」） |
| `caption` | 小标签、时间、计数 |
| `micro` | 视频上的角标（时长、REC） |

需要别的粗细时用 `OneDay.Font.rounded(_:weight:)`，不另起字号。

## 4. 圆角

| Token | 值 | 用途 |
| --- | --- | --- |
| `OneDay.Radius.chip` | 14 | 小标签、输入框、小按钮 |
| `OneDay.Radius.card` | 24 | 卡片、底部弹窗 |
| `OneDay.Radius.hero` | 32 | 首屏大卡片 |
| `OneDay.Radius.tile` | 12 | 片段小图：卡片里的小图、「我的」网格的外框、成片条、聊天里引用的片段 |

为什么是 12：卡片圆角 24、内边距 12，嵌在里面的东西用 24 − 12 = 12，内外两条弧线平行。以后别的东西嵌进卡片，也按「外圆角 − 内边距」算，算出来不是现有 token 时先来这里加。

「我的」那种紧挨着的网格，只有整块的四个外角用 `tile`，格子之间不做圆角。

胶囊形（按钮、tab 栏）用 `Capsule()`，不算圆角 token。

## 5. 间距

只用这 6 档，padding、`spacing:`、外边距都一样：

| Token | 值 | 用途 |
| --- | --- | --- |
| `OneDay.Space.xs` | 4 | 图标和文字之间、紧挨着的网格缝 |
| `OneDay.Space.s` | 8 | 同一组里的元素之间 |
| `OneDay.Space.m` | 12 | 卡片内边距、头像和文字之间、标题和下面内容之间 |
| `OneDay.Space.l` | 16 | 卡片之间、大卡片的内边距 |
| `OneDay.Space.xl` | 20 | 页面左右边距 |
| `OneDay.Space.xxl` | 28 | 分区之间 |

旧页面换过来时按这张表对：

| 旧值 | 换成 |
| --- | --- |
| 3、5、6 | `xs`（4）或 `s`（8），看是不是紧挨着的一组 |
| 9、10、11 | `s`（8）或 `m`（12），同一组里的用 8，隔开两块的用 12 |
| 14、18 | `m`（12）或 `l`（16），卡片之间一律 16 |
| 22、24、26 | `xxl`（28），分区之间 |

换的时候会有一两个点的变化，按 1day-design-system 的路径 B 逐页截图对比。

## 6. 组件清单

页面要的东西先在这里找。状态是「已统一」才可以直接用；「待合并」的那几个，新代码只用合并目标，不再用旧的。

| 组件 | 用途 | 位置 | 状态 |
| --- | --- | --- | --- |
| `ClipThumbnail` | 片段第一帧，竖拍放横框时铺模糊底、不裁脸 | `Components/ClipPlayback.swift` | 已统一，是所有片段小图的底层 |
| `ClipTile` / `ClipTileLabel` | 嵌在卡片、列表行、弹窗、网格里的片段小图：圆角 `tile`、细边、选中时品牌色描边；角上的时间或时长用 `ClipTileLabel`。尺寸由调用方定。贴边放（网格、卡片封面）时用 `edge: .flush`，外角交给容器 | `DesignSystem/ClipTile.swift` | 新建，各页正在换过来（第一批） |
| 占满页面宽度的大画面 | 房间里每个人的大格、时间线大卡 | `PersonFrame`（22）、`ClipThumb`（16） | **待合并**（第二批）：直接放在页面上的按卡片用 `card` 圆角 |
| `PortraitTile` | 房间列表和「我的」里的竖版卡片：最新一段做 3:4 封面，下面是名字和一行说明 | `Components/PortraitTile.swift` | 已统一；圆角现在写的是 20，第二批改成 `card` |
| `GlassCard` / `.glassSurface()` | 普通卡片底 | `DesignSystem/OneDaySurfaces.swift` | 已统一，但多数页面没用它 |
| `OverVideoGlass` / `.overVideoControl()` | 压在视频上的玻璃底 | `DesignSystem/OneDaySurfaces.swift` | 已统一 |
| `PrimaryActionStyle` / `SoftActionStyle` | 主按钮 / 次按钮 | `DesignSystem/OneDayControls.swift` | 已统一 |
| `OneDayChip`、`PillSelector`、`OptionRow`、`SectionLabel`、`IconBubble` | 小标签、分段选择、设置行、分区标题、圆形图标按钮 | `DesignSystem/OneDayControls.swift` | 已统一 |
| `AvatarDot` / `AvatarStack` | 头像 / 一排头像 | `Avatar/`、`Components/AvatarStack.swift` | 已统一 |
| `FloatingTabBar` | 底部相机 / 房间两个 tab | `Components/FloatingTabBar.swift` | 已统一 |
| `EmptyFrame` | 空状态 | `DesignSystem/OneDaySurfaces.swift` | 已统一 |

合并一个组件的顺序：先把目标组件做好，再把用到旧组件的页面一个个换过去，每换一页在真机上截图对比，最后旧组件没人用了再删。

## 7. 可以写数字的例外

- **相机取景画面上的叠加层**（倒计时大数字、取景框线条）：跟着画面尺寸算，不跟着系统字号变。
- **合成进成片里的字**（字幕、水印）：画进视频像素，按视频分辨率算。
- **头像、图标的固定尺寸**：`frame(width:height:)` 可以写数字，但同一种东西尺寸要一样。

例外的地方在代码旁边写一行注释说明为什么。

## 8. 动效

只用 `OneDay.Motion` 的 `soft` / `pop` / `snap` 三种弹簧。系统打开「减弱动态效果」时，循环和缩放类动画套 `OneDay.Motion.reduced(_:if:)`，它会让动画直接跳到结果。不加入场飞入动画。

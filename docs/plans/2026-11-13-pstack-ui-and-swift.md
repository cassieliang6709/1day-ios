# pstack 在 1Day 的应用

## 来源与取舍

已核对 Lauren Tan / poteto 的 [pstack](https://github.com/poteto/plugins/tree/74dd2291e8e37b12fd6dc49b2acbd655c6bdaf12/pstack)，不是同名的 Linux 堆栈工具。
阅读了 README、poteto-mode、perf-issue，以及 prove-it-works、build-the-lever、subtract-before-you-add、encode-lessons-in-structure 四条原则。另参考作者的 [verification-skill-example](https://github.com/poteto/verification-skill-example) 中“按用户旅程验证”的结构。

采用的是方法，而非原样复制 Cursor 插件、模型配置或并行 agent 流程。这里是原生 SwiftUI / AVFoundation，验证入口必须落在 Xcode、XCTest、模拟器和真机上。没有 iOS trace 的源代码发现只能叫风险或缺陷，不能叫已量化的性能收益。

## UI 建议

以下是从当前代码得到的建议，不是已完成的界面截图审计。竞品只作为设计方向的类比，没有在本轮捕获它们或本 App 的原生页面。

| 借鉴方向 | 对当前 1Day 的建议 | 这一轮 |
| --- | --- | --- |
| 系统相机的操作集中 | 保留 Camera / Rooms，不因旧 PRD 再加一层导航。拍摄和记录后的去向比增加装饰重要。 | 保持结构 |
| Photos 的内容优先 | 奶油黄、头像和胶囊已经有辨识度。先减少无关的持续运动，把最亮的视觉留给真实片段；不据此断言所有阴影和模糊都是性能瓶颈。 | 时间线装饰 pulse 尊重 Reduce Motion |
| 原生选择控件的稳定反馈 | 底栏始终保留文字和选中颜色；开启 Reduce Motion 后无需滑动的选中底板或符号替换动画。 | 已修改底栏 |
| 随系统文字设置适配 | `FloatingTabBar` 目前使用固定字号，并限制 Dynamic Type 上限。应该比较大字体、小屏、中英文，再决定自适应布局，避免仅取消上限后产生溢出。 | 待原生截图与布局验证，不盲改布局 |
| 私人日记的明确归属 | 区分“已在我的片段里”和“已分享到某个房间”，把下一步放在内容附近。当前 `rooms-personal` 已有文字入口，不应重复加浮动入口。 | 建议，未增加入口 |
| 分享工具的可恢复状态 | 房间等待媒体时先给可用内容；失败给局部重试，保留已拍素材。继续验收上一批下载保护、互动先返回和缓存版本修复。 | 使用 verify 的 room / media 旅程 |

没有更换品牌色、重排主流程或添加新的打卡/计数压力。布局、对比度和视觉层级的正式结论仍需要当前原生页面。

## 三个项目 skills

- [dayday-mode](../../.agents/skills/dayday-mode/SKILL.md)：把用户动作、数据所有权、小改动和验证连在一起。
- [dayday-swift-performance](../../.agents/skills/dayday-swift-performance/SKILL.md)：线程隔离、任务取消、媒体生命周期、缓存成本、请求版本及测量方法。
- [dayday-verify](../../.agents/skills/dayday-verify/SKILL.md)：可运行的 doctor / static / 选定 XCTest，配合短小的用户旅程。已在 AGENTS.md 注册引用。

项目内可使用这些名称或直接指向对应 SKILL.md。它们是项目文件，不代表已安装 Cursor 的 pstack 插件。

## 本轮决定与应用

| 证据 | 决定 | 没有选择的方案 |
| --- | --- | --- |
| `AvatarImageCache` 用静态字典强持有每个解码头像，没有驱逐策略 | 改为 NSCache，按解码字节成本设置 12 MiB 与 64 条驱逐目标，更新或删除文件时失效；主动清除 URL 自带的元数据缓存以重新读取版本 | 未重写头像服务，未改图片尺寸或画质，未宣称总内存会严格低于 12 MiB |
| 时间线 pulse 与底栏替换动画没有读取 Reduce Motion | 仅在系统要求时停用这两处装饰动画，保留选择和操作能力 | 未更换设计系统或删除所有动画 |
| 上一批只有一次性静态命令，Linux 又没有 Xcode | 把检查变成可重复运行的工具，native 前置条件缺失时返回 2，测试零执行不算通过 | 不把解析、构建或脚本退出码冒充 iOS 行为证据 |

## 证据状态

已在 Linux 执行 helper 的 static、doctor 和 test --target avatar。static 通过并单列 4 处原有 Presentation `.now` 默认参数；doctor 与 test 返回 2，明确说明缺少 macOS / Xcode / XcodeGen。
另在临时 Git 仓库验证 static 模式能拒绝新分层违规，并允许单独报告既有债务。Python 脚本和本轮 Swift 改动通过语法检查。

头像更新、复用、删除的回归用例已加入现有 `MemberProfileSyncTests`。XCTest、UI 交互、原生截图和前后性能测量尚未执行。helper 的 macOS 测试执行分支也尚需首次实机运行，未声称验证过。

在 Mac 上先运行：

```bash
python3 .agents/skills/dayday-verify/scripts/verify.py doctor
python3 .agents/skills/dayday-verify/scripts/verify.py test --target avatar
python3 .agents/skills/dayday-verify/scripts/verify.py test --target ui
```

随后按 UI 旅程对比 Reduce Motion 与大字体；按同一设备、同一房间数据和同一 Release 构建捕获头像回看前后的内存峰值。UI 测试通过仍不能代替这些视觉和性能证据。

## 后续应用：共用按钮与拍后房间列表

用户希望继续完善体验，同时保持现有 UI 风格。这次应用 `dayday-design-system` 和 `dayday-verify`，没有新增主题体系。

- 主、次按钮现在读取 Reduce Motion，开启后按压不缩放；主按钮仍改变光晕，次按钮改变透明度，保留反馈。次按钮也根据 `isEnabled` 降低强调程度。
- 拍后 `RoomSendList` 的文字与图标改用语义字号，长标题允许两行，列表高度预算随字号缩放。保留原有最小 44pt 行高和选择逻辑。
- 选中图标使用 `brandText`，未选中使用 `inkSoft`；VoiceOver 读取完整房间名与已有选中 trait，装饰图标不单独朗读。
- 搜索确认 `PillSelector` 当前只有定义，没有调用；本轮没有修改该闲置组件。主次按钮有实际调用，房间列表由拍后预览使用。

静态分层与 diff 检查、两份改动 Swift 文件的 tree-sitter 语法解析通过。`doctor` 返回 2，缺少 macOS / Xcode / XcodeGen。没有新增只验证样式常量的测试；已将实际按钮和长房间名的验收步骤加入 verify 旅程。原生编译、VoiceOver 朗读、最大字号下保存按钮是否仍可达，以及两种皮肤的视觉验收尚未执行。本次不宣称运行时性能收益。

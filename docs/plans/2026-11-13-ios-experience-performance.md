# iOS 体验与性能：优先修复的 10 项

基线：`main` / `cad8642fe87dfdbc1f1246007ff8f32fc847eff8`。修复放在独立分支供审查，未合并到 main、部署或发布环境。

## 产品判断

以当前 README 的 1.5 流程和现有实现为准：打开相机 → 随手记录 → 保存 → 在自己或朋友的时间线回看 → 按需生成影片。
沿用当前 Camera / Rooms 双入口，不把旧 PRD 的三入口或尚未确定的提案直接变成新需求。
优先让用户刚拍的内容正确出现、退出后停止耗资源、失败时保住已有文件，再处理首屏等待。
不增加打卡压力、强制整理步骤或后台自动生成影片。

这是基于源代码的产品与性能审查。当前 Linux 没有 Xcode、iOS 模拟器或 Instruments；没有完成界面截图审计，也没有真机帧率、能耗或速度测量。下列优先级依据用户影响和代码证据，不代表已测出的耗时排名。

## 任务顺序

“已改”表示代码已实施，仍待 macOS 编译和 iOS 验证。

| 顺序 | 优先级 | 任务、证据与用户影响 | 当前状态 |
| --- | --- | --- | --- |
| 1 | P0 | **重拍和编辑后正确回看多人瞬间。** `StitchedMomentPreview.cacheKey` 原先只拼 day 与 clip ID；同 ID 同 URL 的重拍，以及第二条字幕或字幕位置的变化都可能命中旧文件。改为完整画面版本，并在请求变化时重置旧播放和失败状态；不把重建的字幕 UUID 当作画面变化。 | 已改 |
| 2 | P0 | **下载失败不能先删掉本地可用素材。** `OneDayAPI.download` 和 `RoomClipCache.install` 原先先删除目标再移动文件。现在先暂存到目标目录，再替换完整文件；同时处理取消、删除下载临时文件、保留真实目录错误。下载使用移动而非多复制一份整个视频。 | 已改 |
| 3 | P1 | **离开成片页或改变设置时，停止无用导出。** 原有 `exportAsynchronously` 不会随 Swift task 自动取消，滤镜和重构图还会吞掉错误继续处理。主导出、滤镜与重构图接入 `cancelExport`，传播取消并清理中间文件；重试也走页面管理的 `.task`。不包含配乐与录制后烘焙的独立流程。 | 已改 |
| 4 | P1 | **缩略图既要刷新正确，也要避免反复解码。** `ClipThumbnail.task` 原先只按可空的 recordedAt 启动，URL 变化可能不刷新，旧任务还可能写回图片。现在按 URL + 拍摄版本加载、取消过期请求，并用有成本限制的 NSCache 复用解码帧（24 MiB / 120 条为驱逐目标，不是总内存保证）。 | 已改 |
| 5 | P1 | **片段离屏或进后台后不继续循环解码。** `LoopingPlayerLayerView` 原先只在 dismantle 时 pause，更新 muted 不生效，旧 looper/队列未显式释放。现在由可见性和 scenePhase 控制播放，更新静音，切换和销毁时解除 looper、清空队列与 layer。 | 已改 |
| 6 | P1 | **成片更新时切换到新视频，避免播放器和观察者残留。** `VlogPlayer` 的 State 原先只在 init 中根据 URL 创建；URL 更新可能仍保留旧播放器。结束通知的 block observer 也没有注销。现在切换素材并重置比例，注销观察者，后台暂停，进入全屏时暂停内嵌播放。 | 已改 |
| 7 | P1 | **房间页在后台停止定时轮询。** `StoryTimelineView` 的 10 秒循环原先只绑定 challengeID，没有前后台条件。现在仅在 active 时启动，退后台取消循环，回前台立即同步，仍保留手动刷新和推送触发的更新。这不承诺中断 RoomSyncService 内部已经开始的共享拉取。 | 已改 |
| 8 | P1 | **限制多人瞬间缓存，回收无主的衍生视频。** 原先静态 `[String: URL]` 没有容量或删除策略；完善版本键后，每次重拍更会生成一条。现在以 8 条 LRU 保留缓存，缓存与正在播放的视图共享文件所有权；淘汰不会删掉仍被预览使用的文件，最后一个持有者释放后清理。 | 已改 |
| 9 | P1 | **切换相机时避免主线程等配置队列。** `ClipRecorder.flipCamera` 原先使用 `sessionQueue.sync`，换输入、准备格式、提交配置都在同步等待范围内。现在在串行队列异步配置，增加 `isChangingCamera`，阻止重复切换、双摄配置和拍摄交错；主线程接收结果，失败恢复旧输入，恢复也失败则显示相机不可用。页面关闭后完成的切换不会重新开启闪光灯。需要真机验证前后置、双摄、横竖拍、缩放与闪光灯。 | 已改 |
| 10 | P1 | **让互动不排在全部视频后。** `ChallengeStore.syncRoom` 原先依次等待成员、片段、补传、互动、标题。现在用结构化子任务独立拉取互动，媒体同步和补传不阻塞回应/评论出现；保留身份版本、房间 generation 防护，并让较新的互动请求优先，拒绝旧请求迟到覆盖。头像改为至多 4 个并发下载且保持成员顺序；片段沿用已有 4 个下载并发限制。成员列表本身仍等待头像阶段，未宣称所有首屏内容都立即返回。 | 已改 |

## 验证与交接

在现有 XCTest 文件中补了 8 个针对真实边界的回归测试：同路径重拍；额外字幕与字幕位置（含无关 UUID 变化不失效）；人物顺序和烧录文字；取消后不读取媒体；安装失败保留旧文件与下载源的所有权；缓存淘汰时保留正在使用的文件；视频等待期间先展示互动；乱序响应不能让旧互动覆盖新结果。另调整原有退出账号测试：允许互动提前请求，但迟到结果不得写入，后续视频步骤不得继续。原有测试未删除，没有添加源文件或更改工程配置、锁文件、构建号。

本机结果：19 个改动的 Swift 文件通过语法树解析；`git diff --check` 和 Models 禁止引用 Strings 的检查通过；Presentation 没有新增分层违规。完整 Presentation 检查发现 4 处原有 `.now` 默认参数（`HomeHeaderSummary`、`HomeHeroChoice`、`HomeStories`、`StoryTimeline`），本轮未修改。这不是 Swift 类型检查或 iOS 运行验证；`xcodebuild -version` 返回 command not found，XCTest 尚未执行。

macOS 上先按 `AGENTS.md` 和 `.github/actions/setup-ios/action.yml` 使用 Xcode 26.2，执行 `cd ios && xcodegen generate --spec project.yml`。从 `simctl` 选现有模拟器，运行：

```bash
xcodebuild test -project AISetlog.xcodeproj -scheme AISetlog \
  -destination "id=$SIMULATOR_UDID" -derivedDataPath build/DerivedData \
  -only-testing:AISetlogTests/LocalRoomMediaKeyTests \
  -only-testing:AISetlogTests/RoomClipCacheTests \
  -only-testing:AISetlogTests/RoomPreviewMediaScopeTests \
  -only-testing:AISetlogTests/RoomSyncLifecycleTests \
  -only-testing:AISetlogTests/VideoStitcherTests \
  CODE_SIGNING_ALLOWED=NO
```

必须补验的实际流程：

1. 在不同视频间快速滑动，再重拍同一槽位；封面与播放都应对应新内容。
2. 多人瞬间里编辑第二条字幕和位置；重新打开应更新，内容未改则复用。
3. 成片导出中返回或改设置；Instruments 确认旧导出结束、中间文件释放，新请求没有被旧结果覆盖。
4. 播放片段后切后台、返回；离屏无声音，前台按预期恢复；内嵌切全屏没有双重播放。
5. 打开超过缓存容量的不同多人瞬间，确认已淘汰且不再使用的衍生文件回收，仍打开的预览可播放。
6. 弱网替换已有视频、取消下载、重试；旧完整文件保留，成功后替换；前后台切换后轮询没有重复计时器。
7. 真机快速切换前后置/双摄并马上点快门、切换中返回，再重新进入；配置中不可录制，完成后方向/缩放/闪光灯正确，退出后摄像头与灯不被迟到回调重新启动。
8. 受控网络暂停视频与头像请求；互动应先出现，旧账号及旧请求的响应不得覆盖当前数据。再用 Instruments 测量主线程等待和实际首屏时间。

上述检查通过之前，不称这些改动已经通过 iOS 验收，也不报告性能提升百分比。

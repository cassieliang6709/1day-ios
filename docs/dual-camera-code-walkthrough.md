# 1day 前后双拍与画中画代码导读

以“后摄拍风景，前摄拍自己，自己出现在右上角”为例，1day 的实现分为三步：同时采集两个摄像头、在取景界面叠放两个预览、录制结束后把两个文件合成一个画中画文件。后续回看、草稿和上传都接收这个单一文件。

这里的 PiP 指视频画面里的小窗，不是 iOS 退出 App 后悬浮播放的系统画中画功能。

## 先看整条路径

```text
点击“前后同时拍”
    RecordClipView → ClipRecorder.setDualCamera(true)
                           │
                  AVCaptureMultiCamSession
                    ┌──────┴──────┐
                   后摄           前摄
                    │              │
              主预览与文件输出   副预览与文件输出
                    │              │
取景时       DualCameraStage 把两个预览排成大图和小窗
                    │              │
录制时          primary.mov    secondary.mov
                    └──────┬───────┘
结束后              PiPComposer.compose
                           │
             两条视频轨道 + 一条主文件音轨
                           │
             内置视频合成器 + 白框后处理
                           │
                    导出 pip-….mov
                           │
                 CameraStyleBaker 处理风格
                           │
                     recorder.clipURL
```

`primary` 指最初的主采集通道，`secondary` 指后加的通道。它们不固定代表后摄与前摄；本例从后摄开始，所以 primary 是后摄。

## 第一站 开启前后两个摄像头

打开 [ClipRecorder.swift](../ios/AISetlog/Services/Media/ClipRecorder.swift)，从第 682 行 `setDualCamera` 看起，再看第 721 行 `addSecondaryCamera`。

| 对象 | 在本例中负责什么 |
| --- | --- |
| `AVCaptureMultiCamSession` | 组织前后摄同时采集，管理输入、输出和连接 |
| `AVCaptureDeviceInput` | 把一个具体摄像头接入会话 |
| `AVCaptureConnection` | 把指定摄像头的视频端口接到预览层或文件输出 |
| `AVCaptureVideoPreviewLayer` | 在屏幕上显示该摄像头的实时画面 |
| `AVCaptureMovieFileOutput` | 把该摄像头的画面录成视频文件 |

`addSecondaryCamera` 会查询设备支持的摄像头组合，选择能同时工作的前后摄。第二路输入和输出先通过 `addInputWithNoConnections`、`addOutputWithNoConnections` 加入，再显式连接，确保副摄画面进入副文件和副预览。代码还会检查硬件与系统压力预算；无法启用时保持单摄状态。

**这个阶段的工作是取得两路画面。视频合成规则在拍完之后才用到。**

## 第二站 取景时的小窗怎么出现

打开 [RecordClipView.swift](../ios/AISetlog/Views/Record/RecordClipView.swift) 第 788 行，以及 [CameraComponents.swift](../ios/AISetlog/Views/Record/CameraComponents.swift) 第 554 行。

`livePreview` 把 `CameraPreview` 和 `SecondaryCameraPreview` 交给 `DualCameraStage`。后者通过 `ZStack` 把一个预览铺满，另一个缩到小窗的位置，并绘制白框和阴影。

因此，屏幕上的画中画来自两个实时预览的界面布局。此时还没有生成画中画视频文件。

小窗的位置存放在 `recorder.insetRect`，布局算法在 [PiPInsetLayout.swift](../ios/AISetlog/Services/Media/PiPInsetLayout.swift)。坐标采用相对比例：例如宽度 `0.3` 表示画布宽度的 30%。预览和导出读取同一份位置数据，分别换算为屏幕点或视频像素。

点小窗会调用 `flipCamera()`。双摄模式下，它只切换 `isSwapped`，让两个预览交换大小；前后摄继续沿各自通道采集。小窗只允许在拍摄之间拖动和缩放，因为当前导出使用一份固定位置，没有记录逐帧的位置变化。

## 第三站 按下录制后先得到两个文件

看 [ClipRecorder.swift](../ios/AISetlog/Services/Media/ClipRecorder.swift) 第 459 行。

主输出调用 `movieOutput.startRecording`；副通道有效时，副输出也调用 `secondaryOutput.startRecording`。两路设置相同的最长录制时长，分别写文件。

录制结束回调从第 587 行开始收集结果，第 599 行等待两个输出都返回，再校正文件方向。第 631 行调用：

```swift
let composed = await PiPComposer.compose(
    primary: primary,
    secondary: secondary,
    secondaryIsMain: self.isSwapped,
    ...
)
```

上面是省略参数的阅读示意。`secondaryIsMain` 决定哪个文件铺满画面；声音始终取自 primary 文件，因为麦克风连接在主通道上。交换画面大小不会交换音源。

## 第四站 两个文件怎样合成画中画

仍看 [ClipRecorder.swift](../ios/AISetlog/Services/Media/ClipRecorder.swift)，从第 941 行 `PiPComposer.build` 开始。

假设两段素材都是 5 秒，目标画布是 1080 × 1920，后摄铺满，前摄放右上角。

| 对象或变量 | 本例中的任务 | 代码位置 |
| --- | --- | --- |
| `AVURLAsset` | 读取两个视频文件及其音轨、时长等信息 | 944 行 |
| `AVMutableComposition` | 建立时间轴，把两个视频片段都从第 0 秒放入各自轨道 | 955 行 |
| `AVMutableVideoCompositionLayerInstruction` | 分别指定后摄和前摄的旋转、缩放、位置，以及小窗裁剪 | 977、993 行 |
| `AVMutableVideoCompositionInstruction` | 指定这些图层规则作用的时间段，以及前后叠放顺序 | 1003 行 |
| `AVMutableVideoComposition` | 汇总画布大小、帧率和所有时间段的合成指令 | 1007 行 |
| `AVVideoCompositionCoreAnimationTool` | 把白色圆角边框和阴影叠到视频上 | 1011、1050 行 |
| `AVAssetExportSession` | 使用时间轴与画面规则，导出新的 `.mov` 文件 | 1013 行 |

**`AVMutableComposition` 管“哪段素材在什么时候出现”；`AVMutableVideoComposition` 管“那个时刻的画面怎么排”。** 这里的 `Mutable` 表示代码可以逐步设置和修改配置。

两段素材都插入第 0 秒，所以它们同时出现。如果把第二段接在第一段结束之后，就变成前后播放的剪辑。

图层顺序在代码里明确写成：

```swift
instruction.layerInstructions = [insetLayer, mainLayer]
```

前面的图层在上面，所以小窗盖在主画面上。小窗先按比例缩放，再裁剪到框内，避免画面溢出。整个输出以每秒 30 帧配置。实际输出尺寸取决于主素材和所选画幅，1080 × 1920 只是这个例子的尺寸。

导出完成后，两个原始输入文件会被删除，合成文件再经过 `CameraStyleBaker`，最后成为 `recorder.clipURL`。如果画中画合成失败，当前代码会保留主文件作为本次拍摄结果。

## 第五站 AVVideoCompositing 在项目哪里用

**前后双拍的 `PiPComposer` 使用系统内置合成器。** 它配置图层指令，让系统执行缩放、裁剪和叠放。

你贴的 `AVVideoCompositing` 则用在 [FriendsTogetherCompositor.swift](../ios/AISetlog/Services/Media/FriendsTogetherCompositor.swift) 第 37 行：多人同屏，以及成片中需要适配不同画幅的模糊背景处理。

在 [VideoStitcher.swift](../ios/AISetlog/Services/Media/VideoStitcher.swift) 第 227 行，多人布局通过下面的配置选用它；第 512 行的单片段模糊背景适配也复用这个合成器：

```swift
videoComposition.customVideoCompositorClass = FriendsTogetherCompositor.self
```

它需要根据素材与格子的比例决定裁剪填满，或者完整显示主体并在背后铺一份模糊画面。这类处理由 Core Image 绘制。

回到文档中的几个对象，读第 62 到 98 行就能逐一对应：

| 文档中的接口或对象 | 项目里的实际职责 |
| --- | --- |
| `sourcePixelBufferAttributes` | 声明接收 BGRA 格式的源像素缓冲区 |
| `requiredPixelBufferAttributesForRenderContext` | 声明输出缓冲区也需要 BGRA 格式 |
| `renderContextChanged` | 记住新的渲染尺寸 |
| `AVVideoCompositionRenderContext` | 提供输出尺寸，并通过 `newPixelBuffer()` 分配输出画面的内存 |
| `AVAsynchronousVideoCompositionRequest` | 携带这一帧的合成指令，让合成器取得各条轨道对应的源画面 |
| `FriendsTogetherInstruction` | 自定义指令，保存各个画面的轨道 ID、格子位置和方向 |
| `startRequest` | 读取源画面，用 Core Image 合成，写入输出缓冲区，再完成请求 |

其中最关键的动作是：

```swift
let source = request.sourceFrame(byTrackID: placement.trackID)
image = cell.composited(over: image)
self.context.render(image, to: buffer)
request.finish(withComposedVideoFrame: buffer)
```

上面摘出了核心语句，完整的循环和错误处理在源码第 74 行的 `startRequest` 中。`CIContext` 负责把 Core Image 的图像运算渲染进像素缓冲区；它与 AVFoundation 提供的 `AVVideoCompositionRenderContext` 分工不同。

如果将来把前后摄画中画改为自定义合成器，也可以在 `startRequest` 中取得后摄与前摄的源帧，先画满后摄，再画前摄小窗，最后交回一帧。但目前这条功能已经用内置图层合成实现。

## 苹果文档对照

- [AVMutableComposition](https://developer.apple.com/documentation/avfoundation/avmutablecomposition)：组织素材轨道和时间范围。
- [AVVideoComposition](https://developer.apple.com/documentation/avfoundation/avvideocomposition)：描述各时间点的视频画面合成规则，支持内置或自定义合成器。
- [AVVideoCompositionLayerInstruction](https://developer.apple.com/documentation/avfoundation/avvideocompositionlayerinstruction)：指定轨道的变换、裁剪和透明度。
- [AVVideoCompositing](https://developer.apple.com/documentation/avfoundation/avvideocompositing)：自定义合成器需要实现的协议。

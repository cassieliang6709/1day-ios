# 1day — 核心功能规格说明书 (Detailed Feature PRD)

> **版本**：v3.0 (Structured Engineering PRD)  
> **更新日期**：2026-09-11  
> **规范说明**：本 PRD 严格采用 **【问题描述】 $\rightarrow$ 【预期目标】 $\rightarrow$ 【功能详情（入口/配置/过程/结果/异常）】 $\rightarrow$ 【源码级技术实现】** 的深度结构化标准编写，覆盖当前系统的 6 大核心模块。

---

## 1. 真实多人房间单机演示 (D1/D4)

### 1.1 问题描述
用户或测试人员往往只有一台 iPhone，无法同时拉拢多位真实好友配合测试多人房间；若在正式云端建假房间，会污染 CloudKit 线上数据库、产生无法清理的垃圾数据；此前独立开发的测试页面（`RoomVideoDemoView`）控件堆叠、充满调试按钮，完全脱离真实用户进入房间的真实体验。

### 1.2 预期目标
在单台 iPhone 上无门槛、免登录复刻真实用户进入多人共享房间的完整体验。直接唤起正式房间时间线（`StoryTimelineView`），由本地内存沙盒注入 2~3 位虚拟成员的动态素材与对话，退出即物理销毁，绝不产生网络请求与数据污染。

### 1.3 功能详情
* **生成与进入入口**：
  * **位置**：首页 `PlansHomeView` 底部胶囊入口，或导航栏调试入口；
  * **标识**：`accessibilityIdentifier: "home-room-demo"`；
  * **环境门禁**：仅在 `DEBUG` 或命令行编译宏 `LOCAL_ROOM_CHAT_DEMO` 下显式展示；正式 Release 构建完全隐藏（编译期剔除）。
* **演示环境配置**：
  * **成员数量**：默认 3 人（成员 1、成员 2、成员 3）；
  * **素材规格**：各成员预置一段 3 秒的动态色阶视频（含递增进度百分比与动态横条）；
  * **时间线卡片**：预设 1 个主题瞬间（如 `MOMENT 1: 本地动态示例`），3 位成员均处于“已打卡”态；
  * **演示聊天**：预填一条来自系统的欢迎气泡。
* **过程与交互细节**：
  * 点击“房间演示”按钮，以整页模态（Sheet）弹出正式的 `StoryTimelineView`；
  * **顶部横幅**：常驻浅灰胶囊徽章，文案：`本地示例 · 不上传房间`（英文：`Local samples · Never uploaded`）；
  * **瞬间卡片点击**：点击已拍卡片，直接滑出多人合拍对比底板（`TimelineSheet.moment`），可横滑切换各成员原画；
  * **右上角聊天**：点击气泡按钮滑出 `RoomChatView`，输入文字点击发送，即刻在本地演示会话中追加显示，带发送成功状态；
  * **退出演示**：点击导航栏左侧或右上角“退出演示”（`Exit demo`），模态收起。
* **异常与清理行为**：
  * 退出房间瞬间，调度器调用底层沙盒清理例程，物理删除 `/tmp/1day-local-room-*/` 下的所有临时 MOV 文件与内存状态；
  * 若用户在演示过程中切到系统后台再返回，保持状态不黑屏、不白屏。
* **空态文案与提示**：
  * 顶部副标题：`本地示例 · 不上传房间`；
  * 无内容兜底：若素材生成被系统异常拦截，卡片展示浅灰占位符及文案：`素材加载失败，点击重试`。

### 1.4 源码级技术实现
* **入口视图**：`ios/AISetlog/Views/Plans/PlansHomeView.swift`，通过条件编译绑定 `.sheet(isPresented: $showRoomDemo)`。
* **核心页面复用**：`ios/AISetlog/Views/Timeline/StoryTimelineView.swift`。
* **沙盒隔离核心**：`ios/AISetlog/Services/Persistence/LocalRoomDemoStorage.swift`。
  * 遵循协议：`ChallengeRepository`, `ClipFileStore`, `TemplateCoverStore`；
  * 内部定义：`root = FileManager.default.temporaryDirectory.appendingPathComponent("1day-local-room-\(UUID().uuidString)")`；
  * 关键隔离方法：`loadChallenges()` 与 `saveChallenges()` 纯内存操作，不读写 `UserDefaults` 的 `challenges.v2`；
  * 退出物理销毁：`func close()` 执行 `try? FileManager.default.removeItem(at: root)`。
* **同步阻断**：初始化独立的 `ChallengeStore` 实例，并将 `roomSync` 绑定为非联网实例，拦截 `CloudKitService`。

---

## 2. 视频合成与无裁切合拍管线 (P3 / build20)

### 2.1 问题描述
以往多人合拍（`friendsTogether`）在固定竖画布中，直接将两个 9:16 竖屏素材居中硬切成扁平横条，导致用户拍摄的头部与下巴被强行裁掉（“切头切脸”）；此外，拍摄方向与最终成片方向规则混乱，经常产生方向倒转、两侧突兀大黑边等问题。

### 2.2 预期目标
确立全链路的**智能互补反转画幅原则**（竖拍默认合横版，横拍默认合竖版），彻底消灭硬切人脸的粗暴逻辑；在合拍中采用 **Aspect-Fit** 保持完整画幅，两侧/上下空余区域由素材自身的**高斯模糊（Gaussian Blur）沉浸式背景**自动铺满。

### 2.3 功能详情
* **默认画幅规则 (build20 规则)**：
  * **竖拍输入**：第一段有效素材经几何校正后高度大于宽度 $\rightarrow$ 默认输出 **16:9 横屏成片**；
  * **横拍输入**：第一段有效素材宽度大于高度 $\rightarrow$ 默认输出 **9:16 竖屏成片**；
  * **方形素材**：宽高相等 $\rightarrow$ 保持 1:1 输出；
  * **手动覆盖入口**：在成片导出与回看面板提供三档选择器：`[自动 (Auto), 竖版 (Portrait), 横版 (Landscape)]`，用户手动选定后拥有最高裁决权。
* **无裁切合拍布局 (方案 A 落地细节)**：
  * 针对 2 人同框合拍：
    * 画布划分为左/右（横版）或上/下（竖版）两个子网格（Cell）；
    * 成员原画在 Cell 内部按 `scale = min(cellWidth / sourceWidth, cellHeight / sourceHeight)` 居中等比缩放（Aspect-Fit）；
    * 背景层：原素材画面先按 `fillScale = max(cellWidth / sourceWidth, cellHeight / sourceHeight)` 撑满 Cell，再叠加 `CIGaussianBlur(radius: 25)` 进行高斯模糊打底；
    * 视觉效果：画面全屏沉浸，原画居中清晰，左右/上下是该视频同色系的动态微模糊衬底。
* **导出质量与参数规格**：
  * **编码格式**：H.264 / AAC 复合音频；
  * **横屏基准尺寸**：`960 × 540`（长边 960，短边 540 保证偶数）；
  * **竖屏基准尺寸**：`540 × 960`；
  * **帧率控制**：30 fps，音频混音按人数自动分流衰减：`volume = max(0.15, 0.8 / Float(clips.count))`。

### 2.4 源码级技术实现
* **合成核心类**：`ios/AISetlog/Services/Media/VideoStitcher.swift`。
* **智能画幅裁决**：
  ```swift
  // VideoStitcher.swift
  static func defaultForSource(_ size: CGSize) -> Aspect? {
      if size.height > size.width { return .landscape }
      if size.width > size.height { return .portrait }
      return nil
  }
  ```
* **几何变换与图层指令**：
  * 方法：`buildFriendsTogether(loaded:into:renderSize:startAt:instructions:audioParams:captions:)`；
  * 尺寸判断基准：通过 `LoadedClip.orientedSize` 计算几何旋转后的可视矩形：
    ```swift
    var orientedSize: CGSize {
        let r = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return CGSize(width: abs(r.width), height: abs(r.height))
    }
    ```
  * 双层指令：使用 `AVMutableVideoCompositionLayerInstruction` 分别对模糊底图 Track 与原画 Track 进行 `setTransform` 与 `setCropRectangle`。

---

## 3. 苹果官方 CIFilter 三参数滤镜 (P1)

### 3.1 问题描述
旧版 1day 仅内置了 3 个固定的写死 LUT 调色板（`GentleLook` 预设），无法满足用户个性化微调需求；市面上部分相机 App 采用录制底层硬件参数（如白平衡偏置），导致录完无法事后调整，朋友传来的视频也无法应用，且第三方私有滤镜极易导致导出色差与原片损坏。

### 3.2 预期目标
移除写死的 3 套预设，改用 **Apple 官方原生 CoreImage (`CIFilter`) 标准后处理管线**。提供曝光、色温、对比度 3 个 `-50 ~ +50` 的物理回中微调滚轮；仅作用于本人拍摄素材，绝不损坏只读原片，回看与导出保持 100% 像素一致。

### 3.3 功能详情
* **调节入口**：
  * **位置**：拍摄完成后的单片预览确认页（`ClipPreviewView`）底部工具栏；
  * **触发**：点击“画面微调”图标，自底向上呼出调节托盘。
* **三个参数滚轮定义**：
  1. **曝光 (Exposure)**：
     * 范围：`-50 ~ +50`（步长 1，默认居中 `0`）；
     * 作用：增加或降低画面进光通透感。
  2. **色温 (Temperature)**：
     * 范围：`-50 ~ +50`（步长 1，默认居中 `0`）；
     * 作用：负值为冷蓝调，正值为暖橙调。
  3. **对比度 (Contrast)**：
     * 范围：`-50 ~ +50`（步长 1，默认居中 `0`）；
     * 作用：微调亮暗部反差与灰度。
* **交互细节**：
  * 滚轮支持连续滑动与惯性滚动，滑动时上方视频画面以 60fps 实时响应；
  * 双击任意滚轮数值标签，立即平滑动画回弹至 `0`；
  * 右侧提供显式的“重置全部”（`Reset all`）文字按钮；
  * **主权独立**：调色仅记录在当前卡片元数据中，不影响房间内其他成员的素材。
* **性能优化**：
  * 当三个参数均为 `0` 时，渲染引擎判定为 `isIdentity`，直接 Bypass 跳过 GPU 滤镜节点，零额外渲染功耗。

### 3.4 源码级技术实现
* **参数存储模型**：`ios/AISetlog/Models/DayClip.swift` 中的 `PersonalEffectRecipe`：
  ```swift
  struct PersonalEffectRecipe: Codable, Equatable {
      var exposure: Float = 0.0    // -50 ~ +50
      var temperature: Float = 0.0 // -50 ~ +50
      var contrast: Float = 0.0    // -50 ~ +50
      var isIdentity: Bool { exposure == 0 && temperature == 0 && contrast == 0 }
  }
  ```
* **CoreImage 映射引擎**：`ios/AISetlog/Services/Media/GentleLookFilter.swift`：
  * 曝光映射：`CIExposureAdjust`，参数 `kCIInputEVKey = exposure * 0.03`（映射范围 -1.5 ~ +1.5 EV）；
  * 色温映射：`CITemperatureAndTint`，参数 `inputTargetNeutral = CIVector(x: 6500 + temperature * 40, y: 0)`；
  * 对比度映射：`CIColorControls`，参数 `kCIInputContrastKey = 1.0 + contrast * 0.008`（映射范围 0.6 ~ 1.4）；
* **合成导出一致性**：`VideoStitcher.filteredClips` 读取此配方构建 `AVVideoComposition`，确保导出渲染与预览使用的是完全相同的 CIFilter 链条。

---

## 4. 房间级统一聊天与可靠投递 (C1/C2/C5)

### 4.1 问题描述
旧版 1day 存在致命缺陷：评论按“目标作者（`targetAuthorID`）”进行过滤拉取，导致同一个房间内的不同成员只能看到关于自己的碎片留言，无法形成真正的多人房间沟通；且网络不佳时容易吞消息、无离线队列，甚至已删除的消息在下拉全量刷新后死灰复燃。

### 4.2 预期目标
构建房间级单一消息流（All-in-one Conversation）。全房间成员共享同一条聊天脉络，未拍摄成员亦可自由发言；具备完善的本地 Outbox 离线排队、UUID 幂等去重、作者专属撤回以及基于 Tombstone 的持久防复活机制。

### 4.3 功能详情
* **入口与布局**：
  * **位置**：房间时间线右上方聊天气泡按钮（带未读小圆点）；
  * **展现形式**：半屏/全屏弹性抽屉（`RoomChatView`）；
  * **气泡结构**：
    * 他人消息：靠左，头像 + 昵称 + 气泡 + 时间戳；
    * 本人消息：靠右，气泡 + 时间戳 + 投递状态（发送中旋转 / 失败红感叹号）；
    * 瞬间引用卡片：若某条消息关联了特定瞬间，气泡上方内嵌小横幅，显示该瞬间题目与微缩图标，点击可锚定跳转。
* **发送流程与字符限制**：
  * 输入框右侧常驻发送按钮；字符上限硬性限制为 **2000 UTF-8 字符**；
  * 点击发送后，键盘不收起，输入框内容清空，消息立即以浅灰“发送中”气泡出现在列表底部；
  * 后台写入本地 Outbox 队列并向云端派发，云端确认回执后气泡转为正常色。
* **离线与弱网重试**：
  * 断网时消息右侧显示黄色感叹号及文案：`未发送，点击重试`；
  * 点击感叹号可原地重新触发投递；应用冷重启后，未发送队列完整从磁盘恢复，绝不丢稿。
* **撤回与删除机制**：
  * 用户长按自己发送的消息气泡，震动弹出“撤回 / 删除”菜单；他人消息无此项；
  * 确认删除后，气泡渐隐消失，本地维护强持久化的 `deletedIDs`（Tombstones）；
  * 对端下一次下拉同步时，检测到该 UUID 被删除，对应气泡自动移除。
* **空态文案**：
  * 标题：`还没有消息`；
  * 正文：`在房间里说点什么，或者对某个瞬间发表想法。`

### 4.4 源码级技术实现
* **状态与模型**：`ios/AISetlog/Models/RoomChatState.swift`。
  * 消息定义：
    ```swift
    struct RoomChatMessage: Codable, Equatable, Identifiable {
        let id: UUID
        let roomCode: String
        let authorID: String
        let authorName: String
        let text: String
        let moment: Int?
        let createdAt: Date
        var deliveryStatus: RoomChatDeliveryStatus
    }
    ```
* **会话中枢**：`ios/AISetlog/Services/RoomChatSession.swift`。
  * 维护持久状态：`RoomChatState`，包含 `messages: [RoomChatMessage]`, `outbox: [RoomChatMessage]`, `deletedIDs: Set<UUID>`；
  * 存储路径：`Application Support/RoomChat/<scope>/state.json`；
* **防复活合并逻辑**：
  ```swift
  // RoomChatState.swift
  mutating func mergeRemote(incoming: [RoomChatMessage]) {
      let filtered = incoming.filter { !deletedIDs.contains($0.id) }
      // 依靠唯一 UUID 进行集合去重与时间排序，严防历史快照复活已删消息
  }
  ```
* **账号租约隔离**：`AccountStore.identityRevision`，切号或登出时租约递增，旧会话的迟到异步回调全部判定失效，禁止写穿。

---

## 5. 意图置顶 AI 故事创建器 (A1)

### 5.1 问题描述
用户在创建故事时常常面临空白画布的心理压力，必须先绞尽脑汁想出一个完美的标题才能开始添加瞬间；且此前的 AI 服务端与客户端直接绑定了写死的 prompts 字段，服务端若想返回可选的标题建议会导致旧版客户端 JSON 解码崩溃。

### 5.2 预期目标
实现“输入意图优先”的低门槛创建模式。用户只写一句话想法，AI 即同步启发故事标题与 3~7 个灵感瞬间；客户端与 Worker 架构双向解耦，支持可选 `title` 字段，服务端超时或错误时优雅降级，保障手动流程完全畅通。

### 5.3 功能详情
* **入口位置**：创建故事首页（`StoryComposerView`）顶部置顶展示。
* **意图输入框**：
  * 大尺寸圆角输入区，Placeholder 文案：`今天想记录什么？（例如：和朋友的周末野餐）`；
  * 限制单次输入最多 200 字符；输入框右下方提供魔棒按钮“AI 灵感”。
* **生成与回填过程**：
  * 点击魔棒，输入框右侧进入 Loading 状态，下方生成按钮置灰；
  * 请求超时阈值设为 **20 秒**；
  * 请求成功后：
    * 标题输入框自动填入 AI 生成的凝练标题（如：`森林里的野餐日`）；
    * 下方列表自动生成并展开 3~7 个卡片（如：`1. 挑选水果`、`2. 铺开野餐垫`、`3. 举杯笑脸`）；
    * 所有回填内容均处于可编辑状态，用户可直接点击光标修改文字或删除多余瞬间。
* **异常与重试逻辑**：
  * 若因断网、超时或服务端限流报错：
    * 弹出非阻断式提示：`AI 暂时无法响应，请直接手动编辑`；
    * 用户已键入的原意图文字毫发无损地保留在框内；
    * 自动为用户垫入 3 个通用的空白瞬间卡片，不卡死流程。
* **安全与数据保护**：
  * 若用户在点击 AI 之前已经手动修改过标题或部分卡片，再次点击 AI 时弹出确认提示：`重新生成将覆盖已编辑的内容，是否继续？`，避免用户劳动成果被覆盖。

### 5.4 源码级技术实现
* **客户端服务**：`ios/AISetlog/Services/PromptSuggestionService.swift`。
* **双向容错契约模型**：
  ```swift
  // PromptSuggestionService.swift
  struct Request: Codable {
      let intent: String
      let count: Int
      let language: String
      let device: String
  }
  struct Response: Codable {
      let prompts: [String]
      let title: String? // 重点：可选解码，完美兼容返回旧格式与新格式
  }
  ```
* **服务端逻辑**：`workers/suggest-prompts/src/index.js`，运行在 Cloudflare Workers 上，持有服务端专用 API 秘钥，客户端无鉴权泄露风险。

---

## 6. 账号安全注销与数据清理状态机 (C3)

### 6.1 问题描述
原版 `ChallengeStore.deleteAccountAndAllData()` 存在严重安全隐患：遇到网络失败直接吞异常报错，本地只粗暴清空了部分缓存，未能物理抹除 CloudKit 云端的媒体文件与聊天记录；在途未完成的网络请求会在注销后突然成功写入，留下不可控的孤儿数据。

### 6.2 预期目标
构建严格可恢复、具备事务日志（Journal）的五阶段账号注销状态机。彻底阻断新操作，排干在途请求，分批擦除云端及本地全部私有数据，严禁假成功与吞错。

### 6.3 功能详情
* **操作入口**：设置页（`SettingsView`）底部危险区域，红色文字：`注销账号并删除所有数据`。
* **二次安全确认**：
  * 点击弹出系统标准 ActionSheet 警告框：
    * 标题：`确定要注销账号吗？`；
    * 正文：`该操作不可逆。你在所有共享房间内上传的视频、照片、聊天记录及本地历史都将被彻底抹除。`；
    * 按钮：红色 `注销并抹除` / 灰色 `取消`。
* **注销执行状态流 (Progress Flow)**：
  * 点击确认后，界面转入全屏高阻断 Loading 遮罩，禁止用户点击返回；
  * 状态机按顺序流转：
    1. **Freeze（写保护）**：禁用拍摄、本地持久化与消息发送；
    2. **Drain（排干）**：等待队列中正在上传的 MOV/Comment 请求终止（最长等待 8 秒）；
    3. **Remote Delete（云端分批清理）**：调用 CloudKit 分页查询本人名下的所有 Record，按批次（每次最多 50 条）物理删除；
    4. **Local Wipe（本地抹除）**：彻底递归删除 Documents/clips、templateCovers、RoomChat 等整个应用数据目录；
    5. **Revoke（凭证吊销）**：清除 Keychain 身份，`identityRevision` 自增，跳回初遇引导页。
* **异常处理与恢复断点**：
  * 若云端删除遇到网络错误（如 Error -1009 断网）：
    * 界面停留在失败态，提示：`网络连接失败，数据清理未全部完成。请检查网络后重试。`；
    * 底部提供 `继续重试清理` 按钮；
    * **绝不**退回未清理前的正常主页，**绝不**向用户谎报注销完毕。

### 6.4 源码级技术实现
* **协调器设计**：`ios/AISetlog/Services/ChallengeStore.swift` 结合夜间新增的 `AccountDeletionCoordinator.swift`。
* **本地注销日志 (Journaling)**：在沙盒根目录写入 `deletion_journal.json`，记录 `[stage, pendingRemoteRecords, attempts]`。
* **防串号写穿防护**：
  ```swift
  // AccountStore.swift
  func signOut() {
      Self.identityRevision &+= 1 // 租约失效
      account = nil
      UserDefaults.standard.removeObject(forKey: Self.key)
  }
  ```
  在每个在途网络请求完成回调前，强制比对当前 `identityRevision == capturedRevision`，一旦租约已变，立即将结果抛弃，绝不写入。

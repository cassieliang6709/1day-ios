# 相机：拍、回看、字幕、发出去

底部 tab「相机」。点一下快门拍 2 秒，回看，加字幕或贴纸，再发到房间或保留到「我的」。

## 子功能

- 拍摄：快门 `camera-shutter`（「点一下，拍 2 秒」），闪光灯 `camera-flash`，关闭 `camera-close`。
- 横拍：`camera-sideways-toggle`（「横拍」）切换，横拍状态的提示 `camera-sideways`。
- 回看：`capture-review-frame`，`moment-stage` 是画面区域，`moment-close` 关闭，`moment-more` 更多，`moment-chat` 聊天。画面下方一排按钮：`moment-caption`（加字幕）、`moment-rerecord`（重拍）、`moment-add-take`（再拍一段）。
- 字幕和贴纸：
  - `caption-text`：输入文字，`caption-done` 完成
  - `caption-tints`：颜色，`caption-plates`：底板样式
  - `caption-sticker`：贴纸，`caption-handle`：拖动改大小
  - `caption-undo` 撤销，`caption-delete` 删除，`caption-gesture-hint` 是第一次的手势提示
- 发出去：`send-room-row` 选房间发送。
- 草稿：没发的片段可以「保留」到「我的」，只有自己看得到。草稿入口 `drafts-entry`（「N 段只有我看得到」）和「我的」里的 `drafts-row`。

## 用户怎么找到它

点底部 tab「相机」。房间里格子上的「拍一段」`room-feed-film` 和时刻条上的「开拍」`diary-film-<n>` 也进相机，拍完默认发到那个房间。

## 怎么操作

- 直接进相机：`scripts/agent/open-link.sh surface/camera`。
- 模拟器没有摄像头：启动参数加 `-simulatedCamera YES`，按快门会出一段示例片段。不加的话会显示「相机不可用」和一个「示例片段」按钮，UI 测试用的是这个。
- 拍完卡顿：`scripts/agent/trace.sh --device --url oneday://debug/surface/camera`。

## 验证

| 编号 | 功能 | 入口 | 怎么走 | 屏幕上算成功 | 服务器证据 | 要真人 | 对外写 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F9 | 拍一段 | 底部 tab「相机」→ `camera-shutter` | 点一下快门，等 2 秒（旧表写的是「按住」，按钮文案是「点一下，拍 2 秒」） | 出现回看画面 `capture-review-frame` | — | 否 | 否 |
| F10 | 发到房间 | 回看页 → `send-room-row` | 选测试房间 → 发送 | 房间里出现这段，作者是自己 | `recent 5`：一条 `clip` 行，`who` 是本人 | 否 | 是 |
| F11 | 改字幕 | `caption-text` → `caption-done` | 改一个已发出的片段的字幕 | 房间里字幕更新 | `sql`：那条 clip 的 `overlay_text` 变了 | 否 | 是 |
| F23 | 保留到草稿 | 拍完不发 → 切到房间 tab → 选「保留」 | 拍一段，不发，切 tab | `drafts-entry` 出现，数字多 1 | — | 否 | 否 |

## 容易出错的地方

- **前置相机只有 1x 和 2x。** 1x 就是整个传感器，没有 0.5x，不要找。
- **方向只看横拍按钮。** 拍出来是横是竖由 `camera-sideways-toggle` 决定，不看手机怎么拿。
- 前置拍出来的成片不镜像。
- 拍完没发就点别的 tab，会弹「保留 / 丢弃」。丢弃之后片段找不回来；验证时选保留。
- 相机只在当前页面是相机时才挂载，离开就停掉，所以切回来要重新等预览出来。
- 真机拍摄要相机和麦克风权限，第一次会弹系统窗口。

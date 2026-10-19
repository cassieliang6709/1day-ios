# CloudKit：给 `Clip` 加 `captionsJSON` 字段

一段片段现在可以有好几条字幕。房间里的 `Clip` 记录要多存一个字段 `captionsJSON`，里面是这一段所有字幕（文字、位置、大小、角度、颜色、底色）的 JSON。代码已经写好，但 Production 里还没有这个字段，Production 会拒绝写它。

## 部署前会怎样

Debug 和 Release 默认都连 Production（`ios/project.yml` 里的 `CLOUDKIT_ENVIRONMENT`），所以部署前：

- 上传片段照常成功。片段和第 1 条字幕（老字段 `overlayText`）先存一次；`captionsJSON` 是之后单独再存一次，这一次会失败，只在控制台打一行 `[room] captionsJSON save failed (field not deployed?): ...`，不影响片段本身。
- 朋友那边只看到第 1 条字幕（和 1.5 (31) 一样）。
- 自己的手机上不受影响：自己的片段在房间里显示的是本机存的全部字幕。
- 成片导出用的是同样的数据：自己的片段烧全部字幕，朋友的片段在部署前只烧第 1 条。

部署后不用发新版，下次上传或改字幕就会写成功。

## 新旧版本怎么共存

| 谁写 | `overlayText` | `captionsJSON` |
| --- | --- | --- |
| 新版 | 第 1 条字幕的文字 | 全部字幕 |
| 1.5 (31) 及更早 | 唯一那条字幕 | 不认识，不动它 |

读的时候：有 `captionsJSON` 而且它的第 1 条文字和 `overlayText` 一样，就用 `captionsJSON`；否则只用 `overlayText`。这样 1.5 (31) 重拍或改了字幕之后（它只改 `overlayText`，会留下旧的 `captionsJSON`），新版显示的是刚改的字，不是旧的那组。

代码位置：`CloudKitService.uploadClip` / `updateClipCaption` / `saveCaptionsJSON`（`ios/AISetlog/Services/Cloud/CloudKitService.swift`），读的规则在 `Caption.fromCloud`（`ios/AISetlog/Models/Caption.swift`）。

## 字段

| 项 | 值 |
| --- | --- |
| 记录类型 | `Clip`（已经有了） |
| 新字段 | `captionsJSON` |
| 类型 | String |
| 索引 | 不需要（不按它查询） |

## 第 1 步：在 CloudKit Console 的 Development 里加字段

打开 <https://icloud.developer.apple.com/dashboard>，选容器 `iCloud.com.cassie.AISetlog`，环境选 **Development**。

1. 左边 **Schema → Record Types**，点开 `Clip`。
2. 点 **+ Add Field**（或字段列表下面的 **+**），名字填 `captionsJSON`，类型选 **String**。
3. 点 **Save Changes**。

也可以让 App 自己在 Development 里建出这个字段：临时把 `ios/project.yml` 里 Debug 的 `CLOUDKIT_ENVIRONMENT: Production` 改成 `Development`，`xcodegen generate --spec ios/project.yml --project ios`，装 Debug 版，在一个 Development 的房间里拍一段、加两条字幕，看到控制台没有 `captionsJSON save failed` 就说明字段建好了。**测完马上改回 Production 再生成一次**，`git diff ios/project.yml` 确认没改动，这个改动不能提交。

## 第 2 步：部署到 Production

1. Console 左下角点 **Deploy Schema Changes...**。
2. 在对比里确认只有一项新增：`Clip` 的 `captionsJSON`（String）。**如果出现别的改动，先停下来**，弄清楚是谁加的再部署。（如果 `Member` 记录类型那次还没部署，它也会出现在这里，见 `docs/cloudkit-member-deploy.md`，两样一起部署没问题。）
3. 点 **Deploy**。
4. 环境切到 **Production**，在 **Schema → Record Types → Clip** 里确认能看到 `captionsJSON`。

## 部署后怎么确认

1. 用正常的 Debug 版（连 Production）在真机上，进一个房间，点自己的一段，加两条字幕。
2. Xcode 控制台没有 `captionsJSON save failed`。
3. Console 切到 Production → **Data → Records** → `Clip`，按 `roomCode` 查到这一段，`captionsJSON` 里能看到两条字幕，`overlayText` 是第 1 条的文字。
4. 另一台装新版的手机进同一个房间，那一段能看到两条字幕；装 1.5 (31) 的手机看到第 1 条。

## 相关测试

- `ios/AISetlogTests/CaptionListTests.swift`：旧的本机数据（卡片、多拍的那几段、草稿）解码成 1 条；保存时还会写回老字段；`captionsJSON` 和 `overlayText` 对不上时用 `overlayText`；没有新字段、新字段坏了都退回 `overlayText`。
- `ios/AISetlogTests/RoomUploadRetryTests.swift`：补传带上全部字幕；改字幕会把整组推到房间；房间里只有 1 条时，自己的片段显示本机的全部字幕。

这些测试都不连 CloudKit。

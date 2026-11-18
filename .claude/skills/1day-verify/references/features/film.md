# 房间 vlog：生成、调整、配乐、保存

把一个房间里所有人的片段拼成一条 vlog。生成后可以筛人、筛片段、排顺序、换配乐、加旁白，然后保存到相册或分享。

「我的」里自己挑片段出 vlog 是另一个入口，见 [personal.md](personal.md)。生成之后的页面是同一个。

## 子功能

- 生成：房间「更多」菜单 → 「生成 vlog」`room-make-vlog`。生成中显示进度，完成后进成片页。
- 成片页三个按钮：`film-save`（保存，保存中会显示「保存中」，完成后显示「已保存」）、`film-share`（分享）、`film-adjust`（调整）。没有相册权限时出 `film-open-settings`（打开系统设置）。
- 筛选 `film-filter`：
  - 按人：`film-filter-person-<n>`、`film-person-<n>`，整个人包含 `film-person-include` 或全部定格 `film-person-hold-all`
  - 按片段：`film-clip-include-<n>` 放不放进成片，`film-clip-hold-<n>` 定格，`film-clip-hold-frame-<n>` 选定格在哪一帧
  - `film-filter-toggle-<n>`，确认 `film-filter-apply`（「应用」）
- 排顺序 `film-order`：每行 `film-order-row`，拖动排序。
- 声音：`film-sound-mode` 在原声、音乐、混合之间切换，`film-sound-next` 换下一首。
- 旁白：`film-voiceover`（加旁白 / 重录 / 去掉），`voiceover-start` 开始录。

## 用户怎么找到它

进房间 → 右上角「更多」→「生成 vlog」。「更多」菜单里还有「预览成片」。

## 怎么操作

- 「更多」是 SwiftUI `Menu`，菜单项用 `phone_tap_label` 按文字点「生成 vlog」。
- 生成卡住：`scripts/agent/app-logs.sh --seconds 60` 看拼接有没有报错，`scripts/agent/trace.sh --device --template Allocations` 看内存。

## 验证

| 编号 | 功能 | 入口 | 怎么走 | 屏幕上算成功 | 服务器证据 | 要真人 | 对外写 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F24 | 生成房间 vlog | `room-more` →「生成 vlog」 | 在有 2 段以上片段的测试房间里生成 → 换一次配乐 → 保存 | 进度结束后能播放；`film-sound-next` 后曲名变了；`film-save` 显示已保存，相册里多一条视频 | — | 否 | 否（`film-share` 不点） |

## 容易出错的地方

- 生成不会一直转圈不结束：每次生成要么出成片，要么显示失败原因。看到一直转圈就是 bug，抓日志。
- 生成过程中改了筛选或顺序，旧的那次生成会被丢掉，屏幕只显示最新那次。
- 保存到相册第一次会弹相册权限。

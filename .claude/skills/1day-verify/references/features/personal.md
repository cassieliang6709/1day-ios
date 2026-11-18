# 「我的」

只有自己看得到的页面：日期条、今天的计划、所有拍过的片段、心情。可以从全部片段里挑几段出一条 vlog。

## 子功能

- 日期条：`day-strip`，每一天 `day-strip-day`。选过去某天显示那天的回顾 `day-recap`（几段片段）和那天的心情 `mood-day-card`；选未来某天显示「提前写计划」`day-plan-ahead`。
- 今天的计划：`today-plan-card`，每一项 `today-plan-item`（拍过的打勾），`today-plan-open` 打开。
- 草稿：`drafts-row`，只有自己看得到的、还没发出去的片段。
- 全部片段和选片出 vlog：
  - `library-select`（「选择」）进入多选，`library-selected-summary` 显示选了几段
  - `library-make-vlog`（「生成 vlog」）进入排序页
  - 排序页每段 `vlog-arrange-row-<n>`，可拖动、可预览，`vlog-arrange-make` 开始生成
  - 生成之后的页面和房间 vlog 一样，见 [film.md](film.md)
- 心情：`mood-today-card`（今天的心情），选一个 `mood-<kind>`，选完显示 `mood-today-selected`（「点一下改心情」）。可以写一句 `mood-note`，或者按 `mood-mic` 用语音输入。
- 引导卡片：`home-guide`，显示在心情卡片附近。

## 用户怎么找到它

房间页上点「我的」`rooms-personal`。点 `personal-back`（「房间」）回去。

## 怎么操作

- 直接进：`scripts/agent/open-link.sh surface/plans`。
- 片段太少没法测选片：`scripts/agent/open-link.sh seed-library` 塞示例片段。

## 验证

| 编号 | 功能 | 入口 | 怎么走 | 屏幕上算成功 | 服务器证据 | 要真人 | 对外写 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F16 | 「我的」页面 | `rooms-personal` | 点「我的」 | 问候、日期条、心情、所有片段都出现 | — | 否 | 否 |
| F17 | 记心情 | `mood-today-card` → `mood-<kind>` | 选一个心情 | 选中状态出现 | `recent 5`：一条 `mood` 行（只看 `day`，不读内容） | 否 | 否（只有本人可见） |
| F25 | 选片出 vlog | `library-select` → `library-make-vlog` → `vlog-arrange-make` | 选 3 段 → 拖动换一下顺序 → 生成 | 成片按排序页的顺序播放 | — | 否 | 否 |

## 容易出错的地方

- 心情的内容是隐私：验证 F17 只看 `day` 字段，不读心情内容。
- 选片 vlog 没有竖拍横拍选择，成片的形状由选的片段决定。
- `seed-library` 只在 Debug 构建里有。塞进去的示例片段和真片段混在一起，验证完不要拿它们发到房间。

# 新建：房间和计划

全屏的新建流程。可以建一个和朋友一起拍的房间，也可以给自己写今天或这 7 天要拍什么。

## 子功能

- 起点：`composer-question`（今天的计划 / 新建房间），`composer-start`（「创建房间」或「拍出今天的一天」）。
- 竖拍还是横拍房间：`room-shape-portrait` / `room-shape-landscape`。
- 几天：`plan-one-day`（一日计划）、`plan-seven-day`（7 日计划）。
- 拍什么：`write-own-entry`（写今天的清单）或 `by-time-entry`（不写，按时间拍）。
- 清单编辑：
  - `today-intent`：今天想做什么的一句话
  - `custom-prompt-<n>`：第 n 项
  - `list-add-row`：加一项
  - `suggest-prompts`：AI 建议，失败时点 `suggest-retry`
  - `list-from-reminders`：从提醒事项导入，进去后勾 `reminder-row`，点 `reminders-add`
  - `use-these-moments`：确认用这些项
  - `composer-list-summary`：已选几项的汇总

## 用户怎么找到它

房间页或「我的」底部中间的圆按钮（accessibility 名字「新建」，identifier `home-compose`）。房间页的「新建房间」`friends-new-room` 也进这里，会预选和朋友一起拍。「我的」日期条选未来某天时，点「提前写计划」`day-plan-ahead`。

## 怎么操作

- 直接进新建：`scripts/agent/open-link.sh surface/compose`。
- AI 建议走 `workers/suggest-prompts`，失败时看 `scripts/agent/app-logs.sh --category api`。

## 验证

| 编号 | 功能 | 入口 | 怎么走 | 屏幕上算成功 | 服务器证据 | 要真人 | 对外写 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F5 | 新建房间 | `friends-new-room` | 新建 → 起名「测试 + 时间」 | 新卡片出现在列表第一个 | `room <CODE>`：`room=1` | 否 | 是（新房间，只有自己） |
| F21 | 写清单建计划 | `home-compose` → `write-own-entry` | 加两项 → `use-these-moments` → `composer-start` | 打开新计划的时间线，两项都在 | — | 否 | 否 |

## 容易出错的地方

- 新建页不保留填了一半的内容：中途切到别的页面再回来，是一张新表单。
- 从提醒事项导入会弹系统权限，只弹一次。
- 竖拍还是横拍在建房间时选。相机拍出来的方向只看相机里的横拍按钮，不看手机怎么拿，见 [camera.md](camera.md)。

# 1Day 功能地图

App 里所有能用的功能、每个功能做什么、用户从哪里找到它。要找一个功能，先在这页搜关键词，再点进对应文件。

## App 的骨架

底部浮动 tab 栏只有两个：**相机**（`tab-camera`）和**房间**（`tab-rooms`）。

- 「我的」不是 tab：在房间页点 `rooms-personal` 进去，点 `personal-back` 回来。
- 「新建」是全屏页面：在房间页或「我的」点 `home-compose`。
- 设置是 sheet：在房间页**点左上角自己的头像**。它没有 identifier，按 accessibility label「设置」找。

## 功能索引

| 文件 | 功能 | 关键词 | 验证编号 |
| --- | --- | --- | --- |
| [launch-and-sign-in.md](launch-and-sign-in.md) | 冷启动、首次引导、权限说明、Apple / Google 登录 | 启动、登录、引导、权限 | F1–F3 |
| [rooms.md](rooms.md) | 房间列表、加入、邀请、退出 | 邀请码、加入、邀请朋友、退出房间 | F4、F6、F8、F20 |
| [compose.md](compose.md) | 新建房间或计划：一日 / 7 日计划、清单、提醒导入、AI 建议、竖拍横拍房间 | 新建、计划、清单、提醒事项、建议 | F5、F21 |
| [room-page.md](room-page.md) | 房间里面：一人一格、片段流、日历、视图切换、单人页、改房间名、更多菜单 | 房间页、格子、日历、视图、改名 | F7、F22 |
| [camera.md](camera.md) | 拍摄、横拍、闪光灯、回看、字幕和贴纸、发到房间、保留到草稿 | 相机、快门、字幕、草稿、横拍 | F9–F11、F23 |
| [chat-and-reactions.md](chat-and-reactions.md) | 聊天、表情回应、拍一拍、推送 | 聊天、回应、表情、拍一拍、通知 | F12–F15 |
| [film.md](film.md) | 房间 vlog：生成、筛选、排顺序、配乐、旁白、保存、分享 | vlog、成片、配乐、旁白、筛选 | F24 |
| [personal.md](personal.md) | 「我的」：日期条、今天的计划、全部视频、选片出 vlog、心情 | 我的、日历、心情、选片、生成 vlog | F16、F17、F25 |
| [settings-and-avatar.md](settings-and-avatar.md) | 头像设置流程、改名字、登录状态、退出登录、测试房间 | 设置、头像、Memoji、名字、退出登录 | F18、F19、F26 |
| [driving.md](driving.md) | 不点屏幕也能到达某个页面或状态的工具：调试深链、启动参数、日志、lldb、性能追踪、Worker 日志 | 深链、启动参数、日志、断点、trace | — |

## 每个功能文件的结构

1. **子功能**：这个功能下面分哪几块，各自的 identifier。
2. **用户怎么找到它**：从打开 App 开始，用户要点哪里。
3. **怎么操作**：agent 用的命令或 `phone_run_steps` 要点。通用工具的用法在 [driving.md](driving.md)。
4. **验证**：编号、算成功的标准、服务器证据、要不要真人、会不会对外写。
5. **容易出错的地方**。

## 验证表的列

- **入口**：accessibility identifier，用 `phone_elements` 的 `query` 找。带 `<...>` 的是一组，比如 `mood-<kind>`。
- **服务器证据**：用 `scripts/d1_read.py` 查。
- **要真人**：是，就要用户本人操作（Face ID、密码、第二个账号）。
- **对外写**：是，就会在真实房间里留下朋友看得到的东西。只在自己的测试房间里做，或者先问用户。

F1–F19 是原来的清单。F20 以后是这次新加的，还没在真机上完整走过一遍。第一次用时按实际界面修正，并删掉这句。

## 维护

- App 加了功能、改了入口或 identifier，在同一次改动里更新对应文件。
- 查漏：下面这条命令列出代码里所有 identifier，跟这里对一遍。

```bash
grep -rhoE 'accessibilityIdentifier\("[^"]+' ios/AISetlog | sed 's/.*("//' | sort -u
```

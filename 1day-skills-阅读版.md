# 1Day 项目 skills 阅读版（2026-11-16 整理）

源文件在 `~/Developer/01_Career_Portfolio/1day/.claude/skills/`。下面先是现状和这次的改动，后面是全文（改动后的版本）。

## 现状

| Skill | 作用 | 状态 |
| --- | --- | --- |
| 1day-mode | 入口：判断任务类型，选 P1–P5 步骤 | 完整 |
| 1day-verify | 真机逐项验证 + 查 D1 | 完整；F20–F26 还没在真机走过 |
| 1day-design-system | 维护 DESIGN.md，统一组件 | 完整；lint 测试 3/3 通过 |
| run-1day | 编译、装真机、截图 | 完整；本次改成中文并拆分 |

和 pstack 的关系：`1day-mode` 照 `poteto-mode` 的结构写（入口 skill + playbooks），把 pstack 的 6 条 principle 改写成中文一句话规则：prove-it-works → 先证明能用，fix-root-causes → 修根因，subtract-before-you-add → 先减再加，experience-first → 从手机体验倒推，migrate-callers-then-delete → 先迁移调用方再删旧的，never-block-on-the-human → 不卡在用户身上。P1/P2 对应 pstack 的 feature / bug-fix，P3–P5 是 1Day 自己的。

## 这次改了什么（都没提交）

1. `.gitignore` 第 2 行 `.claude/` 改成 `.claude/*` + `!.claude/skills/`。现在 git 能看到 19 个 skill 文件；worktrees、settings.local.json、launch.json 仍然忽略。
2. `run-1day/SKILL.md` 改成中文，只留真机流程（327 → 162 行）；模拟器流程挪到新文件 `run-1day/references/simulator.md`（93 行）。原文里所有命令、UDID、路径、commit 号都核对过，没丢。原版备份在 `/tmp/run-1day-SKILL.backup.md`。
3. `1day-mode/references/playbooks.md` P1 第 1 步补了一句：新加数据结构或跨函数边界的改动，先用 how 看现有结构，再用 architect 比较 2～3 个做法。步骤编号没变。

## 没改的，和原因

1. **design lint 比基线差**（AvatarSetupFlow.swift、MomentFilmstrip.swift、Plans/New.swift）：这些文件都在工作区里没提交，是正在进行的头像改动。不是 skill 的问题，按规则不碰别人未提交的改动。做完那批改动时按 P1 第 7 步处理。
2. **F20–F26 没在真机验证**：要连着 iPhone 实际操作，部分会在真实房间留痕迹，需要你在场。README 里那句提醒保留。
3. **没加 PR / 发布流程**：你的全局规则不让 agent 自己提交和推送，所以不加。

---


---

# 全文：`1day-mode/SKILL.md`

---
name: 1day-mode
description: 1Day 项目（iOS App 加 Cloudflare Worker 后端）里稍大开发任务的入口：先判断是哪种任务，再按这种任务的固定步骤开任务清单，一步步做到在真机上验证完。用户在 1Day 里要改界面或逻辑、修 bug、改 Worker 后端、统一组件、打 TestFlight，或说「继续开发」「做这个功能」时使用。不用于：只问问题或解释代码（直接回答）；一两行的文案或数字改动（直接改，只编译）；只想装上看看（用 run-1day）；只做验证（用 1day-verify）；只定设计规范（用 1day-design-system）。
---

# 1day-mode

1Day 的开发任务都从这里进。它不替代其他 Skill，只决定这次做什么、按什么顺序、用哪个 Skill、什么时候停。

## 第 1 步：复述目标

用一句话说出这次要达成什么，以及做完后用户在手机上能看到什么变化。

用户的话有两种合理理解、而且会做出不同的东西时，问一个问题，给 2～3 个猜测让用户选。只有一种合理理解时直接做。

## 第 2 步：看现场

1. 跑 `git status --short`，记下开始前就有的改动。那些不是本次的改动，不覆盖、不回滚。
2. 跑 `ps aux | grep -c "[c]laude --dangerously-skip-permissions"`。不是 0 时，可能有别的 Agent 在同一个目录写代码：停下告诉用户。
3. 用户的全局规则（改代码的边界、不碰 git 历史、大改先问）优先于本 Skill。

## 第 3 步：选任务类型

| 任务 | 步骤 |
| --- | --- |
| 改界面、改逻辑、加功能 | P1 |
| 修 bug、「这个不对」「点了没反应」 | P2 |
| 改 `workers/api`：接口、表、推送 | P3 |
| 组件不统一、统一样式 | P4 |
| 打包、发 TestFlight | P5 |

前后端都要动时，先 P3 再 P1。每种步骤的完整内容在 [playbooks.md](references/playbooks.md)：只读选中的那一节。

## 第 4 步：开任务清单

把选中步骤逐条放进任务清单，同一时间只有一条在进行中。中途发现要换类型时，重开清单并说明为什么换。

## 第 5 步：按步骤做

做每一步时遵守这些原则：

- **先证明能用。** 没在 iPhone 上看到、没在 D1 里查到，不说「好了」。只编译过就说「只编译过」。
- **修根因。** 找到值是在哪一步变错的，再改那一步。
- **先减再加。** 先看能不能复用现有组件或删掉多余代码，再写新的。
- **从手机上的体验倒推。** 判断做法好坏，看用户在手机上看到什么、要点几下。
- **先迁移调用方，再删旧的。** 换组件、换接口时，新旧并存到没人用旧的为止。
- **不卡在用户身上。** 要用户做的事（解锁手机、Face ID、在网页后台点按钮）一次列全；不依赖用户的部分先做。

## 第 6 步：交付

按这个顺序说：

1. 现在什么能用了，在手机上怎么看到。
2. 证据：截图、测试结果、D1 查询结果。
3. 没做或没验证的部分，和原因。
4. 需要用户决定或去做的事，一次说完。

没有用户的明确要求时，不提交、不推送、不部署。


---

# 全文：`1day-mode/references/playbooks.md`

# 1Day 任务步骤

每种任务一份固定步骤。开始时把选中的那一份逐条放进任务清单，做完一条勾一条。步骤里写的命令都在仓库根目录跑。

## 目录

- P1 App 改动（界面或逻辑）
- P2 修 bug
- P3 Worker 后端改动
- P4 统一组件
- P5 打 TestFlight

## P1 App 改动

1. 找到要改的代码。牵涉多个模块时，先派只读子 Agent 查调用关系。要新加数据结构、或改动跨过函数边界时，先用 how skill 弄清现有结构，再用 architect skill 比较 2～3 个做法，选定后再写。一两个文件内的小改动跳过这一步。
2. 动到界面时，先读 `DESIGN.md`：用第 6 节已有的组件，只写 `OneDay.*` token。
3. 纯逻辑的改动，能便宜地写单元测试就先写一个失败的测试。
4. 写最少的代码让它成立。能复用、能删的先复用、先删。
5. 新增或删除了 Swift 文件时，重新生成工程：`xcodegen generate --spec ios/project.yml --project ios`。参数顺序不能换。
6. 按测试档位跑：删字改文案只编译；改逻辑跑对应的 `-only-testing:AISetlogTests/XxxTests`。
7. 动到界面时跑 `python3 .claude/skills/1day-design-system/scripts/design_lint.py --baseline docs/design/design-lint-baseline.json`，不能比基线更差。
8. 按 run-1day 装到 iPhone，用 1day-verify 验证受影响的功能编号。
9. 交付：改了什么、截图、跑了哪档测试、哪些没验证。

## P2 修 bug

1. 先复现：在 iPhone 上按用户说的步骤走一遍并截图，或写一个能失败的单元测试。复现不了就停下，问用户一个具体问题（哪一步、哪个房间、什么时候）。
2. 找根因。顺着数据走：界面显示的值从哪来、哪一步变错了。不靠猜改代码。
3. 修根因，不在显示层盖住错误的值。
4. 证明修好了：同样的复现步骤现在是对的，并加一个以后能抓住同类问题的测试。
5. 按 P1 第 6～9 步收尾。

## P3 Worker 后端改动

后端在 `workers/api`，先读它的 `README.md`（路由表、上线步骤、用户 id 规则）。

1. 用户 id 规则不能破：Apple 用户在库里和 App 里是不带 `apple:` 的 `sub`，Google 用户是 `google:<sub>`。两边的转换函数要一起改。
2. 改表结构时新建 `workers/api/migrations/000N_<名字>.sql`。已经上线的 migration 文件不改。
3. 在 `workers/api/test/api.test.mjs` 里为新行为加测试，跑 `npm test`（在 `workers/api` 里）。
4. 本地真跑一遍：

   ```bash
   cd workers/api
   npx --no-install wrangler d1 migrations apply oneday --local --persist-to /tmp/oneday-state
   npx --no-install wrangler dev --port 8799 --persist-to /tmp/oneday-state
   ```

   用 `npx --no-install wrangler`（项目里的版本），不用全局那个旧版。本地数据放 `/tmp`，不碰 `.wrangler/state`。
5. 已经发出去的 App 版本还在用旧接口：不删、不改名它们用到的路由和字段。要换就新加一个，等旧版本没人用了再删。
6. 部署前问用户。同意后，有新 migration 先跑 `npx --no-install wrangler d1 migrations apply oneday --remote`，再 `npx --no-install wrangler deploy`。
7. 线上检查：不带 token 请求应该是 401；用 `.claude/skills/1day-verify/scripts/d1_read.py` 查数据；推送只能在真机上验。
8. App 也要改时，接着走 P1。

## P4 统一组件

按 1day-design-system 的路径 B 做。本步骤只补两条：

1. 统一组件不和功能改动放在同一次改动里。
2. 每统一完一类组件就停下给用户看截图，再做下一类。

## P5 打 TestFlight

每一步对外的操作（上传、提交、部署）都先问用户。

1. 要发的改动都已经提交了吗？没有就问用户要不要提交。不自己提交。
2. Worker 有没部署的改动时，先走 P3 第 6～7 步。
3. 这次改了数据去向吗（新服务器、新登录方式、新收集的数据）？改了就提醒用户：App Store Connect 的隐私标签和审核备注要更新，`docs/app-store-submission.md` 不一定是最新的。
4. build 号加 1：改 `ios/project.yml` 的 `CURRENT_PROJECT_VERSION`，再跑 xcodegen（P1 第 5 步的命令）。
5. 测试第 3 档：在模拟器上跑全部单元测试和 UI 测试。
6. 用 1day-verify 在 iPhone 上走全部编号。
7. 打 Release 归档：

   ```bash
   xcodebuild -project ios/AISetlog.xcodeproj -scheme AISetlog -configuration Release \
     -destination 'generic/platform=iOS' -archivePath /tmp/1day-release.xcarchive \
     -allowProvisioningUpdates archive 2>&1 | grep -E "error:|ARCHIVE"
   ```

8. 导出：`xcodebuild -exportArchive`，ExportOptions 里 `method` 是 `app-store-connect`，加 `-allowProvisioningUpdates`。
9. 上传：问用户，由用户在 Xcode Organizer 里上传，或用户同意后用 ExportOptions 的 `destination: upload` 直接传。
10. build 号的改动要不要提交，问用户。


---

# 全文：`1day-verify/SKILL.md`

---
name: 1day-verify
description: 在 Cassie 的 iPhone 上逐项验证 1Day App 的功能真的能用，并到线上 D1 数据库查证据，最后给出「哪项过了、证据是什么、哪项没验」的报告。用户说「验证一下」「测一下能不能用」「上线前走一遍」「这个功能好了吗」，或改完代码要证明它在真机上工作时使用。不用于：只编译或跑单元测试（直接用 xcodebuild）；只装上看一眼（用 run-1day）；界面统不统一（用 1day-design-system）；删除账号、给朋友发消息这类会留下真实痕迹的操作（先问用户）。
---

# 1day-verify

证明 1Day 在真机上能用。证据分两种，每项功能至少要有一种：**屏幕证据**（iPhone 截图或 `phone_elements` 读到的状态）和**服务器证据**（D1 里出现了对应的行）。

功能地图在 [references/features/README.md](references/features/README.md)。先在 README 里按关键词找到功能文件，每个文件写了子功能、用户怎么找到、怎么操作、验证表（编号、入口、什么算成功、服务器证据）和容易出错的地方。不点屏幕就能跳页面、看日志、打断点、录性能的工具在 [driving.md](references/features/driving.md)。

## 第 1 步：定范围

1. 看这次改了什么：`git status --short` 和 `git diff --stat`。
2. 从功能清单里挑出受影响的编号。
3. 用户说「全走一遍」或要打 TestFlight 时，选全部编号。
4. 把要验证的编号列给用户，不用等回复，直接开始。

## 第 2 步：装到手机上

1. 按 run-1day 的 Path B 编译、安装、启动 Debug 版。
2. 调 `phone_status`。`drivable` 不是 true 时，调一次 `phone_reconnect`（`wait_secs: 180`）。
3. 还是连不上时停下，告诉用户手机上要做什么（通常是解锁）。不改用模拟器冒充真机。

## 第 3 步：准备测试房间

清单里「对外写」标着「是」的功能，只在测试房间里做：

1. 先找有没有名字以「测试」开头、只有本人在的房间。
2. 没有就按 F5 建一个，名字是「测试」加当前时间。
3. 拍一拍（F14）、改头像名字（F18）、收推送（F15）会影响朋友或要别人配合：先问用户。

## 第 4 步：逐项验证

对每个编号：

1. 按「怎么走」操作。点按钮优先用 `phone_tap_label`；同名的元素先 `phone_elements` 查到再点。
2. 用 `phone_screenshot` 截图，确认「屏幕上算成功」那一条。黑屏、白屏、一直转圈都算失败。
3. 有服务器证据的，跑脚本查：

   ```bash
   python3 .claude/skills/1day-verify/scripts/d1_read.py recent 5
   python3 .claude/skills/1day-verify/scripts/d1_read.py room <邀请码>
   ```

   脚本只能读，不能写。退出码 1 是 wrangler 出错，看它打印的最后几行。
4. 记下结果：通过 / 失败 / 没验（写原因）。
5. 失败时，用 `phone_logs`（`process: "AISetlog"`）抓日志，`phone_crashes` 看有没有崩溃。App 自己的日志在 subsystem `com.cassie.AISetlog`（api / sync / app / debug），每个请求有一行状态码和耗时。后端那边用 `scripts/agent/worker-tail.sh --seconds 60` 边操作边看。只记录，不在本 Skill 里改代码。

「要真人」标着「是」的步骤（Face ID、密码、第二个账号）：停在那一步，告诉用户要做什么，用户做完再继续。不替用户输入密码。

## 第 5 步：收尾

1. 测试房间里本次发的消息和片段，留着还是退房删掉，问用户一次。
2. 调 `phone_release_owner` 把手机交还。

## 报告格式

一张表，每行一个编号：

| 编号 | 结果 | 证据 |
| --- | --- | --- |
| F6 | 通过，加入用了 2 秒 | 截图 + `members` 多 1 行 |

表后写：没验的项和原因；失败的项附日志里的关键一行。

## 维护功能清单

App 加了功能、改了入口或 identifier 时，同一次改动里更新 `references/features/` 里对应的功能文件。验证时发现 identifier 找不到，先查代码里它是不是改名了，改的是地图就修地图，改的是代码就报告给用户。


---

# 全文：`1day-verify/references/features/README.md`

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


---

# 全文：`1day-design-system/SKILL.md`

---
name: 1day-design-system
description: 维护 1Day iOS App 的设计规范 DESIGN.md，并把页面里的组件、字号、圆角、间距、颜色统一到规范上。用户说「组件不统一」「统一一下」「定设计规范」「加一个新组件」「这页和那页长得不一样」，或要新建一个可复用的 SwiftUI 组件、要定下某个 token 的值（哪怕只是一个圆角或间距）时使用。不用于：只问代码里现在用的是哪个颜色或字号变量（直接回答）；与 1Day 无关的通用 UI/UX 评审（用 oiloil-ui-ux-guide）；只想看 App 现在什么样（用 run-1day）；验证功能能不能用（用 1day-verify）。
---

# 1day-design-system

`DESIGN.md`（仓库根目录）是 1Day 界面的唯一依据。代码落点：`ios/AISetlog/Resources/Theme.swift` 里的 `OneDay` token，和 `ios/AISetlog/Views/DesignSystem/` 里的共用组件。本 Skill 只做两件事：**改规范**和**按规范统一页面**。

## 第 0 步：量现状

每次开始都先跑一次检查脚本，记下数字：

```bash
python3 .claude/skills/1day-design-system/scripts/design_lint.py
```

它数出 `ios/AISetlog/Views` 里手写的字号、圆角、padding、spacing、十六进制颜色，并列出最多的文件。

- 还没有基线文件 `docs/design/design-lint-baseline.json` 时，加 `--write-baseline docs/design/design-lint-baseline.json` 存一份，告诉用户存了。
- 已有基线时，加 `--baseline docs/design/design-lint-baseline.json`。退出码 1 表示有文件比基线更差，先看是谁加的。

## 选路径

| 用户要的 | 走 |
| --- | --- |
| 定规范、改 token、加组件条目 | 路径 A |
| 把某类组件或某几页统一到规范 | 路径 B |
| 两个都要 | 先 A 后 B，A 定下来之前不动页面 |

## 路径 A：改规范

1. 读完整的 `DESIGN.md`。
2. 找出这次要定的条目。标 **【待定】** 的条目优先。
3. 有审美取舍的地方，不自己拍板。准备 2～3 个选项，每个写一句取舍。能在真机上看的，按 run-1day 装到 iPhone 上截图给用户比较。
4. 等用户选定，再改 `DESIGN.md`：删掉【待定】标记，写上定下的值和用途。
5. 需要新 token 时，加到 `Theme.swift` 的 `OneDay` 里，名字和 `DESIGN.md` 完全一致。
6. 编译一次（测试第 1 档：只编译）。

停止条件：用户还没选的条目保持【待定】，不替用户填。

## 路径 B：统一页面

一次只统一**一类组件**（例如所有片段小图），不和功能改动混在一起。

1. 在 `DESIGN.md` 第 6 节找到这类组件的合并目标。没有目标时先走路径 A 定下来。
2. 用 `grep` 列出所有用到旧组件或手写样式的文件。
3. 把要改的文件清单和改法告诉用户。超过 3 个文件或约 100 行时，等用户说「可以」再动。
4. 先在 `Views/DesignSystem/` 做好目标组件（或确认已有的能用），只用 token。
5. 改动前，在 iPhone 上给每个受影响的页面截一张图，作为对比基准。
6. 一页一页把调用方换成目标组件。每换完一页：编译，再到 iPhone 上截同一个画面。
7. 对比前后截图。除了本来就要统一的地方，其他视觉变化（尺寸跳动、文字截断、颜色变了）都先停下，把两张图给用户看。
8. 旧组件没有任何调用方以后，再删掉它。用 `grep` 确认没人用了。
9. 更新 `DESIGN.md` 第 6 节：状态改成「已统一」。
10. 跑 `design_lint.py --baseline …`，确认没有变差，再用 `--write-baseline` 存新基线。
11. 跑测试第 2 档：编译 + 受影响页面对应的单元测试；有 UI 测试用到被改元素的 identifier 时跑那一个。

## 规则

- 页面代码只写 `OneDay.xxx`。确实需要写数字的（`DESIGN.md` 第 7 节的例外），在那一行写注释 `// design-lint: allow` 加一句原因。
- 新组件先在 `DESIGN.md` 第 6 节有一行，再写代码。
- 不改组件的行为、无障碍标签和 accessibility identifier；UI 测试靠它们找元素。
- 截图看的是用户的 iPhone。手机连不上时才用模拟器，并说明用的是模拟器。

## 交付时说

- 统一了哪类组件，改了哪几页。
- 前后截图各一张（同一个画面）。
- `design_lint.py` 的数字前后各是多少。
- 跑了哪一档测试，结果如何。
- 还剩哪些页面没统一。


---

# 全文：`run-1day/SKILL.md`

---
name: run-1day
description: 编译、安装、启动 1Day iOS App（AISetlog），装到 Cassie 的 iPhone 上截图看效果；手机连不上时退到模拟器。用户说「跑起来」「装到手机上」「截个图」「看看现在什么样」「开模拟器」，或改完代码要确认界面真的渲染出来、不只是编译过时使用。不用于：逐项验证功能并查 D1（用 1day-verify）；只跑单元测试（直接用本文「测试」一节的命令）。
---

# run-1day

| | |
|---|---|
| Xcode 工程 | `ios/AISetlog.xcodeproj`（由 `ios/project.yml` 生成，不在 git 里） |
| Scheme | `AISetlog` |
| Bundle ID | `com.cassie.AISetlog` |
| 最低系统 | iOS 17.0，只支持竖屏、只支持 iPhone（`TARGETED_DEVICE_FAMILY: "1"`） |

**Cassie 的规则（2026-10-30）：在模拟器上做的事（看页面、点流程、截图）都改到她的 iPhone 上，用 `iphone-use` MCP 做。** 按下面「真机（Path B）」第 1～4 步安装，用第 6 步的 `phone_*` 工具操作。手机连不上（调一次 `phone_reconnect` 后 `phone_status` 还没就绪）时，才按 [references/simulator.md](references/simulator.md) 用模拟器（Path A），并告诉用户换成了模拟器，不悄悄换。`xcodebuild test` 单元测试照常在模拟器上跑。

## 开始前：有没有别人在这个目录里写代码

```bash
git -C . status --short | wc -l          # 干净的起点应该是 0
ps aux | grep -c "[c]laude --dangerously-skip-permissions"
```

编译错误出在你没碰过的文件里，就说明有别人在写。这个仓库出过两次事：见 `progress.md` §1 的「并发事故记录」；还有 2026-09-15，会话中途 28 个文件变成已修改，`DayClip` 上一个写了一半的 `captionSticker` 字段把 `LocalRoomRuntime.swift` 编译搞坏了，而当时正在验证的是一个无关的配色改动。

**不要绕过去编译，也不要顺手修好它。** 那是别人写了一半的功能，替人写完只会让冲突更大。

不碰别人的改动也能验证自己的改动：在 `HEAD` 建一个临时 worktree，只把自己改的文件拷进去。

```bash
git worktree add /tmp/1day-verify HEAD --detach
cp ios/AISetlog/<你改的每个文件> /tmp/1day-verify/ios/AISetlog/<同样的路径>
cd /tmp/1day-verify
xcodegen generate --spec ios/project.yml --project ios   # .xcodeproj 不在 git 里
xcodebuild -project ios/AISetlog.xcodeproj -scheme AISetlog -configuration Debug \
  -destination 'id=<SIM_UDID>' -derivedDataPath /tmp/1day-dd-verify build 2>&1 \
  | grep -E "error:|BUILD"
# 用完：git worktree remove /tmp/1day-verify --force
```

`xcodegen` 这一步不能省：`.gitignore` 排除了 `ios/AISetlog.xcodeproj`，新 worktree 里根本没有工程文件。

装到真机的包也从这个 worktree 编，不从被污染的目录编，否则装到她手机上的包里带着别人没写完的东西。

## 真机（Path B，已验证到安装）

### 1. 找到设备

```bash
xcrun devicectl list devices
```

取标着 `available (paired)` 的那一行。Cassie 的是 `00008150-000A082A3A68C01C`（iPhone 17 Pro Max，有线；2026-10-13 之前是 `6BAD8B60-…`，现在 `devicectl` 列的是硬件 UDID）。同一台硬件有几行过期的 `unavailable` 是正常的，忽略。

### 2. 手机要解锁，并且保持亮屏

锁屏时下面每一步都会失败，报错不同，意思一样：

| 步骤 | 锁屏时的报错 |
|---|---|
| 用 `-destination 'id=…'` 编译 | `The developer disk image could not be mounted on this device.`，然后 `Timed out waiting for all destinations` |
| `devicectl device install app` | `kAMDMobileImageMounterDeviceLocked: The device is locked.` |
| `devicectl device process launch` | `FBSOpenApplicationErrorDomain error 7 … Locked` |

手机会按自动锁定时间自己锁屏，动作慢了就会在安装和启动**之间**锁上。请她把「设置 → 显示与亮度 → 自动锁定」改成「永不」，或者用第 5 步轮询。

`devicectl device info lockState` 报的 `passcodeRequired` / `unlockedSinceBoot` 都不能说明手机**现在**锁没锁。不用查，直接执行操作看报错。

### 3. 编译：不要按设备 id 指定目标

```bash
cd ios
xcodebuild -project AISetlog.xcodeproj -scheme AISetlog -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/1day-dd-dev \
  -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD"
```

关键是 `-destination 'generic/platform=iOS'`。按设备 id 指定时，`xcodebuild` 要先解析目标设备，这一步要挂载 DDI，挂载要求手机解锁。所以手机一锁，连**编译**也会在 60 秒超时后失败。用 generic 就分开了：编译总能成功，只有安装和启动要求解锁。

`-allowProvisioningUpdates` 让 Xcode 自动生成 team 的 provisioning profile。签名身份是 `Apple Development: liang.yue@northeastern.edu`，team `M7BPQ88622`。

产物在 `/tmp/1day-dd-dev/Build/Products/Debug-iphoneos/AISetlog.app`。

`grep` 不能省：完整编译日志约 5000 行，读它是这里最浪费时间的事。`error:` 加 `BUILD` 就是全部有用的信息。

### 4. 安装并启动

**用 `&&` 连在一条命令里。** 分两次调用，中间的空档里手机会自动锁屏：安装成功了，启动返回 `Locked`，又得重新轮询。2026-09-15 出现过两次。

```bash
DEV=00008150-000A082A3A68C01C
APP=/tmp/1day-dd-dev/Build/Products/Debug-iphoneos/AISetlog.app
xcrun devicectl device install app --device $DEV "$APP" && \
xcrun devicectl device process launch --device $DEV --terminate-existing com.cassie.AISetlog
```

成功时会看到 `installationURL: file:///private/var/containers/...` 和一个 `processIdentifier`。

安装成功、只有启动失败时，**就算完成**：包已经在她手机上，她点图标就能打开。不要花三分钟轮询启动，说「已经装上」然后继续。

### 5. 轮询，不要一直催

她不在手机旁边时，让它自己装上，不要问了再等：

```bash
for i in $(seq 1 12); do
  out=$(xcrun devicectl device install app --device $DEV "$APP" 2>&1)
  echo "$out" | grep -q "installationURL" && { echo "INSTALLED (try $i)"; break; }
  echo "try $i: locked"; sleep 15
done
```

`process launch` 也是一样的写法，匹配 `processIdentifier`。最多约 3 分钟，超过就说超时了，不要一直悄悄循环。

### 6. 看屏幕和点击：`iphone-use` MCP

开源项目 [leeguooooo/iphone-use](https://github.com/leeguooooo/iphone-use)：Mac 上一个 daemon，加上手机上它自己的 XCTest runner（USB 或 Wi-Fi）。装在 `~/Applications/iPhoneUse.app`，MCP server 名字是 `iphone-use`（user scope）。

| 要做的事 | 工具 |
|---|---|
| 能不能用 | `phone_status`；不行就调一次 `phone_reconnect` |
| 截图 | `phone_screenshot`（截完要真的看图，黑屏就是失败） |
| 把屏幕读成文字 | `phone_elements`（用 `query` 过滤） |
| 点击 | 先用 `phone_tap_label`；只能按位置点的控件用 `phone_tap`（x/y 取 0～1） |
| 输入 / 滚动 | `phone_type`、`phone_scroll` |
| 崩溃 / 日志 | `phone_crashes`、`phone_logs`（`process: "AISetlog"`） |
| 录一段操作 | `phone_record` 开始/停止，MP4 存在 Mac 上 |

用 `devicectl` 安装启动（第 4 步），再用这些工具操作。手机还是要解锁；在终端跑 `iphone-use doctor` 会说缺什么。装上了不等于能用，要截图看。

启动返回了 PID 只说明程序起来了，不说明画面渲染出来了。这个 App 的历史里全是黑屏 bug（`progress.md` §3，build 13–19）。黑屏、白屏都算失败。

## 跳页面、看日志、断点、性能：`scripts/agent/`

一路点过去之前，先看 `scripts/agent/README.md`：

- `open-link.sh surface/camera`（还有 `story/<uuid>`、`seed-library`、`dump-state` 等）在运行中的 Debug 版里直接切页面，不弹确认。`simctl openurl oneday://...` 也行，但 iOS 每次都会问「在 1Day Dev 中打开？」。
- `app-logs.sh --seconds 20` 输出 App 自己的日志（每个 Worker 请求的状态码和耗时、房间同步、调试链接）。
- `debug.sh --break File.swift:LINE --url <route>` 在 lldb 里停在那一行，打印 `bt` 和 `frame variable` 后断开。
- `trace.sh --launch` 录 Time Profiler，列出最重的 1Day 函数。

## 重新生成 Xcode 工程

改了 `ios/project.yml`，或者新加的 `.swift` 文件没被编译时：

```bash
xcodegen generate --spec ios/project.yml --project ios
```

**参数顺序不能换。** `xcodegen --project ios/AISetlog.xcodeproj` 会把 `--project` 当成**输出目录**，生成一个嵌套的 `AISetlog.xcodeproj/AISetlog.xcodeproj/`，真正的工程没变。2026-09-11 02:09 到修复之间，每一次「编译通过」编的都是旧工程（`progress.md` §1）。刚改的东西没效果时，先查有没有这个嵌套目录，再去调别的。

## 测试

```bash
xcodebuild -project ios/AISetlog.xcodeproj -scheme AISetlog \
  -destination 'id=<SIM_UDID>' -derivedDataPath /tmp/1day-dd test 2>&1 \
  | grep -E "error:|failed|Executed .* tests"
```

`<SIM_UDID>` 怎么查见 [references/simulator.md](references/simulator.md) 第 1 步。

`AISetlogUITests` 的超时是按这台机器调的，在 CI 机器上已知偏紧（commit `98648fb`）。在本机上 UI 测试只因为时间超时失败，通常是机器负载高，不是 App 出了问题。


---

# 全文：`run-1day/references/simulator.md`

# 模拟器（Path A，已端到端验证）

只在 iPhone 连不上时用（见 SKILL.md 开头的规则），用了要告诉用户。单元测试本来就在模拟器上跑，不受这条限制。

## 1. 选设备并启动

```bash
xcrun simctl list devices available | grep -A20 "iOS 2"
xcrun simctl boot <SIM_UDID>
open -a Simulator
```

这台机器上：`iPhone 17 Pro Max` = `7F09FED5-12E4-4875-B27C-2629AF67CE97`，`iPhone SE (2nd generation)` = `2612ECE6-9957-4CBF-933F-2002C5D493D4`。重装运行时后 UDID 会变，用前重新列一遍，不要直接信这两个。

## 2. 编译

```bash
cd ios
xcodebuild -project AISetlog.xcodeproj -scheme AISetlog -configuration Debug \
  -destination 'id=<SIM_UDID>' -derivedDataPath /tmp/1day-dd build 2>&1 \
  | grep -E "error:|BUILD"
```

`-derivedDataPath` 不放默认位置：Xcode 里索引卡住时不会影响命令行编译，而且 `rm -rf /tmp/1day-dd` 是安全的彻底重置。

## 3. 安装：第一次会卡住

```bash
xcrun simctl install <SIM_UDID> /tmp/1day-dd/Build/Products/Debug-iphonesimulator/AISetlog.app
```

症状：没有输出、没有报错，进程 CPU 约 0%，一直不结束。`bootstatus` 会说「Device already booted, nothing to do」：它说的开机状态是对的，但设备其实还没准备好。

解决办法，重试每次都成功：

```bash
pkill -f "simctl install"
xcrun simctl shutdown all
killall Simulator
killall -9 com.apple.CoreSimulator.CoreSimulatorService
sleep 4
xcrun simctl boot <SIM_UDID> && open -a Simulator && sleep 5
# 再装一次
```

## 4. 启动并截图

```bash
xcrun simctl launch --terminate-running-process <SIM_UDID> com.cassie.AISetlog
sleep 5
xcrun simctl io <SIM_UDID> screenshot /tmp/1day-shot.png
```

然后**读这张 PNG**。启动返回了 PID 只说明程序起来了，不说明画面渲染出来了。黑屏或空白都算失败。

首屏应该是：「把今天，留成一支片」、一段循环播放的示例视频（`RoomDemoPlaybackSurface`）和「开始我的第一支片」。

先给相机和麦克风权限，免得权限弹窗挡住屏幕：
`xcrun simctl privacy booted grant camera com.cassie.AISetlog.dev`。

## 5. 点击

首选 iOS Simulator MCP（`mcp__Claude_Code_iOS_Simulator__control`），按设备点坐标点击（17 Pro Max 是 440×956）。点击加 `duration: 0.15`，时长为 0 的点击有时会丢。

没有 `simctl tap`。其他两个办法都不太好用：

**AppleScript**：要把终端加到「系统设置 → 隐私与安全性 → 辅助功能」，否则每次点击都返回 `-25204`。

```bash
# 设备屏幕是 Simulator 窗口的第 5 个 UI 元素
osascript -e 'tell application "Simulator" to activate' \
          -e 'tell application "System Events" to tell process "Simulator" \
              to tell window 1 to get {position, size} of UI element 5'
```

把 1320×2868 的 `simctl` 截图上的点换算到屏幕：`x = gx + px * gw / 1320`，`y = gy + py * gh / 2868`，再 `tell application "System Events" to click at {x, y}`。

要**先**激活 Simulator：窗口不在最前面时查它会返回 `-1719`（invalid index）。

**`idb`**（`brew install facebook/fb/idb-companion`）好用一些，但这台机器没装。要点很多次时再装。

## 6. 相机

iOS 26 模拟器上相机显示「相机不可用」（没有采集设备）。要截相机页面，用 Debug 版才有的假相机启动：

```bash
xcrun simctl launch --terminate-running-process <SIM_UDID> com.cassie.AISetlog \
  -onboarding.completed.v1 YES -appLanguage chinese -simulatedCamera YES
```

取景框是一个标着 SIMULATOR 的动画画面，按住快门会生成一段 `DemoClipFactory` 片段，所以拍摄到回看能完整走通。这个开关故意默认关闭：UI 测试要用「相机不可用」页面上的「示例片段」按钮。

跳页面、看日志等工具和真机通用，见 SKILL.md 的 `scripts/agent/` 一节。

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
3. 写最少的代码让它成立。能复用、能删的先复用、先删。
4. 新增或删除了 Swift 文件时，重新生成工程：`xcodegen generate --spec ios/project.yml --project ios`。参数顺序不能换。
5. 编译通过。项目没有自动化测试（2026-11-21 全部删除），不要新写测试，也不要跑 `xcodebuild test`。
6. 动到界面时跑 `python3 .claude/skills/1day-design-system/scripts/design_lint.py --baseline docs/design/design-lint-baseline.json`，不能比基线更差。
7. 按 run-1day 装到 iPhone，用 1day-verify 验证受影响的功能编号。
8. 交付：改了什么、截图、哪些没验证。

## P2 修 bug

1. 先复现：在 iPhone 上按用户说的步骤走一遍并截图。复现不了就停下，问用户一个具体问题（哪一步、哪个房间、什么时候）。
2. 找根因。顺着数据走：界面显示的值从哪来、哪一步变错了。不靠猜改代码。
3. 修根因，不在显示层盖住错误的值。
4. 证明修好了：在 iPhone 上按同样的复现步骤走一遍，现在是对的。
5. 按 P1 第 5～8 步收尾。

## P3 Worker 后端改动

后端在 `workers/api`，先读它的 `README.md`（路由表、上线步骤、用户 id 规则）。

1. 用户 id 规则不能破：Apple 用户在库里和 App 里是不带 `apple:` 的 `sub`，Google 用户是 `google:<sub>`。两边的转换函数要一起改。
2. 改表结构时新建 `workers/api/migrations/000N_<名字>.sql`。已经上线的 migration 文件不改。
3. 本地真跑一遍：

   ```bash
   cd workers/api
   npx --no-install wrangler d1 migrations apply oneday --local --persist-to /tmp/oneday-state
   npx --no-install wrangler dev --port 8799 --persist-to /tmp/oneday-state
   ```

   用 `npx --no-install wrangler`（项目里的版本），不用全局那个旧版。本地数据放 `/tmp`，不碰 `.wrangler/state`。
4. 已经发出去的 App 版本还在用旧接口：不删、不改名它们用到的路由和字段。要换就新加一个，等旧版本没人用了再删。
5. 部署前问用户。同意后，有新 migration 先跑 `npx --no-install wrangler d1 migrations apply oneday --remote`，再 `npx --no-install wrangler deploy`。
6. 线上检查：不带 token 请求应该是 401；用 `.claude/skills/1day-verify/scripts/d1_read.py` 查数据；推送只能在真机上验。
7. App 也要改时，接着走 P1。

## P4 统一组件

按 1day-design-system 的路径 B 做。本步骤只补两条：

1. 统一组件不和功能改动放在同一次改动里。
2. 每统一完一类组件就停下给用户看截图，再做下一类。

## P5 打 TestFlight

每一步对外的操作（上传、提交、部署）都先问用户。

1. 要发的改动都已经提交了吗？没有就问用户要不要提交。不自己提交。
2. Worker 有没部署的改动时，先走 P3 第 5～6 步。
3. 这次改了数据去向吗（新服务器、新登录方式、新收集的数据）？改了就提醒用户：App Store Connect 的隐私标签和审核备注要更新，`docs/app-store-submission.md` 不一定是最新的。
4. build 号加 1：改 `ios/project.yml` 的 `CURRENT_PROJECT_VERSION`，再跑 xcodegen（P1 第 4 步的命令）。
5. 用 1day-verify 在 iPhone 上走全部编号。
6. 打 Release 归档：

   ```bash
   xcodebuild -project ios/AISetlog.xcodeproj -scheme AISetlog -configuration Release \
     -destination 'generic/platform=iOS' -archivePath /tmp/1day-release.xcarchive \
     -allowProvisioningUpdates archive 2>&1 | grep -E "error:|ARCHIVE"
   ```

7. 导出：`xcodebuild -exportArchive`，ExportOptions 里 `method` 是 `app-store-connect`，加 `-allowProvisioningUpdates`。
8. 上传：问用户，由用户在 Xcode Organizer 里上传，或用户同意后用 ExportOptions 的 `destination: upload` 直接传。
9. build 号的改动要不要提交，问用户。

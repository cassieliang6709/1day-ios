# CloudKit：部署 `Member` 记录类型

有人用邀请码加入房间后，App 会在公共数据库写一条 `Member` 记录。代码已经写好，但 Production 环境里还没有这个记录类型，Production 会拒绝写入。在部署之前：

- 加入房间照常成功，只是控制台会多一行 `[room] member record failed: ...`。
- 账号注销会去删这条记录，删一条不存在的记录算成功，不会卡住注销。

所以部署前后都不会坏东西，只是部署前没有记录。

## 记录长什么样

| 项 | 值 |
| --- | --- |
| 记录类型 | `Member` |
| recordName | `房间码_用户ID`，例如 `KPADC7_001234.abcd...`。同一个人重复加入只改这一条 |
| `roomCode` | String，房间码 |
| `userID` | String，Apple 登录给的用户 ID（和 Clip 的 `authorID` 是同一个值） |
| `displayName` | String，加入时的显示名 |
| `joinedAt` | Date/Time，最近一次加入的时间（重复加入会覆盖） |

代码位置：`CloudKitService.saveMember` / `memberRecordName`（`ios/AISetlog/Services/Cloud/CloudKitService.swift`）。

## 第 1 步：本地临时连 Development（不要提交）

`ios/project.yml` 里 Debug 和 Release 默认都连 Production。要在真机或模拟器上先让 App 在 Development 里自动建出 `Member` 类型，需要临时把 Debug 改掉：

1. 打开 `ios/project.yml`，找到 `configs: → Debug:` 下面的 `CLOUDKIT_ENVIRONMENT: Production`，改成 `CLOUDKIT_ENVIRONMENT: Development`。
2. 重新生成工程：

   ```bash
   xcodegen generate --spec ios/project.yml --project ios
   ```

3. 用 Debug 版装到手机，登录后用邀请码加入一个 **Development 里的房间**（Development 和 Production 的数据是两套，Production 的房间码在这里查不到，要先在这台 Debug 版上建一个房间，再用另一台设备或另一个测试账号加入）。
4. 看 Xcode 控制台出现 `[room] saved member code=...`，说明 Development 里已经有 `Member` 类型了。
5. **测完马上改回** `CLOUDKIT_ENVIRONMENT: Production`，再跑一次 `xcodegen generate`。用 `git diff ios/project.yml` 确认没有改动，这个改动不能提交。

也可以跳过第 1 步，直接在 Console 里手建类型（第 2 步）。

## 第 2 步：在 CloudKit Console 的 Development 里建类型和索引

打开 <https://icloud.developer.apple.com/dashboard>，选容器 `iCloud.com.cassie.AISetlog`，环境选 **Development**。

1. 左边 **Schema → Record Types**。如果第 1 步跑过，`Member` 已经在了；没有就点 **+**，名字填 `Member`，加四个字段：
   - `roomCode` — String
   - `userID` — String
   - `displayName` — String
   - `joinedAt` — Date/Time
2. 左边 **Schema → Indexes**，选 `Member`，加这几个索引：
   - `recordName` — **QUERYABLE**（Console 里按记录浏览需要它）
   - `roomCode` — **QUERYABLE**（以后按房间列出成员要用）
   - `joinedAt` — **SORTABLE**（按加入时间排序）
3. 点 **Save Changes**。
4. 可选检查：**Data → Records**，类型选 `Member`，按 `roomCode` 查一下，能看到第 1 步写进去的那条。

权限用默认的就行（公共数据库：所有人可读，登录用户可新建，只有创建者能改和删）。注销时删自己的记录靠的就是"创建者能删"。

## 第 3 步：部署到 Production

1. Console 左下角点 **Deploy Schema Changes...**。
2. 在弹出的对比里确认只有这些新增：`Member` 记录类型、4 个字段、3 个索引。**如果出现别的改动，先停下来**，弄清楚是谁加的再部署。
3. 点 **Deploy**。
4. 环境切到 **Production**，在 **Schema → Record Types** 里确认能看到 `Member`。

部署后不用发新版：已经装了这版代码的手机，下次加入房间就会写成功。

## 部署后怎么确认

1. 用正常的 Debug 版（连 Production）在真机上用邀请码加入一个房间。
2. Xcode 控制台出现 `[room] saved member code=...`，没有 `member record failed`。
3. Console 切到 Production → **Data → Records** → `Member`，按 `roomCode` 能查到这条。

## 相关测试

`ios/AISetlogTests/RoomMemberRecordTests.swift`（加入写一条、重复加入不新增、写失败不影响加入、找不到房间不写、本地演示房间不写）和 `AccountDeletionServiceTests.testDeletingMyAccountDeletesMyMemberRecord`（注销会删）。这些测试都不连 CloudKit。

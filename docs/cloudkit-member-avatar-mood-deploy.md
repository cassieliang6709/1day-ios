# CloudKit：一次建好 `Member` 记录类型（含头像和心情）

`Member` 是房间成员的记录。上一版只写了 4 个字段（见 `docs/cloudkit-member-deploy.md`），**那一版还没部署**。这一版又加了 3 个字段：头像图、今天的心情、心情是哪天选的。所以不要分两次部署，按这份文档**一次把 7 个字段和索引都建好，一次 Deploy**。`docs/cloudkit-member-deploy.md` 那份可以不用再看。

## 部署前会怎样

Debug 和 Release 默认都连 Production。Production 里没有 `Member` 类型，所有写入和查询都会被拒绝。代码已经按这个情况处理：

- 加入房间照常成功。控制台多一行 `[room] member record failed: ...`。
- 选心情、改心情照常保存在手机上（私有库的心情日记不受影响）。写进房间失败只打一行 `[room] member profile failed: ...`，下次回到 App 再试。
- 做头像照常保存在手机上，我自己的头像和心情在房间里照常显示（读的是本机）。朋友那边看不到，直到部署。
- 拉房间成员失败只打 `[room] member fetch failed: ...`，房间里的人照常显示名字首字。

部署之后不用发新版，下次回到 App 就会把头像和心情写上去。

## 记录长什么样

| 项 | 类型 | 说明 |
| --- | --- | --- |
| 记录类型 | `Member` | |
| recordName | | `房间码_用户ID`，例如 `KPADC7_001234.abcd...`。一个人在一个房间只有这一条 |
| `roomCode` | String | 房间码 |
| `userID` | String | Apple 登录给的用户 ID（和 Clip 的 `authorID` 同一个值） |
| `displayName` | String | 显示名 |
| `joinedAt` | Date/Time | 最近一次加入的时间。自己建的房间是第一次写头像或心情的时间 |
| `avatar` | **Asset** | 做好的头像 PNG（768×768，约 200–400 KB）。**只有成品头像，原照片从不上传** |
| `moodKind` | String | 今天的心情：`happy` / `calm` / `tired` / `sad` / `angry` |
| `moodDay` | Date/Time | 选这个心情的时间。朋友的手机只在同一天显示，过了这天就不显示 |

心情日记的文字**不在这里**，它只在私有库（`MoodSync`）。

代码位置：`CloudKitService.saveMember` / `saveMemberProfile` / `fetchMembers`（`ios/AISetlog/Services/Cloud/CloudKitService.swift`）。

## 第 1 步：在 Development 里建类型（Console 手建，最简单）

打开 <https://icloud.developer.apple.com/dashboard>，选容器 `iCloud.com.cassie.AISetlog`，环境选 **Development**。

1. 左边 **Schema → Record Types**，点 **+**，名字填 `Member`。
2. 点 **+ Add Field**，加下面 7 个字段（名字一个字母都不能错，大小写也要一样）：
   - `roomCode` — String
   - `userID` — String
   - `displayName` — String
   - `joinedAt` — Date/Time
   - `avatar` — Asset
   - `moodKind` — String
   - `moodDay` — Date/Time
3. 点 **Save**。

（也可以临时把 `ios/project.yml` 里 Debug 的 `CLOUDKIT_ENVIRONMENT` 改成 `Development`，在 Development 里加入房间、做头像、选心情，让 App 自动建出这些字段。做法见 `docs/cloudkit-member-deploy.md` 第 1 步，测完一定改回 `Production`，这个改动不能提交。手建更省事。）

## 第 2 步：加索引

还是 Development，左边 **Schema → Indexes**，选 `Member`，点 **+**，加这 3 个：

| 字段 | 索引类型 | 为什么 |
| --- | --- | --- |
| `recordName` | **QUERYABLE** | Console 里按记录浏览要用 |
| `roomCode` | **QUERYABLE** | **必须有。** App 按房间码拉成员（头像、心情）靠它，没有它查询会失败 |
| `joinedAt` | **SORTABLE** | 按加入时间排序 |

点 **Save Changes**。

权限用默认的（公共库：所有人可读，登录用户可新建，只有创建者能改和删）。改自己的头像和心情、注销时删自己的记录，靠的都是"创建者能改能删"。

## 第 3 步：部署到 Production

1. Console 左下角点 **Deploy Schema Changes...**。
2. 在弹出的对比里确认只有这些新增：`Member` 记录类型、7 个字段、3 个索引。**如果出现别的改动，先停下来**，弄清楚是谁加的再部署。
3. 点 **Deploy**。
4. 环境切到 **Production**，在 **Schema → Record Types** 里确认 `Member` 有 7 个字段，**Schema → Indexes** 里 `roomCode` 是 QUERYABLE。

## 部署后怎么确认

1. 真机装正常的 Debug 版（连 Production），登录，进一个房间。
2. 在「我的」选一个心情。Xcode 控制台出现 `[room] saved member profile code=...`，没有 `member profile failed`。
3. 在设置里点自己的头像，做一个头像，点「就是这样」。控制台再出现一次 `saved member profile`。
4. Console 切到 Production → **Data → Records** → 类型 `Member`，按 `roomCode` 查，能看到这条，`avatar` 有文件，`moodKind` 是刚选的心情。
5. 用另一台手机（另一个 Apple ID）进同一个房间，下拉或等 10 秒同步，房间页我那一列的头像变成我的头像，右下角挂着今天的心情表情。

## 相关测试（都不连 CloudKit）

- `ios/AISetlogTests/MemberProfileSyncTests.swift`：心情和头像写进我所有房间；同样的内容不重复写；写失败下次重试；不写心情文字；朋友的心情只在当天显示；拉成员失败保留原来的头像。
- `ios/AISetlogTests/RoomMemberRecordTests.swift`：加入写一条、重复加入不新增、写失败不影响加入。
- `ios/AISetlogTests/AvatarDecorLayoutTests.swift`：头像装饰层（腮红、贴纸、描边）的位置规则。

## 可以和 Clip 的 captionsJSON 一起部署

`Clip` 记录要加的 `captionsJSON` 字段（见 `docs/cloudkit-clip-captions-deploy.md`）可以和这份的 `Member` 放在同一次 **Deploy Schema Changes** 里：先在 Development 把两边都建好，第 3 步的对比里应该看到 `Member`（7 个字段、3 个索引）加上 `Clip.captionsJSON`，确认后一次 Deploy。

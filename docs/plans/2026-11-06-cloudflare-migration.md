# 把 CloudKit 全部换成 Cloudflare（2026-11-06）

目标：房间、成员、片段、回应、聊天、拍一拍、心情日记、推送，全部走自己的 Worker（`workers/api`，域名 `auth.liangyue.site`），App 里不再用 CloudKit。

## 放在哪

| 东西 | 以前（CloudKit） | 现在（Cloudflare） |
| --- | --- | --- |
| 房间 / 成员 / 片段信息 / 回应 / 聊天 / 拍一拍 | 公共数据库的 `Room` `Member` `Clip` `Reaction` `Comment` `Poke` | D1 数据库 `oneday`，同名的表 |
| 视频、头像 | `CKAsset` | R2 桶 `oneday-media` |
| 心情日记 | 私有数据库 `MoodEntry` | D1 `moods` 表，只有本人能读 |
| 推送 | `CKQuerySubscription` | Worker 写入后直接调 APNs |
| 登录 | 不需要（看 iCloud 账号） | Apple / Google 登录换 1Day 的 session token |

## 要遵守的点

1. **身份只从 token 来。** 每个请求带 `Authorization: Bearer <session>`，Worker 从 token 里取用户 id，请求里写的 authorID 必须等于它，否则 403。
2. **用户 id 和老数据对得上。** Apple 用户在 App 里的 id 是 Apple 的 `sub`（没有前缀），Google 是 `google:<sub>`。Worker 的 session 里是 `apple:<sub>`，写进数据库时去掉 `apple:`，这样 CloudKit 搬过来的老数据作者不变。
3. **记录名不变。** 片段、成员、回应、拍一拍的 id 还是原来的确定性名字（`code_author_dayN` 这种），评论还是本地 UUID。重复写同一条 = 覆盖，不报错。删账号、退房间都按名字删。
4. **只能删自己的。** 按名字删时，别人的记录不删、也不算删掉；本来就不存在的算删掉（和 CloudKit 的 unknownItem 一样）。
5. **知道邀请码 = 能看房间。** 和 CloudKit 公共库一样，不另加成员校验。写东西要登录。
6. **App 里其他代码少动。** `CloudKitService` 这个名字和它的结构体先留着，只换里面的实现，调用的地方不用改。改名以后单独做。
7. **不自动部署、不提交。** 建 D1 / R2、`wrangler deploy`、跑数据迁移，都写成命令留给 Cassie 确认后跑。
8. **测试分档。** Worker 用 `npm test`（本地 sqlite 模拟 D1，不联网）；iOS 编译 + 相关单测。

## 需要 Cassie 设置的

见 `workers/api/README.md` 的「上线步骤」。

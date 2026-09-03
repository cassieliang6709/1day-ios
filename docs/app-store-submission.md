# 1Day — App Store 提交材料

依据代码实际行为整理,不是估计。核对方式:全仓搜索第三方 SDK、网络调用、位置/通讯录/广告标识符
API,以及 `CloudKitService` 里实际写入的每一个字段。

**核心事实**

- 零第三方 SDK,零 `URLSession`,零分析/崩溃统计库
- 不使用位置、通讯录、IDFA、App Tracking Transparency
- Sign in with Apple 只请求 `.fullName`(`AccountStore.configure`)——**不收邮箱**
- **单人故事完全离线**:片段和数据只在设备上,一个字节都不上传
- **只有共享房间**会上传,目标是本 App 的 CloudKit **公共**数据库

因为用的是公共数据库(由开发者控制),Apple 的口径里这算「收集」,必须申报。
如果用的是用户自己 iCloud 里的私有数据库,则通常不算。

---

## 一、App 隐私问卷(App Privacy)

App Store Connect → App 隐私 → 编辑。逐项如下。

### 需要申报「收集」的四项

全部四项的答案都一样:

- **是否关联到用户身份?** → **是**(绑定 Apple 用户 ID 与显示名)
- **是否用于追踪?** → **否**(不做跨 App 追踪、不给数据经纪商、无广告)
- **用途** → **仅勾「App 功能」(App Functionality)**
  不要勾分析、产品个性化、广告

| 类别 | 具体项 | 实际是什么 |
|---|---|---|
| 联系信息 Contact Info | **姓名 Name** | Sign in with Apple 拿到的显示名,写进 `authorName` / `ownerName`,房间里其他成员看得到 |
| 用户内容 User Content | **照片或视频 Photos or Videos** | 上传到房间的片段(CKAsset) |
| 用户内容 User Content | **音频数据 Audio Data** | 片段里录进去的声音。它嵌在视频里,但含用户语音,**照实勾上** |
| 用户内容 User Content | **其他用户内容 Other User Content** | 字幕(`overlayText`)、评论文字、表情回应、房间标题与瞬间名称 |
| 标识符 Identifiers | **用户 ID User ID** | Apple 的稳定用户标识,存为 `authorID` / `ownerID` |

> 音频那项容易漏。宁可多勾也不要少勾 —— 少申报会被打回,多申报只是标签上多一行。

### 明确选「否 / 不收集」的项

邮箱、电话、地址、其他联系方式、健康与健身、财务信息、**位置(精确与粗略都没有)**、
敏感信息、通讯录、浏览记录、搜索记录、设备 ID、购买记录、使用数据、诊断数据、其他数据。

### 会被追问的两点

**「单人模式什么都不传,还要申报吗?」** 要。问卷没有「有时候」这个选项 —— 只要存在
会上传的路径就得申报。差别写在审核备注里说明。

**推送通知**:共享房间用 CloudKit 订阅推送。推送令牌由 Apple 处理,App 自己不收集、
不存储设备令牌,所以**不勾** Device ID。

---

## 二、审核备注(App Review Information → Notes)

英文版(填这份):

```
1Day records short video clips (2/5/10s) throughout a day and stitches
them into one short film on-device.

NO DEMO ACCOUNT NEEDED — the complete core loop works signed-out:
  1. Launch → "Start today's story"
  2. Pick a theme, tap Next, choose "By yourself", tap "Create story"
  3. On the timeline, tap the highlighted moment → record a 2s clip
  4. Repeat for the remaining moments
  5. The film is generated automatically when the last moment is filmed,
     and can be replayed any time via the button at the bottom of the
     timeline

Permissions: camera and microphone are required to record. The app only
records in-app; importing from the photo library is intentionally not
offered.

SHARED ROOMS ("With friends") require two devices signed into two
different iCloud accounts, plus Sign in with Apple. If only one device is
available, this feature cannot be fully exercised — the solo flow above
covers all core functionality. Shared rooms use our CloudKit public
database; no third-party servers are involved.

ACCOUNT DELETION (Guideline 5.1.1(v)):
  Home → tap the avatar (top right) → Settings → Account → Delete account
This deletes the local account and every story on the device, and removes
the clips, reactions and comments this user uploaded to shared rooms.
Sign in with Apple is only used for shared rooms; solo users never create
an account.

Privacy policy: https://1day.liangyue.site/privacy

No third-party SDKs, no analytics, no advertising, no tracking. Solo
stories never leave the device.
```

中文版(备用,一般不需要):

```
1Day 让用户在一天中录下若干 2/5/10 秒的短片段,并在设备上自动合成一支短片。

无需测试账号 —— 未登录即可完整体验核心流程:
  1. 启动 → 「开始今天的故事」
  2. 选一个主题 → 下一步 → 选「自己来」→ 「创建故事」
  3. 在时间线上点高亮的那个瞬间 → 录一段 2 秒
  4. 依次录完其余瞬间
  5. 录完最后一个会自动生成短片,也可随时通过时间线底部按钮重看

权限:录制需要相机和麦克风。App 只支持现场拍摄,不提供从相册导入。

「和朋友一起」需要两台设备、两个不同的 iCloud 账号,并使用「通过 Apple 登录」。
只有一台设备时无法完整验证该功能 —— 上面的单人流程已覆盖全部核心功能。
共享房间使用本 App 的 CloudKit 公共数据库,不涉及任何第三方服务器。

删除账号(指南 5.1.1(v)):
  首页 → 点右上角头像 → 设置 → 账号 → 删除账号

隐私政策:https://1day.liangyue.site/privacy
```

---

## 三、提交前必做

- [ ] **CloudKit schema 从 Development 部署到 Production**
      CloudKit Console → Schema → Deploy Schema Changes。
      不做的话共享房间在 TestFlight 和线上**一定坏** —— 发布包的 entitlement 是
      `icloud-container-environment: Production`,而全部开发测试都跑在 Development。
      同时确认 Production 里 `Clip` 的 `roomCode` 和 `day` 是 **queryable**,
      否则 `fetchClips` 抛 `.fieldNotQueryable`(索引不会随 schema 自动创建)。
- [ ] **隐私政策 URL** 填进 App Store Connect(与 App 内 Settings 里的一致)
- [ ] **截图本地化**:不要把 `docs/appstore/` 现有中文截图继续用于美国区。
      按 `ios/release/1.2/AppStoreMetadata.md` 的顺序分别导出英文和简体中文两套
      1320×2868 截图;美国区前三张必须是英文,并优先展示「三个瞬间 → 自动成片」
- [ ] **年龄分级**问卷
- [ ] **导出合规**:已在 `project.yml` 设 `ITSAppUsesNonExemptEncryption: false`
      (只用 HTTPS/CloudKit,属豁免),上传时不会再问

## 四、已知会被审核盯上的点

**5.1.1(v) 删除账号** —— 已实现,位置见上。审核员会专门找,备注里写清路径能少一轮。

**5.1.1 权限用途说明** —— 三条 `NSxxxUsageDescription` 都在 `project.yml` 里,
且都说明了具体用途,不是空话。

**2.1 完整性** —— 单人流程不需要登录也不需要网络,审核员一定跑得通。这是最大的保险。

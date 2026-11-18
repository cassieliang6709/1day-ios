# 房间列表、加入、邀请、退出

房间页（tab「房间」）列出我加入和创建的所有房间。从这里加入别人的房间、邀请朋友、退出房间。

## 子功能

- 房间卡片：`today-story-open` 打开房间，`today-story-continue` 是卡片上的「继续拍」或「看成片」。
- 新建房间：`friends-new-room`（「新建房间」），进入新建流程，见 [compose.md](compose.md)。
- 加入房间：`friends-join-room`（「我有邀请码」）或 `home-join-room`（「输入邀请码」），弹出输入框 `invite-code-field`。剪贴板里没有邀请码时出现 `paste-failed`。
- 邀请朋友：`friends-invite`（「邀请朋友一起拍」）弹出选房间的 sheet。选已有房间 `friends-invite-room-<邀请码>` 或新建 `friends-invite-new-room`，然后显示邀请码 `invite-code`，可以复制 `invite-copy-code` 或分享 `invite-share`（「发给朋友」）。房间里面也有邀请按钮 `room-invite`。
- 退出房间：房间页里的 `room-more`（「更多」）菜单 → 退出房间。自己一个人的计划显示的是删除。
- 示例房间：`home-room-demo`，只在 Debug 构建开了 `-demoEntries YES` 时出现。

## 用户怎么找到它

打开 App 默认就在房间页。加入和邀请的按钮在房间页上半部分；退出要先进房间，点右上角「更多」。

## 怎么操作

- 跳到房间页：`scripts/agent/open-link.sh surface/friends`。
- 加入：`phone_run_steps` 依次点 `friends-join-room`、在 `invite-code-field` 输入邀请码、点加入，再用 `wait_for` 等房间页出现。
- 用深链 `oneday://join?code=<邀请码>` 也能加入（`InviteCode.fromDeepLink`），会跳过首次引导。Release 版也认这个链接。

## 验证

| 编号 | 功能 | 入口 | 怎么走 | 屏幕上算成功 | 服务器证据 | 要真人 | 对外写 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F4 | 房间列表 | 底部 tab「房间」 | 打开房间 tab | 我加入和创建的房间都在，卡片有封面 | `sql`：本人 `members` 行数 = 列表里的房间数（加上自己建的） | 否 | 否 |
| F6 | 加入房间 | `friends-join-room` → `invite-code-field` | 输入邀请码 → 加入 | 进入房间页；**记下从点「加入」到出现房间页的秒数** | `room <CODE>`：`members` 多 1 | 否 | 是 |
| F8 | 退出房间 | `room-more` | 更多 → 退出 | 房间从列表消失 | `room <CODE>`：本人的成员和片段行没了 | 否 | **是**（朋友那边看不到我的片段了），只在测试房间做 |
| F20 | 邀请朋友 | `friends-invite` → `friends-invite-room-<CODE>` | 选测试房间 → 复制邀请码 | 显示的 `invite-code` 和房间的邀请码一致，复制后提示已复制 | — | 否 | 否（只复制，不点分享） |

## 容易出错的地方

- 加入房间不等视频下载完就进房间页，片段小图之后才陆续出现。F6 计时看的是进房间页，不是片段加载完。
- 房间页和「我的」是同一个页面组件的两份，同时挂在界面上，没显示的那份对 accessibility 隐藏。`phone_elements` 读到的是当前显示的那份。
- `invite-share` 会弹系统分享面板，选了联系人就是真的发出去了。验证时不要点。

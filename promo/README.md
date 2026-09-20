# 1Day 宣传视频

用代码渲染宣传视频。素材是 iOS 模拟器录屏 + 仓库里已有的演示片，
编排写在 `src/shots.ts`，渲染用 Remotion。

## 出片

```bash
npm install
npm run dev              # 浏览器里预览，改代码即时生效
npm run render:all       # 三条一起
npm run render:solo      # out/1day-solo-xhs.mp4
npm run render:appstore  # out/1day-solo-appstore.mp4
npm run render:friends   # out/1day-friends-xhs.mp4
```

## 三个成片

| 文件 | 尺寸 | 时长 | 去哪 |
| --- | --- | --- | --- |
| `1day-solo-xhs.mp4` | 1080×1920 | 29.2 秒 | 小红书 / 视频号 |
| `1day-solo-appstore.mp4` | 886×1920 | 26.8 秒 | App Store 预览 |
| `1day-friends-xhs.mp4` | 1080×1920 | 31.4 秒 | 小红书 / 视频号 |

单人版讲「一个人用：治拖延，给生活留痕」，双人版讲「和朋友用：跨距离，互相看见」。
两条分工，不让一条片子同时说两件事。

小红书版有品牌底色、手机卡片和中文字幕；App Store 版录屏满屏、无字幕、无外框，
开头那张钩子卡也去掉——苹果要求预览画面基本都是 App 内录制。

双人版不进 App Store：房间用的是本地演示数据，不是真实使用，
片尾也写了「片中房间为演示数据」。

苹果对预览视频的硬性要求：`.mp4`/`.mov`/`.m4v`，最高 30fps，15–30 秒，
每个尺寸最多 3 条，画面必须是设备上录的 App 界面，不能出现手指、
不能出现 App Store 标志、不能画设备外框。小红书版没有这些限制。

## 改内容

全部编排在 [`src/shots.ts`](src/shots.ts)。一个 shot 就是一个镜头：

```ts
{src: 's4-settings.mp4', seconds: 3.8, caption: '题目拆成几个瞬间，一个一个拍'}
```

- `src` — `public/` 里的文件名，`null` 表示纯文字卡
- `seconds` — 这个镜头停留多久，不能超过素材本身长度
- `caption` — 一行中文字幕，只在小红书版显示
- `card` — 用大字卡代替手机画面
- `filmCard` — 16:9 横屏素材，做成卡片居中，不裁成竖屏
- `only` — 只在某个版本出现，例如 `['XHS']`

改完直接 `npm run render:xhs`，不用动别的文件。

## 重新录素材

`record.sh` 录当前已启动的模拟器：

```bash
xcrun simctl boot "iPhone 17 Pro Max"
cd ../ios && xcodegen generate --spec project.yml
xcodebuild -project AISetlog.xcodeproj -scheme AISetlog \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -derivedDataPath /tmp/1day-dd CODE_SIGNING_ALLOWED=NO build
xcrun simctl install booted /tmp/1day-dd/Build/Products/Debug-iphonesimulator/AISetlog.app
./record.sh take-c 90   # 录 90 秒到 raw/take-c.mp4
```

模拟器录屏是变帧率的，直接裁会错位。先转成固定 30fps 再裁：

```bash
ffmpeg -i raw/take-c.mp4 -vf "scale=886:1920:flags=lanczos" -r 30 -fps_mode cfr \
  -an -c:v libx264 -crf 18 -pix_fmt yuv420p raw/take-c-cfr.mp4
ffmpeg -ss 14.4 -i raw/take-c-cfr.mp4 -t 4.6 -an -c:v libx264 -crf 18 \
  -pix_fmt yuv420p -r 30 public/s3-scroll.mp4
```

找剪辑点用缩略图墙，比来回拖进度条快：

```bash
ffmpeg -i raw/take-c-cfr.mp4 -vf "fps=1,scale=150:-1,tile=8x4" -frames:v 1 raw/contact.jpg
```

## 双人房间怎么录

房间演示可以整个预填好、并且不画任何演示外壳，录出来和真实房间没有区别。

```bash
npm run render:demo          # 渲 6 条 960x540 / 3 秒素材到 out/demo/
./stage-clips.sh             # 推进 App 容器的 Documents/demo-clips/
xcrun simctl launch booted com.cassie.AISetlog --args \
  -demoEntries YES \
  -demoRoomTitle "我们的一天" \
  -demoRoomMembers "小蓝,小白" \
  -demoRoomMoments "晨光,午饭,傍晚" \
  -demoRoomClips demo-clips \
  -demoRoomChrome NO
```

然后首页点「房间演示」，进去就是填好的房间：三个瞬间、六个片段、9 秒成片。

启动参数都在 `ios/AISetlog/Services/LocalRoomRuntime.swift`，全部 `#if DEBUG`，
一个都不传时行为和以前完全一样：

| 参数 | 作用 |
| --- | --- |
| `-demoEntries YES` | 首页出现「房间演示」，相机页出现「使用示例片段」 |
| `-demoRoomTitle` | 房间标题，默认「本地房间示例」 |
| `-demoRoomMembers` | 逗号分隔的成员名，同时决定人数（2 或 3） |
| `-demoRoomMoments` | 逗号分隔的瞬间名，每多一个就多一段成片 |
| `-demoRoomClips` | Documents 下的文件夹名，按文件名排序、瞬间优先分配 |
| `-demoRoomChrome NO` | 不画提示条、人数选择器和替换菜单 |

素材必须是 **960×540 横版、3 秒**。两个原因：

- `VideoStitcher.grid` 按片段形状决定布局，竖版左右拼、横版上下拼。
  给竖版会把横图挤进 270 宽的格子里，整屏都是模糊边
- `DemoClipFactory` 横版就是 960×540，手动导入那条路
  (`LocalRoomClipImporter.trim`) 也走 `AVAssetExportPreset960x540` 并只取前 3 秒

## 模拟器的两个坑

**相机是黑的。** 1Day 的拍摄页在模拟器里显示「相机不可用」，
所以录屏只能覆盖计划、设置、我的这些页面。真实拍摄画面要真机录。

**中文打不进去。** 注入的按键只支持 ASCII，拼音候选栏也点不到，
所以「自己写题目 → AI 出题目」这段没法在模拟器里现场演。
两个办法：真机录，或者录生成结果那一屏、把输入的那句话做成字幕叠上去。

## 单人版还缺三段真机素材

模拟器的相机页永远显示「相机不可用」，所以取景、录制、导出这三段只能真机录。
位置已经在 [`src/shots.ts`](src/shots.ts) 里留好了，注释掉的三行就是。

| 文件名 | 内容 | 最短长度 |
| --- | --- | --- |
| `p1-record.mp4` | 相机取景 + 按下录制，让 2 秒倒计时走完 | 6 秒 |
| `p2-review.mp4` | 拍完的回看页，画面里看得到「重拍」 | 4 秒 |
| `p3-save.mp4` | 点保存到相册，等系统提示弹出来 | 3 秒 |

丢进 `public/`，把 `shots.ts` 里那三行的 `//` 去掉，`npm run render:solo`。
时长和字幕都配好了，不用改别的。

单人版会从 29.2 秒变成 39.7 秒——小红书没问题，但 App Store 版超了 30 秒上限，
到时候把 `s3-scroll` 和 `s4-settings` 各砍 2 秒就行。

## 真机录屏（画质更好，App Store 更推荐）

1. iPhone 连 Mac，打开 QuickTime Player → 文件 → 新建影片录制 → 摄像头选 iPhone
2. iPhone 设置 → 勿扰模式开，通知全关，电量充满（状态栏会入镜）
3. 录之前先把要演的流程走两遍，手指动作慢一点
4. 导出后放进 `public/`，在 `shots.ts` 里换掉对应的 `src`

真机录出来是 1320×2868，和模拟器同一个比例，`scale=886:1920` 直接能用。

## 已知可以再改的地方

- 设置页那两个镜头顶部有一条灰色状态栏（sheet 弹出时系统压暗的效果）
- 没有配乐。加的话在 `src/Promo.tsx` 里放一个 `<Audio>`，
  注意商用授权；`mluedke2/app-preview-music` 有一批免费的 15–30 秒片段
- 「自己写题目 → AI 出题目」这段还没进片子，它是 1.2 版最值得讲的功能

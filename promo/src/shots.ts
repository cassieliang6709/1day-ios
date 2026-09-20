import {FPS} from './theme';

export type Shot = {
  /** File in public/, or null for a pure text card. */
  src: string | null;
  /** Seconds this shot stays on screen. Must be <= the clip's own length. */
  seconds: number;
  /** Caption shown over the shot. Keep it to one short line. */
  caption?: string;
  /** Big centred text instead of a phone (title / outro cards). */
  card?: {title: string; sub?: string; note?: string};
  /** Landscape 16:9 clip shown as a card instead of inside a phone. */
  filmCard?: boolean;
  /** Drop this shot from the App Store cut. */
  xhsOnly?: boolean;
};

export const sec = (s: number) => Math.round(s * FPS);

/**
 * 单人版 — 「一个人用：治拖延，给生活留痕」.
 *
 * No finished film yet: the Simulator has no camera, so the recorder, the
 * review screen and the export are the three shots that have to come off a
 * real phone. Everything here is a screen a solo user actually sees first.
 */
export const soloShots: Shot[] = [
  {
    src: null,
    seconds: 2.4,
    card: {title: '一天过完了，\n还是想不起做过什么'},
    xhsOnly: true,
  },
  {src: 'o1-onboard.mp4', seconds: 4.0, caption: '3 个两秒瞬间，一支属于你的短片'},
  {src: 'o2-start.mp4', seconds: 3.0, caption: '选一个故事，它替你把一天拆开'},
  {src: 's2-plan.mp4', seconds: 3.2, caption: '不知道拍什么？题目它来出'},
  {src: 's3-scroll.mp4', seconds: 4.2, caption: '一日 · 七日 · 按时间 · 自己写'},
  {src: 's4-settings.mp4', seconds: 4.0, caption: '想起哪个拍哪个，随时重拍'},
  {src: 's5-duration.mp4', seconds: 2.4, caption: '每段 2 秒、5 秒或 10 秒'},

  // ---- 真机素材的位置 -------------------------------------------------
  // 这三段模拟器拍不了：相机页在模拟器里永远是「相机不可用」，所以取景、
  // 录制和导出只能在真机上录。把文件丢进 public/ 用这三个名字，然后把下面
  // 三行的注释去掉——不用改别的，时长和字幕都已经配好了。
  //
  //   p1-record.mp4   取景 + 按下录制，2 秒倒计时走完   ≥6 秒
  //   p2-review.mp4   拍完的回看页，看得到「重拍」       ≥4 秒
  //   p3-save.mp4     点保存到相册，系统提示弹出来       ≥3 秒
  //
  // 竖屏录，开勿扰关通知，电量充满（状态栏会入镜）。QuickTime 影片录制
  // 比手机自带录屏好，后者会把状态栏时间胶囊染红。
  //
  // {src: 'p1-record.mp4', seconds: 4.5, caption: '对着想记住的东西，按一下'},
  // {src: 'p2-review.mp4', seconds: 3.0, caption: '不满意就重拍，没人看得到'},
  // {src: 'p3-save.mp4', seconds: 3.0, caption: '存进相册，或者直接发出去'},
  // ---------------------------------------------------------------------

  {src: 's1-home.mp4', seconds: 3.0, caption: '不用注册，全部存在你的 iPhone 上'},
  {
    src: null,
    seconds: 3.0,
    card: {title: '1Day', sub: 'App Store 搜「1 Day」'},
  },
];

/**
 * 双人版 — 「和朋友用：跨距离，互相看见」. 小红书 only.
 *
 * The room is the app's own local demo: production room, chat and compositor,
 * with sample clips standing in for two people's footage. That is worth saying
 * out loud on the end card rather than hoping nobody asks.
 */
export const friendsShots: Shot[] = [
  {src: null, seconds: 2.4, card: {title: '各自在不同的生活里'}},
  {src: 's6-friends.mp4', seconds: 3.5, caption: '6 位邀请码，叫上朋友一起拍'},
  {src: 'r1-room.mp4', seconds: 4.0, caption: '同一个房间，各拍各的'},
  {src: 'r2-scroll.mp4', seconds: 5.0, caption: '晨光 · 午饭 · 傍晚'},
  {src: 'r3-render.mp4', seconds: 4.0, caption: '拍完，自动缝成一部'},
  {src: 'r4-ready.mp4', seconds: 3.5, caption: '存进相册，或者直接发出去'},
  {src: 'r5-play.mp4', seconds: 6.0, caption: '几秒的碎片，也能互相看见'},
  {
    src: null,
    seconds: 3.0,
    card: {
      title: '1Day',
      sub: 'App Store 搜「1 Day」',
      note: '片中房间为演示数据',
    },
  },
];

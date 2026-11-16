import {FPS} from './theme';

export type Shot = {
  src: string | null;
  seconds: number;
  caption?: string;
  card?: {title: string; sub?: string; note?: string};
  filmCard?: boolean;
  xhsOnly?: boolean;
};

export const sec = (s: number) => Math.round(s * FPS);

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


  {src: 's1-home.mp4', seconds: 3.0, caption: '不用注册，全部存在你的 iPhone 上'},
  {
    src: null,
    seconds: 3.0,
    card: {title: '1Day', sub: 'App Store 搜「1 Day」'},
  },
];

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

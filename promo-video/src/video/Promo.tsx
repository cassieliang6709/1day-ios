import React from 'react';
import {
  AbsoluteFill,
  Easing,
  Img,
  Sequence,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {Audio, Video} from '@remotion/media';

type Variant = {
  id: string;
  duration: number;
  eyebrow: string;
  title: [string, string];
  thesis: string;
  beats: Array<{at: number; title: string; copy: string; screen: string}>;
  closing: string;
  accent: string;
};

export const promoVariants: Variant[] = [
  {
    id: 'FriendsTogether',
    duration: 24,
    eyebrow: '1DAY · TOGETHER',
    title: ['不在同一个城市', '也能一起记录一天'],
    thesis: '你拍早餐，我拍晚霞。几秒的碎片，拼成我们的一天。',
    beats: [
      {at: 5, title: '一个邀请码', copy: '把朋友拉进同一天', screen: 'friends'},
      {at: 10, title: '各自拍几秒', copy: '生活不用特别，真实就好', screen: 'moments'},
      {at: 15, title: '轻轻回应', copy: '表情、短评，也可以进入成片', screen: 'film'},
    ],
    closing: '就算生活在远方，也能互相看见。',
    accent: '#68D6FF',
  },
  {
    id: 'NoPressureVlog',
    duration: 21,
    eyebrow: '1DAY · SOLO',
    title: ['没有值得拍的一天？', '先拍 2 秒再说'],
    thesis: '不用想脚本，不用拍很久。一个提示，带你留住一个瞬间。',
    beats: [
      {at: 5, title: '选一个主题', copy: '今天，想怎么生活？', screen: 'themes'},
      {at: 10, title: '2s / 5s / 10s', copy: '短到没有拖延的理由', screen: 'home'},
      {at: 15, title: '自由拍，自由重来', copy: '顺序由你，舒服最重要', screen: 'moments'},
    ],
    closing: '普通的一天，也值得有片尾。',
    accent: '#89A7FF',
  },
  {
    id: 'SevenDayChallenge',
    duration: 22,
    eyebrow: '1DAY · 7 DAYS',
    title: ['想坚持一件事', '把它拍成七天'],
    thesis: '输入目标，拆成每天能完成的一小步。进度不只被打卡，也被看见。',
    beats: [
      {at: 5, title: '从一句目标开始', copy: 'AI 给出可执行分镜与小任务', screen: 'themes'},
      {at: 10, title: '每天只拍一个片段', copy: '一点点，也算向前', screen: 'moments'},
      {at: 16, title: '七天后得到一部片', copy: '成长终于有了画面', screen: 'film'},
    ],
    closing: '不是逼自己坚持，是看见自己正在改变。',
    accent: '#A58BFF',
  },
  {
    id: 'FilmMadeOnIPhone',
    duration: 20,
    eyebrow: '1DAY · ON DEVICE',
    title: ['你负责生活', '1Day 负责成片'],
    thesis: '方向、声音、字幕、转场，自动整理。完整影片在 iPhone 本地生成。',
    beats: [
      {at: 4, title: '零手动剪辑', copy: '不同画面方向，自动统一', screen: 'moments'},
      {at: 9, title: '故事自然连起来', copy: '标题、字幕、评论与转场', screen: 'film'},
      {at: 14, title: '保存或分享', copy: '相册与 MP4，随你带走', screen: 'hero'},
    ],
    closing: '拍完这一天，就拥有这一天。',
    accent: '#44E0C1',
  },
  {
    id: 'IActuallyBuiltIt',
    duration: 25,
    eyebrow: 'MADE BY CASSIE · VERSION 1.3',
    title: ['我真的做出来了', '一款和朋友共拍 vlog 的 App'],
    thesis: '找工作的间隙，我把低落时救过自己的那种连接，做成了 1Day。',
    beats: [
      {at: 6, title: '从一个真实需要开始', copy: '异地朋友互发碎片，让普通生活重新发亮', screen: 'home'},
      {at: 12, title: '一个人，也能完成', copy: '产品、设计、iOS、CloudKit 与成片系统', screen: 'themes'},
      {at: 18, title: '现在，1.3 已上架', copy: '它还在长大，也需要你的视角', screen: 'film'},
    ],
    closing: '1Day · 在各自的生活里，互相看见。',
    accent: '#68D6FF',
  },
];

const screens: Record<string, string> = {
  hero: 'screens/01-hero.png',
  home: 'screens/02-home.png',
  themes: 'screens/03-themes.png',
  moments: 'screens/04-moments.png',
  film: 'screens/05-film.png',
  friends: 'screens/friends.png',
};

const clamp = {extrapolateLeft: 'clamp' as const, extrapolateRight: 'clamp' as const};

const Background: React.FC<{accent: string}> = ({accent}) => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{background: '#061A36', overflow: 'hidden'}}>
      <div style={{position: 'absolute', inset: -220, background: `radial-gradient(circle at ${40 + frame * 0.025}% 26%, ${accent}42 0, transparent 34%), radial-gradient(circle at 72% 88%, #345BFF24 0, transparent 30%)`}} />
      <div style={{position: 'absolute', inset: 0, opacity: 0.16, backgroundImage: 'linear-gradient(#ffffff10 1px, transparent 1px), linear-gradient(90deg, #ffffff10 1px, transparent 1px)', backgroundSize: '72px 72px'}} />
      {Array.from({length: 18}).map((_, index) => (
        <div key={index} style={{position: 'absolute', width: 3, height: 3, borderRadius: 9, background: '#CDE5FF', left: `${(index * 37) % 100}%`, top: `${(index * 23) % 100}%`, opacity: interpolate(frame, [index * 3, index * 3 + 20], [0.08, 0.42], clamp)}} />
      ))}
    </AbsoluteFill>
  );
};

const Wordmark: React.FC<{light?: boolean}> = ({light = true}) => (
  <div style={{display: 'flex', alignItems: 'center', gap: 15, color: light ? '#F7FBFF' : '#071A35', fontFamily: '-apple-system, BlinkMacSystemFont, PingFang SC, sans-serif', fontSize: 30, fontWeight: 750, letterSpacing: -1}}>
    <Img src={staticFile('brand/icon.png')} style={{width: 54, height: 54, borderRadius: 14}} />
    1Day
  </div>
);

const Phone: React.FC<{screen: string; accent: string; side?: 'left' | 'right'}> = ({screen, accent, side = 'right'}) => {
  const frame = useCurrentFrame();
  return (
    <div style={{position: 'absolute', width: 490, height: 1064, right: side === 'right' ? 70 : undefined, left: side === 'left' ? 70 : undefined, top: 205, borderRadius: 72, padding: 15, background: 'linear-gradient(145deg,#EDF5FF,#A8BCD4 46%,#FFFFFF)', boxShadow: `0 70px 140px #000B, 0 0 90px ${accent}33`, rotate: side === 'right' ? '-4deg' : '4deg', translate: `0 ${interpolate(frame, [0, 120], [60, -8], {...clamp, easing: Easing.out(Easing.cubic)})}px`, scale: interpolate(frame, [0, 32], [0.92, 1], {...clamp, easing: Easing.out(Easing.cubic)})}}>
      <div style={{position: 'absolute', zIndex: 3, width: 145, height: 38, background: '#05070B', borderRadius: 30, left: '50%', translate: '-50% 0', top: 26}} />
      <Img src={staticFile(screens[screen])} style={{width: '100%', height: '100%', objectFit: 'cover', borderRadius: 58}} />
      <div style={{position: 'absolute', inset: 15, borderRadius: 58, boxShadow: 'inset 0 0 0 1px #FFFFFF99', pointerEvents: 'none'}} />
    </div>
  );
};

const Opening: React.FC<{variant: Variant}> = ({variant}) => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{padding: '105px 76px', color: '#F8FBFF', fontFamily: '-apple-system, BlinkMacSystemFont, PingFang SC, sans-serif'}}>
      <div style={{opacity: interpolate(frame, [0, 18], [0, 1], clamp)}}><Wordmark /></div>
      <div style={{marginTop: 165, fontSize: 21, fontWeight: 760, letterSpacing: 4.5, color: variant.accent, opacity: interpolate(frame, [9, 28], [0, 1], clamp)}}>{variant.eyebrow}</div>
      <div style={{marginTop: 30, fontSize: 88, lineHeight: 1.08, fontWeight: 820, letterSpacing: -5.5, maxWidth: 920}}>
        {variant.title.map((line, i) => (
          <div key={line} style={{opacity: interpolate(frame, [18 + i * 7, 38 + i * 7], [0, 1], clamp), translate: `${interpolate(frame, [18 + i * 7, 42 + i * 7], [42, 0], {...clamp, easing: Easing.out(Easing.cubic)})}px 0`}}>{line}</div>
        ))}
      </div>
      <div style={{width: interpolate(frame, [36, 62], [0, 780], {...clamp, easing: Easing.out(Easing.cubic)}), height: 3, background: `linear-gradient(90deg,${variant.accent},transparent)`, marginTop: 43}} />
      <div style={{marginTop: 36, fontSize: 33, lineHeight: 1.5, fontWeight: 480, color: '#D4E5F8', maxWidth: 850, opacity: interpolate(frame, [42, 65], [0, 1], clamp)}}>{variant.thesis}</div>
    </AbsoluteFill>
  );
};

const Beat: React.FC<{variant: Variant; beat: Variant['beats'][number]; index: number}> = ({variant, beat, index}) => {
  const frame = useCurrentFrame();
  const local = frame;
  return (
    <AbsoluteFill style={{fontFamily: '-apple-system, BlinkMacSystemFont, PingFang SC, sans-serif', color: '#F8FBFF'}}>
      <Phone screen={beat.screen} accent={variant.accent} side={index % 2 === 0 ? 'right' : 'left'} />
      <div style={{position: 'absolute', top: 300, left: index % 2 === 0 ? 72 : 620, width: 400, opacity: interpolate(local, [0, 18, 115, 145], [0, 1, 1, 0], clamp), translate: `${interpolate(local, [0, 24], [index % 2 === 0 ? -32 : 32, 0], {...clamp, easing: Easing.out(Easing.cubic)})}px 0`}}>
        <div style={{fontSize: 21, letterSpacing: 4, color: variant.accent, fontWeight: 760}}>0{index + 1}</div>
        <div style={{fontSize: 61, lineHeight: 1.12, fontWeight: 800, letterSpacing: -3, marginTop: 22}}>{beat.title}</div>
        <div style={{fontSize: 28, lineHeight: 1.55, color: '#BCD2EA', marginTop: 26}}>{beat.copy}</div>
      </div>
    </AbsoluteFill>
  );
};

const Closing: React.FC<{variant: Variant}> = ({variant}) => {
  const frame = useCurrentFrame();
  const start = (variant.duration - 4) * 30;
  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', color: '#F8FBFF', fontFamily: '-apple-system, BlinkMacSystemFont, PingFang SC, sans-serif', textAlign: 'center', opacity: interpolate(frame, [start, start + 22], [0, 1], clamp)}}>
      <Img src={staticFile('brand/icon.png')} style={{width: 142, height: 142, borderRadius: 36, boxShadow: `0 30px 90px ${variant.accent}55`, scale: interpolate(frame, [start, start + 28], [0.72, 1], {...clamp, easing: Easing.out(Easing.back(1.4))})}} />
      <div style={{fontSize: 52, fontWeight: 760, lineHeight: 1.25, maxWidth: 880, marginTop: 54, letterSpacing: -2}}>{variant.closing}</div>
      <div style={{fontSize: 25, color: variant.accent, letterSpacing: 5, fontWeight: 720, marginTop: 34}}>1DAY · APP STORE</div>
    </AbsoluteFill>
  );
};

export const Promo: React.FC<{variantId: string}> = ({variantId}) => {
  const variant = promoVariants.find((item) => item.id === variantId) ?? promoVariants[0];
  const {fps} = useVideoConfig();
  return (
    <AbsoluteFill>
      <Background accent={variant.accent} />
      <Sequence durationInFrames={5 * fps}><Opening variant={variant} /></Sequence>
      {variant.beats.map((beat, index) => {
        const nextStart = variant.beats[index + 1]?.at ?? variant.duration - 4;
        return (
          <Sequence key={beat.title} from={beat.at * fps} durationInFrames={(nextStart - beat.at) * fps}>
            <Beat variant={variant} beat={beat} index={index} />
          </Sequence>
        );
      })}
      <Closing variant={variant} />
      <Audio src={staticFile('audio/ambient.mp3')} volume={0.18} loop />
      {variant.beats.map((beat) => <Audio key={beat.at} src={staticFile('audio/whoosh.wav')} from={beat.at * fps} volume={0.42} />)}
      <Audio src={staticFile('audio/chime.wav')} from={(variant.duration - 4) * fps} volume={0.5} />
    </AbsoluteFill>
  );
};

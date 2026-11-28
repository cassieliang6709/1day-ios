import { useEffect, useState } from 'react';
import { AppleLogo, ArrowRight, Camera, CameraRotate, CheckCircle, Clock, FilmStrip, MusicNotes, Smiley, UsersThree, VideoCamera } from '@phosphor-icons/react';

export const APP_STORE_URL = 'https://apps.apple.com/cn/app/1-day/id6794565199?uo=4';
export const TESTFLIGHT_URL = 'https://testflight.apple.com/join/cRQm6Va2';






export const metadata = {
  zh: { title: '1Day — 每天拍几秒，攒成 vlog', description: '用相机随手记录，在房间里分享日常，也留住自己的一天。挑选喜欢的片段，拼成一支 vlog。', privacyTitle: '1Day 视频日记隐私政策', privacyDescription: '了解 1Day 如何处理单人故事、共享房间和可选提示建议的数据。', og: '/assets/og-zh.png' },
  en: { title: '1Day — Film a few seconds a day, make it a vlog', description: 'Capture everyday moments, share them in a room, and keep your own timeline. Choose your favorite clips and turn them into a vlog.', privacyTitle: '1Day Video Diary Privacy Policy', privacyDescription: 'Learn how 1Day handles data for solo stories, shared rooms, and optional prompt suggestions.', og: '/assets/og-en.png' },
};

export function pageMetadata(locale, isPrivacy = false) {
  const base = metadata[locale];
  return isPrivacy ? { ...base, title: base.privacyTitle, description: base.privacyDescription } : base;
}

const copy = {
  zh: {
    nav: ['怎么用', '隐私'], storeAria: '在 App Store 下载 1Day', storeLabel: '下载 1Day', storeCompact: 'App Store', betaTitle: '体验 1.5 新版 · TestFlight', betaScan: '本页展示 1.5 开发版，App Store 版本可能有所不同。扫码体验公测。', betaButton: '加入 TestFlight 公测', betaQrAlt: '1Day TestFlight 公测二维码', eyebrow: '日日是好日',
    title: <>每天拍几秒，<br /><em>攒成你的 vlog。</em></>, lede: '随手拍下日常，留在自己的时间线里，也可以分享到房间。看看朋友这天怎么过，再把喜欢的片段拼成一支 vlog。', learn: '看看怎么用',
    footer: ['隐私政策', 'App Store', '支持'], portfolio: 'Cassie 的个人主页', back: '← 返回 1Day', privacyTitle: '隐私政策', privacyDate: '更新日期：2026 年 11 月 14 日',
    heroCaption: '示意画面 · 按 1.5 开发版界面绘制，成员为示例', heroAria: '1Day 界面示意：拍下来、分享到房间、拼成 vlog',
    phone: { steps: ['拍下来', '分享到房间', '拼成 vlog'], chips: [['DV 画面，带上日期', '随手拍几秒'], ['今天的心情，点一下就记', '谁拍了，一眼看到'], ['原声和音乐混在一起', '在手机上生成']], tabs: ['相机', '房间'], mode: '自由拍摄', greeting: '下午好', today: '11月18日 周三', moodTitle: '今天的心情', moods: ['开心', '平静', '累', '难过', '生气'], roomsTitle: '房间', join: '加入', newRoom: '新建房间', cards: [['我的', '你 · 12:30'], ['我们的周六', '小白 · 12:15']], members: ['小白', '你'], memberInitial: '小', whoIn: '成片里有谁', clips: '2 段', sound: '声音', soundOptions: ['原声', '音乐', '混合'] },
    whyLabel: '为什么做 1Day', whyTitle: '一天过去了，总该留下点什么', beforeLabel: '以前', nowLabel: '现在',
    before: ['想记录，又不知道拍什么', '拍了一堆，散在相册里找不到', '朋友这天怎么过的，只能等他发动态'],
    now: [['随手拍几秒', '不用想好拍什么，点相机就拍。片段按天留在自己的时间线里'], ['分享到房间', '一个房间最多 6 人，点头像连着看朋友的一天'], ['拼成一支 vlog', '挑几段排好顺序，在手机上生成。过去的某一天也能生成回顾']],
    moreLabel: '还有这些', moreTitle: '拍得更像你的一天',
    features: [['DV 日期画面', '画面像老式 DV，带上拍摄日期。'], ['前后双摄', '支持的 iPhone 可以前后镜头一起拍。'], ['心情和计划', '每天记一个心情，写下今天的计划。'], ['原声和音乐', 'vlog 用原声、音乐，或者两个混在一起。']],
    faqLabel: '隐私', faqTitle: '你拍的，先留在你手机上',
    faq: [['片段存在哪？', '个人片段保存在你的设备上。只有你选择分享到房间的片段，才会上传到 1Day 的云端服务（Cloudflare R2）。'], ['分享到房间，谁能看到？', '房间里的成员。房间码是邀请方式，不是密码：收到房间码的人可以加入房间，看到里面分享的内容。'], ['vlog 在哪生成？', '在你的手机上生成。成片只有在你选择保存或分享时，才会离开 App。'], ['用一句话生成拍摄提示，会发送什么？', '只发送你写的那句话、提示数量、语言和一个用于限流的随机标识符，由 DeepSeek 生成提示。视频和照片不会发送。这个功能可以不用。']],
    faqMore: '看完整隐私政策',
    ctaTitle: '今天，拍几秒吧。', ctaText: 'iPhone 上可用。也可以加入 TestFlight，先体验 1.5 新版。',
    privacySections: [
      ['概览', '1Day 帮你记录短视频瞬间，并将它们编成一支影片。单人故事的片段和故事数据保存在你的设备上。共享房间使用 1Day 的云端服务，支持 Apple 或 Google 登录。'],
      ['我们处理的信息', '应用可能会处理Apple 或 Google 登录提供的名称与账号标识符、挑战详情、房间成员、文字说明，以及你选择上传到共享房间的视频片段。相机、麦克风和照片图库仅在你授权后使用。'],
      ['存储与分享', '单人故事数据和片段存储在你的设备上。共享房间的数据存储于 Cloudflare D1，你选择上传的片段和头像存储于 Cloudflare R2。房间码是邀请方式，而非密码；收到房间码的人可以加入并访问其中的共享内容。成片只会在你选择保存或分享时离开应用。'],
      ['可选的提示建议', '如果你选择用一句话生成拍摄提示，应用会向 1Day 的提示服务发送这句话、所需提示数量、所选语言和一个随机的安装标识符（用于限流）。该服务将你的这句话和生成提示所需的系统指令发送给 DeepSeek API。它不会发送你的影片、照片或安装标识符给 DeepSeek。此功能是可选的；你也可以自己写提示，或按时间记录。'],
    ],
  },
  en: {
    nav: ['How it works', 'Privacy'], storeAria: 'Download 1Day on the App Store', storeLabel: 'Get 1Day', storeCompact: 'App Store', betaTitle: 'Try 1.5 · TestFlight beta', betaScan: 'This page shows the 1.5 development build. The App Store version may differ. Scan to try the beta.', betaButton: 'Join the TestFlight beta', betaQrAlt: '1Day TestFlight beta QR code', eyebrow: 'Every day is a good day',
    title: <>Film a few seconds a day.<br /><em>Make it a vlog.</em></>, lede: 'Capture everyday moments for your own timeline or share them in a room. See a little of your friends’ day, then turn your favorite clips into a vlog.', learn: 'See how it works',
    footer: ['Privacy Policy', 'App Store', 'Support'], portfolio: 'Made by Cassie', back: '← Back to 1Day', privacyTitle: 'Privacy Policy', privacyDate: 'Updated November 14, 2026',
    heroCaption: 'Illustration · drawn from the 1.5 development build, demo members', heroAria: '1Day UI illustration: film it, share to a room, make a vlog',
    phone: { steps: ['Film it', 'Share to a room', 'Make a vlog'], chips: [['Camcorder look, dated', 'Film a few seconds'], ['Log today’s mood in one tap', 'See who filmed at a glance'], ['Original audio plus music', 'Made on your phone']], tabs: ['Camera', 'Rooms'], mode: 'Free-form', greeting: 'Good afternoon', today: 'Wed, Nov 18', moodTitle: 'Today’s mood', moods: ['Happy', 'Calm', 'Tired', 'Sad', 'Angry'], roomsTitle: 'Rooms', join: 'Join', newRoom: 'New room', cards: [['Mine', 'You · 12:30'], ['Our Saturday', 'Mia · 12:15']], members: ['Mia', 'You'], memberInitial: 'M', whoIn: 'Who’s in it', clips: '2 clips', sound: 'Sound', soundOptions: ['Original', 'Music', 'Mix'] },
    whyLabel: 'Why 1Day', whyTitle: 'A day goes by. Something should stay.', beforeLabel: 'Before', nowLabel: 'Now',
    before: ['You want to film, but don’t know what', 'Clips pile up, lost in your camera roll', 'You only see a friend’s day if they post it'],
    now: [['Film a few seconds', 'No plan needed. Clips stay in your own timeline, by day.'], ['Share to a room', 'Up to 6 people. Tap a face to watch a friend’s day.'], ['Turn them into a vlog', 'Pick and order a few clips, made on your phone. Recap any past day too.']],
    moreLabel: 'And also', moreTitle: 'Make it look like your day',
    features: [['Dated camcorder look', 'Footage looks like an old camcorder, with the date on screen.'], ['Front and back cameras', 'Film both at once on supported iPhones.'], ['Mood and plans', 'Log a mood each day and write down today’s plan.'], ['Original audio and music', 'Use the original sound, music, or a mix of both.']],
    faqLabel: 'Privacy', faqTitle: 'What you film stays on your phone first',
    faq: [['Where are my clips stored?', 'Personal clips stay on your device. Only clips you choose to share in a room are uploaded to 1Day’s cloud service (Cloudflare R2).'], ['Who can see clips I share in a room?', 'Members of that room. A room code is an invitation, not a password: anyone who receives it can join and see what is shared there.'], ['Where is the vlog made?', 'On your phone. A finished film leaves the app only when you choose to save or share it.'], ['What is sent when I generate filming prompts?', 'Only your sentence, the prompt count, your language, and a random identifier for rate limiting. DeepSeek generates the prompts. Videos and photos are never sent. The feature is optional.']],
    faqMore: 'Read the full privacy policy',
    ctaTitle: 'Film a few seconds today.', ctaText: 'Available on iPhone. Or join TestFlight to try 1.5 early.',
    privacySections: [
      ['Overview', '1Day helps you record short video moments and assemble them into a film. Solo story data and footage stay on your device. Shared rooms use 1Day’s cloud service and support Apple or Google sign-in.'],
      ['Information we handle', 'The app may handle the name and stable identifier provided through Apple or Google sign-in, challenge details, room membership, captions, and video clips you choose to upload to a shared room. Camera, microphone, and photo-library access are used only after you grant permission.'],
      ['Storage and sharing', 'Solo story data and clips are stored on your device. Shared-room data is stored in Cloudflare D1. Clips and avatars you choose to upload are stored in Cloudflare R2. A room code is an invitation, not a password: people who receive it can join that room and access its shared content. Finished films leave the app only when you choose to save or share them.'],
      ['Optional prompt suggestions', 'If you choose to generate filming prompts from one sentence, the app sends that sentence, the requested prompt count, selected language, and a random installation identifier for rate limiting to 1Day’s prompt service. The service sends your sentence and the system instructions needed to generate prompts to the DeepSeek API. It does not send your videos, photos, or installation identifier to DeepSeek. This feature is optional: you can write prompts yourself or record by time.'],
    ],
  },
};

function StoreButton({ locale, compact = false }) { const t = copy[locale]; return <a className={`store-button ${compact ? 'compact' : ''}`} href={APP_STORE_URL} target="_blank" rel="noreferrer" aria-label={t.storeAria}><AppleLogo weight="fill" /><span>{compact ? t.storeCompact : t.storeLabel}</span></a>; }
function BetaInvite({ locale }) { const t = copy[locale]; return <div className="beta-invite"><img className="beta-qr" width="96" height="96" src="/assets/testflight-qr.png" alt={t.betaQrAlt} /><p><strong>{t.betaTitle}</strong><span>{t.betaScan}</span></p><a className="beta-button" href={TESTFLIGHT_URL} target="_blank" rel="noreferrer">{t.betaButton} <ArrowRight /></a></div>; }
// Hero phone drawn in HTML/CSS (approved 2026-11-18). It is an illustration of the 1.5 UI, so keep it in sync with the App and keep the caption saying so.
const moodFaces = {
  smile: <><circle cx="8.5" cy="9" r="1.1" /><circle cx="15.5" cy="9" r="1.1" /><path d="M10 12.2q2 1.6 4 0" /></>,
  calm: <><path d="M7.3 9.2q1.2 1 2.4 0M14.3 9.2q1.2 1 2.4 0M10.5 12.6q1.5 .9 3 0" /></>,
  happy: <><path d="M7.3 9.6q1.2-1.2 2.4 0M14.3 9.6q1.2-1.2 2.4 0" /><path className="fill" d="M9.4 11.6h5.2q-.4 2.6-2.6 2.6t-2.6-2.6z" /></>,
  tired: <><path d="M7.3 9.4h2.4M14.3 9.4h2.4M10.8 12.8h2.4M18 3.5h2l-2 2h2" /></>,
  sad: <><circle cx="8.5" cy="9" r="1.1" /><circle cx="15.5" cy="9" r="1.1" /><path d="M10 13.4q2-1.4 4 0" /></>,
  angry: <><path d="M7 7.6l2.6 1.2M17 7.6l-2.6 1.2" /><circle cx="8.6" cy="10" r="1" /><circle cx="15.4" cy="10" r="1" /><path d="M10 13.6q2-1.2 4 0" /></>,
};
function Mascot({ size = 28, mood = 'smile', tone = '' }) {
  return <span className={`ph-mascot ${tone}`} style={{ width: size, height: size * .86 }} aria-hidden="true"><svg viewBox="0 0 24 20">{moodFaces[mood] ?? moodFaces.smile}</svg></span>;
}
// In-screen controls are mouse/touch shortcuts only (tabIndex -1, inside aria-hidden); the step buttons below the phone are the accessible way to switch.
function PhoneTabBar({ t, active, go }) {
  return <div className="ph-tabbar">{t.phone.tabs.map((label, index) => { const Icon = index === 0 ? Camera : UsersThree; return <button type="button" tabIndex={-1} key={label} className={index === active ? 'on' : ''} onClick={() => go(index)}><Icon weight={index === active ? 'fill' : 'regular'} />{label}</button>; })}</div>;
}
function CameraScene({ t, go }) {
  return <div className="ph-cam">
    <div className="ph-cam-head"><span className="ph-close">×</span><div><Mascot size={30} /><b>1day</b></div><small>{t.phone.mode}</small></div>
    <div className="ph-viewfinder"><i className="ph-sun" /><i className="ph-ground" /><span className="ph-corner tl" /><span className="ph-corner tr" /><span className="ph-corner bl" /><span className="ph-corner br" /><span className="ph-rec"><i />REC</span><span className="ph-date">NOV 18 2026<br />2:06 PM</span></div>
    <div className="ph-cam-controls"><span className="ph-round" /><button type="button" tabIndex={-1} className="ph-shutter ph-tap" onClick={() => go(1)}><i /></button><span className="ph-round" /></div>
    <PhoneTabBar t={t} active={0} go={go} />
  </div>;
}
const moods = [['happy', 'm-happy'], ['calm', 'm-calm'], ['tired', 'm-tired'], ['sad', 'm-sad'], ['angry', 'm-angry']];
function DvCover({ variant, date }) {
  return <div className={`ph-dv ${variant}`}><span className="ph-corner tl" /><span className="ph-corner tr" /><span className="ph-corner bl" /><span className="ph-corner br" /><span className="ph-rec"><i />REC</span><span className="ph-date">{date}</span></div>;
}
function HomeScene({ t, go }) {
  const p = t.phone;
  return <div className="ph-home">
    <div className="ph-greet"><span className="ph-avatar lg a2"><Mascot size={20} /></span><span><b>{p.greeting}</b><small>{p.today}</small></span></div>
    <div className="ph-mood"><small>{p.moodTitle}</small><div>{moods.map(([face, tone], index) => <span key={face} className={index === 0 ? 'on' : ''}><Mascot size={30} mood={face} tone={tone} /><em>{p.moods[index]}</em></span>)}</div></div>
    <div className="ph-rooms-head"><h4>{p.roomsTitle}</h4><span className="ph-pill">{p.join}</span><span className="ph-pill yellow">+ {p.newRoom}</span></div>
    <div className="ph-room-grid">{p.cards.map(([name, meta], index) => <button type="button" tabIndex={-1} key={name} className="ph-room-card ph-tap" onClick={() => go(2)}><DvCover variant={`v${index + 1}`} date={<>NOV 18 2026<br />{index === 0 ? '12:30 PM' : '12:15 PM'}</>} /><span className="ph-room-faces">{index === 0 ? <span className="ph-avatar sm a2"><Mascot size={10} /></span> : <><span className="ph-avatar sm a1">{p.memberInitial}</span><span className="ph-avatar sm a2"><Mascot size={10} /></span></>}</span><span className="ph-room-meta"><b>{name}</b><small>{meta}</small></span></button>)}</div>
    <PhoneTabBar t={t} active={1} go={go} />
  </div>;
}
function FilmScene({ t, go }) {
  const p = t.phone;
  return <div className="ph-film">
    <div className="ph-top-row"><button type="button" tabIndex={-1} className="ph-icon-btn ph-tap" onClick={() => go(1)}>‹</button></div>
    <div className="ph-player"><i className="f1" /><i className="f2" /><i className="f3" /><span className="ph-play">▶</span><div className="ph-progress"><i /></div></div>
    <div className="ph-card"><small>{p.whoIn}</small><div className="ph-who">{p.members.map((name, index) => <span key={name}><span className={`ph-avatar a${index + 1}`}>{index === 0 ? p.memberInitial : <Mascot size={14} />}</span><b>{name}</b><em>{p.clips}</em></span>)}</div></div>
    <div className="ph-card"><small>{p.sound}</small><div className="ph-seg">{p.soundOptions.map((label, index) => <span key={label} className={index === 2 ? 'on' : ''}>{label}</span>)}</div></div>
  </div>;
}
function HeroPhone({ t }) {
  const [scene, setScene] = useState(0); const [auto, setAuto] = useState(true);
  useEffect(() => {
    if (!auto || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return undefined;
    const timer = setInterval(() => setScene((current) => (current + 1) % 3), 4500);
    return () => clearInterval(timer);
  }, [auto]);
  const go = (index) => { setScene(index); setAuto(false); }; const chips = t.phone.chips[scene]; const [ChipA, ChipB] = [[VideoCamera, Clock], [Smiley, UsersThree], [MusicNotes, CheckCircle]][scene]; const scenes = [CameraScene, HomeScene, FilmScene];
  return <figure className="hero-phone" aria-label={t.heroAria}>
    <div className="hero-blob" aria-hidden="true" />
    <div className="phone-frame" aria-hidden="true"><div className="ph-screen"><span className="ph-island" /><div className="ph-status"><b>9:41</b><span><i className="ph-signal" /><i className="ph-battery" /></span></div>{scenes.map((Scene, index) => <section key={index} className={`ph-scene ${index === scene ? 'on' : ''}`}><Scene t={t} go={go} /></section>)}</div></div>
    <span key={`a${scene}`} className="hero-chip chip-top"><ChipA weight="fill" aria-hidden="true" />{chips[0]}</span>
    <span key={`b${scene}`} className="hero-chip chip-bottom"><ChipB weight="fill" aria-hidden="true" />{chips[1]}</span>
    <div className="ph-steps" role="group" aria-label={t.heroAria}>{t.phone.steps.map((label, index) => <button key={label} type="button" className={index === scene ? 'on' : ''} aria-pressed={index === scene} onClick={() => go(index)}><span>{index + 1}</span>{label}</button>)}</div>
    <figcaption>{t.heroCaption}</figcaption>
  </figure>;
}
function PrivacyPolicy({ locale }) { const t = copy[locale]; const zh = locale === 'zh'; return <main className="legal-page"><header className="nav shell"><a href={zh ? '/zh' : '/'} className="brand" aria-label="1Day home"><img className="brand-logo" src="/assets/brand/1day-logo-lockup-cream.png" alt="1Day" /></a><a className="language" href={zh ? '/privacy' : '/zh/privacy'}>{zh ? 'EN' : '中文'}</a></header><article className="legal-copy"><p className="eyebrow">1Day</p><h1>{t.privacyTitle}</h1><p className="legal-updated">{t.privacyDate}</p>{t.privacySections.map(([heading, body]) => <section key={heading}><h2>{heading}</h2><p>{body}</p></section>)}<h2>{zh ? '联系我们' : 'Contact'}</h2><p>{zh ? '问题或数据删除请求：' : 'Questions or deletion requests: '}<a href="mailto:cassie@cassieliang.com">cassie@cassieliang.com</a></p><p><a className="text-link legal-back" href={zh ? '/zh' : '/'}>{t.back}</a></p></article></main>; }

const COMPANY = '量越（杭州）电子商务有限公司';
const CONTACT_EMAIL = 'cassie@cassieliang.com';
const aboutCopy = {
  zh: { title: '关于我们', sections: [['公司', `1Day 由${COMPANY}开发和运营，公司注册在中国杭州。`], ['我们在做什么', '1Day 是一款 iOS 视频日记 App。用户每天拍几秒片段，可以留给自己，也可以分享到和朋友共用的房间，最后挑出喜欢的片段拼成一支 vlog。'], ['技术', 'iOS 端用 Swift 和 SwiftUI 开发，视频的拍摄、剪辑和合成都在手机上完成。云端服务跑在 Cloudflare Workers 上，用大语言模型生成每日拍摄提示，并帮用户挑选片段。']] },
  en: { title: 'About us', sections: [['Company', `1Day is built and operated by ${COMPANY}, a company registered in Hangzhou, China.`], ['What we make', '1Day is an iOS video diary app. People film a few seconds a day, keep the clips for themselves or share them in a room with friends, then pick their favorites and turn them into a vlog.'], ['Technology', 'The iOS app is written in Swift and SwiftUI, and capture, editing, and rendering happen on the phone. Our cloud service runs on Cloudflare Workers and uses a large language model to suggest daily filming prompts and help pick clips.']] },
};
function About({ locale }) { const t = copy[locale]; const a = aboutCopy[locale]; const zh = locale === 'zh'; return <main className="legal-page"><header className="nav shell"><a href={zh ? '/zh' : '/'} className="brand" aria-label="1Day home"><img className="brand-logo" src="/assets/brand/1day-logo-lockup-cream.png" alt="1Day" /></a><a className="language" href={zh ? '/about' : '/zh/about'}>{zh ? 'EN' : '中文'}</a></header><article className="legal-copy"><p className="eyebrow">1Day</p><h1>{a.title}</h1>{a.sections.map(([heading, body]) => <section key={heading}><h2>{heading}</h2><p>{body}</p></section>)}<h2>{zh ? '联系我们' : 'Contact'}</h2><p><a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a></p><p><a className="text-link legal-back" href={zh ? '/zh' : '/'}>{t.back}</a></p></article></main>; }

const updates = [
  {version: '1.5', beta: true, zh: '相机、房间，和自己的一天', en: 'A camera, shared rooms, and your own day', zhItems: ['底部改为「相机」和「房间」两个入口；在房间页点自己的卡片，进入个人时间线。', '随手拍摄，选择保留或分享到房间；DV 日期画面和支持机型的前后双摄。', '房间里每人一张片段卡片。点头像连着看这个人的片段，也能聊天、回应、评论和拍一拍。', '按天回看片段、记录心情，挑选片段并调整顺序，生成 vlog。', '成片支持原声、音乐或混合音轨；可调整柔和度、亮度和暖度。', '支持 Apple 和 Google 登录；共享内容由 1Day 的云端服务同步。'], enItems: ['Two tabs: Camera and Rooms. Open your own card in Rooms to reach your personal timeline.', 'Capture a few seconds, then choose what to keep or share. Includes a dated camcorder look and dual-camera capture on supported iPhones.', 'Each room member has a clip card. Tap a face to watch their clips, chat, react, comment, or send a poke.', 'Revisit clips by day, record your mood, and arrange selected clips into a vlog.', 'Use original audio, music, or both, and adjust softness, brightness, and warmth.', 'Apple and Google sign-in, with shared content synced through 1Day’s cloud service.']},
  {version: '1.3', pending: true, zh: '让它变成你的样子', en: 'Make it yours', zhItems: ['挑一个头像颜色，整个 App 的主色跟着变。', '拍摄时能变焦：0.5x、1x、2x，也能捏合到任意倍数。', '每个故事有自己的封面：抽一帧、传照片，或用海报。', '回看页重做，字幕能捏能转能换色。', '小蓝出现在成片的片头和角标上。'], enItems: ['Pick your avatar color — the whole app follows it.', 'Zoom while you film: 0.5x, 1x, 2x, or pinch to anything in between.', 'Give each story its own cover: pull a frame, pick a photo, or use a poster.', 'Rebuilt replay, with captions you can pinch, rotate, and recolor.', 'Blue now opens your film and signs its corner.']},
  {version: '1.2', date: '2026-09-09', zh: '按自己的方式，过好、拍下、回看一天', en: 'Plan, capture, and revisit a day your way', zhItems: ['说一句今天想做什么，获得一组拍摄提示，再按自己的想法修改。', '把自定义题目存进模板库，配上喜欢的封面，下次还能继续用。', '想拍哪个瞬间就先拍哪个，不必按照题目顺序完成。', '全屏回看片段，左右滑动就能接着看下一刻。', '调整柔和度、亮度和暖色效果，让回看与成片更合心意，保留原始素材。', '合拍时更清楚地看到谁在房间里、谁已经拍了，以及还有谁尚未记录。'], enItems: ['Describe what you want to do today, get filming prompts, and make them your own.', 'Save your custom prompts to the template library with a cover you love, ready to use again.', 'Capture any available moment first, without following a fixed order.', 'Review clips full-screen and swipe to the next moment.', 'Adjust softness, brightness, and warmth for playback and the finished film while preserving the original footage.', 'See who is in a shared room, who has filmed, and who has yet to contribute.']},
  {version: '1.1', date: '2026-08-25', zh: '给平常的一天，留下一支短片', en: 'A short film of an ordinary day', zhItems: ['选择完美的一天、慢慢重启等主题，跟着瞬间提示拍摄。', '通过房间码邀请朋友，把不同视角留在同一个故事里。', '在时间轴与网格之间切换，回看已经拍下的瞬间。', '在手机上将片段串成影片，也可以创建自己的拍摄题目。'], enItems: ['Choose a theme such as Perfect Day or Soft Reset and follow moment prompts.', 'Invite friends with a room code and bring different perspectives into one story.', 'Switch between a timeline and a grid to revisit your moments.', 'Assemble clips into a film on your phone, or create your own filming prompts.']},
];
function Changelog({locale}) {
  const zh = locale === 'zh'; const home = zh ? '/zh' : '/';
  return <main className="updates-page"><header className="nav shell"><a href={home} className="brand"><img className="brand-logo" src="/assets/brand/1day-logo-lockup-cream.png" alt="1Day" /></a><a className="updates-home" href={home}>{zh ? '返回首页' : 'Back to home'}</a><a className="language" href={zh ? '/updates' : '/zh/updates'}>{zh ? 'EN' : '中文'}</a></header><div className="updates-layout shell"><aside className="updates-months"><p>{zh ? '按版本浏览' : 'Browse by version'}</p>{updates.map(entry=><a key={entry.version} href={`#version-${entry.version.replace('.', '-')}`}>v{entry.version}<span>{entry.beta ? (zh ? 'TestFlight 公测' : 'TestFlight beta') : entry.pending ? (zh ? '待发布' : 'Upcoming') : (zh ? '已发布' : 'Released')}</span></a>)}</aside><article><p className="eyebrow">1Day · {zh ? '一点点变好' : 'A little better, every day'}</p><h1>{zh ? 'App 版本更新' : 'App release notes'}</h1><p className="updates-intro">{zh ? '看看每个版本带来的新功能与体验改进。' : 'New features and improvements, version by version.'}</p><div className="updates-timeline">{updates.map(entry=><section id={`version-${entry.version.replace('.', '-')}`} key={entry.version}><div className="update-date"><strong>v{entry.version}</strong><span>{entry.beta ? (zh ? 'TestFlight 公测' : 'TestFlight beta') : entry.pending ? (zh ? '待发布' : 'Upcoming') : (zh ? '已发布' : 'Released')}</span>{entry.date && <time dateTime={entry.date}>{new Date(entry.date+'T12:00:00Z').toLocaleDateString(zh ? 'zh-CN' : 'en-US', {year:'numeric',month:'long',day:'numeric',timeZone:'UTC'})}</time>}</div><h2>{entry[locale]}</h2><p className="release-note">{entry.beta ? (zh ? '这一版正在 TestFlight 公测，还没在 App Store 上线。' : 'This version is in TestFlight beta and not yet on the App Store.') : entry.pending ? (zh ? '以下为下一版更新预告，尚未在 App Store 上线。' : 'A preview of the next release, not yet available on the App Store.') : (zh ? '此版本的主要功能' : 'Features available in this version')}</p><ul>{entry[zh ? 'zhItems' : 'enItems'].map(item=><li key={item}>{item}</li>)}</ul></section>)}</div></article></div></main>;
}

export function App({ pathname }) {
  const path = pathname ?? (typeof window === 'undefined' ? '/' : window.location.pathname); const locale = path.startsWith('/zh') ? 'zh' : 'en'; const isPrivacy = path.endsWith('/privacy') || path.endsWith('/privacy/'); const isUpdates = /\/updates\/?$/.test(path); const isAbout = /\/about\/?$/.test(path); const page = isAbout ? {title: locale === 'zh' ? '关于我们 — 1Day' : 'About us — 1Day', description: locale === 'zh' ? `1Day 由${COMPANY}开发和运营。` : `1Day is built and operated by ${COMPANY}.`} : isUpdates ? {title: locale === 'zh' ? '更新日志 — 1Day' : 'What’s new — 1Day', description: locale === 'zh' ? '看看每个版本带来的新功能与体验改进。' : 'New features and improvements, version by version.'} : pageMetadata(locale, isPrivacy); const t = copy[locale]; const home = locale === 'zh' ? '/zh' : '';
  useEffect(() => { document.documentElement.lang = locale === 'zh' ? 'zh-CN' : 'en'; document.title = page.title; const description = document.querySelector('meta[name="description"]'); if (description) description.content = page.description; }, [locale, page.description, page.title]);
  if (isUpdates) return <Changelog locale={locale} />;
  if (isAbout) return <About locale={locale} />;
  if (isPrivacy) return <PrivacyPolicy locale={locale} />;
  return <main className="site-page">
    <header className="nav shell"><a href="#top" className="brand" aria-label="1Day home"><img className="brand-logo" src="/assets/brand/1day-logo-lockup-cream.png" alt="1Day" /></a><nav aria-label="Main navigation"><a href="#why">{t.nav[0]}</a><a href="#faq">{t.nav[1]}</a><a href={`${home}/updates`}>{locale === 'zh' ? '更新日志' : 'Updates'}</a></nav><div className="nav-actions"><a className="language" href={locale === 'zh' ? '/' : '/zh'}>{locale === 'zh' ? 'EN' : '中文'}</a><StoreButton locale={locale} compact /></div></header>
    <section id="top" className="hero shell"><div className="hero-copy"><p className="eyebrow">{t.eyebrow}</p><h1>{t.title}</h1><p className="lede">{t.lede}</p><div className="hero-actions"><StoreButton locale={locale} /><a className="text-link" href="#why">{t.learn} <ArrowRight /></a></div><BetaInvite locale={locale} /></div><HeroPhone t={t} /></section>
    <section id="why" className="why-section shell"><div className="why-intro"><p className="eyebrow">{t.whyLabel}</p><h2>{t.whyTitle}</h2></div><div className="why-compare"><div className="why-before"><p className="why-tag">{t.beforeLabel}</p><ul>{t.before.map((item) => <li key={item}><Clock aria-hidden="true" />{item}</li>)}</ul></div><div className="why-now"><p className="why-tag">{t.nowLabel}</p><ol>{t.now.map(([title, text], index) => { const Icon = [Camera, UsersThree, FilmStrip][index]; return <li key={title}><span className="feature-icon"><Icon weight="duotone" aria-hidden="true" /></span><span><strong>{title}</strong><small>{text}</small></span></li>; })}</ol></div></div></section>
    <section className="more-section shell"><p className="eyebrow">{t.moreLabel}</p><h2>{t.moreTitle}</h2><div className="more-grid">{t.features.map(([title, text], index) => { const Icon = [VideoCamera, CameraRotate, Smiley, MusicNotes][index]; return <div key={title}><span className="feature-icon"><Icon weight="duotone" aria-hidden="true" /></span><strong>{title}</strong><p>{text}</p></div>; })}</div></section>
    <section id="faq" className="faq-section shell"><div><p className="eyebrow">{t.faqLabel}</p><h2>{t.faqTitle}</h2><a className="text-link" href={`${home}/privacy`}>{t.faqMore} <ArrowRight /></a></div><div className="faq-list">{t.faq.map(([q, a]) => <details key={q}><summary>{q}</summary><p>{a}</p></details>)}</div></section>
    <section className="cta-section shell"><h2>{t.ctaTitle}</h2><p>{t.ctaText}</p><div className="hero-actions"><StoreButton locale={locale} /><a className="text-link" href={TESTFLIGHT_URL} target="_blank" rel="noreferrer">{t.betaButton} <ArrowRight /></a></div></section>
    <footer className="site-footer shell"><StoreButton locale={locale} /><div><a href={`${home}/updates`}>{locale === 'zh' ? '更新日志' : 'Updates'}</a><a href={`${home}/about`}>{aboutCopy[locale].title}</a><a href={`${home}/privacy`}>{t.footer[0]}</a><a href={APP_STORE_URL}>{t.footer[1]}</a><a href="mailto:cassie@cassieliang.com">{t.footer[2]}</a><a href="https://liangyue.site" target="_blank" rel="noreferrer">{t.portfolio}</a></div><p className="footer-company">© 2026 {COMPANY}</p></footer>
  </main>;
}

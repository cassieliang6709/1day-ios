import { useEffect, useMemo, useState } from 'react';
import { AppleLogo, ArrowRight, CalendarBlank, Camera, Check, FilmStrip, LockKey, Smiley, UsersThree } from '@phosphor-icons/react';

const TESTFLIGHT_URL = 'https://testflight.apple.com/join/cRQm6Va2';

const themes = [
  { id: 'perfect', en: 'Perfect Day', zh: '完美的一天', enNote: 'Capture the little things that made today good.', zhNote: '记下那些让今天变好的小事。', image: '/assets/moment-1.jpg' },
  { id: 'reset', en: 'Soft Reset', zh: '轻轻重启', enNote: 'A fresh start. Reset your day, your way.', zhNote: '重新开始，按自己的节奏来。', image: '/assets/moment-4.jpg' },
  { id: 'lockin', en: 'Study Lock-in', zh: '专注时刻', enNote: 'Focus, progress, repeat.', zhNote: '专注、进步、重复。', image: '/assets/moment-3.jpg' },
  { id: 'main', en: 'Main Character', zh: '主角时刻', enNote: "It's your story. Own the plot.", zhNote: '这是你的故事，由你做主。', image: '/assets/moment-5.jpg' },
];

const copy = {
  zh: {
    nav: ['使用方式', '你能做什么', '隐私'], beta: '加入 TestFlight 测试', betaSmall: '加入测试', heroNote: '你的每一天，都值得留成故事。',
    title: <>把琐事<br />拍成 <em>电影</em><br />让生活更有意思。</>,
    lede: '录下 2 秒、5 秒或 10 秒的片段。1Day 会把它们编成一支完整的每日短片——一个人，或和朋友一起。', learn: '看看它如何工作', themeTitle: '选择你的故事主题', allThemes: '查看全部主题',
    how: '1Day 如何工作', howNote: '从一个小小的故事开始，把散落的瞬间留成完整的一天。',
    steps: [
      ['开始一个故事', '选一个主题，开启属于你的一天或七天挑战。', CalendarBlank],
      ['记录瞬间', '用前后镜头拍下 2 秒、5 秒或 10 秒的短片，也能保留声音。', Camera],
      ['添一点细节', '名字、文字、回应和评论，让你的故事慢慢有了生命。', Smiley],
      ['观看成片', '1Day 自动整理所有片段，完成一支好看的每日短片。', FilmStrip],
    ],
    finished: '在 iPhone 上完成', filmTitle: <>每一段。<br />一个完整故事。</>, filmText: '随时预览最后的竖版短片；想和朋友一起看时切成网格，然后保存到照片或通过 iOS 分享。', privacy: '单人故事只留在你的设备上。要不要保存或分享，始终由你决定。',
    modes: [['独自记录', '只关于你和你的这一天。', UsersThree], ['朋友房间', '无论身处哪里，一起记录。', UsersThree], ['每日成片', '每天一支，都是故事。', FilmStrip]], footer: ['隐私政策', '测试海报', '支持'], filmNote: '真实成片 · 7 个瞬间 · 11 秒', filmAria: '1Day 生成的样片', back: '← 返回 1Day', privacyTitle: '隐私政策', privacyDate: '生效日期：2026 年 7 月 24 日',
  },
  en: {
    nav: ['How it works', 'What you can do', 'Privacy'], beta: 'Join the beta on TestFlight', betaSmall: 'Join beta', heroNote: 'Your day is a story worth keeping.',
    title: <>Turn everyday<br />moments into <em>film</em>.<br />Make life more fun.</>,
    lede: 'Record 2, 5, or 10-second clips of your day. 1Day turns them into a beautiful daily film—solo or with friends.', learn: 'Learn how it works', themeTitle: 'Choose your story theme', allThemes: 'See all themes',
    how: 'How 1Day works', howNote: 'Start with a small story, then keep the moments that make up a complete day.',
    steps: [
      ['Start a story', 'Choose a theme and start your one-day or seven-day challenge.', CalendarBlank],
      ['Record moments', 'Capture 2, 5, or 10-second clips with the front or rear camera, with audio.', Camera],
      ['Add the little things', 'Names, captions, reactions, and comments make your story come alive.', Smiley],
      ['Watch your film', '1Day orders every clip and turns it into a beautiful daily film.', FilmStrip],
    ],
    finished: 'Finished on your iPhone', filmTitle: <>Every clip.<br />One complete story.</>, filmText: 'Preview the finished vertical film, turn shared clips into a grid when you want, then save it to Photos or share it through iOS.', privacy: 'Solo stories stay on your device. You decide what to save or share.',
    modes: [['Solo', 'Just you and your day.', UsersThree], ['Friends Room', 'Capture together, from anywhere.', UsersThree], ['Daily Film', 'One film. Every day.', FilmStrip]], footer: ['Privacy Policy', 'Beta Poster', 'Support'], filmNote: 'A real film · 7 moments · 11s', filmAria: 'Sample film made by 1Day', back: '← Back to 1Day', privacyTitle: 'Privacy Policy', privacyDate: 'Effective July 24, 2026',
  },
};

function StoreButton({ locale, compact = false }) {
  const t = copy[locale];
  return <a className={`store-button ${compact ? 'compact' : ''}`} href={TESTFLIGHT_URL} target="_blank" rel="noreferrer" aria-label={t.beta}><AppleLogo weight="fill" /><span><small>{locale === 'zh' ? '加入 beta 测试' : 'Join the beta on'}</small>{compact ? t.betaSmall : 'TestFlight'}</span></a>;
}

function PrivacyPolicy({ locale }) {
  const t = copy[locale];
  const zh = locale === 'zh';
  return <main className="legal-page"><header className="nav shell"><a href={zh ? '/' : '/en'} className="brand" aria-label="1Day home"><img className="brand-logo" src="/assets/brand/1day-logo-lockup-v2.png" alt="" /></a><a className="language" href={zh ? '/en/privacy' : '/privacy'}>{zh ? 'EN' : '中文'}</a></header><article className="legal-copy">
    <p className="eyebrow">1Day</p><h1>{t.privacyTitle}</h1><p className="legal-updated">{t.privacyDate}</p>
    <h2>{zh ? '概览' : 'Overview'}</h2><p>{zh ? '1Day 帮你记录短视频瞬间，并将它们编成一支短片。单人挑战保存在你的设备上；共享挑战使用 Apple iCloud，并需要“通过 Apple 登录”。' : '1Day helps you record short video moments and assemble them into a film. Solo challenges stay on your device. Shared challenges use Apple iCloud and require Sign in with Apple.'}</p>
    <h2>{zh ? '我们处理的信息' : 'Information we handle'}</h2><p>{zh ? '应用可能会处理“通过 Apple 登录”提供的名称与稳定标识符、挑战详情、房间成员、文字说明，以及你选择上传到共享房间的视频片段。相机、麦克风和照片图库仅在你授权后使用。' : 'The app may handle the name and stable identifier provided through Sign in with Apple, challenge details, room membership, captions, and video clips you choose to upload to a shared room. Camera, microphone, and photo-library access are used only after you grant permission.'}</p>
    <h2>{zh ? '存储与分享' : 'Storage and sharing'}</h2><p>{zh ? '单人挑战数据和片段只存储在你的设备上。共享房间的数据和片段存储于 Apple CloudKit。房间码是邀请方式，而非密码；收到房间码的人可以加入并访问其中的共享内容。成片只会在你选择保存或分享时离开应用。' : 'Solo challenge data and clips are stored locally on your device. Shared-room data and clips are stored in Apple CloudKit. A room code is an invitation, not a password: people who receive it can join that room and access its shared content. Finished films leave the app only when you choose to save or share them.'}</p>
    <h2>{zh ? '联系我们' : 'Contact'}</h2><p>{zh ? '问题或数据删除请求：' : 'Questions or deletion requests: '}<a href="mailto:liangyue3666@gmail.com">liangyue3666@gmail.com</a></p><p><a className="text-link" href={zh ? '/' : '/en'}>{t.back}</a></p>
  </article></main>;
}

export function App() {
  const path = window.location.pathname;
  const locale = path.startsWith('/en') ? 'en' : 'zh';
  const t = copy[locale];
  useEffect(() => {
    const english = locale === 'en';
    document.documentElement.lang = english ? 'en' : 'zh-CN';
    document.title = english ? '1Day — Turn everyday moments into film.' : '1Day — 把琐事拍成电影，让生活更有意思。';
    const description = document.querySelector('meta[name="description"]');
    if (description) description.content = english
      ? '1Day is an iOS video diary. Record small moments from your day, then keep them as one finished daily film.'
      : '1Day 是一款 iOS 视频日记。记录一天里的短短片段，留成一支完整的每日短片。';
  }, [locale]);
  if (path.endsWith('/privacy') || path.endsWith('/privacy/')) return <PrivacyPolicy locale={locale} />;
  const [selectedTheme, setSelectedTheme] = useState(themes[0].id);
  const selected = useMemo(() => themes.find((theme) => theme.id === selectedTheme), [selectedTheme]);
  const home = locale === 'zh' ? '' : '/en';
  const themeName = selected[locale];

  return <main className="site-page">
    <header className="nav shell"><a href="#top" className="brand" aria-label="1Day home"><img className="brand-logo" src="/assets/brand/1day-logo-lockup-v2.png" alt="" /></a><nav aria-label="Main navigation"><a href="#how">{t.nav[0]}</a><a href="#film">{t.nav[1]}</a><a href={`${home}/privacy`}>{t.nav[2]}</a></nav><div className="nav-actions"><a className="language" href={locale === 'zh' ? '/en' : '/'}>{locale === 'zh' ? 'EN' : '中文'}</a><StoreButton locale={locale} compact /></div></header>
    <section id="top" className="hero shell">
      <div className="hero-copy"><p className="scribble">{t.heroNote}</p><h1>{t.title}</h1><p className="lede">{t.lede}</p><div className="hero-actions"><StoreButton locale={locale} /><a className="text-link" href="#how">{t.learn} <ArrowRight /></a></div></div>
      <div className="phone-wrap"><div className="phone"><div className="speaker" /><img src="/assets/app-screen-current.jpg" alt={locale === 'zh' ? '1Day 应用主页预览' : '1Day app home preview'} /></div><p className="phone-callout">{locale === 'zh' ? '短短片段，一支完整短片。' : 'Short clips. One beautiful film.'}</p></div>
      <aside className="theme-panel" aria-label={t.themeTitle}><h2>{t.themeTitle}</h2><div className="theme-options">{themes.map((theme) => <button type="button" key={theme.id} className={selectedTheme === theme.id ? 'selected' : ''} onClick={() => setSelectedTheme(theme.id)} aria-pressed={selectedTheme === theme.id}><img src={theme.image} alt="" /><span><strong>{theme[locale]}</strong><small>{theme[`${locale}Note`]}</small></span>{selectedTheme === theme.id ? <Check weight="bold" /> : <i />}</button>)}</div><a href="#how" className="text-link">{t.allThemes} <ArrowRight /></a><p className="selected-theme" aria-live="polite">{themeName}</p></aside>
    </section>
    <section id="how" className="how shell"><div className="how-heading"><p className="eyebrow">{t.how}</p><p>{t.howNote}</p></div><div className="steps">{t.steps.map(([title, note, Icon], index) => <article className="step" key={title}><div className="step-icon"><Icon weight="fill" /></div><div><p><b>{index + 1}</b> {title}</p><small>{note}</small></div>{index < t.steps.length - 1 && <ArrowRight className="step-arrow" />}</article>)}</div></section>
    <section id="film" className="film-section shell"><div className="film-copy"><p className="eyebrow">{t.finished}</p><h2>{t.filmTitle}</h2><p>{t.filmText}</p><p className="privacy"><LockKey weight="bold" />{t.privacy}</p></div><figure className="movie"><video className="sample-film" src="/assets/sample-film.mp4" poster="/assets/sample-film-poster.jpg" autoPlay muted loop playsInline preload="metadata" aria-label={t.filmAria} /><figcaption>{t.filmNote}</figcaption></figure></section>
    <section className="modes shell">{t.modes.map(([title, note, Icon], index) => <div key={title}><Icon weight="fill" /><span><small>0{index + 1}</small><strong>{title}</strong><em>{note}</em></span></div>)}</section>
    <footer className="site-footer shell"><StoreButton locale={locale} /><div><a href={`${home}/privacy`}>{t.footer[0]}</a><a href="/assets/testflight-qr-poster-ipad.png" download>{t.footer[1]}</a><a href="mailto:liangyue3666@gmail.com">{t.footer[2]}</a></div></footer>
  </main>;
}

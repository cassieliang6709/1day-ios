import { useMemo, useState } from 'react';
import {
  ArrowRight,
  Camera,
  Check,
  FilmStrip,
  LockKey,
  Play,
  Sparkle,
  UsersThree,
} from '@phosphor-icons/react';

const betaEmail = 'mailto:liangyue3666@gmail.com?subject=1Day%20private%20beta';

const dayTypes = [
  { name: 'Sunday Reset', short: 'Reset', image: '/assets/morning.jpg' },
  { name: 'Study Lock-in', short: 'Focus', image: '/assets/focus.jpg' },
  { name: 'Room Reset', short: 'Refresh', image: '/assets/morning.jpg' },
  { name: 'One-Day Glow Up', short: 'Glow up', image: '/assets/walk.jpg' },
  { name: 'Friend Day', short: 'Together', image: '/assets/friends.jpg' },
];

const moments = [
  { time: '8:30', title: 'Set the tone', image: '/assets/morning.jpg' },
  { time: '10:15', title: 'Find your focus', image: '/assets/focus.jpg' },
  { time: '12:40', title: 'Notice the little things', image: '/assets/walk.jpg' },
  { time: '2:30', title: 'Pause and refuel', image: '/assets/morning.jpg' },
  { time: '5:20', title: 'Step outside', image: '/assets/walk.jpg' },
  { time: '8:00', title: 'Keep your people close', image: '/assets/friends.jpg' },
  { time: '10:45', title: 'Close the day', image: '/assets/morning.jpg' },
];

const steps = [
  {
    number: '01',
    icon: Sparkle,
    title: 'Pick a story',
    copy: 'Choose a one-day or seven-day challenge, then make it yours.',
  },
  {
    number: '02',
    icon: Camera,
    title: 'Live it, clip by clip',
    copy: 'Gentle prompts bring you back for a few seconds at a time.',
  },
  {
    number: '03',
    icon: FilmStrip,
    title: 'Watch the day come together',
    copy: '1Day turns the clips into a finished film—no editing timeline required.',
  },
];

function BetaButton({ compact = false, light = false }) {
  return (
    <a className={`beta-button${compact ? ' compact' : ''}${light ? ' light' : ''}`} href={betaEmail}>
      <span>{compact ? 'Join beta' : 'Join the private beta'}</span>
      <ArrowRight weight="bold" aria-hidden="true" />
    </a>
  );
}

function Brand() {
  return (
    <a href="/#top" className="brand" aria-label="1Day home">
      <span className="brand-mark" aria-hidden="true"><i>1</i></span>
      <span>1Day</span>
    </a>
  );
}

function SiteHeader() {
  return (
    <header className="site-nav shell">
      <Brand />
      <nav aria-label="Main navigation">
        <a href="#how">How it works</a>
        <a href="#together">With friends</a>
        <a href="/privacy">Privacy</a>
      </nav>
      <BetaButton compact />
    </header>
  );
}

function PrivacyPolicy() {
  return (
    <main className="legal-page">
      <header className="site-nav shell"><Brand /></header>
      <article className="legal-copy">
        <p className="kicker">The small print</p>
        <h1>Privacy Policy</h1>
        <p className="legal-updated">Effective July 24, 2026</p>

        <h2>Overview</h2>
        <p>1Day helps you record short video moments and assemble them into a film. Solo challenges stay on your device. Shared challenges use Apple iCloud and require Sign in with Apple.</p>

        <h2>Information we handle</h2>
        <p>The app may handle the name and stable identifier provided through Sign in with Apple, challenge details, room membership, captions, and video clips you choose to upload to a shared room. Camera, microphone, and photo-library access are used only after you grant permission.</p>

        <h2>How information is used</h2>
        <p>We use this information only to create and join challenges, identify contributions inside a shared film, synchronize shared clips, render films, and let you save or share the result. 1Day does not use third-party advertising or analytics SDKs and does not sell personal information.</p>

        <h2>Storage and sharing</h2>
        <p>Solo challenge data and clips are stored locally on your device. Shared-room data and clips are stored in Apple CloudKit. A room code is an invitation, not a password: people who receive it can join that room and access its shared content. Finished films leave the app only when you choose to save or share them.</p>

        <h2>Retention and deletion</h2>
        <p>You can delete local challenges in the app. To request deletion of account-linked shared-room data, contact us from the email associated with your request. We may retain information when required for security, legal compliance, or resolving abuse.</p>

        <h2>Children</h2>
        <p>1Day is not directed to children under 13. If you believe a child has provided personal information, contact us so we can remove it.</p>

        <h2>Contact</h2>
        <p>Questions or deletion requests: <a href="mailto:liangyue3666@gmail.com">liangyue3666@gmail.com</a>.</p>
        <p><a className="inline-link" href="/">← Back to 1Day</a></p>
      </article>
    </main>
  );
}

function Hero() {
  const [selectedDay, setSelectedDay] = useState(dayTypes[0].name);
  const selected = useMemo(
    () => dayTypes.find((day) => day.name === selectedDay) ?? dayTypes[0],
    [selectedDay],
  );

  return (
    <>
      <section id="top" className="hero shell">
        <div className="hero-copy">
          <p className="kicker"><span /> Private iOS beta</p>
          <h1>A whole day,<br /><em>worth replaying.</em></h1>
          <p className="hero-lede">Seven tiny check-ins. One finished film. Keep the moments that would otherwise disappear.</p>
          <div className="hero-actions">
            <BetaButton />
            <a className="inline-link" href="#how">See how it works <ArrowRight aria-hidden="true" /></a>
          </div>
          <ul className="hero-facts" aria-label="Product highlights">
            <li><Check weight="bold" /> No editing required</li>
            <li><Check weight="bold" /> Local-first</li>
            <li><Check weight="bold" /> Made for iPhone</li>
          </ul>
        </div>

        <div className="hero-visual" aria-label="1Day app preview">
          <div className="visual-orbit orbit-one" />
          <div className="visual-orbit orbit-two" />
          <div className="phone">
            <div className="speaker" />
            <img src="/assets/app-screen.jpg" alt="1Day screen for choosing a one-day video story" />
          </div>
          <div className="floating-card floating-top">
            <span className="mini-photo"><img src={selected.image} alt="" /></span>
            <span><small>Today’s story</small>{selected.name}</span>
          </div>
          <div className="floating-card floating-bottom">
            <span className="pulse-dot" />
            <span><small>Moment 4 of 7</small>Just five seconds</span>
          </div>
        </div>
      </section>

      <section className="story-picker shell" aria-labelledby="story-picker-title">
        <div>
          <p className="kicker">Make it yours</p>
          <h2 id="story-picker-title">What kind of day is today?</h2>
        </div>
        <div className="day-options" role="list" aria-label="Story ideas">
          {dayTypes.map((day) => (
            <button
              type="button"
              key={day.name}
              className={selectedDay === day.name ? 'selected' : ''}
              onClick={() => setSelectedDay(day.name)}
              aria-pressed={selectedDay === day.name}
            >
              <img src={day.image} alt="" />
              <span><small>{day.short}</small>{day.name}</span>
            </button>
          ))}
        </div>
      </section>
    </>
  );
}

function MomentRibbon() {
  return (
    <section className="moments-section" aria-labelledby="moments-title">
      <div className="section-heading shell">
        <p className="kicker">A little, throughout the day</p>
        <h2 id="moments-title">Don’t film everything.<br />Remember the right things.</h2>
        <p>Each prompt asks for only a few seconds, so the camera never takes over the day.</p>
      </div>
      <div className="moment-ribbon">
        {moments.map((moment, index) => (
          <article className="moment-card" key={moment.time}>
            <img src={moment.image} alt="" />
            <div className="moment-overlay" />
            <span className="moment-count">{String(index + 1).padStart(2, '0')}</span>
            <div>
              <p>{moment.time}</p>
              <h3>{moment.title}</h3>
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}

function HowItWorks() {
  return (
    <section id="how" className="how-section shell" aria-labelledby="how-title">
      <div className="section-heading left">
        <p className="kicker">Simple on purpose</p>
        <h2 id="how-title">You live the story.<br />1Day does the editing.</h2>
      </div>
      <div className="step-grid">
        {steps.map(({ number, icon: Icon, title, copy }) => (
          <article className="step-card" key={number}>
            <div className="step-top"><span>{number}</span><Icon aria-hidden="true" /></div>
            <h3>{title}</h3>
            <p>{copy}</p>
          </article>
        ))}
      </div>
    </section>
  );
}

function TogetherSection() {
  return (
    <section id="together" className="together-section">
      <div className="together-inner shell">
        <div className="together-art" aria-hidden="true">
          <div className="friend-photo photo-one"><img src="/assets/friends.jpg" alt="" /></div>
          <div className="friend-photo photo-two"><img src="/assets/walk.jpg" alt="" /></div>
          <div className="room-code"><UsersThree weight="fill" /><span><small>Shared room</small>DAY 7K2</span></div>
        </div>
        <div className="together-copy">
          <p className="kicker">Better together</p>
          <h2>One story.<br />Everyone’s angle.</h2>
          <p>Invite friends with a room code, collect each person’s clips, and turn the day into one shared film.</p>
          <ul>
            <li><Check weight="bold" /> No custom account for solo stories</li>
            <li><Check weight="bold" /> Shared clips sync through iCloud</li>
            <li><Check weight="bold" /> You choose when to save or share</li>
          </ul>
        </div>
      </div>
    </section>
  );
}

function Finale() {
  const [playing, setPlaying] = useState(false);

  return (
    <section id="beta" className="finale">
      <div className="finale-inner shell">
        <div className="finale-copy">
          <p className="kicker">By bedtime</p>
          <h2>Today,<br />in 45 seconds.</h2>
          <p>No loose clips. No editing backlog. Just a tiny film ready to keep.</p>
          <BetaButton light />
          <p className="privacy-note"><LockKey weight="bold" /> Solo stories stay on your device.</p>
        </div>
        <button
          className={`movie-card${playing ? ' playing' : ''}`}
          type="button"
          onClick={() => setPlaying((value) => !value)}
          aria-label={playing ? 'Pause sample film preview' : 'Play sample film preview'}
        >
          <div className="movie-images">
            {['morning.jpg', 'focus.jpg', 'walk.jpg', 'friends.jpg'].map((src) => (
              <img key={src} src={`/assets/${src}`} alt="" />
            ))}
          </div>
          <span className="movie-shade" />
          <span className="play-button"><Play weight="fill" /></span>
          <span className="movie-meta"><i><b>{playing ? 'Playing' : 'Your 1Day'}</b><small>Sunday reset · 0:45</small></i><em>{playing ? '0:18' : '0:00'}</em></span>
          <span className="progress-track"><i /></span>
        </button>
      </div>
      <footer className="site-footer shell">
        <Brand />
        <p>Small moments. One film worth keeping.</p>
        <div><a href="/privacy">Privacy</a><a href="mailto:liangyue3666@gmail.com">Support</a></div>
      </footer>
    </section>
  );
}

function HomePage() {
  return (
    <main>
      <SiteHeader />
      <Hero />
      <MomentRibbon />
      <HowItWorks />
      <TogetherSection />
      <Finale />
    </main>
  );
}

export function App() {
  const isPrivacyPage = window.location.pathname === '/privacy' || window.location.pathname === '/privacy/';
  return isPrivacyPage ? <PrivacyPolicy /> : <HomePage />;
}

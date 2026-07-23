import { useMemo, useState } from 'react';
import { AppleLogo, ArrowRight, LockKey, Play } from '@phosphor-icons/react';

const dayTypes = [
  { name: 'Sunday Reset', image: '/assets/morning.jpg' },
  { name: 'Study Lock-in', image: '/assets/focus.jpg' },
  { name: 'Room Reset', image: '/assets/morning.jpg' },
  { name: 'One-Day Glow Up', image: '/assets/walk.jpg' },
  { name: 'Friend Day', image: '/assets/friends.jpg' },
];

const moments = [
  { time: '8:30 AM', title: 'Morning reset', note: 'Coffee, sunlight, set the tone.', image: '/assets/morning.jpg' },
  { time: '10:15 AM', title: 'Deep work', note: 'Focus block. No distractions.', image: '/assets/focus.jpg' },
  { time: '1:00 PM', title: 'Step outside', note: 'Walk, breathe, clear your head.', image: '/assets/walk.jpg' },
  { time: '2:30 PM', title: 'Refuel', note: 'Pause for what keeps you going.', image: '/assets/morning.jpg', position: 'left' },
  { time: '6:15 PM', title: 'Sunset pause', note: 'Notice the view. Be here.', image: '/assets/walk.jpg', position: 'right' },
  { time: '8:00 PM', title: 'Time together', note: 'People > plans. Make it count.', image: '/assets/friends.jpg' },
  { time: '10:45 PM', title: 'Night wrap', note: 'One last thought. End with calm.', image: '/assets/morning.jpg', position: 'right' },
];

function AppStoreButton({ compact = false }) {
  return (
    <a className={`store-button ${compact ? 'compact' : ''}`} href="#download" aria-label="Download One Day on the App Store">
      <AppleLogo weight="fill" aria-hidden="true" />
      <span><small>Download on the</small>App Store</span>
    </a>
  );
}

export function App() {
  const [selectedDay, setSelectedDay] = useState(dayTypes[0].name);
  const [playing, setPlaying] = useState(false);
  const selectedLabel = useMemo(() => selectedDay.replace('One-Day ', ''), [selectedDay]);

  return (
    <main>
      <header className="nav shell">
        <a href="#top" className="brand" aria-label="One Day home"><span className="brand-mark" />One Day</a>
        <nav aria-label="Main navigation">
          <a href="#how">How it works</a>
          <a href="#moments">For you</a>
          <a href="#privacy">Privacy</a>
        </nav>
        <AppStoreButton compact />
      </header>

      <section id="top" className="chooser shell" aria-labelledby="chooser-title">
        <h2 id="chooser-title">What kind of day is it?</h2>
        <div className="day-options" role="list">
          {dayTypes.map((day) => (
            <button
              type="button"
              key={day.name}
              className={selectedDay === day.name ? 'selected' : ''}
              onClick={() => setSelectedDay(day.name)}
              aria-pressed={selectedDay === day.name}
            >
              <img src={day.image} alt="" />
              {day.name}
            </button>
          ))}
        </div>
      </section>

      <section className="hero shell">
        <div className="hero-copy">
          <p className="eyebrow">Your {selectedLabel.toLowerCase()} story</p>
          <h1>Make today<br />a tiny movie.</h1>
          <p className="lede">Seven moments. 24 hours.<br />Capture what matters, beautifully.</p>
          <div className="hero-actions">
            <AppStoreButton />
            <a className="text-link" href="#how">Learn how it works <ArrowRight aria-hidden="true" /></a>
          </div>
        </div>
        <div className="phone-wrap" aria-label="One Day app preview">
          <div className="phone">
            <div className="speaker" />
            <img src="/assets/app-screen.jpg" alt="One Day app screen for choosing a one-day story" />
          </div>
        </div>
      </section>

      <section id="how" className="timeline shell" aria-labelledby="timeline-title">
        <div className="timeline-heading">
          <p className="eyebrow">One gentle day</p>
          <h2 id="timeline-title">Seven moments, then a movie.</h2>
          <p>We nudge you at the right moments. You just live them.</p>
        </div>
        <div id="moments" className="moment-grid">
          {moments.map((moment, index) => (
            <article className="moment" key={moment.time}>
              <div className="moment-number">{index + 1}</div>
              <p className="moment-time">{moment.time}</p>
              <h3>{moment.title}</h3>
              <p>{moment.note}</p>
              <img src={moment.image} style={{ objectPosition: moment.position || 'center' }} alt={`${moment.title} captured as part of a one-day story`} />
            </article>
          ))}
        </div>
      </section>

      <section id="download" className="night-section">
        <div className="night-inner shell">
          <div className="night-copy">
            <p className="eyebrow">Tonight</p>
            <h2>Your night.<br />One tiny movie.</h2>
            <p>We stitch your seven moments into a beautiful vlog—ready to watch, save, or share.</p>
            <p id="privacy" className="privacy"><LockKey weight="bold" aria-hidden="true" /> Private by default. Only you decide what to share.</p>
          </div>
          <button className={`movie ${playing ? 'playing' : ''}`} type="button" onClick={() => setPlaying(!playing)} aria-label={playing ? 'Pause sample movie' : 'Play sample movie'}>
            <div className="filmstrip">
              {['morning.jpg', 'focus.jpg', 'walk.jpg', 'friends.jpg', 'morning.jpg'].map((src, i) => <img key={`${src}-${i}`} src={`/assets/${src}`} alt="" />)}
            </div>
            <span className="play"><Play weight="fill" aria-hidden="true" /></span>
            <span className="progress"><i /></span>
            <small>{playing ? '0:18' : '0:00'} <span>0:45</span></small>
          </button>
          <div className="final-download"><AppStoreButton /></div>
        </div>
      </section>
    </main>
  );
}

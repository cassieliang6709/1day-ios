import React from 'react';
import {
  AbsoluteFill,
  OffthreadVideo,
  Sequence,
  staticFile,
  useVideoConfig,
} from 'remotion';
import {Phone} from './components/Phone';
import {Caption, TitleCard} from './components/Caption';
import {sec, Shot} from './shots';
import {brand, fontStack} from './theme';

type Variant = 'XHS' | 'AppStore';

const Background: React.FC<{variant: Variant}> = ({variant}) =>
  variant === 'XHS' ? (
    <AbsoluteFill
      style={{
        background: `linear-gradient(170deg, ${brand.paper} 0%, #eaf3ff 55%, #dfeeff 100%)`,
      }}
    />
  ) : (
    <AbsoluteFill style={{background: '#000'}} />
  );

const ShotView: React.FC<{shot: Shot; variant: Variant}> = ({shot, variant}) => {
  const {width, height} = useVideoConfig();
  const xhs = variant === 'XHS';

  if (shot.card) {
    return (
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
        <TitleCard
          title={shot.card.title}
          sub={shot.card.sub}
          note={shot.card.note}
          size={width * 0.075}
        />
      </AbsoluteFill>
    );
  }

  // A 16:9 clip (the film the app renders) shown as a card, never cropped to 9:16.
  if (shot.filmCard && shot.src) {
    const cardWidth = xhs ? width * 0.86 : width;
    return (
      <AbsoluteFill
        style={{justifyContent: 'center', alignItems: 'center', gap: height * 0.04}}
      >
        {shot.caption && xhs ? (
          <Caption text={shot.caption} size={width * 0.05} />
        ) : null}
        <div
          style={{
            width: cardWidth,
            height: Math.round((cardWidth / 16) * 9),
            borderRadius: xhs ? width * 0.035 : 0,
            overflow: 'hidden',
            fontFamily: fontStack,
            boxShadow: xhs
              ? '0 36px 80px rgba(16, 32, 58, 0.22)'
              : undefined,
          }}
        >
          <OffthreadVideo
            src={staticFile(shot.src)}
            style={{width: '100%', height: '100%', objectFit: 'cover'}}
            muted
          />
        </div>
      </AbsoluteFill>
    );
  }

  // Phone-in-frame shot.
  const phoneWidth = xhs ? width * 0.66 : width;

  if (!xhs) {
    // App Store: the recording fills the frame, caption floats near the bottom.
    return (
      <AbsoluteFill>
        {shot.src ? (
          <OffthreadVideo
            src={staticFile(shot.src)}
            style={{width: '100%', height: '100%', objectFit: 'cover'}}
            muted
          />
        ) : null}
      </AbsoluteFill>
    );
  }

  return (
    <AbsoluteFill
      style={{
        justifyContent: 'flex-start',
        alignItems: 'center',
        paddingTop: height * 0.055,
      }}
    >
      {shot.caption ? (
        <div style={{marginBottom: height * 0.03, padding: '0 8%'}}>
          <Caption text={shot.caption} size={width * 0.05} />
        </div>
      ) : null}
      {shot.src ? <Phone src={shot.src} width={phoneWidth} /> : null}
    </AbsoluteFill>
  );
};

export const Promo: React.FC<{variant: Variant; shots: Shot[]}> = ({
  variant,
  shots,
}) => {
  const visible = shots.filter((s) => variant === 'XHS' || !s.xhsOnly);
  let cursor = 0;

  return (
    <AbsoluteFill>
      <Background variant={variant} />
      {visible.map((shot, i) => {
        const from = cursor;
        const durationInFrames = sec(shot.seconds);
        cursor += durationInFrames;
        return (
          <Sequence
            key={i}
            from={from}
            durationInFrames={durationInFrames}
            name={shot.caption ?? shot.card?.title ?? `shot-${i}`}
          >
            <ShotView shot={shot} variant={variant} />
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};

export const totalFrames = (variant: Variant, shots: Shot[]) =>
  shots
    .filter((s) => variant === 'XHS' || !s.xhsOnly)
    .reduce((n, s) => n + sec(s.seconds), 0);

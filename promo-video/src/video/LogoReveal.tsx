import React from 'react';
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {Audio} from '@remotion/media';

const clamp = {
  extrapolateLeft: 'clamp' as const,
  extrapolateRight: 'clamp' as const,
};

const GlowBackground: React.FC = () => {
  const frame = useCurrentFrame();
  const drift = Math.sin((frame / 150) * Math.PI * 2);
  const breathe = Math.sin((frame / 150) * Math.PI * 2 - Math.PI / 2);

  return (
    <AbsoluteFill style={{backgroundColor: '#05269A', overflow: 'hidden'}}>
      <div
        style={{
          position: 'absolute',
          inset: -260,
          background: [
            `radial-gradient(circle at ${50 + drift * 2.5}% ${37 + drift * 1.5}%, rgba(113, 202, 255, ${0.72 + breathe * 0.05}) 0%, rgba(39, 129, 255, 0.62) 19%, rgba(15, 79, 223, 0.74) 44%, rgba(2, 25, 118, 0.96) 78%)`,
            'linear-gradient(145deg, rgba(26,111,255,.55), rgba(1,16,91,.72))',
          ].join(','),
          scale: 1.03 + breathe * 0.015,
        }}
      />
      <div
        style={{
          position: 'absolute',
          inset: 0,
          opacity: 0.085,
          backgroundImage:
            'url("data:image/svg+xml,%3Csvg viewBox=%270 0 220 220%27 xmlns=%27http://www.w3.org/2000/svg%27%3E%3Cfilter id=%27n%27%3E%3CfeTurbulence type=%27fractalNoise%27 baseFrequency=%27.85%27 numOctaves=%274%27 stitchTiles=%27stitch%27/%3E%3C/filter%3E%3Crect width=%27100%25%27 height=%27100%25%27 filter=%27url(%23n)%27 opacity=%27.5%27/%3E%3C/svg%3E")',
          mixBlendMode: 'soft-light',
        }}
      />
      <div
        style={{
          position: 'absolute',
          inset: 0,
          boxShadow: 'inset 0 0 220px rgba(0, 10, 70, .72)',
        }}
      />
    </AbsoluteFill>
  );
};

const Logo: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const reveal = spring({
    frame: frame - 13,
    fps,
    durationInFrames: 38,
    config: {damping: 18, stiffness: 92, mass: 0.95},
  });
  const settle = Math.sin(((frame - 35) / 115) * Math.PI * 2);
  const blink = interpolate(
    frame,
    [61, 64, 67, 70],
    [0, 1, 1, 0],
    clamp,
  );

  return (
    <div
      style={{
        position: 'absolute',
        top: 258,
        left: '50%',
        width: 568,
        height: 568,
        translate: '-50% 0',
        opacity: interpolate(frame, [8, 24], [0, 1], clamp),
        scale: interpolate(reveal, [0, 1], [0.78, 1], clamp) * (1 + Math.max(0, settle) * 0.008),
      }}
    >
      <div
        style={{
          position: 'absolute',
          inset: -75,
          borderRadius: 190,
          background: 'radial-gradient(circle, rgba(170,224,255,.62) 0%, rgba(50,148,255,.28) 42%, transparent 72%)',
          filter: 'blur(24px)',
          opacity: 0.72 + Math.sin((frame / 150) * Math.PI * 2) * 0.08,
        }}
      />
      <Img
        src={staticFile('brand/icon.png')}
        style={{
          position: 'absolute',
          inset: 0,
          width: '100%',
          height: '100%',
          borderRadius: 126,
          boxShadow: '0 54px 110px rgba(0,16,105,.42), 0 0 65px rgba(180,231,255,.42)',
        }}
      />
      {/* A short eyelid overlay creates one restrained blink while preserving the original mark. */}
      <div style={{position: 'absolute', left: 221, top: 250, width: 18, height: 18, borderRadius: 20, background: '#1575F6', scale: `1 ${blink}`}} />
      <div style={{position: 'absolute', left: 331, top: 250, width: 18, height: 18, borderRadius: 20, background: '#1575F6', scale: `1 ${blink}`}} />
    </div>
  );
};

export const LogoReveal: React.FC<{withAudio: boolean}> = ({withAudio}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const wordmark = spring({
    frame: frame - 64,
    fps,
    durationInFrames: 28,
    config: {damping: 200},
  });
  const badge = spring({
    frame: frame - 91,
    fps,
    durationInFrames: 28,
    config: {damping: 200},
  });
  const contentOpacity = interpolate(frame, [132, 149], [1, 0], clamp);

  return (
    <AbsoluteFill style={{fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif'}}>
      <GlowBackground />
      <AbsoluteFill style={{opacity: contentOpacity}}>
        <Logo />
        <div
          style={{
            position: 'absolute',
            top: 894,
            left: 0,
            right: 0,
            color: '#FFFFFF',
            textAlign: 'center',
            fontSize: 126,
            fontWeight: 650,
            letterSpacing: interpolate(wordmark, [0, 1], [5, -5], clamp),
            opacity: wordmark,
            translate: `0 ${interpolate(wordmark, [0, 1], [28, 0], clamp)}px`,
            textShadow: '0 18px 55px rgba(0, 22, 120, .34)',
          }}
        >
          1Day
        </div>
        <Img
          src={staticFile('brand/app-store-en.png')}
          style={{
            position: 'absolute',
            width: 430,
            left: '50%',
            top: 1112,
            translate: `-50% ${interpolate(badge, [0, 1], [20, 0], clamp)}px`,
            opacity: badge,
            scale: interpolate(badge, [0, 1], [0.97, 1], {
              ...clamp,
              easing: Easing.out(Easing.cubic),
            }),
            filter: 'drop-shadow(0 20px 35px rgba(0, 12, 80, .28))',
          }}
        />
      </AbsoluteFill>
      {withAudio ? (
        <>
          <Audio src={staticFile('audio/ambient.mp3')} volume={0.11} loop />
          <Audio src={staticFile('audio/chime.wav')} from={88} volume={0.36} />
        </>
      ) : null}
    </AbsoluteFill>
  );
};

import React from 'react';
import {Composition, Folder} from 'remotion';
import {Promo, promoVariants} from './video/Promo';
import {LogoReveal} from './video/LogoReveal';

const fps = 30;

export const Root: React.FC = () => (
  <>
    <Folder name="1Day-Logo-Reveal">
      <Composition
        id="LogoReveal5s"
        component={LogoReveal}
        width={1080}
        height={1440}
        fps={fps}
        durationInFrames={5 * fps}
        defaultProps={{withAudio: true}}
      />
      <Composition
        id="LogoReveal5sSilent"
        component={LogoReveal}
        width={1080}
        height={1440}
        fps={fps}
        durationInFrames={5 * fps}
        defaultProps={{withAudio: false}}
      />
    </Folder>
    <Folder name="1Day-Promos">
      {promoVariants.map((variant) => (
        <Composition
          key={variant.id}
          id={variant.id}
          component={Promo}
          width={1080}
          height={1440}
          fps={fps}
          durationInFrames={variant.duration * fps}
          defaultProps={{variantId: variant.id}}
        />
      ))}
    </Folder>
  </>
);

import { useEffect, useRef } from 'react';
import { gsap } from 'gsap';
import './BounceCards.css';

const defaultTransforms = [
  'rotate(10deg) translate(-170px)',
  'rotate(5deg) translate(-85px)',
  'rotate(-3deg)',
  'rotate(-10deg) translate(85px)',
  'rotate(2deg) translate(170px)',
];

function withoutRotation(transform) {
  if (/rotate\([\s\S]*?\)/.test(transform)) {
    return transform.replace(/rotate\([\s\S]*?\)/, 'rotate(0deg)');
  }

  return transform === 'none' ? 'rotate(0deg)' : `${transform} rotate(0deg)`;
}

function withHorizontalOffset(transform, offset) {
  const translatePattern = /translate\(([-0-9.]+)px\)/;
  const match = transform.match(translatePattern);

  if (match) {
    const nextPosition = Number.parseFloat(match[1]) + offset;
    return transform.replace(translatePattern, `translate(${nextPosition}px)`);
  }

  return transform === 'none' ? `translate(${offset}px)` : `${transform} translate(${offset}px)`;
}

export default function BounceCards({
  className = '',
  images = [],
  imageAlts = [],
  containerWidth = 400,
  containerHeight = 400,
  animationDelay = 0.5,
  animationStagger = 0.06,
  easeType = 'elastic.out(1, 0.8)',
  transformStyles = defaultTransforms,
  enableHover = false,
  hoverPushDistance = 160,
}) {
  const containerRef = useRef(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return undefined;

    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const cards = gsap.utils.selector(container)('.bounce-card');
    const context = gsap.context(() => {
      if (reduceMotion) {
        gsap.set(cards, { scale: 1 });
        return;
      }

      gsap.fromTo(
        cards,
        { scale: 0 },
        {
          scale: 1,
          stagger: animationStagger,
          ease: easeType,
          delay: animationDelay,
        },
      );
    }, container);

    return () => {
      gsap.killTweensOf(cards);
      context.revert();
    };
  }, [animationDelay, animationStagger, easeType, images]);

  const animateCards = (hoveredIndex) => {
    if (!enableHover || !containerRef.current) return;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

    const select = gsap.utils.selector(containerRef);

    images.forEach((_, index) => {
      const target = select(`[data-bounce-card="${index}"]`);
      const baseTransform = transformStyles[index] ?? 'none';
      const distance = Math.abs(hoveredIndex - index);
      const transform = index === hoveredIndex
        ? withoutRotation(baseTransform)
        : withHorizontalOffset(baseTransform, index < hoveredIndex ? -hoverPushDistance : hoverPushDistance);

      gsap.killTweensOf(target);
      gsap.to(target, {
        transform,
        duration: 0.4,
        ease: 'back.out(1.4)',
        delay: index === hoveredIndex ? 0 : distance * 0.05,
        overwrite: 'auto',
      });
    });
  };

  const resetCards = () => {
    if (!enableHover || !containerRef.current) return;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

    const select = gsap.utils.selector(containerRef);
    images.forEach((_, index) => {
      const target = select(`[data-bounce-card="${index}"]`);
      gsap.killTweensOf(target);
      gsap.to(target, {
        transform: transformStyles[index] ?? 'none',
        duration: 0.4,
        ease: 'back.out(1.4)',
        overwrite: 'auto',
      });
    });
  };

  return (
    <div
      className={`bounce-cards ${className}`.trim()}
      ref={containerRef}
      style={{ width: `min(100%, ${containerWidth}px)`, height: containerHeight }}
      onMouseLeave={resetCards}
    >
      {images.map((src, index) => (
        <div
          className="bounce-card"
          data-bounce-card={index}
          key={`${src}-${index}`}
          style={{ transform: transformStyles[index] ?? 'none' }}
          onMouseEnter={() => animateCards(index)}
        >
          <img className="bounce-card__image" src={src} alt={imageAlts[index] ?? ''} loading="lazy" />
        </div>
      ))}
    </div>
  );
}

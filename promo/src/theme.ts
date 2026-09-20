// Brand tokens mirrored from landing-page/src/styles.css
export const brand = {
  blue: '#1875ef',
  ink: '#10203a',
  light: '#9dccff',
  paper: '#f8fbff',
  teal: '#0f7d75', // the app's primary action colour
} as const;

export const fontStack =
  '"PingFang SC", "Hiragino Sans GB", "Noto Sans SC", "Helvetica Neue", Arial, sans-serif';

// Source recordings are 886x1920 (the App Store 6.9" portrait preview size,
// which is also the native aspect ratio of an iPhone 17 Pro Max screen).
export const APP_W = 886;
export const APP_H = 1920;
export const FPS = 30;

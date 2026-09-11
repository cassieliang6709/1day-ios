import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { render } from '../.ssr/entry-server.js';

const root = resolve(import.meta.dirname, '..');
const dist = resolve(root, 'dist');
const origin = 'https://1day.liangyue.site';
const pages = [['/', 'zh', 'index.html'], ['/en', 'en', 'en.html'], ['/privacy', 'zh', 'privacy.html'], ['/en/privacy', 'en', 'en/privacy.html'], ['/updates', 'zh', 'updates.html'], ['/en/updates', 'en', 'en/updates.html']];
const metadata = {
  zh: { title: '1Day — 今天，想怎么过？', description: '给今天一个主题，和自己或朋友一起，把它过成一支 Vlog。跟着瞬间提示去经历今天，留下一段值得回看的记忆。', privacyTitle: '1Day 视频日记隐私政策', privacyDescription: '了解 1Day 如何处理单人故事、共享房间和可选提示建议的数据。', og: '/assets/og-zh.png', lang: 'zh-CN' },
  en: { title: '1Day — How do you want to spend today?', description: 'Give today a theme. Live it your way, on your own or with friends, and turn it into a vlog. Follow moment prompts and keep a memory of the day.', privacyTitle: '1Day Video Diary Privacy Policy', privacyDescription: 'Learn how 1Day handles data for solo stories, shared rooms, and optional prompt suggestions.', og: '/assets/og-en.png', lang: 'en' },
};
const template = await readFile(resolve(dist, 'index.html'), 'utf8');
const escape = (value) => value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function documentFor(pathname, locale) {
  const baseMeta = metadata[locale]; const isPrivacy = pathname.endsWith('/privacy'); const isUpdates = pathname.endsWith('/updates'); const meta = isUpdates ? { ...baseMeta, title: locale === 'zh' ? '更新日志 — 1Day' : 'What’s new — 1Day', description: locale === 'zh' ? '看看每个版本带来的新功能与体验改进。' : 'New features and improvements, version by version.' } : isPrivacy ? { ...baseMeta, title: baseMeta.privacyTitle, description: baseMeta.privacyDescription } : baseMeta; const canonical = `${origin}${pathname}`; const translations = isUpdates ? { zh: '/updates', en: '/en/updates' } : isPrivacy ? { zh: '/privacy', en: '/en/privacy' } : { zh: '/', en: '/en' };
  const ld = JSON.stringify({ '@context': 'https://schema.org', '@type': 'SoftwareApplication', name: '1Day', applicationCategory: 'LifestyleApplication', operatingSystem: 'iOS', description: meta.description, url: canonical }).replace(/</g, '\\u003c');
  const seo = `<link rel="canonical" href="${canonical}" /><link rel="alternate" hreflang="zh-CN" href="${origin}${translations.zh}" /><link rel="alternate" hreflang="en" href="${origin}${translations.en}" /><link rel="alternate" hreflang="x-default" href="${origin}${translations.zh}" /><meta property="og:type" content="website" /><meta property="og:site_name" content="1Day" /><meta property="og:locale" content="${locale === 'zh' ? 'zh_CN' : 'en_US'}" /><meta property="og:title" content="${escape(meta.title)}" /><meta property="og:description" content="${escape(meta.description)}" /><meta property="og:url" content="${canonical}" /><meta property="og:image" content="${origin}${meta.og}" /><meta name="twitter:card" content="summary_large_image" /><meta name="twitter:title" content="${escape(meta.title)}" /><meta name="twitter:description" content="${escape(meta.description)}" /><meta name="twitter:image" content="${origin}${meta.og}" /><script type="application/ld+json">${ld}</script>`;
  return template.replace(/<html[^>]*>/, `<html lang="${meta.lang}">`).replace(/<title>[\s\S]*?<\/title>/, `<title>${escape(meta.title)}</title>`).replace(/<meta name="description"[^>]*>/, `<meta name="description" content="${escape(meta.description)}" />`).replace('</head>', `${seo}</head>`).replace('<div id="root"></div>', `<div id="root">${render(pathname)}</div>`);
}
for (const [pathname, locale, filename] of pages) { const target = resolve(dist, filename); await mkdir(dirname(target), { recursive: true }); await writeFile(target, documentFor(pathname, locale)); }
await writeFile(resolve(dist, 'robots.txt'), `User-agent: *\nAllow: /\nSitemap: ${origin}/sitemap.xml\n`);
await writeFile(resolve(dist, 'sitemap.xml'), `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>${origin}/</loc></url><url><loc>${origin}/en</loc></url><url><loc>${origin}/privacy</loc></url><url><loc>${origin}/en/privacy</loc></url><url><loc>${origin}/updates</loc></url><url><loc>${origin}/en/updates</loc></url></urlset>\n`);
await rm(resolve(root, '.ssr'), { recursive: true, force: true });

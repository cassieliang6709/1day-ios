import { renderToStaticMarkup } from 'react-dom/server';
import { App } from './App.jsx';
export function render(pathname) { return renderToStaticMarkup(<App pathname={pathname} />); }

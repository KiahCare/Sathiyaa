/**
 * A static file server for the Flutter web builds.
 *
 * Deliberately dependency-free: `npx serve` needs the network, and these
 * machines are meant to work offline.
 *
 *   node static-server.mjs <port> <directory>
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const port = Number(process.argv[2]);
const root = path.resolve(process.argv[3]);

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.otf': 'font/otf', '.ttf': 'font/ttf',
  '.woff': 'font/woff', '.woff2': 'font/woff2', '.wasm': 'application/wasm',
  '.bin': 'application/octet-stream', '.map': 'application/json; charset=utf-8',
};

http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  let file = path.join(root, url);
  // Anything outside the served directory is a path-traversal attempt.
  if (!file.startsWith(root)) { res.writeHead(403).end('Forbidden'); return; }
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    const index = path.join(file, 'index.html');
    // Single-page app: unknown routes fall back to index.html.
    file = fs.existsSync(index) ? index : path.join(root, 'index.html');
  }
  if (!fs.existsSync(file)) { res.writeHead(404).end('Not found'); return; }
  res.writeHead(200, {
    'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream',
    // Flutter's service worker caches aggressively; during development the
    // whole point is to see the build you just made.
    'Cache-Control': 'no-store',
    // Needed for the CanvasKit renderer.
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'credentialless',
  });
  fs.createReadStream(file).pipe(res);
}).listen(port, () => console.log(`serving ${root} on http://localhost:${port}`));

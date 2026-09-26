/**
 * Bundles the Admin / Business Partner portal into one self-contained .html.
 *
 * Vite normally emits index.html plus separate JS, CSS and image files, which
 * needs a web server. This produces a single file that opens from anywhere —
 * a hosted URL, a phone, or a double-click — by inlining the script, the
 * stylesheet and the one runtime image as data URIs.
 *
 * It builds in mock-data mode on purpose. A file served from somewhere else
 * cannot reach an API running on your own machine, so the deployed copy is
 * the self-contained demo; point the local build at the real backend instead.
 *
 *   node build-single-file.mjs [outfile]
 */
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const dist = path.join(here, 'dist');
const outFile = process.argv[2] || path.join(here, 'sathiyaa-admin-portal.html');

// ---------------------------------------------------------------- build ---
console.log('[single-file] building…');
execFileSync(process.execPath, [path.join(here, 'node_modules', 'vite', 'bin', 'vite.js'), 'build'], {
  cwd: here,
  stdio: 'inherit',
  env: {
    ...process.env,
    // No server to rewrite paths, so routes live in the hash.
    VITE_HASH_ROUTER: 'true',
    // Explicit rather than relying on the default.
    VITE_USE_MOCK: 'true',
  },
});

// ---------------------------------------------------------------- inline ---
let html = fs.readFileSync(path.join(dist, 'index.html'), 'utf8');

/** Replaces a <script src> / <link href> with the file's contents. */
function inlineAssets() {
  html = html.replace(
    /<script[^>]*src="([^"]+)"[^>]*><\/script>/g,
    (_m, src) => `<script type="module">\n${read(src)}\n</script>`
  );
  html = html.replace(
    /<link[^>]*rel="stylesheet"[^>]*href="([^"]+)"[^>]*>/g,
    (_m, href) => `<style>\n${read(href)}\n</style>`
  );
}

function read(urlPath) {
  const file = path.join(dist, urlPath.replace(/^\//, ''));
  return fs.readFileSync(file, 'utf8');
}

inlineAssets();

// The logo is referenced by string from React, so Vite never sees it. Use the
// 256px mark — it renders at 26-46px, and the full-size file would add a
// quarter of a megabyte of base64 for nothing.
const logo = fs.readFileSync(path.join(here, 'public', 'logo', 'sathiyaa-mark-256.png'));
const logoDataUri = `data:image/png;base64,${logo.toString('base64')}`;
html = html.replaceAll('/logo/sathiyaa-mark.png', logoDataUri);
html = html.replaceAll('/logo/sathiyaa-mark-256.png', logoDataUri);

// The favicon lives at a path that will not exist; drop the tag rather than
// ship a broken request.
html = html.replace(/<link[^>]*rel="icon"[^>]*>/g, '');

// A note for anyone who opens the file and wonders what they are looking at.
html = html.replace(
  '<head>',
  `<head>
    <!--
      Sathiyaa - Admin & Business Partner Portal.
      Single-file build: script, styles and logo are inlined, so this runs from
      any URL with no server. Built in demo-data mode - nothing here touches a
      real database. Regenerate with: node build-single-file.mjs
    -->`
);

fs.writeFileSync(outFile, html, 'utf8');

const kb = (n) => `${Math.round(n / 1024)} KB`;
console.log(`[single-file] wrote ${outFile} (${kb(Buffer.byteLength(html))})`);
if (/src="\/|href="\//.test(html)) {
  console.warn('[single-file] WARNING: an absolute asset path survived — it will 404 when hosted.');
  process.exitCode = 1;
}

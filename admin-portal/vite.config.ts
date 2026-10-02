import { readFileSync } from 'node:fs'

import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'vite'

// The console's version comes from package.json, so `npm version minor` is the
// only edit a release needs. It used to be the string "v1.0" typed into the
// sidebar, which is the kind of copy that is wrong within a fortnight and that
// nobody thinks to check -- a console reporting v1.0 while talking to a 1.4 API
// makes a bug report point at the wrong month.
const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8'))

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  define: {
    __APP_VERSION__: JSON.stringify(pkg.version),
    // Set by the build pipeline; a version says what was meant to ship, the
    // commit says what did.
    __BUILD_SHA__: JSON.stringify(process.env.BUILD_SHA ?? null),
  },
  build: {
    // One bundle is the point here - the admin console is also shipped as a
    // single self-contained file - so the default 500 kB warning is noise.
    chunkSizeWarningLimit: 2000,
  },
  server: {
    host: true,
    port: 5173,
  },
})

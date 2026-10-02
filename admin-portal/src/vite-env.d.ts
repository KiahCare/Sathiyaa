/// <reference types="vite/client" />

/**
 * Values Vite substitutes at build time, declared in `vite.config.ts`.
 *
 * They are compile-time constants, not variables, so they are declared here
 * rather than read off `import.meta.env` — which would put the version in the
 * environment file and make it one more thing to remember to change.
 */
declare const __APP_VERSION__: string;
declare const __BUILD_SHA__: string | null;

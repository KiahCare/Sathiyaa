// Loaded into every test script by run-all.ps1, as:
//
//     node --import file:///.../lib/preamble.mjs  some-test.mjs
//
// It exists so that pointing the suite at a deployment does not mean editing
// eighteen files. A public deployment puts the whole API behind a shared key
// (middleware/accessKey.js); without it every call comes back 401 and the suite
// reports the server as comprehensively broken rather than as locked.
//
// Three of the scripts send the header themselves. Wrapping fetch here rather
// than adding a header to fourteen hand-rolled header blocks keeps the change
// in one place, and leaves every script runnable on its own exactly as before
// — with no key set this file does nothing at all.

const KEY = process.env.API_ACCESS_KEY || '';

if (KEY) {
  const inner = globalThis.fetch;

  globalThis.fetch = function fetchWithAccessKey(input, init) {
    // Only the plain (url, init) form is used anywhere in this suite. Anything
    // else — a Request object, say — is passed through untouched rather than
    // half-handled.
    if (typeof input !== 'string' && !(input instanceof URL)) {
      return inner(input, init);
    }

    const opts = { ...(init || {}) };
    const headers = new Headers(opts.headers || {});
    // A script that already sets the header wins; it may be testing a wrong one.
    if (!headers.has('X-Sathiyaa-Key')) headers.set('X-Sathiyaa-Key', KEY);
    opts.headers = headers;

    return inner(input, opts);
  };

  console.log(`[preamble] sending X-Sathiyaa-Key (${KEY.length} chars) on every request`);
}

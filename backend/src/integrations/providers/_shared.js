/**
 * Helpers shared by the real (non-stub) integration adapters.
 *
 * Every adapter follows the same shape: it declares which environment
 * variables it cannot work without, and `requireConfig` refuses to let the
 * server start without them. The point is that a half-configured integration
 * fails at boot with a message naming the missing variable, rather than
 * failing silently the first time a customer tries to pay.
 */

/** Thrown at startup when a selected provider is missing its credentials. */
export class IntegrationConfigError extends Error {
  constructor(provider, missing) {
    super(
      `${provider} is selected but not configured. Set: ${missing.join(', ')}. ` +
        `Leave the *_PROVIDER variable unset (or "stub") to keep running without it.`
    );
    this.name = 'IntegrationConfigError';
    this.provider = provider;
    this.missing = missing;
  }
}

export function requireConfig(provider, values) {
  const missing = Object.entries(values)
    .filter(([, v]) => v === undefined || v === null || v === '')
    .map(([k]) => k);
  if (missing.length) throw new IntegrationConfigError(provider, missing);
}

const DEFAULT_TIMEOUT_MS = 15000;

/**
 * JSON over HTTP with a timeout and errors that say which provider failed and
 * what it said, so a failure in the field is diagnosable from the log alone.
 */
export async function httpJson(provider, url, { method = 'GET', headers = {}, body, form, timeoutMs = DEFAULT_TIMEOUT_MS } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      method,
      headers: {
        Accept: 'application/json',
        ...(form ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {}),
        ...(body ? { 'Content-Type': 'application/json' } : {}),
        ...headers,
      },
      body: form ? new URLSearchParams(form).toString() : body ? JSON.stringify(body) : undefined,
      signal: controller.signal,
    });

    const text = await res.text();
    let json;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      json = null;
    }

    if (!res.ok) {
      const detail = json ? JSON.stringify(json).slice(0, 400) : text.slice(0, 400);
      const err = new Error(`[${provider}] ${method} ${hostOf(url)} failed (${res.status}): ${detail}`);
      err.status = res.status;
      err.provider = provider;
      err.responseBody = json ?? text;
      throw err;
    }
    return json;
  } catch (err) {
    if (err.name === 'AbortError') {
      throw new Error(`[${provider}] request to ${hostOf(url)} timed out after ${timeoutMs}ms`);
    }
    throw err;
  } finally {
    clearTimeout(timer);
  }
}

/** Fetches a remote image as a Buffer — face matching needs the bytes. */
export async function fetchBinary(provider, url, timeoutMs = DEFAULT_TIMEOUT_MS) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) throw new Error(`[${provider}] could not fetch ${hostOf(url)} (${res.status})`);
    return Buffer.from(await res.arrayBuffer());
  } finally {
    clearTimeout(timer);
  }
}

function hostOf(url) {
  try {
    return new URL(url).host;
  } catch {
    return url;
  }
}

export function basicAuth(user, pass) {
  return `Basic ${Buffer.from(`${user}:${pass}`).toString('base64')}`;
}

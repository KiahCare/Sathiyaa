import axios from 'axios';

export const API_BASE_URL =
  (import.meta.env.VITE_API_BASE_URL as string) || 'http://localhost:4000/api/v1';

// VITE_USE_MOCK defaults to true when unset so the app is demoable standalone
// without a running backend (see .env.example / README.md).
export const USE_MOCK = (import.meta.env.VITE_USE_MOCK as string | undefined) !== 'false';

/**
 * The shared key a public deployment requires on every call.
 *
 * Baked into the bundle at build time, so anyone who opens devtools on the
 * console can read it. That is understood: it is a door on the building, not a
 * lock on the safe. What it stops is an unauthenticated scanner finding the API
 * and walking through a registration flow that hands back one-time codes.
 *
 * Empty by default, so a local server with no key configured is unaffected.
 */
export const API_ACCESS_KEY = (import.meta.env.VITE_API_ACCESS_KEY as string) || '';

export const apiClient = axios.create({
  baseURL: API_BASE_URL,
  timeout: 15000,
});

apiClient.interceptors.request.use((config) => {
  config.headers = config.headers ?? {};
  const token = localStorage.getItem('sathiyaa_token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  if (API_ACCESS_KEY) {
    config.headers['X-Sathiyaa-Key'] = API_ACCESS_KEY;
  }
  return config;
});

/**
 * Turns a failed request into an error carrying the *server's* wording.
 *
 * Axios's own message is "Request failed with status code 404", which tells
 * nobody anything. The API always replies with {error:{code,message}}, so that
 * is what the screens should show.
 */
function toApiError(error: any): ApiRequestError {
  const status = error?.response?.status;
  const payload = error?.response?.data?.error;
  if (payload?.message) {
    return new ApiRequestError(payload.code ?? `HTTP_${status}`, payload.message, status);
  }
  if (error?.code === 'ECONNABORTED') {
    return new ApiRequestError('TIMEOUT', 'The server took too long to answer. Is it still running?', status);
  }
  if (!error?.response) {
    return new ApiRequestError(
      'NETWORK',
      `Could not reach the API at ${API_BASE_URL}. Check that the backend is running.`,
    );
  }
  return new ApiRequestError(`HTTP_${status}`, error.message ?? 'The request failed.', status);
}

apiClient.interceptors.response.use(
  (res) => res,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('sathiyaa_token');
      localStorage.removeItem('sathiyaa_user');
      if (!window.location.pathname.startsWith('/login')) {
        window.location.assign('/login');
      }
    }
    return Promise.reject(toApiError(error));
  }
);

export class ApiRequestError extends Error {
  code: string;
  status?: number;
  constructor(code: string, message: string, status?: number) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

/** Simulated network latency for the mock adapter, so loading states are visible. */
export function mockDelay(ms = 380): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Resolve a stored `*_url` value into something a browser can actually load.
 *
 * Uploaded files are served from the API host at `/uploads/...`, while the
 * console is served from a different origin entirely (its own CloudFront
 * distribution, backed by S3). Rendering the stored path straight into an
 * `<img src>` or an `<a href>` resolves it against the *console's* origin, so
 * the browser asks S3 for `/uploads/...`, S3 has no such key, and the SPA
 * fallback rewrites the 404 to `index.html` with a 200. The result is an image
 * tag holding a page of HTML, which renders as nothing and reports no error.
 *
 * Three shapes arrive here:
 *   - a `data:` URI (the seeded placeholder avatars) -- already self-contained
 *   - an absolute http(s) URL -- left alone
 *   - `/uploads/...` -- the only one that needs the API origin in front
 *
 * Anything else is a path from somebody's phone that was stored by mistake;
 * it is not loadable from anywhere, so this returns undefined and the caller
 * shows its "not uploaded" state instead of a broken image.
 */
export function uploadUrl(ref: string | null | undefined): string | undefined {
  if (!ref) return undefined;
  if (ref.startsWith('data:') || ref.startsWith('http://') || ref.startsWith('https://')) return ref;
  if (!ref.startsWith('/uploads/')) return undefined;
  return API_BASE_URL.replace(/\/api\/v\d+\/?$/, '') + ref;
}

import { env } from './env.js';

/**
 * Refuses to start when the configuration is unsafe for a server that
 * strangers can reach.
 *
 * The checks hang off PUBLIC_DEPLOYMENT rather than NODE_ENV on purpose. This
 * deployment runs with NODE_ENV=development so the one-time code still appears
 * on screen — no SMS provider is wired up yet, and without either one nobody
 * could log in at all. That is a deliberate decision, but it must not quietly
 * bring the *rest* of the development defaults along with it: a shared JWT
 * secret, an open CORS policy and an unthrottled login endpoint are fine on a
 * laptop and are not fine on the internet.
 *
 * So: one flag says "people other than me can reach this", and everything that
 * matters keys off that.
 */

const PLACEHOLDER_SECRETS = new Set([
  'dev-secret',
  'change-this-in-production-please',
  'changeme',
  'secret',
]);

export function preflight() {
  const problems = [];
  const warnings = [];

  if (env.publicDeployment) {
    // A forgeable token is the whole game: sign your own with role "admin" and
    // every endpoint in admin.routes.js opens.
    if (!process.env.JWT_SECRET) {
      problems.push('JWT_SECRET is not set. Anyone who has seen this repository can forge a super-admin token.');
    } else if (PLACEHOLDER_SECRETS.has(process.env.JWT_SECRET)) {
      problems.push(`JWT_SECRET is still the placeholder "${process.env.JWT_SECRET}".`);
    } else if (process.env.JWT_SECRET.length < 32) {
      problems.push(`JWT_SECRET is ${process.env.JWT_SECRET.length} characters. Use at least 32 — "openssl rand -base64 48".`);
    }

    if (!env.db.password) {
      problems.push('DB_PASSWORD is empty.');
    }

    if (env.corsOrigins.length === 0) {
      problems.push('CORS_ORIGINS is empty. Set it to the admin console address, comma separated, so a page on another domain cannot drive this API.');
    }

    // The access key is what stands between an echoed OTP and anyone who finds
    // the hostname. Without SMS, requesting a code for a number returns the
    // code, so an open endpoint is an open account.
    if (!env.accessKey) {
      problems.push(
        'API_ACCESS_KEY is empty. While the one-time code is returned in the response ' +
        '(NODE_ENV is not "production"), an unauthenticated caller can request a code for ' +
        'any registered mobile number and read it. The key is what keeps that off the open internet.'
      );
    } else if (env.accessKey.length < 24) {
      problems.push(`API_ACCESS_KEY is ${env.accessKey.length} characters. Use at least 24.`);
    }

    if (!env.isProd) {
      warnings.push(
        'NODE_ENV is not "production", so the one-time code is returned in the ' +
        'response body and shown on screen. That is what you asked for while no SMS ' +
        'provider is configured. It means anybody who has the API access key can sign ' +
        'in as any registered number — treat the key as a password and do not put it ' +
        'in a public repository or a screenshot.'
      );
    }

    if (env.uploadDir.includes('backend') && !process.env.UPLOAD_DIR) {
      warnings.push(
        'UPLOAD_DIR is not set, so uploads land inside the application folder. ' +
        'Point it at a mounted volume, or they vanish the next time the instance ' +
        'is replaced.'
      );
    }
  }

  for (const w of warnings) {
    console.warn(`[preflight] NOTE: ${w}`);
  }

  if (problems.length > 0) {
    console.error('\n[preflight] refusing to start — PUBLIC_DEPLOYMENT is on and this configuration is not safe to expose:\n');
    for (const p of problems) console.error(`  * ${p}`);
    console.error('\n  Fix these in backend/.env. See .env.example for what each one is for.\n');
    process.exit(1);
  }

  if (env.publicDeployment) {
    console.log('[preflight] public deployment checks passed.');
  }
}

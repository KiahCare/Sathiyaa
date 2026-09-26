import { createApp } from './app.js';
import { env } from './config/env.js';
import { preflight } from './config/preflight.js';
import { pingDb } from './db/pool.js';
import { startJobs, stopJobs } from './jobs/index.js';
import { assertIntegrationsConfigured, logIntegrationStatus } from './integrations/index.js';

async function main() {
  // Before anything else: refuse to start unsafely exposed.
  preflight();

  // Then refuse to start half-configured. A selected payment provider with no
  // secret must not become a runtime surprise.
  try {
    assertIntegrationsConfigured();
  } catch (err) {
    console.error(`[integrations] ${err.message}`);
    process.exit(1);
  }
  logIntegrationStatus();

  try {
    await pingDb();
    console.log(`[db] connected to ${env.db.host}:${env.db.port}/${env.db.database}`);
  } catch (err) {
    console.error('[db] failed to connect. Did you run `npm run migrate`?', err.message);
    process.exit(1);
  }

  const app = createApp();
  const server = app.listen(env.port, () => {
    console.log(`[server] Sathiyaa API listening on port ${env.port} (env=${env.nodeEnv})`);
    if (env.publicDeployment) {
      console.log('[server] public deployment: access key required, CORS limited to ' +
        env.corsOrigins.join(', '));
    }
  });

  startJobs();

  const shutdown = () => {
    console.log('\n[server] shutting down...');
    stopJobs();
    server.close(() => process.exit(0));
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main();

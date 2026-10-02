import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import multer from 'multer';
import { attachAudit } from './middleware/audit.js';
import { requireAccessKey } from './middleware/accessKey.js';
import { generalLimiter, authLimiter } from './middleware/rateLimit.js';
import { notFoundHandler, errorHandler } from './middleware/errorHandler.js';
import apiRoutes from './routes/index.js';
import { env } from './config/env.js';
import { buildInfo } from './config/version.js';

export function createApp() {
  const app = express();

  // Behind CloudFront or an ALB the caller's address arrives in
  // X-Forwarded-For. A hop count rather than `true`: trusting the header
  // blindly lets anyone spoof their own address and walk around the rate
  // limiter one fake IP at a time.
  if (env.trustProxyHops > 0) app.set('trust proxy', env.trustProxyHops);

  // Sensible security headers. contentSecurityPolicy is off because this
  // process serves an API and uploaded files, not pages; the console is a
  // separate static origin with its own headers.
  app.use(helmet({ contentSecurityPolicy: false, crossOriginResourcePolicy: { policy: 'cross-origin' } }));

  // An open CORS policy is fine on a laptop and is not fine in front of an
  // admin API. With no origins configured this behaves exactly as before.
  app.use(
    cors(
      env.corsOrigins.length > 0
        ? { origin: env.corsOrigins, credentials: false }
        : undefined
    )
  );

  app.use(express.json({ limit: '5mb' }));
  app.use(morgan(env.isProd ? 'combined' : 'dev'));
  app.use(attachAudit);

  // Before the limiter, and before the access key: a load balancer needs to be
  // able to ask whether this process is alive without a credential.
  // Which build is actually answering.
  //
  // Unauthenticated on purpose: this is what a load balancer polls and what
  // somebody checks first when the console and the API disagree about
  // something. It says what the build is, never anything about who is using it.
  app.get('/health', (req, res) => res.json({
    ok: true, env: env.nodeEnv, time: new Date().toISOString(), ...buildInfo,
  }));

  app.use(generalLimiter);

  // Uploaded photos and documents. Served straight from disk here; a
  // deployment would put these behind a CDN or object store instead.
  //
  // THIS PATH IS NOT AUTHENTICATED, AND THAT IS A KNOWN GAP.
  //
  // It sits above the access-key check deliberately, because it has to: the
  // console renders these with `<img src>`, which cannot send a header, and
  // every stored URL is already a bare path. What protects a file is that its
  // name is sixteen random bytes and is only ever handed to the people entitled
  // to it — a capability URL. That is a real mechanism, and it is weaker than
  // an access check in two specific ways: a URL that leaks stays valid forever,
  // and nothing records who fetched it.
  //
  // These are identity papers, police verifications and medical certificates,
  // so the gap is written down rather than left to be discovered. SECURITY.md
  // says what closes it and when. Until then the three headers below are what
  // can be done without a client change:
  //
  //   private      keeps CloudFront and any corporate proxy from storing
  //                somebody's Aadhaar card in a shared cache. It was `public`
  //                for seven days.
  //   nosniff      never let a stored file be interpreted as a script.
  //   noindex      a URL that escapes into a crawler's hands does not then
  //                escape into a search index.
  app.use(
    '/uploads',
    express.static(env.uploadDir, {
      fallthrough: true,
      index: false,
      setHeaders: (res) => {
        res.set('Cache-Control', 'private, max-age=604800');
        res.set('X-Content-Type-Options', 'nosniff');
        res.set('X-Robots-Tag', 'noindex, nofollow');
      },
    })
  );

  // The order matters. The key is checked first, so an unauthenticated
  // scanner gets 401 on every path rather than a working registration flow.
  // Then sign-in and code-request endpoints get their own tighter limit.
  app.use('/api/v1', requireAccessKey);
  app.use('/api/v1/auth', authLimiter);
  app.use('/api/v1', apiRoutes);

  // Multer reports "too big" and "too many files" as its own error type;
  // translate them into the standard envelope rather than a 500.
  app.use((err, req, res, next) => {
    if (err instanceof multer.MulterError) {
      const message =
        err.code === 'LIMIT_FILE_SIZE'
          ? 'That file is larger than the 8 MB limit.'
          : `Upload rejected: ${err.message}`;
      return res.status(422).json({ error: { code: err.code, message } });
    }
    return next(err);
  });

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}

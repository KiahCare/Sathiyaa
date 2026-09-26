import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import dotenv from 'dotenv';

const backendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

// Loaded by absolute path rather than from the working directory. dotenv
// defaults to `${cwd}/.env`, so a script started from anywhere but the backend
// folder -- a smoke test, a cron job, a service whose working directory is set
// elsewhere -- would find no file and fall back to every default in silence,
// which looks like the config being ignored rather than never read.
dotenv.config({ path: path.join(backendRoot, '.env') });

/**
 * TLS for the database connection, off unless DB_SSL=true.
 *
 * A managed database reached over a network is exactly where this belongs, and
 * RDS can be set to refuse anything else (`require_secure_transport`). Off by
 * default so a laptop talking to a MySQL on localhost is unaffected.
 *
 * DB_SSL_CA should point at RDS's certificate bundle, which the RDS console
 * itself hands you the command for:
 *   curl -o global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
 *
 * Without it the traffic is still encrypted, but the server's certificate is
 * not checked -- which stops somebody reading the password off the wire and
 * does not stop somebody answering in the database's place.
 */
function databaseTls() {
  if ((process.env.DB_SSL || '').toLowerCase() !== 'true') return undefined;

  const caPath = process.env.DB_SSL_CA;
  if (!caPath) {
    console.warn(
      '[db] DB_SSL is on but DB_SSL_CA is not set, so the connection is encrypted ' +
        'without verifying who is on the other end. Download the RDS bundle and point ' +
        'DB_SSL_CA at it.'
    );
    return { rejectUnauthorized: false };
  }

  return { ca: fs.readFileSync(caPath, 'utf8'), rejectUnauthorized: true };
}

export const env = {
  port: parseInt(process.env.PORT || '4000', 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  isProd: process.env.NODE_ENV === 'production',

  /// True on anything strangers can reach.
  ///
  /// Deliberately separate from NODE_ENV. This deployment runs with
  /// NODE_ENV=development so the one-time code still comes back in the
  /// response — there is no SMS provider yet, and without one or the other
  /// nobody could log in. That decision must not also hand over the rest of
  /// the development defaults, so every guard that matters keys off this flag
  /// instead. config/preflight.js refuses to start when it is on and the
  /// configuration is not safe to expose.
  publicDeployment: process.env.PUBLIC_DEPLOYMENT === 'true',

  /// Origins the admin console is served from. Empty means "allow any", which
  /// preflight rejects for a public deployment.
  corsOrigins: (process.env.CORS_ORIGINS || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean),

  /// A shared key every caller sends in X-Sathiyaa-Key. See
  /// middleware/accessKey.js for what it is and is not for.
  accessKey: process.env.API_ACCESS_KEY || '',

  /// How many proxies sit in front of this process. Behind CloudFront or an
  /// ALB it is 1; get it wrong and rate limiting counts every request against
  /// the proxy's address instead of the caller's.
  trustProxyHops: parseInt(process.env.TRUST_PROXY_HOPS || '0', 10),

  /// The seeded super-admin. Read from the environment so a deployment does
  /// not ship with the password that is printed in the repository.
  admin: {
    email: process.env.ADMIN_EMAIL || 'admin@sathiyaa.com',
    password: process.env.ADMIN_PASSWORD || 'Admin@123',
  },

  db: {
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '3306', 10),
    database: process.env.DB_NAME || 'sathiyaa',
    user: process.env.DB_USER || 'sathiyaa_app',
    password: process.env.DB_PASSWORD || '',
    ssl: databaseTls(),
  },

  jwt: {
    secret: process.env.JWT_SECRET || 'dev-secret',
    expiresIn: process.env.JWT_EXPIRES_IN || '7d',
  },

  otpTtlMinutes: parseInt(process.env.OTP_TTL_MINUTES || '10', 10),
  bookingPaymentWindowMinutes: parseInt(process.env.BOOKING_PAYMENT_WINDOW_MINUTES || '15', 10),
  bookingRequestStaleMinutes: parseInt(process.env.BOOKING_REQUEST_STALE_MINUTES || '30', 10),
  startServiceGeofenceKm: parseFloat(process.env.START_SERVICE_GEOFENCE_KM || '0.5'),

  /// Third-party integrations. Every one of these defaults to `stub`, so a
  /// fresh checkout runs end-to-end with no accounts, no keys and no bills.
  /// Setting a provider name switches that integration to the real service;
  /// the adapter then refuses to start unless its keys are present, so a
  /// half-configured integration fails loudly at boot rather than silently
  /// at 2am.
  integrations: {
    payment: process.env.PAYMENT_PROVIDER || 'stub', // stub | razorpay
    sms: process.env.SMS_PROVIDER || 'stub', // stub | msg91 | twilio
    faceMatch: process.env.FACE_PROVIDER || 'stub', // stub | rekognition | azure
    maps: process.env.MAPS_PROVIDER || 'stub', // stub | osm (free, no key) | google
    push: process.env.PUSH_PROVIDER || 'stub', // stub | fcm
    call: process.env.CALL_PROVIDER || 'stub', // stub | exotel
  },

  razorpay: {
    keyId: process.env.RAZORPAY_KEY_ID || '',
    keySecret: process.env.RAZORPAY_KEY_SECRET || '',
    webhookSecret: process.env.RAZORPAY_WEBHOOK_SECRET || '',
  },

  msg91: {
    authKey: process.env.MSG91_AUTH_KEY || '',
    senderId: process.env.MSG91_SENDER_ID || '',
    otpTemplateId: process.env.MSG91_OTP_TEMPLATE_ID || '',
    smsTemplateId: process.env.MSG91_SMS_TEMPLATE_ID || '',
  },

  twilio: {
    accountSid: process.env.TWILIO_ACCOUNT_SID || '',
    authToken: process.env.TWILIO_AUTH_TOKEN || '',
    fromNumber: process.env.TWILIO_FROM_NUMBER || '',
  },

  azureFace: {
    endpoint: process.env.AZURE_FACE_ENDPOINT || '',
    key: process.env.AZURE_FACE_KEY || '',
    // Similarity below this is treated as "not the same person".
    threshold: parseFloat(process.env.FACE_MATCH_THRESHOLD || '0.6'),
  },

  /// Settings every face provider shares, so switching from the stub to
  /// Rekognition does not quietly move the bar for "the same person".
  faceMatch: {
    threshold: parseFloat(process.env.FACE_MATCH_THRESHOLD || '0.6'),
    timeoutMs: parseInt(process.env.FACE_TIMEOUT_MS || '12000', 10),
  },

  /// AWS, for Rekognition. Everything else on AWS is reached by the instance
  /// itself rather than by key, so this block exists only for the face check
  /// -- and it is read from the server's own .env, never from anything
  /// checked in. See docs/AWS-REKOGNITION.md.
  ///
  /// Left blank the adapter refuses rather than guesses: `verifyFace` returns
  /// `rekognition_not_configured` and the arrival check fails closed.
  aws: {
    region: process.env.AWS_REGION || 'ap-south-1',
    accessKeyId: process.env.AWS_ACCESS_KEY_ID || '',
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || '',
    // Only set when the credentials came from a role rather than an IAM user.
    sessionToken: process.env.AWS_SESSION_TOKEN || '',
  },

  googleMaps: {
    apiKey: process.env.GOOGLE_MAPS_API_KEY || '',
  },

  fcm: {
    projectId: process.env.FCM_PROJECT_ID || '',
    clientEmail: process.env.FCM_CLIENT_EMAIL || '',
    // The service-account private key is pasted into .env with its newlines
    // escaped as backslash-n; turn them back into real newlines so the RS256
    // signer can read the PEM.
    privateKey: (process.env.FCM_PRIVATE_KEY || '').replace(/\\n/g, '\n'),
  },

  exotel: {
    sid: process.env.EXOTEL_SID || '',
    apiKey: process.env.EXOTEL_API_KEY || '',
    apiToken: process.env.EXOTEL_API_TOKEN || '',
    callerId: process.env.EXOTEL_CALLER_ID || '',
    subdomain: process.env.EXOTEL_SUBDOMAIN || 'api.exotel.com',
  },

  /// Where uploaded photos and documents are written. Point this at a mounted
  /// volume in a real deployment, or swap the storage engine in
  /// controllers/uploadController.js for S3/Azure Blob.
  uploadDir: process.env.UPLOAD_DIR
    ? path.resolve(process.env.UPLOAD_DIR)
    : path.join(backendRoot, 'uploads'),
};

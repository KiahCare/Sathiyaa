/**
 * File uploads.
 *
 * Every "upload" in the requirements doc — customer photo, prescription,
 * provider photo, Aadhar, police verification, work certificate, medical
 * certificate, broadcast image — is the same operation: take a file, store it,
 * hand back a URL that goes into the relevant `*_url` column. So there is one
 * endpoint rather than eight, and the column it eventually lands in is the
 * caller's business.
 *
 * Files are written to `backend/uploads/<category>/` and served back as static
 * files from `/uploads/...`. That is deliberately the simplest thing that
 * works locally; a deployment would point `UPLOAD_DIR` at a mounted volume, or
 * swap the storage engine here for S3/Azure Blob without touching any caller.
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

import { Errors } from '../utils/apiError.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { env } from '../config/env.js';

/** What a file is for. Keeps the storage tidy and lets limits differ later. */
const CATEGORIES = new Set([
  'photo',
  'prescription',
  'aadhar',
  'police-verification',
  'work-certificate',
  'medical-certificate',
  // An organisation's certificate of incorporation, shops-and-establishment
  // licence, society or trust registration.
  //
  // This was missing, and the provider app has been sending it since the
  // organisation registration path was built: `api_backend.dart` maps
  // orgRegistrationUrl to the category 'org-registration', which failed the
  // check below with a 400. Registration catches that failure deliberately so
  // a bad upload does not lose the account — so every organisation that ever
  // registered through the app did so with its registration certificate
  // silently dropped, and the only sign was a line in the debug console.
  'org-registration',
  'broadcast',
  'selfie',
]);

const ALLOWED = {
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp',
  'image/heic': '.heic',
  'application/pdf': '.pdf',
};

export const MAX_UPLOAD_BYTES = 8 * 1024 * 1024; // 8 MB

export function uploadRoot() {
  return env.uploadDir;
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

/**
 * The caller may send `category` as a query param or a form field; multer has
 * already put the file on `req.file`.
 */
export const uploadFile = asyncHandler(async (req, res) => {
  if (!req.file) {
    throw Errors.badRequest('NO_FILE', 'Attach a file in the "file" field of a multipart/form-data request');
  }

  const category = String(req.query.category || req.body.category || 'photo').toLowerCase();
  if (!CATEGORIES.has(category)) {
    throw Errors.badRequest(
      'VALIDATION',
      `category must be one of: ${[...CATEGORIES].join(', ')}`
    );
  }

  const ext = ALLOWED[req.file.mimetype];
  if (!ext) {
    throw Errors.unprocessable(
      'UNSUPPORTED_TYPE',
      `${req.file.mimetype} is not accepted. Send a JPEG, PNG, WebP, HEIC or PDF.`
    );
  }

  // Owner-scoped, random filename: nothing about the stored name leaks who the
  // file belongs to, and two uploads never collide.
  const dir = path.join(uploadRoot(), category);
  ensureDir(dir);
  const name = `${Date.now()}-${crypto.randomBytes(8).toString('hex')}${ext}`;
  const dest = path.join(dir, name);
  await fs.promises.writeFile(dest, req.file.buffer);

  const relative = `/uploads/${category}/${name}`;

  // `url` is relative, deliberately, and this is the second attempt at it.
  //
  // It used to be `${req.protocol}://${req.get('host')}${relative}`, which is
  // right on a laptop and wrong behind a CDN. CloudFront forwards every header
  // except Host, so `req.get('host')` is the origin's own name and the scheme
  // is the http of the internal hop -- producing
  // `http://ec2-<origin>.ap-south-1.compute.amazonaws.com/uploads/...`.
  // That address is missing the port, is not https, and points at an instance
  // whose only open port is closed to everyone but CloudFront. Customer photos
  // uploaded through the deployed app were stored with exactly that URL and
  // could never be displayed again.
  //
  // A relative path cannot be wrong in that way. Every client already knows
  // its own API address and resolves against it: both apps have absoluteUrl()
  // and the console has uploadUrl().
  await req.audit('Upload', 'CREATE', { category, bytes: req.file.size, url: relative });

  res.status(201).json({
    url: relative,
    path: relative,
    category,
    contentType: req.file.mimetype,
    bytes: req.file.size,
  });
});

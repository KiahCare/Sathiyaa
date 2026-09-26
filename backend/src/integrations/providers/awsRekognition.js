/**
 * Face matching with AWS Rekognition `CompareFaces`.
 *
 * Switched on with `FACE_PROVIDER=rekognition` in the server's .env. Until
 * then the stub is used and this file is never loaded at run time.
 *
 * WHY REKOGNITION RATHER THAN AZURE FACE
 * --------------------------------------
 * Azure's Face API is Limited Access: verification needs an application form
 * and Microsoft's approval, which takes weeks and can be refused. Rekognition
 * `CompareFaces` is generally available -- an IAM user with one permission and
 * it works this afternoon. Sathiyaa is already on AWS, so the bill, the
 * region and the console are ones that already exist.
 *
 * WHY NO AWS SDK
 * --------------
 * `@aws-sdk/client-rekognition` is forty-odd packages for one HTTP call. The
 * server runs on a free-tier t2.micro and `npm ci` runs on every deploy, so
 * the signing is done here instead: about seventy lines of Signature Version
 * 4 against Node's own crypto, with no dependency to install, audit or
 * update. CompareFaces is one POST with a JSON body; there is nothing else in
 * the SDK this needs.
 *
 * WHAT IT COSTS
 * -------------
 * $0.001 per image processed (ap-south-1, first million a month), and the
 * free tier covers 5,000 a month for the first twelve months. One arrival
 * check is one CompareFaces call, so a thousand visits a month is one dollar.
 * See docs/AWS-REKOGNITION.md.
 *
 * WHAT IT IS AND IS NOT
 * ---------------------
 * CompareFaces answers "are these two photographs the same person". It does
 * NOT answer "is there a live human in front of the camera" -- a printed
 * photograph held up to the lens compares as a match. Rekognition Face
 * Liveness is a separate, more expensive service with its own SDK-side flow.
 * Sathiyaa's arrival check pairs this with a real geofence, which is what
 * makes the pair worth something: faking both means standing at the family's
 * address holding a photograph of the carer.
 */
import crypto from 'node:crypto';
import { env } from '../../config/env.js';
import { fetchBinary } from './_shared.js';

const SERVICE = 'rekognition';
const TARGET = 'RekognitionService.CompareFaces';

const sha256 = (data) => crypto.createHash('sha256').update(data).digest('hex');
const hmac = (key, data) => crypto.createHmac('sha256', key).update(data).digest();

/** The date stamps SigV4 wants: 20260925T161420Z and 20260925. */
function stamps(now = new Date()) {
  const amz = now.toISOString().replace(/[:-]|\.\d{3}/g, '');
  return { amz, date: amz.slice(0, 8) };
}

/**
 * Signs and sends one Rekognition request.
 *
 * Signature Version 4, the query-free POST form: canonical request, string to
 * sign, a signing key derived date -> region -> service -> aws4_request, and
 * the result in an Authorization header.
 */
async function callRekognition(body, { timeoutMs }) {
  const { region, accessKeyId, secretAccessKey, sessionToken } = env.aws;
  const host = `${SERVICE}.${region}.amazonaws.com`;
  const payload = JSON.stringify(body);
  const { amz, date } = stamps();

  const headers = {
    'content-type': 'application/x-amz-json-1.1',
    host,
    'x-amz-date': amz,
    'x-amz-target': TARGET,
    ...(sessionToken ? { 'x-amz-security-token': sessionToken } : {}),
  };

  // Canonical headers must be sorted by name, lower-cased, and the signed
  // list must match exactly what is sent.
  const names = Object.keys(headers).sort();
  const canonicalHeaders = names.map((n) => `${n}:${String(headers[n]).trim()}\n`).join('');
  const signedHeaders = names.join(';');

  const canonicalRequest = [
    'POST', '/', '', canonicalHeaders, signedHeaders, sha256(payload),
  ].join('\n');

  const scope = `${date}/${region}/${SERVICE}/aws4_request`;
  const stringToSign = ['AWS4-HMAC-SHA256', amz, scope, sha256(canonicalRequest)].join('\n');

  const kDate = hmac(`AWS4${secretAccessKey}`, date);
  const kRegion = hmac(kDate, region);
  const kService = hmac(kRegion, SERVICE);
  const kSigning = hmac(kService, 'aws4_request');
  const signature = crypto.createHmac('sha256', kSigning).update(stringToSign).digest('hex');

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(`https://${host}/`, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        ...headers,
        Authorization:
          `AWS4-HMAC-SHA256 Credential=${accessKeyId}/${scope}, `
          + `SignedHeaders=${signedHeaders}, Signature=${signature}`,
      },
      body: payload,
    });
    const text = await res.text();
    let json;
    try { json = JSON.parse(text); } catch { json = { __raw: text }; }
    return { status: res.status, json };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Whether the selfie taken on arrival is the carer in their profile photo.
 *
 * Never throws. Every failure -- a missing photo, an unreadable image, a
 * timeout, a misconfigured key -- comes back as `match: false` with a reason,
 * because the caller does the same thing in all of them: refuse the check and
 * say so. A carer standing in somebody's hallway should get a sentence, not a
 * 500.
 */
export async function verifyFace(selfieUrl, referencePhotoUrl) {
  if (!selfieUrl) return { match: false, confidence: 0, reason: 'no_selfie_provided' };
  if (!referencePhotoUrl) return { match: false, confidence: 0, reason: 'no_reference_photo' };
  if (!env.aws.accessKeyId || !env.aws.secretAccessKey) {
    return { match: false, confidence: 0, reason: 'rekognition_not_configured' };
  }

  const timeoutMs = env.faceMatch.timeoutMs ?? 12000;
  // Rekognition's threshold is a percentage; the rest of this codebase keeps
  // face confidence as 0..1, so the two are converted at this boundary rather
  // than leaking a second convention into the caller.
  const threshold = Math.round((env.faceMatch.threshold ?? 0.6) * 100);

  try {
    const [selfie, reference] = await Promise.all([
      fetchBinary('rekognition', selfieUrl, timeoutMs),
      fetchBinary('rekognition', referencePhotoUrl, timeoutMs),
    ]);

    const { status, json } = await callRekognition({
      SourceImage: { Bytes: reference.toString('base64') },
      TargetImage: { Bytes: selfie.toString('base64') },
      SimilarityThreshold: threshold,
      QualityFilter: 'AUTO',
    }, { timeoutMs });

    if (status !== 200) {
      // The AWS error type is the useful half; the message often repeats it.
      const type = String(json?.__type ?? '').split('#').pop() || `http_${status}`;
      // Worth distinguishing: this one is a photograph problem, not a
      // configuration problem, and it is the common one in the field.
      if (type === 'InvalidParameterException') {
        return { match: false, confidence: 0, reason: 'no_face_found_in_one_of_the_photos' };
      }
      return { match: false, confidence: 0, reason: `rekognition_${type}` };
    }

    const best = (json.FaceMatches ?? [])[0];
    if (!best) {
      // Rekognition answered and found nobody similar enough. UnmatchedFaces
      // tells us whether it saw a face at all, which is a different problem
      // for the person standing there: retake the photo, or you are not the
      // carer on this booking.
      const sawAFace = (json.UnmatchedFaces ?? []).length > 0;
      return {
        match: false,
        confidence: 0,
        reason: sawAFace ? 'face_did_not_match' : 'no_face_found_in_selfie',
      };
    }

    return {
      match: true,
      confidence: Number(best.Similarity ?? 0) / 100,
      referencePhotoUrl,
    };
  } catch (err) {
    return { match: false, confidence: 0, reason: `rekognition_error_${err.name || 'unknown'}` };
  }
}

/**
 * Proves the credentials and the signing without needing anybody's
 * photograph.
 *
 * Sends a one-pixel image, which Rekognition correctly refuses as having no
 * face in it. That refusal is the answer we want: a signed request that
 * reached the service and was understood means the key, the secret, the
 * region and the permission are all correct. Anything else comes back as the
 * AWS error type, which is what actually needs fixing.
 *
 * Used by scripts/check-rekognition.mjs.
 */
export async function probeCredentials() {
  if (!env.aws.accessKeyId || !env.aws.secretAccessKey) {
    return { ok: false, reason: 'rekognition_not_configured' };
  }
  // A 1x1 transparent PNG.
  const onePixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    + 'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
  try {
    const { status, json } = await callRekognition({
      SourceImage: { Bytes: onePixel },
      TargetImage: { Bytes: onePixel },
      SimilarityThreshold: 80,
    }, { timeoutMs: env.faceMatch.timeoutMs ?? 12000 });

    const type = String(json?.__type ?? '').split('#').pop() || '';
    // "There is no face in this one pixel" is the service working.
    if (status === 400 && type === 'InvalidParameterException') {
      return { ok: true, reason: 'signed_request_accepted' };
    }
    if (status === 200) return { ok: true, reason: 'signed_request_accepted' };
    return { ok: false, reason: type || `http_${status}` };
  } catch (err) {
    return { ok: false, reason: `rekognition_error_${err.name || 'unknown'}` };
  }
}

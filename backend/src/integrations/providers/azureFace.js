/**
 * Azure AI Face — comparing the selfie a provider takes at the door against
 * the photo on their approved profile.
 *
 * Written and ready, but only used when `FACE_PROVIDER=azure`.
 *
 *   FACE_PROVIDER=azure
 *   AZURE_FACE_ENDPOINT=https://<resource>.cognitiveservices.azure.com
 *   AZURE_FACE_KEY=...
 *   FACE_MATCH_THRESHOLD=0.6        (optional; Azure's own default)
 *
 * **Before this can be switched on:** face verification is a Limited Access
 * feature. Microsoft requires an approved application describing the use case
 * before the Verify operation is enabled on a resource. That is a form and a
 * wait, not a code change — worth starting well before you need it.
 *
 * Azure rather than AWS because its API authenticates with a plain header,
 * so no SDK and no request signing is needed. If you would rather use AWS
 * Rekognition's CompareFaces, that one does need `@aws-sdk/client-rekognition`
 * for SigV4 signing; the shape of this file would be the same.
 */
import { env } from '../../config/env.js';
import { fetchBinary, httpJson, requireConfig } from './_shared.js';

const API = 'face/v1.0';

function config() {
  requireConfig('Azure Face', {
    AZURE_FACE_ENDPOINT: env.azureFace.endpoint,
    AZURE_FACE_KEY: env.azureFace.key,
  });
  return { endpoint: env.azureFace.endpoint.replace(/\/+$/, ''), key: env.azureFace.key };
}

/** Detects exactly one face and returns its id, which lives for 24 hours. */
async function detectFaceId(imageUrl, label) {
  const { endpoint, key } = config();
  const bytes = await fetchBinary('Azure Face', imageUrl);

  const url = `${endpoint}/${API}/detect?returnFaceId=true&detectionModel=detection_03&recognitionModel=recognition_04`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Ocp-Apim-Subscription-Key': key, 'Content-Type': 'application/octet-stream' },
    body: bytes,
  });
  const body = await res.json().catch(() => null);
  if (!res.ok) {
    throw new Error(`[Azure Face] detect on ${label} failed (${res.status}): ${JSON.stringify(body).slice(0, 300)}`);
  }
  if (!Array.isArray(body) || body.length === 0) return { faceId: null, reason: `no_face_in_${label}` };
  if (body.length > 1) return { faceId: null, reason: `multiple_faces_in_${label}` };
  return { faceId: body[0].faceId };
}

export async function verifyFace(selfieUrl, referencePhotoUrl) {
  if (!selfieUrl) return { match: false, confidence: 0, reason: 'no_selfie_provided' };
  if (!referencePhotoUrl) {
    // Nothing to compare against — the provider has no approved photo yet.
    return { match: false, confidence: 0, reason: 'no_reference_photo' };
  }

  const { endpoint, key } = config();
  const [selfie, reference] = await Promise.all([
    detectFaceId(selfieUrl, 'selfie'),
    detectFaceId(referencePhotoUrl, 'profile_photo'),
  ]);
  if (!selfie.faceId) return { match: false, confidence: 0, reason: selfie.reason };
  if (!reference.faceId) return { match: false, confidence: 0, reason: reference.reason };

  const res = await httpJson('Azure Face', `${endpoint}/${API}/verify`, {
    method: 'POST',
    headers: { 'Ocp-Apim-Subscription-Key': key },
    body: { faceId1: selfie.faceId, faceId2: reference.faceId },
  });

  const confidence = res?.confidence ?? 0;
  return {
    match: confidence >= env.azureFace.threshold,
    confidence,
    threshold: env.azureFace.threshold,
    referencePhotoUrl,
  };
}

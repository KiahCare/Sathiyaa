/**
 * Facial recognition for the pre-service check.
 *
 * `FACE_PROVIDER` chooses the implementation; the default stub always matches,
 * so the start-of-service flow is testable without a Face resource. The
 * *geofence* half of that check is real arithmetic either way — a provider
 * standing in the wrong city is refused whichever provider is selected.
 */
import { env } from '../config/env.js';
import * as stub from './providers/faceMatchStub.js';
import * as azure from './providers/azureFace.js';
import * as rekognition from './providers/awsRekognition.js';

// Rekognition is the one to reach for: CompareFaces is generally available,
// where Azure Face verification is Limited Access and needs Microsoft's
// written approval first. Both are here because the choice belongs in the
// .env, not in a rewrite.
const IMPLS = { rekognition, azure, stub };

const chosen = env.integrations.faceMatch;
const impl = IMPLS[chosen] ?? stub;

export const providerName = IMPLS[chosen] ? chosen : 'stub';
export const isLive = providerName !== 'stub';

export const verifyFace = (...args) => impl.verifyFace(...args);

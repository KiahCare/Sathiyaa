/**
 * Facial recognition integration stub.
 * Swap in AWS Rekognition / Azure Face API here.
 * Real impl: download both images, call CompareFaces, threshold on
 * similarity score.
 */
export async function verifyFace(selfieUrl, referencePhotoUrl) {
  await new Promise((r) => setTimeout(r, 100));
  if (!selfieUrl) {
    return { match: false, confidence: 0, reason: 'no_selfie_provided' };
  }
  return { match: true, confidence: 0.99, referencePhotoUrl };
}

/**
 * Is the face check actually configured and working?
 *
 * Run on the server, where the keys are:
 *
 *   cd /opt/sathiyaa/backend
 *   node ../../backend-scripts/check-rekognition.mjs <imageA> <imageB>
 *
 * or from this folder on a laptop with the two variables exported. The two
 * arguments are image URLs or local files; with none it compares one picture
 * with itself, which proves the credentials and the signing without needing
 * anybody's photograph.
 *
 * It prints what happened and nothing else. NO KEY IS EVER PRINTED -- the
 * access key id is shown as its first four characters so you can tell which
 * key is in use, and the secret is never read out at all.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const backend = path.resolve(here, '..');

// Load the server's own .env if it is there, so this can be run without
// exporting anything by hand.
const envFile = path.join(backend, '.env');
if (fs.existsSync(envFile)) {
  for (const line of fs.readFileSync(envFile, 'utf8').split(/\r?\n/)) {
    const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*)$/.exec(line);
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2].trim();
  }
}

const { env } = await import(`file://${path.join(backend, 'src/config/env.js').replace(/\\/g, '/')}`);
const { verifyFace, probeCredentials } = await import(
  `file://${path.join(backend, 'src/integrations/providers/awsRekognition.js').replace(/\\/g, '/')}`
);

const id = env.aws.accessKeyId;
console.log(`provider   : ${env.integrations.faceMatch}`);
console.log(`region     : ${env.aws.region}`);
console.log(`access key : ${id ? `${id.slice(0, 4)}… (${id.length} chars)` : 'NOT SET'}`);
console.log(`secret     : ${env.aws.secretAccessKey ? 'set' : 'NOT SET'}`);
console.log(`threshold  : ${env.faceMatch.threshold}`);
console.log('');

if (!id || !env.aws.secretAccessKey) {
  console.log('Nothing to test: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are not both set.');
  console.log('See docs/AWS-REKOGNITION.md, step 3.');
  process.exit(1);
}

const [a, b] = process.argv.slice(2);

// With no arguments: prove the credentials and the signing, which is what
// somebody following the setup guide actually needs to know. No third-party
// image is fetched and nobody's photograph is required.
if (!a) {
  const started = Date.now();
  const probe = await probeCredentials();
  const ms = Date.now() - started;
  if (probe.ok) {
    console.log(`OK   AWS accepted a signed request   (${ms} ms)`);
    console.log('');
    console.log('The key, the secret, the region and the CompareFaces permission are all correct.');
    console.log('To compare two real photographs, pass two image URLs:');
    console.log('   node check-rekognition.mjs <selfie-url> <profile-photo-url>');
    process.exit(0);
  }
  console.log(`FAILED   ${probe.reason}   (${ms} ms)`);
  console.log('');
  explain(probe.reason);
  process.exit(1);
}

console.log(`comparing  : ${a}`);
console.log(`       and : ${b ?? a}`);
console.log('');

const started = Date.now();
const result = await verifyFace(a, b ?? a);
const ms = Date.now() - started;

if (result.match) {
  console.log(`MATCH   confidence ${(result.confidence * 100).toFixed(1)}%   (${ms} ms)`);
  console.log('Rekognition answered and the credentials work.');
  process.exit(0);
}

console.log(`NO MATCH   reason: ${result.reason}   (${ms} ms)`);
explain(result.reason);
process.exit(1);

function explain(reason) {
  switch (reason) {
    case 'rekognition_not_configured':
    case 'not_configured':
      console.log('The keys are not reaching the adapter. Check the .env is the one the service reads.');
      break;
    case 'rekognition_UnrecognizedClientException':
    case 'UnrecognizedClientException':
    case 'rekognition_InvalidSignatureException':
    case 'InvalidSignatureException':
      console.log('The key or the secret is wrong, or the region does not match. Both are in .env.');
      break;
    case 'rekognition_AccessDeniedException':
    case 'AccessDeniedException':
      console.log('The key works but is not allowed rekognition:CompareFaces. See step 1 of the guide.');
      break;
    case 'no_face_found_in_one_of_the_photos':
    case 'no_face_found_in_selfie':
      console.log('Rekognition answered fine; it could not find a face in one of the images.');
      console.log('That is a picture problem, not a setup problem -- the credentials work.');
      break;
    case 'face_did_not_match':
      console.log('Two different people. The setup works.');
      break;
    default:
      console.log('Unexpected. The reason above is the AWS error type.');
  }
}

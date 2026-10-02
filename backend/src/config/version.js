/**
 * What version of the API this is, read from the one place that defines it.
 *
 * `package.json` is the single source of truth for the backend's version —
 * `npm version minor` bumps it, and nothing else has to be kept in step. This
 * module reads it at start-up rather than hardcoding a copy, because a copy is
 * a thing that goes stale silently: a build labelled 1.1.0 that is actually
 * 1.3.0 is worse than no label at all, since it makes a bug report point at the
 * wrong fortnight of work.
 *
 * `buildSha` and `builtAt` are filled in by the deployment, not by the
 * repository. A version number says what was meant to ship; the commit says
 * what actually did. They come from the environment because the running process
 * has no git to ask — `package-for-ec2.ps1` sets them when it makes the tarball.
 * Both are null on a laptop, which is the honest answer there.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const packageJsonPath = path.join(
  path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'package.json'
);

function readVersion() {
  try {
    return JSON.parse(fs.readFileSync(packageJsonPath, 'utf8')).version ?? '0.0.0';
  } catch {
    // A missing or unreadable package.json must not stop the API from starting:
    // not knowing the version is a cosmetic problem, and refusing to serve
    // bookings over it would not be.
    return '0.0.0';
  }
}

export const version = readVersion();
export const buildSha = process.env.BUILD_SHA || null;
export const builtAt = process.env.BUILT_AT || null;

/** The shape `/health` answers with, so one object describes the build. */
export const buildInfo = { version, buildSha, builtAt };

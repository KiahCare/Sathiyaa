// Proves the free maps provider really reaches OpenStreetMap.
// Imported by a path relative to this file, so moving the folder does not
// break the check.
import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const mapsModule = path.resolve(
  HERE, '..', 'sathiyaa-full-project - Flutter Web version', 'backend', 'src', 'integrations', 'maps.js'
);
const { geocode, getDirections, providerName, isLive } = await import(pathToFileURL(mapsModule).href);

console.log(`provider: ${providerName} (live: ${isLive})`);

const g = await geocode('Navrangpura, Ahmedabad');
console.log('\ngeocode "Navrangpura, Ahmedabad":');
console.log(`  ${g.formattedAddress}`);
console.log(`  ${g.latitude}, ${g.longitude}`);

const d = await getDirections({ fromLat: 22.9861, fromLng: 72.6013, toLat: 23.0225, toLng: 72.5714 });
console.log('\ndirections Navrangpura -> Ashram Road:');
console.log(`  ${d.distanceKm} km, about ${d.etaMinutes} min`);
console.log(`  polyline: ${d.polyline ? d.polyline.slice(0, 40) + '…' : 'none'}`);
console.log(`  ${d.note ?? d.status ?? ''}`);

const straight = Math.round(Math.hypot((23.0225 - 22.9861) * 111, (72.5714 - 72.6013) * 108) * 10) / 10;
console.log(`\n  (straight line would be ~${straight} km — a real road route should be longer)`);

// Without this the script prints "undefined" twice and exits zero, which is
// how a machine with no internet reports that OpenStreetMap is working fine.
const problems = [];
if (!Number.isFinite(g?.latitude) || !Number.isFinite(g?.longitude)) {
  problems.push('geocode returned no coordinates');
}
if (!Number.isFinite(d?.distanceKm) || d.distanceKm <= 0) {
  problems.push('directions returned no distance');
} else if (isLive && d.distanceKm < straight) {
  problems.push(`road route ${d.distanceKm} km is shorter than the straight line ${straight} km, so it is not a road route`);
}
console.log(problems.length ? '\nFAIL' : '\nOK  the maps provider answered');
for (const p of problems) console.log('  - ' + p);
if (problems.length) process.exitCode = 1;

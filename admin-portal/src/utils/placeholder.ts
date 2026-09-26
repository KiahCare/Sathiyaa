// Locally-generated SVG data-URI placeholders so the app never depends on an
// external image host (avatars, document scans, broadcast images) — keeps
// every screen fully populated and console-error-free even with no network.

const PALETTE = ['#0e6e5f', '#2563eb', '#7c3aed', '#d97706', '#dc2626', '#0891b2', '#be185d', '#4338ca'];

function hashString(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return h;
}

function initials(name: string): string {
  const parts = name.trim().split(/\s+/);
  const first = parts[0]?.[0] ?? '';
  const last = parts.length > 1 ? parts[parts.length - 1][0] : '';
  return (first + last).toUpperCase();
}

export function avatarDataUri(name: string, seed: number | string): string {
  const color = PALETTE[hashString(String(seed)) % PALETTE.length];
  const label = initials(name) || '?';
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120">` +
    `<rect width="120" height="120" rx="60" fill="${color}"/>` +
    `<text x="60" y="60" font-family="Arial, sans-serif" font-size="46" font-weight="700" fill="#ffffff" text-anchor="middle" dominant-baseline="central">${label}</text>` +
    `</svg>`;
  return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;
}

export function documentDataUri(label: string, seed: number | string): string {
  const color = PALETTE[hashString(String(seed) + label) % PALETTE.length];
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="420">` +
    `<rect width="640" height="420" fill="#f4f6f9"/>` +
    `<rect x="16" y="16" width="608" height="388" rx="10" fill="#ffffff" stroke="${color}" stroke-width="3" stroke-dasharray="10 8"/>` +
    `<circle cx="320" cy="170" r="46" fill="${color}" opacity="0.15"/>` +
    `<text x="320" y="178" font-family="Arial, sans-serif" font-size="30" fill="${color}" text-anchor="middle">📄</text>` +
    `<text x="320" y="250" font-family="Arial, sans-serif" font-size="20" font-weight="700" fill="#1a2233" text-anchor="middle">${label}</text>` +
    `<text x="320" y="278" font-family="Arial, sans-serif" font-size="13" fill="#667085" text-anchor="middle">Sample uploaded document (demo data)</text>` +
    `</svg>`;
  return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;
}

export function bannerDataUri(title: string, seed: number | string): string {
  const color = PALETTE[hashString(String(seed) + title) % PALETTE.length];
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="500" height="260">` +
    `<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">` +
    `<stop offset="0" stop-color="${color}"/><stop offset="1" stop-color="#0f2b26"/>` +
    `</linearGradient></defs>` +
    `<rect width="500" height="260" fill="url(#g)"/>` +
    `<text x="250" y="140" font-family="Arial, sans-serif" font-size="22" font-weight="700" fill="#ffffff" text-anchor="middle">${title}</text>` +
    `</svg>`;
  return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;
}

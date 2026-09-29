// Builds the "Family" app icon: a cream plate with a saffron heart, flanked by
// a fork and a spoon, on a warm peach → saffron background. Third member of
// the family (owner = espresso + saffron pot, maid = saffron + cook medallion).
// The mark stays inside a 290 px radius of the 1024 canvas (Android adaptive
// icon safe zone).
//
// Writes branding/family.svg, family-foreground.svg, family-monochrome.svg and
// renders the PNGs into family_app/assets/icon/.
// Run: NODE_PATH=<dir with sharp in node_modules> node branding/family-build.js
const fs = require("fs");
const path = require("path");

const BRANDING = __dirname;
const OUT = path.join(__dirname, "..", "family_app", "assets", "icon");

const BG_DEFS = `
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFBE94"/><stop offset="0.5" stop-color="#F7935A"/><stop offset="1" stop-color="#E2672A"/></linearGradient>
  <radialGradient id="glow" cx="0.5" cy="0.55" r="0.5"><stop offset="0" stop-color="#FFF0DE" stop-opacity="0.45"/><stop offset="1" stop-color="#FFF0DE" stop-opacity="0"/></radialGradient>
  <radialGradient id="sheen" cx="0.18" cy="0.08" r="0.85"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.42"/><stop offset="0.55" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>`;
const BG_RECTS = `<rect width="1024" height="1024" fill="url(#bg)"/><rect width="1024" height="1024" fill="url(#glow)"/><rect width="1024" height="1024" fill="url(#sheen)"/>`;

// ---------- geometry ----------
const C = { x: 512, y: 512 };
const PLATE_R = 200; // outer rim
const WELL_R = 142; // inner well
const FORK_X = 284;
const SPOON_X = 740;
const TOP = 338; // top of fork tines / spoon bowl
const BOTTOM = 688; // end of both handles

// Heart centred in the well (classic two-lobe heart).
const heart = (cx, cy, w) => {
  const s = w / 200; // designed 200 wide, ~180 tall, origin at centre
  const p = (x, y) => `${(cx + x * s).toFixed(1)} ${(cy + y * s).toFixed(1)}`;
  return `M${p(0, 88)} C${p(-20, 72)} ${p(-100, 18)} ${p(-100, -34)} C${p(-100, -72)} ${p(-72, -96)} ${p(-44, -96)} C${p(-20, -96)} ${p(-6, -82)} ${p(0, -66)} C${p(6, -82)} ${p(20, -96)} ${p(44, -96)} C${p(72, -96)} ${p(100, -72)} ${p(100, -34)} C${p(100, 18)} ${p(20, 72)} ${p(0, 88)} Z`;
};
const HEART = heart(C.x, C.y + 8, 174);

// Fork: three tines joined by a rounded base, then a long handle.
const TINE_W = 18, TINE_GAP = 9, TINE_H = 96;
const forkW = TINE_W * 3 + TINE_GAP * 2; // 82
const fx0 = FORK_X - forkW / 2;
const tines = [0, 1, 2].map((i) => {
  const x = fx0 + i * (TINE_W + TINE_GAP);
  return `M${x} ${TOP + TINE_W / 2} A${TINE_W / 2} ${TINE_W / 2} 0 0 1 ${x + TINE_W} ${TOP + TINE_W / 2} L${x + TINE_W} ${TOP + TINE_H} L${x} ${TOP + TINE_H} Z`;
}).join(" ");
const HW = 27; // handle width
const forkBase = `M${fx0} ${TOP + TINE_H - 8} L${fx0 + forkW} ${TOP + TINE_H - 8} L${fx0 + forkW} ${TOP + TINE_H + 8} C${fx0 + forkW} ${TOP + TINE_H + 44} ${FORK_X + HW / 2 + 4} ${TOP + TINE_H + 58} ${FORK_X + HW / 2} ${TOP + TINE_H + 80} L${FORK_X - HW / 2} ${TOP + TINE_H + 80} C${FORK_X - HW / 2 - 4} ${TOP + TINE_H + 58} ${fx0} ${TOP + TINE_H + 44} ${fx0} ${TOP + TINE_H + 8} Z`;
const handle = (x, y0) => `M${x - HW / 2} ${y0} L${x + HW / 2} ${y0} L${x + HW / 2 + 3} ${BOTTOM - HW / 2} A${HW / 2 + 3} ${HW / 2 + 3} 0 0 1 ${x - HW / 2 - 3} ${BOTTOM - HW / 2} Z`;
const FORK = `${tines} ${forkBase} ${handle(FORK_X, TOP + TINE_H + 70)}`;

// Spoon: oval bowl, slim neck, same handle.
const BOWL = { rx: 40, ry: 60 };
const bowlCy = TOP + BOWL.ry;
const SPOON_BOWL = `M${SPOON_X} ${TOP} C${SPOON_X + BOWL.rx * 1.35} ${TOP} ${SPOON_X + BOWL.rx * 1.2} ${bowlCy + BOWL.ry} ${SPOON_X} ${bowlCy + BOWL.ry} C${SPOON_X - BOWL.rx * 1.2} ${bowlCy + BOWL.ry} ${SPOON_X - BOWL.rx * 1.35} ${TOP} ${SPOON_X} ${TOP} Z`;
const SPOON_NECK = `M${SPOON_X - 12} ${bowlCy + BOWL.ry - 10} L${SPOON_X + 12} ${bowlCy + BOWL.ry - 10} L${SPOON_X + HW / 2} ${bowlCy + BOWL.ry + 60} L${SPOON_X - HW / 2} ${bowlCy + BOWL.ry + 60} Z`;
const SPOON = `${SPOON_BOWL} ${SPOON_NECK} ${handle(SPOON_X, bowlCy + BOWL.ry + 50)}`;

// The layout above is drawn large; the whole mark is scaled about the centre
// so its farthest point (corners of the fork tines, spoon bowl, handle ends)
// lands inside the 290 px safe radius, with a little room to spare.
const pts = [
  [fx0, TOP], [fx0 + forkW, TOP], [FORK_X - HW / 2 - 3, BOTTOM], [FORK_X + HW / 2 + 3, BOTTOM],
  [SPOON_X + BOWL.rx, bowlCy], [SPOON_X + BOWL.rx * 0.8, TOP + 12], [SPOON_X + HW / 2 + 3, BOTTOM],
];
const S = Math.min(1, 284 / Math.max(...pts.map(([x, y]) => Math.hypot(x - C.x, y - C.y))));
const T = `translate(${C.x} ${C.y}) scale(${S.toFixed(4)}) translate(${-C.x} ${-C.y})`;
const far = S * Math.max(...pts.map(([x, y]) => Math.hypot(x - C.x, y - C.y)));

const markDefs = `
  <linearGradient id="plate" x1="0.2" y1="0" x2="0.8" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#FFE9D4"/></linearGradient>
  <linearGradient id="well" x1="0.8" y1="1" x2="0.2" y2="0"><stop offset="0" stop-color="#FFFDFB"/><stop offset="1" stop-color="#FBE3CC"/></linearGradient>
  <linearGradient id="cutlery" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#FFE7D1"/></linearGradient>
  <linearGradient id="heart" x1="0.2" y1="0" x2="0.8" y2="1"><stop offset="0" stop-color="#FBB56F"/><stop offset="1" stop-color="#DE6216"/></linearGradient>
  <filter id="drop" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="16" stdDeviation="18" flood-color="#7A2A06" flood-opacity="0.40"/></filter>
  <filter id="soft" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="6" stdDeviation="6" flood-color="#8A3A0A" flood-opacity="0.30"/></filter>`;

const mark = `<g transform="${T}">
<g filter="url(#drop)">
  <path d="${FORK}" fill="url(#cutlery)"/>
  <path d="${SPOON}" fill="url(#cutlery)"/>
  <circle cx="${C.x}" cy="${C.y}" r="${PLATE_R}" fill="url(#plate)"/>
</g>
<!-- glassy rim + well -->
<circle cx="${C.x}" cy="${C.y}" r="${PLATE_R - 2}" fill="none" stroke="#FFFFFF" stroke-opacity="0.9" stroke-width="4"/>
<circle cx="${C.x}" cy="${C.y}" r="${WELL_R}" fill="url(#well)"/>
<circle cx="${C.x}" cy="${C.y}" r="${WELL_R}" fill="none" stroke="#EBBE97" stroke-width="7"/>
<path d="M${C.x - 150} ${C.y - 70} A${PLATE_R - 24} ${PLATE_R - 24} 0 0 1 ${C.x - 40} ${C.y - 158}" fill="none" stroke="#FFFFFF" stroke-opacity="0.95" stroke-width="12" stroke-linecap="round"/>
<!-- heart -->
<g filter="url(#soft)"><path d="${HEART}" fill="url(#heart)"/></g>
<path d="M${C.x - 58} ${C.y - 40} C${C.x - 60} ${C.y - 58} ${C.x - 46} ${C.y - 70} ${C.x - 30} ${C.y - 68}" fill="none" stroke="#FFFFFF" stroke-opacity="0.55" stroke-width="10" stroke-linecap="round"/>
<!-- cutlery sheen -->
<path d="M${FORK_X - 6} ${TOP + TINE_H + 96} L${FORK_X - 6} ${BOTTOM - 40}" stroke="#FFFFFF" stroke-opacity="0.8" stroke-width="6" stroke-linecap="round"/>
<path d="M${SPOON_X - 22} ${TOP + 34} C${SPOON_X - 30} ${TOP + 56} ${SPOON_X - 30} ${TOP + 80} ${SPOON_X - 22} ${TOP + 100}" fill="none" stroke="#FFFFFF" stroke-opacity="0.8" stroke-width="8" stroke-linecap="round"/>
<path d="M${SPOON_X - 6} ${bowlCy + BOWL.ry + 90} L${SPOON_X - 6} ${BOTTOM - 40}" stroke="#FFFFFF" stroke-opacity="0.8" stroke-width="6" stroke-linecap="round"/>
</g>`;

const svg = (defs, body, size = 1024) => `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 1024 1024">
<defs>${defs}
</defs>
${body}
</svg>
`;

const full = svg(BG_DEFS + markDefs, BG_RECTS + mark);
const fg = svg(markDefs, mark);
const bgOnly = svg(BG_DEFS, BG_RECTS);

// Mono (Android 13 themed icon): one white silhouette, details cut out.
const monoDefs = `
  <mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
    <g transform="${T}">
      <g fill="#FFF">
        <path d="${FORK}"/>
        <path d="${SPOON}"/>
        <circle cx="${C.x}" cy="${C.y}" r="${PLATE_R}"/>
      </g>
      <circle cx="${C.x}" cy="${C.y}" r="${WELL_R}" fill="none" stroke="#000" stroke-width="16"/>
      <path d="${HEART}" fill="#000"/>
    </g>
  </mask>`;
const mono = svg(monoDefs, `<rect width="1024" height="1024" fill="#FFFFFF" mask="url(#m)"/>`);

// Rounded app-icon look for the in-app logo and the splash image.
const R = 1024 * 0.2237;
const rounded = svg(
  BG_DEFS + markDefs + `<clipPath id="corner"><rect width="1024" height="1024" rx="${R.toFixed(1)}"/></clipPath>`,
  `<g clip-path="url(#corner)">${BG_RECTS}${mark}</g>`,
);

fs.writeFileSync(path.join(BRANDING, "family.svg"), full);
fs.writeFileSync(path.join(BRANDING, "family-foreground.svg"), fg);
fs.writeFileSync(path.join(BRANDING, "family-monochrome.svg"), mono);

console.log("scale", S.toFixed(3), "· farthest mark point from centre:", far.toFixed(1));

if (process.argv.includes("--svg-only")) process.exit(0);

const sharp = require("sharp");
async function png(svgText, out, size = 1024, flatten = null) {
  let img = sharp(Buffer.from(svgText), { density: 72 * (size / 1024) * 2 }).resize(size, size);
  if (flatten) img = img.flatten({ background: flatten });
  await img.png().toFile(path.join(OUT, out));
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  // iOS / legacy Android icon: full bleed, no transparency.
  await png(full, "icon.png", 1024, "#F7A25B");
  // Android adaptive icon layers + Android 13 themed (monochrome) icon.
  await png(bgOnly, "icon_bg.png");
  await png(fg, "icon_fg.png");
  await png(mono, "icon_mono.png");
  // In-app logo and splash image (rounded icon, transparent corners).
  await png(rounded, "logo.png", 512);
  await png(rounded, "splash.png", 600);
  // Android 12+ splash: the mark alone, placed on a coloured circle by the OS.
  await png(fg, "splash_android12.png", 960);
  console.log("family_app/assets/icon →", fs.readdirSync(OUT).join(", "));
})();

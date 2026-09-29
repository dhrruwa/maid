// Builds full.svg, fg.svg, mono.svg for the "Friendly portrait" Maid icon.
const fs = require("fs");
const path = require("path");
const out = __dirname;

const BG_DEFS = `
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FAB36A"/><stop offset="0.5" stop-color="#EC8331"/><stop offset="1" stop-color="#CF5D18"/></linearGradient>
  <radialGradient id="glow" cx="0.5" cy="0.6" r="0.5"><stop offset="0" stop-color="#FFE3C4" stop-opacity="0.35"/><stop offset="1" stop-color="#FFE3C4" stop-opacity="0"/></radialGradient>
  <radialGradient id="sheen" cx="0.18" cy="0.08" r="0.85"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.5"/><stop offset="0.55" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>`;
const BG_RECTS = `<rect width="1024" height="1024" fill="url(#bg)"/><rect width="1024" height="1024" fill="url(#glow)"/><rect width="1024" height="1024" fill="url(#sheen)"/>`;

// ---------- geometry ----------
const DISC_R = 282;
const H = { cx: 512, cy: 410, rx: 128, ry: 126 };           // hair dome
const ePt = (deg, k = 1) => [H.cx + H.rx * k * Math.cos(deg * Math.PI / 180), H.cy + H.ry * k * Math.sin(deg * Math.PI / 180)];
const HAIRBACK = `M432 490 C404 472 384 446 384 410 A${H.rx} ${H.ry} 0 0 1 640 410 C640 446 620 472 592 490 Z`;
const BUN = { cx: 606, cy: 334, r: 54 };
const S = 1.06, PY = 560;   // figure scale about (512, PY)
const T = `translate(512 ${PY}) scale(${S}) translate(-512 -${PY})`;
const SPOON = "M540 766 L562 690";
const FACE = "M512 318 C574 318 610 362 610 426 C610 496 566 550 512 550 C458 550 414 496 414 426 C414 362 450 318 512 318 Z";
const HAIRLINE = "M412 480 C412 404 446 360 512 346 C578 360 612 404 612 480";
const FRINGE = `M370 480 L412 480 C412 404 446 360 512 346 C578 360 612 404 612 480 L654 480 L654 270 L370 270 Z`;
const EARS = [[409, 452], [615, 452]];
const NECK = "M480 506 L544 506 L550 600 Q512 652 474 600 Z";
const TORSO = "M282 880 C282 708 350 632 446 612 Q468 606 480 600 Q512 642 544 600 Q556 606 578 612 C674 632 742 708 742 880 Z";
const NECKLINE = "M480 600 Q512 642 544 600";
const BIB = "M446 664 Q446 650 460 650 L564 650 Q578 650 578 664 L608 880 L416 880 Z";
const STRAPS = "M460 656 L484 606 M564 656 L540 606";
const POCKET = "M474 756 L550 756";
const EYES = [[475, 446], [549, 446]];
const BROWS = "M455 414 Q475 402 495 411 M529 411 Q549 402 569 414";
const SMILE = "M482 494 Q512 522 542 494";
const BINDI = { cx: 512, cy: 412, r: 6.5 };
const JUNCTION = (() => { const a = ePt(-66), b = ePt(-12); return `M${a[0].toFixed(1)} ${a[1].toFixed(1)} A${H.rx} ${H.ry} 0 0 1 ${b[0].toFixed(1)} ${b[1].toFixed(1)}`; })();

// gajra: jasmine buds strung along the hair / bun junction
const buds = [];
for (let i = 0; i < 8; i++) {
  const d = -63 + i * 6.5;
  const [x, y] = ePt(d, 1.0);
  buds.push([x, y, d + 90]);
}

const clipDisc = `<clipPath id="disc"><circle cx="512" cy="${(PY - (PY - 512) / S).toFixed(2)}" r="${(DISC_R / S).toFixed(2)}"/></clipPath>`;
const clipHair = `<clipPath id="hairclip"><path d="${HAIRBACK}"/></clipPath>`;

const markDefs = `
  ${clipDisc}${clipHair}
  <linearGradient id="glass" x1="0.25" y1="0" x2="0.75" y2="1"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.55"/><stop offset="1" stop-color="#FFF4E8" stop-opacity="0.22"/></linearGradient>
  <linearGradient id="rim" x1="0.2" y1="0" x2="0.8" y2="1"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.9"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0.25"/></linearGradient>
  <linearGradient id="hair" x1="0.2" y1="0" x2="0.8" y2="1"><stop offset="0" stop-color="#4A3226"/><stop offset="1" stop-color="#1F140D"/></linearGradient>
  <linearGradient id="skin" x1="0.2" y1="0" x2="0.8" y2="1"><stop offset="0" stop-color="#B8794A"/><stop offset="1" stop-color="#955831"/></linearGradient>
  <linearGradient id="neck" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7A4324"/><stop offset="0.5" stop-color="#93572F"/></linearGradient>
  <linearGradient id="blouse" x1="0.2" y1="0" x2="0.8" y2="1"><stop offset="0" stop-color="#E06A22"/><stop offset="1" stop-color="#A9390C"/></linearGradient>
  <linearGradient id="apron" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#F3E1CB"/></linearGradient>
  <filter id="drop" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#6B2A06" flood-opacity="0.32"/></filter>
  <filter id="discshadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="14" stdDeviation="16" flood-color="#7A3108" flood-opacity="0.28"/></filter>
  <filter id="soft" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="6" stdDeviation="6" flood-color="#5A2205" flood-opacity="0.28"/></filter>`;

const BUD = "M0 -16 C9 -10 10 3 0 10 C-10 3 -9 -10 0 -16 Z";
const bud = ([x, y, a], i) => `<g transform="translate(${x.toFixed(1)} ${y.toFixed(1)}) rotate(${a.toFixed(1)}) translate(0 ${i % 2 ? 3 : 0}) scale(${i % 2 ? 0.88 : 1})"><path d="${BUD}" fill="#FFFFFF" stroke="#E6D8C6" stroke-width="2"/></g>`;

const mark = `
<!-- frosted glass medallion -->
<circle cx="512" cy="512" r="${DISC_R}" fill="url(#glass)" filter="url(#discshadow)"/>
<circle cx="512" cy="512" r="${DISC_R - 1.5}" fill="none" stroke="url(#rim)" stroke-width="3"/>
<g filter="url(#drop)"><g transform="${T}">
  <!-- bun -->
  <circle cx="${BUN.cx}" cy="${BUN.cy}" r="${BUN.r}" fill="url(#hair)"/>
  <path d="M571 314 A40 40 0 0 1 632 303" fill="none" stroke="#FFFFFF" stroke-opacity="0.22" stroke-width="8" stroke-linecap="round"/>
  <!-- body, clipped to the medallion -->
  <g clip-path="url(#disc)">
    <path d="${NECK}" fill="url(#neck)"/>
    <path d="${TORSO}" fill="url(#blouse)"/>
    <path d="M334 712 C356 656 398 630 446 620" fill="none" stroke="#FFFFFF" stroke-opacity="0.25" stroke-width="12" stroke-linecap="round"/>
    <g filter="url(#soft)">
      <path d="${STRAPS}" fill="none" stroke="#FBF3E9" stroke-width="16" stroke-linecap="round"/>
      <path d="${BIB}" fill="url(#apron)"/>
    </g>
    <path d="M466 756 L558 756 L560 880 L464 880 Z" fill="#F6E8D6"/>
    <path d="${POCKET}" stroke="#E4CDB0" stroke-width="6" stroke-linecap="round"/>
  </g>
  <!-- head -->
  <path d="${HAIRBACK}" fill="url(#hair)"/>
  ${EARS.map(([x, y]) => `<ellipse cx="${x}" cy="${y}" rx="12" ry="19" fill="#A1623A"/><circle cx="${x}" cy="${y + 22}" r="7.5" fill="#F4B942" stroke="#C98A1C" stroke-width="2"/>`).join("")}
  <path d="${FACE}" fill="url(#skin)"/>
  <path d="${FRINGE}" fill="url(#hair)" clip-path="url(#hairclip)"/>
  <path d="M512 346 L512 298" stroke="#5B4133" stroke-width="4" stroke-linecap="round"/>
  <path d="M420 362 C440 322 474 298 512 294" fill="none" stroke="#FFFFFF" stroke-opacity="0.22" stroke-width="10" stroke-linecap="round"/>
  ${buds.map(bud).join("\n  ")}
  <!-- face -->
  <ellipse cx="453" cy="484" rx="19" ry="11" fill="#E06B4E" fill-opacity="0.26"/>
  <ellipse cx="571" cy="484" rx="19" ry="11" fill="#E06B4E" fill-opacity="0.26"/>
  <path d="${BROWS}" fill="none" stroke="#2A1B12" stroke-width="7" stroke-linecap="round"/>
  ${EYES.map(([x, y]) => `<ellipse cx="${x}" cy="${y}" rx="11" ry="14" fill="#2A1B12"/><circle cx="${x + 4}" cy="${y - 5}" r="3.5" fill="#FFFFFF"/>`).join("")}
  <path d="M506 470 Q512 476 518 470" fill="none" stroke="#6E3A1D" stroke-width="5" stroke-linecap="round"/>
  <path d="${SMILE}" fill="none" stroke="#2A1B12" stroke-width="8" stroke-linecap="round"/>
  <circle cx="${BINDI.cx}" cy="${BINDI.cy}" r="${BINDI.r}" fill="#8E1B2C"/>
</g></g>`;

const svg = (defs, body) => `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>${defs}
</defs>
${body}
</svg>
`;

fs.writeFileSync(path.join(out, "full.svg"), svg(BG_DEFS + markDefs, BG_RECTS + mark));
fs.writeFileSync(path.join(out, "fg.svg"), svg(markDefs, mark));

// ---------- mono: one white silhouette, details cut with a mask ----------
const cut = `stroke="#000" fill="none" stroke-linecap="round" stroke-linejoin="round"`;
const monoDefs = `
  ${clipDisc}
  <mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
    <g transform="${T}">
    <g fill="#FFF">
      <circle cx="${BUN.cx}" cy="${BUN.cy}" r="${BUN.r}"/>
      <path d="${HAIRBACK}"/>
      ${EARS.map(([x, y]) => `<ellipse cx="${x}" cy="${y}" rx="12" ry="19"/><circle cx="${x}" cy="${y + 22}" r="7.5"/>`).join("")}
      <path d="${FACE}"/>
      <g clip-path="url(#disc)"><path d="${NECK}"/><path d="${TORSO}"/></g>
    </g>
    <path d="${JUNCTION}" ${cut} stroke-width="11"/>
    ${buds.map(([x, y, a]) => `<g transform="translate(${x.toFixed(1)} ${y.toFixed(1)}) rotate(${a.toFixed(1)})"><path d="${BUD}" fill="#FFF" stroke="#000" stroke-width="5"/></g>`).join("")}
    <path d="${HAIRLINE}" ${cut} stroke-width="12"/>
    <path d="M428 500 C450 536 480 554 512 554 C544 554 574 536 596 500" ${cut} stroke-width="12"/>
    <g clip-path="url(#disc)">
      <path d="${NECKLINE}" ${cut} stroke-width="12"/>
      <path d="${BIB}" ${cut} stroke-width="12"/>
      <path d="${STRAPS}" ${cut} stroke-width="30"/>
      <path d="${STRAPS}" stroke="#FFF" stroke-width="12" stroke-linecap="round"/>
      <path d="M458 756 L566 756" stroke="#FFF" stroke-width="8"/>
      <path d="${POCKET}" ${cut} stroke-width="7"/>
    </g>
    <path d="${BROWS}" ${cut} stroke-width="7"/>
    ${EYES.map(([x, y]) => `<ellipse cx="${x}" cy="${y}" rx="11" ry="14" fill="#000"/>`).join("")}
    <path d="${SMILE}" ${cut} stroke-width="9"/>
    <circle cx="${BINDI.cx}" cy="${BINDI.cy}" r="${BINDI.r}" fill="#000"/>
    </g>
  </mask>`;
const monoBody = `<rect width="1024" height="1024" fill="#FFFFFF" mask="url(#m)"/>`;
fs.writeFileSync(path.join(out, "mono.svg"), svg(monoDefs, monoBody));
console.log("built");

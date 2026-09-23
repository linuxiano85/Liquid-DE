#!/usr/bin/env python3
"""Genera le tre pagine «Minerva liquida»: stesso motore, tre modi di stare
sulla scrivania (Isola, Goccia, Bordi vivi)."""
from pathlib import Path

QUI = Path(__file__).parent

CSS = r"""
:root {
  color-scheme: dark;
  --base: #070a12; --carta: #0c111c; --bordo: rgba(238,244,255,.10);
  --testo: #eef4ff; --tenue: #8a93a8; --accento: #22d3ee; --alt: #8b5cf6;
  --display: "Inter", "Adwaita Sans", system-ui, sans-serif;
  --mono: "Noto Sans Mono", ui-monospace, monospace;
}
body { background: var(--base); color: var(--testo); font-family: var(--display);
  padding-inline: 16px; padding-block: 26px 40px; }
.guscio { max-width: 1240px; margin: 0 auto; display: grid; gap: 16px; }
header { display: grid; gap: 6px; }
.sopra { font: 500 11px/1 var(--mono); letter-spacing: .14em; text-transform: uppercase; color: var(--accento); }
h1 { margin: 0; font-weight: 300; font-size: clamp(28px, 4.2vw, 44px); letter-spacing: -.02em; text-wrap: balance; }
h1 b { font-weight: 600; }
.sotto { margin: 0; color: var(--tenue); max-width: 70ch; line-height: 1.55; font-size: 15px; }
.cornice { position: relative; width: 100%; aspect-ratio: 16/9; border-radius: 14px; overflow: hidden;
  border: 1px solid var(--bordo); background: var(--carta); touch-action: none; user-select: none; }
.scrivania { position: absolute; left: 0; top: 0; width: 1280px; height: 720px; transform-origin: 0 0; }
canvas.acqua, canvas.colli { position: absolute; left: 0; top: 0; width: 1280px; height: 720px; }
canvas.colli { pointer-events: none; }
.ogg { position: absolute; left: 0; top: 0; will-change: transform; overflow: hidden; }
.ogg > canvas.fondo { position: absolute; inset: 0; width: 100%; height: 100%; }
.ogg > .dentro { position: absolute; inset: 0; }
.fin { border-radius: 16px; overflow: hidden; box-shadow: 0 22px 50px rgba(0,0,0,.40), inset 0 1px 0 rgba(255,255,255,.08); }
.fin .titolo { position: absolute; left: 0; right: 0; top: 0; height: 34px; display: flex; align-items: center; gap: 9px;
  padding: 0 13px; font-size: 12.5px; font-weight: 500; cursor: grab; }
.fin .titolo i { width: 10px; height: 10px; border-radius: 50%; }
.fin .contenuto { position: absolute; left: 0; right: 0; top: 34px; bottom: 0; }
.editor { padding: 10px 16px; font: 12px/1.75 var(--mono); color: #c3cde0; }
.editor .k { color: #c084fc; } .editor .f { color: var(--accento); } .editor .c { color: #7a849c; } .editor .s { color: #34d399; }
.note { padding: 12px 16px; font-size: 13.5px; line-height: 1.6; color: #dbe3f3; }
.note h3 { margin: 0 0 6px; font-size: 15px; font-weight: 600; }
canvas.film { position: absolute; inset: 0; width: 100%; height: 100%; }
.pannello { display: grid; grid-template-columns: 1.3fr 1fr; gap: 18px; align-items: start; }
@media (max-width: 760px) { .pannello { grid-template-columns: 1fr; } }
.pannello h2 { margin: 0 0 8px; font-size: 18px; font-weight: 600; }
.pannello p { margin: 0 0 10px; color: var(--tenue); line-height: 1.6; font-size: 14.5px; max-width: 64ch; }
.pannello ul { margin: 0; padding-left: 18px; line-height: 1.8; font-size: 14px; }
.scatola { border: 1px solid var(--bordo); border-radius: 12px; padding: 16px; background: var(--carta); display: grid; gap: 10px; }
.scatola .riga { display: flex; flex-wrap: wrap; gap: 8px; }
.scatola button { font: 500 13px var(--display); color: var(--testo); background: rgba(238,244,255,.06);
  border: 1px solid var(--bordo); border-radius: 8px; padding: 8px 12px; cursor: pointer; }
.scatola button:hover { border-color: rgba(34,211,238,.45); }
.scatola button:focus-visible { outline: 2px solid var(--accento); outline-offset: 2px; }
.scatola label { display: flex; align-items: center; gap: 8px; font-size: 13.5px; color: var(--tenue); }
.altre { color: var(--tenue); font-size: 13.5px; }
.altre a { color: var(--accento); }
.icona { width: 44px; height: 44px; border-radius: 13px; display: grid; place-items: center;
  font: 600 16px var(--display); color: #061018; transform-origin: 50% 100%; }
"""

MOTORE = r"""
(() => {
const riduci = matchMedia('(prefers-reduced-motion: reduce)').matches;
const W = 1280, H = 720;
const cornice = document.getElementById('cornice'), scriv = document.getElementById('scrivania');
let scala = 1;
function adatta() { scala = cornice.clientWidth / W; scriv.style.transform = `scale(${scala})`; }
new ResizeObserver(adatta).observe(cornice); adatta();
function inScrivania(e) { const r = cornice.getBoundingClientRect(); return { x: (e.clientX - r.left) / scala, y: (e.clientY - r.top) / scala }; }
window.MINERVA = { W, H, inScrivania, riduci, oggetti: [], materiale: { acquerello: true, mercurio: true, acqua: true } };
const M = window.MINERVA;

// ── Lo sfondo, e l'acqua sopra ─────────────────────────────────────
const QW = 320, QH = 180;
const sfondo = document.createElement('canvas'); sfondo.width = QW; sfondo.height = QH;
{ const g = sfondo.getContext('2d');
  const lin = g.createLinearGradient(0, 0, QW, QH); lin.addColorStop(0, '#0d1530'); lin.addColorStop(1, '#070a12');
  g.fillStyle = lin; g.fillRect(0, 0, QW, QH);
  for (const [x, y, r, c] of [[60, 150, 120, '#1d3a6a'], [270, 30, 110, '#35205e'], [180, 110, 80, '#0f4b5c'], [20, 20, 60, '#1a2450']]) {
    const rg = g.createRadialGradient(x, y, 0, x, y, r); rg.addColorStop(0, c); rg.addColorStop(1, 'transparent');
    g.fillStyle = rg; g.fillRect(0, 0, QW, QH); }
  // Punti di luce lontani: su un colore liscio l'acqua non si vedrebbe.
  let s = 7; const caso = () => (s = (s * 16807) % 2147483647) / 2147483647;
  for (let i = 0; i < 260; i++) { g.fillStyle = `rgba(${150 + caso() * 100},${180 + caso() * 70},255,${0.08 + caso() * 0.25})`;
    const r = 0.4 + caso() * 1.1; g.beginPath(); g.arc(caso() * QW, caso() * QH, r, 0, 7); g.fill(); }
}
const pixSfondo = sfondo.getContext('2d').getImageData(0, 0, QW, QH).data;
const acqua = document.getElementById('acqua'), ga = acqua.getContext('2d');
const piccola = document.createElement('canvas'); piccola.width = QW; piccola.height = QH;
const gp = piccola.getContext('2d'), img = gp.createImageData(QW, QH);
img.data.set(pixSfondo);
let h1 = new Float32Array(QW * QH), h2 = new Float32Array(QW * QH), energia = 1;
M.goccia = (x, y, forza = 1, raggio = 3) => {
  if (!M.materiale.acqua || riduci) return;
  const cx = Math.round(x / 4), cy = Math.round(y / 4);
  for (let dy = -raggio; dy <= raggio; dy++) for (let dx = -raggio; dx <= raggio; dx++) {
    const px = cx + dx, py = cy + dy; if (px < 1 || py < 1 || px >= QW - 1 || py >= QH - 1) continue;
    const d = Math.hypot(dx, dy); if (d > raggio) continue;
    h1[py * QW + px] += forza * 90 * (1 - d / raggio); }
  energia = 1;
};
function acquaPasso() {
  if (energia > 0.002) {
    let e = 0;
    for (let y = 1; y < QH - 1; y++) for (let x = 1; x < QW - 1; x++) {
      const i = y * QW + x;
      const v = ((h1[i - 1] + h1[i + 1] + h1[i - QW] + h1[i + QW]) / 2 - h2[i]) * 0.975;
      h2[i] = v; e += Math.abs(v); }
    [h1, h2] = [h2, h1]; energia = e / (QW * QH);
    const d = img.data;
    for (let y = 1; y < QH - 1; y++) for (let x = 1; x < QW - 1; x++) {
      const i = y * QW + x, dx = h1[i - 1] - h1[i + 1], dy = h1[i - QW] - h1[i + QW];
      const sx = Math.min(QW - 1, Math.max(0, x + (dx * 0.06) | 0)), sy = Math.min(QH - 1, Math.max(0, y + (dy * 0.06) | 0));
      const j = (sy * QW + sx) * 4, o = i * 4, luce = (dx - dy) * 0.9;
      d[o] = pixSfondo[j] + luce; d[o + 1] = pixSfondo[j + 1] + luce; d[o + 2] = pixSfondo[j + 2] + luce * 1.2; d[o + 3] = 255; }
    gp.putImageData(img, 0, 0);
    ga.imageSmoothingQuality = 'high'; ga.drawImage(piccola, 0, 0, W, H);
  } else if (energia > 0) { ga.imageSmoothingQuality = 'high'; ga.drawImage(sfondo, 0, 0, W, H); energia = 0; }
}
ga.drawImage(sfondo, 0, 0, W, H);

// ── Il film: la finestra che cambia colore ──────────────────────────
const scene = [[245, 158, 11], [239, 68, 68], [34, 211, 238], [16, 185, 129], [139, 92, 246]];
M.coloreFilm = [245, 158, 11];
function disegnaFilm(t) {
  const c = document.querySelector('canvas.film'); if (!c) return;
  const g = c.getContext('2d'), k = (t / 3500) % scene.length, a = scene[Math.floor(k)], b = scene[(Math.floor(k) + 1) % scene.length], u = k % 1;
  const col = a.map((v, i) => Math.round(v + (b[i] - v) * u)); M.coloreFilm = col;
  const gr = g.createLinearGradient(0, 0, c.width, c.height); gr.addColorStop(0, `rgb(${col})`); gr.addColorStop(1, '#070a12');
  g.fillStyle = gr; g.fillRect(0, 0, c.width, c.height);
  g.fillStyle = 'rgba(255,255,255,.85)'; g.beginPath(); g.arc(c.width / 2 + c.width * .28 * Math.sin(t / 2100), c.height * .45, 26 + 8 * Math.sin(t / 600), 0, 7); g.fill();
}

// ── Acquerello: il colore di quello che sta dietro ─────────────────
const FW = 40, FH = 23;
const campo = document.createElement('canvas'); campo.width = FW; campo.height = FH;
const gc = campo.getContext('2d');
const accumulo = document.createElement('canvas'); accumulo.width = FW; accumulo.height = FH;
const gacc = accumulo.getContext('2d'); gacc.drawImage(sfondo, 0, 0, FW, FH);
const medio = document.createElement('canvas'); medio.width = 160; medio.height = 90;
const gm = medio.getContext('2d');
const grande = document.createElement('canvas'); grande.width = 640; grande.height = 360;
const gg = grande.getContext('2d');
function campoPasso() {
  gc.drawImage(sfondo, 0, 0, FW, FH);
  for (const o of M.oggetti) if (o.film) {
    gc.fillStyle = `rgb(${M.coloreFilm})`;
    gc.fillRect(o.x / W * FW, o.y / H * FH, o.w / W * FW, o.h / H * FH); }
  // Il colore INSEGUE, non salta: acqua che si mescola.
  gacc.globalAlpha = 0.05; gacc.drawImage(campo, 0, 0); gacc.globalAlpha = 1;
  gm.imageSmoothingQuality = 'high'; gm.drawImage(accumulo, 0, 0, 160, 90);
  gg.imageSmoothingQuality = 'high'; gg.drawImage(medio, 0, 0, 640, 360);
}
const TINTA = 'rgba(8, 11, 20, 0.40)', TINTA_PIENA = 'rgba(12, 16, 28, 0.92)';
function materiale(g, x, y, w, h, densita) {
  // `densita`: le superfici grandi (lo stagno) vogliono più corpo, o il colore
  // di quello che c'è dietro ci passa a macchie e sembra un difetto.
  if (M.materiale.acquerello) { g.drawImage(grande, x / 2, y / 2, w / 2, h / 2, 0, 0, w, h); g.fillStyle = densita ? `rgba(8, 11, 20, ${densita})` : TINTA; }
  else g.fillStyle = TINTA_PIENA;
  g.fillRect(0, 0, w, h);
}

// ── Mercurio: le forme vicine si fondono ───────────────────────────
const colli = document.getElementById('colli'), gcol = colli.getContext('2d');
const maschera = document.createElement('canvas'); maschera.width = 640; maschera.height = 360;
const gma = maschera.getContext('2d', { willReadFrequently: true });
const strato = document.createElement('canvas'); strato.width = 640; strato.height = 360;
const gs = strato.getContext('2d');
let firma = '';
function colliPasso() {
  gcol.clearRect(0, 0, W, H);
  if (!M.materiale.mercurio) return;
  const forme = M.oggetti.filter(o => o.visibile !== false && !o.film && o.scala > 0.2);
  const f = forme.map(o => [o.x, o.y, o.w, o.h, o.r, o.scala].map(v => Math.round(v)).join()).join('|');
  if (f !== firma) {
    firma = f;
    gma.clearRect(0, 0, 640, 360); gma.filter = 'blur(9px)'; gma.fillStyle = '#000';
    for (const o of forme) {
      const w = o.w * o.scala, h = o.h * o.scala, x = o.x + (o.w - w) / 2, y = o.y + (o.h - h) / 2;
      gma.beginPath(); gma.roundRect(x / 2, y / 2, w / 2, h / 2, Math.min(o.r * o.scala, w / 2, h / 2) / 2); gma.fill(); }
    gma.filter = 'none';
    const dati = gma.getImageData(0, 0, 640, 360), d = dati.data;
    for (let i = 3; i < d.length; i += 4) { const a = d[i]; d[i] = a < 122 ? 0 : a > 134 ? 255 : (a - 122) * 21.25; }
    gma.putImageData(dati, 0, 0);
  }
  gs.globalCompositeOperation = 'source-over'; gs.clearRect(0, 0, 640, 360);
  if (M.materiale.acquerello) gs.drawImage(grande, 0, 0); else { gs.fillStyle = '#0c101c'; gs.fillRect(0, 0, 640, 360); }
  gs.fillStyle = M.materiale.acquerello ? TINTA : TINTA_PIENA; gs.fillRect(0, 0, 640, 360);
  gs.globalCompositeOperation = 'destination-in'; gs.drawImage(maschera, 0, 0);
  gcol.imageSmoothingQuality = 'high'; gcol.drawImage(strato, 0, 0, W, H);
}

// ── Oggetti di materiale: finestre, isole, gocce ───────────────────
M.crea = (o) => {
  const el = document.createElement('div'); el.className = 'ogg ' + (o.classe || '');
  const fondo = document.createElement('canvas'); fondo.className = 'fondo';
  const dentro = document.createElement('div'); dentro.className = 'dentro'; dentro.innerHTML = o.html || '';
  el.append(fondo, dentro); (o.sopra || scriv).append(el);
  Object.assign(o, { el, fondo, dentro, vx: 0, vy: 0, scala: o.scala ?? 1, r: o.r ?? 16, z: o.z ?? 10 });
  el.style.borderRadius = o.r + 'px'; el.style.zIndex = o.z;
  M.oggetti.push(o); return o;
};
function disegnaOggetti() {
  for (const o of M.oggetti) {
    const w = Math.max(1, Math.round(o.w)), h = Math.max(1, Math.round(o.h));
    o.el.style.width = w + 'px'; o.el.style.height = h + 'px';
    o.el.style.borderRadius = Math.min(o.r, w / 2, h / 2) + 'px';
    o.el.style.transform = `translate(${o.x}px, ${o.y}px) scale(${o.scala})`;
    o.el.style.display = o.visibile === false || o.scala < 0.02 ? 'none' : '';
    o.el.style.zIndex = o.z;
    if (o.film) continue;
    if (o.fondo.width !== w || o.fondo.height !== h) { o.fondo.width = w; o.fondo.height = h; }
    materiale(o.fondo.getContext('2d'), o.x, o.y, w, h, o.densita);
  }
}

// ── Il tavolo vivo, versione base ──────────────────────────────────
let presa = null, zmax = 50, attiva = null;
M.trascinabile = (o, maniglia) => {
  maniglia.addEventListener('pointerdown', e => {
    e.stopPropagation(); const p = inScrivania(e);
    presa = { o, dx: p.x - o.x, dy: p.y - o.y, storia: [{ ...p, t: performance.now() }] };
    maniglia.setPointerCapture(e.pointerId); o.vx = o.vy = 0; o.z = ++zmax; attiva = o;
  });
};
cornice.addEventListener('pointermove', e => {
  const p = inScrivania(e); M.puntatore = p; M.suMovimento && M.suMovimento(p);
  if (!presa) return;
  presa.o.x = p.x - presa.dx; presa.o.y = p.y - presa.dy;
  presa.storia.push({ ...p, t: performance.now() }); if (presa.storia.length > 6) presa.storia.shift();
});
function lascia() {
  if (!presa) return;
  const s = presa.storia, a = s[0], b = s[s.length - 1], dt = Math.max(16, b.t - a.t), o = presa.o;
  if (!riduci) { o.vx = (b.x - a.x) / dt * 16; o.vy = (b.y - a.y) / dt * 16; }
  presa = null;
  // La finestra posata cade nell'acqua: un'onda dal suo centro.
  if (Math.hypot(o.vx, o.vy) < 4) M.goccia(o.x + o.w / 2, o.y + o.h / 2, 1.3, 5);
  M.suRilascio && M.suRilascio(o);
}
cornice.addEventListener('pointerup', lascia); cornice.addEventListener('pointercancel', lascia);
acqua.addEventListener('pointerdown', e => { const p = inScrivania(e); M.goccia(p.x, p.y, 1.1, 3); M.suClicSfondo && M.suClicSfondo(p); });

let passiScia = 0;
function fisica() {
  for (const o of M.oggetti) {
    if (!o.finestra || (presa && presa.o === o) || (!o.vx && !o.vy)) continue;
    o.x += o.vx; o.y += o.vy; o.vx *= 0.94; o.vy *= 0.94;
    const alto = M.margineAlto || 0, basso = M.margineBasso || 0;
    if (o.x < 0) { o.x = 0; o.vx = -o.vx * .55; M.goccia(o.x, o.y + o.h / 2, .6, 3); }
    if (o.x + o.w > W) { o.x = W - o.w; o.vx = -o.vx * .55; M.goccia(W - 2, o.y + o.h / 2, .6, 3); }
    if (o.y < alto) { o.y = alto; o.vy = -o.vy * .55; }
    if (o.y + o.h > H - basso) { o.y = H - basso - o.h; o.vy = -o.vy * .55; }
    // La scia del lancio.
    if (++passiScia % 3 === 0 && Math.hypot(o.vx, o.vy) > 4) M.goccia(o.x + o.w / 2 - o.vx * 6, o.y + o.h / 2 - o.vy * 6, .35, 2);
    if (Math.hypot(o.vx, o.vy) < .3) { o.vx = o.vy = 0; M.goccia(o.x + o.w / 2, o.y + o.h / 2, 1, 5); }
  }
}

// ── Le finestre di tutte e tre le pagine ───────────────────────────
function finestra(nome, colore, x, y, w, h, contenuto, film) {
  const o = M.crea({ classe: 'fin', finestra: true, film, x, y, w, h, r: 16, z: ++zmax,
    html: `<div class="titolo"><i style="background:${colore}"></i>${nome}</div><div class="contenuto">${contenuto}</div>` });
  if (film) o.el.querySelector('.contenuto').innerHTML = '<canvas class="film" width="440" height="236"></canvas>';
  if (film) { o.el.style.background = '#0c101c'; o.fondo.remove(); }
  M.trascinabile(o, o.el.querySelector('.titolo'));
  o.el.addEventListener('pointerdown', () => { o.z = ++zmax; attiva = o; });
  return o;
}
M.nuovaFinestra = (nome, colore, dove) => {
  const w = 460, h = 290, x = Math.min(W - w - 20, Math.max(20, (dove ? dove.x : W / 2) - w / 2)), y = Math.min(H - h - 20, Math.max(70, (dove ? dove.y : H / 2) - h / 2));
  const o = finestra(nome, colore, x, y, w, h, `<div class="note"><h3>${nome}</h3>Appena aperta. Chiudila con un doppio clic sulla barra del titolo.</div>`);
  o.scala = 0.15; o.scalaObj = 1; M.goccia(x + w / 2, y + h / 2, 1.4, 6);
  o.el.querySelector('.titolo').addEventListener('dblclick', () => { o.scalaObj = 0; o.muore = true; M.goccia(o.x + w / 2, o.y + h / 2, 1, 5); });
  return o;
};
M.finestre = [
  finestra('Film — Il viaggio', '#f59e0b', 120, 150, 440, 270, '', true),
  finestra('Note — idee', '#22d3ee', 600, 120, 360, 250,
    '<div class="note"><h3>Minerva liquida</h3>Il testo resta fermo e nitido; è la forma che si muove. Avvicina questa finestra a un\'altra: si fondono come gocce.</div>'),
  finestra('Editor — acqua.rs', '#8b5cf6', 700, 400, 420, 220,
    '<div class="editor"><span class="c">// l\'acqua sotto la scrivania</span><br><span class="k">fn</span> <span class="f">goccia</span>(x, y, forza) {<br>&nbsp;&nbsp;campo[x][y] += forza;<br>&nbsp;&nbsp;<span class="k">self</span>.<span class="f">onda</span>(<span class="s">"leggera"</span>);<br>}</div>'),
];
M.interruttori = (dove) => {
  const s = (k) => M.materiale[k] ? 'checked' : '';
  dove.innerHTML = `<label><input type="checkbox" id="c-acq" ${s('acquerello')}> Acquerello (il colore di quello che sta dietro)</label>
    <label><input type="checkbox" id="c-mer" ${s('mercurio')}> Mercurio (le forme vicine si fondono)</label>
    <label><input type="checkbox" id="c-acqua" ${s('acqua')}> ${M.etichettaAcqua || 'Increspature (lo sfondo è acqua)'}</label>`;
  dove.querySelector('#c-acq').onchange = e => M.materiale.acquerello = e.target.checked;
  dove.querySelector('#c-mer').onchange = e => { M.materiale.mercurio = e.target.checked; firma = ''; };
  // Spento a metà di un'onda, l'acqua resterebbe ferma increspata: si ridisegna liscia.
  dove.querySelector('#c-acqua').onchange = e => { M.materiale.acqua = e.target.checked; if (!e.target.checked) { h1.fill(0); h2.fill(0); energia = 0; ga.drawImage(sfondo, 0, 0, W, H); } };
};

function molleScala() {
  for (const o of M.oggetti) if (o.scalaObj !== undefined) {
    o.vs = (o.vs || 0) * 0.72 + (o.scalaObj - o.scala) * 0.14; o.scala += o.vs;
    if (o.muore && o.scala < 0.03) { o.visibile = false; }
  }
}
function ciclo(t) {
  disegnaFilm(t); fisica(); molleScala(); M.suPasso && M.suPasso(t);
  campoPasso(); if (M.materiale.acqua) acquaPasso(); colliPasso(); disegnaOggetti();
  requestAnimationFrame(ciclo);
}
M.avvia = () => requestAnimationFrame(ciclo);
})();
"""

ISOLA = r"""
(() => {
const M = window.MINERVA, W = M.W, H = M.H;
M.margineAlto = 0; M.margineBasso = 0;
// ── L'Isola ─────────────────────────────────────────────────────────
const stati = {
  ora:      { w: 190, h: 40,  html: () => `<div class="isola-ora"><b>20:14</b><span>mer 23</span></div>` },
  musica:   { w: 360, h: 64,  html: () => `<div class="isola-riga"><div class="disco"></div><div><b>Aurora</b><span>Minerva Sound</span></div><div class="onda">${'<i></i>'.repeat(9)}</div></div>` },
  scarica:  { w: 320, h: 56,  html: () => `<div class="isola-riga"><div class="freccia">↓</div><div style="flex:1"><b>minerva-0.9.iso</b><div class="barra"><i></i></div></div><span class="num">62%</span></div>` },
  notifica: { w: 420, h: 104, html: () => `<div class="isola-notifica"><div class="freccia" style="background:#22d3ee">A</div><div><b>Thunderbird · Anna</b><span>La cena di sabato: confermi per le otto?</span></div></div>` },
};
let stato = 'ora';
const isola = M.crea({ classe: 'isola', x: W / 2 - 95, y: 12, w: 190, h: 40, r: 24, z: 9000, html: '' });
const obIsola = { w: 190, h: 40 }, vIsola = { w: 0, h: 0 };
function mostra(s) { stato = s; obIsola.w = stati[s].w; obIsola.h = stati[s].h; isola.dentro.innerHTML = stati[s].html(); M.goccia(W / 2, 30, .7, 4); }
M.isolaStato = mostra; mostra('ora');

// ── La dock di mercurio ────────────────────────────────────────────
const app = [['F', '#22d3ee'], ['W', '#8b5cf6'], ['T', '#34d399'], ['M', '#f0abfc'], ['E', '#f59e0b'], ['I', '#60a5fa'], ['S', '#fb7185']];
const dock = M.crea({ classe: 'dock', x: W / 2 - 220, y: H - 78, w: 440, h: 64, r: 26, z: 9000,
  html: `<div class="dock-icone">${app.map(([l, c]) => `<div class="icona" style="background:${c}">${l}</div>`).join('')}</div>` });
const icone = [...dock.dentro.querySelectorAll('.icona')];
M.suMovimento = (p) => {
  const vicino = p.y > H - 130;
  icone.forEach(ic => {
    const r = ic.getBoundingClientRect(), c = M.inScrivania({ clientX: r.left + r.width / 2, clientY: r.top + r.height / 2 });
    const d = Math.abs(p.x - c.x), s = vicino ? 1 + 0.55 * Math.max(0, 1 - d / 150) : 1;
    ic.style.transform = `scale(${s.toFixed(3)})`;
  });
  const gonfia = vicino ? 14 : 0; dock.obH = 64 + gonfia;
};
dock.obH = 64;
M.suPasso = () => {
  // L'isola cambia forma come una goccia: una molla su larghezza e altezza.
  for (const k of ['w', 'h']) { const f = (obIsola[k] - isola[k]) * 0.16; vIsola[k] = vIsola[k] * 0.72 + f; isola[k] += vIsola[k]; }
  isola.x = W / 2 - isola.w / 2;
  dock.h += (dock.obH - dock.h) * 0.2; dock.y = H - 14 - dock.h;
};
const giro = ['ora', 'musica', 'scarica', 'notifica'];
setInterval(() => { if (!document.hidden && M.auto) mostra(giro[(giro.indexOf(stato) + 1) % giro.length]); }, 3200);
M.auto = true;
})();
"""

GOCCIA = r"""
(() => {
const M = window.MINERVA, W = M.W, H = M.H;
M.margineAlto = 0; M.margineBasso = 0;
const R = 30;
const goccia = M.crea({ classe: 'goccia', x: W / 2 - R, y: H - 2 * R - 18, w: 2 * R, h: 2 * R, r: R, z: 9000,
  html: `<div class="goccia-ora">20:14</div>` });
let aperta = false, trascina = null, dest = { x: goccia.x, y: goccia.y }, v = { x: 0, y: 0 };
// Le goccioline che si versano: ognuna porta un'app, e il mercurio le lega.
const app = [['F', '#22d3ee', 'File'], ['W', '#8b5cf6', 'Web'], ['T', '#34d399', 'Terminale'], ['M', '#f0abfc', 'Musica'],
             ['E', '#f59e0b', 'Editor'], ['I', '#60a5fa', 'Impostazioni'], ['S', '#fb7185', 'Foto']];
const gocce = app.map(([l, c, n]) => M.crea({ classe: 'gocciolina', x: goccia.x, y: goccia.y, w: 58, h: 58, r: 29, z: 9001, scala: 0,
  html: `<div class="icona" style="background:${c};margin:7px">${l}</div>` }));
const stato = M.crea({ classe: 'pozza', x: 0, y: 0, w: 300, h: 92, r: 26, z: 9001, scala: 0,
  html: `<div class="pozza"><div class="cerca">Cerca o chiedi…</div><div class="righe"><span>22° sereno</span><span>IT</span><span>76%</span></div><div class="notif"><b>Anna</b> · La cena di sabato?</div></div>` });
function dispiega() {
  const cx = goccia.x + R, cy = goccia.y + R;
  // Verso il centro dello schermo: la goccia si versa dalla parte libera.
  const verso = Math.atan2(H / 2 - cy, W / 2 - cx), n = gocce.length, raggio = 150;
  gocce.forEach((g, i) => {
    const a = verso + (i - (n - 1) / 2) * 0.36;
    g.ox = cx + Math.cos(a) * raggio - 29; g.oy = cy + Math.sin(a) * raggio - 29; g.os = aperta ? 1 : 0;
  });
  stato.ox = cx + Math.cos(verso) * 270 - 150; stato.oy = cy + Math.sin(verso) * 270 - 46; stato.os = aperta ? 1 : 0;
  stato.ox = Math.min(W - 310, Math.max(10, stato.ox)); stato.oy = Math.min(H - 100, Math.max(10, stato.oy));
}
goccia.el.addEventListener('pointerdown', e => {
  e.stopPropagation(); const p = M.inScrivania(e);
  trascina = { dx: p.x - goccia.x, dy: p.y - goccia.y, mosso: 0 }; goccia.el.setPointerCapture(e.pointerId);
});
goccia.el.addEventListener('pointermove', e => {
  if (!trascina) return; const p = M.inScrivania(e);
  goccia.x = p.x - trascina.dx; goccia.y = p.y - trascina.dy; trascina.mosso++; dest = { x: goccia.x, y: goccia.y };
});
goccia.el.addEventListener('pointerup', () => {
  if (!trascina) return;
  if (trascina.mosso < 3) { aperta = !aperta; M.goccia(goccia.x + R, goccia.y + R, 1.2, 5); }
  else {
    // Tensione superficiale: si attacca al bordo più vicino.
    const cx = goccia.x + R, cy = goccia.y + R, dist = [cx, W - cx, cy, H - cy], m = dist.indexOf(Math.min(...dist));
    dest = { x: m === 0 ? 14 : m === 1 ? W - 2 * R - 14 : cx - R, y: m === 2 ? 14 : m === 3 ? H - 2 * R - 14 : cy - R };
  }
  trascina = null;
});
M.suClicSfondo = () => { if (aperta) { aperta = false; } };
M.goccia_apri = () => { aperta = true; M.goccia(goccia.x + R, goccia.y + R, 1.2, 5); };
M.suPasso = () => {
  if (!trascina) { for (const k of ['x', 'y']) { const f = (dest[k] - goccia[k]) * 0.12; v[k] = v[k] * 0.7 + f; goccia[k] += v[k]; } }
  dispiega();
  const cx = goccia.x + R - 29, cy = goccia.y + R - 29;
  [...gocce, stato].forEach((g, i) => {
    const tx = g.os > 0 ? g.ox : (g === stato ? goccia.x + R - 150 : cx), ty = g.os > 0 ? g.oy : (g === stato ? goccia.y + R - 46 : cy);
    const ritardo = aperta ? 0.08 + i * 0.012 : 0.2;
    g.x += (tx - g.x) * ritardo; g.y += (ty - g.y) * ritardo; g.scala += (g.os - g.scala) * (aperta ? 0.12 : 0.25);
  });
};
})();
"""

BORDI = r"""
(() => {
const M = window.MINERVA, W = M.W, H = M.H;
M.margineAlto = 0; M.margineBasso = 0;
const lati = {
  alto:    { html: `<div class="bordo-alto"><b>20:14</b><span>mercoledì 23</span><span>22° sereno</span><span>IT</span><span>76%</span><span class="avviso"><b style="font:600 12.5px var(--display)">Anna</b> · La cena di sabato?</span></div>`,
             riposo: () => ({ x: W / 2 - 160, y: -60, w: 320, h: 60 }), aperto: () => ({ x: W / 2 - 330, y: 10, w: 660, h: 58 }) },
  basso:   { html: `<div class="bordo-app">${[['F','#22d3ee'],['W','#8b5cf6'],['T','#34d399'],['M','#f0abfc'],['E','#f59e0b'],['I','#60a5fa'],['S','#fb7185']].map(([l,c])=>`<div class="icona" style="background:${c}">${l}</div>`).join('')}</div>`,
             riposo: () => ({ x: W / 2 - 150, y: H, w: 300, h: 70 }), aperto: () => ({ x: W / 2 - 230, y: H - 84, w: 460, h: 70 }) },
  sinistra:{ html: `<div class="bordo-stanze"><div class="stanza on"><b>Lavoro</b><i></i></div><div class="stanza"><b>Studio</b><i></i></div><div class="stanza"><b>Svago</b><i></i></div></div>`,
             riposo: () => ({ x: -150, y: H / 2 - 150, w: 150, h: 300 }), aperto: () => ({ x: 12, y: H / 2 - 170, w: 170, h: 340 }) },
  destra:  { html: `<div class="bordo-cassetto"><b>Cassetto</b><div class="voce"><i>PDF</i>preventivo.pdf</div><div class="voce"><i>FOTO</i>tramonto.jpg</div><div class="voce"><i>LINK</i>minerva.dev/piano</div><div class="voce"><i>TESTO</i>«riunione alle 10»</div></div>`,
             riposo: () => ({ x: W, y: H / 2 - 140, w: 190, h: 280 }), aperto: () => ({ x: W - 212, y: H / 2 - 150, w: 200, h: 300 }) },
};
const og = {};
for (const [k, l] of Object.entries(lati)) { const r = l.riposo(); og[k] = M.crea({ classe: 'bordo', ...r, r: 22, z: 9000, html: l.html }); og[k].aperto = false; }
let ultimo = 0;
M.suMovimento = (p) => {
  const vic = { alto: p.y < 14, basso: p.y > H - 14, sinistra: p.x < 14, destra: p.x > W - 14 };
  for (const k in og) {
    const o = og[k], a = lati[k].aperto();
    const dentro = p.x > a.x - 30 && p.x < a.x + a.w + 30 && p.y > a.y - 30 && p.y < a.y + a.h + 30;
    if (vic[k] && !o.aperto) { o.aperto = true; M.goccia(k === 'sinistra' ? 6 : k === 'destra' ? W - 6 : p.x, k === 'alto' ? 6 : k === 'basso' ? H - 6 : p.y, 1, 5); }
    else if (o.aperto && !vic[k] && !dentro) o.aperto = false;
  }
};
M.apriBordo = (k) => { for (const x in og) og[x].aperto = x === k; M.goccia(W / 2, H / 2, .01, 1); };
M.suPasso = () => {
  for (const k in og) {
    const o = og[k], t = o.aperto ? lati[k].aperto() : lati[k].riposo();
    o.vx2 = (o.vx2 || 0) * 0.7 + (t.x - o.x) * 0.12; o.vy2 = (o.vy2 || 0) * 0.7 + (t.y - o.y) * 0.12;
    o.x += o.vx2; o.y += o.vy2; o.w += (t.w - o.w) * 0.14; o.h += (t.h - o.h) * 0.14;
    o.visibile = o.aperto || Math.abs(t.x - o.x) + Math.abs(t.y - o.y) > 2 ? true : false;
  }
};
})();
"""

RIVA = r'''
(() => {
const M = window.MINERVA, W = M.W, H = M.H;
M.margineAlto = 0; M.margineBasso = 0;

// ── L'Isola: trascinabile, si attacca in alto o in basso ────────────
const stati = {
  ora:    { w: 190, h: 40,  html: () => `<div class="isola-ora"><b>20:14</b><span>mer 23</span></div>` },
  musica: { w: 360, h: 64,  html: () => `<div class="isola-riga"><div class="disco"></div><div><b>Aurora</b><span>Minerva Sound</span></div><div class="onda">${'<i></i>'.repeat(9)}</div></div>` },
  stato:  { w: 560, h: 104, html: () => `<div class="isola-stato"><div class="righe"><b>20:14</b><span>mercoledì 23</span><span>22° sereno</span><span>IT</span><span>76%</span></div><div class="notif"><b>Anna</b> · La cena di sabato: confermi per le otto?</div></div>` },
  chiedi: { w: 520, h: 64,  html: () => `<div class="isola-chiedi">Scrivi un'app, un file, un'azione… oppure scrivi e basta, ovunque</div>` },
};
let stato = 'ora', lato = 'alto';
const isola = M.crea({ classe: 'isola', x: W / 2 - 95, y: 12, w: 190, h: 40, r: 24, z: 9000 });
const ob = { w: 190, h: 40 }, v = { w: 0, h: 0 };
let isolaX = W / 2, trascinaIsola = null;
function mostra(s) { stato = s; ob.w = stati[s].w; ob.h = stati[s].h; isola.dentro.innerHTML = stati[s].html(); }
M.isolaStato = mostra; mostra('ora');
isola.el.addEventListener('pointerdown', e => {
  e.stopPropagation(); const p = M.inScrivania(e);
  trascinaIsola = { dx: p.x - isolaX, dy: p.y - isola.y, mosso: 0 }; isola.el.setPointerCapture(e.pointerId);
});
isola.el.addEventListener('pointermove', e => {
  if (!trascinaIsola) return; const p = M.inScrivania(e);
  isolaX = p.x - trascinaIsola.dx; isola.y = p.y - trascinaIsola.dy; trascinaIsola.mosso++;
});
isola.el.addEventListener('pointerup', e => {
  if (!trascinaIsola) return;
  if (trascinaIsola.mosso < 3) mostra(stato === 'chiedi' ? 'ora' : 'chiedi');
  else { const p = M.inScrivania(e); lato = p.y < H / 2 ? 'alto' : 'basso'; M.goccia(isolaX, lato === 'alto' ? 20 : H - 20, 1, 5); M.avviso && M.avviso(`L'Isola ora sta ${lato === 'alto' ? 'in alto' : 'in basso'}.`); }
  trascinaIsola = null;
});

// ── Gli strumenti dei bordi, che si scambiano posto ────────────────
const app = [['File','#22d3ee'],['Web','#8b5cf6'],['Terminale','#34d399'],['Musica','#f0abfc'],['Editor','#f59e0b'],['Impostazioni','#60a5fa']];
const strumenti = {
  banchina: { L: 470, S: 74, html: (v) => `<div class="banchina ${v}">${app.map(([n, c]) => `<div class="icona" title="${n}" data-app="${n}" style="background:${c}">${n[0]}</div>`).join('')}<div class="icona tutte" title="Tutte le app" data-stagno="1">⋯</div></div>` },
  stanze:   { L: 360, S: 150, html: (v) => `<div class="stanze ${v}"><div class="maniglia">Stanze</div><div class="stanza on"><b>Lavoro</b><i></i></div><div class="stanza"><b>Studio</b><i></i></div><div class="stanza"><b>Svago</b><i></i></div></div>` },
  cassetto: { L: 300, S: 200, html: (v) => `<div class="cassetto ${v}"><div class="maniglia">Cassetto</div><div class="voce"><i>PDF</i>preventivo.pdf</div><div class="voce"><i>FOTO</i>tramonto.jpg</div><div class="voce"><i>LINK</i>minerva.dev/piano</div></div>` },
};
const assegnati = { basso: 'banchina', sinistra: 'stanze', destra: 'cassetto' };
function geometria(nome, l, aperto) {
  const t = strumenti[nome];
  if (l === 'basso') return aperto ? { x: W / 2 - t.L / 2, y: H - 14 - t.S, w: t.L, h: t.S } : { x: W / 2 - t.L / 2, y: H + 4, w: t.L, h: t.S };
  if (l === 'sinistra') return aperto ? { x: 14, y: H / 2 - t.L / 2, w: t.S, h: t.L } : { x: -t.S - 4, y: H / 2 - t.L / 2, w: t.S, h: t.L };
  return aperto ? { x: W - 14 - t.S, y: H / 2 - t.L / 2, w: t.S, h: t.L } : { x: W + 4, y: H / 2 - t.L / 2, w: t.S, h: t.L };
}
const og = {};
function latoDi(nome) { return Object.keys(assegnati).find(k => assegnati[k] === nome); }
function riempi(nome) { const l = latoDi(nome); og[nome].dentro.innerHTML = strumenti[nome].html(l === 'basso' ? 'orizz' : 'vert'); agganci(nome); }
for (const nome of Object.keys(strumenti)) { const g = geometria(nome, latoDi(nome), false); og[nome] = M.crea({ classe: 'bordo', ...g, r: 22, z: 9000 }); og[nome].aperto = false; riempi(nome); }
let spostando = null;
function agganci(nome) {
  const o = og[nome];
  o.dentro.querySelectorAll('[data-app]').forEach(ic => ic.addEventListener('click', e => { e.stopPropagation(); const p = M.inScrivania(e); M.nuovaFinestra(ic.dataset.app, ic.style.background, { x: p.x, y: p.y - 200 }); }));
  o.dentro.querySelectorAll('[data-stagno]').forEach(ic => ic.addEventListener('click', e => { e.stopPropagation(); apriStagno(''); }));
  const m = o.dentro.querySelector('.maniglia') || o.dentro.querySelector('.banchina');
  m.addEventListener('pointerdown', e => {
    if (e.target.closest('[data-app],[data-stagno]')) return;
    e.stopPropagation(); const p = M.inScrivania(e);
    spostando = { nome, dx: p.x - o.x, dy: p.y - o.y, mosso: 0 }; m.setPointerCapture(e.pointerId);
  });
  m.addEventListener('pointermove', e => { if (!spostando || spostando.nome !== nome) return; const p = M.inScrivania(e); o.x = p.x - spostando.dx; o.y = p.y - spostando.dy; spostando.mosso++; });
  m.addEventListener('pointerup', e => {
    if (!spostando || spostando.nome !== nome) return;
    if (spostando.mosso > 3) {
      const cx = o.x + o.w / 2, cy = o.y + o.h / 2, d = { sinistra: cx, destra: W - cx, basso: H - cy };
      const nuovo = Object.keys(d).reduce((a, b) => d[a] < d[b] ? a : b), vecchio = latoDi(nome);
      if (nuovo !== vecchio) { const altro = assegnati[nuovo]; assegnati[nuovo] = nome; assegnati[vecchio] = altro; riempi(nome); riempi(altro);
        M.avviso && M.avviso(`${nome[0].toUpperCase() + nome.slice(1)} ora sta ${nuovo === 'basso' ? 'in basso' : 'a ' + nuovo}.`); }
      M.goccia(cx, cy, 1, 5);
    }
    spostando = null;
  });
}

// ── Lo Stagno: tutte le app come gocce ─────────────────────────────
const tutte = [
  ['Lavoro', [['File', 40, '#22d3ee'], ['Terminale', 34, '#34d399'], ['Editor', 30, '#f59e0b'], ['Custodia', 16, '#38bdf8'], ['Calcolatrice', 10, '#94a3b8'], ['Posta', 22, '#60a5fa'], ['Calendario', 12, '#a78bfa']]],
  ['Web', [['Minerva Web', 38, '#8b5cf6'], ['Chrome', 26, '#fbbf24'], ['Telegram', 24, '#38bdf8'], ['Thunderbird', 14, '#3b82f6']]],
  ['Creare', [['GIMP', 12, '#a3a3a3'], ['Inkscape', 6, '#e5e5e5'], ['Kdenlive', 8, '#60a5fa'], ['Blender', 5, '#fb923c'], ['Anteprima', 20, '#f472b6']]],
  ['Svago', [['Steam', 28, '#1e40af'], ['Musica', 26, '#f0abfc'], ['Lettore', 18, '#fb7185'], ['Scacchi', 4, '#d6d3d1']]],
  ['Sistema', [['Impostazioni', 24, '#60a5fa'], ['Attività', 14, '#34d399'], ['Manutenzione', 9, '#fbbf24'], ['Stampanti', 3, '#9ca3af']]],
];
const stagno = M.crea({ classe: 'stagno', x: W / 2 - 235, y: H - 88, w: 470, h: 74, r: 30, z: 9500, scala: 1, visibile: false, densita: 0.8 });
stagno.dentro.innerHTML = `<input id="cerca-stagno" class="cerca-stagno" placeholder="Scrivi il nome di un'app, o cosa vuoi fare" autocomplete="off"><div class="correnti"></div>`;
const correnti = stagno.dentro.querySelector('.correnti'), cerca = stagno.dentro.querySelector('#cerca-stagno');
const centri = [[190, 250], [470, 190], [760, 250], [1000, 190], [640, 430]];
tutte.forEach(([nomeC, lista], ci) => {
  const [cx, cy] = centri[ci];
  const et = document.createElement('div'); et.className = 'corrente'; et.textContent = nomeC; et.style.left = (cx - 60) + 'px'; et.style.top = (cy - 130) + 'px'; correnti.append(et);
  const ord = [...lista].sort((a, b) => b[1] - a[1]);
  ord.forEach(([n, uso, col], i) => {
    const r = 22 + uso * 0.9, ang = i * 2.39996, dist = 30 * Math.sqrt(i) * (i ? 1.9 : 0);
    const d = document.createElement('button'); d.type = 'button'; d.className = 'goccia-app'; d.dataset.nome = n.toLowerCase();
    d.style.cssText = `left:${cx + Math.cos(ang) * dist - r}px;top:${cy + Math.sin(ang) * dist - r}px;width:${2 * r}px;height:${2 * r}px;--c:${col};animation-delay:${-(i * 0.7 + ci)}s`;
    d.innerHTML = `<span>${n}</span>`;
    d.addEventListener('click', e => { e.stopPropagation(); const b = d.getBoundingClientRect(); const p = M.inScrivania({ clientX: b.left + b.width / 2, clientY: b.top + b.height / 2 }); chiudiStagno(); M.nuovaFinestra(n, col, p); });
    correnti.append(d);
  });
});
let stagnoAperto = false;
const chiuso = () => ({ x: W / 2 - 235, y: H - 88, w: 470, h: 74 }), aperto = () => ({ x: 50, y: 64, w: W - 100, h: H - 90 });
function apriStagno(testo) {
  stagnoAperto = true; stagno.visibile = true; cerca.value = testo; filtra(); M.goccia(W / 2, H - 60, 1.4, 6);
  setTimeout(() => cerca.focus(), 30);
}
function chiudiStagno() { stagnoAperto = false; cerca.blur(); }
function filtra() {
  const q = cerca.value.trim().toLowerCase();
  correnti.querySelectorAll('.goccia-app').forEach(d => d.classList.toggle('affonda', q !== '' && !d.dataset.nome.includes(q)));
}
cerca.addEventListener('input', filtra);
cerca.addEventListener('keydown', e => { if (e.key === 'Escape') chiudiStagno(); if (e.key === 'Enter') { const d = correnti.querySelector('.goccia-app:not(.affonda)'); d && d.click(); } });
M.apriStagno = () => apriStagno('');
// Scrivi e basta: una lettera, ovunque, apre lo stagno con quella lettera.
document.addEventListener('keydown', e => {
  if (stagnoAperto || e.ctrlKey || e.metaKey || e.altKey || e.key.length !== 1 || /input|textarea/i.test(document.activeElement.tagName)) return;
  const r = document.getElementById('cornice').getBoundingClientRect(); if (r.bottom < 0 || r.top > innerHeight) return;
  e.preventDefault(); apriStagno(e.key);
});
M.suClicSfondo = () => { if (stagnoAperto) chiudiStagno(); if (stato === 'chiedi') mostra('ora'); };

// ── I bordi, il puntatore, e il passo ──────────────────────────────
M.suMovimento = (p) => {
  const vic = { basso: p.y > H - 14, sinistra: p.x < 14, destra: p.x > W - 14 };
  for (const [l, nome] of Object.entries(assegnati)) {
    const o = og[nome], a = geometria(nome, l, true);
    const dentro = p.x > a.x - 30 && p.x < a.x + a.w + 30 && p.y > a.y - 30 && p.y < a.y + a.h + 30;
    if (vic[l] && !o.aperto && !stagnoAperto) { o.aperto = true; M.goccia(l === 'sinistra' ? 6 : l === 'destra' ? W - 6 : p.x, l === 'basso' ? H - 6 : p.y, 1, 5); }
    else if (o.aperto && !vic[l] && !dentro && !(spostando && spostando.nome === nome)) o.aperto = false;
  }
  // L'Isola: il puntatore sul suo bordo la apre sullo stato.
  const suoBordo = lato === 'alto' ? p.y < 14 : p.y > H - 14;
  if (suoBordo && stato === 'ora') mostra('stato');
  else if (stato === 'stato' && (lato === 'alto' ? p.y > 150 : p.y < H - 150)) mostra('ora');
};
M.apriBordo = (l) => { for (const [k, n] of Object.entries(assegnati)) og[n].aperto = k === l; };
M.suPasso = () => {
  for (const k of ['w', 'h']) { const f = (ob[k] - isola[k]) * 0.16; v[k] = v[k] * 0.72 + f; isola[k] += v[k]; }
  if (!trascinaIsola) {
    isolaX += (Math.min(W - isola.w / 2 - 12, Math.max(isola.w / 2 + 12, isolaX)) - isolaX) * 0.2;
    const ty = lato === 'alto' ? 12 : H - 12 - isola.h; isola.vy2 = (isola.vy2 || 0) * 0.7 + (ty - isola.y) * 0.12; isola.y += isola.vy2;
  }
  isola.x = isolaX - isola.w / 2;
  for (const [l, nome] of Object.entries(assegnati)) {
    const o = og[nome]; if (spostando && spostando.nome === nome) continue;
    const t = geometria(nome, l, o.aperto && !stagnoAperto);
    o.vx2 = (o.vx2 || 0) * 0.7 + (t.x - o.x) * 0.12; o.vy2 = (o.vy2 || 0) * 0.7 + (t.y - o.y) * 0.12;
    o.x += o.vx2; o.y += o.vy2; o.w += (t.w - o.w) * 0.18; o.h += (t.h - o.h) * 0.18;
    o.visibile = o.aperto || Math.abs(t.x - o.x) + Math.abs(t.y - o.y) > 2;
  }
  // Lo stagno sale dalla banchina e ci torna.
  const t = stagnoAperto ? aperto() : chiuso();
  for (const k of ['x', 'y', 'w', 'h']) { stagno['v' + k] = (stagno['v' + k] || 0) * 0.68 + (t[k] - stagno[k]) * 0.1; stagno[k] += stagno['v' + k]; }
  if (!stagnoAperto && Math.abs(stagno.h - t.h) < 3) stagno.visibile = false;
  stagno.el.classList.toggle('pieno', stagno.h > 300);
};
// Il cartello in basso a sinistra, per dire cosa è successo.
const cart = document.createElement('div'); cart.className = 'cartello'; document.getElementById('scrivania').append(cart);
let tc; M.avviso = (t) => { cart.textContent = t; cart.hidden = false; clearTimeout(tc); tc = setTimeout(() => cart.hidden = true, 2400); }; cart.hidden = true;
})();
'''

PAGINE = {
    'riva2': dict(
        titolo='Minerva Riva studiata', sopra='La fusione, seconda versione · menù, controlli, tasti',
        h1='La <b>Riva</b>, studiata meglio',
        sotto='Il menù delle app emerge come un sottomarino dall\'angolo in basso a sinistra e trova le app per nome o per quello che fanno. Wi-Fi, luce notturna, non disturbare, blocco e spegnimento hanno un posto solo: il Centro di controllo, in alto a destra accanto all\'Isola. Lo sfondo liquido ora è un\'opzione, spenta.',
        css=(QUI / 'riva2.css').read_text(),
        pannello=r"""<h2>Cosa provare</h2><ul>
<li>Puntatore nell'<b>angolo in basso a sinistra</b>: spunta il periscopio, poi emerge il menù. Se te ne vai subito, si rituffa.</li>
<li><b>Scrivi</b> ovunque «navigare il web», «chrome», «foto», «conti», «notte»: le app per nome e per funzione, e le azioni.</li>
<li>Nel menù: le quattro <b>viste</b> e <b>⇆</b> per averlo verticale.</li>
<li><b>Angolo in alto a destra</b>, o clic sui segni dell'Isola: il <b>Centro di controllo</b>. Spegni e Riavvia si tengono premuti.</li>
<li>Angolo <b>in basso a destra</b>: la scrivania si libera. Bordi basso, sinistra e destra: banchina, stanze, Cassetto, come prima.</li>
<li>Trascina l'<b>Isola</b> in basso: il Centro di controllo la segue.</li></ul>""",
        comandi=r"""<div class="riga"><button type="button" onclick="MINERVA.apriMenu()">Menù</button><button type="button" onclick="MINERVA.cambiaVerso()">Orizzontale / verticale</button><button type="button" onclick="MINERVA.apriCentro()">Centro di controllo</button><button type="button" onclick="MINERVA.mostraScrivania()">Scrivania libera</button><button type="button" onclick="MINERVA.isolaStato('musica')">Isola: musica</button></div>""",
        dopo=(QUI / 'riva2-tasti.html').read_text(),
        acqua='Sfondo liquido (opzionale: spento di serie)',
        codice=(QUI / 'riva2.js').read_text()),
    'riva': dict(
        titolo='Minerva Riva', sopra='La fusione · Bordi vivi + Isola + Goccia',
        h1='La <b>Riva</b>',
        sotto='I bordi vivi della terza idea, l\'Isola della prima, e dalla Goccia il gesto più semplice: le cose si spostano trascinandole e lasciandole. Le app non sono un elenco: sono uno stagno, e si trovano scrivendo.',
        css=r""".isola .dentro, .bordo .dentro { display: grid; place-items: center; }
.isola { cursor: grab; }
.isola-ora { display: flex; gap: 10px; align-items: baseline; font-size: 13px; color: var(--tenue); }
.isola-ora b { font: 500 16px var(--mono); color: var(--testo); }
.isola-riga { display: flex; align-items: center; gap: 12px; width: 100%; padding: 0 16px; font-size: 13px; }
.isola-riga b { display: block; font-size: 13.5px; } .isola-riga span { color: var(--tenue); font-size: 12px; }
.isola-riga .disco { width: 38px; height: 38px; border-radius: 10px; background: conic-gradient(from 30deg, #8b5cf6, #22d3ee, #f0abfc, #8b5cf6); flex: none; }
.onda { display: flex; gap: 3px; align-items: center; margin-left: auto; }
.onda i { width: 3px; height: 14px; border-radius: 2px; background: var(--accento); animation: onda 1s ease-in-out infinite; }
.onda i:nth-child(2n) { animation-delay: -.3s; } .onda i:nth-child(3n) { animation-delay: -.6s; }
@keyframes onda { 50% { transform: scaleY(.35); } }
.isola-stato { display: grid; gap: 10px; padding: 0 20px; width: 100%; font-size: 13px; }
.isola-stato .righe { display: flex; gap: 16px; align-items: baseline; color: #c7d0e2; white-space: nowrap; }
.isola-stato .righe b { font: 500 17px var(--mono); color: var(--testo); }
.isola-stato .notif { color: #dbe3f3; }
.isola-chiedi { color: var(--tenue); font-size: 13.5px; padding: 0 20px; }
.banchina { display: flex; gap: 12px; align-items: center; justify-content: center; cursor: grab; width: 100%; height: 100%; }
.banchina.vert { flex-direction: column; }
.banchina .icona { cursor: pointer; transition: transform .15s; font-size: 15px; }
.banchina .icona:hover { transform: scale(1.18); }
.banchina .tutte { background: rgba(238,244,255,.14); color: var(--testo); font-size: 20px; }
.maniglia { font: 600 11px var(--mono); letter-spacing: .12em; text-transform: uppercase; color: var(--accento); cursor: grab; padding: 2px 0 6px; }
.stanze, .cassetto { display: flex; flex-direction: column; gap: 8px; width: 100%; padding: 12px 14px; }
.stanze.orizz { flex-direction: row; align-items: stretch; } .stanze.orizz .maniglia { writing-mode: vertical-rl; }
.stanza { border-radius: 12px; padding: 8px; background: rgba(238,244,255,.06); flex: 1; }
.stanza b { font-size: 12px; } .stanza i { display: block; height: 44px; margin-top: 6px; border-radius: 8px; background: linear-gradient(135deg, #1d3a6a, #35205e); }
.stanza.on { outline: 2px solid var(--accento); }
.cassetto .voce { background: rgba(238,244,255,.07); border-radius: 10px; padding: 8px 10px; display: flex; gap: 8px; align-items: center; font-size: 12.5px; }
.cassetto .voce i { font: 600 9.5px var(--mono); letter-spacing: .08em; color: var(--accento); font-style: normal; }
.cassetto.orizz { flex-direction: row; flex-wrap: wrap; align-content: center; }
.stagno .dentro { overflow: hidden; }
.cerca-stagno { position: absolute; left: 50%; top: 18px; transform: translateX(-50%); width: min(520px, 80%); padding: 11px 16px; border-radius: 999px;
  border: 1px solid rgba(238,244,255,.16); background: rgba(7,10,18,.55); color: var(--testo); font: 400 15px var(--display); outline: none; opacity: 0; transition: opacity .25s; }
.cerca-stagno:focus { border-color: rgba(34,211,238,.6); }
.correnti { position: absolute; inset: 0; opacity: 0; transition: opacity .3s; }
.stagno.pieno .cerca-stagno, .stagno.pieno .correnti { opacity: 1; }
.corrente { position: absolute; width: 120px; text-align: center; font: 600 11px var(--mono); letter-spacing: .14em; text-transform: uppercase; color: var(--tenue); }
.goccia-app { position: absolute; border-radius: 50%; border: 1px solid rgba(255,255,255,.18); cursor: pointer; padding: 0;
  background: radial-gradient(circle at 32% 28%, rgba(255,255,255,.55), transparent 32%), radial-gradient(circle at 50% 60%, var(--c), color-mix(in srgb, var(--c) 45%, #070a12));
  box-shadow: 0 8px 22px rgba(0,0,0,.4); display: grid; place-items: center; animation: galleggia 6s ease-in-out infinite;
  transition: opacity .35s, filter .35s, translate .35s; font: 600 11px var(--display); color: #fff; text-shadow: 0 1px 3px rgba(0,0,0,.7); }
.goccia-app span { padding: 0 4px; line-height: 1.1; }
.goccia-app:hover { filter: brightness(1.15); }
.goccia-app:focus-visible { outline: 2px solid var(--accento); outline-offset: 3px; }
.goccia-app.affonda { opacity: .12; filter: blur(2px) saturate(.3); translate: 0 18px; pointer-events: none; }
@keyframes galleggia { 50% { transform: translate(0, -6px) scale(1.03); } }
@media (prefers-reduced-motion: reduce) { .goccia-app { animation: none; } }
.cartello { position: absolute; left: 20px; bottom: 20px; z-index: 9800; font: 500 12.5px var(--display); background: rgba(7,10,18,.8);
  border: 1px solid var(--bordo); border-radius: 999px; padding: 7px 13px; }""",
        pannello=r"""<h2>Cosa provare</h2><ul>
<li><b>Scrivi</b> una lettera qualunque (col puntatore sulla pagina): sale lo <b>stagno</b> delle app. Scrivi «te»: resta a galla Terminale, il resto affonda. Invio apre.</li>
<li>Nello stagno le gocce grandi sono le app che usi di più. <b>Toccane una</b>: l'app nasce da lì. Doppio clic sulla sua barra per chiuderla.</li>
<li>Puntatore contro il <b>bordo basso</b>: la banchina, con «⋯» per lo stagno. <b>Sinistra</b> e <b>destra</b>: stanze e Cassetto.</li>
<li><b>Trascina</b> la banchina (dal bordo, non dalle icone) o il titolo di Stanze e Cassetto verso un altro bordo: si scambiano posto.</li>
<li>Puntatore contro il bordo dell'<b>Isola</b>: si apre sullo stato. Clic: si apre per chiedere. <b>Trascinala</b> in basso: vive lì.</li></ul>""",
        comandi=r"""<div class="riga"><button type="button" onclick="MINERVA.apriStagno()">Apri lo stagno</button><button type="button" onclick="MINERVA.apriBordo('basso')">Banchina</button><button type="button" onclick="MINERVA.apriBordo('sinistra')">Sinistra</button><button type="button" onclick="MINERVA.apriBordo('destra')">Destra</button><button type="button" onclick="MINERVA.isolaStato('musica')">Isola: musica</button><button type="button" onclick="MINERVA.isolaStato('ora')">Isola: ora</button></div>""",
        codice=RIVA),
    'isola': dict(
        titolo='Minerva Isola', sopra='Prototipo 1 di 3 · barra e dock liquide',
        h1='L\'<b>Isola</b> e la dock di mercurio',
        sotto='Barra e dock restano, ma diventano liquide: l\'Isola in alto cambia forma col contesto come una goccia, la dock gonfia le icone al passaggio e si fonde con le finestre che le si avvicinano.',
        css=r""".isola .dentro, .dock .dentro { display: grid; place-items: center; }
.isola-ora { display: flex; gap: 10px; align-items: baseline; font-size: 13px; color: var(--tenue); }
.isola-ora b { font: 500 16px var(--mono); color: var(--testo); }
.isola-riga { display: flex; align-items: center; gap: 12px; width: 100%; padding: 0 16px; font-size: 13px; }
.isola-riga b { display: block; font-size: 13.5px; } .isola-riga span { color: var(--tenue); font-size: 12px; }
.isola-riga .disco { width: 38px; height: 38px; border-radius: 10px; background: conic-gradient(from 30deg, #8b5cf6, #22d3ee, #f0abfc, #8b5cf6); flex: none; }
.onda { display: flex; gap: 3px; align-items: center; margin-left: auto; }
.onda i { width: 3px; height: 14px; border-radius: 2px; background: var(--accento); animation: onda 1s ease-in-out infinite; }
.onda i:nth-child(2n) { animation-delay: -.3s; } .onda i:nth-child(3n) { animation-delay: -.6s; }
@keyframes onda { 50% { transform: scaleY(.35); } }
.freccia { width: 34px; height: 34px; border-radius: 50%; background: #34d399; color: #061018; display: grid; place-items: center; font-weight: 700; flex: none; }
.barra { height: 5px; border-radius: 3px; background: rgba(238,244,255,.12); margin-top: 6px; overflow: hidden; } .barra i { display: block; height: 100%; width: 62%; background: #34d399; }
.num { font: 500 12px var(--mono); color: var(--testo) !important; }
.isola-notifica { display: flex; gap: 12px; align-items: center; padding: 0 18px; font-size: 13px; }
.isola-notifica b { display: block; font-size: 13.5px; margin-bottom: 3px; } .isola-notifica span { color: #c7d0e2; }
.dock-icone { display: flex; gap: 12px; align-items: flex-end; height: 100%; padding-bottom: 10px; }
.dock-icone .icona { transition: transform .12s ease-out; }""",
        pannello=r"""<h2>Cosa provare</h2><ul>
<li>Guarda l'<b>Isola</b>: cambia forma da sola (ora, musica, download, notifica), o scegli tu qui a destra.</li>
<li>Passa col mouse sulla <b>dock</b>: le icone si gonfiano come gocce.</li>
<li>Porta una finestra vicino alla dock o all'Isola: si <b>fondono</b> col mercurio.</li>
<li>Lancia una finestra e lasciala: cade nell'<b>acqua</b>. Clicca lo sfondo.</li></ul>""",
        comandi=r"""<div class="riga"><button type="button" onclick="MINERVA.auto=false;MINERVA.isolaStato('ora')">Ora</button><button type="button" onclick="MINERVA.auto=false;MINERVA.isolaStato('musica')">Musica</button><button type="button" onclick="MINERVA.auto=false;MINERVA.isolaStato('scarica')">Download</button><button type="button" onclick="MINERVA.auto=false;MINERVA.isolaStato('notifica')">Notifica</button><button type="button" onclick="MINERVA.auto=true">Da sola</button></div>""",
        codice=ISOLA),
    'goccia': dict(
        titolo='Minerva Goccia', sopra='Prototipo 2 di 3 · niente barra, niente dock',
        h1='Una <b>Goccia</b> sola',
        sotto='Barra, dock, menù e notifiche diventano un oggetto solo: una goccia che riposa su un bordo. Toccala e si versa nelle app e nello stato; toccala ancora e si ritira. Trascinala: si attacca al bordo più vicino.',
        css=r""".goccia { box-shadow: 0 10px 30px rgba(0,0,0,.45), inset 0 1px 0 rgba(255,255,255,.14); cursor: pointer; }
.goccia .dentro { display: grid; place-items: center; }
.goccia-ora { font: 500 12px var(--mono); }
.gocciolina { box-shadow: 0 8px 20px rgba(0,0,0,.35); }
.pozza { padding: 12px 16px; display: grid; gap: 8px; font-size: 12.5px; }
.pozza .cerca { background: rgba(238,244,255,.08); border-radius: 10px; padding: 8px 12px; color: var(--tenue); }
.pozza .righe { display: flex; gap: 14px; color: #c7d0e2; font-family: var(--mono); font-size: 12px; }
.pozza .notif { color: #dbe3f3; }""",
        pannello=r"""<h2>Cosa provare</h2><ul>
<li><b>Tocca la goccia</b> in basso: si versa in un ventaglio di app, con ricerca, stato e notifiche.</li>
<li><b>Trascinala</b> verso un altro bordo e lasciala: si attacca lì, e si verserà verso il centro.</li>
<li>Clicca lo sfondo per farla ritirare. Lancia le finestre: l'acqua risponde.</li></ul>""",
        comandi=r"""<div class="riga"><button type="button" onclick="MINERVA.goccia_apri()">Versa la goccia</button></div>""",
        codice=GOCCIA),
    'bordi': dict(
        titolo='Minerva Bordi vivi', sopra='Prototipo 3 di 3 · il 100% dello schermo al contenuto',
        h1='Bordi <b>vivi</b>',
        sotto='A riposo non c\'è niente: lo schermo è tutto tuo. I bordi però sono acqua: spingi il puntatore contro un bordo e si gonfia, raccogliendo lo strumento di quel lato. Allontanati e si riassorbe.',
        css=r""".bordo .dentro { padding: 14px 16px; font-size: 12.5px; }
.bordo-alto { display: flex; gap: 16px; align-items: center; height: 100%; margin-top: -14px; color: #c7d0e2; white-space: nowrap; }
.bordo-alto b { font: 500 16px var(--mono); color: var(--testo); } .bordo-alto .avviso { color: var(--testo); margin-left: auto; }
.bordo-app { display: flex; gap: 12px; justify-content: center; align-items: center; height: 100%; margin-top: -14px; }
.bordo-stanze { display: grid; gap: 10px; } .stanza { border-radius: 12px; padding: 8px; background: rgba(238,244,255,.06); }
.stanza b { font-size: 12px; } .stanza i { display: block; height: 52px; margin-top: 6px; border-radius: 8px; background: linear-gradient(135deg, #1d3a6a, #35205e); }
.stanza.on { outline: 2px solid var(--accento); }
.bordo-cassetto { display: grid; gap: 8px; } .bordo-cassetto .voce { background: rgba(238,244,255,.07); border-radius: 10px; padding: 8px 10px; display: flex; gap: 8px; align-items: center; }
.bordo-cassetto .voce i { font: 600 9.5px var(--mono); letter-spacing: .08em; color: var(--accento); font-style: normal; }""",
        pannello=r"""<h2>Cosa provare</h2><ul>
<li>Porta il puntatore contro il <b>bordo alto</b>: ora, stato, notifiche.</li>
<li>Contro il <b>bordo basso</b>: le app. A <b>sinistra</b> le stanze, a <b>destra</b> il Cassetto.</li>
<li>Allontanati: il bordo si riassorbe. Lancia le finestre fino ai bordi.</li></ul>""",
        comandi=r"""<div class="riga"><button type="button" onclick="MINERVA.apriBordo('alto')">Alto</button><button type="button" onclick="MINERVA.apriBordo('basso')">Basso</button><button type="button" onclick="MINERVA.apriBordo('sinistra')">Sinistra</button><button type="button" onclick="MINERVA.apriBordo('destra')">Destra</button><button type="button" onclick="MINERVA.apriBordo('')">Riassorbi</button></div>""",
        codice=BORDI),
}

for nome, p in PAGINE.items():
    html = f"""<meta charset="utf-8">
<title>{p['titolo']}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=Noto+Sans+Mono:wght@400;500&display=swap">
<style>{CSS}
{p['css']}</style>
<div class="guscio">
  <header>
    <div class="sopra">{p['sopra']}</div>
    <h1>{p['h1']}</h1>
    <p class="sotto">{p['sotto']}</p>
  </header>
  <div class="cornice" id="cornice">
    <div class="scrivania" id="scrivania">
      <canvas class="acqua" id="acqua" width="1280" height="720"></canvas>
      <canvas class="colli" id="colli" width="1280" height="720"></canvas>
    </div>
  </div>
  <section class="pannello">
    <div>{p['pannello']}</div>
    <div class="scatola">{p['comandi']}<div id="interruttori" style="display:grid;gap:8px"></div></div>
  </section>
  {p.get('dopo', '')}
  <p class="altre">Le tre pagine hanno lo stesso materiale e le stesse finestre: cambia solo il modo di stare sulla scrivania. Solido ma liquido: il testo resta fermo, si muove la forma.</p>
</div>
<script>{MOTORE}</script>
<script>{p['codice']}
MINERVA.etichettaAcqua = {p.get('acqua', '')!r} || undefined;
MINERVA.interruttori(document.getElementById('interruttori'));
MINERVA.avvia();
</script>
"""
    (QUI / f"minerva-{nome}.html").write_text(html)
    print("scritta", nome)

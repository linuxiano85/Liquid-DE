(() => {
const M = window.MINERVA, W = M.W, H = M.H;
M.margineAlto = 0; M.margineBasso = 0;
// Lo sfondo liquido è un'opzione, e parte spento.
M.materiale.acqua = false;
const scriv = document.getElementById('scrivania');

// ── Le impostazioni rapide ──────────────────────────────────────────
const rapide = { wifi: true, bt: false, notte: false, dnd: false, risparmio: false, gioco: false, volume: 62, luce: 100 };
const NOMI = { wifi: 'Wi-Fi', bt: 'Bluetooth', notte: 'Luce notturna', dnd: 'Non disturbare', risparmio: 'Risparmio', gioco: 'Modo gioco' };

// ── L'Isola: trascinabile, in alto o in basso ───────────────────────
let lato = 'alto', stato = 'ora';
const segni = () => [rapide.dnd && 'NON DISTURBARE', rapide.notte && 'NOTTE', rapide.gioco && 'GIOCO', rapide.risparmio && 'RISPARMIO']
  .filter(Boolean).map(s => `<i class="acceso">${s}</i>`).join('') + `<i>${rapide.wifi ? 'WI-FI' : 'NO RETE'}</i><i>76%</i>`;
const accesi = () => rapide.dnd + rapide.notte + rapide.gioco + rapide.risparmio;
const stati = {
  ora:    () => ({ w: 250 + accesi() * 96, h: 40,
            html: `<div class="isola-ora"><b>20:14</b><span class="tempo">mer 23</span><button type="button" class="stato-isola" title="Centro di controllo">${segni()}</button></div>` }),
  stato:  () => ({ w: Math.max(560, 420 + accesi() * 96), h: 104,
            html: `<div class="isola-stato"><div class="righe"><b>20:14</b><span>mercoledì 23</span><span>22° sereno</span><button type="button" class="stato-isola" title="Centro di controllo">${segni()}</button></div><div class="notif">${rapide.dnd ? '<span class="tenue">Non disturbare: 2 notifiche tenute da parte</span>' : '<b>Anna</b> · La cena di sabato: confermi per le otto?'}</div></div>` }),
  musica: () => ({ w: 360, h: 64,
            html: `<div class="isola-riga"><div class="disco"></div><div><b>Aurora</b><span>Minerva Sound</span></div><div class="onda">${'<i></i>'.repeat(9)}</div></div>` }),
};
const isola = M.crea({ classe: 'isola', x: W / 2 - 125, y: 12, w: 250, h: 40, r: 24, z: 9000 });
const ob = { w: 250, h: 40 }, v = { w: 0, h: 0 };
let isolaX = W / 2, trascinaIsola = null;
function mostra(s) {
  stato = s; const st = stati[s](); ob.w = st.w; ob.h = st.h; isola.dentro.innerHTML = st.html;
  isola.dentro.querySelectorAll('.stato-isola').forEach(b => {
    b.addEventListener('pointerdown', e => e.stopPropagation());
    b.addEventListener('click', e => { e.stopPropagation(); centroAperto ? chiudiCentro() : apriCentro(); });
  });
}
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
  if (trascinaIsola.mosso < 3) mostra(stato === 'ora' ? 'stato' : 'ora');
  else {
    const p = M.inScrivania(e), prima = lato; lato = p.y < H / 2 ? 'alto' : 'basso';
    M.goccia(isolaX, lato === 'alto' ? 20 : H - 20, 1, 5);
    if (lato !== prima) M.avviso(`L'Isola ora sta ${lato === 'alto' ? 'in alto' : 'in basso'}: il Centro di controllo la segue.`);
  }
  trascinaIsola = null;
});

// ── Gli strumenti dei bordi, che si scambiano posto ────────────────
const fisse = [['File', '#22d3ee'], ['Minerva Web', '#8b5cf6'], ['Terminale', '#34d399'], ['Musica', '#f0abfc'], ['Editor', '#fbbf24'], ['Impostazioni', '#60a5fa']];
const strumenti = {
  banchina: { L: 470, S: 74, html: (v) => `<div class="banchina ${v}">${fisse.map(([n, c]) => `<div class="icona" title="${n}" data-app="${n}" style="background:${c}">${n[0]}</div>`).join('')}<div class="icona tutte" title="Tutte le app" data-menu="1">⋯</div></div>` },
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
const latoDi = (nome) => Object.keys(assegnati).find(k => assegnati[k] === nome);
function riempi(nome) { og[nome].dentro.innerHTML = strumenti[nome].html(latoDi(nome) === 'basso' ? 'orizz' : 'vert'); agganci(nome); }
for (const nome of Object.keys(strumenti)) { og[nome] = M.crea({ classe: 'bordo', ...geometria(nome, latoDi(nome), false), r: 22, z: 9000 }); og[nome].aperto = false; riempi(nome); }
let spostando = null;
function agganci(nome) {
  const o = og[nome];
  o.dentro.querySelectorAll('[data-app]').forEach(ic => ic.addEventListener('click', e => { e.stopPropagation(); const p = M.inScrivania(e); M.nuovaFinestra(ic.dataset.app, ic.style.background, { x: p.x, y: p.y - 200 }); }));
  o.dentro.querySelectorAll('[data-menu]').forEach(ic => ic.addEventListener('click', e => { e.stopPropagation(); apriMenu(''); }));
  const m = o.dentro.querySelector('.maniglia') || o.dentro.querySelector('.banchina');
  m.addEventListener('pointerdown', e => {
    if (e.target.closest('[data-app],[data-menu]')) return;
    e.stopPropagation(); const p = M.inScrivania(e);
    spostando = { nome, dx: p.x - o.x, dy: p.y - o.y, mosso: 0 }; m.setPointerCapture(e.pointerId);
  });
  m.addEventListener('pointermove', e => { if (!spostando || spostando.nome !== nome) return; const p = M.inScrivania(e); o.x = p.x - spostando.dx; o.y = p.y - spostando.dy; spostando.mosso++; });
  m.addEventListener('pointerup', () => {
    if (!spostando || spostando.nome !== nome) return;
    if (spostando.mosso > 3) {
      const cx = o.x + o.w / 2, cy = o.y + o.h / 2, d = { sinistra: cx, destra: W - cx, basso: H - cy };
      const nuovo = Object.keys(d).reduce((a, b) => d[a] < d[b] ? a : b), vecchio = latoDi(nome);
      if (nuovo !== vecchio) { const altro = assegnati[nuovo]; assegnati[nuovo] = nome; assegnati[vecchio] = altro; riempi(nome); riempi(altro);
        M.avviso(`${nome[0].toUpperCase() + nome.slice(1)} ora sta ${nuovo === 'basso' ? 'in basso' : 'a ' + nuovo}.`); }
      M.goccia(cx, cy, 1, 5);
    }
    spostando = null;
  });
}

// ── Il catalogo: nome, cosa fa, parole, categoria, attività, uso ───
const APP = [
  ['Minerva Web', 'Browser web', 'internet navigare siti pagine browser', 'Internet', 'Navigare', 38, '#8b5cf6'],
  ['Google Chrome', 'Browser web', 'internet navigare siti browser google', 'Internet', 'Navigare', 30, '#f59e0b'],
  ['Firefox', 'Browser web', 'internet navigare siti browser mozilla', 'Internet', 'Navigare', 6, '#fb923c'],
  ['Telegram', 'Messaggi', 'chat messaggi amici chiamate', 'Internet', 'Comunicare', 24, '#38bdf8'],
  ['Thunderbird', 'Posta elettronica', 'email posta mail', 'Internet', 'Comunicare', 14, '#3b82f6'],
  ['File', 'Gestore file', 'cartelle documenti esplorare', 'Accessori', 'Organizzare', 40, '#22d3ee'],
  ['Calendario', 'Calendario', 'appuntamenti eventi date agenda', 'Ufficio', 'Organizzare', 12, '#a78bfa'],
  ['Custodia', 'Salvataggi', 'backup copie ripristino', 'Sistema', 'Organizzare', 16, '#0ea5e9'],
  ['Terminale', 'Riga di comando', 'console shell comandi bash', 'Sistema', 'Programmare', 34, '#34d399'],
  ['Codice', 'Ambiente di sviluppo', 'programmare sviluppo vscode', 'Sviluppo', 'Programmare', 22, '#60a5fa'],
  ['Editor', 'Editor di testo', 'testo scrivere note appunti codice', 'Accessori', 'Scrivere', 30, '#fbbf24'],
  ['Writer', 'Elaboratore di testi', 'documenti lettere word libreoffice', 'Ufficio', 'Scrivere', 10, '#2563eb'],
  ['Calc', 'Foglio di calcolo', 'tabelle excel conti numeri libreoffice', 'Ufficio', 'Calcolare', 6, '#16a34a'],
  ['Calcolatrice', 'Calcolatrice', 'conti numeri calcoli percentuali', 'Accessori', 'Calcolare', 10, '#94a3b8'],
  ['Anteprima', 'Visualizzatore di immagini', 'foto immagini album', 'Grafica', 'Guardare', 20, '#f472b6'],
  ['Lettore', 'Lettore video', 'film video serie', 'Multimedia', 'Guardare', 18, '#fb7185'],
  ['Musica', 'Lettore musicale', 'canzoni audio brani', 'Multimedia', 'Ascoltare', 26, '#f0abfc'],
  ['GIMP', 'Fotoritocco', 'foto immagini modificare ritoccare', 'Grafica', 'Creare', 12, '#a8a29e'],
  ['Inkscape', 'Grafica vettoriale', 'disegno loghi svg illustrazioni disegnare', 'Grafica', 'Creare', 5, '#d6d3d1'],
  ['Kdenlive', 'Montaggio video', 'video montare filmati', 'Multimedia', 'Creare', 8, '#818cf8'],
  ['Blender', 'Modellazione 3D', '3d animazione modelli', 'Grafica', 'Creare', 4, '#fb923c'],
  ['Steam', 'Negozio di giochi', 'giochi videogiochi', 'Giochi', 'Giocare', 28, '#1d4ed8'],
  ['Impostazioni', 'Impostazioni di sistema', 'preferenze configurare opzioni', 'Sistema', 'Sistemare', 24, '#60a5fa'],
  ['Attività', 'Monitor di sistema', 'processi memoria cpu task manager', 'Sistema', 'Sistemare', 14, '#34d399'],
  ['Manutenzione', 'Pulizia e salute', 'pulire spazio disco aggiornamenti', 'Sistema', 'Sistemare', 9, '#eab308'],
].map(([n, g, p, c, a, u, col]) => ({ n, g, p, c, a, u, col }));
const AZIONI = [
  ['Blocca lo schermo', 'blocca bloccare lock schermo', 'blocca'], ['Sospendi', 'sospendi dormire sleep', 'sospendi'],
  ['Riavvia', 'riavvia riavviare reboot', 'riavvia'], ['Spegni', 'spegni spegnere arresta shutdown', 'spegni'],
  ['Esci dalla sessione', 'esci uscire logout sessione', 'esci'],
  ['Wi-Fi', 'wifi rete internet wireless', 'wifi'], ['Bluetooth', 'bluetooth cuffie', 'bt'],
  ['Luce notturna', 'luce notturna notte occhi sera', 'notte'], ['Non disturbare', 'non disturbare silenzio notifiche', 'dnd'],
].map(([n, p, id]) => ({ n, p, id }));
// I sinonimi: è quello che fa trovare Chrome scrivendo «navigare il web».
const SIN = { navigare: ['web', 'internet', 'browser', 'siti'], internet: ['web', 'browser'], browser: ['web'], web: ['browser', 'internet'],
  scrivere: ['testo', 'documenti', 'note'], foto: ['immagini'], immagini: ['foto'], musica: ['audio', 'canzoni'],
  video: ['film', 'filmati'], film: ['video'], giocare: ['giochi', 'videogiochi'], giochi: ['giocare'], posta: ['email', 'mail'],
  email: ['posta', 'mail'], mail: ['posta', 'email'], chat: ['messaggi'], disegnare: ['disegno', 'illustrazioni', 'vettoriale'], cartelle: ['file'],
  comandi: ['terminale', 'console', 'shell'], programmare: ['codice', 'sviluppo'], conti: ['calcolatrice', 'numeri', 'calcoli'],
  backup: ['salvataggi', 'copie'], pulire: ['pulizia', 'spazio'], ascoltare: ['musica', 'audio'], guardare: ['video', 'film', 'foto'] };
const VUOTE = new Set(['il', 'lo', 'la', 'i', 'gli', 'le', 'di', 'a', 'da', 'in', 'con', 'su', 'per', 'un', 'una', 'e', 'del', 'della', 'voglio', 'vorrei', 'apri']);
const norma = (s) => s.toLowerCase().normalize('NFD').replace(/\p{M}/gu, '');
function valuta(o, campi, parole, sinonimi = true) {
  let punti = 0, prese = 0, perche = '';
  for (const t of parole) {
    const termini = sinonimi ? [t, ...(SIN[t] || [])] : [t]; let meglio = 0, qui = '';
    // Una lettera sola cerca solo l'inizio dei nomi: è «scrivi e basta».
    for (const [peso, testo, motivo] of (t.length === 1 ? campi.slice(0, 1) : campi)) for (const x of termini) {
      const nt = norma(testo), inizia = nt.split(/[\s-]+/).some(w => w.startsWith(x));
      const p = inizia ? peso : (t.length > 2 && nt.includes(x)) ? peso * 0.6 : 0;
      if (p > meglio) { meglio = p; qui = motivo(x); }
    }
    if (meglio) { prese++; punti += meglio; if (!perche) perche = qui; }
  }
  return { punti: punti + (o.u || 0) * 0.3, prese, perche };
}
function cerca(q) {
  const parole = norma(q).split(/\s+/).filter(t => t && !VUOTE.has(t));
  if (!parole.length) return { app: [], azioni: [] };
  const app = APP.map(a => ({ a, ...valuta(a, [[100, a.n, () => 'per nome'], [55, a.g, () => `perché è un «${a.g.toLowerCase()}»`],
      [40, a.p, (x) => `per «${x}»`], [30, a.a, () => `perché serve a ${a.a.toLowerCase()}`]], parole) }))
    .filter(r => r.prese).sort((x, y) => y.prese - x.prese || y.punti - x.punti);
  // Se qualcosa risponde a tutte le parole, il resto è rumore. Le azioni senza sinonimi:
  // «navigare il web» non deve proporre di spegnere il Wi-Fi.
  const piene = app.filter(r => r.prese === parole.length);
  const azioni = AZIONI.map(a => ({ a, ...valuta(a, [[100, a.n, () => ''], [60, a.p, () => '']], parole, false) })).filter(r => r.prese)
    .sort((x, y) => y.punti - x.punti).slice(0, 3);
  return { app: piene.length ? piene : app, azioni };
}

// ── La bolla: il periscopio che spunta nell'angolo prima dello scafo ─
const bolla = M.crea({ classe: 'bolla', x: 4, y: H - 40, w: 36, h: 36, r: 18, z: 9601, scala: 0 });
bolla.scalaObj = 0;
function bollaIn(angolo) {
  const pos = { 'basso-sx': [4, H - 40], 'alto-sx': [4, 4], 'alto-dx': [W - 40, 4], 'basso-dx': [W - 40, H - 40] }[angolo];
  bolla.x = pos[0]; bolla.y = pos[1]; bolla.scalaObj = 1;
}

// ── Il Sottomarino: il menù delle app ──────────────────────────────
let vista = 'categorie', verso = 'orizzontale', categoria = 'Tutte', menuAperto = false, menuEntrato = false, fase = 0;
const menu = M.crea({ classe: 'menu', x: 16, y: H + 30, w: 920, h: 400, r: 26, z: 9600, densita: 0.84, visibile: false });
menu.vel = {};
menu.dentro.innerHTML = `<div class="menu-testa">
    <input id="cerca-app" class="cerca-app" placeholder="Nome dell'app o cosa vuoi fare: «navigare il web», «foto», «spegni»…" autocomplete="off" aria-label="Cerca app e azioni">
    <div class="viste" role="tablist" aria-label="Viste del menù">
      <button type="button" role="tab" data-vista="categorie">Categorie</button><button type="button" role="tab" data-vista="attivita">Cosa vuoi fare</button><button type="button" role="tab" data-vista="frequenti">Frequenti</button><button type="button" role="tab" data-vista="az">A–Z</button>
      <button type="button" class="verso" title="Orizzontale o verticale">⇆ <span>Verticale</span></button>
    </div></div><div class="menu-corpo"></div>`;
const campo = menu.dentro.querySelector('#cerca-app'), corpo = menu.dentro.querySelector('.menu-corpo');
function geomMenu(aperto) {
  const sotto = lato === 'basso' ? 64 : 0;
  const g = verso === 'orizzontale' ? { x: 16, y: H - 16 - 400 - sotto, w: 920, h: 400 } : { x: 16, y: 16, w: 410, h: H - 32 - sotto };
  return aperto ? g : { ...g, y: H + 30 };
}
const tessera = (a, grande) => `<button type="button" class="tessera${grande ? ' grande' : ''}" data-app="${a.n}"><span class="ic" style="background:${a.col}">${a.n[0]}</span><span class="nm">${a.n}</span><span class="gn">${a.g}</span></button>`;
function disegnaMenu() {
  menu.dentro.classList.toggle('vert', verso === 'verticale');
  menu.dentro.querySelector('.verso span').textContent = verso === 'orizzontale' ? 'Verticale' : 'Orizzontale';
  menu.dentro.querySelectorAll('[data-vista]').forEach(b => b.setAttribute('aria-selected', b.dataset.vista === vista));
  const q = campo.value.trim();
  let h = '';
  if (q) {
    const { app, azioni } = cerca(q);
    if (azioni.length) h += `<div class="gruppo"><h4>Azioni</h4><div class="azioni">${azioni.map(r => `<button type="button" class="azione" data-azione="${r.a.id}">${r.a.n}${r.a.id in NOMI ? ` <b>${rapide[r.a.id] ? 'acceso' : 'spento'}</b>` : ''}</button>`).join('')}</div></div>`;
    h += app.length ? `<div class="gruppo"><h4>App</h4><div class="risultati">${app.slice(0, 8).map(r => `<button type="button" class="risultato" data-app="${r.a.n}"><span class="ic" style="background:${r.a.col}">${r.a.n[0]}</span><span><b>${r.a.n}</b><small>${r.a.g} · trovata ${r.perche}</small></span></button>`).join('')}</div></div>`
      : azioni.length ? '' : `<p class="niente">Nessuna app per «${q}». Prova con quello che vuoi fare: «ascoltare», «disegnare», «conti».</p>`;
  } else if (vista === 'categorie') {
    const cats = ['Tutte', ...new Set(APP.map(a => a.c))];
    h = `<div class="cat-riga">${cats.map(c => `<button type="button" class="cat" data-cat="${c}" aria-pressed="${c === categoria}">${c}</button>`).join('')}</div>
      <div class="griglia">${APP.filter(a => categoria === 'Tutte' || a.c === categoria).sort((x, y) => x.n.localeCompare(y.n)).map(a => tessera(a)).join('')}</div>`;
  } else if (vista === 'attivita') {
    h = [...new Set(APP.map(a => a.a))].map(vb => `<div class="gruppo"><h4>${vb}</h4><div class="fila">${APP.filter(a => a.a === vb).sort((x, y) => y.u - x.u).map(a => tessera(a)).join('')}</div></div>`).join('');
  } else if (vista === 'frequenti') {
    const ord = [...APP].sort((x, y) => y.u - x.u);
    h = `<div class="gruppo"><h4>Le più usate a quest'ora</h4><div class="fila">${ord.slice(0, 6).map(a => tessera(a, true)).join('')}</div></div>
      <div class="gruppo"><h4>Poi</h4><div class="griglia">${ord.slice(6).map(a => tessera(a)).join('')}</div></div>`;
  } else {
    const perLettera = {};
    [...APP].sort((x, y) => x.n.localeCompare(y.n)).forEach(a => (perLettera[a.n[0].toUpperCase()] ||= []).push(a));
    h = `<div class="az">${Object.entries(perLettera).map(([l, lista]) => `<div class="lettera"><span class="l">${l}</span><div>${lista.map(a => `<button type="button" class="riga-az" data-app="${a.n}"><span class="ic piccola" style="background:${a.col}">${a.n[0]}</span>${a.n}<small>${a.g}</small></button>`).join('')}</div></div>`).join('')}</div>`;
  }
  corpo.innerHTML = h;
  corpo.querySelectorAll('[data-app]').forEach(b => b.addEventListener('click', e => {
    e.stopPropagation(); const a = APP.find(x => x.n === b.dataset.app);
    chiudiMenu(); M.nuovaFinestra(a.n, a.col, { x: 640 + (Math.random() - .5) * 240, y: 330 });
  }));
  corpo.querySelectorAll('[data-cat]').forEach(b => b.addEventListener('click', e => { e.stopPropagation(); categoria = b.dataset.cat; disegnaMenu(); }));
  corpo.querySelectorAll('[data-azione]').forEach(b => b.addEventListener('click', e => { e.stopPropagation(); azioneDalMenu(b.dataset.azione); }));
}
menu.dentro.querySelectorAll('[data-vista]').forEach(b => b.addEventListener('click', e => { e.stopPropagation(); vista = b.dataset.vista; campo.value = ''; disegnaMenu(); }));
menu.dentro.querySelector('.verso').addEventListener('click', e => { e.stopPropagation(); cambiaVerso(); });
function cambiaVerso() { verso = verso === 'orizzontale' ? 'verticale' : 'orizzontale'; disegnaMenu(); M.avviso(`Menù ${verso}.`); }
campo.addEventListener('input', disegnaMenu);
campo.addEventListener('keydown', e => {
  if (e.key === 'Escape') chiudiMenu();
  if (e.key === 'Enter') { const b = corpo.querySelector('[data-app],[data-azione]'); b && b.click(); }
});
menu.el.addEventListener('pointerdown', e => e.stopPropagation());
function apriMenu(testo) {
  chiudiCentro();
  if (menuAperto) { if (testo) { campo.value = testo; disegnaMenu(); campo.focus({ preventScroll: true }); } return; }
  menuAperto = true; menuEntrato = false; menu.visibile = true; campo.value = testo || ''; disegnaMenu();
  // Prima il periscopio, poi lo scafo. Il fuoco senza scorrere: col menù ancora
  // sott'acqua il browser farebbe scorrere la cornice per mostrarlo, e la scrivania salterebbe.
  bollaIn('basso-sx'); fase = performance.now();
  M.goccia(24, H - 24, 1.2, 5);
  setTimeout(() => { if (menuAperto) campo.focus({ preventScroll: true }); }, 420);
}
function chiudiMenu() { if (!menuAperto) return; menuAperto = false; campo.blur(); M.goccia(120, H - 10, .8, 4); }
M.apriMenu = () => apriMenu('');
M.cercaNelMenu = (t) => { apriMenu(''); campo.value = t; disegnaMenu(); };
M.cambiaVerso = cambiaVerso;

// ── Il Centro di controllo ──────────────────────────────────────────
let centroAperto = false, centroEntrato = false;
const CW = 390, CH = 486;
const centro = M.crea({ classe: 'centro', x: W - 16 - CW, y: -CH - 30, w: CW, h: CH, r: 26, z: 9600, densita: 0.84, visibile: false });
centro.vel = {};
const geomCentro = (aperto) => ({ x: W - 16 - CW, y: lato === 'alto' ? (aperto ? 16 : -CH - 30) : (aperto ? H - 16 - CH : H + 30) });
const SVG = {
  prec: '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3 3h2v10H3zM14 3v10L6 8z"/></svg>',
  pausa: '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M4 3h3v10H4zM9 3h3v10H9z"/></svg>',
  succ: '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M11 3h2v10h-2zM2 3v10l8-5z"/></svg>',
};
function disegnaCentro() {
  const t = (id, sotto) => `<button type="button" class="interr${rapide[id] ? ' on' : ''}" data-rapida="${id}" aria-pressed="${rapide[id]}"><b>${NOMI[id]}</b><small>${rapide[id] ? sotto : 'spento'}</small></button>`;
  const cursore = (id, nome) => `<div class="liquido" data-cursore="${id}" role="slider" aria-label="${nome}" aria-valuenow="${rapide[id]}"><i style="width:${rapide[id]}%"></i><span>${nome}</span><em>${rapide[id]}%</em></div>`;
  centro.dentro.innerHTML = `<div class="centro-dentro">
    <div class="interruttori-rapidi">${t('wifi', 'Casa-5G')}${t('bt', 'Cuffie')}${t('notte', 'fino alle 7:00')}${t('dnd', 'finché lo spegni')}${t('risparmio', 'effetti ridotti')}${t('gioco', 'notifiche zitte')}</div>
    ${cursore('volume', 'Volume')}${cursore('luce', 'Luminosità')}
    <div class="lettore"><span class="disco"></span><span class="titoli"><b>Aurora</b><small>Minerva Sound</small></span><span class="tasti"><button type="button" aria-label="Precedente">${SVG.prec}</button><button type="button" aria-label="Pausa">${SVG.pausa}</button><button type="button" aria-label="Successivo">${SVG.succ}</button></span></div>
    <div class="energia"><button type="button" data-energia="blocca">Blocca</button><button type="button" data-energia="sospendi">Sospendi</button><button type="button" class="tieni" data-energia="esci"><i></i><span>Esci</span></button><button type="button" class="tieni" data-energia="riavvia"><i></i><span>Riavvia</span></button><button type="button" class="tieni" data-energia="spegni"><i></i><span>Spegni</span></button></div>
    <p class="tieni-nota">Esci, Riavvia e Spegni: tieni premuto finché non si riempie.</p></div>`;
  centro.dentro.querySelectorAll('[data-rapida]').forEach(b => b.addEventListener('click', e => { e.stopPropagation(); esegui(b.dataset.rapida); }));
  centro.dentro.querySelectorAll('[data-cursore]').forEach(c => {
    const id = c.dataset.cursore;
    const imposta = (e) => {
      const r = c.getBoundingClientRect(); rapide[id] = Math.round(Math.max(id === 'luce' ? .2 : 0, Math.min(1, (e.clientX - r.left) / r.width)) * 100);
      c.querySelector('i').style.width = rapide[id] + '%'; c.querySelector('em').textContent = rapide[id] + '%'; c.setAttribute('aria-valuenow', rapide[id]);
      if (id === 'luce') aggiornaLuce();
    };
    c.addEventListener('pointerdown', e => { e.stopPropagation(); c.setPointerCapture(e.pointerId); imposta(e); c.onpointermove = imposta; });
    c.addEventListener('pointerup', () => { c.onpointermove = null; });
  });
  centro.dentro.querySelectorAll('[data-energia]').forEach(b => {
    const cosa = b.dataset.energia;
    if (!b.classList.contains('tieni')) { b.addEventListener('click', e => { e.stopPropagation(); esegui(cosa); }); return; }
    // Niente finestra «sei sicuro?»: il pulsante si riempie d'acqua mentre lo tieni.
    let t0 = 0, anim = 0;
    const acqua = b.querySelector('i');
    const riempi = () => {
      const k = Math.min(1, (performance.now() - t0) / 900); acqua.style.height = (k * 100) + '%';
      if (k >= 1) { b.classList.remove('premuto'); acqua.style.height = '0'; esegui(cosa); return; }
      anim = requestAnimationFrame(riempi);
    };
    b.addEventListener('pointerdown', e => { e.stopPropagation(); t0 = performance.now(); b.classList.add('premuto'); anim = requestAnimationFrame(riempi); });
    const ferma = () => { cancelAnimationFrame(anim); b.classList.remove('premuto'); acqua.style.height = '0'; };
    b.addEventListener('pointerup', ferma); b.addEventListener('pointerleave', ferma);
  });
}
centro.el.addEventListener('pointerdown', e => e.stopPropagation());
function apriCentro() {
  chiudiMenu(); if (centroAperto) return;
  centroAperto = true; centroEntrato = false; centro.visibile = true; disegnaCentro();
  centro.y = geomCentro(false).y; centro.vel = {};
  bollaIn(lato === 'alto' ? 'alto-dx' : 'basso-dx'); M.goccia(W - 24, lato === 'alto' ? 24 : H - 24, 1.2, 5);
}
function chiudiCentro() { centroAperto = false; }
M.apriCentro = apriCentro;
function aggiornaLuce() { scriv.style.filter = rapide.luce < 100 ? `brightness(${0.35 + rapide.luce / 100 * 0.65})` : ''; }
function azioneDalMenu(id) {
  // Spegnere dalla ricerca porta al pulsante vero: la conferma è una sola, e sta lì.
  if (['spegni', 'riavvia', 'esci'].includes(id)) { apriCentro(); M.avviso('Tieni premuto il pulsante per confermare.'); return; }
  if (id === 'blocca' || id === 'sospendi') chiudiMenu();
  esegui(id); if (menuAperto) disegnaMenu();
}
function esegui(cosa) {
  if (cosa in NOMI) {
    rapide[cosa] = !rapide[cosa]; M.avviso(`${NOMI[cosa]}: ${rapide[cosa] ? 'acceso' : 'spento'}`);
    if (cosa === 'notte') scriv.classList.toggle('notte', rapide.notte);
    mostra(stato === 'musica' ? 'ora' : stato); if (centroAperto) disegnaCentro(); return;
  }
  if (cosa === 'blocca') { chiudiCentro(); blocca(); return; }
  M.avviso({ sospendi: 'Il computer dorme (simulazione).', esci: 'Uscita dalla sessione (simulazione).', riavvia: 'Riavvio (simulazione).', spegni: 'Spegnimento (simulazione).' }[cosa]);
}

// ── Il blocco: una marea che sale e si ritira ───────────────────────
const tenda = document.createElement('div'); tenda.className = 'tenda';
tenda.innerHTML = '<div class="tenda-ora">20:14</div><div class="tenda-data">mercoledì 23 settembre</div><div class="tenda-campo">Tocca per sbloccare</div>';
scriv.append(tenda);
function blocca() { tenda.classList.add("su"); }
M.blocca = blocca;
tenda.addEventListener('pointerdown', e => { e.stopPropagation(); tenda.classList.remove('su'); M.goccia(W / 2, H / 2, 1.2, 6); });

// ── Mostra la scrivania: le finestre scivolano via, e tornano ───────
let scrivaniaLibera = false;
function mostraScrivania() {
  scrivaniaLibera = !scrivaniaLibera;
  for (const f of M.oggetti.filter(o => o.finestra && o.visibile !== false)) {
    f.vx = f.vy = 0; f.vel = {};
    if (scrivaniaLibera) { f.casa = { x: f.x, y: f.y }; f.meta = { x: f.x + f.w / 2 < W / 2 ? -f.w - 60 : W + 60, y: f.y }; }
    else if (f.casa) f.meta = f.casa;
  }
  M.avviso(scrivaniaLibera ? 'Scrivania libera. Di nuovo nell\'angolo per riavere le finestre.' : 'Finestre tornate.');
}
M.mostraScrivania = mostraScrivania;

// ── Gli angoli attivi: una sosta breve, poi agiscono ───────────────
const ANGOLO = 12, SOSTA = 160;
let angolo = null, t0Angolo = 0;
function quale(p) {
  const s = p.x < ANGOLO, d = p.x > W - ANGOLO, a = p.y < ANGOLO, b = p.y > H - ANGOLO;
  return s && b ? 'basso-sx' : d && a ? 'alto-dx' : d && b ? 'basso-dx' : s && a ? 'alto-sx' : null;
}
function azioneAngolo(a) {
  if (a === 'basso-sx') return menuAperto ? null : () => apriMenu('');
  const centroQui = lato === 'alto' ? 'alto-dx' : 'basso-dx';
  if (a === centroQui) return centroAperto ? null : apriCentro;
  if (a === 'alto-dx' || a === 'basso-dx') return mostraScrivania;
  return () => M.avviso('Angolo in alto a sinistra: qui andrà la panoramica delle finestre.');
}
const dentroDi = (o, p, m) => p.x > o.x - m && p.x < o.x + o.w + m && p.y > o.y - m && p.y < o.y + o.h + m;
M.suMovimento = (p) => {
  const q = quale(p);
  if (q !== angolo) {
    angolo = q; t0Angolo = performance.now();
    // Il periscopio spunta subito: se te ne vai prima della sosta, si rituffa.
    if (q && azioneAngolo(q)) bollaIn(q); else if (!menuAperto && !centroAperto) bolla.scalaObj = 0;
  }
  // Si chiudono quando ci sei entrato e poi te ne vai lontano; una ricerca scritta tiene aperto.
  if (menuAperto) { if (dentroDi(menu, p, 0)) menuEntrato = true; else if (menuEntrato && !dentroDi(menu, p, 90) && !campo.value) chiudiMenu(); }
  if (centroAperto) { if (dentroDi(centro, p, 0)) centroEntrato = true; else if (centroEntrato && !dentroDi(centro, p, 90)) chiudiCentro(); }
  // I bordi vivi, fuori dagli angoli e quando nessuno dei due pannelli è aperto.
  const vic = { basso: p.y > H - 14, sinistra: p.x < 14, destra: p.x > W - 14 };
  for (const [l, nome] of Object.entries(assegnati)) {
    const o = og[nome], a = geometria(nome, l, true);
    if (vic[l] && !q && !o.aperto && !menuAperto && !centroAperto) { o.aperto = true; M.goccia(l === 'sinistra' ? 6 : l === 'destra' ? W - 6 : p.x, l === 'basso' ? H - 6 : p.y, 1, 5); }
    else if (o.aperto && !vic[l] && !dentroDi(a, p, 30) && !(spostando && spostando.nome === nome)) o.aperto = false;
  }
  const suoBordo = lato === 'alto' ? p.y < 14 : p.y > H - 14;
  if (suoBordo && !q && stato === 'ora' && Math.abs(p.x - isolaX) < 320) mostra('stato');
  else if (stato === 'stato' && (lato === 'alto' ? p.y > 160 : p.y < H - 160)) mostra('ora');
};
M.suClicSfondo = () => { chiudiMenu(); chiudiCentro(); if (stato === 'stato') mostra('ora'); };
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') { chiudiMenu(); chiudiCentro(); return; }
  if (e.ctrlKey || e.metaKey || e.altKey || e.key.length !== 1 || /input|textarea|button/i.test(document.activeElement.tagName)) return;
  const r = document.getElementById('cornice').getBoundingClientRect(); if (r.bottom < 0 || r.top > innerHeight) return;
  // Scrivi e basta: una lettera, ovunque, e il menù emerge con quella lettera.
  e.preventDefault(); apriMenu(e.key);
});
M.apriBordo = (l) => { for (const [k, n] of Object.entries(assegnati)) og[n].aperto = k === l; };

function molla(o, meta, rig, smorz) {
  for (const k of Object.keys(meta)) { o.vel[k] = (o.vel[k] || 0) * smorz + (meta[k] - o[k]) * rig; o[k] += o.vel[k]; }
}
M.suPasso = () => {
  const ora = performance.now();
  if (angolo && t0Angolo && ora - t0Angolo > SOSTA) { const f = azioneAngolo(angolo); t0Angolo = 0; f && f(); }
  // L'Isola
  for (const k of ['w', 'h']) { const f = (ob[k] - isola[k]) * 0.16; v[k] = v[k] * 0.72 + f; isola[k] += v[k]; }
  if (!trascinaIsola) {
    isolaX += (Math.min(W - isola.w / 2 - 12, Math.max(isola.w / 2 + 12, isolaX)) - isolaX) * 0.2;
    const ty = lato === 'alto' ? 12 : H - 12 - isola.h; isola.vy2 = (isola.vy2 || 0) * 0.7 + (ty - isola.y) * 0.12; isola.y += isola.vy2;
  }
  isola.x = isolaX - isola.w / 2;
  // I bordi
  for (const [l, nome] of Object.entries(assegnati)) {
    const o = og[nome]; if (spostando && spostando.nome === nome) continue;
    const t = geometria(nome, l, o.aperto && !menuAperto && !centroAperto);
    o.vx2 = (o.vx2 || 0) * 0.7 + (t.x - o.x) * 0.12; o.vy2 = (o.vy2 || 0) * 0.7 + (t.y - o.y) * 0.12;
    o.x += o.vx2; o.y += o.vy2; o.w += (t.w - o.w) * 0.18; o.h += (t.h - o.h) * 0.18;
    o.visibile = o.aperto || Math.abs(t.x - o.x) + Math.abs(t.y - o.y) > 2;
  }
  // Il sottomarino: lo scafo sale solo dopo il periscopio, con la spinta che lo fa oscillare.
  const gm = geomMenu(menuAperto && ora - fase > 170);
  molla(menu, { x: gm.x, w: gm.w, h: gm.h }, 0.14, 0.7);
  molla(menu, { y: gm.y }, 0.075, 0.8);
  if (!menuAperto && menu.y > H + 10) menu.visibile = false;
  menu.el.classList.toggle('emerso', menuAperto && Math.abs(menu.y - gm.y) < 40);
  // Il centro
  const gc = geomCentro(centroAperto);
  molla(centro, { y: gc.y }, 0.09, 0.76); centro.x = gc.x;
  if (!centroAperto && (centro.y < -CH || centro.y > H + 10)) centro.visibile = false;
  centro.el.classList.toggle('emerso', centroAperto && Math.abs(centro.y - gc.y) < 40);
  // Il periscopio si rituffa quando lo scafo è su.
  if ((menuAperto && ora - fase > 420) || (centroAperto && Math.abs(centro.y - gc.y) < 30)) bolla.scalaObj = 0;
  // Le finestre che scivolano via e tornano.
  for (const f of M.oggetti) if (f.finestra && f.meta) {
    f.vel = f.vel || {}; molla(f, f.meta, 0.08, 0.76);
    if (Object.keys(f.meta).every(k => Math.abs(f.meta[k] - f[k]) < 0.5 && Math.abs(f.vel[k] || 0) < .1)) { Object.assign(f, f.meta); f.meta = null; f.vel = {}; }
  }
};

const cart = document.createElement('div'); cart.className = 'cartello'; scriv.append(cart);
let tc; M.avviso = (t) => { cart.textContent = t; cart.hidden = false; clearTimeout(tc); tc = setTimeout(() => cart.hidden = true, 2600); }; cart.hidden = true;
})();

// ── I tasti: le prove cliccabili, e Super tenuto premuto ────────────
(() => {
const M = window.MINERVA, W = M.W, H = M.H, scriv = document.getElementById('scrivania');
let attiva = null;
scriv.addEventListener('pointerdown', e => { const el = e.target.closest('.ogg.fin'); if (el) attiva = M.oggetti.find(o => o.el === el); }, true);
const ultima = () => (attiva && attiva.visibile !== false ? attiva : null) || M.oggetti.filter(o => o.finestra && o.visibile !== false).sort((a, b) => b.z - a.z)[0];
// Aggancio con la molla: la finestra ci arriva, supera di un soffio, e si posa.
function aggancia(dove) {
  const f = ultima(); if (!f) return;
  f.vx = f.vy = 0; f.vel = {};
  if (!f.libera) f.libera = { x: f.x, y: f.y, w: f.w, h: f.h };
  const m = 10;
  f.meta = { sinistra: { x: m, y: m, w: W / 2 - m * 1.5, h: H - 2 * m }, destra: { x: W / 2 + m / 2, y: m, w: W / 2 - m * 1.5, h: H - 2 * m },
    su: { x: m, y: m, w: W - 2 * m, h: H - 2 * m }, giu: f.libera }[dove];
  if (dove === 'giu') f.libera = null;
}
const chip = document.createElement('div'); chip.className = 'suggerimenti';
const S = (x, y, t, k) => `<div class="sugg" style="left:${x}px;top:${y}px"><kbd>${k}</kbd>${t}</div>`;
chip.innerHTML = S(24, H - 70, 'Menù', 'Super') + S(W - 250, 24, 'Centro di controllo', 'Super A') + S(24, 24, 'Panoramica', 'Super Tab')
  + S(W - 250, H - 70, 'Scrivania', 'Super D') + S(W / 2 - 150, H / 2 - 60, 'Metà sinistra · metà destra', 'Super ← →')
  + S(W / 2 - 150, H / 2, 'Ingrandisci · torna com\'era', 'Super ↑ ↓') + S(W / 2 - 150, H / 2 + 60, 'Stanza 1, 2, 3…', 'Super 1 2 3');
scriv.append(chip);
function mostraTasti() { chip.classList.add('su'); clearTimeout(chip.t); chip.t = setTimeout(() => chip.classList.remove('su'), 2600); }
const azioni = {
  menu: () => M.apriMenu(), centro: () => M.apriCentro(), scrivania: () => M.mostraScrivania(),
  sinistra: () => aggancia('sinistra'), destra: () => aggancia('destra'), su: () => aggancia('su'), giu: () => aggancia('giu'),
  tieni: mostraTasti, blocca: () => M.blocca(), cerca: () => M.cercaNelMenu('navigare il web'),
  panoramica: () => M.avviso('La panoramica è la prossima simulazione.'),
};
document.querySelectorAll('[data-prova]').forEach(b => b.addEventListener('click', () => {
  document.getElementById('cornice').scrollIntoView({ block: 'center', behavior: M.riduci ? 'auto' : 'smooth' });
  setTimeout(azioni[b.dataset.prova], 250);
}));
})();

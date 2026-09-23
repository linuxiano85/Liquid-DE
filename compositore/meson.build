# minerva-wayland — il compositore di Minerva.
#
# Meson e non CMake, al contrario del plugin: è quello che usano wlroots e
# tutti i compositori costruiti su di lei, e `wayland-scanner` ha già un
# generatore meson pronto. Andare controcorrente qui vorrebbe dire scrivere a
# mano la generazione dei protocolli, che è la parte più noiosa e più facile
# da sbagliare in silenzio.
project('minerva-wayland', 'c',
  version: '0.1.0',
  license: 'GPL-3.0-or-later',
  default_options: [
    'c_std=c11',
    'warning_level=2',
    # Un avviso in un compositore è un difetto che si vedrà a schermo fra tre
    # settimane, quando nessuno si ricorderà di questa riga.
    'werror=true',
  ])

cc = meson.get_compiler('c')

# ── La riga senza la quale wlroots non si lascia includere ──────────────
#
# Ogni suo header comincia con `#error "Add -DWLR_USE_UNSTABLE"`. Non è un
# avvertimento sulla qualità: è wlroots che dichiara di non promettere
# compatibilità fra una versione e l'altra, e chiede di dirlo per iscritto.
# Il fork è incluso nei sorgenti: Meson ricompila le dipendenze interessate
# quando cambiano gli header, senza dipendere dall'ABI di wlroots di sistema.
add_project_arguments('-DWLR_USE_UNSTABLE', language: 'c')

# ── Le dipendenze, e perché queste ────────────────────────────────────────
#
# wlroots dà l'hardware E i protocolli: xdg-shell, seat, appunti, XWayland,
# e `wlr-layer-shell`, che è SUO ed è quello su cui la shell di Minerva è già
# costruita (48 usi di `WlrLayershell`). È il motivo per cui si è scelta lei e
# non aquamarine, che dà solo l'hardware.
# ── Il NOSTRO wlroots, fermo a una revisione ─────────────────────────────
#
# Dal 20 settembre 2026 il compositore non si lega più alla wlroots di
# sistema né a SceneFX: compila il fork in `subprojects/wlroots` (base
# 0.20.2, provenienza e SHA in `subprojects/wlroots/MINERVA.md`) come
# libreria STATICA. Gli effetti — sfocatura, angoli, il buco dell'anello —
# stanno dentro la scena del fork (`wlr_minerva_*` in `wlr_scene.h`), e con
# loro i protocolli per i giochi (`fifo-v1`, `commit-timing-v1`,
# presentation-time). Questa dipendenza non deve MAI risolversi sulla
# libreria di sistema: `costruisci.sh` lo verifica con `ldd`.
wlroots_project = subproject('wlroots', default_options: [
  'default_library=static', 'examples=false', 'werror=true'])
wlroots = wlroots_project.get_variable('wlroots')
gles2 = dependency('glesv2')
systemd = dependency('libsystemd')
wayland_server = dependency('wayland-server')
# `wayland-client` non serve al compositore: serve a `minerva-cattura`, il
# programmino che legge lo schermo per «trasmetti lo schermo». È un CLIENT del
# nostro stesso compositore — la stessa strada di `grim`.
wayland_client = dependency('wayland-client')
wayland_protos = dependency('wayland-protocols', version: '>=1.41')
xkbcommon = dependency('xkbcommon')
pixman = dependency('pixman-1')

# ── xcb: non lo chiamiamo, ma i suoi header ce li portiamo dentro ────────
#
# `wlr/xwayland.h` include `xcb/xcb.h`, `xcb/xcb_icccm.h` e `xcb/xcb_ewmh.h`,
# e da lì vengono le costanti che usiamo (`XCB_STACK_MODE_ABOVE`) e i campi
# che leggiamo (`size_hints`). Dichiararlo qui non è pedanteria: è l'unico
# modo perché la mancanza si veda come «manca xcb» invece che come una
# cascata di errori dentro un header di wlroots.
# ── libinput: le manopole di touchpad e mouse ───────────────────────────
#
# wlroots dà la maniglia (`wlr_libinput_get_device_handle`), ma le manopole —
# scorrimento naturale, tocco per cliccare, velocità — sono di libinput, e per
# chiamarle bisogna dichiararla. È la stessa libreria che wlroots usa già
# sotto: non è una dipendenza nuova per la macchina, è una che smettiamo di
# usare di seconda mano.
libinput = dependency('libinput')

xcb = dependency('xcb')
xcb_icccm = dependency('xcb-icccm')
xcb_ewmh = dependency('xcb-ewmh')

# ── cairo e pango: la barra del titolo ──────────────────────────────────
#
# Il compositore disegna la barra del titolo da sé (`src/barra.c`), e per
# scriverci dentro il titolo serve un motore di testo vero: righe, ellissi,
# caratteri che non sono lettere latine. Sono le stesse due librerie che usa
# già il plugin — quindi non è una dipendenza nuova per il progetto, è la
# stessa spostata dove ora vive il disegno.
cairo = dependency('cairo')
pangocairo = dependency('pangocairo')

# ── I protocolli: descritti in XML, tradotti in C ────────────────────────
#
# Un protocollo Wayland non è una libreria: è un file XML che elenca le
# richieste e gli eventi, e `wayland-scanner` lo traduce in C. wlroots
# IMPLEMENTA layer-shell ma non ne installa l'XML — il suo header comincia con
# `#include "wlr-layer-shell-unstable-v1-protocol.h"`, e quel file lo deve
# generare chi lo usa.
#
# ── E perché l'XML sta nel nostro repository ─────────────────────────────
#
# Perché è la ragione per cui esiste questa cartella. Un compositore che si
# rifiuta di compilare finché non installi un pacchetto da un repository
# esterno non è indipendente: è dipendente in un punto in più, e per un file
# di testo di trentamila caratteri che non cambia mai.
#
# La copia in `protocolli/` viene dal pacchetto ufficiale ed è confrontata
# byte per byte da `costruisci.sh` quando `wlr-protocols` è installato: se
# un giorno il protocollo cambiasse, la costruzione lo direbbe invece di far
# finta di niente.
wayland_scanner = find_program('wayland-scanner')

protocolli = []
foreach nome : ['wlr-layer-shell-unstable-v1']
  protocolli += custom_target(nome + '-protocol.h',
    input: files('protocolli' / nome + '.xml'),
    output: nome + '-protocol.h',
    command: [wayland_scanner, 'server-header', '@INPUT@', '@OUTPUT@'])
endforeach

# ── E lo stesso protocollo, dal lato di chi CHIEDE ───────────────────────
#
# `wlr-screencopy` il compositore lo implementa già (`main.c:7351`, è quello
# con cui `grim` fa le fotografie). Qui ne serve l'altra metà: le funzioni che
# un client usa per chiederlo. Sono due file generati dallo stesso XML —
# l'intestazione e il codice — e `private-code` è la parte che, dimenticata,
# fa fallire il collegamento con dei nomi che sembrano di wlroots e non lo
# sono.
screencopy_xml = files('protocolli/wlr-screencopy-unstable-v1.xml')
screencopy_h = custom_target('wlr-screencopy-client-protocol.h',
  input: screencopy_xml,
  output: 'wlr-screencopy-unstable-v1-client-protocol.h',
  command: [wayland_scanner, 'client-header', '@INPUT@', '@OUTPUT@'])
screencopy_c = custom_target('wlr-screencopy-protocol.c',
  input: screencopy_xml,
  output: 'wlr-screencopy-unstable-v1-protocol.c',
  command: [wayland_scanner, 'private-code', '@INPUT@', '@OUTPUT@'])

# ── minerva-cattura ──────────────────────────────────────────────────────
#
# Legge lo schermo e lo scrive grezzo sull'uscita standard: è la prima metà di
# «trasmetti lo schermo». Non comprime e non parla in rete — quello lo fa il
# demone — e sta in un processo suo perché la compressione è lavoro a raffica,
# e ogni millisecondo speso dentro il compositore è un millisecondo in cui la
# scrivania non disegna.
executable('minerva-cattura',
  files('src/cattura.c'), screencopy_h, screencopy_c,
  dependencies: [wayland_client, cc.find_library('rt', required: false)],
  install: true)

# ── minerva-pty ──────────────────────────────────────────────────────────
#
# Lo pseudo-terminale del Terminale di Minerva: apre il PTY, ci mette la
# shell, fa da tramite. Sta qui e non in `minervad/` perché è C e questo è
# l'unico posto del progetto che compila C — ma non è parte del compositore:
# è un programmino a sé, come `minerva-cattura`. Il perché sta in cima a
# `src/minerva-pty.c`.
executable('minerva-pty',
  files('src/minerva-pty.c'),
  dependencies: [cc.find_library('util', required: false)],
  install: true)

# ── Le prove del lettore di schermi ─────────────────────────────────────
#
# Un eseguibile a parte, senza wlroots: `schermi.c` legge testo e riempie una
# struttura, e quella parte si può provare senza uno schermo. È deliberato —
# la configurazione degli schermi è l'unico pezzo del compositore in cui un
# difetto si porta via il modo di ripararlo, quindi è anche l'unico che vale
# la pena separare apposta per poterlo provare.
prova_schermi = executable('prova-schermi',
  files('src/prova-schermi.c', 'src/schermi.c'),
  install: false)
test('schermi', prova_schermi)

# ── E le prove dell'aggancio ai bordi ───────────────────────────────────
#
# Stessa idea, stessa ragione: `src/aggancio.c` è conto puro — non tocca
# wlroots — e il suo difetto si vedrebbe come una finestra nel posto sbagliato,
# cioè tardi. Provarlo con dei numeri costa un eseguibile da niente.
prova_aggancio = executable('prova-aggancio',
  files('src/prova-aggancio.c', 'src/aggancio.c'),
  install: false)
test('aggancio', prova_aggancio)

# ── E le prove del ritaglio della lente ─────────────────────────────────
#
# Stessa idea, con una ragione in più che vale solo qui: la lente **non si può
# fotografare**. Agisce sullo scanout, e `grim` cattura la scena — due catture
# con lente spenta e accesa sono identiche al pixel. Dove non si può guardare,
# provare i numeri non è un ripiego: è l'unica strada che c'è.
prova_lente = executable('prova-lente',
  files('src/prova-lente.c', 'src/lente.c'),
  dependencies: [cc.find_library('m', required: false)],
  install: false)
test('lente', prova_lente)

# ── E le prove dell'elastico ────────────────────────────────────────────
#
# Con una ragione ancora diversa dalle due qui sopra: l'elastico è un
# comportamento NEL TEMPO, e una fotografia è un istante. I due modi in cui si
# rompe — «la finestra scatta e basta» e «la finestra ondeggia per sempre» —
# danno la stessa fotografia di uno che funziona, se la si scatta nel momento
# giusto. E il caso peggiore, la molla che guadagna energia con un passo
# lungo, si vede una volta su venti: cioè mai, quando lo cerchi.
prova_molla = executable('prova-molla',
  files('src/prova-molla.c', 'src/molla.c'),
  dependencies: [cc.find_library('m', required: false)],
  install: false)
test('molla', prova_molla)

prova_ondulazione = executable('prova-ondulazione',
  files('src/prova-ondulazione.c', 'src/ondulazione.c', 'src/molla.c'),
  dependencies: [cc.find_library('m')], install: false)
test('ondulazione', prova_ondulazione)

prova_canale = executable('prova-canale', files('src/prova-canale.c'),
  dependencies: [wayland_server], install: false)
test('canale', prova_canale)

prova_puntatore = executable('prova-puntatore', files('src/prova-puntatore.c'),
  dependencies: [wlroots, wayland_server, pixman, cc.find_library('m')], install: false)
test('puntatore', prova_puntatore)

# Richiede un contesto GPU; esecuzione esplicita, non nella suite senza schermo.
executable('prova-wobbly-gpu',
  files('src/prova-wobbly-gpu.c', 'src/wobbly.c', 'src/ondulazione.c'),
  dependencies: [wlroots, wayland_server, pixman, gles2, cc.find_library('m')],
  install: false)

executable('minerva-wayland',
  files('src/main.c', 'src/barra.c', 'src/anello.c', 'src/schermi.c',
    'src/canale.c', 'src/aggancio.c', 'src/lente.c', 'src/molla.c',
    'src/ondulazione.c', 'src/wobbly.c', 'src/sonno.c', 'src/puntatore.c',
    'src/energia.c'),
  protocolli,
  dependencies: [wlroots, wayland_server, xkbcommon, pixman, cairo,
    pangocairo, libinput, xcb, xcb_icccm, xcb_ewmh, gles2, systemd,
    cc.find_library('m')],
  install: true)

# Solo con un bus D-Bus privato; il banco rifiuta il bus di sistema reale.
prova_sonno = executable('prova-sonno', files('src/prova-sonno.c', 'src/sonno.c'),
  dependencies: [systemd, wayland_server, wlroots], install: false)
prova_energia = executable('prova-energia', files('src/prova-energia.c', 'src/energia.c'),
  dependencies: [systemd, wayland_server, wlroots, cc.find_library('m')],
  install: false)

# Le due prove del bus di sistema girano in un bus PRIVATO: `dbus-run-session`
# ne apre uno, e la stessa strada fa da bus «di sistema». `prova-sonno`
# c'era dal 15 settembre e non la lanciava nessun giro — scritta, verde, e
# mai più guardata.
dbus_run_session = find_program('dbus-run-session', required: false)
if dbus_run_session.found()
  foreach nome, prova : {'sonno': prova_sonno, 'energia': prova_energia}
    test(nome, dbus_run_session,
      args: ['--', 'sh', '-c',
        'DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" exec "$0"', prova],
      timeout: 20)
  endforeach
endif

# Richieste Wayland vere contro il fork (client e server in processo, senza
# GPU né sessione): ordine FIFO, timestamp, oggetti distrutti, figli
# sincronizzati. Sette scenari di errore, ognuno con la sua connessione.
timing_headers = []
foreach name : ['fifo', 'commit-timing']
  timing_headers += custom_target(name + '-client',
    input: wayland_protos.get_variable('pkgdatadir') / 'staging' / name / (name + '-v1.xml'),
    output: name + '-v1-client.h',
    command: [wayland_scanner, 'client-header', '@INPUT@', '@OUTPUT@'])
endforeach
prova_presentazione = executable('prova-presentazione',
  files('src/prova-presentazione.c'), timing_headers,
  dependencies: [wlroots, wayland_client, dependency('threads')],
  c_args: ['-Wno-unused-parameter'], install: false)
test('presentazione', prova_presentazione, timeout: 15)
foreach scenario : ['invalid-ns', 'duplicate-timestamp', 'duplicate-fifo',
    'duplicate-timer', 'dead-timer', 'dead-fifo-set', 'dead-fifo-wait']
  test('presentazione-' + scenario, prova_presentazione, args: [scenario], timeout: 15)
endforeach
prova_buffer_size = executable('prova-buffer-size', files('src/prova-buffer-size.c'),
  include_directories: include_directories('subprojects/wlroots/include'), install: false)
test('buffer-size', prova_buffer_size)

# Un client che dichiara danneggiato SOLO quello che cambia: il banco di
# `prova-danno-blur.py`. Nessun programma installato lo fa — alacritty e Qt
# dichiarano tutta la finestra — e senza di lui il danno incrementale del
# blur non si può distinguere da uno sbagliato.
xdg_shell_client = custom_target('xdg-shell-client',
  input: wayland_protos.get_variable('pkgdatadir') / 'stable/xdg-shell/xdg-shell.xml',
  output: 'xdg-shell-client.h',
  command: [wayland_scanner, 'client-header', '@INPUT@', '@OUTPUT@'])
xdg_shell_codice = custom_target('xdg-shell-codice',
  input: wayland_protos.get_variable('pkgdatadir') / 'stable/xdg-shell/xdg-shell.xml',
  output: 'xdg-shell-codice.c',
  command: [wayland_scanner, 'private-code', '@INPUT@', '@OUTPUT@'])
executable('prova-danno-client',
  files('src/prova-danno-client.c'), xdg_shell_client, xdg_shell_codice,
  dependencies: [wayland_client], install: false)

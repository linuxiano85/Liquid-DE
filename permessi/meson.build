# minerva-polkit — l'agente delle password di Minerva.
#
# Un progetto suo e non un secondo eseguibile dentro `compositore/`: non
# c'entra niente col compositore, non condivide una riga di codice con lui, e
# tenerlo separato vuol dire che si può compilare senza wlroots.
project('minerva-polkit', 'c',
  version: '0.1.0',
  license: 'GPL-3.0-or-later',
  default_options: [
    'c_std=c11',
    'warning_level=2',
    # Stessa regola del compositore: un avviso qui è un difetto che si vedrà
    # come una finestra della password che non compare, cioè come «il computer
    # non mi fa più montare le chiavette».
    'werror=true',
  ])

# ── Le dipendenze, e perché nessuna è nuova ─────────────────────────────
#
# `polkit-agent-1` e `polkit-gobject-1` arrivano col pacchetto `polkit`, che
# su questa macchina c'è per forza: lo vuole systemd. Non stiamo aggiungendo
# una dipendenza — stiamo smettendo di usarne una di seconda mano
# (`hyprpolkitagent`), che è un programma intero per fare quello che qui sono
# quattrocento righe.
#
# ── E la parte che NON scriviamo ────────────────────────────────────────
#
# `libpolkit-agent-1` fa da sé tutto il giro con `polkit-agent-helper-1`, il
# programma setuid che parla PAM. È deliberato: la verifica della password è
# il punto in cui un errore diventa un buco di sicurezza, e polkitd non si
# fida di nessun agente proprio per questo. Noi raccogliamo del testo e lo
# consegniamo.
polkit_agent = dependency('polkit-agent-1')
glib = dependency('glib-2.0')
gio = dependency('gio-2.0')
gobject = dependency('gobject-2.0')

executable('minerva-polkit',
  files('src/minerva-polkit.c'),
  dependencies: [polkit_agent, glib, gio, gobject],
  install: true)

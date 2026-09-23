# Liquid DE

Un ambiente desktop per Linux, su Wayland, costruito intorno a un'idea sola:
**fluidità, un desktop elastico, quasi liquido.** Solido ma liquido: il testo
resta fermo e nitido, si muove la forma.

Il compositore, il demone, l'interfaccia, la schermata di accesso e le app di
sistema sono scritti qui.

Creatore: **linuxiano85**.

---

## I tre pezzi

| Cartella | Cos'è | Linguaggio |
|---|---|---|
| `compositore/` | `minerva-wayland`, il compositore, su una copia privata di wlroots 0.20.2 con gli effetti nostri | C, 17.000 righe |
| `minervad/` | il demone: stato del sistema, impostazioni, file, rete, audio, Bluetooth, accesso | Dart, 36.000 righe |
| `minerva-shell/` | tutto quello che si vede: la scrivania, le app, l'accesso, il blocco | QML su [Quickshell](https://quickshell.org/), 82.000 righe |

Si parlano attraverso due canali dichiarati, mai per scorciatoie:

- **shell ↔ demone**: un socket Unix in `$XDG_RUNTIME_DIR`, JSON, un
  messaggio per riga. Ogni azione esistente è in [`EVENTS.md`](EVENTS.md), e
  una prova controlla che l'elenco sia vero.
- **shell ↔ compositore**: il canale di testo del compositore, attraverso un
  modulo solo (`minerva-shell/core/Compositore.qml`).

La regola dei confini è in [`MODULI.md`](MODULI.md).

Il piano di lavoro è in [`PIANO.md`](PIANO.md); il disegno di riferimento
(le simulazioni da cui nasce la scrivania) è in `disegno/`.

---

## Provare senza rischiare la sessione

Tutto si prova **dentro una sessione annidata**, in una finestra o senza
schermo, senza toccare quella in cui si lavora:

```bash
./compositore/prova-annidata.sh
```

Le prove:

```bash
cd compositore && meson test -C build-native   # il compositore
cd minervad && dart test                       # il demone
./scripts/prove.sh                             # tutto, finestre comprese
```

---

## Costruire e installare

```bash
./compositore/costruisci.sh        # il compositore
./scripts/minerva-compila          # il demone
./scripts/install-minerva.sh       # dipendenze, PAM, polkit, voce al login
```

Cosa serve e perché: [`DEPENDENCIES.md`](DEPENDENCIES.md).

---

## Licenza

GPL-3.0: vedi [`LICENSE`](LICENSE). La copia di wlroots in
`compositore/subprojects/wlroots` resta sotto la sua licenza MIT.

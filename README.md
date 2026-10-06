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
  messaggio per riga, con una parola d'ordine che il demone scrive per sé.
- **shell ↔ compositore**: il canale di testo del compositore, attraverso un
  modulo solo (`minerva-shell/core/Compositore.qml`).


---

## Le prove

Questo repository contiene solo quello che serve a costruire e installare
Liquid DE. Le prove — più di 1500 sul demone, le prove del compositore in C e
nella sessione annidata, quelle della shell — stanno in un repository a
parte, **Liquid_test**, da tenere accanto a questa cartella: il suo
`collega.sh` gli dà la stessa forma del progetto, e il `meson.build` del
compositore costruisce le prove in C solo se lo trova.

---

## Costruire e installare

Su Arch Linux e derivate, apri una sessione grafica e avvia l'installer guidato:

```bash
./install.sh
```

Mostra le dipendenze mancanti prima di installarle, registra l'avanzamento e
alla fine propone i gestori di accessi installati. Quello attuale resta
selezionato: il cambio avviene solo su scelta esplicita e vale dal riavvio.
Se Qt o Quickshell mancano, il lanciatore prepara prima i componenti grafici.
I registri si trovano in `~/.local/state/liquid-de/installer/`: `launch-*.log`
contiene l'avvio della finestra e i passaggi della guida; il registro con data
e ora contiene tutti i comandi dell'installazione.

Per l'installazione da terminale rimane disponibile:

```bash
./compositore/costruisci.sh        # il compositore
./scripts/minerva-compila          # il demone
./scripts/install-minerva.sh       # dipendenze, PAM, polkit, voce al login
```

---

## Licenza

GPL-3.0: vedi [`LICENSE`](LICENSE). La copia di wlroots in
`compositore/subprojects/wlroots` resta sotto la sua licenza MIT.

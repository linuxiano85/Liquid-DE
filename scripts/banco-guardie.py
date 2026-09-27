#!/usr/bin/env python3
"""Il banco delle guardie: le prove che sorvegliano il codice, messe alla prova.

    scripts/banco-guardie.py            tutti i casi
    scripts/banco-guardie.py hyprctl    solo quelli che nominano «hyprctl»

── Perché esiste ──────────────────────────────────────────────────────────

Una guardia scritta male è peggio di nessuna guardia: dice verde mentre non
guarda niente. Il 27 settembre 2026 le guardie sono state messe alla prova
così, e ne sono uscite tre famiglie di difetti che nessun verde rivelava: la
barra di scorrimento controllata file per file invece che superficie per
superficie, `hyprctl` sorvegliato nel Dart e nel QML ma non negli script, e
sette guardie su otto che si facevano ingannare da un commento.

── Come funziona ──────────────────────────────────────────────────────────

Si fa una COPIA del progetto in una cartella temporanea (il progetto vero non
si tocca mai), e per ogni caso:

  1. DIFETTI INIETTATI — si mette nella copia proprio il difetto che una
     guardia dice di prendere: la guardia deve diventare ROSSA;
  2. COMMENTI — la riga che una guardia pretende diventa un commento con lo
     stesso testo: la guardia deve diventare ROSSA, o si fida di un commento
     invece che del codice.

Chi scrive una guardia nuova aggiunge qui il suo difetto: è il «vista rossa
prima» del progetto, ma che resta e si può rifare.
"""
import pathlib
import re
import subprocess
import sys
import tempfile

RADICE = pathlib.Path(__file__).resolve().parent.parent

# (nome, file, come, testo, prova)
#   come: "fine" in fondo al file; "in_fondo" prima dell'ultima graffa;
#         ("sostituisci", vecchio); ("prima", ancora).
MUTANTI = [
    ("convivenza: cartella di Minerva con la graffa",
     "scripts/minerva-risveglia", "fine",
     '\nD="${XDG_CONFIG_HOME:-$HOME/.config}/minerva"\n',
     "test/convivenza_test.dart"),
    ("convivenza: programma in ~/.local/bin",
     "minerva-shell/core/Apps.qml", "fine",
     '\n// finto\nreadonly property string x: "$HOME/.local/bin/minerva-files"\n',
     "test/convivenza_test.dart"),
    ("convivenza: servizio PAM di Minerva",
     "scripts/minerva-blocca", "fine", "\n# /etc/pam.d/minerva\ncat /etc/pam.d/minerva\n",
     "test/convivenza_test.dart"),
    ("disegno senza GPU: layer.enabled in un'app",
     "minerva-shell/files/Pane.qml", ("prima", "    Component.onCompleted"),
     "    layer.enabled: true\n", "test/disegno_senza_gpu_test.dart"),
    ("disegno senza GPU: ShaderEffect in un'app",
     "minerva-shell/editor/Editor.qml", ("prima", "    Component.onCompleted"),
     "    ShaderEffect { }\n", "test/disegno_senza_gpu_test.dart"),
    ("scorrimento: ListView senza barra",
     "minerva-shell/files/Transfers.qml", ("prima", "    Component.onCompleted"),
     "    ListView {\n        model: 3\n    }\n", "test/scorrimento_test.dart"),
    ("scorrimento: ListView senza barra nel terminale (cartella nuova)",
     "minerva-shell/terminale/Terminale.qml", ("prima", "    Component.onCompleted"),
     "    ListView {\n        model: 3\n    }\n", "test/scorrimento_test.dart"),
    ("valori di fabbrica: la shell legge una chiave inventata",
     "minerva-shell/dock/Dock.qml", ("prima", "    Component.onCompleted"),
     '    readonly property bool _finto: Core.Ipc.get("dock.chiaveInventata", false)\n',
     "test/valori_di_fabbrica_test.dart"),
    ("valori di fabbrica: la shell scrive una chiave inventata",
     "minerva-shell/dock/Dock.qml", ("prima", "    Component.onCompleted"),
     '    function _finta() { Core.Ipc.setSetting("dock.altraInventata", 1); }\n',
     "test/valori_di_fabbrica_test.dart"),
    ("finestre: le Impostazioni rimettono follow_mouse",
     "minerva-shell/settings/sections/Input.qml", ("prima", "    function apply() {"),
     '    readonly property string _f: "follow_mouse = 1"\n', "test/finestre_test.dart"),
    ("finestre: le Impostazioni scrivono in ~/.config/hypr",
     "minerva-shell/settings/sections/Input.qml", ("prima", "    function apply() {"),
     '    readonly property string _d: "$HOME/.config/hypr/x.conf"\n', "test/finestre_test.dart"),
    ("porta: un servizio chiama hyprctl",
     "minerva-shell/core/Meteo.qml", "in_fondo",
     '    function _h() { Quickshell.execDetached(["hyprctl", "dispatch", "exit"]); }\n',
     "test/porta_compositore_test.dart"),
    ("porta: un file fuori dalla porta importa Quickshell.Hyprland",
     "minerva-shell/dock/Dock.qml", ("prima", "import QtQuick\n"),
     "import Quickshell.Hyprland\n", "test/porta_compositore_test.dart"),
    ("bus: la shell manda un'azione che il demone non conosce",
     "minerva-shell/core/Ipc.qml", "in_fondo",
     '    function _finta() { return send({ "action": "azione_che_non_esiste" }); }\n',
     "test/bus_coerenza_test.dart"),
    ("iscrizioni: la shell ascolta un annuncio che il compositore non fa",
     "minerva-shell/core/Compositore.qml", ("sostituisci", 'canale.write("ascolta scrivania '),
     'canale.write("ascolta annuncioinventato scrivania ', "test/iscrizioni_compositore_test.dart"),
    ("sezioni: una voce della colonna senza pagina",
     "minerva-shell/settings/System.qml",
     ("sostituisci", '{ "id": "animazioni",'),
     '{ "id": "sezioneFinta", "icon": "x", "it": "Finta", "en": "Fake" },\n        { "id": "animazioni",',
     "test/impostazioni_sezioni_test.dart"),
    ("moduli fragili: un file di core importa QtMultimedia",
     "minerva-shell/core/Meteo.qml", ("prima", "import QtQuick\n"),
     "import QtMultimedia\n", "test/moduli_fragili_test.dart"),
    ("app pronte: un punto d'ingresso torna a uscire con Qt.quit()",
     "minerva-shell/app.qml", ("sostituisci", "onRequestClose: prontaEditor.chiudi()"),
     "onRequestClose: Qt.quit()", "test/preload_avvio_test.dart"),
    ("hyprctl: lo script della schermata torna a chiedere a Hyprland",
     "scripts/minerva-schermata", "fine",
     '\nREGIONE=$(hyprctl activewindow -j 2>/dev/null)\n', "test/porta_compositore_test.dart"),
    ("hyprctl: un avviso torna a hyprctl notify",
     "scripts/minerva-risveglia", "fine",
     '\nhyprctl notify 1 2500 "rgb(f0407f)" "x" >/dev/null 2>&1\n', "test/porta_compositore_test.dart"),
    ("hyprctl: uno script Python chiede i dispositivi",
     "scripts/prova-tasti.py", "fine",
     '\nimport subprocess\nsubprocess.run(["hyprctl", "-j", "devices"])\n', "test/porta_compositore_test.dart"),
    ("hyprctl: una sola chiamata nel QML",
     "minerva-shell/core/Meteo.qml", "in_fondo",
     '    function _h() { Quickshell.execDetached(["hyprctl", "dispatch", "exit"]); }\n',
     "test/porta_compositore_test.dart"),
]

# (testo che la guardia pretende, prova che lo pretende)
CASI = [
    ('readonly property string nome: "liquid-de"', "test/canale_segreto_test.dart"),
    ("default=wlr", "test/due_sessioni_test.dart"),
    ("XCURSOR_THEME", "test/due_sessioni_test.dart"),
    ("Core.TenutaPronta", "test/preload_avvio_test.dart"),
    ("scripts/minerva-ospite", "test/preload_avvio_test.dart"),
    ("Core.Notifications.apriPerId(", "test/notifiche_interagibili_test.dart"),
    ('"fullscreen": c.schermoIntero === true', "test/finestre_test.dart"),
    ("string:x-minerva-file:", "test/notifiche_interagibili_test.dart"),
]

SEGNO = {".qml": "// ", ".dart": "// ", ".js": "// ", ".c": "// ", ".h": "// "}
CARTELLE = ["minerva-shell", "scripts", "config", "minervad/lib",
            "compositore/src", "desktop"]


def applica(testo, come, pezzo):
    if come == "fine":
        return testo + pezzo
    if come == "in_fondo":
        i = testo.rstrip().rfind("}")
        return testo[:i] + pezzo + testo[i:]
    tipo, ancora = come
    assert ancora in testo, f"ancora «{ancora[:40]}» non trovata"
    if tipo == "sostituisci":
        return testo.replace(ancora, pezzo, 1)
    return testo.replace(ancora, pezzo + ancora, 1)


def commenta(riga, estensione):
    rientro = re.match(r"\s*", riga).group(0)
    return rientro + SEGNO.get(estensione, "# ") + riga.lstrip()


def gira(copia, prova):
    r = subprocess.run(["nice", "-n", "15", "dart", "test", prova],
                       cwd=copia / "minervad", capture_output=True, text=True,
                       timeout=600)
    return r.returncode


def difetti(copia, filtro):
    storte = 0
    print("── difetti iniettati")
    for nome, rel, come, pezzo, prova in MUTANTI:
        if filtro and filtro not in nome:
            continue
        f = copia / rel
        orig = f.read_text()
        try:
            f.write_text(applica(orig, come, pezzo))
        except AssertionError as e:
            print(f"  ??  {nome}: non si applica ({e})")
            storte += 1
            continue
        try:
            rossa = gira(copia, prova) != 0
        finally:
            f.write_text(orig)
        print(f"  {'ok' if rossa else 'NO'}  {nome}"
              + ("" if rossa else "  → la guardia non l'ha preso"), flush=True)
        storte += 0 if rossa else 1
    return storte


def commenti(copia, filtro):
    storte = 0
    print("── commenti")
    for testo, prova in CASI:
        if filtro and filtro not in testo and filtro not in prova:
            continue
        toccati = {}
        for c in CARTELLE:
            for f in (copia / c).rglob("*"):
                if not f.is_file() or f.suffix in (".png", ".svg", ".ttf", ".json"):
                    continue
                try:
                    righe = f.read_text().split("\n")
                except Exception:
                    continue
                nuove, cambiato = [], False
                for r in righe:
                    if testo in r and not r.lstrip().startswith(("//", "#", "*")):
                        nuove.append(commenta(r, f.suffix))
                        cambiato = True
                    else:
                        nuove.append(r)
                if cambiato:
                    toccati[f] = "\n".join(righe)
                    f.write_text("\n".join(nuove))
        if not toccati:
            print(f"  ??  «{testo}» non si trova più nel codice")
            storte += 1
            continue
        try:
            rossa = gira(copia, prova) != 0
        finally:
            for f, orig in toccati.items():
                f.write_text(orig)
        print(f"  {'ok' if rossa else 'NO'}  «{testo}» come commento"
              + ("" if rossa else "  → la guardia si fida del commento"), flush=True)
        storte += 0 if rossa else 1
    return storte


def main():
    filtro = sys.argv[1] if len(sys.argv) > 1 else ""
    with tempfile.TemporaryDirectory(prefix="liquid-de-banco-") as tmp:
        copia = pathlib.Path(tmp) / "copia"
        subprocess.run(["rsync", "-a", "--exclude=.git", "--exclude=compositore/build*",
                        "--exclude=compositore/subprojects", "--exclude=*.png",
                        "--exclude=disegno", f"{RADICE}/", f"{copia}/"], check=True)
        storte = difetti(copia, filtro) + commenti(copia, filtro)
    print("\ntutte le guardie hanno visto il loro difetto" if storte == 0
          else f"\n{storte} da guardare")
    return 1 if storte else 0


if __name__ == "__main__":
    sys.exit(main())

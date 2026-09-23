//@ pragma AppId minerva-viewer
// viewer.qml — Minerva Anteprima, come processo a sé.
//
// Il quarto punto d'ingresso di Minerva, dopo il gestore file, le Impostazioni
// e Attività, per le stesse ragioni scritte in cima a `filemanager.qml`: un
// errore qui dentro non deve poter spegnere la barra.
//
// ── Perché esiste questo programma ──────────────────────────────────────────
//
// Fino a ieri un doppio clic su una fotografia dentro Minerva apriva Gwenview:
// una finestra di KDE, con la sua barra degli strumenti, il suo tema e le sue
// librerie. Funzionava — e si vedeva da un chilometro che veniva da un altro
// mondo. Guardare un'immagine è la cosa che si fa più spesso partendo dal
// gestore file, quindi era anche l'uscita più frequente da Minerva.
//
// C'è una seconda ragione, meno ovvia: il pannello delle schermate scatta e
// salva, e poi non c'era un posto dentro Minerva dove GUARDARE quello che
// aveva scattato. Il giro si chiudeva fuori.
//
// Si avvia così, ed è quello che fa lo script `minerva-viewer`:
//
//     MINERVA_VIEWER_PATHS=/home/tizio/Immagini/foto.png \
//         qs -d -n -p .../minerva-shell/viewer.qml
//
// e chi è già aperto si comanda così:
//
//     qs ipc -p .../minerva-shell/viewer.qml call viewer open /tmp/foto.png
import QtQuick
import Quickshell
import Quickshell.Io

import "theme" as Theme
import "core" as Core
import "viewer"

ShellRoot {
    id: app

    // Come gli altri punti d'ingresso: la ricarica automatica chiude le
    // finestre sotto le mani di chi guarda.
    Component.onCompleted: {
        Quickshell.watchFiles = false;
    }

    // ── Quello che si prende dalle impostazioni ──────────────────────────
    //
    // Ripetuto e non condiviso: sono processi diversi e non possono leggersi
    // le proprietà a vicenda. La sorgente però è la stessa — il demone —
    // quindi cambiare tema li ridipinge tutti nello stesso istante.

    Binding {
        target: Core.Strings
        property: "requestedLanguage"
        value: Core.Ipc.get("general.language", "auto")
    }


    // ── Il tema ──────────────────────────────────────────────────────────
    //
    // Un oggetto solo al posto dei blocchi di `Binding` che stavano qui: la
    // tavolozza non legge le impostazioni, e chi fa il legame lo fa in un
    // posto solo per tutti e sei i punti d'ingresso. Vedi `theme/LegaTema.qml`.
    Theme.LegaTema { }






    // ── La finestra ──────────────────────────────────────────────────────

    // ── Chiusa, ma pronta ────────────────────────────────────────────────
    //
    // Spenta di fabbrica: riaprire Anteprima costa 422 ms, tenerla pronta costa
    // 158 MB sempre — è la più cara di tutte, perché le miniature costruite
    // restano costruite. Il conto lo fa chi usa il computer, nelle
    // Impostazioni.
    Core.TenutaPronta {
        id: pronta
        nome: "anteprima"
        laFinestra: finestra
    }

    Viewer {
        id: finestra
        dormiente: pronta.dormiente

        /// I file da guardare, passati nell'ambiente da chi ci lancia, uno per
        /// riga. Nell'ambiente e non sulla riga di comando perché la riga di
        /// comando è di `qs`: `qs -p file.qml foto.png` non passerebbe niente
        /// a noi, proverebbe a leggerlo come un'opzione sua.
        initialPaths: {
            var raw = Quickshell.env("MINERVA_VIEWER_PATHS");
            if (!raw || raw === "")
                return [];
            var out = [];
            var righe = String(raw).split("\n");
            for (var i = 0; i < righe.length; i++) {
                var r = righe[i].trim();
                if (r !== "")
                    out.push(r);
            }
            return out;
        }

        /// Una cartella da sfogliare invece di un file da guardare. La
        /// distinzione la fa lo script, che ha `-d`; qui arriva già decisa.
        initialDir: {
            var d = Quickshell.env("MINERVA_VIEWER_DIR");
            return (d && d !== "") ? d : "";
        }

        // Chiudere la finestra chiude il programma, a meno che l'utente
        // abbia chiesto di tenerlo pronto: un processo senza finestre che
        // resta in memoria SENZA che nessuno l'abbia chiesto è un programma
        // che l'utente crede di aver chiuso e invece no.
        onRequestClose: pronta.chiudi()
    }

    /// Porta la finestra davanti e sulla scrivania di chi guarda.
    ///
    /// Senza, il secondo doppio clic su un'immagine sembra non fare niente:
    /// l'immagine cambia davvero, ma dietro a tutto il resto, magari su
    /// un'altra scrivania.
    function raise() {
        pronta.risveglia();
    }

    IpcHandler {
        target: "viewer"

        function open(path: string): string {
            if (path && path !== "")
                finestra.show(path);
            app.raise();
            return "ok";
        }

        /// Sfoglia una cartella intera. È quello che chiede il gestore file
        /// con «Sfoglia con Anteprima», e `minerva-viewer ~/Immagini`.
        function openDir(path: string): string {
            if (path && path !== "")
                finestra.apriCartella(path);
            app.raise();
            return "ok";
        }

        /// Serve a chi ci lancia per sapere che siamo vivi senza aprire niente.
        function ping(): string {
            return "ok";
        }
    }
}

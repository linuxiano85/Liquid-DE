//@ pragma AppId minerva-media
// minervamedia.qml — Minerva Media, come processo a sé.
//
// Come `filemanager.qml`: un secondo programma scritto con gli stessi pezzi
// della shell. Un errore nel lettore non deve poter spegnere la barra.
//
// Si avvia così, ed è quello che fa lo script `minerva-media`:
//
//     MINERVA_MEDIA_APRI=/home/tizio/musica.ogg \
//         qs -d -p .../minerva-shell/minervamedia.qml
//
// e chi è già aperto si comanda così:
//
//     qs ipc -p .../minerva-shell/minervamedia.qml call media apri /home/tizio/brano.mp3
//
// Il percorso nell'ambiente e non sulla riga di comando, la lingua, il tema e
// le trasparenze: tutto ripetuto da `filemanager.qml`, per gli stessi motivi.
import QtQuick
import Quickshell
import Quickshell.Io

import "theme" as Theme
import "core" as Core
import "media"

ShellRoot {
    id: app

    Component.onCompleted: {
        Quickshell.watchFiles = false;
    }

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






    // ── Chiuso, ma pronto ────────────────────────────────────────────────

    Core.TenutaPronta {
        id: pronta
        nome: "media"
        laFinestra: media

        // Si riparte puliti: musica ferma e pagina del Player.
        onAddormentata: media.addormenta()
    }

    MediaWindow {
        id: media

        /// Il percorso con cui aprirsi, passato nell'ambiente da chi ci
        /// lancia. Nell'ambiente e non sulla riga di comando: la riga è di
        /// `qs`, non nostra.
        initialPath: {
            var start = "";
            try {
                start = Quickshell.env("MINERVA_MEDIA_APRI") || "";
            } catch (e) {
                start = "";
            }
            return start;
        }

        dormiente: pronta.dormiente
        onRequestClose: pronta.chiudi()
    }

    /// Porta la finestra davanti. Il come sta in `core/TenutaPronta.qml`.
    function raise() {
        pronta.risveglia();
    }

    // ── Comandi dall'esterno ─────────────────────────────────────────────

    IpcHandler {
        target: "media"

        /// Un file si ascolta, una cartella si esplora.
        function apri(percorso: string): string {
            if (media.dormiente)
                media.risveglia(percorso);
            else if (percorso && percorso !== "")
                media.apriPercorso(percorso);
            pronta.risveglia();
            return "ok";
        }

        /// Un indirizzo di rete: si va dritti alla pagina Download.
        function scarica(indirizzo: string): string {
            if (media.dormiente)
                media.risveglia("");
            media.apriDownload(indirizzo);
            pronta.risveglia();
            return "ok";
        }

        /// Serve a chi ci lancia per sapere che siamo vivi senza aprire
        /// niente: se questa risponde, il processo c'è.
        function ping(): string {
            return "ok";
        }
    }
}
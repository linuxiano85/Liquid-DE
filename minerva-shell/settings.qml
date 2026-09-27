//@ pragma AppId minerva-settings
// settings.qml — Le Impostazioni di Minerva, come processo a sé.
//
// Terzo punto d'ingresso di Minerva, dopo `shell.qml` e `filemanager.qml`.
// Il ragionamento è scritto per esteso in cima a `filemanager.qml` e vale
// identico: un errore QML dentro un pannello di regolazioni non deve poter
// spegnere la barra da cui si aprono le regolazioni.
//
// Qui però c'è un motivo in più, e più stretto. Le Impostazioni sono la
// finestra in cui si TOCCANO le cose: si sposta un cursore e cambia la
// trasparenza, si preme un interruttore e cambia il tema. È esattamente il
// posto dove un valore fuori scala fa esplodere qualcosa. Finché stava dentro
// la shell, sbagliare una regolazione poteva portarsi via barra, dock e
// scrivania — cioè anche il modo di rimettere a posto la regolazione.
//
// Si avvia così, ed è quello che fa lo script `minerva-settings`:
//
//     MINERVA_SETTINGS_SECTION=audio \
//         qs -d -n -p .../minerva-shell/settings.qml
//
// e chi è già aperto si comanda così:
//
//     qs ipc -p .../minerva-shell/settings.qml call settings open rete
//
// Come per il gestore file, ciò che si continua a condividere è il DEMONE:
// le impostazioni stanno lì, quindi cambiarle qui le cambia per tutti senza
// che nessun processo debba sapere degli altri.
import QtQuick
import Quickshell
import Quickshell.Io

import "theme" as Theme
import "core" as Core
import "settings"

ShellRoot {
    id: app

    Component.onCompleted: {
        Quickshell.watchFiles = false;
    }

    // ── Quello che si prende dalle impostazioni ──────────────────────────
    //
    // Ripetute da `shell.qml`: sono processi diversi e non possono leggersi le
    // proprietà a vicenda. La sorgente però è la stessa, quindi cambiare
    // l'accento QUI ridipinge anche questa finestra nell'istante in cui il
    // demone lo ridice a tutti — cosa che si nota, perché è proprio questa la
    // finestra da cui lo si cambia.

    Binding {
        target: Core.Strings
        property: "requestedLanguage"
        value: Core.Ipc.get("general.language", "auto")
    }

    // ── Il colore di Minerva ─────────────────────────────────────────────
    //
    // Tema, accento e trasparenze si legano QUI e non dentro la palette,
    // perché la palette non deve conoscere il demone: un tema che sa dove
    // stanno le impostazioni è un tema che non si può riusare. E si ripete in
    // tutti e tre i punti d'ingresso perché sono processi diversi, che non
    // possono leggersi le proprietà a vicenda — la sorgente però è la stessa,
    // quindi cambiare tema li ridipinge tutti nello stesso istante.
    // Il tema di colore: una tinta e un verso, e da lì escono tutte le
    // superfici. Sta prima dell'accento di proposito — l'accento predefinito
    // è quello suggerito dal tema, e chi non ne ha scelto uno suo deve
    // vedersi arrivare quello giusto insieme al resto.

    // ── Il tema ──────────────────────────────────────────────────────────
    //
    // Un oggetto solo al posto dei blocchi di `Binding` che stavano qui: la
    // tavolozza non legge le impostazioni, e chi fa il legame lo fa in un
    // posto solo per tutti e sei i punti d'ingresso. Vedi `theme/LegaTema.qml`.
    Theme.LegaTema { }






    Binding {
        target: Core.SystemState
        property: "volumeCeiling"
        value: Core.Ipc.get("audio.allowOverdrive", false) ? 150 : 100
    }

    // I suoni di risposta ai comandi: qui dentro si preme molto, e premere
    // senza sentire niente in una finestra che altrove suona è una
    // dimenticatura che si nota.
    Binding {
        target: Core.Sounds
        property: "enabled"
        value: Core.Ipc.get("audio.feedbackSounds", true)
    }

    Binding {
        target: Core.Sounds
        property: "level"
        value: Core.Ipc.get("audio.feedbackVolume", 0.4)
    }

    // NB: non si tocca `Core.Wallpaper.rotates`. Il mazzo degli sfondi lo fa
    // girare la shell, che è quella che disegna la scrivania; questa finestra
    // può sceglierli e cambiarli a mano, ma il turno non è suo. Vedi il
    // commento su `rotates` in `core/Wallpaper.qml`.

    // ── Chiuse, ma pronte ────────────────────────────────────────────────
    //
    // Spente di fabbrica: riaprire le Impostazioni costa 516 ms, tenerle
    // pronte costa 159 MB sempre. Il conto lo fa chi usa il computer, in
    // questa stessa finestra.
    Core.TenutaPronta {
        id: pronta
        nome: "impostazioni"
        laFinestra: panel
    }

    // ── La finestra ──────────────────────────────────────────────────────

    System {
        id: panel

        dormiente: pronta.dormiente

        /// La sezione da aprire. Chi ci lancia può chiederne una; se non ne
        /// chiede nessuna si torna dove si era rimasti.
        ///
        /// ── Una riga d'aiuto che diceva il falso ──────────────────────────
        ///
        /// `scripts/minerva-settings` prometteva «apre dove si era rimasti»
        /// da sempre, e qui c'era scritto `"appearance"`: si riapriva su
        /// Aspetto ogni volta, anche dopo mezz'ora passata in Rete. Delle due
        /// cose si è tenuta la promessa, perché era anche quella giusta.
        ///
        /// Prima che il demone risponda `get` dà il valore di ripiego: la
        /// finestra non è ancora dipinta (`prontoADipingere`), quindi il salto
        /// alla sezione vera non si vede.
        section: {
            var wanted = Quickshell.env("MINERVA_SETTINGS_SECTION");
            if (wanted && wanted !== "")
                return app.sezioneNuova(wanted);
            return app.sezioneNuova(Core.Ipc.get("settings.lastSection", "appearance"));
        }

        onSectionChanged: app.ricordaSezione()

        onRequestClose: pronta.chiudi()
    }

    /// I nomi delle sezioni che non ci sono più, tradotti in quella che ne ha
    /// preso il posto (28 settembre 2026: da sei pagine di Personalizzazione
    /// a quattro, e «Lingua» dentro «Data e ora»). Un'ultima sezione
    /// ricordata o uno script che chiede «riva» arrivano nel posto giusto
    /// invece che su Aspetto.
    function sezioneNuova(id) {
        switch (String(id)) {
        case "stile":      return "appearance";
        case "animazioni": return "finestre";
        case "riva":       return "dock";
        case "lingua":     return "dataora";
        }
        return String(id);
    }

    /// Si segna dove si è arrivati. Non a ogni cambio di valore: solo quando
    /// cambia la SEZIONE, che è una volta ogni tanto.
    ///
    /// ── Perché non basta `onSectionChanged` ───────────────────────────────
    ///
    /// Perché aprendo su una sezione chiesta da fuori
    /// (`minerva-settings utente`) la sezione non CAMBIA mai: nasce già
    /// giusta, il segnale non scatta, e quando le impostazioni arrivano non
    /// c'è più niente da segnare. Provato: si riapriva su Aspetto lo stesso.
    /// Quindi ci si segna anche nel momento in cui il demone risponde.
    function ricordaSezione() {
        if (panel.section !== "" && Core.Ipc.impostazioniArrivate)
            Core.Ipc.setSetting("settings.lastSection", panel.section);
    }

    Connections {
        target: Core.Ipc
        function onImpostazioniArrivateChanged() { app.ricordaSezione(); }
    }

    /// Porta la finestra davanti e sulla scrivania di chi guarda: vedi
    /// `filemanager.qml`, stesso problema e stessa soluzione.
    function raise() {
        pronta.risveglia();
    }

    // ── Comandi dall'esterno ─────────────────────────────────────────────

    IpcHandler {
        target: "settings"

        /// Apre una sezione per nome. Chiedere una sezione a una finestra già
        /// aperta la porta lì: è il motivo per cui «Sfondo» nel menu della
        /// scrivania funziona anche con le Impostazioni già aperte su un'altra
        /// pagina.
        function open(section: string): string {
            if (section && section !== "")
                panel.section = app.sezioneNuova(section);
            app.raise();
            return "ok";
        }

        function ping(): string {
            return "ok";
        }
    }
}

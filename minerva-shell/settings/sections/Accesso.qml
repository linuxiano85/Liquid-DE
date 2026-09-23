import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme" as Theme
import "../../core" as Core
import ".." as S

// Accesso — La schermata che si vede prima di entrare.
//
// ── Perché queste preferenze non stanno con le altre ───────────────────────
//
// Tutte le altre impostazioni di Minerva le legge la TUA sessione. Queste no:
// le legge un processo che gira come utente `greeter`, prima che esista una
// sessione, e che nella tua casa non può nemmeno guardare. Quindi vanno
// scritte in un posto che quel processo possa leggere — ed è il motivo per cui
// «Applica» chiede la password: sta scrivendo in `/etc`, non in casa tua.
//
// ── L'accesso automatico, e cosa vuol dire davvero ─────────────────────────
//
// Non è «Minerva ricorda la password»: è greetd che apre la sessione SENZA
// chiederla. Chi accende il computer entra, chiunque sia. Su un portatile che
// esce di casa è una scelta da fare sapendola, ed è per questo che qui sotto
// c'è scritto invece di essere solo un interruttore.
Page {
    id: page

    title: page.it ? "Accesso" : "Login"
    subtitle: page.it
              ? "La schermata che si vede prima di entrare"
              : "The screen you see before logging in"

    readonly property bool it: Core.Strings.lang === "it"

    /// Chi c'è e in cosa può entrare: lo stesso elenco che vede la schermata
    /// di accesso, chiesto allo stesso servizio. Chiederlo qui invece di
    /// scriverlo a mano vuol dire che una sessione installata domani compare
    /// da sola.
    property var utenti: []
    property var sessioni: []
    property bool greetdInstallato: false

    /// I gestori di accessi installati, e quale è acceso adesso.
    ///
    /// Riconosciuti da `Alias=display-manager.service` dentro l'unità systemd
    /// e non da un elenco di nomi: chi ne installa uno che non conosciamo lo
    /// vede comparire, chi lo disinstalla lo vede sparire.
    property var gestori: []
    property string gestoreAttuale: ""

    /// Quale voce è selezionata nel riquadro. Parte da quella accesa.
    property string gestoreScelto: ""

    Connections {
        target: Core.Ipc
        function onGreeterInfoReceived(info) {
            page.utenti = info.utenti || [];
            page.sessioni = info.sessioni || [];
        }
        function onGestoriAccessoReceived(info) {
            page.gestori = info.gestori || [];
            page.gestoreAttuale = info.attuale || "";
            if (page.gestoreScelto === "")
                page.gestoreScelto = page.gestoreAttuale;
        }
    }

    Component.onCompleted: {
        Core.Ipc.greeterInfo();
        Core.Ipc.gestoriAccesso();
        cercaGreetd.running = true;
    }

    Process {
        id: cercaGreetd
        command: ["sh", "-c", "command -v greetd >/dev/null && echo si || echo no"]
        stdout: StdioCollector {
            onStreamFinished: page.greetdInstallato = text.trim() === "si"
        }
    }

    function opzioniUtenti() {
        var o = [];
        for (var i = 0; i < page.utenti.length; i++) {
            var u = page.utenti[i];
            o.push({ "value": u.nome,
                     "label": u.nomeCompleto !== "" ? u.nomeCompleto : u.nome });
        }
        return o.length > 0 ? o : [{ "value": "", "label": "—" }];
    }

    /// Le scrivanie fra cui si può scegliere quella di partenza.
    ///
    /// Senza la riga di comando, che il demone aggiunge sempre in fondo
    /// all'elenco: è la via di scorta per quando le scrivanie non partono, e
    /// sceglierla QUI vorrebbe dire dire al computer «da domani entra in un
    /// terminale». La schermata di accesso ce la mostra, e da lì la si prende
    /// quando serve; una preferenza permanente, no.
    function opzioniSessioni() {
        var o = [];
        for (var i = 0; i < page.sessioni.length; i++) {
            if (page.sessioni[i].tipo === "tty") continue;
            o.push({ "value": page.sessioni[i].id, "label": page.sessioni[i].nome });
        }
        return o.length > 0 ? o : [{ "value": "", "label": "—" }];
    }

    function opzioniGestori() {
        var o = [];
        for (var i = 0; i < page.gestori.length; i++)
            o.push({ "value": page.gestori[i].unita,
                     "label": page.gestori[i].nome });
        return o.length > 0 ? o : [{ "value": "", "label": "—" }];
    }

    function nomeDi(unita) {
        for (var i = 0; i < page.gestori.length; i++)
            if (page.gestori[i].unita === unita) return page.gestori[i].nome;
        return unita;
    }

    /// Accende il gestore scelto. Il nome dell'unità passa come ARGOMENTO e
    /// non incollato in una riga di shell — e comunque `minerva-greetd` lo
    /// ricontrolla da capo, perché lo si può lanciare anche a mano e un
    /// controllo che vive solo qui non è un controllo.
    function cambiaGestore() {
        if (page.comandoGreetd === "" || page.gestoreScelto === "")
            return;
        page.esito = "";
        gestore.command = ["pkexec", page.comandoGreetd,
                           "gestore", page.gestoreScelto];
        gestore.running = true;
    }

    // ── Se greetd non c'è, si dice ───────────────────────────────────────
    //
    // Senza questa riga, questa pagina prometterebbe cose che non succedono:
    // si cambia lo sfondo, si preme Applica, e all'accesso successivo compare
    // la schermata di KDE come sempre. Un'impostazione che non ha effetto è
    // peggio di un'impostazione che manca.

    Card {
        heading: page.it ? "Non è ancora in uso" : "Not in use yet"
        visible: !page.greetdInstallato

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
            lineHeight: Theme.Typography.leadingBody
            text: page.it
                ? "A farti entrare è ancora il gestore di accessi di KDE. La schermata di Minerva è pronta e la puoi guardare, ma per usarla davvero serve «greetd» — il programma che ha il permesso di verificare la password.\n\nFinché non lo installi, quello che cambi qui vale solo per l'anteprima."
                : "KDE's login manager is still the one letting you in. Minerva's own screen is ready and you can preview it, but making it real needs “greetd” — the program allowed to verify your password.\n\nUntil then, what you change here only affects the preview."
        }
    }

    // ── Chi ti apre la porta ─────────────────────────────────────────────
    //
    // Giacomo, 23 agosto 2026: «voglio un'impostazione per impostare il login
    // manager predefinito, nel caso in cui io voglia quello di kde o cosmic o
    // gnome o altri».
    //
    // Vale anche come via di ritorno, ed è la ragione per cui sta in cima alla
    // pagina invece che in fondo: se la nostra schermata non entrasse, finora
    // l'unico modo di tornare indietro era ricordarsi «sudo minerva-greetd
    // indietro» da una console testuale — con Fn, su questa tastiera. Averlo
    // qui vuol dire poterlo fare PRIMA che serva.
    //
    // Il cambio ha effetto dal prossimo riavvio, e si dice: un pulsante che
    // sembra agire subito e non lo fa è il modo più veloce di far premere due
    // volte una cosa delicata.

    Card {
        heading: page.it ? "Chi ti apre la porta" : "Who lets you in"
        visible: page.gestori.length > 1

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
            lineHeight: Theme.Typography.leadingBody
            text: page.it
                ? "Il programma che chiede la password all'accensione. Qui ci sono quelli installati su questo computer; il cambio vale dal prossimo riavvio, e quello di adesso viene spento ma non disinstallato."
                : "The program that asks for your password at boot. These are the ones installed on this computer; the change takes effect at the next restart, and the current one is switched off but not uninstalled."
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Gestore di accessi" : "Login manager"
            description: page.gestoreAttuale === ""
                ? (page.it ? "Adesso non ne risulta acceso nessuno"
                           : "None appears to be enabled right now")
                : (page.it ? "Adesso: " + page.nomeDi(page.gestoreAttuale)
                           : "Now: " + page.nomeDi(page.gestoreAttuale))
            controlWidth: 260

            control: S.ChoicePicker {
                value: page.gestoreScelto
                options: page.opzioniGestori()
                onPicked: function(v) { page.gestoreScelto = v; }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Cambia gestore di accessi"
                           : "Change login manager"
            description: page.it
                ? "Chiede la password di amministratore. Ha effetto dal prossimo riavvio"
                : "Asks for the administrator password. Takes effect at the next restart"
            controlWidth: 130
            visible: page.gestoreScelto !== ""
                     && page.gestoreScelto !== page.gestoreAttuale

            control: Rectangle {
                width: 130
                height: 34
                radius: Theme.Effects.radiusSM
                color: cambia.containsMouse ? Qt.alpha(Theme.Colors.accent, 0.35)
                                            : Qt.alpha(Theme.Colors.accent, 0.20)
                border.width: Theme.Effects.hairline
                border.color: Qt.alpha(Theme.Colors.accent, 0.5)

                Text {
                    anchors.centerIn: parent
                    text: page.it ? "Cambia" : "Change"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }

                MouseArea {
                    id: cambia
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.cambiaGestore()
                }
            }
        }
    }

    // ── L'anteprima ──────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Guardala" : "See it"

        S.SettingRow {
            width: parent.width
            label: page.it ? "Apri l'anteprima" : "Open the preview"
            description: page.it
                ? "Si apre in una finestra, con le impostazioni di adesso. Non tocca il modo in cui entri"
                : "Opens in a window with the current settings. It does not touch how you log in"
            controlWidth: 130

            control: Rectangle {
                width: 130
                height: 34
                radius: Theme.Effects.radiusSM
                color: guarda.containsMouse ? Theme.Colors.raisedHigh : Theme.Colors.raised
                border.width: Theme.Effects.hairline
                border.color: Theme.Colors.edge

                Text {
                    anchors.centerIn: parent
                    text: page.it ? "Anteprima" : "Preview"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }

                MouseArea {
                    id: guarda
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // `-p` con il percorso fra virgolette: la cartella del
                    // progetto contiene uno spazio, e ogni `exec` che lo
                    // dimentica muore senza dire niente.
                    onClicked: Quickshell.execDetached(
                        ["qs", "-p", Quickshell.shellDir + "/greeter.qml"])
                }
            }
        }
    }

    // ── L'aspetto ────────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Aspetto" : "Look"

        S.SettingRow {
            width: parent.width
            label: page.it ? "Sfondo" : "Background"
            description: page.it
                ? "«Aurora» è disegnata dalla scheda grafica: si muove piano e non si ripete mai uguale"
                : "“Aurora” is drawn by the GPU: it drifts slowly and never repeats"
            controlWidth: 260

            control: S.ChoicePicker {
                value: Core.Ipc.get("greeter.background", "aurora")
                options: [
                    { "value": "aurora",   "label": page.it ? "Aurora" : "Aurora" },
                    { "value": "immagine", "label": page.it ? "Immagine" : "Image" }
                ]
                onPicked: function(v) { Core.Ipc.setSetting("greeter.background", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("greeter.background", "aurora") === "aurora"
            label: page.it ? "Intensità dell'aurora" : "Aurora strength"
            description: page.it
                ? "Quanto sono accese le correnti di luce"
                : "How bright the drifting light is"
            controlWidth: 260

            control: S.ValueSlider {
                value: Core.Ipc.get("greeter.auroraStrength", 0.55)
                from: 0.15
                to: 1.0
                onReleased: function(v) {
                    Core.Ipc.setSetting("greeter.auroraStrength", Math.round(v * 100) / 100);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("greeter.background", "aurora") === "immagine"
            label: page.it ? "Immagine di sfondo" : "Background image"
            // ── La frase di prima diceva una cosa vera e inutile ─────────
            //
            // «Dev'essere leggibile da tutti: la tua cartella personale non lo
            // è» era esatta e scaricava il problema su chi legge: e adesso?
            // Sposto la fotografia a mano in /usr/share?
            //
            // Adesso la porta Minerva: `scripts/minerva-greetd` la copia
            // accanto alla schermata di accesso, che è l'unico posto da cui
            // quella può leggerla — esattamente come fa già il ritratto.
            description: page.it
                ? "Viene copiata accanto alla schermata di accesso: è l'unico posto da cui può leggerla"
                : "It gets copied next to the login screen: the only place it can read from"
            controlWidth: 340

            // Qui c'era una casella e basta, con sotto la spiegazione di quali
            // cartelle sono leggibili da tutti — cioè si chiedeva di scrivere
            // `/usr/share/backgrounds/…` a mano SAPENDO già il percorso.
            // Giacomo, 5 settembre 2026: «ci sono parti delle impostazioni dove
            // devi incollare il percorso e a me non piace perché voglio
            // semplicità».
            control: S.SceltaPercorso {
                width: 340
                // Un'immagine si sceglie GUARDANDOLA: si apre il selettore
                // con le anteprime, lo stesso di «Scegli dal disco…».
                immagini: true
                percorso: Core.Ipc.get("greeter.wallpaper", "")
                segnaposto: "/usr/share/backgrounds/…"
                daDove: "/usr/share/backgrounds"
                titolo: page.it ? "Lo sfondo della schermata di accesso"
                                : "The login screen background"
                onScelto: function (p) {
                    Core.Ipc.setSetting("greeter.wallpaper", p);
                }
            }
        }

        // ── Perché non si vede subito ────────────────────────────────────
        //
        // La schermata di accesso non legge le TUE impostazioni: ne ha una
        // copia sua, in una cartella di sistema, presa quando è stata
        // installata. Non è una scelta di comodo — è l'unico modo: quando
        // quella schermata è a video, la tua cartella personale è ancora
        // chiusa a chiave.
        //
        // Quindi va detto, invece di lasciare che uno cambi lo sfondo e non
        // veda succedere niente. Giacomo, 6 settembre 2026: «il cambio sfondo
        // della login non fa comparire lo sfondo ma nero».
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: page.it
                ? "L'anteprima qui sopra mostra subito quello che scegli. La "
                + "schermata VERA invece ne tiene una copia sua — quando è a "
                + "video la tua cartella personale è ancora chiusa a chiave — e "
                + "quella copia si aggiorna col pulsante qui sotto."
                : "The preview above shows your choices right away. The real "
                + "screen keeps its own copy — while it is on screen your home "
                + "folder is still locked — and that copy is refreshed with the "
                + "button below."
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            visible: true
        }

        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("greeter.background", "aurora") === "immagine"
            label: page.it ? "Sfocatura" : "Blur"
            description: page.it
                ? "È ciò che permette al testo di stare sulla fotografia senza un riquadro sotto"
                : "It is what lets the text sit on the photo without a panel behind it"
            controlWidth: 260

            control: S.ValueSlider {
                value: Core.Ipc.get("greeter.blur", 48)
                from: 0
                to: 96
                // In PIXEL, non in percentuale. Con `unit: ""` — che non è
                // nessuna delle unità che `ValueSlider` conosce — si finiva
                // nel caso di ripiego, la percentuale, e quarantasette pixel
                // di sfocatura si presentavano come «4700%».
                unit: "pixel"
                onReleased: function(v) {
                    Core.Ipc.setSetting("greeter.blur", Math.round(v));
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Velo scuro" : "Dark veil"
            description: page.it
                ? "Alza il contrasto del testo. Troppo poco e l'ora sparisce su uno sfondo chiaro"
                : "Raises text contrast. Too little and the clock disappears on a light background"
            controlWidth: 260

            control: S.ValueSlider {
                value: Core.Ipc.get("greeter.scrim", 0.42)
                from: 0.0
                to: 0.85
                onReleased: function(v) {
                    Core.Ipc.setSetting("greeter.scrim", Math.round(v * 100) / 100);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Mostra l'ora" : "Show the clock"
            description: page.it
                ? "L'orologio grande in cima"
                : "The large clock at the top"
            controlWidth: 60

            control: S.ToggleSwitch {
                checked: Core.Ipc.get("greeter.showClock", true)
                onToggled: function(v) { Core.Ipc.setSetting("greeter.showClock", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("greeter.showClock", true)
            label: page.it ? "Orario di 24 ore" : "24-hour clock"
            description: page.it ? "Spento: 7:40 PM" : "Off: 7:40 PM"
            controlWidth: 60

            control: S.ToggleSwitch {
                checked: Core.Ipc.get("greeter.clock24", true)
                onToggled: function(v) { Core.Ipc.setSetting("greeter.clock24", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Ora e accesso" : "Clock and sign-in"
            description: page.it
                ? "Da che parte stanno. Vale anche per la schermata di blocco, che usa l'altra metà per le notifiche"
                : "Which side they sit on. Also used by the lock screen, which puts notifications on the other half"
            searchTerms: "lato sinistra destra disposizione accesso blocco"
            controlWidth: 300

            control: S.ChoicePicker {
                value: Core.Ipc.get("greeter.lato", "sinistra")
                options: [
                    { "value": "sinistra", "label": page.it ? "A sinistra" : "Left" },
                    { "value": "centro",   "label": page.it ? "Al centro" : "Center" },
                    { "value": "destra",   "label": page.it ? "A destra" : "Right" }
                ]
                onPicked: function(v) { Core.Ipc.setSetting("greeter.lato", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Meteo" : "Weather"
            description: page.it
                ? "Sotto la data, con la città scelta per il meteo: chi guarda la schermata la vede"
                : "Under the date, with your weather city: anyone at the screen can see it"
            searchTerms: "meteo tempo città accesso login"
            controlWidth: 60

            control: S.ToggleSwitch {
                checked: Core.Ipc.get("greeter.meteo", true)
                onToggled: function(v) { Core.Ipc.setSetting("greeter.meteo", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Saluto" : "Greeting"
            description: page.it
                ? "«Buonasera, Giacomo» al posto del nome"
                : "“Good evening, Giacomo” instead of the name"
            controlWidth: 60

            control: S.ToggleSwitch {
                checked: Core.Ipc.get("greeter.saluto", true)
                onToggled: function(v) { Core.Ipc.setSetting("greeter.saluto", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Batteria e tastiera" : "Battery and keyboard"
            description: page.it
                ? "In alto a destra: la carica e la disposizione dei tasti"
                : "Top right: the charge and the keyboard layout"
            controlWidth: 60

            control: S.ToggleSwitch {
                checked: Core.Ipc.get("greeter.stato", true)
                onToggled: function(v) { Core.Ipc.setSetting("greeter.stato", v); }
            }
        }
    }

    // ── Chi e cosa, di partenza ──────────────────────────────────────────

    Card {
        heading: page.it ? "Di partenza" : "Preselected"

        S.SettingRow {
            width: parent.width
            label: page.it ? "Utente" : "User"
            description: page.it
                ? "Chi risulta già scelto quando la schermata si apre"
                : "Who is already selected when the screen opens"
            controlWidth: 260

            control: S.ChoicePicker {
                value: Core.Ipc.get("greeter.user", "")
                options: page.opzioniUtenti()
                onPicked: function(v) { Core.Ipc.setSetting("greeter.user", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Sessione" : "Session"
            description: page.it
                ? "In cosa si entra premendo Invio senza toccare altro"
                : "What you get by pressing Enter without touching anything"
            controlWidth: 260

            control: S.ChoicePicker {
                value: Core.Ipc.get("greeter.session", "minerva")
                options: page.opzioniSessioni()
                onPicked: function(v) { Core.Ipc.setSetting("greeter.session", v); }
            }
        }
    }

    // ── L'accesso automatico ─────────────────────────────────────────────

    Card {
        heading: page.it ? "Accesso automatico" : "Automatic login"

        S.SettingRow {
            width: parent.width
            label: page.it ? "Entra senza chiedere la password"
                           : "Log in without asking for the password"
            description: page.it
                ? "Chi accende il computer entra, chiunque sia. Su un portatile che esce di casa vuol dire che chi lo trova è dentro"
                : "Whoever turns the computer on gets in. On a laptop that leaves the house, that means whoever finds it is inside"
            controlWidth: 60

            control: S.ToggleSwitch {
                checked: Core.Ipc.get("greeter.autologin", false)
                onToggled: function(v) { Core.Ipc.setSetting("greeter.autologin", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("greeter.autologin", false)
            label: page.it ? "Entra come" : "Log in as"
            description: page.it
                ? "Con l'accesso automatico acceso, questo è l'unico utente che entra"
                : "With automatic login on, this is the only user who gets in"
            controlWidth: 260

            control: S.ChoicePicker {
                value: Core.Ipc.get("greeter.user", "")
                options: page.opzioniUtenti()
                onPicked: function(v) { Core.Ipc.setSetting("greeter.user", v); }
            }
        }

        // ── Applica ──────────────────────────────────────────────────────
        //
        // Le impostazioni qui sopra stanno nel demone. Queste due — chi entra
        // da solo, e in cosa — le deve sapere GREETD, che le legge da
        // `/etc/greetd/config.toml` e non dal demone. Scrivere in `/etc`
        // richiede la password di amministratore: è ciò che fa `pkexec`, ed è
        // il motivo per cui questo è un pulsante e non un interruttore che
        // agisce subito.

        S.SettingRow {
            width: parent.width
            // ── Diceva metà del proprio mestiere ─────────────────────
            //
            // Si chiamava «Scrivi la configurazione di greetd» e parlava solo
            // di accesso automatico e sessione di partenza. In realtà porta
            // alla schermata di accesso TUTTO quello che si sceglie in questa
            // pagina — sfondo, sfocatura, velo, ora — perché `configura`
            // chiama anche `copia_impostazioni`.
            //
            // Giacomo, 6 settembre 2026: «quando clicco su uno sfondo e clicco
            // su anteprima dovrei vederlo giusto? o devo prima cliccare su
            // applica?». La domanda nasce da qui: il pulsante che serviva
            // c'era, e diceva di riguardare un'altra cosa.
            label: page.it ? "Porta le scelte alla schermata di accesso"
                           : "Take these choices to the login screen"
            description: page.it
                ? "Sfondo, sfocatura, ora e accesso automatico. Chiede la password: la schermata di accesso vive fuori dalla tua cartella"
                : "Background, blur, clock and automatic login. Asks for the password: the login screen lives outside your home folder"
            controlWidth: 130
            visible: page.greetdInstallato

            control: Rectangle {
                width: 130
                height: 34
                radius: Theme.Effects.radiusSM
                color: applica.containsMouse ? Qt.alpha(Theme.Colors.accent, 0.35)
                                             : Qt.alpha(Theme.Colors.accent, 0.20)
                border.width: Theme.Effects.hairline
                border.color: Qt.alpha(Theme.Colors.accent, 0.5)

                Text {
                    anchors.centerIn: parent
                    text: page.it ? "Applica" : "Apply"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }

                MouseArea {
                    id: applica
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Finché non si sa DOVE sta il programma, non si lancia
                    // niente: `pkexec` con un percorso vuoto aprirebbe la
                    // finestrella della password per poi non fare nulla.
                    onClicked: {
                        if (page.comandoGreetd !== "")
                            scrivi.running = true;
                    }
                }
            }
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            visible: page.esito !== ""
            text: page.esito
            color: page.esitoGrave ? Theme.Colors.danger : Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    property string esito: ""
    property bool esitoGrave: false

    /// Dove sta il programma che scrive in `/etc/greetd`. **Quello
    /// installato, se c'è.**
    ///
    /// Lo esegue `pkexec`, cioè root. Fino al 23 agosto 2026 questa riga
    /// puntava alla copia dentro la cartella del progetto: root eseguiva uno
    /// script scrivibile dall'utente. La password di amministratore la
    /// chiedeva lo stesso, quindi non era una scalata di privilegi — ma è la
    /// forma classica del guaio, perché qualunque cosa giri come te (un
    /// pacchetto npm, un'estensione del browser) può riscrivere quello script
    /// e poi aspettare che tu prema il pulsante.
    ///
    /// `minerva-greetd installa` mette una copia in `/usr/local/bin`, di root
    /// e non scrivibile da altri. È la stessa scelta già fatta per
    /// `minerva-utente` e per `greeter.qml`.
    property string comandoGreetd: ""

    Core.Exec {
        id: doveSta
        Component.onCompleted: doveSta.shArgs(
            '[ -x /usr/local/bin/minerva-greetd ] '
            + '&& { printf %s /usr/local/bin/minerva-greetd; exit 0; }; '
            + 'printf %s "$1"',
            [Quickshell.shellDir + "/../scripts/minerva-greetd"]);
        onDone: function (out) { page.comandoGreetd = out; }
    }

    Process {
        id: gestore
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") {
                    page.esito = text.trim();
                    page.esitoGrave = false;
                }
                // Si rilegge chi è acceso invece di darlo per fatto: se
                // `systemctl enable` è fallito, lo script ha già rimesso
                // quello di prima, e mostrare il nuovo sarebbe una bugia.
                Core.Ipc.gestoriAccesso();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "")
                    return;
                page.esito = text.trim();
                page.esitoGrave = true;
            }
        }
        onExited: function (code) {
            if (code === 126)
                page.esito = page.it ? "Annullato." : "Cancelled.";
        }
    }

    Process {
        id: scrivi
        // Il percorso passa come ARGOMENTO e non incollato nella riga: la
        // cartella del progetto ha uno spazio nel nome, e i valori che
        // arrivano dalle impostazioni non si infilano mai dentro `sh -c`.
        // Vedi `core/Exec.qml`.
        command: ["pkexec", page.comandoGreetd, "configura"]
        stdout: StdioCollector {
            onStreamFinished: {
                page.esito = text.trim();
                page.esitoGrave = false;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "")
                    return;
                page.esito = text.trim();
                page.esitoGrave = true;
            }
        }
    }
}

import QtQuick
import Quickshell
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// Avvio — I programmi che partono insieme alla sessione.
//
// KDE ha una pagina così; Minerva non aveva niente, e non per svista:
// **Hyprland non legge `~/.config/autostart`**. Chi arriva da un altro
// ambiente si porta dietro quella cartella e i suoi programmi smettono di
// partire senza che nessuno glielo dica.
//
// ── Perché le voci di sistema si vedono ma sono spente ────────────────────
//
// Sotto `/etc/xdg/autostart` ci sono diciannove voci lasciate dai pacchetti di
// KDE — `baloo_file` che indicizza tutto il disco, `plasmashell`, `powerdevil`.
// Oggi non partono, e la sessione funziona benissimo. Accenderle tutte perché
// «un desktop completo fa così» vorrebbe dire far comparire dal nulla un
// indicizzatore del disco il giorno in cui si aggiunge questa pagina.
//
// Quindi si vedono, spente, con la levetta: chi ne vuole una se l'accende. È
// la stessa scelta che fa KDE, e ha il pregio di non cambiare niente a chi non
// tocca nulla.
Page {
    id: page

    readonly property bool it: Core.Strings.lang === "it"

    title: page.it ? "Avvio" : "Startup"
    subtitle: page.it ? "I programmi che partono con la sessione"
                      : "Programs that start with your session"

    property var voci: []

    Component.onCompleted: Core.Ipc.autostartList()

    Connections {
        target: Core.Ipc
        function onAutostartReceived(v) { page.voci = v || []; }
        // Se il demone cade e torna, l'elenco va richiesto di nuovo: altrimenti
        // la pagina resta con quello di prima e sembra che non ci sia niente.
        function onConnectedChanged() {
            if (Core.Ipc.connected) Core.Ipc.autostartList();
        }
    }

    readonly property var mie: {
        var out = [];
        for (var i = 0; i < page.voci.length; i++)
            if (page.voci[i].utente) out.push(page.voci[i]);
        return out;
    }

    readonly property var diSistema: {
        var out = [];
        for (var i = 0; i < page.voci.length; i++)
            if (!page.voci[i].utente) out.push(page.voci[i]);
        return out;
    }

    // ── Le nostre app, tenute pronte ─────────────────────────────────────
    //
    // Sta qui e non nelle pagine delle singole app perché è una scelta sola,
    // che si fa guardando il totale: sei levette sparse in sei posti sono sei
    // decisioni prese senza sapere quanto costa l'insieme.
    //
    // Il prezzo è scritto in ogni riga, e non è un vezzo: è la sola cosa che
    // permette di scegliere. Vedi `core/TenutaPronta.qml` per come sono stati
    // misurati.

    readonly property var appPronte: [
        { "chiave": "files.tieniAcceso",    "nome": page.it ? "File" : "Files",
          "attesa": 645, "costo": 84, "fabbrica": true },
        { "chiave": "preload.impostazioni", "nome": page.it ? "Impostazioni" : "Settings",
          "attesa": 480, "costo": 98, "fabbrica": false },
        { "chiave": "preload.editor",       "nome": page.it ? "Editor" : "Editor",
          "attesa": 385, "costo": 61,  "fabbrica": false },
        { "chiave": "preload.attivita",     "nome": page.it ? "Attività" : "Activity",
          "attesa": 353, "costo": 74, "fabbrica": false },
        { "chiave": "preload.anteprima",    "nome": page.it ? "Anteprima" : "Preview",
          "attesa": 359, "costo": 52,  "fabbrica": false },
        { "chiave": "preload.calcolatrice", "nome": page.it ? "Calcolatrice" : "Calculator",
          "attesa": 317, "costo": 49,  "fabbrica": false },
        // Il Terminale tenuto pronto ha già una shell viva dentro: costo da
        // misurare (15 settembre 2026), i numeri sotto sono provvisori e
        // vanno rimisurati come gli altri, con `memoria.sh`.
        { "chiave": "preload.terminale",    "nome": page.it ? "Terminale" : "Terminal",
          "attesa": 400, "costo": 60,  "fabbrica": false }
    ]

    /// Quanto costa in tutto quello che è acceso adesso.
    ///
    /// Il totale e non la somma delle etichette: è il numero che serve per
    /// decidere, e nessuno lo fa a mente leggendo sei righe.
    readonly property int costoAcceso: {
        var t = 0;
        for (var i = 0; i < page.appPronte.length; i++) {
            var a = page.appPronte[i];
            if (Core.Ipc.get(a.chiave, a.fabbrica) === true)
                t += a.costo;
        }
        return t;
    }

    Card {
        heading: page.it ? "Le app di Minerva, tenute pronte"
                         : "Minerva apps, kept ready"
        note: page.it
              ? "Un'app tenuta pronta si riapre in meno di un decimo di secondo "
                + "invece che in mezzo. In cambio resta in memoria: acceso "
                + "adesso, " + page.costoAcceso + " MB."
              : "An app kept ready reopens in less than a tenth of a second "
                + "instead of half a second. In exchange it stays in memory: "
                + "currently on, " + page.costoAcceso + " MB."

        Repeater {
            model: page.appPronte

            delegate: S.SettingRow {
                required property var modelData

                width: parent.width
                label: modelData.nome
                description: page.it
                    ? "Si riapre subito invece che in " + modelData.attesa
                      + " ms. Costa " + modelData.costo + " MB sempre."
                    : "Reopens instantly instead of in " + modelData.attesa
                      + " ms. Costs " + modelData.costo + " MB at all times."
                controlWidth: 60
                control: S.ToggleSwitch {
                    checked: Core.Ipc.get(modelData.chiave, modelData.fabbrica)
                    onToggled: function (v) {
                        Core.Ipc.setSetting(modelData.chiave, v);
                    }
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Se non la usi, si spegne"
                           : "If you do not use it, it shuts down"
            description: page.it
                ? "Dopo quanti minuti ferma un'app tenuta pronta esce da sola "
                  + "e libera la memoria. Zero la lascia lì per sempre."
                : "After how many idle minutes a ready app quits by itself and "
                  + "frees the memory. Zero leaves it there forever."
            controlWidth: 240
            control: S.ValueSlider {
                width: 240
                from: 0
                to: 240
                value: Core.Ipc.get("preload.minuti", 30)
                // «intero» e non «percento»: sono minuti, e il valore di
                // fabbrica è 30 — con l'unità sbagliata si leggerebbe «3000%».
                unit: "intero"
                suffix: "min"
                onReleased: function (v) {
                    Core.Ipc.setSetting("preload.minuti", Math.round(v));
                }
            }
        }
    }

    // ── Aggiungerne uno ──────────────────────────────────────────────────

    Card {
        heading: page.it ? "Aggiungi un programma" : "Add a program"
        note: page.it
              ? "Il comando è quello che scriveresti in un terminale."
              : "The command is what you would type in a terminal."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Nome" : "Name"
            description: page.it ? "Come si chiama nell'elenco qui sotto"
                                 : "How it appears in the list below"
            controlWidth: 240
            control: CampoTesto {
                id: nuovoNome
                width: 240
                segnaposto: page.it ? "Il mio programma" : "My program"
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Comando" : "Command"
            description: page.it
                ? "Il programma da avviare. «Sfoglia…» lo cerca sul disco; le opzioni si aggiungono dopo"
                : "The program to start. “Browse…” finds it on disk; add options afterwards"
            controlWidth: 340

            // Qui c'era una casella e basta: chi non sa già dove sta un
            // programma non aveva nessun modo di trovarlo. Giacomo, 5
            // settembre 2026: «voglio semplicità».
            //
            // Scegliendo un file si sostituisce il comando intero, non si
            // aggiunge in coda: chi sfoglia sta scegliendo QUALE programma, e
            // le opzioni le scrive dopo.
            control: S.SceltaPercorso {
                id: nuovoComando
                width: 340
                percorso: ""
                segnaposto: "syncthing --no-browser"
                daDove: "/usr/bin"
                titolo: page.it ? "Quale programma avviare"
                                : "Which program to start"
                // Scegliere riempie il campo e basta: aggiungere è un altro
                // gesto, e farlo da soli toglierebbe la possibilità di
                // scrivere le opzioni dopo il nome del programma.
                onScelto: function (p) { nuovoComando.percorso = p; }
            }
        }

        S.SettingRow {
            width: parent.width
            label: ""
            controlWidth: 130
            control: Pulsante {
                width: 130
                testo: page.it ? "Aggiungi" : "Add"
                // Spento finché non c'è un comando: un pulsante che si può
                // premere e non fa niente insegna a non fidarsi degli altri.
                attivo: nuovoComando.percorso.trim() !== ""
                onPremuto: page.aggiungi()
            }
        }
    }

    function aggiungi() {
        var cmd = nuovoComando.percorso.trim();
        if (cmd === "")
            return;
        var nome = nuovoNome.testo.trim();
        // Senza nome si usa la prima parola del comando: è quasi sempre il
        // nome del programma, e chiedere due volte la stessa cosa infastidisce.
        if (nome === "")
            nome = cmd.split(" ")[0];
        Core.Ipc.autostartAdd(nome, cmd);
        nuovoNome.testo = "";
        nuovoComando.percorso = "";
    }

    // ── I tuoi ───────────────────────────────────────────────────────────

    Card {
        heading: page.it ? "I tuoi" : "Yours"

        Text {
            width: parent.width
            visible: page.mie.length === 0
            text: page.it ? "Non ne hai nessuno. Va benissimo così."
                          : "You have none. That is perfectly fine."
            color: Theme.Colors.textFaint
            wrapMode: Text.WordWrap
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }

        Repeater {
            model: page.mie
            delegate: RigaAvvio {
                required property var modelData
                width: parent.width
                voce: modelData
                puoTogliere: true
            }
        }
    }

    // ── Quelli di sistema ────────────────────────────────────────────────

    Card {
        heading: page.it ? "Messi dai programmi installati"
                         : "Added by installed programs"
        note: page.it
              ? "Sono spenti: Minerva non fa partire da sola le voci di sistema. "
                + "Accendi quelle che ti servono."
              : "They are off: Minerva does not start system entries by itself. "
                + "Turn on the ones you need."

        Repeater {
            model: page.diSistema
            delegate: RigaAvvio {
                required property var modelData
                width: parent.width
                voce: modelData
                puoTogliere: false
            }
        }
    }

    // ── I pezzi ──────────────────────────────────────────────────────────

    component RigaAvvio: Item {
        id: riga

        property var voce: null
        property bool puoTogliere: false

        implicitHeight: Math.max(44, testi.implicitHeight + Theme.Effects.space3)

        Column {
            id: testi
            anchors.left: parent.left
            anchors.right: comandi.left
            anchors.rightMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: riga.voce ? riga.voce.nome : ""
                elide: Text.ElideRight
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            // Sotto: il comando, o il motivo per cui è spenta.
            //
            // Il motivo conta più del comando. Una levetta spenta senza
            // spiegazione si prova a riaccendere all'infinito — e se è spenta
            // perché il programma non è più installato, riaccenderla non farà
            // mai niente.
            Text {
                width: parent.width
                text: {
                    if (!riga.voce)
                        return "";
                    if (riga.voce.motivo !== "" && riga.voce.motivo !== "spenta")
                        return riga.voce.motivo;
                    return riga.voce.exec;
                }
                elide: Text.ElideRight
                color: riga.voce && riga.voce.motivo !== ""
                       && riga.voce.motivo !== "spenta"
                       ? Theme.Colors.warning : Theme.Colors.textFaint
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXS
            }
        }

        Row {
            id: comandi
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.Effects.space3

            S.ToggleSwitch {
                anchors.verticalCenter: parent.verticalCenter
                checked: riga.voce ? riga.voce.acceso : false
                // Una voce il cui programma non c'è più non si accende: la
                // levetta scatterebbe e non partirebbe niente.
                enabled: !riga.voce || riga.voce.motivo === ""
                         || riga.voce.motivo === "spenta"
                onToggled: function(v) {
                    Core.Ipc.autostartSet(riga.voce.file, v);
                }
            }

            // Togliere cancella il file della voce, e il comando scritto a
            // mano con le sue opzioni se ne va con lui. Un clic solo su una
            // × da 28 pixel era troppo poco: il primo chiede «Tolgo?», il
            // secondo entro quattro secondi toglie.
            Rectangle {
                id: togli
                property bool chiede: false
                anchors.verticalCenter: parent.verticalCenter
                visible: riga.puoTogliere
                width: togli.chiede ? togliTesto.implicitWidth + Theme.Effects.space4 : 28
                height: 28
                radius: Theme.Effects.radiusFull
                color: togli.chiede || togliMouse.containsMouse
                       ? Qt.alpha(Theme.Colors.danger, 0.18) : "transparent"

                Ui.Icon {
                    anchors.centerIn: parent
                    visible: !togli.chiede
                    width: 14; height: 14
                    name: "close"
                    color: togliMouse.containsMouse ? Theme.Colors.danger
                                                    : Theme.Colors.textFaint
                    alwaysDrawn: true
                }

                Text {
                    id: togliTesto
                    anchors.centerIn: parent
                    visible: togli.chiede
                    text: page.it ? "Tolgo?" : "Remove?"
                    color: Theme.Colors.danger
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeXS
                }

                Timer {
                    interval: 4000
                    running: togli.chiede
                    onTriggered: togli.chiede = false
                }

                MouseArea {
                    id: togliMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!togli.chiede) {
                            togli.chiede = true;
                            return;
                        }
                        togli.chiede = false;
                        Core.Ipc.autostartRemove(riga.voce.file);
                    }
                }
            }
        }
    }

    component CampoTesto: Rectangle {
        id: campo

        property alias testo: dentro.text
        property string segnaposto: ""
        signal accettato()

        height: 34
        radius: Theme.Effects.radiusSM
        color: Theme.Colors.sunken
        border.width: Theme.Effects.hairline
        border.color: dentro.activeFocus ? Theme.Colors.edgeAccent
                                         : Theme.Colors.edge

        TextInput {
            id: dentro
            anchors.fill: parent
            anchors.leftMargin: Theme.Effects.space3
            anchors.rightMargin: Theme.Effects.space3
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
            selectByMouse: true
            selectionColor: Theme.Colors.selected
            onAccepted: campo.accettato()
        }

        Text {
            anchors.fill: dentro
            verticalAlignment: Text.AlignVCenter
            visible: dentro.text === "" && !dentro.activeFocus
            text: campo.segnaposto
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    component Pulsante: Rectangle {
        id: bottone

        property string testo: ""
        property bool attivo: true
        signal premuto()

        height: 34
        radius: Theme.Effects.radiusSM
        color: !bottone.attivo ? Theme.Colors.sunken
             : premi.containsMouse ? Theme.Colors.raisedHigh
             : Theme.Colors.raised
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge
        opacity: bottone.attivo ? 1 : 0.5

        Text {
            anchors.centerIn: parent
            text: bottone.testo
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }

        MouseArea {
            id: premi
            anchors.fill: parent
            hoverEnabled: true
            enabled: bottone.attivo
            cursorShape: Qt.PointingHandCursor
            onClicked: bottone.premuto()
        }
    }
}

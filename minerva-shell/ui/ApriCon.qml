import QtQuick
import "../theme" as Theme
import "../core" as Core
import "." as Ui

// ApriCon — «Con che cosa lo apro?», e per uno script anche «lo eseguo?».
//
// ── Da dove viene ──────────────────────────────────────────────────────────
//
// Giacomo faceva doppio clic su `joca.sh` — il lanciatore di un suo progetto —
// e si aprivano le PROPRIETÀ. Non era una scelta: era il ripiego che qualcuno
// aveva messo lì per il caso «non so con che cosa aprirlo», e la finestra
// delle proprietà è un posto dove si guardano i permessi e la data, non dove
// si decide che cosa fare di un file.
//
// La metà di quel difetto stava nel demone e si ripara altrove (vedi
// `minervad/lib/services/mime_database.dart`). Questa è l'altra metà: quando
// la domanda è «con che cosa?», si chiede.
//
// ── Perché sta in `ui/` e non in `files/` ─────────────────────────────────
//
// Perché il vicolo cieco era doppio. Nel gestore file si finiva nelle
// proprietà; sulla SCRIVANIA non succedeva niente del tutto —
// `menu/DesktopIcons.qml` chiamava `openDefault` e non ascoltava la risposta.
// Due posti, una finestrella sola.
//
// ── Le tre righe, in quest'ordine ─────────────────────────────────────────
//
// «Esegui nel terminale» sopra, «Apri con <il predefinito>» sotto, e l'elenco
// completo più in basso. Deciso con Giacomo il 17 agosto 2026: per uno script
// le prime due sono quello che si vuole quasi sempre, e la terza serve il
// giorno che l'editor predefinito non è quello giusto — senza, si tornerebbe
// al vicolo cieco di prima.
Rectangle {
    id: chiedi

    /// Il file va eseguito in un terminale. Chi ascolta sa quale terminale
    /// usare: non è roba di una finestrella.
    signal eseguiRichiesto(string percorso)
    /// Il file va reso eseguibile (`chmod +x`).
    signal eseguibileRichiesto(string percorso)
    /// Per conto di un altro programma (`perConto`): la scelta, o «» se si
    /// è lasciato perdere. Aprire tocca a chi ha chiesto, non a noi.
    signal sceltoPerConto(string appId)
    /// Il file va mostrato nella sua cartella, scelto.
    signal mostraRichiesto(string percorso)

    anchors.fill: parent
    color: Theme.Colors.scrim
    visible: false
    z: 40

    readonly property bool it: Core.Strings.lang === "it"

    property string percorso: ""
    property bool eseguibile: false
    property string tipo: ""
    property string predefinito: ""
    property var candidati: []
    property bool ricorda: false
    property bool aspetto: false

    /// La domanda viene dal portale (`scripts/minerva-portale`): un altro
    /// programma — Chrome che apre uno scaricato — vuole sapere con che cosa
    /// aprire il file, e lo aprirà lui. Niente «esegui» né «rendi
    /// eseguibile»: chi chiede ha chiesto un programma, non un terminale.
    property bool perConto: false

    readonly property string nome: {
        var p = String(chiedi.percorso || "");
        var taglio = p.lastIndexOf("/");
        return taglio < 0 ? p : p.substring(taglio + 1);
    }

    function nomeDi(id) {
        for (var i = 0; i < chiedi.candidati.length; i++) {
            if (chiedi.candidati[i].id === id)
                return chiedi.candidati[i].name;
        }
        return id;
    }

    function apri(percorso, eseguibile) {
        chiedi.percorso = percorso;
        chiedi.eseguibile = eseguibile === true;
        chiedi.tipo = "";
        chiedi.predefinito = "";
        chiedi.candidati = [];
        // La spunta nasce VUOTA a ogni apertura. Scelta di Giacomo: «da
        // mettere». Cambiare un'impostazione di sistema è una cosa che si fa
        // apposta, non una cosa che capita mentre si apre un file.
        chiedi.ricorda = false;
        chiedi.perConto = false;
        chiedi.aspetto = true;
        chiedi.visible = true;
        chiedi.forceActiveFocus();
        Core.Ipc.mimeDescribe(percorso);
    }

    /// La stessa domanda, fatta da un altro programma. Col file in mano i
    /// candidati li dice il demone come dappertutto; senza (un indirizzo
    /// `mailto:`) valgono quelli che ha mandato il portale.
    function apriPerConto(percorso, tipo, scelte) {
        chiedi.apri(percorso, false);
        chiedi.perConto = true;
        if (percorso === "") {
            chiedi.tipo = tipo;
            chiedi.candidati = scelte;
            chiedi.aspetto = false;
        }
    }

    // Esc chiude, come in ogni altra finestrella di Minerva. `focus` si prende
    // all'apertura: senza, i tasti vanno a chi c'era prima e la finestra
    // sembra sorda.
    focus: chiedi.visible
    Keys.onEscapePressed: chiedi.chiudi()

    /// Come in `Condividi.qml`: sulla scrivania questa finestrella vive dentro
    /// una finestra di sovrapposizione, che va spenta insieme a lei.
    signal chiuso()

    function chiudi() {
        if (chiedi.perConto && chiedi.visible) {
            chiedi.perConto = false;
            chiedi.sceltoPerConto("");
        }
        chiedi.visible = false;
        chiedi.percorso = "";
        chiedi.candidati = [];
        chiedi.chiuso();
    }

    /// Apre col programma scelto, e se richiesto se lo ricorda PRIMA di
    /// aprire: il demone risponde all'una e all'altra cosa separatamente, e
    /// chiudere la finestrella non deve poter arrivare prima della scrittura.
    function conQuesto(appId) {
        if (chiedi.ricorda && chiedi.tipo !== "")
            Core.Ipc.mimeSetDefault(chiedi.tipo, appId);
        if (chiedi.perConto) {
            chiedi.perConto = false;
            chiedi.sceltoPerConto(appId);
        } else {
            Core.Ipc.openWith(appId, [chiedi.percorso]);
        }
        chiedi.chiudi();
    }

    Connections {
        target: Core.Ipc
        function onMimeDescribed(d) {
            if (!d || d.path === "" || d.path !== chiedi.percorso)
                return;
            chiedi.tipo = d.mime || "";
            chiedi.predefinito = d.defaultApp || "";
            chiedi.candidati = d.candidates || [];
            chiedi.aspetto = false;
        }
    }

    // Il clic sul velo chiude, e prende tutti i clic che passerebbero alla
    // finestra sotto.
    MouseArea {
        anchors.fill: parent
        onClicked: chiedi.chiudi()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.Effects.space6, 520)
        height: Math.min(parent.height - Theme.Effects.space6,
                         corpo.implicitHeight + Theme.Effects.space5 * 2)
        radius: Theme.Effects.radiusMD
        color: Theme.Colors.panel
        border.width: 1
        border.color: Theme.Colors.edge

        MouseArea { anchors.fill: parent }

        Column {
            id: corpo
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.Effects.space5
            spacing: Theme.Effects.space3

            // ── Di che file si parla ─────────────────────────────────────
            Text {
                width: parent.width
                elide: Text.ElideMiddle
                text: chiedi.nome
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeMD
                font.weight: Theme.Typography.weightMedium
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: {
                    if (chiedi.aspetto)
                        return chiedi.it ? "Sto guardando…" : "Looking…";
                    var t = chiedi.tipo !== "" ? chiedi.tipo : "?";
                    if (chiedi.eseguibile)
                        t += chiedi.it ? "  ·  si può eseguire"
                                       : "  ·  can be run";
                    return t;
                }
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXS
            }

            // ── Le due righe grandi ──────────────────────────────────────
            Ui.RigaScelta {
                width: parent.width
                visible: chiedi.eseguibile
                icona: "terminal"
                testo: chiedi.it ? "Esegui nel terminale" : "Run in the terminal"
                onScelto: {
                    var p = chiedi.percorso;
                    chiedi.chiudi();
                    chiedi.eseguiRichiesto(p);
                }
            }

            // Chi non ha il permesso di esecuzione non si esegue di nascosto:
            // si dice quello che manca. Un `chmod` fatto per conto di chi ha
            // solo fatto doppio clic è una cosa che succede e non si vede.
            Ui.RigaScelta {
                width: parent.width
                visible: !chiedi.eseguibile && chiedi.tipoEseguibile
                         && !chiedi.perConto
                icona: "check"
                testo: chiedi.it ? "Rendi eseguibile" : "Make it runnable"
                nota: chiedi.it ? "Poi si potrà avviare col doppio clic"
                                : "Then a double click will start it"
                onScelto: {
                    var p = chiedi.percorso;
                    chiedi.chiudi();
                    chiedi.eseguibileRichiesto(p);
                }
            }

            Ui.RigaScelta {
                width: parent.width
                visible: chiedi.predefinito !== ""
                iconaFile: chiedi.iconaDi(chiedi.predefinito)
                icona: "document"
                testo: (chiedi.it ? "Apri con " : "Open with ")
                       + chiedi.nomeDi(chiedi.predefinito)
                onScelto: chiedi.conQuesto(chiedi.predefinito)
            }

            // ── Tutti gli altri ──────────────────────────────────────────
            Text {
                width: parent.width
                visible: chiedi.altri.length > 0
                text: chiedi.predefinito !== ""
                      ? (chiedi.it ? "oppure con un altro programma:"
                                   : "or with another program:")
                      : (chiedi.it ? "con che cosa lo apro?"
                                   : "what should open it?")
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: !chiedi.aspetto && chiedi.candidati.length === 0
                text: chiedi.it
                      ? "Nessun programma installato dichiara di saper aprire "
                        + "questo tipo di file."
                      : "No installed program declares that it can open this "
                        + "kind of file."
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            // Il file che nessuno sa aprire non deve finire in un vicolo cieco:
            // almeno si vede dov'è, e da lì si rinomina, si sposta, si butta.
            Ui.RigaScelta {
                width: parent.width
                visible: chiedi.perConto && chiedi.percorso !== ""
                         && !chiedi.aspetto && chiedi.candidati.length === 0
                icona: "folder"
                testo: chiedi.it ? "Mostra nella cartella" : "Show in folder"
                onScelto: {
                    var p = chiedi.percorso;
                    chiedi.chiudi();
                    chiedi.mostraRichiesto(p);
                }
            }

            // Avvolto in un Item perché la barra dev'essere FRATELLA del
            // Flickable, e qui il vicino di casa è una `Column`: un fratello
            // diretto diventerebbe un'altra riga della colonna.
            Item {
                width: parent.width
                height: Math.min(elenco.implicitHeight, 200)
                visible: chiedi.altri.length > 0

                Scorrimento {
                    bersaglio: elencoAltri
                    anchors {
                        right: elencoAltri.right
                        top: elencoAltri.top
                        bottom: elencoAltri.bottom
                    }
                }

                Flickable {
                    id: elencoAltri
                    anchors.fill: parent
                    clip: true
                    contentHeight: elenco.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: elenco
                        width: parent.width
                        spacing: 1

                        Repeater {
                            model: chiedi.visible ? chiedi.altri : []

                            delegate: Ui.RigaScelta {
                                required property var modelData
                                width: elenco.width
                                piccola: true
                                iconaFile: modelData.iconPath || ""
                                icona: "apps"
                                testo: modelData.name
                                onScelto: chiedi.conQuesto(modelData.id)
                            }
                        }
                    }
                }
            }

            // ── La spunta ────────────────────────────────────────────────
            Item {
                width: parent.width
                height: 26
                visible: chiedi.tipo !== "" && chiedi.candidati.length > 0

                Rectangle {
                    id: casella
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    radius: Theme.Effects.radiusXS
                    color: chiedi.ricorda ? Theme.Colors.accent : "transparent"
                    border.width: 1
                    border.color: chiedi.ricorda ? Theme.Colors.accent
                                                 : Theme.Colors.edge

                    Ui.Icon {
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        visible: chiedi.ricorda
                        name: "check"
                        color: Theme.Colors.textOnAccent
                    }
                }

                Text {
                    anchors.left: casella.right
                    anchors.leftMargin: Theme.Effects.space2
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: chiedi.it ? "Ricorda per i file di questo tipo"
                                    : "Remember for files of this kind"
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: chiedi.ricorda = !chiedi.ricorda
                }
            }

            // ── Il piede ─────────────────────────────────────────────────
            Item {
                width: parent.width
                height: 34

                Rectangle {
                    anchors.right: parent.right
                    width: 130
                    height: 34
                    radius: Theme.Effects.radiusSM
                    color: viaMouse.containsMouse ? Theme.Colors.raisedHigh
                                                  : Theme.Colors.raised
                    border.width: Theme.Effects.hairline
                    border.color: Theme.Colors.edge

                    Text {
                        anchors.centerIn: parent
                        text: chiedi.it ? "Lascia perdere" : "Never mind"
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    MouseArea {
                        id: viaMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: chiedi.chiudi()
                    }
                }
            }
        }
    }

    // ── Quello che serve alle righe di sopra ─────────────────────────────

    /// I candidati meno il predefinito, che ha già una riga sua.
    readonly property var altri: {
        var fuori = [];
        for (var i = 0; i < chiedi.candidati.length; i++) {
            if (chiedi.candidati[i].id !== chiedi.predefinito)
                fuori.push(chiedi.candidati[i]);
        }
        return fuori;
    }

    function iconaDi(id) {
        for (var i = 0; i < chiedi.candidati.length; i++) {
            if (chiedi.candidati[i].id === id)
                return chiedi.candidati[i].iconPath || "";
        }
        return "";
    }

    /// I tipi che ha senso eseguire. Non l'estensione: il tipo vero, che
    /// adesso il demone sa dire (`mime_database.dart`).
    readonly property bool tipoEseguibile: {
        var t = chiedi.tipo;
        if (t === "")
            return false;
        return t === "text/x-shellscript"
            || t === "text/x-python"
            || t === "application/x-perl"
            || t === "application/x-ruby"
            || t === "text/x-lua"
            || t === "application/x-executable"
            || t === "application/x-pie-executable"
            || t === "application/x-sharedlib";
    }
}

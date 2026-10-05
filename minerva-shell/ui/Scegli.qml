import QtQuick
import Quickshell

import "../theme" as Theme
import "../core" as Core

// Scegli — un piccolo gestore file per scegliere una cartella o un file.
//
// ── Perché non il selettore di sistema ─────────────────────────────────────
//
// Perché il selettore «di sistema» non esiste: esiste quello di GTK e quello di
// Qt, e quale dei due esca dipende dal portale installato. Su una scrivania
// nostra vorrebbe dire una finestra con un altro font, altri colori e altri
// gesti che spunta in mezzo ai nostri — e su una scrivania nuova, quello che
// non risponde affatto. Vedi il portachiavi di Chrome, rotto per mesi
// esattamente così.
//
// E perché ce l'abbiamo già: il demone sa elencare cartelle, dischi e posti da
// quando c'è il gestore file. Qui non si aggiunge nessuna capacità, si mette
// una finestra piccola davanti a quelle che ci sono.
//
// ── Perché sta in `ui/` e non dentro la Custodia ───────────────────────────
//
// Perché «scegli una cartella» serve alla Custodia adesso, all'aggiunta di un
// progetto subito dopo, e a ogni «salva con nome» che scriveremo. Scritto
// dentro un'app diventa il pezzo che si copia-incolla, e da lì in poi ce ne
// sono tre versioni che si comportano in tre modi.
//
//     Ui.Scegli {
//         anchors.fill: parent
//         soloCartelle: true
//         onScelto: function (percorso) { … }
//     }
//
// Si mostra chiamando `apri(percorsoDiPartenza)`, e si nasconde da sola.
Item {
    id: scegli

    /// Se vero, i file si vedono ma non si scelgono: sono lì solo per capire
    /// dove si è. Una cartella vuota e una cartella piena di roba si
    /// distinguono, e senza i file sembrano uguali.
    property bool soloCartelle: true

    property bool it: Core.Strings.lang === "it"

    /// Il titolo della finestrella: chi la apre sa perché, chi la guarda no.
    property string titolo: ""

    signal scelto(string percorso)
    signal annullato()

    visible: false
    z: 100

    property string dove: ""
    property string selezionato: ""
    property var voci: []
    property var posti: []
    property var dischi: []
    property string errore: ""

    function apri(daDove) {
        scegli.selezionato = "";
        scegli.errore = "";
        scegli.visible = true;
        Core.Ipc.fsPlaces();
        Core.Ipc.fsVolumes();
        scegli.vai(daDove && daDove !== "" ? daDove : scegli.casa());
    }

    function casa() {
        return String(Quickshell.env("HOME") || "/");
    }

    function vai(percorso) {
        scegli.dove = String(percorso);
        scegli.selezionato = "";
        scegli.errore = "";
        Core.Ipc.fsList(scegli.dove, false, "scelta");
    }

    function su() {
        if (scegli.dove === "/" || scegli.dove === "") return;
        var i = scegli.dove.lastIndexOf("/");
        scegli.vai(i <= 0 ? "/" : scegli.dove.substring(0, i));
    }

    /// Quello che si porta a casa: la voce selezionata, o — se non se n'è
    /// scelta nessuna — la cartella in cui si è. È la scorciatoia che tutti si
    /// aspettano: entri dove vuoi e premi Scegli, senza dover anche cliccare
    /// il nome della cartella dentro sé stessa.
    readonly property string risultato:
        scegli.selezionato !== "" ? scegli.selezionato : scegli.dove

    Connections {
        target: Core.Ipc

        function onFileListingReceived(l) {
            // Il gestore file usa lo stesso canale: senza questo confronto una
            // finestra riempirebbe l'elenco dell'altra.
            if (!l || String(l.pane) !== "scelta") return;
            if (l.error && String(l.error) !== "") {
                scegli.errore = String(l.error);
                scegli.voci = [];
                return;
            }
            scegli.errore = "";
            var dentro = l.entries || [];
            var fuori = [];
            // Le cartelle prima, sempre: qui si naviga, non si legge un
            // elenco. Un file in mezzo alle cartelle è un ostacolo.
            for (var i = 0; i < dentro.length; i++)
                if (dentro[i].isDir) fuori.push(dentro[i]);
            if (!scegli.soloCartelle)
                for (var j = 0; j < dentro.length; j++)
                    if (!dentro[j].isDir) fuori.push(dentro[j]);
            scegli.voci = fuori;
        }

        function onPlacesReceived(p) {
            if (!p) return;
            var tutti = p.places || p || [];
            var fuori = [];
            for (var i = 0; i < tutti.length; i++) {
                if (!tutti[i].nellaBarra) continue;
                // Il Cestino sta nella barra del gestore file, dove serve.
                // Qui no: nessuno vuole scegliere il cestino come posto dove
                // mettere qualcosa, e offrirglielo è offrire un errore.
                if (String(tutti[i].kind) === "trash") continue;
                fuori.push(tutti[i]);
            }
            scegli.posti = fuori;
        }

        function onVolumesReceived(v) {
            if (!v) return;
            var l = v.volumes || [];
            var fuori = [];
            for (var i = 0; i < l.length; i++)
                if (l[i].mounted && String(l[i].mountPoint) !== "")
                    fuori.push(l[i]);
            scegli.dischi = fuori;
        }
    }

    // ── Il velo ──────────────────────────────────────────────────────────

    Rectangle {
        anchors.fill: parent
        color: Theme.Colors.scrim
        MouseArea {
            anchors.fill: parent
            onClicked: { scegli.visible = false; scegli.annullato(); }
        }
    }

    // ── La finestrella ───────────────────────────────────────────────────

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(720, scegli.width - 48)
        height: Math.min(480, scegli.height - 48)
        radius: Theme.Effects.radiusLG
        color: Theme.Colors.panel
        border.width: 1
        border.color: Theme.Colors.edge

        MouseArea { anchors.fill: parent }

        // ── Il percorso, e il tasto per salire ───────────────────────────
        Item {
            id: cima
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 56

            SpineButton {
                id: suSu
                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space3
                anchors.verticalCenter: parent.verticalCenter
                width: 32; height: 32
                enabled: scegli.dove !== "/"
                opacity: enabled ? 1 : 0.35
                onClicked: scegli.su()
                content: Icon {
                    name: "back"
                    width: 15; height: 15
                    color: Theme.Colors.text
                }
            }

            Column {
                anchors.left: suSu.right
                anchors.leftMargin: Theme.Effects.space3
                anchors.right: parent.right
                anchors.rightMargin: Theme.Effects.space3
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    textFormat: Text.PlainText
                    visible: scegli.titolo !== ""
                    text: scegli.titolo
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeMD
                    font.weight: Theme.Typography.weightSemiBold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideLeft
                    text: scegli.dove
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.Colors.edge
            }
        }

        // ── I posti, a sinistra ──────────────────────────────────────────
        Rectangle {
            id: barra
            anchors.top: cima.bottom
            anchors.left: parent.left
            anchors.bottom: fondo.top
            width: 172
            color: Theme.Colors.sunken

            Scorrimento {
                bersaglio: colonnaPosti
                anchors {
                    right: colonnaPosti.right
                    top: colonnaPosti.top
                    bottom: colonnaPosti.bottom
                }
            }

            Flickable {
                id: colonnaPosti
                anchors.fill: parent
                anchors.margins: Theme.Effects.space2
                contentHeight: elencoPosti.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: elencoPosti
                    width: parent.width
                    spacing: 1

                    Component {
                        id: unPosto
                        Rectangle {
                            property string percorso: ""
                            property string etichetta: ""
                            property string segno: "folder"
                            width: elencoPosti.width
                            height: 32
                            radius: Theme.Effects.radiusMD
                            color: scegli.dove === percorso
                                   ? Theme.Colors.selected
                                   : (mp.containsMouse ? Theme.Colors.hover
                                                       : "transparent")

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.Effects.space2
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.Effects.space2

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: segno
                                    width: 14; height: 14
                                    color: Theme.Colors.textMuted
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 14
                                           - Theme.Effects.space2 * 2
                                    elide: Text.ElideRight
                                    text: etichetta
                                    color: Theme.Colors.text
                                    font.family: Theme.Typography.fontDisplay
                                    font.pixelSize: Theme.Typography.sizeSM
                                }
                            }

                            MouseArea {
                                id: mp
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: scegli.vai(percorso)
                            }
                        }
                    }

                    Loader {
                        sourceComponent: unPosto
                        onLoaded: {
                            item.percorso = scegli.casa();
                            item.etichetta = scegli.it ? "Casa" : "Home";
                            item.segno = "home";
                        }
                    }

                    Repeater {
                        model: scegli.posti
                        Loader {
                            sourceComponent: unPosto
                            onLoaded: {
                                item.percorso = modelData.path;
                                item.etichetta = modelData.name;
                                item.segno = "folder";
                            }
                        }
                    }

                    Item { width: 1; height: Theme.Effects.space2 }

                    Repeater {
                        model: scegli.dischi
                        Loader {
                            sourceComponent: unPosto
                            onLoaded: {
                                item.percorso = modelData.mountPoint;
                                item.etichetta = modelData.name;
                                item.segno = modelData.removable
                                             ? "chiavetta" : "disco";
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: Theme.Colors.edge
            }
        }

        // ── Le cartelle, a destra ────────────────────────────────────────
        Scorrimento {
            bersaglio: colonnaCartelle
            anchors {
                right: colonnaCartelle.right
                rightMargin: Theme.Effects.space1
                top: colonnaCartelle.top
                bottom: colonnaCartelle.bottom
            }
        }

        Flickable {
            id: colonnaCartelle
            anchors.top: cima.bottom
            anchors.left: barra.right
            anchors.right: parent.right
            anchors.bottom: fondo.top
            contentHeight: righe.implicitHeight + Theme.Effects.space2 * 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: righe
                x: Theme.Effects.space2
                y: Theme.Effects.space2
                width: parent.width - Theme.Effects.space2 * 2
                spacing: 1

                Text {
                    visible: scegli.errore !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: scegli.errore
                    color: Theme.Colors.danger
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Text {
                    visible: scegli.errore === "" && scegli.voci.length === 0
                    text: scegli.it ? "Qui non c'è niente."
                                    : "Nothing here."
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Repeater {
                    model: scegli.voci

                    Rectangle {
                        width: righe.width
                        height: 32
                        radius: Theme.Effects.radiusMD
                        // Un file, quando si cercano cartelle, si vede e non si
                        // prende: serve a capire dove si è.
                        readonly property bool prendibile:
                            modelData.isDir || !scegli.soloCartelle
                        color: scegli.selezionato === modelData.path
                               ? Theme.Colors.selected
                               : (mv.containsMouse && prendibile
                                  ? Theme.Colors.hover : "transparent")

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.Effects.space2
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.Effects.space2

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: modelData.isDir ? "folder" : "document"
                                width: 14; height: 14
                                color: prendibile ? Theme.Colors.textMuted
                                                  : Theme.Colors.textFaint
                            }
                            Text {
                                textFormat: Text.PlainText
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 14
                                       - Theme.Effects.space2 * 2
                                elide: Text.ElideRight
                                text: modelData.name
                                color: prendibile ? Theme.Colors.text
                                                  : Theme.Colors.textFaint
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                            }
                        }

                        MouseArea {
                            id: mv
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: prendibile
                            cursorShape: Qt.PointingHandCursor
                            onClicked: scegli.selezionato = modelData.path
                            // Doppio clic per entrare: è quello che fa il
                            // gestore file, e due gesti diversi per la stessa
                            // cosa in due finestre della stessa scrivania sono
                            // il modo più veloce per farla sembrare di altri.
                            onDoubleClicked: {
                                if (modelData.isDir) scegli.vai(modelData.path);
                            }
                        }
                    }
                }
            }
        }

        // ── I due pulsanti ───────────────────────────────────────────────
        Item {
            id: fondo
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 60

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: Theme.Colors.edge
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space4
                anchors.right: bottoni.left
                anchors.rightMargin: Theme.Effects.space3
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideLeft
                text: scegli.risultato
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXS
            }

            Row {
                id: bottoni
                anchors.right: parent.right
                anchors.rightMargin: Theme.Effects.space3
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.Effects.space2

                SpineButton {
                    height: 36
                    horizontalPadding: Theme.Effects.space4
                    onClicked: {
                        scegli.visible = false;
                        scegli.annullato();
                    }
                    content: Text {
                        text: scegli.it ? "Lascia stare" : "Never mind"
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeMD
                    }
                }

                SpineButton {
                    height: 36
                    horizontalPadding: Theme.Effects.space4
                    onClicked: {
                        scegli.visible = false;
                        scegli.scelto(scegli.risultato);
                    }
                    content: Text {
                        text: scegli.it ? "Scegli" : "Choose"
                        color: Theme.Colors.accent
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeMD
                        font.weight: Theme.Typography.weightSemiBold
                    }
                }
            }
        }
    }
}

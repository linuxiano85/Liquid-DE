import QtQuick
import Quickshell
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// DoppioniFoto — Le fotografie che ci sono due volte.
//
// Il demone sapeva già trovarle (`foto/doppioni.dart`: dimensione, estremità,
// file intero) e sapeva già buttarle nel cestino con tre rifiuti che rendono
// «butta tutte le copie» una cosa non esprimibile. Mancava solo chi glielo
// chiedesse (5 ottobre 2026).
//
// Qui si sceglie, per ogni gruppo, quale copia tenere — di serie la prima,
// che il demone mette davanti — e le altre vanno nel CESTINO, da cui si
// recuperano. Niente si cancella davvero da questa finestra.
Rectangle {
    id: pannello

    readonly property bool it: Core.Strings.lang === "it"
    signal chiuso()

    color: Theme.Colors.scrim

    property var gruppi: []
    /// La copia da tenere per ogni gruppo, per chiave (il primo percorso).
    property var scelte: ({})
    /// I gruppi mandati al cestino e non ancora tornati, per chiave.
    property var inViaggio: ({})
    property bool cercando: false
    property string errore: ""
    property int buttate: 0
    property real liberati: 0
    /// Il primo clic su «tutti» chiede conferma; il secondo butta. La
    /// conferma scade: un «sicuro?» lasciato lì non deve valere domani.
    property bool confermaTutti: false
    Timer {
        running: pannello.confermaTutti
        interval: 4000
        onTriggered: pannello.confermaTutti = false
    }

    readonly property string casa: Quickshell.env("HOME") || ""
    function breve(p) {
        var s = String(p);
        return pannello.casa !== "" && s.indexOf(pannello.casa + "/") === 0
            ? "~/" + s.substring(pannello.casa.length + 1) : s;
    }
    function chiave(g) { return String(g.percorsi[0]); }
    function tenuta(g) {
        var c = pannello.scelte[pannello.chiave(g)];
        return c !== undefined ? c : String(g.percorsi[0]);
    }
    readonly property real inPiu: {
        var t = 0;
        for (var i = 0; i < pannello.gruppi.length; i++)
            t += pannello.gruppi[i].byteInPiu || 0;
        return t;
    }

    function apri() {
        pannello.visible = true;
        pannello.errore = "";
        pannello.gruppi = [];
        pannello.scelte = ({});
        pannello.inViaggio = ({});
        pannello.buttate = 0;
        pannello.liberati = 0;
        pannello.confermaTutti = false;
        pannello.cercando = true;
        Core.Ipc.fotoCercaDoppioni();
    }

    function chiudi() {
        pannello.visible = false;
        // Il demone le ha già tolte dal catalogo: la galleria lo rilegge.
        if (pannello.buttate > 0)
            Core.Ipc.fotoChiediPanoramica();
        pannello.chiuso();
    }

    function scegli(g, percorso) {
        var s = Object.assign({}, pannello.scelte);
        s[pannello.chiave(g)] = String(percorso);
        pannello.scelte = s;
    }

    function butta(g) {
        var k = pannello.chiave(g);
        if (pannello.inViaggio[k])
            return;
        var tieni = pannello.tenuta(g);
        var via = g.percorsi.filter(function (p) { return String(p) !== tieni; });
        if (via.length === 0)
            return;
        var v = Object.assign({}, pannello.inViaggio);
        v[k] = { "tieni": tieni, "quante": via.length, "byte": g.byteInPiu || 0 };
        pannello.inViaggio = v;
        Core.Ipc.fotoScartaDoppioni(tieni, via);
    }

    function buttaTutti() {
        if (!pannello.confermaTutti) {
            pannello.confermaTutti = true;
            return;
        }
        pannello.confermaTutti = false;
        for (var i = 0; i < pannello.gruppi.length; i++)
            pannello.butta(pannello.gruppi[i]);
    }

    Connections {
        target: Core.Ipc
        function onFotoDoppioni(p) {
            if (!pannello.visible)
                return;
            pannello.cercando = false;
            if (!p || p.ok !== true) {
                pannello.errore = p && p.error ? p.error
                                 : (pannello.it ? "Non sono riuscito a cercarle." : "Couldn't look for them.");
                return;
            }
            pannello.gruppi = p.gruppi || [];
        }
        function onFotoDoppioniScartati(p) {
            if (!p || !pannello.visible)
                return;
            // L'esito porta la copia TENUTA: è quella che dice di quale gruppo
            // si parla, perché le risposte possono tornare fuori ordine.
            var k = "";
            for (var c in pannello.inViaggio)
                if (pannello.inViaggio[c].tieni === p.tenuta) k = c;
            var v = Object.assign({}, pannello.inViaggio);
            var partito = k !== "" ? v[k] : null;
            if (k !== "")
                delete v[k];
            pannello.inViaggio = v;
            if (p.ok !== true) {
                pannello.errore = p.error || (pannello.it ? "Non le ho buttate." : "Not thrown away.");
                return;
            }
            if (partito) {
                pannello.buttate += partito.quante;
                pannello.liberati += partito.byte;
            }
            pannello.gruppi = pannello.gruppi.filter(function (g) {
                return pannello.chiave(g) !== k;
            });
        }
    }

    // Prende i clic: sotto c'è la galleria.
    MouseArea { anchors.fill: parent; onClicked: pannello.chiudi() }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.Effects.space6, 720)
        height: Math.min(parent.height - Theme.Effects.space6,
                         colonna.implicitHeight + Theme.Effects.space5 * 2)
        radius: Theme.Effects.radiusLG
        color: Theme.Colors.panel
        border.width: 1
        border.color: Theme.Colors.edge
        clip: true

        MouseArea { anchors.fill: parent }

        Flickable {
            id: scorre
            anchors.fill: parent
            anchors.margins: Theme.Effects.space5
            contentHeight: colonna.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: colonna
                width: parent.width
                spacing: Theme.Effects.space3

                Text {
                    width: parent.width
                    text: pannello.it ? "Foto doppie" : "Duplicate photos"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeLG
                    font.weight: Theme.Typography.weightSemiBold
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    text: pannello.cercando
                          ? (pannello.it ? "Confronto le foto: prima la misura, poi il contenuto…"
                                         : "Comparing photos: size first, then content…")
                          : pannello.gruppi.length === 0
                            ? (pannello.buttate > 0
                               ? (pannello.it ? "Fatto: " + pannello.buttate + " copie nel cestino, "
                                                + Core.Formato.peso(pannello.liberati) + " liberati."
                                              : "Done: " + pannello.buttate + " copies in the trash, "
                                                + Core.Formato.peso(pannello.liberati) + " freed.")
                               : (pannello.it ? "Nessuna foto doppia." : "No duplicate photos."))
                            : (pannello.it
                               ? pannello.gruppi.length + " foto ci sono più volte: "
                                 + Core.Formato.peso(pannello.inPiu) + " in più. Tocca la copia da tenere; le altre vanno nel cestino."
                               : pannello.gruppi.length + " photos appear more than once: "
                                 + Core.Formato.peso(pannello.inPiu) + " extra. Tap the copy to keep; the others go to the trash.")
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Text {
                    width: parent.width
                    visible: pannello.errore !== ""
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    text: pannello.errore
                    color: Theme.Colors.danger
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Repeater {
                    model: pannello.gruppi
                    delegate: Rectangle {
                        id: gruppo
                        required property var modelData
                        readonly property bool partito:
                            pannello.inViaggio[pannello.chiave(gruppo.modelData)] !== undefined
                        width: colonna.width
                        height: dentro.implicitHeight + Theme.Effects.space3 * 2
                        radius: Theme.Effects.radiusMD
                        color: Theme.Colors.raised
                        opacity: gruppo.partito ? 0.5 : 1

                        Column {
                            id: dentro
                            anchors.fill: parent
                            anchors.margins: Theme.Effects.space3
                            spacing: Theme.Effects.space2

                            Flow {
                                width: parent.width
                                spacing: Theme.Effects.space2
                                Repeater {
                                    model: gruppo.modelData.percorsi
                                    delegate: Copia {
                                        required property var modelData
                                        percorso: String(modelData)
                                        tenuta: pannello.tenuta(gruppo.modelData) === String(modelData)
                                        onScelta: pannello.scegli(gruppo.modelData, modelData)
                                    }
                                }
                            }

                            Item {
                                width: parent.width
                                height: 30
                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (pannello.it ? "Libera " : "Frees ")
                                          + Core.Formato.peso(gruppo.modelData.byteInPiu || 0)
                                    color: Theme.Colors.textFaint
                                    font.family: Theme.Typography.fontDisplay
                                    font.pixelSize: Theme.Typography.sizeXS
                                }
                                Ui.SpineButton {
                                    anchors.right: parent.right
                                    height: 30
                                    horizontalPadding: Theme.Effects.space3
                                    enabled: !gruppo.partito
                                    onClicked: pannello.butta(gruppo.modelData)
                                    content: Text {
                                        text: pannello.it ? "Le altre nel cestino" : "Others to the trash"
                                        color: Theme.Colors.accent
                                        font.family: Theme.Typography.fontDisplay
                                        font.pixelSize: Theme.Typography.sizeSM
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 36

                    Ui.SpineButton {
                        anchors.left: parent.left
                        height: 36
                        horizontalPadding: Theme.Effects.space4
                        visible: pannello.gruppi.length > 1
                        onClicked: pannello.buttaTutti()
                        content: Text {
                            text: pannello.confermaTutti
                                  ? (pannello.it ? "Sicuro? Tocca di nuovo" : "Sure? Tap again")
                                  : (pannello.it ? "Tutte le copie in più nel cestino" : "All extra copies to the trash")
                            color: pannello.confermaTutti ? Theme.Colors.danger : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeMD
                        }
                    }

                    Ui.SpineButton {
                        anchors.right: parent.right
                        height: 36
                        horizontalPadding: Theme.Effects.space4
                        onClicked: pannello.chiudi()
                        content: Text {
                            text: pannello.it ? "Fatto" : "Done"
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeMD
                        }
                    }
                }
            }
        }
    }

    /// Una copia: la miniatura, dove sta, e il segno di quella che resta.
    component Copia: Rectangle {
        id: copia
        property string percorso: ""
        property bool tenuta: false
        signal scelta()

        width: 150
        height: 150 + percorsoTesto.implicitHeight + 6
        radius: Theme.Effects.radiusSM
        color: "transparent"
        border.width: 2
        border.color: copia.tenuta ? Theme.Colors.accent
                    : copiaArea.containsMouse ? Theme.Colors.edge : "transparent"

        Image {
            id: foto
            x: 3; y: 3
            width: copia.width - 6
            height: 144
            source: copia.percorso !== "" ? "file://" + copia.percorso : ""
            sourceSize.width: 288
            sourceSize.height: 288
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            clip: true
        }
        // Un video, o un formato che Qt non apre: resta il posto.
        Rectangle {
            visible: foto.status !== Image.Ready
            anchors.fill: foto
            color: Theme.Colors.sunken
            Ui.Icon {
                anchors.centerIn: parent
                width: 28; height: 28
                name: "image"
                color: Theme.Colors.textFaint
            }
        }
        Rectangle {
            visible: copia.tenuta
            anchors.top: foto.top
            anchors.left: foto.left
            anchors.margins: 6
            width: tieniTesto.implicitWidth + 12
            height: 20
            radius: 10
            color: Theme.Colors.accent
            Text {
                id: tieniTesto
                anchors.centerIn: parent
                text: Core.Strings.lang === "it" ? "Tengo questa" : "Keep this"
                color: Theme.Colors.textOnAccent
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: 10
                font.weight: Theme.Typography.weightMedium
            }
        }
        Text {
            id: percorsoTesto
            anchors.top: foto.bottom
            anchors.topMargin: 3
            x: 3
            width: copia.width - 6
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
            text: pannello.breve(copia.percorso)
            color: copia.tenuta ? Theme.Colors.text : Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
        }
        MouseArea {
            id: copiaArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: copia.scelta()
        }
    }
}

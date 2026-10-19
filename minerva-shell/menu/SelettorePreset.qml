import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// SelettorePreset — Cambiare preset al volo: Liquid, Minerva, Mac, Windows 11,
// Libero. Super+P, oppure la voce «Preset» nel Centro.
//
// ── Perché esiste ──────────────────────────────────────────────────────────
//
// Il manutentore, 11 ottobre 2026: «un layout switcher che possa fare cambiare
// velocemente preset da Linux a Windows… una combinazione tasti per vedere
// una finestra come isola, e sceglierlo sia da tastiera che con il mouse». Il
// cambio c'era solo in Impostazioni → Aspetto, tre clic e una finestra da
// aprire per una cosa che si vuole fare in un secondo.
//
// ── Perché una superficie a sé e non dentro l'Isola ────────────────────────
//
// Ha la forma dell'Isola — una capsula in alto che si allarga a molla — ma è
// un'altra superficie: nel preset Windows l'Isola non c'è, e il selettore
// deve esserci in tutti i preset, compreso quello da cui si vuole uscire.
//
// ── Tastiera e mouse ───────────────────────────────────────────────────────
//
//     ← → , Tab, Maiusc+Tab   scorrono
//     1 … 5                    scelgono quello e lo applicano
//     Invio, Spazio            applicano quello evidenziato
//     Esc, clic fuori          chiudono senza cambiare niente
//     Super+P di nuovo         passa al successivo, come Alt+Tab
//
// Il passaggio del mouse evidenzia, il clic applica.
PanelWindow {
    id: sel

    /// Il preset applicato, per chi vuole dirlo (l'OSD della shell).
    signal scelto(string nome, string etichetta)

    property bool aperto: false
    property bool mostrato: false
    /// Quale scheda è evidenziata.
    property int indice: 0

    readonly property var elenco: Core.DesktopStyle.elenco
    readonly property bool it: Core.Strings.lang === "it"

    // ── Le misure, con un nome ───────────────────────────────────────────
    readonly property int schedaLarga: 184
    readonly property int schedaAlta: 176
    readonly property int spazioSchede: Theme.Effects.space3
    readonly property int margine: Theme.Effects.space5
    readonly property int titoloAlto: 34
    readonly property int distanzaDalBordo: 14
    /// La capsula chiusa: la misura da cui parte e a cui torna.
    readonly property int capsulaLarga: 220
    readonly property int capsulaAlta: 36

    readonly property int largaAperta: elenco.length * schedaLarga
                                       + (elenco.length - 1) * spazioSchede + 2 * margine
    readonly property int altaAperta: titoloAlto + schedaAlta + 2 * margine

    visible: sel.mostrato
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    WlrLayershell.namespace: "liquid-preset"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: sel.aperto ? WlrKeyboardFocus.Exclusive
                                            : WlrKeyboardFocus.None

    function indiceAttuale() {
        for (var i = 0; i < sel.elenco.length; i++) {
            if (sel.elenco[i].id === Core.DesktopStyle.attuale)
                return i;
        }
        return 0;
    }

    function apri() {
        // Si parte dal preset in uso: Invio subito non cambia niente, e una
        // freccia porta al vicino.
        sel.indice = sel.indiceAttuale();
        sel.mostrato = true;
        sel.aperto = true;
        spegni.stop();
        tasti.forceActiveFocus();
    }

    function chiudi() {
        sel.aperto = false;
        spegni.restart();
    }

    /// Super+P: apre, e se è già aperto passa al successivo.
    function commuta() {
        if (sel.aperto)
            sel.muovi(1);
        else
            sel.apri();
    }

    function muovi(passo) {
        var n = sel.elenco.length;
        sel.indice = ((sel.indice + passo) % n + n) % n;
    }

    function conferma() {
        var v = sel.elenco[sel.indice];
        sel.chiudi();
        if (!v || v.id === Core.DesktopStyle.attuale)
            return;
        Core.DesktopStyle.applica(v.id);
        sel.scelto(v.id, v.nome);
    }

    function scegli(i) {
        if (i < 0 || i >= sel.elenco.length)
            return;
        sel.indice = i;
        sel.conferma();
    }

    // Dopo la chiusura la superficie resta il tempo dell'animazione, poi si
    // toglie: una superficie a schermo intero sul piano più alto, anche
    // trasparente, è lavoro per il compositore a ogni fotogramma.
    Timer {
        id: spegni
        interval: Theme.Motion.liquido ? 450 : 0
        onTriggered: if (!sel.aperto) sel.mostrato = false
    }

    // Il clic fuori chiude.
    MouseArea {
        anchors.fill: parent
        enabled: sel.aperto
        onPressed: sel.chiudi()
    }

    Item {
        id: tasti
        focus: sel.aperto
        Keys.onPressed: function (e) {
            switch (e.key) {
            case Qt.Key_Right:
            case Qt.Key_Tab:
                sel.muovi(1);
                break;
            case Qt.Key_Left:
            case Qt.Key_Backtab:
                sel.muovi(-1);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                sel.conferma();
                break;
            case Qt.Key_Escape:
                sel.chiudi();
                break;
            default:
                if (e.key >= Qt.Key_1 && e.key < Qt.Key_1 + sel.elenco.length) {
                    sel.scegli(e.key - Qt.Key_1);
                    break;
                }
                return;
            }
            e.accepted = true;
        }
    }

    // ── La capsula ───────────────────────────────────────────────────────
    Rectangle {
        id: capsula

        readonly property bool molle: Theme.Motion.liquido && sel.mostrato

        anchors.horizontalCenter: parent.horizontalCenter
        y: sel.distanzaDalBordo
        width: sel.aperto ? Math.min(sel.largaAperta, parent.width - 2 * sel.margine)
                          : sel.capsulaLarga
        height: sel.aperto ? sel.altaAperta : sel.capsulaAlta
        radius: Math.min(height / 2, Theme.Effects.radiusLG)
        opacity: sel.aperto ? 1 : 0
        clip: true
        color: Qt.rgba(Theme.Colors.panel.r, Theme.Colors.panel.g, Theme.Colors.panel.b,
                       Math.max(Theme.Colors.panel.a, 0.98))
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge

        Behavior on width { enabled: capsula.molle; SpringAnimation { spring: Theme.Motion.molla * 0.7; damping: 0.38 } }
        Behavior on height { enabled: capsula.molle; SpringAnimation { spring: Theme.Motion.molla * 0.7; damping: 0.38 } }
        Behavior on opacity { NumberAnimation { duration: sel.aperto ? 90 : 380; easing.type: Easing.InQuad } }

        // I clic dentro la capsula non arrivano al «fuori» che chiude.
        MouseArea { anchors.fill: parent }

        Text {
            id: titolo
            x: sel.margine
            y: sel.margine - 4
            height: sel.titoloAlto
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: sel.it ? "Preset della scrivania" : "Desktop preset"
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeMD
            font.weight: Theme.Typography.weightMedium
            opacity: sel.aperto ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: sel.aperto ? 240 : 60 } }
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: sel.margine
            anchors.verticalCenter: titolo.verticalCenter
            textFormat: Text.PlainText
            text: sel.it ? "← → scegli · Invio applica · Esc chiudi"
                         : "← → choose · Enter apply · Esc close"
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
            opacity: sel.aperto ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: sel.aperto ? 240 : 60 } }
        }

        Row {
            id: schede
            x: sel.margine
            y: sel.margine + sel.titoloAlto
            spacing: sel.spazioSchede
            opacity: sel.aperto ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: sel.aperto ? 260 : 60 } }

            Repeater {
                model: sel.elenco

                delegate: Rectangle {
                    id: scheda
                    required property var modelData
                    required property int index

                    // Il nome serve alle prove, per trovare la scheda sullo schermo.
                    objectName: "presetScheda-" + scheda.modelData.id
                    readonly property bool evidenziata: sel.indice === scheda.index
                    readonly property bool attiva: Core.DesktopStyle.attuale === scheda.modelData.id

                    width: sel.schedaLarga
                    height: sel.schedaAlta
                    radius: Theme.Effects.radiusMD
                    color: scheda.evidenziata ? Qt.alpha(Theme.Colors.accent, 0.16)
                                              : Theme.Colors.raised
                    border.width: scheda.evidenziata ? 2 : Theme.Effects.hairline
                    border.color: scheda.evidenziata ? Theme.Colors.accent : Theme.Colors.edge
                    Behavior on color { ColorAnimation { duration: Theme.Motion.quick } }

                    Ui.SchemaPreset {
                        id: schema
                        x: (scheda.width - width) / 2
                        y: Theme.Effects.space3
                        quale: scheda.modelData.id
                    }

                    Text {
                        id: nome
                        x: Theme.Effects.space3
                        y: schema.y + schema.height + Theme.Effects.space2
                        width: scheda.width - 2 * Theme.Effects.space3
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: (scheda.index + 1) + "  " + scheda.modelData.nome
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                        font.weight: Theme.Typography.weightMedium
                    }

                    Text {
                        x: nome.x
                        y: nome.y + nome.height + 2
                        width: nome.width
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: scheda.attiva ? (sel.it ? "In uso" : "In use") : scheda.modelData.breve
                        color: scheda.attiva ? Theme.Colors.accent : Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXS
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: sel.indice = scheda.index
                        onClicked: sel.scegli(scheda.index)
                    }
                }
            }
        }
    }

    // Il disegnino di ogni preset è `ui/SchemaPreset.qml`.
}

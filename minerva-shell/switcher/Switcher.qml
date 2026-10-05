import QtQuick
import Quickshell
import Quickshell.Wayland

import "../theme" as Theme
import "../core" as Core

// Switcher — Alt+Tab.
//
// ── Perché è la prima cosa che manca ───────────────────────────────────────
//
// Chi arriva da Windows non «impara» Alt+Tab: ce l'ha nelle dita. È il gesto
// che si fa venti volte al giorno senza guardare, e in Minerva non faceva
// niente — nemmeno un rumore. Non è una funzione mancante: è una scrivania
// che, nel gesto più automatico che esista, non risponde.
//
// ── Icone e non anteprime, ed è una scelta ─────────────────────────────────
//
// Quickshell sa catturare il contenuto di una finestra (`ScreencopyView`), e
// le miniature dal vivo sono la cosa che si vede nei video. Qui ci sono le
// icone, per tre motivi in fila:
//
//  · le miniature di sei finestre sono sei catture continue mentre si tiene
//    premuto un tasto — su un portatile con una Iris Xe si sente;
//  · a mezzo secondo di pressione una miniatura di un terminale e una di un
//    altro terminale sono due rettangoli scuri. L'icona si riconosce PRIMA di
//    leggere;
//  · ⌘-Tab sul Mac è a icone da vent'anni, e nessuno lo cambia.
//
// ── Come si comporta ───────────────────────────────────────────────────────
//
// L'ordine è quello di Windows e del Mac: le finestre in ordine di ULTIMO USO,
// non di apertura. Il primo Alt+Tab sceglie già la penultima finestra — cioè
// «torna a quella di prima», che è quello che si vuole nove volte su dieci — e
// da lì ogni Tab avanza. Si conferma lasciando Alt, si annulla con Esc.
//
// Il fuoco della tastiera qui NON serve: i tasti li riceve il compositore, che ce li
// gira come scorciatoie globali. Una superficie che si prende la tastiera
// mentre si tiene premuto Alt se la porterebbe via a chi la stava usando.
PanelWindow {
    id: sel

    /// Le finestre fra cui scegliere, dalla più recente alla più vecchia.
    property var elenco: []
    /// Quale è puntata adesso.
    property int scelto: 0
    /// Aperto.
    property bool attivo: false

    anchors { top: true; bottom: true; left: true; right: true }
    visible: sel.attivo
    color: "transparent"

    WlrLayershell.namespace: "minerva-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Solo il riquadro riceve i clic: il resto dello schermo resta della
    // finestra che c'è sotto, che magari si sta ancora guardando.
    mask: Region { item: cornice }

    // ── L'elenco ─────────────────────────────────────────────────────────

    /// Ricostruisce l'ordine: le finestre per ultimo uso, senza le ridotte a
    /// icona di nessuno e senza le nostre superfici.
    function raccogli() {
        var tutte = Core.Windows.all || [];
        var buone = [];
        for (var i = 0; i < tutte.length; i++) {
            var w = tutte[i];
            if (!w.address || w.address === "")
                continue;
            // Le finestre ridotte a icona ci vanno: «torna a quella che avevo
            // messo via» è metà del motivo per cui si preme Alt+Tab.
            buone.push(w);
        }
        // `stack` è `focusHistoryID`: 0 è quella attiva, 1 la precedente.
        buone.sort(function (a, b) { return (a.stack || 0) - (b.stack || 0); });
        return buone;
    }

    /// Apre, o avanza se è già aperto.
    function avanti() { sel._muovi(1); }
    function indietro() { sel._muovi(-1); }

    function _muovi(passo) {
        if (!sel.attivo) {
            var e = sel.raccogli();
            // Con una finestra sola non c'è niente fra cui scegliere, e un
            // riquadro che compare per dire «c'è questa» è un fastidio.
            if (e.length < 2)
                return;
            sel.elenco = e;
            // Il primo Alt+Tab punta la PENULTIMA, non la prima: «torna a
            // quella di prima» è quello che si vuole nove volte su dieci.
            sel.scelto = passo > 0 ? 1 : e.length - 1;
            sel.attivo = true;
            return;
        }
        var n = sel.elenco.length;
        if (n === 0)
            return;
        sel.scelto = (sel.scelto + passo + n) % n;
    }

    /// Alt lasciato: si va dove si era arrivati.
    function conferma() {
        if (!sel.attivo)
            return;
        var w = sel.elenco[sel.scelto];
        sel.attivo = false;
        if (!w)
            return;
        if (w.minimized)
            Core.Windows.restore(w.address);
        else
            Core.Windows.focus(w.address);
    }

    function annulla() { sel.attivo = false; }

    // ── Il riquadro ──────────────────────────────────────────────────────

    readonly property int lato: 96
    readonly property int passo: sel.lato + Theme.Effects.space3

    Rectangle {
        id: cornice
        anchors.centerIn: parent
        width: Math.min(sel.width - Theme.Effects.space6 * 2,
                        sel.elenco.length * sel.passo + Theme.Effects.space5)
        height: sel.lato + Theme.Effects.space6 * 2 + 26
        radius: Theme.Effects.radiusLG
        color: Theme.Colors.panel
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge

        // Entra crescendo di poco, non da zero: un riquadro che esplode a
        // ogni Alt+Tab stanca alla decima volta della giornata.
        scale: sel.attivo ? 1 : 0.96
        opacity: sel.attivo ? 1 : 0
        Behavior on scale {
            NumberAnimation { duration: Theme.Motion.quick; easing.type: Easing.OutCubic }
        }
        Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }

        // La pastiglia che segue la scelta. È lei a muoversi, non le icone:
        // un elenco che scorre sotto una cornice ferma si segue peggio.
        Rectangle {
            id: pastiglia
            width: sel.lato + Theme.Effects.space2
            height: width
            radius: Theme.Effects.radiusMD
            color: Qt.alpha(Theme.Colors.accent, 0.22)
            border.width: 1
            border.color: Qt.alpha(Theme.Colors.accent, 0.55)
            y: Theme.Effects.space5 - Theme.Effects.space1
            x: fila.x + sel.scelto * sel.passo - Theme.Effects.space1
            visible: sel.elenco.length > 0
            Behavior on x {
                NumberAnimation { duration: Theme.Motion.quick; easing.type: Easing.OutCubic }
            }
        }

        Row {
            id: fila
            y: Theme.Effects.space5
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.Effects.space3

            Repeater {
                model: sel.elenco

                delegate: Item {
                    id: casella
                    required property var modelData
                    required property int index

                    width: sel.lato
                    height: sel.lato

                    readonly property var app:
                        Core.Apps.forClass(casella.modelData.appClass || "")

                    Image {
                        id: figura
                        anchors.fill: parent
                        anchors.margins: Theme.Effects.space2
                        source: casella.app && casella.app.icon
                                ? "file://" + casella.app.icon : ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        asynchronous: true
                        sourceSize.width: sel.lato
                        sourceSize.height: sel.lato
                        visible: status === Image.Ready
                        // La scelta si vede anche senza la pastiglia: le altre
                        // si spengono. Serve a chi distingue male i colori, e
                        // serve di sera.
                        opacity: casella.index === sel.scelto ? 1 : 0.45
                        Behavior on opacity { NumberAnimation { duration: 110 } }
                    }

                    // Ripiego: l'iniziale in un tondo. Un quadrato vuoto dove
                    // le altre hanno un'icona sembra un errore; una lettera
                    // sembra una scelta.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Theme.Effects.space2
                        radius: Theme.Effects.radiusSM
                        visible: figura.status !== Image.Ready
                        color: Qt.alpha(Theme.Colors.accent, 0.18)
                        opacity: casella.index === sel.scelto ? 1 : 0.45

                        Text {
                            anchors.centerIn: parent
                            text: (casella.modelData.appClass
                                   || casella.modelData.title || "?")
                                  .charAt(0).toUpperCase()
                            color: Theme.Colors.accent
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Math.round(sel.lato * 0.4)
                            font.weight: Theme.Typography.weightSemiBold
                        }
                    }

                    // Il pallino di chi è ridotta a icona: si vede che c'è ma
                    // che non è a schermo, e non serve leggere niente.
                    Rectangle {
                        visible: casella.modelData.minimized === true
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 6; height: 6; radius: 3
                        color: Theme.Colors.textMuted
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: sel.scelto = casella.index
                        onClicked: sel.conferma()
                    }
                }
            }
        }

        // Il nome, sotto e in mezzo. Uno solo — quello scelto — perché sei
        // titoli affiancati non si leggono, si guardano.
        Text {
            textFormat: Text.PlainText
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.Effects.space4
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - Theme.Effects.space5 * 2
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: {
                var w = sel.elenco[sel.scelto];
                if (!w) return "";
                var a = Core.Apps.forClass(w.appClass || "");
                var nome = (a && a.name) ? a.name : (w.appClass || "");
                return w.title && w.title !== nome && nome !== ""
                       ? nome + " — " + w.title : (w.title || nome);
            }
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeMD
            font.weight: Theme.Typography.weightMedium
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Osd — L'avviso che compare premendo i tasti del volume o della luminosità.
//
// Senza, premere «volume +» non produce nessun segno a schermo: si sente il
// suono cambiare — quando c'è un suono — ma non si sa a che punto si è, né se
// il tasto ha funzionato. Con la luminosità è peggio: si vede un cambiamento
// ma non si sa quanto manca al minimo.
//
// Compare al CENTRO IN BASSO e non vicino alla barra: nasce da un tasto fisico
// e non da un pulsante, quindi non ha un punto d'origine sullo schermo. In
// basso resta lontano da ciò che si sta guardando.
//
// Non ruba mai il fuoco e non intercetta i clic: appare mentre si sta
// scrivendo, e un avviso che si prende la tastiera farebbe perdere una frase.
PanelWindow {
    id: osd

    WlrLayershell.namespace: "quickshell"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors { bottom: true }
    margins.bottom: 96

    implicitWidth: 280
    implicitHeight: 76
    color: "transparent"
    visible: shown

    // Niente clic: la finestra è alta e larga quanto l'avviso, e senza
    // maschera vuota ingoierebbe i clic su ciò che c'è sotto.
    mask: Region {}

    /// Cosa mostrare: "volume", "brightness" o "" (niente).
    property string kind: ""
    property bool shown: false

    readonly property int value: kind === "brightness" ? Core.SystemState.brightness
                                                       : Core.SystemState.volume
    readonly property bool silent: kind === "volume"
                                   && (Core.SystemState.muted || Core.SystemState.volume === 0)

    /// Vero quando si è chiesto più di quanto si possa avere. Serve a
    /// distinguere «sei al massimo» da «non è successo niente», che è
    /// esattamente ciò che mancava.
    property bool atLimit: false

    /// Mostra l'avviso e fa ripartire il conto alla rovescia.
    function flash(what, limit) {
        osd.kind = what;
        osd.atLimit = limit === true;
        osd.shown = true;
        life.restart();
        if (osd.atLimit)
            nudge.restart();
    }

    // ── Avvisi che non sono un numero ────────────────────────────────────
    //
    // Volume e luminosità sono valori e si mostrano con una barra. Il modo
    // delle finestre no: è una parola, e cambia premendo una scorciatoia. Se
    // non comparisse niente a schermo, premere Super+Y sembrerebbe non fare
    // nulla finché non si apre una finestra nuova — cioè troppo tardi per
    // capire che cosa ha fatto quel tasto.

    property string message: ""
    property string messageIcon: "apps"

    readonly property bool isMessage: osd.kind === "message"

    function say(text, icon) {
        osd.message = text;
        osd.messageIcon = icon || "apps";
        osd.flash("message", false);
    }

    // Al massimo la barra dà una spinta e torna: il valore non può cambiare,
    // quindi il MOVIMENTO è l'unica cosa che possa rispondere al tasto. Senza,
    // premere «alza» a fine corsa mostra un avviso identico al precedente e
    // sembra ancora che non abbia funzionato niente.
    property real limitNudge: 0
    SequentialAnimation {
        id: nudge
        NumberAnimation {
            target: osd; property: "limitNudge"; to: 1
            duration: 90; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: osd; property: "limitNudge"; to: 0
            duration: 220; easing.type: Easing.OutBack
        }
    }

    Timer {
        id: life
        interval: 1600
        onTriggered: osd.shown = false
    }

    // ── Comparsa dai tasti ───────────────────────────────────────────────
    //
    // Non si intercettano i tasti: si guarda il VALORE. Cambiando il volume
    // in qualunque modo — tasto, cursore del pannello, un altro programma —
    // l'avviso compare, ed è giusto così: dice cos'è successo, non chi l'ha
    // fatto.
    //
    // Il primo valore letto all'avvio non deve far comparire niente: la shell
    // parte, legge il volume, e senza questa guardia mostrerebbe l'avviso a
    // ogni accesso senza che nessuno abbia toccato niente.
    property bool _ready: false

    Timer {
        interval: 2500
        running: true
        onTriggered: osd._ready = true
    }

    Connections {
        target: Core.SystemState
        function onVolumeChanged() { if (osd._ready) osd.flash("volume", false); }
        function onMutedChanged()  { if (osd._ready) osd.flash("volume", false); }
        function onBrightnessChanged() {
            // La luminosità cambia da sola quando scatta il risparmio
            // energetico: mostrarlo va bene, è comunque un'informazione.
            if (osd._ready && Core.SystemState.brightness >= 0)
                osd.flash("brightness", false);
        }

        // E questo è il caso che il valore da solo non racconta: si è premuto
        // il tasto ma il numero è già al massimo, quindi non cambia niente e
        // nessuno dei segnali qui sopra scatta. Senza questa riga, «alza il
        // volume» al 100% non produce nulla a schermo — che è precisamente il
        // difetto per cui questa proprietà esiste.
        function onAdjusted(what, atLimit) {
            if (osd._ready)
                osd.flash(what, atLimit);
        }
    }

    // ── L'avviso ─────────────────────────────────────────────────────────

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Theme.Effects.radiusLG
        color: Theme.Colors.membrane
        border.width: 1
        border.color: Theme.Colors.edge

        // Sale di poco entrando e scende uscendo: il movimento verticale lo
        // lega al bordo dello schermo da cui arriva.
        opacity: osd.shown ? 1 : 0
        y: osd.shown ? 0 : 12
        Behavior on opacity {
            NumberAnimation { duration: Theme.Motion.quick }
        }
        Behavior on y {
            NumberAnimation {
                duration: Theme.Motion.panel
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.Motion.emerge
            }
        }

        Ui.Icon {
            id: glyph
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space5
            anchors.verticalCenter: parent.verticalCenter
            width: 26; height: 26
            name: osd.isMessage ? osd.messageIcon
                : osd.kind === "brightness" ? "sun"
                : osd.silent ? "muted"
                : "volume"
            color: osd.isMessage ? Theme.Colors.accent
                 : osd.silent ? Theme.Colors.textFaint
                 : osd.kind === "brightness" ? Theme.Colors.warning
                 : Theme.Colors.accent
        }

        // La parola, quando l'avviso è una parola. Prende il posto del numero
        // e della barra, che qui non vorrebbero dire niente.
        Text {
            anchors.left: glyph.right
            anchors.leftMargin: Theme.Effects.space4
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space5
            anchors.verticalCenter: parent.verticalCenter
            visible: osd.isMessage
            elide: Text.ElideRight
            text: osd.message
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeMD
            font.weight: Theme.Typography.weightSemiBold
        }

        Text {
            id: readout
            visible: !osd.isMessage
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space5
            anchors.top: parent.top
            anchors.topMargin: Theme.Effects.space4
            text: osd.silent ? (Core.Strings.lang === "it" ? "muto" : "muted")
                             : osd.value + "%"
            color: osd.atLimit ? Theme.Colors.warning
                 : osd.silent ? Theme.Colors.textFaint
                 : Theme.Colors.text
            font.family: Theme.Typography.fontMono
            font.pixelSize: Theme.Typography.sizeLG
            font.weight: Theme.Typography.weightBold
        }

        // Barra spessa: si legge di sfuggita, che è l'unico modo in cui la si
        // guarda. Una barretta sottile costringe a fissarla.
        Rectangle {
            visible: !osd.isMessage
            anchors.left: glyph.right
            anchors.leftMargin: Theme.Effects.space4
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space5
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.Effects.space4
            height: 8
            radius: 4
            color: Theme.Colors.sunken

            Rectangle {
                id: fill
                width: parent.width * Math.max(0, Math.min(100, osd.silent ? 0 : osd.value)) / 100
                height: parent.height
                radius: parent.radius
                color: osd.kind === "brightness" ? Theme.Colors.warning : Theme.Colors.accent
                Behavior on width {
                    NumberAnimation {
                        duration: Theme.Motion.quick
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // Il segno di «non si va oltre»: un blocco all'estremità che si
            // accende quando si insiste. Sta a fine corsa perché è lì che si
            // sta spingendo, e si stringe con la barra invece di comparire
            // altrove.
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: parent.height + 6 * osd.limitNudge
                radius: 1.5
                color: Theme.Colors.warning
                opacity: osd.atLimit ? 0.5 + 0.5 * osd.limitNudge : 0
                Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }
            }
        }

        // Una parola sola quando si è in fondo. Serve perché il numero al
        // 100% è identico a quello di un istante prima: senza, l'avviso
        // ricompare uguale e chi preme continua a chiedersi se ha premuto.
        Text {
            anchors.left: glyph.right
            anchors.leftMargin: Theme.Effects.space4
            anchors.top: parent.top
            anchors.topMargin: Theme.Effects.space4 + 4
            text: {
                var it = Core.Strings.lang === "it";
                if (!osd.atLimit)
                    return "";
                if (osd.kind === "brightness")
                    return osd.value >= 100 ? (it ? "massimo" : "maximum")
                                            : (it ? "minimo" : "minimum");
                return osd.value >= Core.SystemState.volumeCeiling
                       ? (it ? "massimo" : "maximum")
                       : (it ? "minimo" : "minimum");
            }
            color: Theme.Colors.warning
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
            font.weight: Theme.Typography.weightMedium
            opacity: osd.atLimit ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }
        }
    }
}

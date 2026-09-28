import QtQuick
import "../theme" as Theme

// SpineButton — Il bersaglio cliccabile della barra.
//
// Tutto ciò che si clicca nella barra è uno di questi: stessa dimensione,
// stesso raggio, stessa reazione. Prima ogni widget disegnava il proprio
// riquadro con misure leggermente diverse, e la barra sembrava assemblata da
// pezzi che non si conoscevano.
//
// Lo stato attivo non è solo un cambio di colore: l'elemento si accende, con
// un alone che deborda oltre il bordo. È il segnale che quel pulsante ha
// aperto qualcosa — e siccome i pannelli nascono proprio da lì, lega
// visivamente il pulsante al pannello che ha fatto scendere.
Item {
    id: button

    property alias content: holder.data
    property bool active: false
    /// Un fondo anche a riposo. Sulla barra i pulsanti sono trasparenti
    /// finché non ci si passa sopra, e va bene: la barra è il loro fondo.
    /// Dentro una pagina invece un pulsante trasparente è testo qualunque —
    /// «kDrive» e «Google Drive» nella pagina Account non sembravano
    /// cliccabili (visto il 28 settembre 2026).
    property bool solido: false
    property bool showGlow: true
    property color accent: Theme.Colors.accent
    property real horizontalPadding: Theme.Effects.space3
    /// Testo mostrato nell'etichetta al passaggio del mouse (vuoto = nessuna)
    property string tooltip: ""

    // Il nome parlato è il suggerimento che già esiste: è la frase che
    // descrive il pulsante, ed è scritta apposta per essere letta.
    Accessible.role: Accessible.Button
    Accessible.name: button.tooltip

    signal clicked()
    signal rightClicked()

    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed

    implicitWidth: Math.max(Theme.Effects.barButton,
                            holder.childrenRect.width + horizontalPadding * 2)
    implicitHeight: Theme.Effects.barButton

    // Alone: un rettangolo sfocato dietro al pulsante. Nessuna ombra vera,
    // solo colore che sfuma — su fondo scuro è ciò che legge come «acceso».
    Rectangle {
        anchors.centerIn: parent
        width: parent.width + 14
        height: parent.height + 14
        radius: height / 2
        color: button.accent
        opacity: (button.active && button.showGlow) ? 0.16 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.Motion.quick }
        }
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: Theme.Effects.radiusSM

        color: button.active ? Qt.alpha(button.accent, 0.18)
                             : button.pressed ? Theme.Colors.pressed
                             : button.hovered ? Theme.Colors.hover
                             : button.solido ? Theme.Colors.raised
                             : "transparent"

        border.width: button.active ? 1 : (button.solido ? Theme.Effects.hairline : 0)
        border.color: button.active ? Qt.alpha(button.accent, 0.45) : Theme.Colors.edge

        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

        // Compressione alla pressione: conferma tattile immediata, prima
        // ancora che l'azione produca un effetto visibile.
        scale: button.pressed ? 0.94 : 1.0
        Behavior on scale {
            NumberAnimation {
                duration: Theme.Motion.instant
                easing.type: Easing.OutCubic
            }
        }

        Item {
            id: holder
            anchors.centerIn: parent
            width: childrenRect.width
            height: childrenRect.height
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(e) {
            if (e.button === Qt.RightButton)
                button.rightClicked();
            else
                button.clicked();
        }
    }

    // Etichetta esplicativa: compare solo dopo una breve permanenza, così
    // non lampeggia mentre si attraversa la barra col puntatore.
    //
    // ── Sopra o sotto ────────────────────────────────────────────────────
    //
    // Nasceva sempre SOTTO, e per la barra della scrivania va bene: sotto c'è
    // tutto lo schermo. Per una barra degli strumenti in fondo a una finestra
    // no — l'etichetta finiva oltre il bordo, e di lei restava un rettangolo
    // tagliato che non si poteva leggere in nessun modo, nemmeno a schermo
    // intero. È lo stesso problema che il menu contestuale risolve con
    // `growUp`, e la risposta è la stessa: si guarda se sotto c'è posto.
    //
    // Si misura quando il puntatore arriva e non con un legame continuo:
    // `mapToItem` è una funzione, non una proprietà — non si riaccorge da sé
    // che il pulsante si è spostato, e legarcisi darebbe un valore che si
    // aggiorna quando gli pare.
    property bool tipSopra: false

    function _guardaDovMettereIlTip() {
        var finestra = button.Window.window;
        if (!finestra) {
            button.tipSopra = false;
            return;
        }
        var giu = button.mapToItem(null, 0, button.height);
        // 26 di etichetta più il distacco, più un dito di margine.
        button.tipSopra = (giu.y + 26 + Theme.Effects.space3 + 4) > finestra.height;
    }

    Loader {
        active: button.tooltip !== "" && tipDelay.hasElapsed && button.hovered && !button.active
        // La posizione e non due ancore a turno: assegnare `undefined` a una
        // linea d'ancoraggio non la stacca, e la targhetta di un pulsante che
        // ha cambiato posto sullo schermo si ritrovava ancorata SOPRA E SOTTO
        // insieme. È lo stesso difetto che teneva i pulsanti della barra del
        // titolo incollati a sinistra — vedi `ui/TitleBarContent.qml`.
        y: button.tipSopra
           ? -height - Theme.Effects.space3
           : parent.height + Theme.Effects.space3
        anchors.horizontalCenter: parent.horizontalCenter
        z: 200

        sourceComponent: Rectangle {
            width: tipText.implicitWidth + Theme.Effects.space4
            height: 26
            radius: Theme.Effects.radiusXS
            color: Theme.Colors.panel
            border.width: 1
            border.color: Theme.Colors.edge

            Text {
                id: tipText
                anchors.centerIn: parent
                text: button.tooltip
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                font.weight: Theme.Typography.weightMedium
            }
        }
    }

    Timer {
        id: tipDelay
        property bool hasElapsed: false
        interval: 550
        running: button.hovered
        onTriggered: hasElapsed = true
    }

    onHoveredChanged: {
        if (button.hovered)
            button._guardaDovMettereIlTip();
        else
            tipDelay.hasElapsed = false;
    }
}

import QtQuick
import QtQuick.Window
import QtQuick.Controls as Controls
import "../../windows11" as W
import "../../ui" as Ui

// Riferimento: dialogo Colori della VM Windows, 20 ottobre 2026.
// Si modifica solo l'anteprima locale: una sola conferma scrive nel demone.
Controls.Popup {
    id: riquadro
    objectName: "selettoreColoreWindows"
    property string titolo: W.Style.it ? "Scegli un colore personalizzato" : "Choose a custom color"
    property color iniziale: "#000000"
    property real tonalita: 0
    property real saturazione: 0
    property real luminosita: 0
    property color pendente: Qt.hsva(tonalita, saturazione, luminosita, 1)
    property bool espanso: false
    property bool hsv: false
    property bool pronto: false
    readonly property bool valido: !espanso || (esa.acceptableInput && canale0.acceptableInput && canale1.acceptableInput && canale2.acceptableInput)
    signal confermato(color colore)

    modal: true
    dim: true
    focus: true
    padding: 0
    closePolicy: Controls.Popup.CloseOnEscape
    width: Math.min(488, parent ? parent.width - 32 : 488)
    height: Math.min(espanso ? 754 : 706, parent ? parent.height - 32 : 706)
    anchors.centerIn: parent
    Controls.Overlay.modal: Rectangle { color: "#52000000" }
    background: Rectangle {
        radius: 8
        color: W.Style.dark ? "#2B2B2B" : "#FFFFFF"
        border.width: 1
        border.color: W.Style.edge
    }

    function daColore(c) {
        if (c.hsvHue >= 0) tonalita = c.hsvHue;
        saturazione = c.hsvSaturation;
        luminosita = c.hsvValue;
    }
    function aggiornaCampi(forza) {
        if (!pronto) return;
        if (forza || !esa.activeFocus) esa.text = pendente.toString().toUpperCase();
        var values = hsv ? [Math.round(tonalita * 360) % 360, Math.round(saturazione * 100), Math.round(luminosita * 100)]
                         : [Math.round(pendente.r * 255), Math.round(pendente.g * 255), Math.round(pendente.b * 255)];
        var fields = [canale0, canale1, canale2];
        for (var i = 0; i < fields.length; i++)
            if (forza || !fields[i].activeFocus) fields[i].text = String(values[i]);
    }
    function daiCanali() {
        if (!canale0.acceptableInput || !canale1.acceptableInput || !canale2.acceptableInput) return;
        if (hsv) {
            tonalita = Number(canale0.text) / 360;
            saturazione = Number(canale1.text) / 100;
            luminosita = Number(canale2.text) / 100;
        } else {
            daColore(Qt.rgba(Number(canale0.text)/255, Number(canale1.text)/255, Number(canale2.text)/255, 1));
        }
        aggiornaCampi(false);
    }
    function apri(c) {
        // La modale copre anche ricerca e navigazione della finestra madre.
        var win = parent ? parent.Window.window : null;
        if (win) riquadro.parent = win.contentItem;
        iniziale = c;
        daColore(iniziale);
        espanso = false;
        hsv = false;
        aggiornaCampi(true);
        rotolo.contentY = 0;
        open();
    }
    function conferma() {
        if (!valido) return;
        var scelto = pendente;
        close();
        confermato(scelto);
    }
    onPendenteChanged: aggiornaCampi(false)
    onHsvChanged: aggiornaCampi(true)
    onEspansoChanged: if (!espanso) aggiornaCampi(true)
    Component.onCompleted: { pronto = true; aggiornaCampi(true); }

    function rivela(item) {
        var ancestor = item;
        while (ancestor && ancestor !== rotolo.contentItem) ancestor = ancestor.parent;
        if (!ancestor || !item) return;
        var p = item.mapToItem(rotolo, 0, 0);
        var next = rotolo.contentY;
        if (p.y < 8) next += p.y - 8;
        else if (p.y + item.height > rotolo.height - 8) next += p.y + item.height - rotolo.height + 8;
        rotolo.contentY = Math.max(0, Math.min(next, Math.max(0, rotolo.contentHeight - rotolo.height)));
    }
    Connections {
        target: riquadro.parent ? riquadro.parent.Window.window : null
        function onActiveFocusItemChanged() {
            if (riquadro.visible && target) riquadro.rivela(target.activeFocusItem);
        }
    }

    component Campo: Controls.TextField {
        implicitWidth: 120
        implicitHeight: 32
        selectByMouse: true
        font.family: W.Style.font
        font.pixelSize: 14
        color: W.Style.text
        selectionColor: W.Style.accent
        selectedTextColor: W.Style.accentForeground
        leftPadding: 10
        rightPadding: 10
        background: Rectangle {
            radius: 4
            color: W.Style.field
            border.width: parent.activeFocus ? 2 : 1
            border.color: parent.activeFocus ? W.Style.accent : W.Style.edge
        }
    }
    contentItem: Item {
        objectName: "coloreDialogoContenuto"
        function revealItem(item) { riquadro.rivela(item); }
        Flickable {
            id: rotolo
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: fondo.top }
            contentWidth: width
            contentHeight: corpo.implicitHeight + 48
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: corpo
                x: Math.min(48, rotolo.width / 10)
                y: 24
                width: rotolo.width - 2*x
                spacing: 24
                Text {
                    width: parent.width
                    text: riquadro.titolo
                    color: W.Style.text
                    font.family: W.Style.font
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                }
                Column {
                    width: Math.min(312, parent.width)
                    spacing: 24
                    Row {
                        width: parent.width
                        spacing: 12
                        Rectangle {
                            id: spettro
                            objectName: "coloreSpettro"
                            width: parent.width - 56
                            height: width
                            radius: 4
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "#FF0000" }
                                GradientStop { position: 1/6; color: "#FFFF00" }
                                GradientStop { position: 2/6; color: "#00FF00" }
                                GradientStop { position: 3/6; color: "#00FFFF" }
                                GradientStop { position: 4/6; color: "#0000FF" }
                                GradientStop { position: 5/6; color: "#FF00FF" }
                                GradientStop { position: 1; color: "#FF0000" }
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: 4
                                gradient: Gradient {
                                    GradientStop { position: 0; color: "#00FFFFFF" }
                                    GradientStop { position: 1; color: "#FFFFFFFF" }
                                }
                            }
                            Rectangle {
                                x: riquadro.tonalita * (parent.width - width)
                                y: (1-riquadro.saturazione) * (parent.height - height)
                                width: 16; height: 16; radius: 8
                                color: "transparent"
                                border.width: 2
                                border.color: "white"
                                Rectangle { anchors.fill: parent; anchors.margins: 2; radius: 6; color: "transparent"; border.width: 1; border.color: "#80000000" }
                            }
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Slider
                            Accessible.name: W.Style.it ? "Tonalità e saturazione" : "Hue and saturation"
                            Keys.onLeftPressed: riquadro.tonalita = Math.max(0, riquadro.tonalita - 1/360)
                            Keys.onRightPressed: riquadro.tonalita = Math.min(1, riquadro.tonalita + 1/360)
                            Keys.onUpPressed: riquadro.saturazione = Math.min(1, riquadro.saturazione + .01)
                            Keys.onDownPressed: riquadro.saturazione = Math.max(0, riquadro.saturazione - .01)
                            Rectangle { anchors.fill: parent; color: "transparent"; border.width: spettro.activeFocus ? 2 : 0; border.color: W.Style.accent }
                            MouseArea {
                                anchors.fill: parent
                                preventStealing: true
                                function muovi(m) {
                                    spettro.forceActiveFocus(Qt.MouseFocusReason);
                                    riquadro.tonalita = Math.max(0, Math.min(1, m.x / width));
                                    riquadro.saturazione = 1 - Math.max(0, Math.min(1, m.y / height));
                                }
                                onPressed: function(m) { muovi(m); }
                                onPositionChanged: function(m) { if (pressed) muovi(m); }
                            }
                        }
                        Column {
                            width: 44
                            Rectangle { width: parent.width; height: spettro.height/2; radius: 4; color: riquadro.iniziale }
                            Rectangle { width: parent.width; height: spettro.height/2; radius: 4; color: riquadro.pendente }
                        }
                    }
                    Controls.Slider {
                        id: cursoreLuce
                        objectName: "coloreLuminosita"
                        width: parent.width
                        height: 16
                        from: 0; to: 1; stepSize: .01
                        value: riquadro.luminosita
                        onMoved: riquadro.luminosita = value
                        Accessible.name: W.Style.it ? "Luminosità" : "Brightness"
                        background: Rectangle {
                            x: cursoreLuce.leftPadding; y: (cursoreLuce.height-height)/2
                            width: cursoreLuce.availableWidth; height: 12; radius: 6
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "#000000" }
                                GradientStop { position: 1; color: Qt.hsva(riquadro.tonalita, riquadro.saturazione, 1, 1) }
                            }
                        }
                        handle: Rectangle {
                            x: cursoreLuce.leftPadding + cursoreLuce.visualPosition * (cursoreLuce.availableWidth-width)
                            y: (cursoreLuce.height-height)/2
                            width: 16; height: 16; radius: 8
                            color: "#333333"; border.width: 3; border.color: "white"
                        }
                    }
                    PulsanteWindows {
                        objectName: "coloreEspandi"
                        anchors.right: parent.right
                        testo: riquadro.espanso ? (W.Style.it ? "Comprimi ⌃" : "Collapse ⌃") : (W.Style.it ? "Espandi ⌄" : "Expand ⌄")
                        onPremuto: riquadro.espanso = !riquadro.espanso
                    }
                    Column {
                        visible: riquadro.espanso
                        width: parent.width
                        spacing: 12
                        Row {
                            width: parent.width
                            spacing: Math.max(8, width-252)
                            TendinaWindows {
                                width: 120
                                objectName: "coloreFormato"
                                valore: riquadro.hsv ? "hsv" : "rgb"
                                voci: [{valore:"rgb", testo:"RGB"}, {valore:"hsv", testo:"HSV"}]
                                onScelto: function(v) { riquadro.hsv = v === "hsv"; }
                            }
                            Campo {
                                id: esa
                                objectName: "coloreEsadecimale"
                                width: 132
                                Accessible.name: W.Style.it ? "Esadecimale" : "Hexadecimal"
                                validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{6}/ }
                                onTextEdited: if (acceptableInput) {
                                    // Conversione tramite una proprietà color tipizzata.
                                    conversione.color = text.charAt(0) === "#" ? text : "#"+text;
                                    riquadro.daColore(conversione.color);
                                }
                            }
                        }
                        Row {
                            spacing: 8
                            Campo {
                                id: canale0
                                objectName: "coloreCanale0"
                                Accessible.name: riquadro.hsv ? (W.Style.it ? "Tonalità" : "Hue") : (W.Style.it ? "Rosso" : "Red")
                                validator: IntValidator { bottom: 0; top: riquadro.hsv ? 359 : 255 }
                                onTextEdited: riquadro.daiCanali()
                            }
                            Text { text: canale0.Accessible.name; color: W.Style.text; font.family: W.Style.font; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Row {
                            spacing: 8
                            Campo {
                                id: canale1
                                objectName: "coloreCanale1"
                                Accessible.name: riquadro.hsv ? (W.Style.it ? "Saturazione" : "Saturation") : (W.Style.it ? "Verde" : "Green")
                                validator: IntValidator { bottom: 0; top: riquadro.hsv ? 100 : 255 }
                                onTextEdited: riquadro.daiCanali()
                            }
                            Text { text: canale1.Accessible.name; color: W.Style.text; font.family: W.Style.font; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Row {
                            spacing: 8
                            Campo {
                                id: canale2
                                objectName: "coloreCanale2"
                                Accessible.name: riquadro.hsv ? (W.Style.it ? "Luminosità" : "Brightness") : (W.Style.it ? "Blu" : "Blue")
                                validator: IntValidator { bottom: 0; top: riquadro.hsv ? 100 : 255 }
                                onTextEdited: riquadro.daiCanali()
                            }
                            Text { text: canale2.Accessible.name; color: W.Style.text; font.family: W.Style.font; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }
                Column {
                    width: parent.width
                    spacing: 12
                    Text { text: W.Style.it ? "Anteprima colore" : "Color preview"; color: W.Style.text; font.family: W.Style.font; font.pixelSize: 14 }
                    Grid {
                        width: parent.width
                        columns: 2
                        Repeater {
                            model: [riquadro.pendente, "#14144B", "#333333", "#DDDDDD"]
                            Rectangle {
                                required property var modelData
                                required property int index
                                width: parent.width/2; height: 40
                                color: modelData
                                Text { anchors.centerIn: parent; text: W.Style.it ? "Anteprima" : "Preview"; font.family: W.Style.font; font.pixelSize: 12; color: parent.index === 0 ? "white" : riquadro.pendente }
                            }
                        }
                    }
                }
            }
        }
        Ui.Scorrimento { bersaglio: rotolo; anchors.right: rotolo.right; anchors.top: rotolo.top; anchors.bottom: rotolo.bottom }
        Rectangle {
            id: fondo
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 80
            radius: 8
            color: W.Style.dark ? "#202020" : "#F3F3F3"
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 8; color: parent.color }
            Row {
                anchors.centerIn: parent
                width: parent.width - 48
                spacing: 8
                PulsanteWindows {
                    objectName: "coloreFine"
                    width: (parent.width-8)/2
                    testo: W.Style.it ? "Fatto" : "Done"
                    enabled: riquadro.valido
                    onPremuto: riquadro.conferma()
                }
                PulsanteWindows {
                    objectName: "coloreAnnulla"
                    width: (parent.width-8)/2
                    testo: W.Style.it ? "Annulla" : "Cancel"
                    onPremuto: riquadro.close()
                }
            }
        }
        Rectangle { id: conversione; visible: false }
    }
}

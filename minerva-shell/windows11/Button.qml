import QtQuick
import QtQuick.Controls as Controls
import "../ui" as Ui
FocusScope {
    id: root
    property string text: ""
    property string icon: ""
    property bool selected: false
    property bool filled: false
    /// Quanto è grande il simbolo. 18 nei pannelli; 24 sulla barra, dove in
    /// Windows 11 Ricerca e Visualizzazione attività hanno la misura delle
    /// icone delle app (a 18 sembravano più piccole: il manutentore, 11 ottobre 2026).
    property int glyphSize: 18
    /// Il fuoco è arrivato col mouse. Il clic dà il fuoco al pulsante (serve
    /// a Invio e alle frecce dopo), ma il contorno del fuoco in Windows 11 si
    /// vede solo arrivandoci con la tastiera: dopo un clic restava un
    /// quadrato acceso sull'ultima cosa cliccata della barra (il manutentore, 11
    /// ottobre 2026).
    property bool _focoDalMouse: false
    readonly property bool _focoVisibile: root.activeFocus && !root._focoDalMouse
    onActiveFocusChanged: if (!activeFocus) _focoDalMouse = false
    property string tooltip: text
    /// Icona e testo a sinistra invece che al centro: gli elenchi di azioni
    /// (l'anteprima di Cerca) in Windows sono allineati a sinistra.
    property bool aSinistra: false
    property alias hovered: mouse.containsMouse
    property color foreground: filled ? Style.accentForeground : Style.text
    /// Al posto del simbolo, il ritratto tondo di chi usa il computer (il
    /// piede dello Start, come in Windows 11): la foto se c'è, altrimenti
    /// l'iniziale del nome.
    property bool avatar: false
    property string ritratto: ""
    signal clicked()
    signal rightClicked()
    signal middleClicked()
    implicitWidth: text === "" ? 40 : Math.max(40, caption.implicitWidth + (icon === "" && !avatar ? 24 : (avatar ? 62 : 54)))
    implicitHeight: 34
    Accessible.role: Accessible.Button; Accessible.name: tooltip
    Accessible.onPressAction: clicked()
    activeFocusOnTab: true
    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
    Keys.onSpacePressed: clicked()
    Rectangle {
        anchors.fill: parent; radius: 4
        color: root.filled ? Style.accent : (root.selected || mouse.containsMouse || root._focoVisibile ? Style.hover : "transparent")
        border.width: root._focoVisibile ? 2 : (root.selected ? 1 : 0)
        border.color: root._focoVisibile ? Style.accentIndicator : Style.edge
        Behavior on color { ColorAnimation { duration: Style.duration } }
    }
    Row {
        anchors.centerIn: root.aSinistra ? undefined : parent
        x: root.aSinistra ? 12 : 0
        anchors.verticalCenter: root.aSinistra ? parent.verticalCenter : undefined
        spacing: 10
        Glyph { visible: root.icon !== "" && !root.avatar; width: root.glyphSize; height: root.glyphSize; name: root.icon; color: root.foreground; alwaysDrawn: true }
        Item {
            visible: root.avatar
            width: 28
            height: 28
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                visible: !foto.pronto
                color: Qt.alpha(Style.accent, 0.25)
                Text {
                    anchors.centerIn: parent
                    text: root.text.charAt(0).toUpperCase()
                    color: Style.text
                    font.family: Style.font
                    font.pixelSize: 13
                }
            }
            Ui.RitrattoTondo { id: foto; anchors.fill: parent; fonte: root.avatar ? root.ritratto : "" }
        }
        Text { id: caption; visible: root.text !== ""; text: root.text; color: root.foreground; font.family: Style.font; font.pixelSize: 12 * Style.textScale; anchors.verticalCenter: parent.verticalCenter }
    }
    MouseArea {
        id: mouse; anchors.fill: parent; hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: function(event) {
            root._focoDalMouse = true;
            root.forceActiveFocus(Qt.MouseFocusReason);
            if (event.button === Qt.RightButton) root.rightClicked();
            else if (event.button === Qt.MiddleButton) root.middleClicked();
            else root.clicked();
        }
    }
    Controls.ToolTip.visible: mouse.containsMouse && root.tooltip !== ""
    Controls.ToolTip.delay: 700
    Controls.ToolTip.text: root.tooltip
}

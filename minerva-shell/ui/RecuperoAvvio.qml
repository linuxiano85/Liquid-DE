import QtQuick
import Quickshell
import Quickshell.Wayland

// Mostrato soltanto quando le preferenze iniziali non arrivano entro la
// scadenza IPC. Il preset dell'utente resta sconosciuto e non si modifica.
PanelWindow {
    id: recovery
    anchors { top:true; bottom:true; left:true; right:true }
    exclusionMode:ExclusionMode.Ignore
    WlrLayershell.namespace:"liquid-startup-recovery"
    WlrLayershell.layer:WlrLayer.Overlay
    WlrLayershell.keyboardFocus:WlrKeyboardFocus.Exclusive
    color:"#111827"
    signal retryRequested()
    readonly property bool it:Qt.locale().name.indexOf("it")===0

    Column {
        anchors.centerIn:parent
        width:Math.min(480,Math.max(180,recovery.width-48))
        spacing:20
        Text {
            width:parent.width
            text:"Liquid DE"
            color:"#F9FAFB"
            font.pixelSize:26
            font.weight:Font.DemiBold
            horizontalAlignment:Text.AlignHCenter
        }
        Text {
            width:parent.width
            text:recovery.it ? "Le impostazioni del desktop non sono ancora disponibili. Puoi attendere o riprovare."
                             : "Desktop settings are not available yet. You can wait or try again."
            color:"#D1D5DB"
            font.pixelSize:16
            wrapMode:Text.WordWrap
            horizontalAlignment:Text.AlignHCenter
        }
        Rectangle {
            id:retry
            anchors.horizontalCenter:parent.horizontalCenter
            width:Math.max(150,caption.implicitWidth+40)
            height:44
            radius:6
            color:mouse.pressed ? "#374151":"#1F2937"
            border.width:retry.activeFocus ? 2:1
            border.color:retry.activeFocus ? "#67E8F9":"#9CA3AF"
            activeFocusOnTab:true
            Component.onCompleted:forceActiveFocus()
            Accessible.role:Accessible.Button
            Accessible.name:caption.text
            Accessible.onPressAction:recovery.retryRequested()
            Keys.onReturnPressed:recovery.retryRequested()
            Keys.onEnterPressed:recovery.retryRequested()
            Keys.onSpacePressed:recovery.retryRequested()
            Text {
                id:caption
                anchors.centerIn:parent
                text:recovery.it ? "Riprova":"Try again"
                color:"#F9FAFB"
                font.pixelSize:16
            }
            MouseArea {id:mouse;anchors.fill:parent;onClicked:recovery.retryRequested()}
        }
    }
}

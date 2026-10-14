import QtQuick
import "../../core" as Core
import "../../windows11" as W

// Testata condivisa tra Home e Sistema, dalle foto della VM.
Item {
    id: intestazione
    property var dati: ({})
    property string prefisso: "device"
    readonly property var aggiornamenti: Core.Ipc.liquidUpdateState
    function tr(it, en) { return W.Style.label(it, en); }
    signal aggiornamentiChiesti()
    width: parent.width
    height: 113
    Rectangle {
        x: 0
        y: 17
        width: 120
        height: 68
        radius: 5
        color: "black"
        Image {
            anchors.fill: parent
            anchors.margins: 4
            source: Core.Wallpaper.urlFile(Core.Wallpaper.current)
            sourceSize: Qt.size(224, 120)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }
    Column {
        x: 136
        y: 24
        width: Math.max(80, parent.width - x - (parent.width >= 680 ? 265 : 8))
        spacing: 3
        Text {
            objectName: intestazione.prefisso + "DeviceName"
            width: parent.width
            text: intestazione.dati.hostname || "Computer"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: W.Style.text
            font.family: W.Style.font
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            text: intestazione.dati.model || intestazione.tr("Informazioni sul dispositivo", "Device information")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: W.Style.muted
            font.family: W.Style.font
            font.pixelSize: 14
        }
    }
    SchedaImpostazione {
        objectName: intestazione.prefisso + "Update"
        y: 16
        visible: parent.width >= 680
        anchors.right: parent.right
        width: 250
        color: "transparent"
        border.width: 0
        icona: "refresh"
        titolo: "Liquid Update"
        descrizione: intestazione.aggiornamenti.phase === "checking" ? intestazione.tr("Verifica in corso", "Checking")
            : intestazione.aggiornamenti.comparison && intestazione.aggiornamenti.comparison.complete && !intestazione.aggiornamenti.comparison.runtimeChanged ? intestazione.tr("Desktop invariato", "Desktop unchanged")
            : intestazione.aggiornamenti.updateAvailable ? intestazione.tr("Aggiornamenti disponibili", "Updates available")
            : intestazione.aggiornamenti.latest && intestazione.aggiornamenti.latest.revision && intestazione.aggiornamenti.installed && intestazione.aggiornamenti.installed.revision === intestazione.aggiornamenti.latest.revision ? intestazione.tr("Componenti aggiornati", "Up to date")
            : intestazione.tr("Verifica aggiornamenti", "Check for updates")
        porta: true
        onAttivata: intestazione.aggiornamentiChiesti()
    }
}

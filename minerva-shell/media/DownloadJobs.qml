import QtQuick
import "../core" as Core
import "../theme" as Theme
import "../ui" as Ui

Item {
    id: panel
    objectName: "mediaDownloadJobs"
    property var jobs: []
    signal cancelRequested(string jobId)
    /// «Svuota completati»: il demone toglie i lavori finiti (non quelli in corso).
    signal clearRequested()
    readonly property bool haFiniti: {
        for (var i = 0; i < jobs.length; i++)
            if (!jobs[i].stale && jobs[i].stato !== "in_coda" && jobs[i].stato !== "in_corso")
                return true;
        return false;
    }
    readonly property bool it: Core.Strings.lang === "it"
    implicitHeight: jobs.length ? 156 : 0
    clip: true
    Text {
        id: title
        text: panel.it ? "Download" : "Downloads"
        color: Theme.Colors.text
        font.pixelSize: Theme.Typography.sizeSM
    }
    Rectangle {
        id: clear
        objectName: "mediaDownloadClear"
        anchors { right: parent.right; rightMargin: 20; verticalCenter: title.verticalCenter }
        visible: panel.haFiniti
        width: clearText.implicitWidth + 20; height: 26; radius: 6
        color: clearArea.containsMouse ? Theme.Colors.hover : "transparent"
        Text {
            id: clearText
            anchors.centerIn: parent
            text: panel.it ? "Svuota completati" : "Clear finished"
            color: Theme.Colors.text
            font.pixelSize: Theme.Typography.sizeXS
        }
        MouseArea { id: clearArea; anchors.fill: parent; hoverEnabled: true; onClicked: panel.clearRequested() }
    }
    ListView {
        id: list
        anchors { left:parent.left;right:parent.right;top:title.bottom;topMargin:8;bottom:parent.bottom;rightMargin:12 }
        model: panel.jobs
        spacing: 8
        clip: true
        delegate: Rectangle {
            required property var modelData
            width: list.width
            height: 58
            radius: 8
            color: Theme.Colors.raised
            readonly property bool activeJob: !modelData.stale && (modelData.stato === "in_coda" || modelData.stato === "in_corso")
            Text {
                anchors { left:parent.left;leftMargin:10;right:cancel.left;rightMargin:10;top:parent.top;topMargin:7 }
                text: modelData.titolo || modelData.corrente || modelData.indirizzo
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                color: Theme.Colors.text
                font.pixelSize: Theme.Typography.sizeSM
            }
            Text {
                anchors { left:parent.left;leftMargin:10;right:cancel.left;rightMargin:10;bottom:parent.bottom;bottomMargin:10 }
                text: {
                    if(modelData.stale) return panel.it ? "Connessione interrotta" : "Connection lost";
                    var names = {"in_coda":["In coda","Queued"],"in_corso":["Scaricamento","Downloading"],
                        "fatto":["Completato","Completed"],"parziale":["Completato in parte","Partially completed"],
                        "errore":["Non riuscito","Failed"],"annullato":["Annullato","Cancelled"]};
                    var label=names[modelData.stato];
                    return (label ? label[panel.it?0:1]:modelData.stato)
                        +(modelData.stato==="in_corso" && modelData.totale>0 ? " · "+Math.min(100,Math.round(100*modelData.scaricati/modelData.totale))+"%":"");
                }
                elide: Text.ElideRight
                color: modelData.stato==="errore" ? Theme.Colors.danger : Theme.Colors.textMuted
                font.pixelSize: Theme.Typography.sizeXS
            }
            Rectangle {
                anchors {left:parent.left;bottom:parent.bottom}
                height:3
                radius:1
                width: modelData.totale>0 ? parent.width*Math.max(0,Math.min(1,modelData.scaricati/modelData.totale)):0
                color: Theme.Colors.accent
            }
            Rectangle {
                id:cancel
                anchors {right:parent.right;rightMargin:8;verticalCenter:parent.verticalCenter}
                width:80;height:30;radius:6
                visible:parent.activeJob
                color: area.containsMouse ? Theme.Colors.hover : "transparent"
                Text { anchors.centerIn:parent;text:panel.it?"Annulla":"Cancel";color:Theme.Colors.text;font.pixelSize:Theme.Typography.sizeXS }
                MouseArea { id:area;anchors.fill:parent;hoverEnabled:true;onClicked:panel.cancelRequested(modelData.id) }
            }
        }
    }
    Ui.Scorrimento { bersaglio:list;anchors {right:parent.right;top:list.top;bottom:list.bottom} }
}

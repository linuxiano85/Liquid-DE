import QtQuick
import "../core" as Core
import "../settings" as S
import "../settings/windows" as Win

Item {
    id: choice
    property var options: []
    property string value: ""
    signal picked(string value)
    implicitHeight: 32
    Win.TendinaWindows {
        anchors.fill:parent
        visible:Core.DesktopStyle.attuale === "windows"
        voci:choice.options.map(function(row){return {valore:row.value,testo:row.label};})
        valore:choice.value
        onScelto:function(value){choice.picked(value);}
    }
    S.Tendina {
        anchors.fill:parent
        visible:Core.DesktopStyle.attuale !== "windows"
        options:choice.options
        value:choice.value
        onPicked:function(value){choice.picked(value);}
    }
}

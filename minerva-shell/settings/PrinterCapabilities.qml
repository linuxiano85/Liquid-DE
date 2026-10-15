import QtQuick
import "../core" as Core
import "../theme" as Theme
import "../windows11" as W

Column {
    id: features
    property var printer: ({})
    readonly property bool it: Core.Strings.lang === "it"
    readonly property bool windows: Core.DesktopStyle.attuale === "windows"
    readonly property real scale: windows ? W.Style.textScale : Theme.Typography.scala
    readonly property color textColor: windows ? W.Style.text : Theme.Colors.text
    readonly property color mutedColor: windows ? W.Style.muted : Theme.Colors.textMuted
    spacing: 7
    function paperName(name) {
        var parts=String(name||"").split("_");
        return parts.length >= 3 ? parts[1].toUpperCase() + " · " + parts[2] : String(name||"");
    }
    readonly property var rows: [
        {label:it?"Collegamento":"Connection",value:printer.connection==="usb"?"USB":printer.connection==="network"?(it?"Rete":"Network"):(it?"Non comunicato":"Not reported")},
        {label:it?"Formato predefinito":"Default paper",value:paperName(printer.paperDefault)},
        {label:it?"Fronte-retro automatico":"Automatic two-sided printing",value:(printer.sides||[]).some(function(s){return s.indexOf("two-sided")===0;}) ? (it?"Disponibile":"Available") : (it?"Non esposto dal driver":"Not exposed by driver")},
        {label:it?"Modalità colore":"Color modes",value:(printer.colors||[]).map(function(c){return c==="monochrome"?(features.it?"Bianco e nero":"Monochrome"):c==="color"?(features.it?"Colore":"Color"):c;}).join(" · ")},
        {label:it?"Risoluzioni del driver":"Driver resolutions",value:(printer.resolutions||[]).map(function(r){return r[0]+"×"+r[1]+(r[2]===4?" dpcm":" dpi");}).join(" · ")},
        {label:it?"Qualità offerte":"Available quality modes",value:(printer.qualities||[]).map(function(q){return q===3?(features.it?"Bozza":"Draft"):q===4?(features.it?"Normale":"Normal"):q===5?(features.it?"Alta":"High"):String(q);}).join(" · ")}
    ]
    Text {
        width:parent.width
        text:features.it?"Carta e funzioni di stampa":"Paper and print features"
        color:features.textColor
        font.family:features.windows?W.Style.font:Theme.Typography.fontDisplay
        font.pixelSize:15*features.scale
        font.weight:Font.DemiBold
    }
    Repeater {
        model:features.rows
        delegate: Text {
            required property var modelData
            width:features.width
            text:modelData.label+": "+(modelData.value||(features.it?"Non comunicato":"Not reported"))
            textFormat:Text.PlainText
            color:features.mutedColor
            wrapMode:Text.Wrap
            font.family:features.windows?W.Style.font:Theme.Typography.fontDisplay
            font.pixelSize:13*features.scale
        }
    }
}

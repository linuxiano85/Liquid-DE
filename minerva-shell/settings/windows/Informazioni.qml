import QtQuick
import Quickshell
import "../../core" as Core
import "../../windows11" as W

// Struttura dalla pagina Informazioni della VM di riferimento: quattro
// riepiloghi, nome del computer e specifiche espandibili. I valori sono Linux.
PaginaWindows {
    id: pagina
    objectName: "impostazioniInformazioniWindows"
    briciole: [{testo:W.Style.label("Sistema", "System"), pagina:"w-sistema"},
        {testo:W.Style.label("Informazioni sul sistema", "About")}]
    function ripristinaDestinazione(percorso) {
        if (percorso.pagina === "w-licenza" && dispositivo.pronto) {
            licenza.searchHighlighted = true;
            pagina.revealItem(licenza);
        }
    }
    RiepilogoDispositivo {
        id: dispositivo
        onProntoChanged: {
            if (pronto && pagina.finestra)
                Qt.callLater(function() { pagina.finestra.ripristinaVistaPagina(); });
        }
    }
    readonly property var dati: dispositivo.dati
    readonly property string mancante: dispositivo.pronto ? W.Style.label("Non disponibile", "Not available") : "…"
    function valore(value) { return value === undefined || value === null || value === "" ? mancante : String(value); }
    function gb(bytes, precision, allowZero) { return bytes > 0 || (allowZero && bytes === 0) ? (bytes/Math.pow(1024,3)).toLocaleString(W.Style.it ? Qt.locale("it_IT") : Qt.locale("en_US"), 'f', precision === undefined ? 2 : precision) + " GB" : mancante; }
    readonly property var hardware: [
        {key:"hostname", label:W.Style.label("Nome dispositivo", "Device name"), value:valore(dati.hostname)},
        {key:"cpu", label:W.Style.label("Processore", "Processor"), value:valore(dati.cpu)},
        {key:"memory", label:W.Style.label("RAM rilevata", "Detected RAM"), value:gb(dati.memory)},
        {key:"architecture", label:W.Style.label("Tipo sistema", "System type"), value:valore(dati.architecture)},
        {key:"graphics", label:W.Style.label("Scheda grafica", "Graphics card"), value:valore(dati.graphics ? dati.graphics.name : "")}
    ]
    readonly property var sistema: [
        {key:"distribution", label:W.Style.label("Distribuzione", "Distribution"), value:valore(dati.os)},
        {key:"version", label:W.Style.label("Versione", "Version"), value:valore(dati.osVersion)},
        {key:"kernel", label:"Kernel", value:valore(dati.kernel)},
        {key:"build", label:W.Style.label("Build sistema operativo", "OS build"), value:valore(dati.osBuild)}
    ]
    readonly property var liquid: [
        {key:"edition", label:W.Style.label("Edizione", "Edition"), value:"Liquid DE"},
        {key:"version", label:W.Style.label("Versione", "Version"), value:valore(dati.liquidVersion)},
        {key:"components", label:W.Style.label("Componenti", "Components"), value:"Minerva shell · minervad · minerva-wayland"},
        {key:"license", label:W.Style.label("Licenza", "License"), value:"GPL-3.0"}
    ]
    function copia(righe) { Quickshell.clipboardText = righe.map(function(row) { return row.label + "\t" + row.value; }).join("\n"); }
    Grid {
        id: riepiloghi
        width: parent.width
        columns: width >= 680 ? 4 : 2
        spacing: 12
        Repeater {
            model: [
                {key:"storage", icon:"hardDrive", label:W.Style.label("Archiviazione", "Storage"), value:pagina.gb(pagina.dati.storage ? pagina.dati.storage.total : 0, 0),
                    note:pagina.dati.storage ? pagina.gb(pagina.dati.storage.used, 0, true) + W.Style.label(" di ", " of ") + pagina.gb(pagina.dati.storage.total, 0) + W.Style.label(" utilizzati", " used") : ""},
                {key:"graphics", icon:"monitor", label:W.Style.label("Scheda grafica", "Graphics card"), value:pagina.gb(pagina.dati.graphics ? pagina.dati.graphics.memory : 0),
                    note:pagina.valore(pagina.dati.graphics ? pagina.dati.graphics.name : "")},
                {key:"memory", icon:"ram", label:W.Style.label("RAM rilevata", "Detected RAM"), value:pagina.gb(pagina.dati.memory), note:"RAM"},
                {key:"cpu", icon:"processor", label:W.Style.label("Processore", "Processor"), value:pagina.valore(pagina.dati.cpu),
                    note:pagina.dati.cpuFrequency > 0 ? (pagina.dati.cpuFrequency/1000000).toLocaleString(W.Style.it ? Qt.locale("it_IT") : Qt.locale("en_US"), 'f', 2) + " GHz" : pagina.dati.cpuCount ? pagina.dati.cpuCount + W.Style.label(" processori logici", " logical processors") : ""}
            ]
            delegate: Rectangle {
                id: scheda
                required property var modelData
                objectName: "infoRiepilogo-" + modelData.key
                width: (riepiloghi.width-(riepiloghi.columns-1)*riepiloghi.spacing)/riepiloghi.columns
                height: Math.max(141, titolo.implicitHeight + dato.implicitHeight + nota.implicitHeight + 58)
                radius: 8
                color: W.Style.card
                border.color: W.Style.cardStroke
                W.Glyph { x:16; y:16; width:14; height:14; name:scheda.modelData.icon; color:W.Style.muted }
                Text {
                    id: titolo
                    x:36; y:14; width:parent.width-x-12
                    text:scheda.modelData.label; textFormat:Text.PlainText
                    wrapMode:Text.Wrap; font.family:W.Style.font; font.pixelSize:12*W.Style.textScale; color:W.Style.muted
                }
                Text {
                    id: dato
                    x:16; y:titolo.y+titolo.implicitHeight+10; width:parent.width-32
                    text:scheda.modelData.value; textFormat:Text.PlainText
                    wrapMode:Text.Wrap; font.family:W.Style.font; font.pixelSize:14*W.Style.textScale; font.weight:Font.DemiBold; color:W.Style.text
                }
                Text {
                    id: nota
                    x:16; anchors.bottom:parent.bottom; anchors.bottomMargin:16; width:parent.width-32
                    text:scheda.modelData.note; textFormat:Text.PlainText
                    wrapMode:Text.Wrap; font.family:W.Style.font; font.pixelSize:12*W.Style.textScale; color:W.Style.muted
                }
            }
        }
    }
    Item { width:1; height:48 }
    SchedaImpostazione {
        objectName:"infoNomeDispositivo"
        titolo:pagina.valore(pagina.dati.hostname)
        descrizione:pagina.valore(pagina.dati.model)
    }
    Repeater {
        model: [
            {key:"device",icon:"informazioni",title:W.Style.label("Specifiche dispositivo", "Device specifications"),rows:pagina.hardware},
            {key:"system",icon:"monitor",title:W.Style.label("Specifiche Linux", "Linux specifications"),rows:pagina.sistema},
            {key:"liquid",icon:"apps",title:W.Style.label("Specifiche Liquid DE", "Liquid DE specifications"),rows:pagina.liquid}
        ]
        delegate: EspansoreImpostazione {
            id: specifiche
            required property var modelData
            objectName:"infoSpecifiche-"+modelData.key
            titolo:modelData.title
            icona:modelData.icon
            aperto:true
            comando:PulsanteWindows {
                objectName:"infoCopia-"+specifiche.modelData.key
                implicitWidth:90
                testo:W.Style.label("Copia", "Copy")
                enabled:dispositivo.pronto
                onPremuto:pagina.copia(specifiche.modelData.rows)
            }
            Specifiche { prefisso:"infoDato-"+specifiche.modelData.key; righe:specifiche.modelData.rows }
        }
    }
    SchedaImpostazione {
        id:licenza
        objectName:"infoLicenza"
        titolo:W.Style.label("Licenza del progetto", "Project license")
        descrizione:"GNU General Public License v3.0"
        icona:"document"
        porta:true
        onAttivata:Qt.openUrlExternally("https://github.com/linuxiano85/Liquid-DE/blob/principale/LICENSE")
    }
    SchedaImpostazione {
        objectName:"infoRipristino"
        titolo:W.Style.label("Ripristino", "Recovery")
        descrizione:W.Style.label("Ripristina le preferenze di Liquid DE", "Reset Liquid DE preferences")
        icona:"restore"
        porta:true
        onAttivata:if(pagina.finestra) pagina.finestra.apriWindows("w-ripristino")
    }
}

import QtQuick
import "../../core" as Core
import "../../windows11" as W
import ".." as S
import "Dati.js" as Dati

PaginaWindows {
    id: pagina
    readonly property var selezionate: Core.Ipc.get("windows11.startFolders", [])
    briciole: [
        { testo: Dati.t(Core.Strings.lang, "personalizzazione"), pagina: "w-personalizzazione" },
        { testo: "Start", pagina: "w-start" },
        { testo: W.Style.label("Cartelle", "Folders") }
    ]

    function scegli(id, presente) {
        var prossime = pagina.selezionate.filter(function(value) { return value !== id; });
        if (presente)
            prossime.push(id);
        Core.Ipc.setSetting("windows11.startFolders", prossime);
    }

    Text {
        width: parent.width
        height: implicitHeight + 32
        text: W.Style.label("Scegli quali cartelle vengono visualizzate su Start accanto al pulsante Arresta.",
                            "Choose which folders appear on Start next to the Power button.")
        color: W.Style.muted
        font.family: W.Style.font
        font.pixelSize: 14
        wrapMode: Text.WordWrap
    }
    Repeater {
        model: W.StartPlaces.entries
        delegate: SchedaImpostazione {
            required property var modelData
            objectName: "startCartellaScheda-" + modelData.id
            titolo: W.Style.label(modelData.it, modelData.en)
            icona: modelData.icon
            disponibile: modelData.available !== false
            S.ToggleSwitch {
                objectName: "startCartella-" + modelData.id
                Accessible.name: W.Style.label(modelData.it, modelData.en)
                checked: pagina.selezionate.indexOf(modelData.id) >= 0
                onToggled: function(v) { pagina.scegli(modelData.id, v); }
            }
        }
    }
}

import QtQuick
import "../../windows11" as W

// Ore e minuti separati evitano salvataggi parziali o un testo non valido.
// Entrambe le tendine mantengono la navigazione da tastiera e la scrollbar.
Row {
    id: ora
    property string valore: "00:00"
    property string etichetta: ""
    signal scelta(string value)
    spacing: 4
    width: implicitWidth
    function voci(count) {
        var result = [];
        for (var i = 0; i < count; i++) {
            var text = String(i).padStart(2, "0");
            result.push({valore:text, testo:text});
        }
        return result;
    }
    TendinaWindows {
        objectName: ora.objectName + "-ore"
        width: 68
        valore: ora.valore.slice(0, 2)
        voci: ora.voci(24)
        Accessible.name: ora.etichetta + W.Style.label(": ore", ": hours")
        onScelto: function(value) { ora.scelta(value + ora.valore.slice(2)); }
    }
    Text {
        height: 32
        verticalAlignment: Text.AlignVCenter
        text: ":"
        color: W.Style.text
        font.family: W.Style.font
        font.pixelSize: 14
    }
    TendinaWindows {
        objectName: ora.objectName + "-minuti"
        width: 68
        valore: ora.valore.slice(3)
        voci: ora.voci(60)
        Accessible.name: ora.etichetta + W.Style.label(": minuti", ": minutes")
        onScelto: function(value) { ora.scelta(ora.valore.slice(0, 3) + value); }
    }
}

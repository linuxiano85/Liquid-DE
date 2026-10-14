import QtQuick
import "../core" as Core
import "../theme" as Theme
import "../ui" as Ui

// Le immagini Windows sono risorse vettoriali originali, senza rete né
// rasterizzazione a dimensioni enormi. Un tema scelto esplicitamente prevale.
Item {
    id: icon

    property string name: "document"
    property color color: Theme.Colors.text
    property real thickness: 1.7
    readonly property string family: name.indexOf("cartella-") === 0 ? "folder" : name
    readonly property bool artwork: Core.DesktopStyle.attuale === "windows" && Core.Ipc.get("icons.style", "minerva") === "minerva" && ["folder", "document", "pdf", "table", "slides", "archive", "image", "music", "video", "code", "font", "disco", "trash"].indexOf(family) >= 0
    readonly property string asset: family === "disco" ? "drive" : family
    readonly property string folderMark: ({
        "cartella-documenti": "document",
        "cartella-scaricati": "back",
        "cartella-immagini": "image",
        "cartella-musica": "music",
        "cartella-video": "video",
        "cartella-scrivania": "monitor",
        "cartella-modelli": "document",
        "cartella-pubblici": "user"
    })[name] || ""

    Ui.Icon {
        anchors.fill: parent
        visible: !icon.artwork || picture.status === Image.Error
        // Un file vuole il disegno a colori del tema anche in elenco, non il
        // segno da pannello che molti temi hanno a 22 pixel (vedi `Icon.qml`).
        sempreGrande: true
        name: icon.name
        color: icon.color
        thickness: icon.thickness
    }

    Image {
        id: picture

        anchors.fill: parent
        visible: icon.artwork && status !== Image.Error
        source: icon.artwork ? Qt.resolvedUrl("artwork/" + icon.asset + ".svg") : ""
        sourceSize: Qt.size(Math.max(1, Math.round(width)), Math.max(1, Math.round(height)))
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
    }

    Ui.Icon {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.5
        width: parent.width * 0.32
        height: width
        visible: icon.artwork && icon.folderMark !== "" && picture.status === Image.Ready
        name: icon.folderMark
        alwaysDrawn: true
        thickness: 2.3
        color: "#91600e"
        rotation: icon.name === "cartella-scaricati" ? -90 : 0
    }

}

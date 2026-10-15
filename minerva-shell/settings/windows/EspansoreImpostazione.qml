import QtQuick
import "../../windows11" as W

// EspansoreImpostazione — La scheda che si apre di Impostazioni di Windows 11
// (il SettingsExpander di WinUI): la testata è una SchedaImpostazione con il
// suo comando e, a destra, la freccia in giù o in su; aperta, sotto ci sono
// le righe, separate da un filo, col testo allineato al titolo della testata.
//
// Le righe sono i figli: di solito altre SchedaImpostazione con
// `interna: true`, oppure contenuti liberi (la griglia dei colori, le
// immagini recenti).
Rectangle {
    id: espansore

    property alias icona: testa.icona
    property alias immagine: testa.immagine
    property alias titolo: testa.titolo
    property alias descrizione: testa.descrizione
    property alias disponibile: testa.disponibile
    property bool aperto: false
    /// Falso: si comporta da scheda semplice, senza freccia né righe (come
    /// «Scegli la modalità» quando non è «Personalizzata»).
    property bool espandibile: true
    /// Il comando nella testata (accanto alla freccia).
    property alias comando: testa.comando
    default property alias righe: corpo.data

    width: parent ? parent.width : 400
    implicitHeight: testa.height + (espansore.aperto && espansore.espandibile ? corpo.implicitHeight : 0)
    height: implicitHeight
    radius: 4
    color: W.Style.card
    border.width: 1
    border.color: W.Style.cardStroke
    clip: true

    SchedaImpostazione {
        id: testa
        interna: true
        // La testata è la prima riga: niente filo sopra.
        filoSopra: false
        width: parent.width
    }

    // La freccia: un pulsante da 32 a destra della testata.
    Rectangle {
        id: freccia
        objectName: espansore.objectName ? espansore.objectName + "-espandi" : ""
        anchors.right: parent.right
        anchors.rightMargin: 8
        y: (testa.height - height) / 2
        width: 32
        height: 32
        radius: 4
        visible: testa.disponibile && espansore.espandibile
        color: presaFreccia.pressed ? W.Style.pressed : presaFreccia.containsMouse ? W.Style.hover : "transparent"
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: espansore.aperto ? (W.Style.it ? "Comprimi" : "Collapse")
                                          : (W.Style.it ? "Espandi" : "Expand")
        Keys.onReturnPressed: espansore.aperto = !espansore.aperto
        Keys.onSpacePressed: espansore.aperto = !espansore.aperto
        border.width: activeFocus ? 2 : 0
        border.color: W.Style.text

        W.Glyph {
            anchors.centerIn: parent
            width: 12
            height: 12
            name: "chevron"
            rotation: espansore.aperto ? 180 : 0
            color: W.Style.text
        }
        MouseArea {
            id: presaFreccia
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: espansore.aperto = !espansore.aperto
        }
    }

    // La testata si apre anche cliccandola fuori dal comando, come in
    // Windows.
    MouseArea {
        anchors.left: parent.left
        anchors.top: parent.top
        width: testa.width * 0.55
        height: testa.height
        enabled: testa.disponibile && espansore.espandibile
        cursorShape: Qt.PointingHandCursor
        onClicked: espansore.aperto = !espansore.aperto
    }

    Column {
        id: corpo
        y: testa.height
        width: parent.width
        visible: espansore.aperto && espansore.espandibile
    }

    // Il comando della testata non deve finire sotto la freccia.
    states: State {
        name: "conFreccia"
        when: freccia.visible
        PropertyChanges { target: testa; width: espansore.width - 40 }
    }
}

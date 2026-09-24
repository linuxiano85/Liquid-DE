import QtQuick
import "../theme" as Theme
import "../ui" as Ui

// SideEntry — Una riga della colonna di sinistra.
//
// Una sola forma per tre cose diverse — una cartella di casa, un percorso
// fissato, un disco — perché per chi guarda SONO la stessa cosa: un posto
// dove andare. Cambia quello che ci si può fare sopra, non come si legge.
//
// Il pulsante che toglie o espelle compare solo al passaggio del puntatore.
// Una fila di crocette sempre visibili trasforma un elenco di posti in un
// elenco di cose da cancellare, e sposta l'attenzione esattamente dove non
// serve.
Rectangle {
    id: entry

    property string icon: "folder"
    property string label: ""
    property string detail: ""
    property string path: ""

    /// Spento: c'è, ma non è pronto. Un disco collegato e non montato.
    property bool dimmed: false
    /// Si può togliere dall'elenco (percorso fissato).
    property bool removable: false
    /// Si può espellere (disco montato e staccabile).
    property bool ejectable: false

    /// La voce della cartella che si sta guardando.
    property bool attiva: false
    /// La goccia della colonna (`ui/Goccia.qml`): è lei a colorare la voce
    /// sotto il puntatore e quella attiva, scivolando dall'una all'altra.
    property Item goccia: null
    onAttivaChanged: if (entry.attiva && entry.goccia) entry.goccia.attiva = entry
    Component.onCompleted: if (entry.attiva && entry.goccia) entry.goccia.attiva = entry

    /// Ci hanno lasciato sopra dei file. Il percorso lo sa già chi ascolta:
    /// è `entry.path`.
    signal rilasciato(var sorgenti)
    /// Acceso mentre ci si passa sopra trascinando: senza, si lascia la roba
    /// al buio e si scopre dov'è finita dopo.
    property bool bersaglio: false

    DropArea {
        anchors.fill: parent
        keys: ["minerva/file", "text/uri-list"]
        // Le voci spente sono dischi non montati: non hanno un percorso in
        // cui mettere niente, e accettarli sarebbe una promessa falsa.
        enabled: !entry.dimmed && entry.path !== ""
        onEntered: entry.bersaglio = true
        onExited: entry.bersaglio = false
        onDropped: function (d) {
            entry.bersaglio = false;
            var sorgenti = (d.source && d.source.percorsi)
                           ? d.source.percorsi
                           : Files.percorsiDaUrl(d.urls);
            if (sorgenti.length > 0)
                entry.rilasciato(sorgenti);
            d.accept();
        }
    }

    signal chosen()
    signal removed()
    signal ejected()
    /// Tasto destro sulla voce. Senza un punto, come `Pane.menuRequested`:
    /// chi riceve apre il menu dove sta il puntatore, e il punto calcolato qui
    /// non lo leggeva nessuno.
    signal secondary()

    readonly property bool hasAction: entry.removable || entry.ejectable

    height: entry.detail !== "" ? 40 : 32
    radius: Theme.Effects.radiusSM
    // Il passaggio del mouse e la voce attiva li disegna la goccia; qui resta
    // solo il bersaglio di un trascinamento, che è un'altra cosa.
    color: entry.bersaglio ? Qt.alpha(Theme.Colors.accent, 0.34) : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
    opacity: entry.dimmed ? 0.6 : 1

    Ui.Icon {
        id: entryIcon
        anchors.left: parent.left
        anchors.leftMargin: Theme.Effects.space2
        anchors.verticalCenter: parent.verticalCenter
        width: 15; height: 15
        name: entry.icon
        color: mouse.containsMouse || entry.attiva ? Theme.Colors.accent
                                                   : Theme.Colors.textFaint
        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
    }

    Text {
        id: entryLabel
        anchors.left: entryIcon.right
        anchors.leftMargin: Theme.Effects.space2
        anchors.right: action.visible ? action.left : parent.right
        anchors.rightMargin: Theme.Effects.space2
        // Un'ancora sola, spostata, invece di due accese a turno: un disco
        // che compare e sparisce cambia `detail` mentre la riga è viva, e
        // `undefined` non stacca l'ancora messa prima — restavano attaccate
        // tutte e due. Stesso difetto di `ui/TitleBarContent.qml`.
        //
        // Nove pixel in su: la riga del dettaglio sta sotto (`anchors.top:
        // entryLabel.bottom`) ed è alta quanto il carattere piccolo, quindi
        // le due insieme restano centrate.
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: entry.detail !== "" ? -9 : 0
        elide: Text.ElideMiddle
        text: entry.label
        color: entry.attiva ? Theme.Colors.text : Theme.Colors.textMuted
        font.family: Theme.Typography.fontDisplay
        font.weight: Theme.Typography.weightRegular
        font.pixelSize: Theme.Typography.sizeSM
    }

    Text {
        anchors.left: entryLabel.left
        anchors.right: entryLabel.right
        anchors.top: entryLabel.bottom
        visible: entry.detail !== ""
        elide: Text.ElideMiddle
        text: entry.detail
        color: Theme.Colors.textFaint
        font.family: Theme.Typography.fontMono
        font.pixelSize: Theme.Typography.sizeXS
    }

    // Sopra l'area della riga, e non è un dettaglio di disegno: l'area che
    // copre tutta la riga è dichiarata dopo, quindi senza questo `z` starebbe
    // SOPRA il pulsante e se lo mangerebbe. Il pulsante si vedrebbe, non
    // reagirebbe al passaggio, e cliccandolo si aprirebbe la cartella invece
    // di toglierla — un guasto che a guardare lo schermo non si vede.
    Rectangle {
        id: action
        z: 2
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 20; height: 20
        radius: Theme.Effects.radiusXS
        visible: entry.hasAction && (mouse.containsMouse || actionMouse.containsMouse)
        color: actionMouse.containsMouse ? Qt.alpha(Theme.Colors.danger, 0.2)
                                         : "transparent"

        Ui.Icon {
            anchors.centerIn: parent
            width: 12; height: 12
            name: entry.ejectable ? "logout" : "close"
            color: actionMouse.containsMouse ? Theme.Colors.danger
                                             : Theme.Colors.textFaint
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (entry.ejectable)
                    entry.ejected();
                else
                    entry.removed();
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onContainsMouseChanged: if (entry.goccia) entry.goccia.punta(entry, mouse.containsMouse)
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(evento) {
            if (evento.button === Qt.RightButton)
                entry.secondary();
            else
                entry.chosen();
        }
    }
}

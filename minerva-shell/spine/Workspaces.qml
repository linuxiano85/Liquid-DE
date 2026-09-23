import QtQuick
import "../core" as Core
import "../theme" as Theme

// Workspaces — Le scrivanie, come pastiglie che si allungano.
//
// La scrivania attiva non cambia colore: cambia FORMA. Da punto diventa
// pastiglia allungata, e il movimento fra una e l'altra è continuo.
//
// Perché la forma e non il colore: un puntino colorato fra puntini grigi si
// distingue solo se si guarda apposta. Una forma diversa si nota con la coda
// dell'occhio, che è esattamente come si guarda una barra di stato.
//
// Il numero si legge solo su quella attiva. Sulle altre sarebbe rumore: se
// una scrivania è vuota non importa quale numero abbia, importa che sia
// libera.
Item {
    id: workspaces

    /// Numero minimo di scrivanie sempre mostrate. Averne un numero fisso
    /// rende il bersaglio stabile: la quarta pastiglia è sempre nello stesso
    /// punto, quindi ci si arriva senza guardare.
    property int minimumCount: 5

    readonly property var list: Core.Compositore.scrivanie

    readonly property int focusedIndex: {
        var n = parseInt(Core.Compositore.nomeScrivaniaAttiva);
        return isNaN(n) ? 0 : n - 1;
    }

    /// Quali indici (0-based) hanno finestre aperte.
    readonly property var occupied: {
        var set = {};
        for (var i = 0; i < list.length; i++) {
            var n = parseInt(list[i].nome);
            if (!isNaN(n))
                set[n - 1] = true;
        }
        return set;
    }

    readonly property int count: {
        var maximum = workspaces.minimumCount;
        for (var i = 0; i < list.length; i++) {
            var n = parseInt(list[i].nome);
            if (!isNaN(n) && n > maximum)
                maximum = n;
        }
        return maximum;
    }

    Component.onCompleted: Core.Compositore.aggiornaScrivanie()

    // Il socket eventi di Hyprland notifica i cambi; senza questo le pastiglie
    // resterebbero ferme finché non si tocca qualcos'altro.
    Connections {
        target: Core.Compositore
        function onScrivanieCambiate() { Core.Compositore.aggiornaScrivanie(); }
    }

    implicitWidth: row.implicitWidth + Theme.Effects.space3 * 2
    implicitHeight: Theme.Effects.barButton

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.Colors.sunken
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.Effects.space1

        Repeater {
            model: workspaces.count

            delegate: Item {
                id: pill
                required property int index

                readonly property bool isActive: index === workspaces.focusedIndex
                readonly property bool isOccupied: workspaces.occupied[index] === true

                width: isActive ? 26 : 10
                height: 10
                anchors.verticalCenter: parent.verticalCenter

                Behavior on width {
                    NumberAnimation {
                        duration: Theme.Motion.panel
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Theme.Motion.emerge
                    }
                }

                Rectangle {
                    id: dot
                    anchors.fill: parent
                    radius: height / 2

                    color: pill.isActive ? Theme.Colors.accent
                         : pill.isOccupied ? Theme.Colors.textFaint
                         : Qt.alpha(Theme.Colors.text, 0.13)

                    Behavior on color { ColorAnimation { duration: Theme.Motion.quick } }

                    // Alone solo sulla pastiglia attiva
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 10
                        height: parent.height + 10
                        radius: height / 2
                        color: Theme.Colors.accent
                        opacity: pill.isActive ? 0.22 : 0
                        z: -1
                        Behavior on opacity { NumberAnimation { duration: Theme.Motion.quick } }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: pill.index + 1
                    visible: pill.isActive
                    opacity: pill.isActive ? 1 : 0
                    color: Theme.Colors.textOnAccent
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: 9
                    Behavior on opacity { NumberAnimation { duration: Theme.Motion.instant } }
                }

                // Il bersaglio cliccabile è più grande della pastiglia: dieci
                // pixel sono impossibili da colpire, trenta no.
                MouseArea {
                    anchors.centerIn: parent
                    width: Math.max(parent.width, 22) + 6
                    height: Theme.Effects.barButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Core.Compositore.vaiAScrivania(pill.index + 1)
                }
            }
        }
    }

    // Rotella sopra le scrivanie: passa alla precedente o alla successiva.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
            Core.Compositore.scrivaniaVicina(wheel.angleDelta.y < 0);
        }
    }
}

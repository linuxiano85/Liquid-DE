import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core

// Toasts — Gli avvisi che compaiono all'arrivo di una notifica.
//
// Entrano da destra e scompaiono da sole. Sono l'unico elemento della shell
// che si presenta senza essere stato chiamato, quindi valgono due regole:
//
//  · non rubano mai il fuoco (si sta scrivendo, e un avviso che intercetta i
//    tasti fa perdere una frase);
//  · restano il tempo che chiede l'applicazione, ma almeno tre secondi e mai
//    più di dieci — alcune applicazioni chiedono timeout assurdi.
//
// Il passaggio del mouse ferma il conto alla rovescia: se lo si sta leggendo
// non deve sparire in faccia.
PanelWindow {
    id: toasts

    WlrLayershell.namespace: "quickshell"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors { top: true; right: true }
    margins.top: toasts.margineAlto
    margins.right: Theme.Effects.space3

    // ── Gli avvisi restano in alto a destra, e il margine se lo fa dire ──
    //
    // Stava scritto `barHeight + space3`, cioè «sotto la barra» — vero finché
    // la barra poteva stare solo in cima. Adesso può stare in fondo, e in quel
    // caso quei 44 pixel sono un buco: gli avvisi comparirebbero staccati dal
    // bordo senza nessun motivo visibile.
    //
    // Non si legge però l'impostazione: si chiede al compositore quanto spazio
    // è riservato in alto su QUESTO schermo. Così il conto vale anche quando
    // in cima c'è la dock invece della barra, o tutte e due, senza che questo
    // file debba sapere cosa sono — è la stessa fonte che usa la griglia della
    // scrivania, e per la stessa ragione.
    //
    // Il ripiego, per il mezzo secondo prima che il compositore risponda, è
    // l'unico posto in cui `inBasso` serve davvero.
    property bool inBasso: false

    readonly property var spazio: {
        var nome = toasts.screen ? toasts.screen.name : "";
        var lista = Core.Windows.spaziPerMonitor || [];
        for (var i = 0; i < lista.length; i++)
            if (lista[i].nome === nome)
                return lista[i];
        return null;
    }

    readonly property int margineAlto: toasts.spazio
            ? Math.max(0, toasts.spazio.y - toasts.spazio.sy) + Theme.Effects.space3
            : (toasts.inBasso ? Theme.Effects.space3
                              : Theme.Effects.barHeight + Theme.Effects.space3)

    implicitWidth: 380
    implicitHeight: Math.max(1, column.implicitHeight)
    /// Spenti dove qualcun altro racconta le notifiche (l'Isola).
    property bool spenti: false
    visible: !spenti && toastModel.count > 0
    color: "transparent"

    // Solo i toast visibili; la cronologia completa vive nel singleton.
    ListModel { id: toastModel }

    readonly property int maximumVisible: 4

    Connections {
        target: Core.Notifications
        function onArrived(item) {
            toastModel.insert(0, {
                "appName": item.appName,
                "summary": item.summary,
                "body": item.body,
                "urgency": item.urgency,
                "timeout": Math.max(3000, Math.min(10000, item.timeout)),
                // ── L'id, e non la notifica ─────────────────────────────
                //
                // Un `ListModel` porta testo e numeri: un oggetto ci passa
                // dentro e ne esce diverso, e con lui se ne andrebbe proprio
                // `invoke()`. Si porta l'id e la notifica vera si ritrova in
                // `Core.Notifications` al momento del clic.
                "nid": String(item.id),
                "apribile": Core.Notifications.siPuoAprire(item)
            });
            while (toastModel.count > toasts.maximumVisible)
                toastModel.remove(toastModel.count - 1);
        }
    }

    Column {
        id: column
        width: parent.width
        spacing: Theme.Effects.space2

        Repeater {
            model: toastModel

            delegate: Rectangle {
                id: toast

                required property int index
                required property string appName
                required property string summary
                required property string body
                required property int urgency
                required property int timeout
                required property string nid
                required property bool apribile

                width: column.width
                implicitHeight: body_.implicitHeight + Theme.Effects.space4 * 2
                height: implicitHeight
                radius: Theme.Effects.radiusMD
                color: Theme.Colors.panel
                border.width: 1
                border.color: Theme.Colors.edge

                readonly property color tone: urgency === 2 ? Theme.Colors.danger
                                            : urgency === 0 ? Theme.Colors.textFaint
                                            : Theme.Colors.accent

                // Entrata da destra
                x: width
                opacity: 0
                Component.onCompleted: enter.start()

                ParallelAnimation {
                    id: enter
                    NumberAnimation {
                        target: toast; property: "x"; to: 0
                        duration: Theme.Motion.panel
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Theme.Motion.emerge
                    }
                    NumberAnimation {
                        target: toast; property: "opacity"; to: 1
                        duration: Theme.Motion.quick
                    }
                }

                ParallelAnimation {
                    id: leave
                    NumberAnimation {
                        target: toast; property: "x"; to: toast.width
                        duration: Theme.Motion.exit
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Theme.Motion.retract
                    }
                    NumberAnimation {
                        target: toast; property: "opacity"; to: 0
                        duration: Theme.Motion.exit
                    }
                    onFinished: if (toast.index >= 0 && toast.index < toastModel.count)
                                    toastModel.remove(toast.index)
                }

                Timer {
                    id: life
                    interval: toast.timeout
                    running: !hover.containsMouse
                    onTriggered: leave.start()
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: parent.height - Theme.Effects.space4
                    radius: 1.5
                    color: toast.tone
                }

                Column {
                    id: body_
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space4 + 4
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                        width: parent.width
                        text: toast.appName
                        elide: Text.ElideRight
                        color: toast.tone
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXS
                        font.weight: Theme.Typography.weightBold
                        font.letterSpacing: Theme.Typography.trackingLabel
                    }

                    Text {
                        width: parent.width
                        text: toast.summary
                        visible: text !== ""
                        elide: Text.ElideRight
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeMD
                        font.weight: Theme.Typography.weightSemiBold
                    }

                    Text {
                        width: parent.width
                        text: toast.body
                        visible: text !== ""
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                }

                // Barra del tempo residuo lungo il bordo inferiore: dice
                // quanto manca alla sparizione, così non coglie di sorpresa.
                Rectangle {
                    id: countdown
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.bottomMargin: 3
                    anchors.leftMargin: Theme.Effects.space3
                    height: 2
                    radius: 1
                    color: Qt.alpha(toast.tone, 0.45)
                    width: toast.width - Theme.Effects.space3 * 2

                    NumberAnimation {
                        id: drain
                        target: countdown
                        property: "width"
                        to: 0
                        duration: toast.timeout
                        easing.type: Easing.Linear
                        running: !hover.containsMouse
                    }
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    // La mano a dito solo se cliccare fa qualcosa: prometterla
                    // su una notifica inerte è dire il falso col puntatore.
                    cursorShape: toast.apribile ? Qt.PointingHandCursor
                                                : Qt.ArrowCursor
                    // ── Cliccare APRE ───────────────────────────────────
                    //
                    // Prima chiudeva e basta. Giacomo: «se scatto uno
                    // screenshot e compare la notifica e ci clicco devo poter
                    // vedere l'immagine con anteprima [...] e questo per tutte
                    // le notifiche».
                    //
                    // Cosa voglia dire «aprire» lo decide
                    // `Core.Notifications.apri`: prima l'azione predefinita
                    // che ha mandato il programma, poi il file che la notifica
                    // dichiara. L'avviso si chiude comunque — anche quando non
                    // c'era niente da aprire, che è come si comportava prima.
                    onClicked: {
                        Core.Notifications.apriPerId(toast.nid);
                        leave.start();
                    }
                }
            }
        }
    }
}

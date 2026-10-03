import QtQuick

import "../theme" as Theme
import "../ui" as Ui

// Il diario della Fucina: la barra, e le righe che arrivano dal demone.
//
// È il registro di Manutenzione con due differenze, e tutte e due vengono da
// `make`:
//
//  · **le righe arrivano a mazzi**, fino a duecento alla volta: `scriviMolte`
//    le aggiunge tutte e scorre una volta sola, non duecento;
//  · **il fondo scala può non esserci**. Alla prima compilazione nessuno sa
//    quanti file ci sono da compilare, e una barra che inventa una
//    percentuale mente. Allora si dice il conto — «1.283 file» — e la barra
//    resta spenta. Dalla seconda volta il conto di prima fa da fondo scala.
Item {
    id: diario

    /// Da 0 a 1; -1 spenta.
    property real avanzamento: -1
    readonly property bool attivo: diario.avanzamento >= 0

    /// Una riga sopra la barra: che cosa si sta facendo adesso.
    property string stato: ""

    property string titolo: "Diario"

    /// Quante righe si tengono. Un errore di compilazione si legge dal fondo,
    /// e quattrocento righe sono più di quante ne servano a capirlo.
    readonly property int massimo: 400

    function scrivi(testo) {
        if (!testo || testo === "") return;
        modello.append({ "testo": String(testo),
                         "quando": Qt.formatTime(new Date(), "HH:mm:ss") });
        diario._pota();
        elenco.positionViewAtEnd();
    }

    function scriviMolte(righe) {
        if (!righe || righe.length === 0) return;
        var ora = Qt.formatTime(new Date(), "HH:mm:ss");
        for (var i = 0; i < righe.length; i++)
            modello.append({ "testo": String(righe[i]), "quando": ora });
        diario._pota();
        elenco.positionViewAtEnd();
    }

    function pulisci() { modello.clear(); }

    function _pota() {
        if (modello.count > diario.massimo)
            modello.remove(0, modello.count - diario.massimo);
    }

    ListModel { id: modello }

    Text {
        id: intestazione
        anchors.top: parent.top
        anchors.left: parent.left
        text: diario.titolo.toUpperCase()
        color: Theme.Colors.textFaint
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: Theme.Typography.sizeXS
        font.weight: Theme.Typography.weightSemiBold
        font.letterSpacing: Theme.Typography.trackingLabel
    }

    Text {
        anchors.right: parent.right
        anchors.left: intestazione.right
        anchors.leftMargin: Theme.Effects.space3
        anchors.baseline: intestazione.baseline
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft
        text: diario.stato
        color: Theme.Colors.textMuted
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: Theme.Typography.sizeXS
        font.features: ({ "tnum": 1 })
    }

    Rectangle {
        id: pista
        anchors.top: intestazione.bottom
        anchors.topMargin: diario.attivo ? Theme.Effects.space2 : 0
        anchors.left: parent.left
        anchors.right: parent.right
        height: diario.attivo ? 6 : 0
        visible: height > 0
        radius: 3
        color: Theme.Colors.sunken

        Behavior on height {
            NumberAnimation { duration: Theme.Motion.quick; easing.type: Easing.OutCubic }
        }

        Rectangle {
            height: parent.height
            radius: 3
            width: parent.width * Math.max(0, Math.min(1, diario.avanzamento))
            color: Theme.Colors.accent

            Behavior on width {
                NumberAnimation { duration: Theme.Motion.quick; easing.type: Easing.OutCubic }
            }
        }
    }

    Rectangle {
        anchors.top: pista.bottom
        anchors.topMargin: Theme.Effects.space2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        radius: Theme.Effects.radiusSM
        color: Theme.Colors.sunken
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge

        ListView {
            id: elenco
            anchors.fill: parent
            anchors.margins: Theme.Effects.space2
            clip: true
            model: modello
            spacing: 1
            cacheBuffer: 2000
            boundsBehavior: Flickable.StopAtBounds

            delegate: Row {
                width: elenco.width
                spacing: Theme.Effects.space2

                Text {
                    id: ora
                    width: 56
                    text: model.quando
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeXS
                }

                Text {
                    width: elenco.width - ora.width - Theme.Effects.space2
                    text: model.testo
                    // Gli avvisi del controllo del .config cominciano con ⚠ e
                    // si devono vedere in mezzo a mille righe di `CC`.
                    color: model.testo.indexOf("⚠") === 0 ? Theme.Colors.warning
                         : (model.testo.indexOf("──") === 0 ? Theme.Colors.text
                                                            : Theme.Colors.textMuted)
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeXS
                    font.weight: model.testo.indexOf("──") === 0
                                 ? Theme.Typography.weightSemiBold
                                 : Theme.Typography.weightRegular
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }
            }
        }

        Ui.Scorrimento {
            bersaglio: elenco
            anchors {
                right: elenco.right
                top: elenco.top
                bottom: elenco.bottom
            }
        }
    }
}

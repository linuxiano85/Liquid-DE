import QtQuick
import "../theme" as Theme

// Slider — Cursore a barra piena, con l'icona dentro.
//
// Non è un filo con una pallina sopra: è una barra spessa che si riempie, e
// l'icona sta dentro la barra a sinistra. Due motivi concreti:
//
//  · il bersaglio è tutta l'altezza della barra invece dei 18px della pallina,
//    quindi si prende al primo colpo anche senza mirare;
//  · il livello si legge come quantità (quanto è pieno) invece che come
//    posizione (dov'è la pallina), che è il modo in cui si pensa al volume.
//
// Trascinare aggiorna in tempo reale; il valore definitivo si conferma al
// rilascio, così chi ascolta la modifica non viene sommerso.
Item {
    id: slider

    property real value: 50
    property real from: 0
    property real to: 100
    property string icon: ""
    property color accent: Theme.Colors.accent
    /// Mostra la percentuale a destra
    property bool showValue: true

    signal moved(real value)
    signal released(real value)

    implicitHeight: 44

    readonly property real _fraction: {
        var span = to - from;
        return span <= 0 ? 0 : Math.max(0, Math.min(1, (value - from) / span));
    }

    /// Dove finisce davvero il riempimento. Serve per decidere il colore di
    /// icona ed etichetta: sopra il riempimento vuole un colore scuro, sul
    /// fondo vuoto uno chiaro. Confrontare la FRAZIONE con una soglia fissa
    /// non basta — a 0.95 il riempimento copre l'icona ma non l'etichetta, e
    /// una delle due sparisce.
    ///
    /// ── A pixel interi ───────────────────────────────────────────────────
    ///
    /// `Math.round`, e non e' un vezzo: la shell disegna col processore, e con
    /// quel motore una geometria a virgola lascia sul posto una riga di pixel
    /// che nessuno ridipinge. E' la stessa regola scritta in
    /// `ui/Scorrimento.qml`, arrivata li' dopo la caccia ai «+».
    readonly property real _fillEnd: Math.round(Math.max(height, width * _fraction))

    Rectangle {
        id: track
        anchors.fill: parent
        radius: Theme.Effects.radiusSM
        color: Theme.Colors.sunken
        clip: true

        // Riempimento con sfumatura: dà volume alla barra e fa capire da che
        // parte cresce anche in un fermo immagine.
        Rectangle {
            id: fill
            width: slider._fillEnd
            height: parent.height
            radius: parent.radius

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.alpha(slider.accent, 0.45) }
                GradientStop { position: 1.0; color: Qt.alpha(slider.accent, 0.85) }
            }

            // ── Niente animazione sulla LARGHEZZA ────────────────────────
            //
            // Qui c'era un `Behavior on width`. Col renderer software una
            // geometria che cambia a ogni fotogramma lascia in giro i pixel
            // di quelli prima: Qt ridipinge solo cio' che dichiara sporco, e
            // una barra che si allunga non dichiara sporco quello che si e'
            // lasciata dietro.
            //
            // Giacomo, 5 settembre 2026: «vedo un difetto estetico in
            // impostazioni […] ci sono anche delle freccette nere al centro
            // insomma e' pieno di artefatti». La ricetta esatta e'
            // «Alimentazione, scorri, Audio», e per trovarla e' servito
            // mettere la fascia del titolo a fare da rivelatore — li' il
            // ciano non c'e' mai — e poi togliere un pezzo per volta finche'
            // e' rimasto questo.
            //
            // E' la stessa regola gia' scritta in `ui/Scorrimento.qml`: «la
            // posizione si puo' animare, la misura no».
        }

        Icon {
            id: glyph
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            width: 19; height: 19
            name: slider.icon
            visible: slider.icon !== ""
            // Sopra il riempimento serve un colore scuro, fuori uno chiaro.
            color: slider._fillEnd > x + width ? Theme.Colors.textOnAccent
                                               : Theme.Colors.textMuted
            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
        }

        Text {
            id: valueText
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            visible: slider.showValue
            text: Math.round(slider._fraction * 100) + "%"
            color: slider._fillEnd > x + width ? Theme.Colors.textOnAccent
                                               : Theme.Colors.textMuted
            font.family: Theme.Typography.fontMono
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        function valueAt(mouseX) {
            // Il riempimento non scende sotto l'altezza della barra (è un
            // capsula arrotondata), quindi la zona utile parte da lì.
            var usable = slider.width - slider.height;
            var f = usable <= 0 ? 0
                  : Math.max(0, Math.min(1, (mouseX - slider.height / 2) / usable));
            return slider.from + f * (slider.to - slider.from);
        }

        onPressed: function(m) {
            slider.value = valueAt(m.x);
            slider.moved(slider.value);
        }
        onPositionChanged: function(m) {
            if (!pressed)
                return;
            slider.value = valueAt(m.x);
            slider.moved(slider.value);
        }
        onReleased: slider.released(slider.value)

        onWheel: function(wheel) {
            var step = (slider.to - slider.from) / 20;
            slider.value = Math.max(slider.from,
                                    Math.min(slider.to,
                                             slider.value + (wheel.angleDelta.y > 0 ? step : -step)));
            slider.moved(slider.value);
            slider.released(slider.value);
        }
    }
}

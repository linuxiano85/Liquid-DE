import QtQuick

// Pronto — vero dal primo fotogramma che la finestra ha mostrato con la sua
// misura vera, falso di nuovo quando si nasconde.
//
// Serve alle molle dei pannelli della riva. Una finestra appena resa
// visibile nasce larga e alta zero, e solo un attimo dopo il compositore le
// dà la misura dello schermo: una posizione calcolata da quella misura
// («in fondo meno l'altezza») con la molla già accesa partiva da zero e
// volava fino al posto giusto. Giacomo, 25 settembre 2026: «il menù app la
// prima volta che lo apri si apre quasi a metà fuori schermo nella parte
// bassa a sinistra e dopo un poco si posiziona giusto». Le molle vanno
// accese solo quando `visto` è vero.
//
// Un Timer fa da rete: se il segnale del fotogramma non arrivasse, dopo
// 300 ms con la finestra visibile e misurata si considera pronto lo stesso.
Item {
    id: pronto

    property bool visto: false

    readonly property var _finestra: pronto.Window.window
    readonly property bool _misurata: pronto._finestra !== null
                                      && pronto._finestra.visible
                                      && pronto._finestra.width > 0
                                      && pronto._finestra.height > 0

    on_MisurataChanged: {
        if (!pronto._misurata) {
            pronto.visto = false;
            rete.stop();
        } else {
            rete.restart();
        }
    }

    Connections {
        target: pronto._finestra
        ignoreUnknownSignals: true
        function onFrameSwapped() {
            if (pronto._misurata)
                pronto.visto = true;
        }
    }

    Timer {
        id: rete
        interval: 300
        onTriggered: if (pronto._misurata) pronto.visto = true
    }
}

import QtQuick
import "../theme" as Theme
import "../core" as Core

// Equalizzatore — Le barre della musica nella barra Liquid.
//
// Il manutentore, 18 ottobre 2026: «in liquid vorrei poter vedere l'effetto onde o
// effetto equalizzatore nella barra dove sta il calendario con il titolo di
// quello che sta riproducendo. Pensa tu a qualcosa di straordinario.»
//
// Le barre seguono il suono vero: lo spettro di ciò che esce dalle casse lo
// calcola il demone (`minervad/lib/services/spettro_service.dart`) e qui
// arrivano solo sedici numeri. Vale per qualunque lettore, non solo Media.
//
// I colori vengono dal disco della musica del prototipo «Minerva Isola»
// (viola → ciano → rosa), disteso dai bassi agli acuti. Le barre crescono
// dal centro verso l'alto e il basso, come un'onda che respira.
//
// Senza dati (niente `parec`, o il demone che non risponde) si torna a
// un'animazione che respira da sola: la barra non resta mai ferma mentre
// suona, e non finge di ascoltare quando non può.
Item {
    id: eq

    /// Vero mentre si vede e qualcosa suona: solo allora si chiede lo spettro.
    property bool attivo: false
    property int quante: 16
    property real altezzaMassima: 18
    property real larghezzaBarra: 3
    property real spazio: 2

    implicitWidth: quante * larghezzaBarra + (quante - 1) * spazio
    implicitHeight: altezzaMassima

    property var bande: []
    property bool disponibile: true
    property bool _iscritto: false
    // L'ultimo dato arrivato: se tace da più di un secondo e mezzo mentre
    // suona, si passa all'animazione.
    property real _ultimo: 0
    property real _ora: 0
    readonly property bool vero: eq.disponibile && eq.bande.length === eq.quante
                                 && (eq._ora - eq._ultimo) < 1500

    function _aggiorna() {
        var vuole = eq.attivo && Core.Ipc.connected;
        if (vuole === eq._iscritto)
            return;
        eq._iscritto = vuole;
        if (vuole)
            Core.Ipc.iscriviSpettro();
        else
            Core.Ipc.disiscriviSpettro();
    }
    onAttivoChanged: eq._aggiorna()
    Component.onCompleted: eq._aggiorna()
    Component.onDestruction: if (eq._iscritto) Core.Ipc.disiscriviSpettro()

    Connections {
        target: Core.Ipc
        function onSpettroRicevuto(bande, disponibile) {
            eq.disponibile = disponibile;
            if (!disponibile)
                return;
            eq.bande = bande;
            eq._ultimo = Date.now();
            eq._ora = eq._ultimo;
        }
        // Il demone riavviato non ricorda le iscrizioni: si rifà.
        function onConnectedChanged() {
            eq._iscritto = false;
            eq._aggiorna();
        }
    }

    // Il controllo del silenzio dei dati: ricalcola `vero` anche quando non
    // arriva niente, che è proprio il caso da accorgersi.
    Timer {
        interval: 500
        repeat: true
        running: eq.attivo
        onTriggered: eq._ora = Date.now()
    }

    // L'animazione di ripiego: una fase che gira, e ogni barra ci legge il
    // suo pezzo di seno.
    property real _fase: 0
    NumberAnimation on _fase {
        running: eq.attivo && !eq.vero && Theme.Motion.liquido
        from: 0; to: Math.PI * 2
        duration: 1600
        loops: Animation.Infinite
    }

    function _colore(i) {
        // viola #8b5cf6 → ciano #22d3ee → rosa #f0abfc
        var t = eq.quante > 1 ? i / (eq.quante - 1) : 0;
        var a, b, u;
        if (t < 0.5) { a = [0x8b, 0x5c, 0xf6]; b = [0x22, 0xd3, 0xee]; u = t * 2; }
        else { a = [0x22, 0xd3, 0xee]; b = [0xf0, 0xab, 0xfc]; u = (t - 0.5) * 2; }
        return Qt.rgba((a[0] + (b[0] - a[0]) * u) / 255,
                       (a[1] + (b[1] - a[1]) * u) / 255,
                       (a[2] + (b[2] - a[2]) * u) / 255, 1);
    }

    Row {
        anchors.centerIn: parent
        spacing: eq.spazio
        Repeater {
            model: eq.quante
            delegate: Rectangle {
                id: barra
                required property int index
                readonly property color tinta: eq._colore(index)
                readonly property real livello: eq.vero
                    ? eq.bande[index] / 100
                    // Il ripiego: una forma varia anche da ferma (animazioni
                    // spente), che respira quando le animazioni ci sono.
                    : (eq.attivo ? 0.25 + 0.55 * Math.abs(Math.sin(eq._fase * 2 + index * 0.9))
                                       * (0.6 + 0.4 * Math.cos(eq._fase + index * 0.37))
                                 : 0)
                anchors.verticalCenter: parent.verticalCenter
                width: eq.larghezzaBarra
                radius: width / 2
                height: Math.max(width, eq.altezzaMassima * Math.max(0, Math.min(1, livello)))
                // Solo coi dati veri, che arrivano trenta volte al secondo:
                // il ripiego cambia a ogni fotogramma, e un Behavior che
                // riparte a ogni fotogramma non arriva mai (barre ferme a
                // puntino, viste nella barra Minerva il 18 ottobre).
                Behavior on height {
                    enabled: Theme.Motion.liquido && eq.vero
                    NumberAnimation { duration: 70; easing.type: Easing.OutQuad }
                }
                // Più chiara in punta: la luce sta dove la barra arriva.
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(barra.tinta, 1.35) }
                    GradientStop { position: 0.5; color: barra.tinta }
                    GradientStop { position: 1; color: Qt.lighter(barra.tinta, 1.35) }
                }
                opacity: 0.55 + 0.45 * Math.min(1, barra.livello * 1.4)
            }
        }
    }
}

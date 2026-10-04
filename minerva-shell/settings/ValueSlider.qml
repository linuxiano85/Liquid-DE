import QtQuick
import "../theme" as Theme

// ValueSlider — Cursore per valori continui, col valore sempre visibile.
//
// Il valore viene notificato con `released` a trascinamento concluso: così una
// regolazione non genera decine di scritture su disco.
// `moved` esiste per l'anteprima dal vivo, che non tocca il disco.
Item {
    id: slider

    /// Il valore VERO, quello che arriva da fuori (di solito legato a
    /// `Core.Ipc.get(…)`). Il cursore non lo scrive mai: vedi `mostrato`.
    property real value: 0.5
    property real from: 0.0
    property real to: 1.0

    /// ── Quello che si vede, e perché non è `value` ───────────────────────
    ///
    /// Fino al 30 settembre 2026 il trascinamento scriveva `slider.value =
    /// …`, e un'assegnazione in QML SPEZZA il legame di chi aveva scritto
    /// `value: Core.Ipc.get("windows.rigidita", 1)`. Da quel momento il
    /// cursore non seguiva più niente: dopo aver trascinato «Rigidità», il
    /// preset «Delicato» rimetteva 1 nelle impostazioni e il cursore restava
    /// dov'era; lo stesso dopo «Ripristina», o una modifica fatta altrove. Su
    /// trenta cursori, uno solo si rimetteva il legame a mano.
    ///
    /// Adesso il dito ha un posto suo, `_dito`: vale mentre si trascina e
    /// per poco dopo — finché il valore nuovo non torna da fuori, o al
    /// massimo un secondo e mezzo, così un valore rifiutato si rivede com'è
    /// davvero. `mostrato` è quello che si disegna, e chi fuori vuole il
    /// numero sotto il dito legge questo.
    property real _dito: NaN
    readonly property real mostrato: isNaN(slider._dito) ? slider.value : slider._dito

    onValueChanged: {
        if (!drag.pressed) {
            slider._dito = NaN;
            attesa.stop();
        }
    }

    Timer {
        id: attesa
        interval: 1500
        onTriggered: if (!drag.pressed) slider._dito = NaN
    }

    /// Come si scrive il valore accanto al cursore.
    ///
    /// C'era solo la percentuale, e per i valori che percentuali NON sono
    /// diceva assurdità: la dimensione delle icone della dock, che è in pixel,
    /// si presentava come «4500%», e l'altezza della barra del titolo come
    /// «3900%». Nessuno dei due numeri voleva dire niente, ed erano lì da
    /// mesi in bella vista in mezzo a cursori che invece dicevano il vero.
    ///
    ///   "percento"  0,93 → «93%»      (trasparenze, ingrandimenti)
    ///   "pixel"     45   → «45 px»    (dimensioni sullo schermo)
    ///   "numero"    2.7  → «2,7»      (fattori)
    ///   "intero"    600  → «600» + `suffix`  (millisecondi, minuti, conteggi)
    ///   "niente"         → nessuna etichetta
    ///
    /// «niente» serve dove il valore è già scritto sopra al cursore con le sue
    /// parole («27 al secondo», «10 min»): lì la seconda etichetta non era
    /// solo di troppo, diceva pure un numero sbagliato.
    property string unit: "percento"
    property string suffix: ""

    /// ── Il valore a cui il cursore si aggancia ───────────────────────────
    ///
    /// Serve ai cursori che hanno un NEUTRO in mezzo alla corsa invece che a
    /// un capo: la sensibilità del puntatore va da −1 a +1, e lo zero —
    /// «normale» — è una posizione su quarantuno, in mezzo, senza niente che
    /// la trattenga.
    ///
    /// Giacomo si è ritrovato il puntatore a **+1.00**, il massimo
    /// dell'accelerazione, senza sapere quando: la catena è onesta dal
    /// pannello al compositore, e l'unico che scrive quel valore è questo
    /// cursore. Basta una trascinata lunga per finire in fondo, e riportarsi
    /// esattamente sullo zero a mano è un'altra cosa.
    ///
    /// `NaN` vuol dire «nessun aggancio», ed è il comportamento di prima:
    /// tutti gli altri cursori non cambiano di un pixel.
    property real aggancioA: NaN
    /// Quanto vicino bisogna essere perché scatti, nelle unità del valore.
    property real aggancioEntro: 0.08

    // Un cursore va detto con il suo NUMERO e la sua unità, non con «cursore»
    // e basta: chi non vede la posizione della manopola ha bisogno del valore.
    Accessible.role: Accessible.Slider
    Accessible.name: slider.unit
    Accessible.description: Math.round(slider.mostrato) + " " + slider.unit

    readonly property string readoutText: {
        // Un suffisso che comincia coi due punti è un orario: «21:00», non
        // «21 :00» (visto nella luce notturna, 28 settembre 2026).
        var tail = slider.suffix === "" ? ""
                 : (slider.suffix.charAt(0) === ":" ? slider.suffix : " " + slider.suffix);
        switch (slider.unit) {
        case "niente": return "";
        case "pixel":  return Math.round(slider.mostrato) + " px";
        case "intero": return Math.round(slider.mostrato) + tail;
        case "numero": return (Math.round(slider.mostrato * 10) / 10)
                              .toLocaleString(Qt.locale(), 'f', 1) + tail;
        case "percento": return Math.round(slider.mostrato * 100) + "%";
        }
        // ── Un'unità che non esiste non è una percentuale ────────────────
        //
        // Il ripiego muto era `default: percentuale`, e ha lasciato in giro
        // due cursori che dicevano il falso per mesi: la sfocatura della
        // schermata di accesso (`unit: ""`) si leggeva «4700%», e il giro
        // della cornice (`unit: "secondi"`, che non è un'unità ma una
        // traduzione) «800%». Erano scritti in bella vista e nessuno se n'è
        // accorto, perché un numero sbagliato ha lo stesso aspetto di un
        // numero giusto.
        //
        // Adesso lo si sente: il numero si mostra nudo, e il registro dice
        // quale unità è stata inventata.
        console.warn("[MINERVA][ValueSlider] unità sconosciuta:",
                     slider.unit, "— il valore si mostra nudo");
        return Math.round(slider.mostrato) + tail;
    }

    /// Emesso in continuo durante il trascinamento (anteprima)
    signal moved(real value)
    /// Emesso una sola volta, a trascinamento finito (salvataggio)
    signal released(real value)

    implicitWidth: 200
    implicitHeight: 28

    readonly property real _fraction: {
        var span = to - from;
        if (span <= 0)
            return 0;
        return Math.max(0, Math.min(1, (slider.mostrato - from) / span));
    }

    Text {
        id: readout
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: slider.unit !== "niente"
        width: visible ? 46 : 0
        horizontalAlignment: Text.AlignRight
        // Il VALORE, non la posizione del cursore. Su un cursore che va da
        // 0,75 a 1 la posizione a metà è il 50%, ma il valore è 87% — e
        // l'etichetta deve dire quello che l'impostazione vale davvero.
        text: slider.readoutText
        color: Theme.Colors.textMuted
        font.family: Theme.Typography.fontMono
        font.pixelSize: Theme.Typography.sizeSM
    }

    Item {
        id: groove
        anchors.left: parent.left
        anchors.right: readout.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: 2
            color: Theme.Colors.raisedHigh

            Rectangle {
                width: parent.width * slider._fraction
                height: parent.height
                radius: parent.radius
                color: Theme.Colors.accent
            }
        }

        Rectangle {
            id: handle
            width: 18
            height: 18
            radius: 9
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(parent.width - width,
                                    slider._fraction * parent.width - width / 2))
            color: Theme.Colors.accent
            border.width: 2
            border.color: Qt.rgba(0, 0, 0, 0.35)
            scale: drag.pressed ? 1.2 : 1.0

            Behavior on scale {
                NumberAnimation { duration: Theme.Motion.instant }
            }
        }

        MouseArea {
            id: drag
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            function valueAt(mouseX) {
                var f = Math.max(0, Math.min(1, mouseX / width));
                var v = slider.from + f * (slider.to - slider.from);
                // Vicino al neutro ci si ferma: è il modo in cui si torna
                // «normale» col dito invece che a occhio. Come il centro di un
                // bilanciamento.
                if (!isNaN(slider.aggancioA)
                        && Math.abs(v - slider.aggancioA) <= slider.aggancioEntro)
                    return slider.aggancioA;
                return v;
            }

            onPressed: function(mouse) {
                attesa.stop();
                slider._dito = valueAt(mouse.x);
                slider.moved(slider._dito);
            }
            onPositionChanged: function(mouse) {
                if (!pressed)
                    return;
                slider._dito = valueAt(mouse.x);
                slider.moved(slider._dito);
            }
            onReleased: {
                var v = slider._dito;
                // Prima il tempo, poi il segnale: chi ascolta di solito
                // scrive nelle impostazioni, il valore torna SUBITO, e
                // `onValueChanged` spegne l'attesa appena accesa.
                attesa.restart();
                slider.released(v);
            }
            onCanceled: {
                slider._dito = NaN;
                attesa.stop();
            }
        }
    }
}

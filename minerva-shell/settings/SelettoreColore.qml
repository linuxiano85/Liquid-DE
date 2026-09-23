import QtQuick
import "../theme" as Theme

// SelettoreColore — Un colore qualunque, non uno degli otto.
//
// ── Perché non c'era ───────────────────────────────────────────────────────
//
// In tutta Minerva non esisteva un modo di scegliere un colore: l'accento era
// una fila di otto pasticche, e il tema uno di sei. Va benissimo per chi vuole
// una scrivania che stia insieme senza pensarci — ed è il motivo per cui le
// otto pasticche restano — ma Giacomo, 3 settembre 2026: «se voglio il colore
// delle finestre rosa i caratteri viola e altre cose stravaganti?».
//
// ── Perché è fatto di rettangoli e non di uno shader ───────────────────────
//
// Le applicazioni di Minerva disegnano col PROCESSORE
// (`QT_QUICK_BACKEND=software`): è la leva che vale una trentina di megabyte
// per applicazione. Col renderer software un `ShaderEffect` non si disegna, e
// non dà errore: sparisce e basta. Lo stesso vale per `layer.effect`.
//
// Quindi il quadrato si fa come si faceva prima che esistessero gli shader:
// la tinta piena, sopra una sfumatura orizzontale verso il bianco, sopra una
// verticale verso il nero. Tre rettangoli, nessuna GPU, e si vede uguale.
Column {
    id: sel

    /// Il colore scelto adesso.
    property color valore: "#22D3EE"

    /// Cambiato di mano, cioè con una scelta e non con un rimbalzo.
    ///
    /// Chi ascolta scrive nelle impostazioni; il valore torna indietro da lì.
    /// Non si scrive dentro `valore` da qui: sarebbe la stessa forma del
    /// difetto del volume — scrivere sulla propria dipendenza mentre la si sta
    /// leggendo — e il cursore comincerebbe a scattare sotto il dito.
    signal scelto(color colore)

    spacing: Theme.Effects.space3

    // ── Le tre coordinate ────────────────────────────────────────────────
    //
    // Si tengono qui, e non si ricavano da `valore` a ogni fotogramma: un
    // colore grigio non ha una tinta — `hsvHue` risponde -1 — e un nero non ha
    // saturazione. Ricavandole ogni volta, trascinando verso il nero il
    // cursore della tinta saltava all'inizio e non ci si poteva più tornare.
    property real tonalita: 0.5
    property real saturazione: 1.0
    property real valoreV: 1.0

    /// Vero mentre siamo noi a muovere: durante il trascinamento il colore
    /// arriva da noi, e rileggerlo da fuori riporterebbe indietro il dito.
    property bool _staScegliendo: false

    function _componi() {
        return Qt.hsva(sel.tonalita, sel.saturazione, sel.valoreV, 1);
    }

    function _daColore(c) {
        if (sel._staScegliendo)
            return;
        // Il grigio puro non ha tinta: si tiene quella di prima, o il cursore
        // salterebbe a rosso ogni volta che si passa per il centro.
        if (c.hsvHue >= 0)
            sel.tonalita = c.hsvHue;
        sel.saturazione = c.hsvSaturation;
        sel.valoreV = c.hsvValue;
    }

    onValoreChanged: sel._daColore(sel.valore)
    Component.onCompleted: sel._daColore(sel.valore)

    function _annuncia() {
        sel._staScegliendo = true;
        sel.scelto(sel._componi());
        sel._staScegliendo = false;
    }

    // ── Il quadrato: saturazione e luminosità ────────────────────────────
    Rectangle {
        id: quadro
        width: parent.width
        height: 140
        radius: Theme.Effects.radiusSM
        color: Qt.hsva(sel.tonalita, 1, 1, 1)
        border.width: 1
        border.color: Theme.Colors.edge
        clip: true

        // Verso il bianco andando a sinistra.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#FFFFFFFF" }
                GradientStop { position: 1.0; color: "#00FFFFFF" }
            }
        }
        // Verso il nero andando in basso.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#00000000" }
                GradientStop { position: 1.0; color: "#FF000000" }
            }
        }

        // Il bersaglio. Bianco fuori e nero dentro perché deve vedersi sia
        // sull'angolo bianco sia su quello nero: un solo colore sparirebbe da
        // una parte, e proprio nell'angolo in cui si sta scegliendo.
        Rectangle {
            width: 16; height: 16; radius: 8
            color: "transparent"
            border.width: 2
            border.color: "#FFFFFF"
            x: sel.saturazione * (quadro.width - 1) - 8
            y: (1 - sel.valoreV) * (quadro.height - 1) - 8

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: 6
                color: "transparent"
                border.width: 1
                border.color: "#80000000"
            }
        }

        MouseArea {
            anchors.fill: parent
            // Il trascinamento prende anche fuori dal riquadro: si sceglie il
            // nero puro tirando oltre il bordo di sotto, ed è il gesto che si
            // fa senza pensarci.
            preventStealing: true
            function aggiorna(mx, my) {
                sel.saturazione = Math.max(0, Math.min(1, mx / quadro.width));
                sel.valoreV = 1 - Math.max(0, Math.min(1, my / quadro.height));
                sel._annuncia();
            }
            onPressed: function(m) { aggiorna(m.x, m.y); }
            onPositionChanged: function(m) { if (pressed) aggiorna(m.x, m.y); }
        }
    }

    // ── La striscia della tinta ──────────────────────────────────────────
    Rectangle {
        id: striscia
        width: parent.width
        height: 22
        radius: 11
        border.width: 1
        border.color: Theme.Colors.edge
        clip: true

        // Sette fermate e non sei: il rosso sta ai due capi, o l'ultimo tratto
        // tornerebbe indietro dal magenta al rosso passando per tutto lo
        // spettro all'incontrario.
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.000; color: "#FF0000" }
            GradientStop { position: 0.167; color: "#FFFF00" }
            GradientStop { position: 0.333; color: "#00FF00" }
            GradientStop { position: 0.500; color: "#00FFFF" }
            GradientStop { position: 0.667; color: "#0000FF" }
            GradientStop { position: 0.833; color: "#FF00FF" }
            GradientStop { position: 1.000; color: "#FF0000" }
        }

        Rectangle {
            width: 6
            height: parent.height + 6
            y: -3
            x: sel.tonalita * (striscia.width - 6)
            radius: 3
            color: "transparent"
            border.width: 2
            border.color: "#FFFFFF"
        }

        MouseArea {
            anchors.fill: parent
            preventStealing: true
            function aggiorna(mx) {
                sel.tonalita = Math.max(0, Math.min(1, mx / striscia.width));
                sel._annuncia();
            }
            onPressed: function(m) { aggiorna(m.x); }
            onPositionChanged: function(m) { if (pressed) aggiorna(m.x); }
        }
    }

    // ── Il numero, per chi ce l'ha già ───────────────────────────────────
    //
    // Chi arriva con un colore preciso in mano — preso da un logo, da un
    // altro programma, da un sito — non lo trova trascinando. Si scrive.
    Row {
        spacing: Theme.Effects.space2

        Rectangle {
            width: 34; height: 34
            radius: Theme.Effects.radiusXS
            color: sel.valore
            border.width: 1
            border.color: Theme.Colors.edge
        }

        Rectangle {
            width: 120; height: 34
            radius: Theme.Effects.radiusXS
            color: Theme.Colors.sunken
            border.width: 1
            border.color: campo.activeFocus ? Theme.Colors.accent
                                            : Theme.Colors.edge

            TextInput {
                id: campo
                anchors.fill: parent
                anchors.leftMargin: Theme.Effects.space2
                anchors.rightMargin: Theme.Effects.space2
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.Colors.text
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeSM
                selectByMouse: true
                maximumLength: 7
                // Il margine è ai LATI e non tutt'intorno: `anchors.margins`
                // toglieva spazio anche sopra e sotto, e con `clip` acceso il
                // testo si vedeva a metà. È lo stesso difetto già corretto nel
                // gestore file e nella casella della password Wi-Fi.
                clip: true

                // Non si riscrive mentre ci si sta scrivendo dentro: si vedrebbe
                // il cursore saltare a ogni carattere.
                text: activeFocus ? text : sel.valore.toString().toUpperCase()

                function manda() {
                    var t = campo.text.trim();
                    if (t.charAt(0) !== "#")
                        t = "#" + t;
                    if (/^#[0-9A-Fa-f]{6}$/.test(t)) {
                        sel.scelto(t);
                    } else {
                        // Sbagliato: si rimette quello che c'era. Un campo che
                        // resta con dentro una cosa che non vale è un campo che
                        // dice che è stata accettata.
                        campo.text = sel.valore.toString().toUpperCase();
                    }
                }

                onAccepted: manda()
                onActiveFocusChanged: if (!activeFocus) manda()
            }
        }
    }
}

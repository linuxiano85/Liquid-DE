import QtQuick
import "../theme" as Theme
import "../core" as Core

// ClockCluster — Il centro della barra: ora e data.
//
// Il centro è l'unica zona che si LEGGE senza cliccare, quindi non ha stati
// al passaggio del mouse né bersagli: un clic a vuoto qui non deve fare nulla.
//
// L'ora usa il monospace perché le cifre non devono ballare al cambio di
// minuto. La data usa il font display, più tenue: è contorno, non
// informazione primaria.
//
// Il titolo della finestra attiva stava qui, e se n'è andato: adesso vive nel
// WindowChip accanto ai suoi tre pulsanti. Mostrarlo in due punti della stessa
// barra faceva sembrare che fossero due cose diverse.
Row {
    id: cluster

    spacing: Theme.Effects.space3

    property string timeText: ""
    property string dateText: ""

    /// Acceso quando il calendario è aperto o il puntatore è sopra.
    property bool dimmed: false

    /// ── Quando lo spazio non basta, resta l'ora ─────────────────────────
    ///
    /// La barra ha tre zone e l'orologio sta in mezzo allo SCHERMO: se la
    /// zona destra cresce — tre valori di sistema, un nome di località lungo,
    /// l'elenco delle finestre — prima o poi lo spazio finisce.
    ///
    /// Restringere il riquadro non basta: dentro c'è una `Row` che conserva
    /// la sua larghezza, e il risultato sarebbe la data stampata SOPRA il
    /// primo pulsante della zona destra. Visto il 9 settembre 2026: «mer 9
    /// set» sopra «94 %».
    ///
    /// Quindi sparisce la DATA, che è la metà tenue — il commento qui sopra
    /// la chiama «contorno, non informazione primaria» — e resta l'ora, che è
    /// la ragione per cui l'orologio sta lì. Un orologio tagliato a metà non
    /// è un orologio più piccolo: è un difetto.
    property bool compatto: false

    /// ── Quanto sarebbe larga con la data, sempre ────────────────────────
    ///
    /// Si calcola anche quando la data non si disegna, e questa è la riga che
    /// evita un anello: chi decide se stringere non può misurare l'oggetto
    /// GIÀ stretto, o stretto ci starebbe, tornerebbe largo, non ci starebbe
    /// più, e i due legami si rincorrerebbero un fotogramma dopo l'altro.
    ///
    /// `implicitWidth` di un `Text` non dipende dal fatto che si veda.
    readonly property real larghezzaPiena:
        ora.implicitWidth + cluster.spacing + 1
        + cluster.spacing + data.implicitWidth

    /// 24 ore oppure AM/PM. Sta nelle impostazioni e non fisso nel codice: era
    /// scritto `"HH:mm"` qui dentro, e chi arriva da un paese dove l'orologio
    /// si legge in dodici ore non aveva nessun posto dove dirlo.
    readonly property bool ore24: Core.Ipc.get("clock.format24", true)
    onOre24Changed: refresh()

    function refresh() {
        var now = new Date();
        var locale = Core.Strings.lang === "it" ? Qt.locale("it_IT") : Qt.locale("en_GB");
        cluster.timeText = now.toLocaleTimeString(
            locale, cluster.ore24 ? "HH:mm" : "h:mm AP");
        cluster.dateText = now.toLocaleDateString(locale, "ddd d MMM");
    }

    Component.onCompleted: refresh()

    Timer {
        // Allineato al minuto: aggiornare ogni secondo un orologio che mostra
        // i minuti significa svegliare la GPU sessanta volte per nulla.
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            var now = new Date();
            if (now.getSeconds() === 0 || cluster.timeText === "")
                cluster.refresh();
        }
    }

    Text {
        id: ora
        anchors.verticalCenter: parent.verticalCenter
        text: cluster.timeText
        color: cluster.dimmed ? Theme.Colors.accent : Theme.Colors.text
        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
        font.family: Theme.Typography.fontMono
        font.pixelSize: Theme.Typography.sizeLG
        font.letterSpacing: 0.5
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: !cluster.compatto
        width: 1
        height: 14
        color: Theme.Colors.edge
    }

    Text {
        id: data
        anchors.verticalCenter: parent.verticalCenter
        visible: !cluster.compatto
        text: cluster.dateText
        color: Theme.Colors.textMuted
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: Theme.Typography.sizeMD
        font.weight: Theme.Typography.weightMedium
        font.letterSpacing: Theme.Typography.trackingSubtitle
    }
}

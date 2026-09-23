import QtQuick
import "../theme" as Theme
import "../core" as Core

// Contenuto — Che cosa mostra un widget: un numero, una parola e una barra.
//
// ── Un file solo per otto widget, e finché dura va bene ────────────────────
//
// Ognuno di questi widget è tre righe: da dove prende il numero, come si
// chiama, e se ha una percentuale da disegnare. Otto file da tre righe sono
// otto posti in cui ricordarsi la stessa struttura.
//
// Il giorno che un widget vuole qualcosa di suo — un grafico che scorre, una
// nota che si scrive, il meteo con la sua icona — quel widget si prende un
// file, e questo resta per gli altri. La riga di confine è: *se è un numero e
// una parola, sta qui*.
//
// ── E le parole non le inventa ─────────────────────────────────────────────
//
// I byte, i secondi e la GPU li mette in parole `core/Macchina.qml`, una volta
// sola. Gli stessi byte scritti in due modi in due angoli della scrivania sono
// due modi di dire la stessa cosa, e chi guarda si chiede quale sia giusto.
Item {
    id: contenuto

    required property string tipo

    /// Senza vetro dietro. Allora il testo si ORLA col colore opposto: è
    /// `Text.Outline` di Qt, raster puro, e funziona anche col renderer
    /// software — dove uno shader non si disegnerebbe affatto e l'oggetto
    /// sparirebbe senza dare errore (`disegno_senza_gpu_test.dart`).
    property bool nudo: false

    /// Vero quando questo valore ha una storia da disegnare. `orologio` e
    /// `meteo` non ce l'hanno, e nemmeno il tempo acceso: una linea che sale
    /// sempre non dice niente.
    readonly property bool haStoria: Core.Macchina.haStoria(contenuto.tipo)

    /// Il grafico si mostra: chiesto, e c'è spazio. Sotto una certa altezza
    /// una linea di sei pixel non è un grafico, è una sporcatura.
    property bool grafico: true

    /// Il numero grosso, già in parole.
    readonly property string valore: {
        var m = Core.Macchina;
        switch (contenuto.tipo) {
        case "processore":
            return m.pronta ? Math.round(m.cpu) + "%" : "—";
        case "memoria":
            return m.memoriaTotale > 0
                   ? Math.round(m.memoriaPerCento) + "%" : "—";
        case "gpu":
            return m.gpuSveglia >= 0 ? Math.round(m.gpuSveglia) + "%" : "—";
        case "temperatura":
            return m.temperatura >= 0 ? Math.round(m.temperatura) + "°" : "—";
        case "rete":
            return m.alSecondo(m.reteGiu);
        case "carico":
            return (Math.round(m.carico * 100) / 100).toString();
        case "acceso":
            return m.daQuanto(m.acceso);
        case "batteria":
            return Core.SystemState.hasBattery
                   ? Core.SystemState.batteryPercent + "%" : "—";
        // Quanto RESTA e non quanto è pieno: la domanda che uno si fa
        // guardando il disco è «ci sta?», non «quanto ne ho consumato».
        case "disco":
            return m.discoTotale > 0 ? m.inParole(m.discoLibero) : "—";
        case "orologio":
            // Con la lingua di Minerva e non con quella del sistema: la barra
            // fa così (`spine/ClockCluster.qml`), e un orologio in italiano
            // con la data in inglese due centimetri più sotto è una scrivania
            // che parla due lingue.
            return contenuto._adesso.toLocaleTimeString(contenuto._lingua,
                       Core.Ipc.get("clock.format24", true)
                       ? "HH:mm" : "h:mm AP");
        case "meteo":
            return Core.Meteo.pronto
                   ? Core.Meteo.gradi(Core.Meteo.adesso.temperatura) : "—";
        }
        return "—";
    }

    /// L'ora, e si sveglia una volta al minuto e non a ogni secondo.
    ///
    /// L'orologio della barra fa lo stesso, e la ragione è misurata: una
    /// scrivania che si ridisegna sessanta volte al minuto per mostrare dei
    /// minuti è la definizione di consumo inutile
    /// (`minerva-prestazioni-svegliarsi`).
    readonly property var _lingua: Core.Strings.lang === "it"
                                   ? Qt.locale("it_IT") : Qt.locale("en_GB")

    property var _adesso: new Date()
    property Timer _minuto: Timer {
        interval: 20000
        running: contenuto.tipo === "orologio"
        repeat: true
        triggeredOnStart: true
        onTriggered: contenuto._adesso = new Date()
    }

    /// Il simbolo, per dove il nome non ci sta: la barra.
    ///
    /// Giacomo, 14 settembre 2026: «quelli sulla barra sono confusionari
    /// perché non hanno un simbolo per capire che valori monitorano». Sta
    /// qui e non in `WidgetBarra`, accanto al nome: sono la stessa tabella,
    /// e un tipo nuovo che ha un nome e non un simbolo si vedrebbe subito.
    readonly property string icona: {
        switch (contenuto.tipo) {
        case "processore":  return "cpu";
        case "memoria":     return "memoria";
        case "gpu":         return "gpu";
        case "temperatura": return "termometro";
        case "rete":        return "rete";
        case "disco":       return "disco";
        case "batteria":    return "battery";
        case "carico":      return "carico";
        case "acceso":      return "timer";
        case "orologio":    return "clock";
        case "meteo":       return "nuvole";
        }
        return "info";
    }

    /// Il nome, sotto. Corto: un widget piccolo è largo venti caratteri.
    readonly property string nome: {
        var it = Core.Strings.lang === "it";
        switch (contenuto.tipo) {
        case "processore":  return it ? "Processore" : "Processor";
        case "memoria":     return it ? "Memoria" : "Memory";
        // «Sveglia» e non «uso», e non è pignoleria: `rc6` dice quanto la GPU
        // è stata sveglia, che è un tetto all'uso e non l'uso. Scriverci
        // «uso» vorrebbe dire mentire ogni cinque secondi.
        case "gpu":         return it ? "GPU sveglia" : "GPU awake";
        case "temperatura": return it ? "Temperatura" : "Temperature";
        case "rete":        return it ? "In arrivo" : "Incoming";
        case "carico":      return it ? "Carico" : "Load";
        case "acceso":      return it ? "Acceso da" : "Up for";
        case "batteria":    return it ? "Batteria" : "Battery";
        case "disco":       return it ? "Liberi sul disco" : "Free on disk";
        case "orologio":    return contenuto._adesso
                            .toLocaleDateString(contenuto._lingua, "ddd d MMM");
        case "meteo":       return Core.Meteo.luogo !== ""
                            ? Core.Meteo.luogo : (it ? "Meteo" : "Weather");
        }
        return contenuto.tipo;
    }

    /// La seconda riga, quando c'è qualcosa di vero da aggiungere. Vuota non
    /// si disegna: una riga vuota sotto il numero fa sembrare il widget rotto.
    readonly property string sotto: {
        var m = Core.Macchina;
        var it = Core.Strings.lang === "it";
        switch (contenuto.tipo) {
        case "processore":
            return m.core > 0 ? m.core + (it ? " core" : " cores") : "";
        case "memoria":
            return m.memoriaTotale > 0
                   ? m.inParole(m.memoriaUsata) + " / "
                     + m.inParole(m.memoriaTotale) : "";
        case "rete":
            return "↑ " + m.alSecondo(m.reteSu);
        case "batteria":
            return Core.SystemState.batteryCharging
                   ? (it ? "in carica" : "charging") : "";
        case "disco":
            return m.discoTotale > 0
                   ? m.inParole(m.discoTotale - m.discoLibero) + " / "
                     + m.inParole(m.discoTotale) : "";
        case "meteo":
            return Core.Meteo.pronto
                   ? Core.Meteo.descrizione(Core.Meteo.adesso.codice) : "";
        }
        return "";
    }

    /// Da 0 a 1 per la barra, o `-1` quando questo widget una percentuale non
    /// ce l'ha — la rete e il tempo acceso non hanno un massimo.
    readonly property real quota: {
        var m = Core.Macchina;
        switch (contenuto.tipo) {
        case "processore":  return m.pronta ? m.cpu / 100 : -1;
        case "memoria":     return m.memoriaTotale > 0 ? m.memoriaPerCento / 100 : -1;
        case "gpu":         return m.gpuSveglia >= 0 ? m.gpuSveglia / 100 : -1;
        // Novanta gradi come fondo scala: sotto i quaranta una barra che si
        // muove non direbbe niente, e sopra i novanta il portatile si spegne
        // da solo.
        case "temperatura": return m.temperatura >= 0
                            ? Math.min(1, Math.max(0, (m.temperatura - 30) / 60)) : -1;
        case "batteria":    return Core.SystemState.hasBattery
                            ? Core.SystemState.batteryPercent / 100 : -1;
        // ── La barra dice quello che dice l'etichetta ────────────────
        //
        // Qui c'era la percentuale USATA, sotto la scritta «Liberi sul
        // disco». Visto in fotografia il 10 settembre 2026: «Liberi sul
        // disco · 624,9 GB» con una barra piena per un terzo, che si legge
        // come «un terzo libero» — cioè il contrario.
        //
        // Un numero e una barra che dicono due cose diverse non sono due
        // informazioni: sono una informazione e un errore, e chi guarda non
        // ha modo di sapere quale sia quale. La barra è quanto RESTA.
        case "disco":       return m.discoTotale > 0
                            ? m.discoLibero / m.discoTotale : -1;
        }
        return -1;
    }

    /// Il colore della barra. Rosso quando la cosa è davvero al limite, e mai
    /// prima: un allarme che si accende all'ottanta per cento smette di
    /// essere un allarme.
    readonly property color tinta: {
        if (contenuto.quota < 0)
            return Theme.Colors.accent;
        // Il disco è come la batteria: la barra dice quanto RESTA, quindi il
        // rosso sta in basso. Le soglie sono strette apposta — con il cinque
        // per cento libero su btrfs le istantanee smettono di riuscire, ed è
        // un guasto che non si annuncia: si scopre il giorno che serve
        // tornare indietro.
        if (contenuto.tipo === "disco")
            return contenuto.quota <= 0.05 ? Theme.Colors.danger
                 : contenuto.quota <= 0.15 ? Theme.Colors.warning
                 : Theme.Colors.accent;
        if (contenuto.tipo === "batteria")
            return contenuto.quota <= 0.15 ? Theme.Colors.danger
                 : contenuto.quota <= 0.30 ? Theme.Colors.warning
                 : Theme.Colors.positive;
        return contenuto.quota >= 0.92 ? Theme.Colors.danger
             : contenuto.quota >= 0.75 ? Theme.Colors.warning
             : Theme.Colors.accent;
    }

    // Chi non vede la scrivania deve poterla sentire. Il valore a parole, non
    // il tipo: «Processore, 43 per cento» e non «widget processore».
    Accessible.role: Accessible.StaticText
    Accessible.name: contenuto.nome
    Accessible.description: contenuto.valore
                            + (contenuto.sotto !== "" ? ", " + contenuto.sotto : "")

    // ── Il grafico sta DIETRO, non accanto ───────────────────────────────
    //
    // Il numero resta la cosa che si legge; la storia è la texture su cui sta.
    // Metterli affiancati vorrebbe dire due cose piccole invece di una grande,
    // e su un widget di centoventi pixel non ci starebbe nessuna delle due.
    Grafico {
        id: storia
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.min(parent.height * 0.55, parent.height - 34)
        visible: contenuto.grafico && contenuto.haStoria && height > 16
        quale: contenuto.tipo
        tinta: contenuto.tinta
        nudo: contenuto.nudo
    }

    // ── In cima quando c'è la storia, in mezzo quando non c'è ────────────
    //
    // Col grafico acceso la metà bassa della carta è sua, e lasciare il
    // numero in mezzo vuol dire una carta con tutto ammucchiato in alto a
    // sinistra e un buco sotto — visto in fotografia il 9 settembre 2026,
    // ed è la differenza fra «un riquadro con dentro un numero» e una carta
    // composta: valore in alto, nome sotto, storia per tutta la base.
    //
    // Senza grafico il numero torna in mezzo, che è dove sta bene da solo.
    // `y` e non un'ancora: un'ancora sola non sa fare due cose.
    Column {
        id: testi
        anchors.left: parent.left
        anchors.right: parent.right
        y: storia.visible ? 0
                          : Math.round((contenuto.height - height) / 2)
        spacing: Theme.Effects.space1

        Text {
            width: parent.width
            text: contenuto.valore
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            // Si adatta all'altezza del widget: ridimensionandolo dalla
            // scrivania il numero cresce con lui, o ingrandire non
            // servirebbe a niente.
            font.pixelSize: Math.max(Theme.Typography.sizeLG,
                                     Math.min(contenuto.height * 0.42,
                                              contenuto.width * 0.34))
            // ── Si restringe, non si taglia ──────────────────────────
            //
            // La misura qui sopra è una frazione della CARTA, e va bene per
            // «6 %». Per «624,9 GB» no: alla stessa misura escono otto
            // caratteri larghi, e con il solo `elide` diventavano «624.9…» —
            // cioè un widget che nasconde proprio la cifra che lo giustifica.
            // Visto in fotografia il 10 settembre 2026.
            //
            // `HorizontalFit` rimpicciolisce finché ci sta, e `elide` resta
            // come ultima rete per il caso in cui nemmeno il minimo basti.
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Theme.Typography.sizeMD
            font.weight: Theme.Typography.weightLight
            elide: Text.ElideRight
            style: contenuto.nudo ? Text.Outline : Text.Normal
            styleColor: Theme.Colors.scura ? "#000000" : "#FFFFFF"
        }

        Text {
            width: parent.width
            text: contenuto.nome
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            elide: Text.ElideRight
            style: contenuto.nudo ? Text.Outline : Text.Normal
            styleColor: Theme.Colors.scura ? "#000000" : "#FFFFFF"
        }

        Text {
            width: parent.width
            visible: contenuto.sotto !== "" && contenuto.height > 96
            text: contenuto.sotto
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontMono
            font.pixelSize: Theme.Typography.sizeXS
            elide: Text.ElideRight
            style: contenuto.nudo ? Text.Outline : Text.Normal
            styleColor: Theme.Colors.scura ? "#000000" : "#FFFFFF"
        }

        // La barra. `Rectangle` e non `Shape`: la shell disegna col
        // processore, e lì una forma dentro una lista lascia i propri pixel
        // dove non c'è più niente (`minerva-residui-software`).
        Rectangle {
            // Non insieme al grafico: la barra e la linea dicono lo stesso
            // numero, e due volte la stessa cosa è rumore.
            visible: contenuto.quota >= 0 && contenuto.height > 76
                     && !(contenuto.grafico && contenuto.haStoria)
            width: parent.width
            height: 4
            radius: 2
            // ── Nudo la traccia sparisce ─────────────────────────────
            //
            // Una traccia scura larga quanto il widget, sopra una fotografia,
            // si legge come una riga tirata sopra il numero — visto in una
            // schermata, e Giacomo l'avrebbe visto un secondo dopo. Resta la
            // parte PIENA, che è quella che dice qualcosa: la scala la dà già
            // il numero lì accanto.
            color: contenuto.nudo ? "transparent" : Theme.Colors.raisedHigh

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, contenuto.quota))
                height: parent.height
                radius: parent.radius
                color: contenuto.tinta
            }
        }
    }
}

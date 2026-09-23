import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// Scrivania — I widget, il blocco, e la scrivania pulita.
//
// ── Perché una sezione a sé ────────────────────────────────────────────────
//
// Giacomo, 9 settembre 2026: «dobbiamo implementare una sezione desktop dove
// possiamo personalizzare il desktop con dei widget».
//
// Le voci della scrivania erano sparse: le icone in Aspetto, lo sfondo in
// Aspetto, i widget da nessuna parte. Chi cerca «come cambio la mia
// scrivania» cerca una voce che si chiami così — è la stessa lezione della
// dock, che aveva sette voci in fondo a una pagina da milleseicento righe e
// Giacomo scriveva «non ci sono impostazioni per essa».
//
// ── E il posto dove si aggiungono è QUI ────────────────────────────────────
//
// Dalla scrivania si spostano e si ridimensionano, che è il gesto giusto per
// dire DOVE. Ma «quali» è una scelta da elenco, non da trascinamento: un menù
// con dieci voci sopra una fotografia è un menù che copre la fotografia.
Page {
    id: page

    readonly property bool it: Core.Strings.lang === "it"

    title: page.it ? "Scrivania" : "Desktop"
    subtitle: page.it ? "I widget, e come si guarda quello che c'è sotto"
                      : "The widgets, and how you see what is underneath"

    readonly property var messi: Core.Ipc.get("desktop.widgets", [])
    readonly property bool bloccati: Core.Ipc.get("desktop.widgetBloccati", true)

    // ── Quali widget esistono ────────────────────────────────────────────
    //
    // Il costo sta accanto al nome, e non è pedanteria: il progetto lo fa già
    // una volta sola nel gestore file — «Costa 131 MB di memoria, sempre» — ed
    // è l'unico modo di scegliere davvero. Un interruttore che dice «più
    // informazioni» e non dice quanto costa non è una scelta, è una spinta.
    //
    // Qui il costo è lo stesso per tutti e quasi zero, e va detto anche
    // questo: la sorgente è UNA, la cadenza è UNA, e dieci widget costano
    // quanto uno. È il contrario di come funzionano di solito.
    readonly property var disponibili: [
        { "tipo": "prestazioni", "it": "Prestazioni", "en": "Performance",
          "detta": page.it ? "Il tabellone: processore in grande, poi memoria, GPU, temperatura, disco e rete con simbolo e barra, e la storia in fondo"
                           : "The board: processor big, then memory, GPU, temperature, disk and network, with the history at the bottom" },
        { "tipo": "bluetooth",   "it": "Bluetooth", "en": "Bluetooth",
          "detta": page.it ? "Gli apparecchi accoppiati, ognuno col suo simbolo e la batteria — se la dice"
                           : "Paired devices, each with its symbol and battery — when it reports one" },
        { "tipo": "riassunto",   "it": "Come sta il computer",
          "en": "How the computer is doing",
          "detta": page.it ? "Una casella sola, in colonna: processore, memoria, GPU, temperatura"
                           : "One card, in a column" },
        { "tipo": "processore",  "it": "Processore", "en": "Processor",
          "detta": page.it ? "Con quattro minuti di storia dietro" : "With four minutes of history" },
        { "tipo": "memoria",     "it": "Memoria", "en": "Memory",
          "detta": page.it ? "Usata e totale" : "Used and total" },
        { "tipo": "gpu",         "it": "GPU sveglia", "en": "GPU awake",
          "detta": page.it ? "Quanto la scheda video è sveglia. Non è l'uso: è il tempo in cui NON dorme"
                           : "How long the GPU is awake — not its usage" },
        { "tipo": "temperatura", "it": "Temperatura", "en": "Temperature",
          "detta": page.it ? "La sonda più calda" : "The hottest probe" },
        { "tipo": "rete",        "it": "Rete", "en": "Network",
          "detta": page.it ? "Byte al secondo, in arrivo e in partenza" : "Bytes per second" },
        { "tipo": "batteria",    "it": "Batteria", "en": "Battery",
          "detta": page.it ? "E se sta caricando" : "And whether it is charging" },
        { "tipo": "disco",       "it": "Liberi sul disco", "en": "Free on disk",
          "detta": page.it ? "Quanto spazio resta. Si rilegge una volta al minuto"
                           : "How much space is left — read once a minute" },
        { "tipo": "carico",      "it": "Carico", "en": "Load",
          "detta": page.it ? "La media di un minuto" : "One-minute average" },
        { "tipo": "acceso",      "it": "Acceso da", "en": "Up for",
          "detta": page.it ? "Da quanto tempo non si riavvia" : "Since the last restart" },
        { "tipo": "orologio",    "it": "Orologio", "en": "Clock",
          "detta": page.it ? "Ora e data, grandi" : "Time and date, big" },
        { "tipo": "meteo",       "it": "Meteo", "en": "Weather",
          "detta": page.it ? "Va acceso in Data e ora" : "Turn it on in Date & time" }
    ]

    function nomeDi(tipo) {
        for (var i = 0; i < page.disponibili.length; i++)
            if (page.disponibili[i].tipo === tipo)
                return page.it ? page.disponibili[i].it : page.disponibili[i].en;
        return tipo;
    }

    /// Una copia della voce: `Core.Ipc.get` restituisce l'oggetto vero, e
    /// cambiarlo sul posto vorrebbe dire che nessun legame se ne accorge.
    function copia(v) {
        return { "id": v.id, "tipo": v.tipo, "aspetto": v.aspetto,
                 "righe": v.righe, "grafico": v.grafico,
                 "fx": v.fx, "fy": v.fy, "fw": v.fw, "fh": v.fh };
    }

    function tutti() {
        var l = [];
        for (var k = 0; k < page.messi.length; k++)
            l.push(page.copia(page.messi[k]));
        return l;
    }

    function aggiungi(tipo) {
        var l = page.tutti();
        var n = l.length;
        // I tabelloni nascono grandi: cinque righe e un grafico non stanno
        // in una casella da widget singolo.
        var grande = tipo === "prestazioni" || tipo === "bluetooth";
        l.push({ "id": "w" + Date.now(), "tipo": tipo,
                 "aspetto": "vetro", "grafico": true,
                 // A scacchiera e non tutti nello stesso punto: due widget
                 // aggiunti di fila si coprirebbero, e il secondo sembrerebbe
                 // non essere comparso.
                 "fx": 0.32 + (n % 3) * 0.21,
                 "fy": 0.12 + Math.floor(n / 3) * 0.22,
                 "fw": grande ? 0.24 : 0.19, "fh": grande ? 0.62 : 0.19 });
        Core.Ipc.setSetting("desktop.widgets", l);
    }

    function togli(i) {
        var l = [];
        for (var k = 0; k < page.messi.length; k++)
            if (k !== i)
                l.push(page.copia(page.messi[k]));
        Core.Ipc.setSetting("desktop.widgets", l);
    }

    // ── La barra ─────────────────────────────────────────────────────────
    //
    // Non tutti i tipi: il riassunto è una colonna, e una colonna dentro una
    // barra alta trentaquattro pixel non è un widget, è un pasticcio.
    // L'orologio la barra ce l'ha già, e il meteo pure — metterceli due volte
    // sarebbe la stessa cosa detta due volte.
    readonly property var perLaBarra: [
        "processore", "memoria", "gpu", "temperatura",
        "rete", "disco", "batteria", "carico"
    ]

    readonly property var nellaBarra: Core.Ipc.get("bar.widgets", [])

    /// Accende o spegne un valore nella barra, tenendo l'ordine dell'elenco
    /// qui sopra: chi ne riaccende uno se lo ritrova al suo posto.
    function barra(quale, acceso) {
        var ora = page.nellaBarra;
        var l = [];
        for (var k = 0; k < page.perLaBarra.length; k++) {
            var t = page.perLaBarra[k];
            var c = (t === quale) ? acceso : (ora.indexOf(t) !== -1);
            if (c)
                l.push(t);
        }
        Core.Ipc.setSetting("bar.widgets", l);
    }

    // ── Le righe che un riassunto può contenere ──────────────────────────
    //
    // Non tutte quelle che esistono: dentro una colonna alta cinque righe,
    // l'orologio e il meteo sarebbero due righe di testo lungo in mezzo a dei
    // numeri, e la colonna smetterebbe di leggersi in un colpo.
    readonly property var righeRiassunto: [
        "processore", "memoria", "gpu", "temperatura",
        "rete", "disco", "batteria", "carico", "acceso"
    ]

    /// Le righe di un riassunto, con il valore di serie quando non le ha
    /// ancora scelte nessuno. Lo stesso elenco è scritto in `Riassunto.qml`
    /// come ripiego: qui è quello che si VEDE nelle spunte, e devono
    /// combaciare o le spunte mentirebbero al primo colpo d'occhio.
    function leRighe(v) {
        if (v && v.righe && v.righe.length > 0)
            return v.righe;
        return ["processore", "memoria", "gpu", "temperatura"];
    }

    function dentroLeRighe(v, quale) {
        return page.leRighe(v).indexOf(quale) !== -1;
    }

    /// Accende o spegne una riga, tenendo l'ordine dell'elenco qui sopra: chi
    /// riaccende «memoria» se la ritrova al suo posto e non in fondo.
    function riga(i, quale, acceso) {
        var l = page.tutti();
        if (i < 0 || i >= l.length)
            return;
        var ora = page.leRighe(page.messi[i]);
        var nuove = [];
        for (var k = 0; k < page.righeRiassunto.length; k++) {
            var r = page.righeRiassunto[k];
            var c = (r === quale) ? acceso : (ora.indexOf(r) !== -1);
            if (c)
                nuove.push(r);
        }
        // Mai vuoto: una casella senza righe è un rettangolo di vetro che non
        // dice niente, e chi ha spento l'ultima non capirebbe come tornare
        // indietro. Si tiene l'ultima accesa.
        if (nuove.length === 0)
            return;
        l[i].righe = nuove;
        Core.Ipc.setSetting("desktop.widgets", l);
    }

    function cambia(i, campo, valore) {
        var l = page.tutti();
        if (i < 0 || i >= l.length)
            return;
        l[i][campo] = valore;
        Core.Ipc.setSetting("desktop.widgets", l);
    }

    // ── Il blocco ────────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Personalizza" : "Customise"
        note: page.it
              ? "Sbloccati si trascinano e si ridimensionano dalla scrivania, "
                + "e col tasto destro si tolgono. Bloccati diventano parte "
                + "dello sfondo: il clic ci passa attraverso."
              : "Unlocked they drag and resize on the desktop. Locked they "
                + "become part of the wallpaper: clicks pass through."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Widget sulla scrivania" : "Desktop widgets"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("desktop.widgetAccesi", true)
                onToggled: function (v) {
                    Core.Ipc.setSetting("desktop.widgetAccesi", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Bloccati" : "Locked"
            description: page.it
                ? "Si sbloccano anche col tasto destro sulla barra, "
                  + "«Personalizza scrivania»"
                : "Also unlocked with a right click on the bar"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: page.bloccati
                onToggled: function (v) {
                    Core.Ipc.setSetting("desktop.widgetBloccati", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Scrivania pulita" : "Clean desktop"
            description: page.it
                ? "Niente icone e niente widget, con un clic. Per una "
                  + "schermata, o per mostrarla a qualcuno."
                : "No icons and no widgets, in one click."
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("desktop.puliti", false)
                onToggled: function (v) {
                    Core.Ipc.setSetting("desktop.puliti", v);
                }
            }
        }
    }

    // ── Quelli che ci sono ───────────────────────────────────────────────

    Card {
        heading: page.it ? "Quelli che hai" : "The ones you have"
        note: page.messi.length === 0
              ? (page.it ? "Nessuno. Se ne aggiunge uno qui sotto."
                         : "None yet. Add one below.")
              : ""

        Repeater {
            model: page.messi

            // Un widget non è una riga sola: ha l'aspetto, e quelli che hanno
            // una storia hanno anche il grafico, e il riassunto ha le sue
            // righe. Una colonna per widget invece di una riga tiene insieme
            // le cose che parlano dello stesso oggetto — che è il motivo per
            // cui questa pagina esiste al posto di sette voci sparse.
            delegate: Column {
                id: voce
                required property var modelData
                required property int index
                width: parent.width
                spacing: 0

                readonly property string tipo: String(voce.modelData.tipo || "")
                readonly property bool nudo:
                    String(voce.modelData.aspetto || "vetro") === "nudo"

                S.SettingRow {
                    width: parent.width
                    label: page.nomeDi(voce.tipo)
                    description: voce.nudo
                        ? (page.it ? "Senza vetro: si vede lo sfondo dietro"
                                   : "No glass: the wallpaper shows through")
                        : (page.it ? "Col vetro" : "With glass")
                    controlWidth: 320

                    control: Row {
                        spacing: Theme.Effects.space2

                        // ── La larghezza si DICE, dentro una Row ────────
                        //
                        // `ChoicePicker` è largo quanto il genitore
                        // (`width: parent.width`): è fatto per stare da solo
                        // nel posto del controllo. Dentro una Row il
                        // genitore è la Row, e la Row è larga quanto i figli:
                        // si rincorrono, e la pagina resta VUOTA — titolo,
                        // sottotitolo, e sotto niente, con «possible
                        // QQuickItem::polish() loop» nel registro a ripetizione.
                        // Giacomo, 13 settembre 2026: «la sezione desktop è
                        // vuota e non posso aggiungere o rimuovere widget».
                        S.ChoicePicker {
                            width: 200
                            value: voce.nudo ? "nudo" : "vetro"
                            options: [
                                { "value": "vetro", "label": page.it ? "Vetro" : "Glass" },
                                { "value": "nudo",  "label": page.it ? "Nudo" : "Bare" }
                            ]
                            onPicked: function (v) {
                                page.cambia(voce.index, "aspetto", v);
                            }
                        }

                        // Togliere è irreversibile quanto lo è rimettere: un
                        // widget si riaggiunge in un clic, quindi non si chiede
                        // conferma. Chiedere conferma per una cosa che si disfa
                        // da sola è il modo di insegnare a cliccare «sì» senza
                        // leggere.
                        // Centrata con `y` e non con un'ancora al genitore:
                        // stessa ragione qui sopra, la Row non deve dipendere
                        // da un figlio che dipende da lei.
                        Rectangle {
                            y: Math.round((parent.height - height) / 2)
                            width: 30
                            height: 26
                            radius: Theme.Effects.radiusSM
                            color: viaMouse.containsMouse
                                   ? Qt.alpha(Theme.Colors.danger, 0.18)
                                   : Theme.Colors.raised
                            border.width: 1
                            border.color: Theme.Colors.edge

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: viaMouse.containsMouse ? Theme.Colors.danger
                                                              : Theme.Colors.textMuted
                                font.pixelSize: Theme.Typography.sizeSM
                            }

                            MouseArea {
                                id: viaMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.togli(voce.index)
                            }
                        }
                    }
                }

                // ── La storia dietro il numero ───────────────────────────
                //
                // Solo per le grandezze che una storia ce l'hanno, e chi lo
                // sa è `Core.Macchina`: l'elenco sta in un posto solo, o si
                // aggiunge una grandezza qui e ci si dimentica là.
                S.SettingRow {
                    width: parent.width
                    visible: Core.Macchina.haStoria(voce.tipo)
                    label: page.it ? "La storia, dietro" : "The history, behind"
                    description: page.it
                        ? "Quattro minuti di grafico dietro al numero. «42 %» "
                          + "non dice se è tanto; «42 % e sale da un minuto» sì."
                        : "Four minutes of graph behind the number."
                    controlWidth: 60
                    control: S.ToggleSwitch {
                        checked: voce.modelData.grafico !== false
                        onToggled: function (v) {
                            page.cambia(voce.index, "grafico", v);
                        }
                    }
                }

                // ── Le righe del riassunto ───────────────────────────────
                //
                // Giacomo: «magari poter avere una singola casella di
                // queste». Una casella sola che le tiene tutte è utile solo
                // se si può dire QUALI: quattro righe fisse sono un widget
                // in più, non una casella su misura.
                Column {
                    width: parent.width
                    visible: voce.tipo === "riassunto"
                    spacing: 0

                    Repeater {
                        model: page.righeRiassunto

                        delegate: S.SettingRow {
                            required property var modelData
                            width: parent.width
                            label: "    " + page.nomeDi(String(modelData))
                            controlWidth: 60
                            control: S.ToggleSwitch {
                                checked: page.dentroLeRighe(voce.modelData,
                                                            String(modelData))
                                onToggled: function (v) {
                                    page.riga(voce.index, String(modelData), v);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── E gli stessi, nella barra ────────────────────────────────────────

    Card {
        heading: page.it ? "Nella barra" : "In the bar"
        note: page.it
              ? "Gli stessi valori, in piccolo, accanto al meteo. Con quattro "
                + "minuti di storia in ventotto pixel: non si legge un numero, "
                + "si vede se sale. Il clic apre il Monitor.\n\n"
                + "La barra c'è sempre, quindi un valore qui tiene acceso il "
                + "campionamento per tutta la sessione — quattro file ogni "
                + "cinque secondi. Sulla scrivania invece si spegne da solo "
                + "quando una finestra la copre."
              : "The same values, small, next to the weather. The bar is "
                + "always there, so a value here keeps the sampling on for the "
                + "whole session."

        Repeater {
            model: page.perLaBarra

            delegate: S.SettingRow {
                required property var modelData
                width: parent.width
                label: page.nomeDi(String(modelData))
                controlWidth: 60
                control: S.ToggleSwitch {
                    checked: page.nellaBarra.indexOf(String(modelData)) !== -1
                    onToggled: function (v) {
                        page.barra(String(modelData), v);
                    }
                }
            }
        }
    }

    // ── Quelli che si possono aggiungere ─────────────────────────────────

    Card {
        heading: page.it ? "Aggiungine uno" : "Add one"
        note: page.it
              ? "Dieci widget costano quanto uno: la sorgente è una sola e la "
                + "cadenza è una sola — il demone legge quattro file ogni "
                + "cinque secondi, e solo mentre almeno un widget guarda. "
                + "L'unica eccezione è il disco, che non si legge da un file: "
                + "quello si chiede una volta al minuto."
              : "Ten widgets cost as much as one: a single source, a single "
                + "cadence, and only while at least one widget is watching. "
                + "The exception is the disk, asked once a minute."

        Repeater {
            model: page.disponibili

            delegate: S.SettingRow {
                required property var modelData
                width: parent.width
                label: page.it ? modelData.it : modelData.en
                description: modelData.detta
                controlWidth: 120

                control: Ui.SpineButton {
                    height: 30
                    horizontalPadding: Theme.Effects.space4
                    onClicked: page.aggiungi(String(modelData.tipo))
                    content: Text {
                        text: page.it ? "Aggiungi" : "Add"
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                }
            }
        }
    }
}

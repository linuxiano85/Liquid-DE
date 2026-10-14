import QtQuick
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// PaginaRadio — Le radio online in Minerva Media.
//
// Il catalogo lo chiede il demone a radio-browser.info
// (`minervad/lib/services/radio_service.dart`, dove c'è anche che cosa esce
// dal computer). Qui si sceglie: tre elenchi, il paese di chi usa il
// computer, tutto il mondo e le radio salvate, e una casella per cercare.
// Suonare lo fa il lettore di Media, lo stesso della musica: la pagina dice
// solo QUALE stazione con `ascolta`.
//
// Niente icone delle stazioni: starebbero sul sito di ogni radio, e un
// elenco vorrebbe dire decine di server contattati solo per guardare. Al
// loro posto l'iniziale, su un colore che viene dal nome (sempre lo stesso
// per la stessa radio, così la si riconosce).
//
// Richiesta del manutentore, 6 ottobre 2026: «Media lo userei per ascoltare
// musica, scaricare video e modificare audio e video. Una radio online.»
Item {
    id: pagina

    /// La stazione che sta suonando (il suo `id`), per segnarla nell'elenco.
    property string inOnda: ""
    /// Vero mentre la radio suona davvero (non solo scelta).
    property bool suona: false
    /// Il lettore non riesce a suonare la stazione: il suo messaggio.
    property string erroreLettore: ""

    /// Ascoltare questa stazione: `{id, nome, url, paese, tag, codec, bitrate}`.
    signal ascolta(var stazione)
    /// Spegnere la radio.
    signal ferma()

    readonly property bool it: Core.Strings.lang === "it"

    /// Il paese di chi usa il computer, dalla lingua del sistema («it_IT» →
    /// «IT»). Se non si capisce, si parte dal mondo.
    readonly property string paeseCasa: {
        var parti = Qt.locale().name.split("_");
        return parti.length > 1 && /^[A-Z]{2}$/.test(parti[1]) ? parti[1] : "";
    }

    /// «paese», «mondo» o «preferite».
    property string elenco: "paese"

    property var stazioni: []
    property string errore: ""
    property bool cercando: false

    /// Le radio salvate. Si leggono dalle impostazioni e si riscrivono intere:
    /// sono poche, e così l'ordine resta quello in cui le si è salvate.
    property var preferite: Core.Ipc.get("media.radioPreferite", [])

    readonly property var mostrate: {
        if (pagina.elenco !== "preferite")
            return pagina.stazioni;
        var t = campo.text.trim().toLowerCase();
        if (t === "")
            return pagina.preferite;
        return pagina.preferite.filter(function (s) {
            return String(s.nome).toLowerCase().indexOf(t) >= 0;
        });
    }

    function _paese() {
        return pagina.elenco === "paese" ? pagina.paeseCasa : "";
    }

    /// La ricerca in corso: si tiene solo la risposta a questa. Due ricerche
    /// di fila possono rispondere nell'ordine sbagliato, e un elenco vecchio
    /// che arriva dopo quello nuovo lo coprirebbe.
    property string _chiesto: ""

    function cerca() {
        if (pagina.elenco === "preferite")
            return;
        var testo = campo.text.trim();
        pagina._chiesto = testo + "|" + pagina._paese();
        pagina.cercando = true;
        pagina.errore = "";
        Core.Ipc.radioCerca(testo, pagina._paese());
    }

    function preferita(id) {
        for (var i = 0; i < pagina.preferite.length; i++)
            if (pagina.preferite[i].id === id)
                return true;
        return false;
    }

    function alternaPreferita(s) {
        var nuove = pagina.preferite.filter(function (p) { return p.id !== s.id; });
        if (nuove.length === pagina.preferite.length) {
            nuove.push({ "id": s.id, "nome": s.nome, "url": s.url, "paese": s.paese || "",
                         "tag": s.tag || [], "codec": s.codec || "", "bitrate": s.bitrate || 0 });
        }
        // Non si assegna `preferite`: romperebbe il legame con le
        // impostazioni. `setSetting` aggiorna subito la copia locale, e il
        // legame porta qui il valore nuovo.
        Core.Ipc.setSetting("media.radioPreferite", nuove);
    }

    /// Due segni per riconoscere una radio senza la sua icona.
    ///
    /// Con la sola iniziale erano quasi tutte «R», perché quasi tutte si
    /// chiamano «Radio qualcosa». Si toglie la parola «radio» e si prendono
    /// le iniziali delle prime due parole («Radio Kiss Kiss» → «KK», «Rai
    /// Radio 3» → «R3»); un numero in testa resta intero («Radio 24» → «24»).
    function sigla(nome) {
        var parole = String(nome).split(/[^A-Za-z0-9À-ÿ.]+/).filter(function (p) {
            return p !== "" && p.toLowerCase() !== "radio";
        });
        if (parole.length === 0)
            return String(nome).charAt(0).toUpperCase();
        if (/^[0-9][0-9.]*$/.test(parole[0]))
            return parole[0].replace(/\.$/, "").substring(0, 3);
        var s = parole[0].charAt(0);
        if (parole.length > 1)
            s += parole[1].charAt(0);
        return s.toUpperCase();
    }

    /// Un colore per nome: lo stesso nome dà sempre lo stesso colore.
    function tinta(nome) {
        var h = 0;
        var s = String(nome);
        for (var i = 0; i < s.length; i++)
            h = (h * 31 + s.charCodeAt(i)) % 360;
        return Qt.hsla(h / 360, 0.45, 0.42, 1);
    }

    Connections {
        target: Core.Ipc

        function onRadioStazioni(r) {
            if ((r.testo || "") + "|" + (r.paese || "") !== pagina._chiesto)
                return;
            pagina.cercando = false;
            pagina.stazioni = r.stazioni || [];
            pagina.errore = r.error || "";
        }
    }

    // La prima volta che la pagina si vede, le radio del paese: una pagina
    // vuota con una casella non dice cosa ci si può trovare.
    property bool _caricata: false
    onVisibleChanged: {
        if (pagina.visible && !pagina._caricata) {
            pagina._caricata = true;
            pagina.cerca();
        }
    }

    // Si cerca mentre si scrive, ma non a ogni lettera: il catalogo è di
    // volontari, e «r», «ra», «rad» sarebbero tre domande buttate.
    Timer {
        id: attesa
        interval: 450
        onTriggered: pagina.cerca()
    }

    // ── In cima: casella, elenchi, e la radio che suona ──────────────────

    Column {
        id: testa
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: Theme.Effects.space2

        Ui.Campo {
            id: campo
            objectName: "radioCampo"
            width: parent.width
            segnaposto: pagina.elenco === "preferite"
                        ? (pagina.it ? "Filtra le radio salvate…" : "Filter saved stations…")
                        : (pagina.it ? "Cerca una radio…" : "Search a station…")
            onCambiato: attesa.restart()
            onAccettato: {
                attesa.stop();
                pagina.cerca();
            }
        }

        Row {
            spacing: Theme.Effects.space2

            Repeater {
                model: [
                    { "id": "paese", "nome": pagina.paeseCasa !== ""
                                             ? (pagina.it ? "Il tuo paese · " : "Your country · ") + pagina.paeseCasa
                                             : (pagina.it ? "Più ascoltate" : "Most played") },
                    { "id": "mondo", "nome": pagina.it ? "Tutto il mondo" : "Worldwide" },
                    { "id": "preferite", "nome": (pagina.it ? "Salvate" : "Saved")
                                                 + (pagina.preferite.length > 0 ? " · " + pagina.preferite.length : "") }
                ]

                delegate: Rectangle {
                    id: scelta
                    required property var modelData
                    readonly property bool attiva: pagina.elenco === modelData.id
                    objectName: "radioElenco-" + modelData.id
                    width: nomeScelta.implicitWidth + Theme.Effects.space4 * 2
                    height: 32
                    radius: height / 2
                    color: scelta.attiva ? Qt.alpha(Theme.Colors.accent, 0.22)
                         : presaScelta.containsMouse ? Theme.Colors.hover : Theme.Colors.raised
                    border.width: 1
                    border.color: scelta.attiva ? Theme.Colors.edgeAccent : "transparent"

                    Text {
                        id: nomeScelta
                        anchors.centerIn: parent
                        text: scelta.modelData.nome
                        font { family: Theme.Typography.fontDisplay
                               ; pixelSize: Theme.Typography.sizeSM }
                        color: scelta.attiva ? Theme.Colors.text : Theme.Colors.textMuted
                    }

                    MouseArea {
                        id: presaScelta
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (pagina.elenco === scelta.modelData.id)
                                return;
                            pagina.elenco = scelta.modelData.id;
                            pagina.stazioni = [];
                            pagina.cerca();
                        }
                    }
                }
            }
        }

        // Quello che succede: si cerca, non risponde, non suona.
        Text {
            width: parent.width
            visible: text !== ""
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: pagina.erroreLettore !== ""
                  ? (pagina.it ? "La radio non si sente: " : "The station does not play: ") + pagina.erroreLettore
                  : pagina.errore !== "" ? pagina.errore
                  : pagina.cercando ? (pagina.it ? "Cerco…" : "Searching…")
                  : pagina.mostrate.length === 0
                    ? (pagina.elenco === "preferite"
                       ? (pagina.it ? "Nessuna radio salvata: la stella accanto a una radio la mette qui."
                                    : "No saved stations: the star next to a station puts it here.")
                       : (pagina.it ? "Nessuna radio trovata." : "No stations found."))
                  : ""
            color: pagina.erroreLettore !== "" || pagina.errore !== ""
                   ? Theme.Colors.danger : Theme.Colors.textFaint
            font { family: Theme.Typography.fontDisplay
                   ; pixelSize: Theme.Typography.sizeSM }
        }
    }

    // ── L'elenco ─────────────────────────────────────────────────────────

    Ui.Scorrimento {
        bersaglio: lista
        anchors { right: lista.right; top: lista.top; bottom: lista.bottom }
    }

    ListView {
        id: lista
        objectName: "radioLista"
        anchors { left: parent.left; right: parent.right
                   top: testa.bottom; topMargin: Theme.Effects.space3
                   bottom: parent.bottom }
        clip: true
        spacing: Theme.Effects.space1
        cacheBuffer: 400
        model: pagina.mostrate

        delegate: Item {
            id: voce
            required property var modelData
            required property int index
            readonly property bool inOnda: pagina.inOnda === modelData.id
            objectName: "radioVoce-" + index
            width: ListView.view ? ListView.view.width : 0
            height: 52

            Rectangle {
                anchors.fill: parent
                radius: Theme.Effects.radiusSM
                color: presaVoce.containsMouse ? Theme.Colors.hover
                     : voce.inOnda ? Qt.alpha(Theme.Colors.accent, 0.10) : "transparent"
            }

            MouseArea {
                id: presaVoce
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (voce.inOnda && pagina.suona)
                        pagina.ferma();
                    else
                        pagina.ascolta(voce.modelData);
                }
            }

            // L'iniziale al posto dell'icona della radio.
            Rectangle {
                id: bollino
                anchors { left: parent.left; leftMargin: Theme.Effects.space2
                           verticalCenter: parent.verticalCenter }
                width: 36
                height: 36
                radius: Theme.Effects.radiusSM
                color: pagina.tinta(voce.modelData.nome)

                Text {
                    anchors.centerIn: parent
                    visible: !(voce.inOnda && pagina.suona)
                    text: pagina.sigla(voce.modelData.nome)
                    textFormat: Text.PlainText
                    font { family: Theme.Typography.fontDisplay
                           ; pixelSize: text.length > 2 ? Theme.Typography.sizeXS
                                                        : Theme.Typography.sizeSM
                           ; weight: Theme.Typography.weightBold }
                    color: "white"
                }
                // Sta suonando: il simbolo della pausa, che è anche quello
                // che succede cliccandoci.
                Ui.Icon {
                    anchors.centerIn: parent
                    visible: voce.inOnda && pagina.suona
                    width: 18
                    height: 18
                    name: "pause"
                    color: "white"
                }
            }

            Column {
                anchors { left: bollino.right; leftMargin: Theme.Effects.space3
                           right: stella.left; rightMargin: Theme.Effects.space2
                           verticalCenter: parent.verticalCenter }
                spacing: 2

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    // Il nome lo sceglie chi ha messo la radio nel catalogo:
                    // testo semplice, mai HTML.
                    textFormat: Text.PlainText
                    text: voce.modelData.nome
                    font { family: Theme.Typography.fontDisplay
                           ; pixelSize: Theme.Typography.sizeMD
                           ; weight: Theme.Typography.weightMedium }
                    color: voce.inOnda ? Theme.Colors.accent : Theme.Colors.text
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: {
                        var s = voce.modelData;
                        var parti = [];
                        if (s.paese)
                            parti.push(s.paese);
                        if (s.tag && s.tag.length > 0)
                            parti.push(s.tag.join(", "));
                        if (s.bitrate > 0)
                            parti.push(s.bitrate + " kbps");
                        return parti.join("  ·  ");
                    }
                    font { family: Theme.Typography.fontDisplay
                           ; pixelSize: Theme.Typography.sizeXS }
                    color: Theme.Colors.textFaint
                }
            }

            // Salvare la radio.
            Rectangle {
                id: stella
                objectName: "radioStella-" + voce.index
                anchors { right: parent.right; rightMargin: Theme.Effects.space2
                           verticalCenter: parent.verticalCenter }
                width: 32
                height: 32
                radius: Theme.Effects.radiusSM
                color: presaStella.containsMouse ? Theme.Colors.hover : "transparent"

                readonly property bool accesa: pagina.preferita(voce.modelData.id)

                Ui.Icon {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    name: "star"
                    // Un segno, non un'icona del tema: quella del tema ignora
                    // il colore, e una stella accesa sembrava spenta.
                    alwaysDrawn: true
                    color: stella.accesa ? Theme.Colors.accent : Theme.Colors.textFaint
                }
                MouseArea {
                    id: presaStella
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pagina.alternaPreferita(voce.modelData)
                }
            }
        }
    }
}

import QtQuick
import Quickshell

import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Custodia — la storia e la sicurezza delle tue cartelle.
//
// ── Da dove nasce ──────────────────────────────────────────────────────────
//
// Da una cartella di Giacomo che si chiama `Documenti/Progetti/Minerva-Copie` e
// che contiene questo:
//
//     minerva-2026-08-04_2014-utente-e-accesso.tar.zst   18 MB
//     minerva-2026-08-04_2018-polkit-scambiato.tar.zst   18 MB
//     minerva-2026-08-05_0347.tar.zst                    18 MB
//     minerva-2026-08-17_pre-github.tar.zst              62 MB
//
// Data, ora, e cosa stava per fare. È già questo programma, eseguito a mano,
// ogni volta che si è ricordato di farlo — e 114 MB che su btrfs sarebbero
// costati zero. Il vocabolario qui sotto è il suo, raccolto e non inventato.
//
// ── Le due parole, e perché sono due ───────────────────────────────────────
//
//   · **SALVATAGGIO** — «ho finito una cosa, mettila nella storia».
//     Sotto è un commit. Tiene i file che git conosce, per sempre.
//
//   · **PUNTO DI RITORNO** — «sto per fare una cosa rischiosa».
//     Sotto è una copia dell'intera cartella. Tiene TUTTO: la roba compilata,
//     le prove a metà, i file che git non ha mai visto. Costa 90 millisecondi
//     e 8 kilobyte, misurati.
//
// Non sono due nomi per la stessa cosa, e tenerle distinte è metà del
// programma: quello che si rompe, di solito, è proprio la roba che git non
// guarda — ed è quella che un «torna al commit di ieri» non riporta indietro.
//
// La parola «git» non compare da nessuna parte nell'interfaccia. Non per
// nasconderla: perché non è una parola, è il nome di un attrezzo, e nessuno
// chiama il martello quando vuole appendere un quadro.
FloatingWindow {
    id: custodia

    // I colori arrivano dal demone: mostrarsi col tema di fabbrica e poi
    // scattare è il difetto che tutte le finestre di Minerva hanno già pagato.
    visible: Core.Ipc.prontoADipingere && !custodia.dormiente
    property bool dormiente: false

    readonly property bool it: Core.Strings.lang === "it"

    title: "Minerva · " + (custodia.it ? "Custodia" : "Custody")
    implicitWidth: 1080
    implicitHeight: 720
    // ── Il colore lo mette la FINESTRA, e costa quindici megabyte di meno ─
    //
    // Il 2 settembre 2026 qui c'era `color: "transparent"` più un
    // `Ui.FondoFinestra` — un rettangolo a tutta finestra col raggio — per
    // arrotondare gli angoli, che Giacomo aveva chiesto.
    //
    // Funzionava, e si è visto nelle fotografie. Costava però **quindici
    // megabyte per applicazione**, misurati: 55 MB senza, 69-72 con. Provato
    // in quattro modi per isolarne la causa — raggio zero, finestra opaca,
    // senza `z: -1` — e il conto non cambiava: in Qt Quick col renderer
    // software un rettangolo grande quanto la finestra costa così, comunque
    // lo si scriva.
    //
    // Su una scrivania che pesa 430 MB, quindici per applicazione non è un
    // prezzo che si paga per un angolo tondo. Gli angoli si faranno nel
    // COMPOSITORE, dove costano una volta sola e valgono anche per i
    // programmi degli altri — che è poi dove deve stare anche il «corpo
    // unico» fra barra e finestra.
    color: Theme.Colors.window

    signal requestClose()
    onClosed: custodia.requestClose()

    // ── I dati ───────────────────────────────────────────────────────────

    property var progetti: []
    property var proposte: []

    /// Il percorso del progetto aperto, oppure "" per la griglia. Il percorso
    /// e non un indice: la griglia si ricarica di continuo, e un indice
    /// punterebbe a un altro progetto appena ne cambia uno.
    property string aperto: ""
    property var dettaglio: ({})

    /// L'ultima frase da mostrare. Arriva già scritta dal demone e non si
    /// reinterpreta: quando un'operazione fallisce c'è sempre una frase
    /// italiana che dice cosa fare, e riscriverla qui vorrebbe dire scriverla
    /// due volte e sbagliarne una.
    property string avviso: ""
    property bool avvisoBuono: false

    function dice(testo, buono) {
        custodia.avviso = testo || "";
        custodia.avvisoBuono = buono === true;
        scadenzaAvviso.restart();
    }

    Timer {
        id: scadenzaAvviso
        interval: 7000
        onTriggered: custodia.avviso = ""
    }

    // ── Il collegamento col demone ───────────────────────────────────────

    Connections {
        target: Core.Ipc

        function onCustodiaPanoramica(info) {
            if (!info || info.ok !== true) return;
            custodia.progetti = info.progetti || [];
            custodia.proposte = info.proposte || [];
        }

        function onCustodiaDettaglio(info) {
            if (!info) return;
            if (info.ok !== true) { custodia.dice(info.errore, false); return; }
            custodia.dettaglio = info;
        }

        function onCustodiaEsito(info) {
            if (!info) return;
            if (info.ok === true) {
                custodia.dice(info.messaggio
                              || (custodia.it ? "Fatto." : "Done."), true);
                // Il `annullabile` arriva solo dopo un «torna a…», ed è la
                // frase più importante che questo programma dica mai: non va
                // schiacciata dentro il messaggio di riuscita.
                if (info.annullabile) custodia.dice(info.annullabile, true);
            } else {
                custodia.dice(info.errore, false);
                custodia.grossi = info.grossi || [];
            }
            custodia.ricarica();
        }
    }

    /// I file troppo grossi che hanno fatto rifiutare un salvataggio: servono
    /// a offrire «salvalo lo stesso» senza far ridigitare niente.
    property var grossi: []

    function ricarica() {
        Core.Ipc.custodiaVedi();
        if (custodia.aperto !== "") Core.Ipc.custodiaApri(custodia.aperto);
    }

    Component.onCompleted: custodia.ricarica()

    // Mentre la finestra è aperta, lo stato invecchia: si è salvato da
    // terminale, si è cambiato un file. Dieci secondi è abbastanza raro da non
    // pesare e abbastanza spesso da non mentire.
    Timer {
        interval: 10000
        running: custodia.visible
        repeat: true
        onTriggered: custodia.ricarica()
    }

    // ── La barra del titolo ──────────────────────────────────────────────
    //
    // Disegnata QUI dentro, e non dal compositore: vedi `ui/WindowTitleBar.qml`
    // per il perché lungo. In due parole, una barra disegnata fuori insegue la
    // finestra e arriva sempre un fotogramma dopo.
    //
    // Mancava, e si vedeva: la Custodia si chiudeva solo con Super+C, non si
    // poteva trascinare per la cima e non si ingrandiva col doppio clic. Non è
    // un dettaglio grafico — è una finestra che non si comanda.

    Ui.WindowTitleBar {
        id: barra
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        label: custodia.title
        onCloseRequested: custodia.requestClose()
    }

    // ── L'intestazione ───────────────────────────────────────────────────

    Rectangle {
        id: testata
        anchors.top: barra.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 64
        color: Theme.Colors.panel

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.Colors.edge
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space4
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.Effects.space3

            Ui.SpineButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: custodia.aperto !== ""
                width: 34; height: 34
                onClicked: { custodia.aperto = ""; custodia.dettaglio = ({}); }
                content: Ui.Icon {
                    name: "back"
                    width: 17; height: 17
                    color: Theme.Colors.text
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    text: custodia.aperto === ""
                          ? (custodia.it ? "Custodia" : "Custody")
                          : (custodia.dettaglio.nome || "")
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXL
                    font.weight: Theme.Typography.weightSemiBold
                }

                Text {
                    text: custodia.aperto === ""
                          ? (custodia.it
                             ? "La storia e la sicurezza delle tue cartelle"
                             : "The history and safety of your folders")
                          : custodia.aperto
                    color: Theme.Colors.textFaint
                    font.family: custodia.aperto === ""
                                 ? Theme.Typography.fontDisplay
                                 : Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }
        }
    }

    // ── L'avviso ─────────────────────────────────────────────────────────
    //
    // Sotto l'intestazione e sopra tutto il resto: una frase che dice come è
    // andata deve stare dove si stava già guardando, non in un angolo.

    Rectangle {
        id: nastro
        anchors.top: testata.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: custodia.avviso === "" ? 0 : testoAvviso.implicitHeight + 22
        clip: true
        color: Qt.alpha(custodia.avvisoBuono ? Theme.Colors.positive
                                             : Theme.Colors.danger, 0.13)

        Behavior on height {
            NumberAnimation { duration: Theme.Motion.quick
                              easing.type: Easing.OutCubic }
        }

        Text {
            id: testoAvviso
            anchors.left: parent.left
            anchors.right: chiudiAvviso.left
            anchors.leftMargin: Theme.Effects.space4
            anchors.rightMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.WordWrap
            text: custodia.avviso
            color: custodia.avvisoBuono ? Theme.Colors.positive
                                        : Theme.Colors.danger
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
        }

        Ui.SpineButton {
            id: chiudiAvviso
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            width: 26; height: 26
            onClicked: custodia.avviso = ""
            content: Ui.Icon {
                name: "close"
                width: 12; height: 12
                color: Theme.Colors.textMuted
            }
        }
    }

    // ── Il corpo ─────────────────────────────────────────────────────────

    Loader {
        id: corpo
        anchors.top: nastro.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        sourceComponent: custodia.aperto === "" ? griglia : dentro
    }

    // ── Una barra sola per tutte e due le pagine ─────────────────────────
    //
    // Sia la griglia dei progetti sia il dentro-progetto sono `Flickable`, e
    // il Loader ne tiene uno per volta: la barra guarda `corpo.item` e segue
    // quella che c'è. Finché non c'è (mentre il Loader carica) `bersaglio` è
    // nullo e la barra semplicemente non si vede.
    //
    // Qui prima c'era `ScrollBar.vertical: ScrollBar {}`, cioè quella di serie
    // di Qt: erano le uniche tre barre di tutta la shell, e si vedeva che
    // erano di un'altra scrivania.
    Ui.Scorrimento {
        bersaglio: corpo.item
        anchors {
            right: corpo.right
            rightMargin: Theme.Effects.space1
            top: corpo.top
            bottom: corpo.bottom
        }
    }

    // ── La griglia ───────────────────────────────────────────────────────

    Component {
        id: griglia

        Flickable {
            contentHeight: colonna.implicitHeight + Theme.Effects.space4 * 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: colonna
                x: Theme.Effects.space4
                y: Theme.Effects.space4
                width: parent.width - Theme.Effects.space4 * 2
                spacing: Theme.Effects.space4

                // Nessun progetto: non una schermata vuota, ma la domanda a cui
                // serve rispondere.
                Column {
                    width: parent.width
                    spacing: Theme.Effects.space2
                    visible: custodia.progetti.length === 0

                    Text {
                        text: custodia.it
                              ? "Non tengo ancora la storia di niente."
                              : "I'm not keeping any history yet."
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeLG
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: custodia.it
                              ? "Scegli una cartella qui sotto, oppure trascinane una dal gestore file."
                              : "Pick a folder below, or drag one in from the file manager."
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                }

                Grid {
                    width: parent.width
                    columns: Math.max(1, Math.floor(width / 330))
                    spacing: Theme.Effects.space3

                    Repeater {
                        model: custodia.progetti
                        RiquadroProgetto {
                            // La larghezza si calcola dal padre e non si eredita:
                            // una Grid allarga ogni colonna quanto la cella più
                            // larga, e un figlio che chiede `parent.width` la fa
                            // crescere all'infinito.
                            width: (colonna.width
                                    - Theme.Effects.space3
                                      * (parent.columns - 1)) / parent.columns
                            dati: modelData
                            it: custodia.it
                            onApri: {
                                custodia.aperto = modelData.percorso;
                                Core.Ipc.custodiaApri(modelData.percorso);
                            }
                        }
                    }
                }

                // Una cartella che non è fra le proposte: si sceglie, non si
                // scrive.
                Ui.SpineButton {
                    height: 38
                    horizontalPadding: Theme.Effects.space4
                    onClicked: custodia.chiediCartella(
                        "progetto", "",
                        custodia.it ? "Quale cartella vuoi tenere d'occhio?"
                                    : "Which folder should I watch?")
                    content: Row {
                        spacing: Theme.Effects.space2
                        Ui.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "folder"
                            width: 15; height: 15
                            color: Theme.Colors.text
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: custodia.it ? "Scegli una cartella…"
                                              : "Choose a folder…"
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeMD
                        }
                    }
                }

                // ── Le proposte ──────────────────────────────────────────
                //
                // La Custodia guarda dove la gente tiene i progetti e mostra
                // cosa ha trovato. **Propone e basta**: adottarli è un clic,
                // ignorarli è non fare niente. Un programma che si prende
                // quattordici cartelle da solo, la prima volta che si apre, è
                // un programma che nessuno riapre.
                Column {
                    width: parent.width
                    spacing: Theme.Effects.space2
                    visible: custodia.proposte.length > 0

                    Item { width: 1; height: Theme.Effects.space2 }

                    Text {
                        text: custodia.it
                              ? "Ho trovato queste, se ti servono"
                              : "I found these, if you want them"
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                        font.letterSpacing: Theme.Typography.trackingLabel
                    }

                    Flow {
                        width: parent.width
                        spacing: Theme.Effects.space2

                        Repeater {
                            model: custodia.proposte

                            Rectangle {
                                width: riga.implicitWidth + Theme.Effects.space3 * 2
                                height: 34
                                radius: 17
                                color: prop.containsMouse ? Theme.Colors.hover
                                                          : Theme.Colors.raised
                                border.width: 1
                                border.color: Theme.Colors.edge

                                Row {
                                    id: riga
                                    anchors.centerIn: parent
                                    spacing: Theme.Effects.space2

                                    Ui.Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "plus"
                                        width: 13; height: 13
                                        color: Theme.Colors.textMuted
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.nome
                                        color: Theme.Colors.text
                                        font.family: Theme.Typography.fontDisplay
                                        font.pixelSize: Theme.Typography.sizeSM
                                    }
                                    // Il motore suggerito, detto in italiano:
                                    // è una scelta tecnica che l'utente non
                                    // deve fare, ma che ha il diritto di vedere.
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.motore === "git"
                                              ? (custodia.it ? "· ogni versione"
                                                             : "· every version")
                                              : (custodia.it ? "· solo copie"
                                                             : "· copies only")
                                        color: Theme.Colors.textFaint
                                        font.family: Theme.Typography.fontDisplay
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                                }

                                MouseArea {
                                    id: prop
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Core.Ipc.custodiaAggiungi(
                                        modelData.percorso, modelData.nome,
                                        modelData.motore)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Il selettore di cartelle ─────────────────────────────────────────
    //
    // Sta QUI e non dentro i pezzi che lo usano, per una ragione di geometria:
    // deve coprire tutta la finestra, e un figlio non può uscire dai confini
    // di chi lo contiene. Chi ne ha bisogno chiama `chiediCartella()`.
    //
    // Il «per cosa» si tiene in una proprietà invece di passare una funzione:
    // in QML una funzione che sopravvive a un `Loader` che si smonta è un
    // riferimento a un oggetto morto, e il modo in cui fallisce è silenzioso.

    property string scopoScelta: ""

    function chiediCartella(scopo, daDove, titolo) {
        custodia.scopoScelta = scopo;
        selettore.titolo = titolo || "";
        selettore.apri(daDove || "");
    }

    Ui.Scegli {
        id: selettore
        // Sotto la barra del titolo, non sopra: mentre si sceglie una cartella
        // la finestra deve restare chiudibile e trascinabile come sempre.
        anchors.top: barra.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        soloCartelle: true
        it: custodia.it

        onScelto: function (percorso) {
            switch (custodia.scopoScelta) {
            case "destinazione":
                Core.Ipc.custodiaDestinazioneAggiungi(
                    custodia.aperto, "cartella", "", percorso);
                break;
            case "progetto":
                Core.Ipc.custodiaAggiungi(percorso, "", "");
                break;
            }
            custodia.scopoScelta = "";
        }
        onAnnullato: custodia.scopoScelta = ""
    }

    // ── Dentro un progetto ───────────────────────────────────────────────

    Component {
        id: dentro
        DentroProgetto {
            dati: custodia.dettaglio
            it: custodia.it
            grossi: custodia.grossi
            percorso: custodia.aperto
            finestra: custodia
        }
    }
}

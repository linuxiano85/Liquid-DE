import QtQuick

import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Ordine — i file che ci sono due volte.
//
// ── Da dove nasce ──────────────────────────────────────────────────────────
//
// Giacomo, 9 settembre 2026: «la nostra fa pulizia? ma solo pulizia ma anche
// riordino della cartella utente che è sempre una pulizia, file doppi, file
// sparsi, riordino per data e anno, rinomina nel riordino».
//
// Misurato la stessa notte, sulla sua cartella di casa: **6,94 GB in 581
// gruppi**, e la parte grossa sono tre copie dello stesso scarico del
// telefono. Tanto quanto tutta la pulizia di quel giorno — con la differenza
// che quelli non sono cache, sono i suoi file, e nessun programma di pulizia
// glieli avrebbe mai mostrati.
//
// ── Le regole, che qui pesano il doppio ────────────────────────────────────
//
// Un programma che cancella cache sbaglia e ti fa perdere tempo. Un programma
// che cancella i tuoi file sbaglia e basta. Quindi:
//
//   · **niente si cancella: si sposta nel CESTINO**, che è già una rete e sa
//     rimettere le cose dov'erano;
//   · **si vede sempre il percorso di tutte le copie**, mai una casella con
//     un nome: tre copie dello stesso video sono tre storie diverse;
//   · **la copia da tenere è una proposta**, e si può cambiare. Un programma
//     che decide da solo quale dei tuoi file sopravvive è un programma che
//     non si riapre;
//   · **una copia resta sempre in piedi**, e non è l'interfaccia a
//     garantirlo: il demone rifà il giro e rifiuta.
Item {
    id: ordine

    property var gruppi: []

    /// Le cartelle che si possono prendere come riferimento, col peso di
    /// ognuna: `[{percorso, liberabili, gruppi}]`.
    property var cartelle: []

    /// ── La cartella di riferimento ───────────────────────────────────────
    ///
    /// Giacomo, 9 settembre 2026: «metti caso che metto un nuovo backup nel
    /// PC e quelli che già avevo sono sparpagliati: seleziono la cartella
    /// come riferimento e tutto il resto viene considerato doppione».
    ///
    /// È il capovolgimento che rende usabile questa pagina. La domanda smette
    /// di essere «quali di questi settecento file butto?» — a cui nessuno
    /// risponde davvero, e chi risponde lo fa senza guardare — e diventa
    /// **«qual è la cartella buona?»**: una domanda sola, con una risposta
    /// che uno sa.
    property string riferimento: ""

    /// Le cartelle che la scansione non guarda. Arrivano dal demone, che le
    /// conserva: è una preferenza che deve valere anche domani, e la finestra
    /// si chiude.
    property var escluse: []
    property bool scegliCartella: false
    property real sprecato: 0
    property int guardati: 0
    property bool cercando: false
    property bool cercatoAlmenoUnaVolta: false

    /// L'ultima riga del racconto del demone, mostrata mentre si cerca. Il
    /// registro vero sta nell'altra pagina: qui serve solo sapere che il
    /// lavoro procede, perché durare quaranta secondi in silenzio è il modo
    /// più facile di sembrare rotti.
    property string ultimoPasso: ""

    /// Quali percorsi sono spuntati per andare nel cestino.
    property var scelti: ({})

    /// Quale copia si tiene, per gruppo (l'indice del gruppo → percorso).
    /// Comincia dalla proposta del demone e si può cambiare.
    property var tenuti: ({})

    signal scrivi(string riga)

    /// ── Qualcosa è cambiato: ridipingi ───────────────────────────────────
    ///
    /// La finestra ha un «pennello» che la ridipinge tutta nei momenti in cui
    /// col renderer software restano le scie (vedi `Manutenzione.qml`). Era
    /// legato solo alle spunte della pagina Spazio: qui le spunte cambiano
    /// tutte insieme — settecento righe con una pastiglia sola — e senza
    /// questo segnale la pagina resta com'era finché non la si tocca.
    ///
    /// Visto in una fotografia: riferimento applicato, 785 file scelti, e
    /// sullo schermo le caselle ancora vuote.
    signal cambiato()

    function _copia(m) {
        var fuori = ({});
        for (var k in m) fuori[k] = m[k];
        return fuori;
    }

    readonly property real sceltiByte: {
        var s = 0;
        for (var i = 0; i < ordine.gruppi.length; i++) {
            var g = ordine.gruppi[i];
            var uno = Math.round(g.byteInPiu / Math.max(1, g.percorsi.length - 1));
            for (var j = 0; j < g.percorsi.length; j++)
                if (ordine.scelti[g.percorsi[j]] === true) s += uno;
        }
        return s;
    }

    readonly property int sceltiQuanti: {
        var n = 0;
        for (var k in ordine.scelti) if (ordine.scelti[k] === true) n++;
        return n;
    }

    // ── Le azioni ────────────────────────────────────────────────────────

    Component.onCompleted: Core.Ipc.manutenzioneVediEscluse()

    function cerca() {
        if (ordine.cercando) return;
        ordine.cercando = true;
        ordine.scrivi("Cerco i file che ci sono due volte.");
        Core.Ipc.manutenzioneCercaDoppioni();
    }

    /// Spunta tutte le copie tranne quella tenuta, in ogni gruppo.
    ///
    /// È la scorciatoia che serve — con 576 gruppi nessuno spunta a mano — ma
    /// **non è spuntata all'apertura**: aprire una finestra e trovarci già
    /// scelti settecento file da buttare è il modo migliore per far premere
    /// senza guardare.
    function scegliTutteMenoUna() {
        var m = ({});
        for (var i = 0; i < ordine.gruppi.length; i++) {
            var g = ordine.gruppi[i];
            var tenuto = ordine.tenuti[i] || g.tieni;
            for (var j = 0; j < g.percorsi.length; j++)
                if (g.percorsi[j] !== tenuto) m[g.percorsi[j]] = true;
        }
        ordine.scelti = m;
    }

    function nessuna() {
        ordine.scelti = ({});
        ordine.riferimento = "";
    }

    /// Prende una cartella come riferimento e spunta tutto il resto.
    ///
    /// Le tre regole, e la terza è quella che rende la cosa sicura:
    ///
    ///  1. dove una copia sta **dentro** il riferimento, quella si tiene e
    ///     tutte le altre si spuntano;
    ///  2. dove **nessuna** copia sta dentro il riferimento, non si spunta
    ///     niente: quel gruppo il riferimento non lo riguarda, e decidere
    ///     per lui vorrebbe dire decidere a caso;
    ///  3. le copie **dentro** il riferimento non si toccano mai, nemmeno se
    ///     sono due. Il riferimento è la cartella buona: la si prende com'è,
    ///     non la si mette in ordine di nascosto.
    function applicaRiferimento(percorso) {
        ordine.riferimento = percorso;
        var m = ({});
        var t = ordine._copia(ordine.tenuti);
        for (var i = 0; i < ordine.gruppi.length; i++) {
            var g = ordine.gruppi[i];
            var dentro = [];
            var fuori = [];
            for (var j = 0; j < g.percorsi.length; j++) {
                var p = g.percorsi[j];
                if (p.indexOf(percorso + "/") === 0) dentro.push(p);
                else fuori.push(p);
            }
            if (dentro.length === 0) continue;
            // Si tiene la meno profonda fra quelle dentro il riferimento.
            var tenuto = dentro[0];
            for (var k = 1; k < dentro.length; k++)
                if (dentro[k].split("/").length < tenuto.split("/").length)
                    tenuto = dentro[k];
            t[i] = tenuto;
            for (var f = 0; f < fuori.length; f++) m[fuori[f]] = true;
        }
        ordine.tenuti = t;
        ordine.scelti = m;
    }

    function tieniInvece(indice, percorso) {
        var t = ordine._copia(ordine.tenuti);
        t[indice] = percorso;
        ordine.tenuti = t;
        // Se la copia appena promossa era spuntata per il cestino, si toglie:
        // tenere e buttare la stessa cosa è una contraddizione, e a
        // risolverla dev'essere il programma, non chi guarda.
        if (ordine.scelti[percorso] === true) {
            var s = ordine._copia(ordine.scelti);
            delete s[percorso];
            ordine.scelti = s;
        }
    }

    function commuta(percorso, indiceGruppo) {
        var tenuto = ordine.tenuti[indiceGruppo]
                     || ordine.gruppi[indiceGruppo].tieni;
        if (percorso === tenuto) return;   // quella che si tiene non si butta
        var s = ordine._copia(ordine.scelti);
        s[percorso] = s[percorso] !== true;
        ordine.scelti = s;
    }

    onSceltiChanged: ordine.cambiato()

    onTenutiChanged: ordine.cambiato()

    onRiferimentoChanged: ordine.cambiato()

    onGruppiChanged: ordine.cambiato()

    Connections {
        target: Core.Ipc

        function onManutenzioneEscluse(info) {
            if (!info) return;
            ordine.escluse = info.percorsi || [];
        }

        function onManutenzionePasso(p) {
            if (!p || String(p.fase || "") !== "doppioni") return;
            ordine.ultimoPasso = String(p.testo || "");
        }

        function onManutenzioneDoppioni(info) {
            if (!info) return;
            ordine.cercando = false;
            ordine.cercatoAlmenoUnaVolta = true;
            ordine.gruppi = info.gruppi || [];
            ordine.cartelle = info.cartelle || [];
            ordine.riferimento = "";
            ordine.sprecato = Number(info.sprecato) || 0;
            ordine.guardati = Number(info.guardati) || 0;
            ordine.scelti = ({});
            ordine.tenuti = ({});
        }

        function onManutenzioneDoppioniTolti(esito) {
            if (!esito) return;
            if (esito.ok !== true) {
                ordine.scrivi(esito.errore || "Non ce l'ho fatta.");
                return;
            }
            var rif = esito.rifiutati || [];
            for (var i = 0; i < rif.length; i++)
                ordine.scrivi(rif[i].percorso + ": " + rif[i].perche);
            ordine.scrivi("Nel cestino " + (esito.cestinati || 0)
                          + " copie. Ricontrollo.");
            ordine.cerca();
        }
    }

    // ── Il corpo ─────────────────────────────────────────────────────────

    Flickable {
        id: rotolo
        anchors.fill: parent
        anchors.bottomMargin: fondo.height
        clip: true
        contentWidth: width
        contentHeight: dentro.implicitHeight + Theme.Effects.space5 * 2
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: dentro
            x: Theme.Effects.space5
            y: Theme.Effects.space5
            width: rotolo.width - Theme.Effects.space5 * 2
            spacing: Theme.Effects.space4

            // Prima di cercare, e mentre si cerca.
            Item {
                width: parent.width
                height: 220
                visible: !ordine.cercatoAlmenoUnaVolta

                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: Theme.Effects.space3

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: ordine.cercando ? "Sto guardando…"
                                              : "I file che hai due volte"
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXL
                        font.weight: Theme.Typography.weightSemiBold
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: ordine.cercando
                              ? (ordine.ultimoPasso !== ""
                                 ? ordine.ultimoPasso
                                 : "Confronto per dimensione, poi le due estremità, "
                                   + "poi il file intero.")
                              : "Guarda la tua cartella di casa e trova i file "
                                + "identici byte per byte. Il codice non si "
                                + "tocca: dentro un progetto i doppioni sono normali."
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                }
            }

            // Niente doppioni: una risposta, non uno spazio bianco.
            Item {
                width: parent.width
                height: 200
                visible: ordine.cercatoAlmenoUnaVolta && !ordine.cercando
                         && ordine.gruppi.length === 0

                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: Theme.Effects.space2

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "Nessun doppione"
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXL
                        font.weight: Theme.Typography.weightSemiBold
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "Ho confrontato " + ordine.guardati
                              + " file: è tutta roba diversa."
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                }
            }

            Column {
                width: parent.width
                spacing: Theme.Effects.space2

                // ── Le cartelle che non si guardano ─────────────────────────
                //
                // Sta QUI, prima di tutto e anche prima di aver cercato: è prima
                // che serve. Una scansione che passa dentro `~/Android` — 3,1 GB
                // e 45.403 file — perde un minuto e riempie l'elenco di roba da
                // non toccare, e accorgersene dopo vuol dire rifarla.
                //
                // Di serie ne salta già un elenco (Progetti, node_modules,
                // Android, flutter): roba GENERATA o scaricata, dove i doppioni
                // sono normali. Queste sono in più, e sono di chi usa il
                // computer — nessun elenco scritto da noi può conoscere le sue
                // cartelle.

            Flow {
                width: parent.width
                spacing: Theme.Effects.space2

                // Niente ancore qui dentro: un `Flow` dispone i figli da
                // sé, e un'ancora glielo impedisce — lo dice a voce alta
                // («Flow will not function») e poi non dispone più niente.
                Text {
                    height: 26
                    verticalAlignment: Text.AlignVCenter
                    text: ordine.escluse.length === 0
                          ? "Non guardo dentro:"
                          : "Non guardo dentro (" + ordine.escluse.length + "):"
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }

                Repeater {
                    model: ordine.escluse

                    Rectangle {
                        id: esclusa
                        required property var modelData
                        implicitWidth: nomeEsclusa.implicitWidth + 34
                        implicitHeight: 26
                        radius: Theme.Effects.radiusFull
                        color: Theme.Colors.sunken
                        border.width: Theme.Effects.hairline
                        border.color: Theme.Colors.edge

                        Text {
                            id: nomeEsclusa
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.Effects.space3
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                var p = esclusa.modelData;
                                var t = p.lastIndexOf("/");
                                return t >= 0 ? p.substring(t + 1) : p;
                            }
                            color: Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                        }

                        // La crocetta rimette dentro. Il segno è fatto di
                        // due rettangoli girati e non di `Ui.Icon`: le
                        // Shape dentro una lista che scorre lasciano la
                        // loro copia sul grafico (vedi `Spunta.qml`).
                        Item {
                            id: croce
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.Effects.space2
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12; height: 12

                            Rectangle {
                                anchors.centerIn: parent
                                width: 11; height: 1.6; radius: 1
                                rotation: 45
                                color: ditoCroce.containsMouse
                                       ? Theme.Colors.danger
                                       : Theme.Colors.textFaint
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 11; height: 1.6; radius: 1
                                rotation: -45
                                color: ditoCroce.containsMouse
                                       ? Theme.Colors.danger
                                       : Theme.Colors.textFaint
                            }

                            MouseArea {
                                id: ditoCroce
                                anchors.fill: parent
                                anchors.margins: -5
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Core.Ipc.manutenzioneIncludi(
                                    esclusa.modelData)
                            }
                        }

                        // Il percorso per esteso al passaggio: la
                        // pastiglia mostra solo l'ultimo pezzo, e due
                        // cartelle possono chiamarsi uguale.
                        Ui.ToolTipHint {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom
                            text: esclusa.modelData
                            shown: ditoNome.containsMouse
                        }

                        MouseArea {
                            id: ditoNome
                            anchors.fill: parent
                            anchors.rightMargin: 22
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }
                    }
                }

                Rectangle {
                    implicitWidth: piuTesto.implicitWidth + Theme.Effects.space4
                    implicitHeight: 26
                    radius: Theme.Effects.radiusFull
                    color: ditoPiu.containsMouse ? Theme.Colors.hover
                                                 : "transparent"
                    border.width: Theme.Effects.hairline
                    border.color: Theme.Colors.edge

                    Text {
                        id: piuTesto
                        anchors.centerIn: parent
                        text: "+ escludi una cartella"
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXS
                    }

                    MouseArea {
                        id: ditoPiu
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ordine.scegliCartella = true
                    }
                }
            }
        }

            // ── La scelta del riferimento ───────────────────────────────
            Column {
                width: parent.width
                spacing: Theme.Effects.space2
                visible: ordine.cartelle.length > 0

                Text {
                    text: "Qual è la cartella buona?"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeLG
                    font.weight: Theme.Typography.weightSemiBold
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Prendine una come riferimento — per esempio un "
                          + "backup appena arrivato — e tutte le copie che "
                          + "stanno fuori vengono spuntate. Quello che c'è "
                          + "dentro non si tocca."
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }

                Flow {
                    width: parent.width
                    spacing: Theme.Effects.space2

                    Repeater {
                        model: ordine.cartelle

                        Rectangle {
                            id: pastiglia
                            required property var modelData

                            readonly property bool sua:
                                ordine.riferimento === pastiglia.modelData.percorso

                            implicitWidth: dentroPastiglia.implicitWidth
                                           + Theme.Effects.space4 * 2
                            implicitHeight: 46
                            radius: Theme.Effects.radiusSM
                            color: pastiglia.sua
                                   ? Theme.Colors.selected
                                   : (ditoPastiglia.containsMouse
                                      ? Theme.Colors.hover : Theme.Colors.sunken)
                            border.width: Theme.Effects.hairline
                            border.color: pastiglia.sua ? Theme.Colors.edgeAccent
                                                        : Theme.Colors.edge

                            Behavior on color {
                                ColorAnimation { duration: Theme.Motion.instant }
                            }

                            Column {
                                id: dentroPastiglia
                                anchors.centerIn: parent
                                spacing: 1

                                Text {
                                    text: {
                                        var p = pastiglia.modelData.percorso;
                                        var t = p.lastIndexOf("/");
                                        return t >= 0 ? p.substring(t + 1) : p;
                                    }
                                    color: pastiglia.sua ? Theme.Colors.accent
                                                         : Theme.Colors.text
                                    font.family: Theme.Typography.fontDisplay
                                    font.pixelSize: Theme.Typography.sizeSM
                                    font.weight: Theme.Typography.weightMedium
                                }

                                Text {
                                    text: "libera "
                                          + Misure.peso(pastiglia.modelData.liberabili)
                                    color: Theme.Colors.textFaint
                                    font.family: Theme.Typography.fontDisplay
                                    font.pixelSize: Theme.Typography.sizeXS
                                }
                            }

                            MouseArea {
                                id: ditoPastiglia
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pastiglia.sua
                                           ? ordine.nessuna()
                                           : ordine.applicaRiferimento(
                                               pastiglia.modelData.percorso)
                            }
                        }
                    }
                }

                // Il percorso per esteso della scelta: i nomi delle cartelle
                // si somigliano (due «DCIM» in due posti diversi), e la
                // pastiglia da sola non basterebbe a sapere quale hai preso.
                Text {
                    width: parent.width
                    visible: ordine.riferimento !== ""
                    text: "Riferimento: " + ordine.riferimento
                    color: Theme.Colors.accent
                    elide: Text.ElideMiddle
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeXS
                }

            }

            Repeater {
                model: ordine.gruppi

                Column {
                    id: gruppo
                    required property var modelData
                    required property int index
                    width: dentro.width
                    spacing: 2

                    readonly property string tenuto:
                        ordine.tenuti[gruppo.index] || gruppo.modelData.tieni

                    Item {
                        width: parent.width
                        height: 30

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: Misure.peso(gruppo.modelData.byteInPiu)
                                  + " in più · " + gruppo.modelData.percorsi.length
                                  + " copie"
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeMD
                            font.weight: Theme.Typography.weightSemiBold
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: gruppo.modelData.perche || ""
                            color: Theme.Colors.textFaint
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                    }

                    Repeater {
                        model: gruppo.modelData.percorsi

                        RigaCopia {
                            required property var modelData
                            width: dentro.width
                            percorso: modelData
                            tenuta: modelData === gruppo.tenuto
                            scelta: ordine.scelti[modelData] === true
                            onCommutata: ordine.commuta(modelData, gruppo.index)
                            onVoglioTenerla: ordine.tieniInvece(gruppo.index, modelData)
                        }
                    }
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        z: 10
        active: ordine.scegliCartella
        sourceComponent: Component {
            Ui.Scegli {
                soloCartelle: true
                titolo: "Quale cartella non devo guardare?"
                onScelto: (percorso) => {
                    Core.Ipc.manutenzioneEscludi(percorso);
                    ordine.scegliCartella = false;
                    ordine.scrivi("Non guarderò più dentro " + percorso + ".");
                }
                onAnnullato: ordine.scegliCartella = false
            }
        }
    }

    Ui.Scorrimento {
        bersaglio: rotolo
        anchors { right: rotolo.right; top: rotolo.top; bottom: rotolo.bottom }
    }

    // ── Il fondo ─────────────────────────────────────────────────────────

    Rectangle {
        id: fondo
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 64
        color: Theme.Colors.panel

        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 1
            color: Theme.Colors.edge
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space5
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.Effects.space2
            visible: ordine.gruppi.length > 0

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Misure.peso(ordine.sprecato)
                color: Theme.Colors.accent
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeLG
                font.weight: Theme.Typography.weightBold
                font.features: ({ "tnum": 1 })
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "sprecati in " + ordine.gruppi.length + " gruppi"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space5
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.Effects.space2

            Pulsante {
                anchors.verticalCenter: parent.verticalCenter
                visible: ordine.gruppi.length > 0
                testo: "Togli le spunte"
                attivo: ordine.sceltiQuanti > 0
                onScelto: ordine.nessuna()
            }

            Pulsante {
                anchors.verticalCenter: parent.verticalCenter
                visible: ordine.gruppi.length > 0
                testo: "Tutte tranne una"
                onScelto: ordine.scegliTutteMenoUna()
            }

            Pulsante {
                anchors.verticalCenter: parent.verticalCenter
                primario: true
                attivo: !ordine.cercando
                        && (ordine.gruppi.length === 0 || ordine.sceltiQuanti > 0)
                testo: {
                    if (ordine.cercando) return "Sto guardando…";
                    if (ordine.gruppi.length === 0) return "Cerca i doppioni";
                    if (ordine.sceltiQuanti === 0) return "Scegli cosa togliere";
                    return "Nel cestino " + ordine.sceltiQuanti + " copie";
                }
                onScelto: {
                    if (ordine.gruppi.length === 0) { ordine.cerca(); return; }
                    var via = [];
                    for (var k in ordine.scelti)
                        if (ordine.scelti[k] === true) via.push(k);
                    ordine.scrivi("Metto nel cestino " + via.length + " copie.");
                    Core.Ipc.manutenzioneDoppioniCestina(via);
                }
            }
        }
    }

    // Lo stesso pulsante della pagina Spazio. Sta scritto due volte e non in
    // `ui/`, per la stessa ragione di `permessi.qml`: `Ui.SpineButton` è il
    // pulsante della barra, sobrio apposta, e qui serve una cosa che si veda.
    component Pulsante: Rectangle {
        id: pulsante
        property string testo: ""
        property bool primario: false
        property bool attivo: true
        signal scelto()

        implicitWidth: etichetta.implicitWidth + Theme.Effects.space5 * 2
        implicitHeight: 36
        radius: Theme.Effects.radiusMD
        opacity: pulsante.attivo ? 1 : 0.45
        color: pulsante.primario
               ? (area.containsMouse && pulsante.attivo
                  ? Qt.lighter(Theme.Colors.accent, 1.12) : Theme.Colors.accent)
               : (area.containsMouse ? Theme.Colors.hover : Theme.Colors.raised)
        border.width: pulsante.primario ? 0 : Theme.Effects.hairline
        border.color: Theme.Colors.edge

        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

        Text {
            id: etichetta
            anchors.centerIn: parent
            text: pulsante.testo
            color: pulsante.primario ? Theme.Colors.textOnAccent
                                     : Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            font.weight: Theme.Typography.weightMedium
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            enabled: pulsante.attivo
            cursorShape: Qt.PointingHandCursor
            onClicked: pulsante.scelto()
        }
    }
}

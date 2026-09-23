import QtQuick
import Quickshell

import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Minerva Manutenzione — cosa occupa posto su questo computer, e cosa se ne
// può fare.
//
// ── Da dove nasce ──────────────────────────────────────────────────────────
//
// Giacomo, 8 settembre 2026: «vorrei un nostro software che pulisca per bene
// il pc e controlli dipendenze non necessarie, lingue non necessarie, con la
// nostra interfaccia», e come modello Stacer, che è abbandonato da anni.
//
// Poi, guardando: «deve essere dettagliata mostrando ogni dettaglio ad esempio
// se è cache, miniature file temporanei, possibilità di deselezionare opzioni
// [...] con grafici fighi e deve essere molto curata esteticamente». E infine:
// «mettiamoci barre di progresso e live log».
//
// ── Cosa la rende diversa da Stacer, che è tutto il progetto ───────────────
//
// Stacer è un cruscotto con tre cerchi grandi e un pulsante che «ottimizza».
// Questa è **un inventario che dice la verità**, e solo dopo un attrezzo.
//
// Il disco di questa macchina è da 950 GB con 617 liberi: non stai per
// riempirlo. Quindi questa finestra non ti salva da niente — **ti fa sapere**.
// È una ragione più onesta di «libera spazio!», e cambia il tono di ogni
// schermata: nessun allarme rosso, nessuna percentuale inventata, nessun
// pulsante che fa una cosa che non si è vista prima.
//
// Le quattro regole che ne discendono, e che valgono anche per il giorno in
// cui questa finestra imparerà a cancellare:
//
//   1. **Niente si tocca senza averlo mostrato prima.** Il conto, poi la
//      spunta, poi il comando.
//   2. **Si dice sempre se torna.** «Si rifà da sola» e «non torna» sono due
//      cose diverse, e chi guarda deve saperlo prima di decidere.
//   3. **Nessuna euristica.** Nessun «file che sembrano inutili». Solo posti
//      che si sanno per certo. Il giorno che un programma di pulizia cancella
//      una cosa che serviva, non lo riapri più.
//   4. **Le cose si chiamano per nome.** Tre pacchetti orfani si elencano,
//      non si contano: uno di quei tre potrebbe servirti.
//
// ── Cosa fa OGGI, detto in chiaro ──────────────────────────────────────────
//
// Guarda e basta. Non c'è un solo pulsante che tolga qualcosa, e non è una
// dimenticanza: è la prima tappa. Cancellare passa dall'aiutante di root
// (`scripts/minerva-radice`), che ha un elenco chiuso di verbi, e arriva
// dopo — con lo stesso registro che si vede già qui a raccontare cosa
// succede.
FloatingWindow {
    id: finestra

    // I colori arrivano dal demone: mostrarsi col tema di fabbrica e poi
    // scattare è il difetto che tutte le finestre di Minerva hanno già pagato.
    visible: Core.Ipc.prontoADipingere && !finestra.dormiente
    property bool dormiente: false

    title: "Minerva · Manutenzione"
    implicitWidth: 1120
    implicitHeight: 780
    minimumSize: Qt.size(820, 560)
    color: Theme.Colors.window

    signal requestClose()
    onClosed: finestra.requestClose()

    // ── Le scie, e il pennello che le cancella ───────────────────────────
    //
    // Giacomo, 9 settembre 2026: «electron builder e pip e pacchetti già
    // installati una volta cliccato lasciano residui di spunte sul grafico
    // [...] lo abbiamo già affrontato in impostazioni questo problema dei
    // residui».
    //
    // È lo stesso difetto, ed è la stessa cura — quella scritta per esteso in
    // `settings/System.qml` e in `settings/sections/Page.qml`.
    //
    // La causa non è nostra: col renderer software una `Shape` dipinge anche
    // FUORI dal ritaglio del `Flickable`. Le nostre spunte sono `Shape`, e
    // ogni fotogramma ne lascia una copia sopra il quadro fermo, dove non
    // ridipinge mai nessuno. Il ritaglio andrebbe rispettato da Qt e non lo
    // è: da qui non si ripara.
    //
    // Quello che si può fare è togliere il posto dove le scie si depositano:
    // si ridipinge tutta la finestra, apposta, nei momenti in cui si
    // depositano. Sono tre, e ognuno ha alle spalle il suo difetto:
    //
    //   · quando si SPUNTA — le spunte fantasma sul grafico, che è quello che
    //     Giacomo ha visto;
    //   · quando si APRE o CHIUDE una sezione — l'elenco si ridispone tutto,
    //     e le frecce girano;
    //   · mentre si SCORRE — la scia verticale, quella riconosciuta il 5
    //     settembre («l'errore si trova sempre in verticale»).

    /// Si alterna a ogni scatto del pittore. Non è un colore: è il segnale
    /// che dice al rettangolo del fondo di cambiare, e quindi a Qt che c'è da
    /// ridisegnare.
    property bool _altraTinta: false

    /// ── Perché venti scatti e non uno ────────────────────────────────────
    ///
    /// Perché un solo ridisegno chiesto con `Qt.callLater` arriva PRIMA che
    /// l'elenco abbia finito di ridisporsi: si ridipinge, e un istante dopo la
    /// riga che si sposta deposita la sua scia. Ridipingere prima del difetto
    /// non serve a niente.
    ///
    /// E c'è un secondo motivo, meno ovvio: alternare fra DUE tinte può
    /// annullarsi. Se il richiamo arriva due volte fra un disegno e l'altro,
    /// il colore torna quello di prima e non si ridipinge niente. Con venti
    /// scatti il caso non si pone.
    function ridipingiTutto() {
        pittore.restanti = 20;
        pittore.start();
    }

    Timer {
        id: pittore
        interval: 16
        repeat: true
        property int restanti: 0
        onTriggered: {
            finestra._altraTinta = !finestra._altraTinta;
            if (--pittore.restanti <= 0)
                pittore.stop();
        }
    }

    // Il pennello: un rettangolo grande quanto la finestra, sotto tutto, che
    // cambia di un livello su 255. Cambiando dichiara sporca la propria area
    // — cioè tutta la finestra — e Qt è costretto a ridisegnare ogni cosa che
    // ci sta sopra. Le scie non sono oggetti di nessuno: nessuno le
    // ridisegna, e spariscono.
    //
    // Due neri quasi trasparenti (1 e 2 su 255) e non uno trasparente: un
    // rettangolo davvero trasparente Qt lo salta, e saltandolo non sporca
    // niente.
    Rectangle {
        anchors.fill: parent
        z: -1
        color: finestra._altraTinta ? Qt.rgba(0, 0, 0, 1 / 255)
                                    : Qt.rgba(0, 0, 0, 2 / 255)
    }

    onScelteChanged: Qt.callLater(finestra.ridipingiTutto)
    onAperteChanged: Qt.callLater(finestra.ridipingiTutto)

    // ── I dati ───────────────────────────────────────────────────────────

    property var voci: []
    property var famiglie: ({})
    property var orfani: []
    property real totale: 0

    /// Quanto Manutenzione ha recuperato **da sempre**: `{byte, volte, dal}`.
    /// Arriva insieme all'inventario, ed è l'unica cosa che questo programma
    /// si ricorda — tutto il resto lo rimisura ogni volta.
    property var recuperato: ({})

    /// ── Le due pagine ────────────────────────────────────────────────────
    ///
    /// `spazio` — cosa occupa posto e cosa si può togliere.
    /// `ordine`  — i file che ci sono due volte.
    ///
    /// Due schede in cima e non una colonna a sinistra: con due voci una
    /// colonna è un elenco di due righe che si guarda una volta sola. Quando
    /// saranno cinque — aggiornamenti, salute, storia — diventerà la colonna
    /// delle Impostazioni, che è già collaudata.
    property string pagina: "spazio"
    property bool caricando: false

    /// Quali voci sono spuntate, per `id`. Una mappa e non un elenco: le
    /// voci si ricaricano ogni volta che si rilegge, e un indice punterebbe
    /// a una voce diversa da quella spuntata. L'`id` è la stessa parola che
    /// un giorno arriverà all'aiutante di root.
    property var scelte: ({})

    /// La famiglia sotto il dito, per legare la riga dell'elenco alla fetta
    /// dell'anello. Un anello che non si collega a niente è un bel disegno
    /// muto.
    property string evidenziata: ""

    readonly property real massimo: {
        var m = 1;
        for (var i = 0; i < finestra.voci.length; i++)
            m = Math.max(m, Number(finestra.voci[i].byte) || 0);
        return m;
    }

    readonly property real spuntati: {
        var s = 0;
        for (var i = 0; i < finestra.voci.length; i++) {
            var v = finestra.voci[i];
            if (finestra.scelte[v.id] === true)
                s += Number(v.byte) || 0;
        }
        return s;
    }

    readonly property bool vuoleLaPassword: {
        for (var i = 0; i < finestra.voci.length; i++) {
            var v = finestra.voci[i];
            if (finestra.scelte[v.id] === true && v.vuoleLaPassword === true)
                return true;
        }
        return false;
    }

    // ── Le famiglie presenti, nell'ordine di quanto è facile decidere ────

    readonly property var gruppi: {
        var fuori = [];
        var ordine = Misure.ordine();
        for (var k = 0; k < ordine.length; k++) {
            var cat = ordine[k];
            var dentro = [];
            var somma = 0;
            for (var i = 0; i < finestra.voci.length; i++) {
                if (finestra.voci[i].categoria === cat) {
                    dentro.push(finestra.voci[i]);
                    somma += Number(finestra.voci[i].byte) || 0;
                }
            }
            if (dentro.length > 0)
                fuori.push({ "categoria": cat, "voci": dentro, "byte": somma,
                             "colore": Misure.colore(cat) });
        }
        return fuori;
    }

    // ── Le spunte ────────────────────────────────────────────────────────

    // ── Una mappa NUOVA ogni volta, e non è pignoleria ───────────────────
    //
    // Giacomo, 9 settembre 2026: «non riesco a selezionare una singola voce
    // ad esempio se non voglio cancellare tutto».
    //
    // Era questo. Il codice prendeva `finestra.scelte`, ci scriveva dentro e
    // la riassegnava a sé stessa — e in QML una `property var` riassegnata
    // **allo stesso oggetto** non è un cambiamento: il valore è identico,
    // perché è lo stesso indirizzo. Le spunte delle righe sono legate a
    // `scelte[id]`, e quel legame non veniva mai risvegliato.
    //
    // Il conto in fondo continuava a funzionare per caso: si ricalcolava a
    // ogni altra cosa che si muoveva. Quindi il difetto non era «non cambia
    // niente», era peggio: cambiava a volte.
    //
    // La cura è copiare. Una mappa nuova ha un altro indirizzo, e QML se ne
    // accorge. È la stessa trappola di `qml-ancore-undefined`: una cosa che
    // sembra fatta e non lo è, senza un errore da nessuna parte.
    function _copia(m) {
        var fuori = ({});
        for (var k in m) fuori[k] = m[k];
        return fuori;
    }

    function commuta(id) {
        var m = finestra._copia(finestra.scelte);
        m[id] = m[id] !== true;
        finestra.scelte = m;
    }

    function commutaFamiglia(cat) {
        // Se ce n'è anche una sola spenta si accendono tutte; se sono tutte
        // accese si spengono. È il verso che si aspetta chi clicca: la prima
        // volta «prendile tutte».
        var tutte = true;
        for (var i = 0; i < finestra.voci.length; i++) {
            var v = finestra.voci[i];
            if (v.categoria === cat && finestra.scelte[v.id] !== true)
                tutte = false;
        }
        var m = finestra._copia(finestra.scelte);
        for (var j = 0; j < finestra.voci.length; j++) {
            var w = finestra.voci[j];
            if (w.categoria === cat)
                m[w.id] = !tutte;
        }
        finestra.scelte = m;
    }

    /// Quali sezioni sono aperte. Chiuse all'apertura, tutte: la finestra
    /// serve prima a far vedere **quanto** e solo dopo **cosa**, e ventotto
    /// righe in faccia sono un elenco che non si legge.
    ///
    /// Non si ricorda fra un'apertura e l'altra, ed è voluto: sarebbe una
    /// preferenza in più da scrivere nelle impostazioni per far risparmiare
    /// un clic.
    property var aperte: ({})

    function apriChiudi(cat) {
        // Copiata, per la stessa ragione di `commuta()`: riassegnare lo
        // stesso oggetto non sveglia nessun legame.
        var m = finestra._copia(finestra.aperte);
        m[cat] = m[cat] !== true;
        finestra.aperte = m;
    }

    function quante(cat) {
        var n = 0;
        for (var i = 0; i < finestra.voci.length; i++)
            if (finestra.voci[i].categoria === cat) n++;
        return n;
    }

    function statoFamiglia(cat) {
        var accese = 0, quante = 0;
        for (var i = 0; i < finestra.voci.length; i++) {
            var v = finestra.voci[i];
            if (v.categoria !== cat) continue;
            quante++;
            if (finestra.scelte[v.id] === true) accese++;
        }
        if (accese === 0) return 0;
        return accese === quante ? 1 : 2;
    }

    function nessuna() {
        finestra.scelte = ({});
    }

    /// ── Quali sono spuntate all'apertura ─────────────────────────────────
    ///
    /// Quelle che si rifanno da sole, non chiedono la password e non hanno
    /// niente da avvertire: le cache dei programmi e le miniature. Sono le
    /// uniche su cui la risposta è la stessa per chiunque.
    ///
    /// **Fuori** restano di proposito: la roba di sviluppo (torna, ma costa
    /// una compilazione lenta), i pacchetti scaricati e il registro (servono
    /// a tornare indietro quando qualcosa si rompe), le lingue (tornerebbero
    /// da sole comunque), i file temporanei (un programma aperto adesso
    /// potrebbe averci dentro qualcosa) e il cestino, che l'hai riempito tu.
    ///
    /// Preselezionare tutto sarebbe la scorciatoia comoda ed è esattamente il
    /// difetto di Stacer: un pulsante che parte già carico e cancella cose
    /// che nessuno ha guardato.
    function scegliLeSicure() {
        var m = ({});
        for (var i = 0; i < finestra.voci.length; i++) {
            var v = finestra.voci[i];
            var sicura = v.torna === "sola"
                         && v.vuoleLaPassword !== true
                         && String(v.avvertenza || "") === ""
                         && (v.categoria === "cache" || v.categoria === "miniature");
            if (sicura) m[v.id] = true;
        }
        finestra.scelte = m;
    }

    // ── Il collegamento col demone ───────────────────────────────────────

    function rileggi() {
        if (finestra.caricando) return;
        finestra.caricando = true;
        diario.avanzamento = 0;
        diario.scrivi("Comincio a guardare.");
        Core.Ipc.manutenzioneVedi();
    }

    Connections {
        target: Core.Ipc

        function onManutenzionePasso(p) {
            if (!p) return;
            var quante = Number(p.quante) || 1;
            diario.avanzamento = Math.max(0, Math.min(1, (Number(p.fatte) || 0) / quante));
            diario.scrivi(String(p.testo || ""));
        }

        function onManutenzioneInventario(info) {
            if (!info) return;
            finestra.caricando = false;
            diario.avanzamento = -1;
            finestra.voci = info.voci || [];
            finestra.famiglie = info.famiglie || ({});
            finestra.orfani = info.orfani || [];
            finestra.totale = Number(info.totale) || 0;
            finestra.recuperato = info.recuperato || ({});
            diario.scrivi("Trovati " + Misure.peso(finestra.totale)
                          + " in " + finestra.voci.length + " voci.");
            // La prima volta si propone una scelta; dopo no, o rileggendo si
            // butterebbe via quello che si era appena spuntato a mano.
            if (finestra._primaVolta) {
                finestra._primaVolta = false;
                finestra.scegliLeSicure();
            }
        }

        function onManutenzioneOrfaniTolti(esito) {
            if (!esito) return;
            finestra.togliendoOrfani = false;
            if (esito.ok !== true) {
                diario.scrivi(esito.errore || "Non ce l'ho fatta.");
                return;
            }
            diario.scrivi(esito.quanti > 0
                          ? "Tolti " + esito.quanti + " pacchetti. Ricontrollo."
                          : "Non c'era più niente da togliere.");
            finestra.rileggi();
        }

        function onManutenzionePulito(esito) {
            if (!esito) return;
            finestra.pulendo = false;
            diario.avanzamento = -1;
            if (esito.ok !== true) {
                diario.scrivi(esito.errore || "Non ce l'ho fatta.");
                return;
            }
            // Voce per voce, e solo quelle andate storte: un elenco di
            // ventidue righe verdi non lo legge nessuno, e le due rosse in
            // mezzo si perderebbero.
            var fatte = esito.fatte || [];
            for (var i = 0; i < fatte.length; i++) {
                if (fatte[i].ok !== true)
                    diario.scrivi(fatte[i].id + ": " + (fatte[i].perche || "non riuscito"));
            }
            diario.scrivi("Tolte " + (esito.quante || 0) + " voci"
                          + ((esito.nonRiuscite || 0) > 0
                             ? ", " + esito.nonRiuscite + " no" : "")
                          + ". Adesso ricontrollo.");
            // ── Si rimisura, sempre ─────────────────────────────────────
            //
            // Il numero che conta non è quello promesso prima: è quello che
            // l'inventario trova dopo. Rileggendo, il totale in cima scende
            // da sé — e se non scende, si vede.
            finestra.scelte = ({});
            finestra.rileggi();
        }

        // Il demone dice quando un'azione è fallita invece di tacere: senza
        // questa riga, un inventario che scoppia lascerebbe la barra ferma a
        // metà per sempre.
        function onAzioneFallita(azione, perche) {
            if (azione !== "manutenzione_inventario"
                && azione !== "manutenzione_pulisci") return;
            finestra.pulendo = false;
            finestra.caricando = false;
            diario.avanzamento = -1;
            diario.scrivi("Non ce l'ho fatta: " + (perche || "non so perché"));
        }
    }

    property bool _primaVolta: true

    /// Vero mentre il demone sta togliendo. Serve a spegnere tutto quello che
    /// si può premere: una seconda pulizia partita in mezzo alla prima
    /// lavorerebbe su un elenco già vecchio.
    property bool pulendo: false

    /// Vero quando si è chiesto di pulire e si aspetta la conferma. La
    /// conferma non è un fastidio da togliere appena si può: è la prima delle
    /// quattro regole — niente si tocca senza averlo mostrato prima.
    property bool chiedoConferma: false

    readonly property var idScelti: {
        var fuori = [];
        for (var i = 0; i < finestra.voci.length; i++) {
            var v = finestra.voci[i];
            if (finestra.scelte[v.id] === true) fuori.push(v.id);
        }
        return fuori;
    }

    /// Quante fra quelle spuntate chiedono la password. Oggi Minerva non le
    /// sa ancora togliere — passeranno dall'aiutante di root — e va detto
    /// PRIMA di premere, non dopo: un pulsante che promette 17 GB e ne toglie
    /// 9 è un pulsante che mente.
    readonly property int quanteConPassword: {
        var n = 0;
        for (var i = 0; i < finestra.voci.length; i++) {
            var v = finestra.voci[i];
            if (finestra.scelte[v.id] === true && v.vuoleLaPassword === true) n++;
        }
        return n;
    }


    property bool togliendoOrfani: false
    property bool confermoOrfani: false

    function togliOrfani() {
        if (finestra.togliendoOrfani || finestra.orfani.length === 0) return;
        finestra.confermoOrfani = false;
        finestra.togliendoOrfani = true;
        diario.scrivi("Tolgo i pacchetti rimasti soli: "
                      + finestra.orfani.join(", "));
        Core.Ipc.manutenzioneOrfani();
    }

    function pulisci() {
        if (finestra.pulendo || finestra.idScelti.length === 0) return;
        finestra.chiedoConferma = false;
        finestra.pulendo = true;
        diario.avanzamento = 0;
        diario.scrivi("Comincio a togliere.");
        Core.Ipc.manutenzionePulisci(finestra.idScelti);
    }

    Component.onCompleted: finestra.rileggi()

    // ── La barra del titolo ──────────────────────────────────────────────
    //
    // Disegnata qui dentro e non dal compositore: una barra disegnata fuori
    // insegue la finestra e arriva sempre un fotogramma dopo. Il perché lungo
    // sta in `ui/WindowTitleBar.qml`.

    Ui.WindowTitleBar {
        id: barra
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        label: finestra.title
        onCloseRequested: finestra.requestClose()
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

        Column {
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space5
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                text: "Manutenzione"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXL
                font.weight: Theme.Typography.weightSemiBold
            }

            Text {
                text: "Cosa occupa posto su questo computer"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }
        }

        Row {
            id: schede
            anchors.centerIn: parent
            spacing: Theme.Effects.space1

            Scheda { quale: "spazio"; testo: "Spazio" }
            Scheda { quale: "ordine"; testo: "Ordine" }
        }

        // ── Quanto hai recuperato da sempre ─────────────────────────────
        //
        // Giacomo: «possiamo mettere un riepilogo di tutto lo spazio che è
        // stato recuperato con la app? Giga totali ad esempio?».
        //
        // È il numero che dà senso a tutto il resto. Una singola pulizia si
        // dimentica il giorno dopo — «ho tolto 384 MB» non se lo ricorda
        // nessuno — mentre «da quando c'è, ti ha restituito dieci giga» è la
        // ragione per cui vale la pena riaprirla.
        //
        // Compare solo quando c'è: un «0 B recuperati» il primo giorno
        // sarebbe un rimprovero a chi ha appena installato il programma.
        Column {
            id: medaglia
            visible: (Number(finestra.recuperato.byte) || 0) > 0
            anchors.right: tastoRileggi.left
            anchors.rightMargin: Theme.Effects.space5
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
                anchors.right: parent.right
                text: "RECUPERATO IN TUTTO"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
                font.weight: Theme.Typography.weightSemiBold
                font.letterSpacing: Theme.Typography.trackingLabel
            }

            Row {
                anchors.right: parent.right
                spacing: Theme.Effects.space2

                Text {
                    text: Misure.peso(finestra.recuperato.byte)
                    color: Theme.Colors.accent
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeLG
                    font.weight: Theme.Typography.weightBold
                    font.features: ({ "tnum": 1 })
                }

                Text {
                    anchors.baseline: parent.children[0].baseline
                    text: {
                        var v = Number(finestra.recuperato.volte) || 0;
                        return v === 1 ? "in una pulizia"
                                       : "in " + v + " pulizie";
                    }
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }
        }

        // ── «Rileggi», scritto ──────────────────────────────────────────
        //
        // Era un quadratino da 36 pixel con dentro una freccia circolare:
        // Giacomo, «quel tasto per aggiornare è minuscolo». Un'icona da sola
        // costringe a indovinare o a scoprirlo passandoci sopra, e in una
        // finestra che si apre due volte al mese non lo impara nessuno.
        Pulsante {
            id: tastoRileggi
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space5
            anchors.verticalCenter: parent.verticalCenter
            attivo: !finestra.caricando && !finestra.pulendo
            testo: finestra.caricando ? "Sto guardando…" : "Rileggi"
            onScelto: finestra.rileggi()
        }
    }

    // ── Il quadro in cima STA FERMO, e non è una scelta di gusto ─────────
    //
    // Giacomo, 9 settembre 2026: «il grafico a torta scendendo nella pagina
    // rimane impresso a schermo un residuo e fa schifo».
    //
    // È il difetto di famiglia del disegno col processore, quello scritto in
    // `minerva-residui-software`: Qt ridipinge soltanto ciò che qualcuno ha
    // dichiarato sporco, e una forma dentro una superficie che scorre lascia
    // i propri pixel dov'erano. Si può curare a valle — obbligando la
    // finestra a ridipingersi tutta a ogni fotogramma di scorrimento — ma è
    // la cura peggiore: si paga un ridisegno pieno per tutta la lunghezza del
    // gesto, ed è proprio quando si vuole che scorra liscio.
    //
    // La cura vera è che l'anello non scorra affatto. E per una volta la cosa
    // giusta è anche la più comoda: il totale e la legenda restano sotto gli
    // occhi mentre si guarda l'elenco, che è esattamente quando servono.

    Item {
        id: cima
        visible: finestra.pagina === "spazio"
        // ── E le spunte che passavano DENTRO l'anello ────────────────────
        //
        // Giacomo, 9 settembre 2026: «miniature e cache addirittura risultano
        // passare attraverso il grafico, facendo scroll su e giù si muovono
        // su e giù dentro al grafico».
        //
        // Fotografato: scorrendo, dentro l'anello compariva una colonna di
        // spunte nere. Non era questo quadro a essere nel posto sbagliato —
        // era la lista a dipingere fuori dal proprio ritaglio, come fanno le
        // `Shape` col renderer software.
        //
        // Si poteva coprire (questo quadro sopra la lista, con un fondo
        // opaco) e si poteva ridipingere. La prima cosa toglie il vetro a
        // una fascia della finestra, la seconda insegue una scia appena
        // depositata. Si è tolta invece la causa: spunte e frecce adesso
        // sono rettangoli e non `Shape` — vedi `Spunta.qml` e `Freccia.qml`
        // — e un rettangolo il ritaglio lo rispetta.
        //
        // Provato con il pennello SPENTO, che è l'unico modo di sapere se la
        // causa è andata via davvero e non solo coperta.
        anchors.top: testata.bottom
        anchors.topMargin: Theme.Effects.space5
        anchors.left: parent.left
        anchors.leftMargin: Theme.Effects.space5
        anchors.right: parent.right
        anchors.rightMargin: Theme.Effects.space5
        height: 236

        Anello {
            id: anello
            width: 224
            height: 224
            anchors.left: parent.left
            anchors.top: parent.top
            fette: finestra.gruppi
            totale: finestra.totale
            evidenziata: finestra.evidenziata
        }

        // Il numero grande sta DENTRO il buco dell'anello: la parte e
        // il tutto si leggono senza spostare gli occhi.
        Column {
            anchors.centerIn: anello
            width: anello.width - 70
            spacing: 0

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: finestra.evidenziata === ""
                      ? Misure.peso(finestra.totale)
                      : Misure.peso(finestra.famiglie[finestra.evidenziata] || 0)
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXL
                font.weight: Theme.Typography.weightBold
                font.features: ({ "tnum": 1 })
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: finestra.evidenziata === ""
                      ? "si possono togliere"
                      : Misure.nome(finestra.evidenziata)
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }
        }

        // La legenda: una riga per famiglia, con il suo colore.
        Column {
            id: legenda
            anchors.left: anello.right
            anchors.leftMargin: Theme.Effects.space5
            anchors.top: anello.top
            width: 250
            spacing: 2

            Repeater {
                model: finestra.gruppi

                Item {
                    width: legenda.width
                    height: 28

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.Effects.radiusXS
                        color: finestra.evidenziata === modelData.categoria
                               ? Theme.Colors.hover : "transparent"
                    }

                    Rectangle {
                        id: pallino
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.Effects.space2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10; height: 10
                        radius: Theme.Effects.radiusFull
                        color: modelData.colore
                    }

                    Text {
                        anchors.left: pallino.right
                        anchors.leftMargin: Theme.Effects.space2
                        anchors.verticalCenter: parent.verticalCenter
                        text: Misure.nome(modelData.categoria)
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.Effects.space2
                        anchors.verticalCenter: parent.verticalCenter
                        text: Misure.peso(modelData.byte)
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                        font.weight: Theme.Typography.weightMedium
                        font.features: ({ "tnum": 1 })
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: finestra.evidenziata = modelData.categoria
                        onExited: if (finestra.evidenziata === modelData.categoria)
                                      finestra.evidenziata = ""
                        onClicked: finestra.commutaFamiglia(modelData.categoria)
                    }
                }
            }
        }

        Registro {
            id: diario
            anchors.left: legenda.right
            anchors.leftMargin: Theme.Effects.space5
            anchors.right: parent.right
            anchors.top: anello.top
            anchors.bottom: anello.bottom
            titolo: finestra.caricando ? "Sto guardando" : "Registro"
        }
    }

    // ── Il corpo ─────────────────────────────────────────────────────────

    Flickable {
        id: rotolo
        visible: finestra.pagina === "spazio"
        anchors.top: cima.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: fondo.top
        clip: true
        contentWidth: width
        contentHeight: dentro.implicitHeight + Theme.Effects.space5 * 2
        boundsBehavior: Flickable.StopAtBounds

        onContentYChanged: Qt.callLater(finestra.ridipingiTutto)

        // `Qt.callLater` raggruppa: al massimo un ridisegno per fotogramma,
        // non uno per pixel di scorrimento.


        Column {
            id: dentro
            x: Theme.Effects.space5
            y: Theme.Effects.space5
            width: rotolo.width - Theme.Effects.space5 * 2
            spacing: Theme.Effects.space5

            // ── Quando non c'è niente ───────────────────────────────────
            //
            // Giacomo, 9 settembre 2026, dopo aver pulito quasi tutto:
            // «quando non c'è niente da pulire deve uscire scritto solamente
            // "Niente da pulire" invece delle selezioni».
            //
            // Un elenco vuoto non è una risposta: è uno spazio bianco, e chi
            // guarda si chiede se il programma abbia finito di caricare o si
            // sia rotto. La riga qui sotto è una risposta, ed è pure una
            // bella notizia.
            //
            // Non compare mentre si sta guardando: durante la scansione lo
            // spazio è vuoto perché non si sa ancora, non perché non c'è
            // niente, e dirlo prima sarebbe dire una cosa non vera per
            // qualche secondo.
            Item {
                width: parent.width
                height: 200
                visible: finestra.voci.length === 0 && !finestra.caricando

                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: Theme.Effects.space2

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "Niente da pulire"
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXL
                        font.weight: Theme.Typography.weightSemiBold
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: "Su questo computer non è rimasto niente che "
                              + "valga la pena togliere. Le cache si rifanno "
                              + "usandolo: fra qualche giorno riguarda."
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                }
            }

            // ── Le famiglie, una sezione per ognuna ─────────────────────

            Repeater {
                model: finestra.gruppi

                Column {
                    width: dentro.width
                    spacing: Theme.Effects.space2

                    // ── L'intestazione, quando serve ────────────────────
                    //
                    // Con una voce sola non serve: direbbe lo stesso nome e
                    // lo stesso numero della riga sotto. Lo si è visto in una
                    // fotografia — «Lingue che non usi» scritto due volte,
                    // 361 MB due volte — e allora la riga si fa capofamiglia
                    // da sé.
                    // ── L'intestazione si apre e si chiude ─────────────
                    //
                    // Giacomo: «metterei delle liste richiudibili per
                    // comprimere o allargare la singola sezione per non
                    // vedere tutta la lista delle cache». Sono ventidue voci
                    // solo di cache, e quasi sempre non si vuole guardarle:
                    // si vuole sapere quanto pesano tutte insieme e passare
                    // avanti.
                    //
                    // Chiuse all'apertura, quindi, e la spunta della famiglia
                    // resta raggiungibile senza aprire niente: chi si fida
                    // spunta il gruppo, chi non si fida apre e sceglie.
                    Item {
                        width: parent.width
                        height: 52
                        visible: modelData.voci.length > 1

                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: -Theme.Effects.space2
                            anchors.rightMargin: -Theme.Effects.space2
                            radius: Theme.Effects.radiusSM
                            color: ditoFamiglia.containsMouse ? Theme.Colors.hover
                                                              : "transparent"
                        }

                        Spunta {
                            id: spuntaFamiglia
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.Effects.space3
                            anchors.verticalCenter: parent.verticalCenter
                            stato: finestra.statoFamiglia(modelData.categoria)
                            onPremuta: finestra.commutaFamiglia(modelData.categoria)
                        }

                        Freccia {
                            id: freccia
                            anchors.left: spuntaFamiglia.right
                            anchors.leftMargin: Theme.Effects.space3
                            anchors.verticalCenter: parent.verticalCenter
                            aperta: finestra.aperte[modelData.categoria] === true
                        }

                        Rectangle {
                            id: tacca
                            anchors.left: freccia.right
                            anchors.leftMargin: Theme.Effects.space3
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: 26
                            radius: 2
                            color: modelData.colore
                        }

                        Column {
                            anchors.left: tacca.right
                            anchors.leftMargin: Theme.Effects.space3
                            anchors.right: pesoFamiglia.left
                            anchors.rightMargin: Theme.Effects.space4
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Row {
                                spacing: Theme.Effects.space2

                                Text {
                                    text: Misure.nome(modelData.categoria)
                                    color: Theme.Colors.text
                                    font.family: Theme.Typography.fontDisplay
                                    font.pixelSize: Theme.Typography.sizeLG
                                    font.weight: Theme.Typography.weightSemiBold
                                }

                                // Quante ce ne sono dentro: chiusa, è l'unica
                                // cosa che dice se aprirla vale la pena.
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.voci.length + " voci"
                                    color: Theme.Colors.textFaint
                                    font.family: Theme.Typography.fontDisplay
                                    font.pixelSize: Theme.Typography.sizeXS
                                }
                            }

                            Text {
                                width: parent.width
                                text: Misure.spiega(modelData.categoria)
                                color: Theme.Colors.textFaint
                                wrapMode: Text.WordWrap
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                        }

                        Text {
                            id: pesoFamiglia
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.Effects.space3
                            anchors.verticalCenter: parent.verticalCenter
                            text: Misure.peso(modelData.byte)
                            color: Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeMD
                            font.weight: Theme.Typography.weightSemiBold
                            font.features: ({ "tnum": 1 })
                        }

                        // Il clic sull'intestazione APRE, non spunta: sono
                        // due gesti diversi e devono restare due bersagli
                        // diversi, o aprire una sezione per guardarla dentro
                        // vorrebbe dire anche sceglierla per la cancellazione.
                        MouseArea {
                            id: ditoFamiglia
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: finestra.evidenziata = modelData.categoria
                            onExited: if (finestra.evidenziata === modelData.categoria)
                                          finestra.evidenziata = ""
                            onClicked: finestra.apriChiudi(modelData.categoria)
                        }
                    }

                    Repeater {
                        // Le voci esistono solo quando la sezione è aperta:
                        // ventidue righe costruite e nascoste sarebbero
                        // ventidue righe da disegnare e da misurare comunque.
                        model: finestra.aperte[modelData.categoria] === true
                               || modelData.voci.length === 1
                               ? modelData.voci : []

                        // `modelData` qui è la VOCE e non più la famiglia: i
                        // due Repeater si annidano e il nome interno copre
                        // quello esterno. La famiglia si ritrova dalla voce
                        // stessa, che se la porta dietro.
                        RigaVoce {
                            required property var modelData
                            width: dentro.width
                            voce: modelData
                            colore: Misure.colore(modelData.categoria)
                            massimo: finestra.massimo
                            capofamiglia: finestra.quante(modelData.categoria) === 1
                            spiegazione: Misure.spiega(modelData.categoria)
                            scelta: finestra.scelte[modelData.id] === true
                            onCommutata: finestra.commuta(modelData.id)
                        }
                    }
                }
            }

            // ── Gli orfani, che non si misurano in byte ─────────────────

            Column {
                width: dentro.width
                spacing: Theme.Effects.space2
                visible: finestra.orfani.length > 0

                Text {
                    text: "Pacchetti rimasti soli"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeLG
                    font.weight: Theme.Typography.weightSemiBold
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    // Il numero di megabyte non si scrive perché **è zero**, e
                    // prometterli sarebbe la prima bugia del programma: gli
                    // orfani si tolgono per ordine, non per spazio.
                    text: "Installati come dipendenza di qualcosa che non c'è più. "
                          + "Non liberano spazio: si tolgono per ordine, e per questo "
                          + "sono scritti per nome — uno di loro potrebbe servirti."
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }

                Row {
                    spacing: Theme.Effects.space3

                    Pulsante {
                        testo: finestra.togliendoOrfani
                               ? "Sto togliendo…"
                               : (finestra.confermoOrfani
                                  ? "Sì, togli " + finestra.orfani.length
                                  : "Togli " + finestra.orfani.length
                                    + (finestra.orfani.length === 1
                                       ? " pacchetto" : " pacchetti"))
                        primario: finestra.confermoOrfani
                        attivo: !finestra.togliendoOrfani
                        onScelto: {
                            if (finestra.confermoOrfani)
                                finestra.togliOrfani();
                            else
                                finestra.confermoOrfani = true;
                        }
                    }

                    Pulsante {
                        visible: finestra.confermoOrfani && !finestra.togliendoOrfani
                        testo: "Lascia stare"
                        onScelto: finestra.confermoOrfani = false
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: finestra.confermoOrfani
                        text: "Ti chiederà la password."
                        color: Theme.Colors.warning
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }

                Flow {
                    width: parent.width
                    spacing: Theme.Effects.space2

                    Repeater {
                        model: finestra.orfani

                        Rectangle {
                            implicitWidth: nomeOrfano.implicitWidth + Theme.Effects.space4
                            implicitHeight: 30
                            radius: Theme.Effects.radiusFull
                            color: Theme.Colors.sunken
                            border.width: Theme.Effects.hairline
                            border.color: Theme.Colors.edge

                            Text {
                                id: nomeOrfano
                                anchors.centerIn: parent
                                text: modelData
                                color: Theme.Colors.textMuted
                                font.family: Theme.Typography.fontMono
                                font.pixelSize: Theme.Typography.sizeSM
                            }
                        }
                    }
                }
            }
        }
    }

    Ui.Scorrimento {
        visible: finestra.pagina === "spazio"
        bersaglio: rotolo
        anchors {
            right: rotolo.right
            top: rotolo.top
            bottom: rotolo.bottom
        }
    }

    // ── Il fondo: quanto hai spuntato ────────────────────────────────────
    //
    // Il numero sta qui **prima** che esista un pulsante che cancella, e non
    // è un caso: prima il conto, poi la spunta, poi il comando. Quando il
    // comando ci sarà, questo numero sarà già quello giusto e già collaudato.

    Ordine {
        id: paginaOrdine
        visible: finestra.pagina === "ordine"
        anchors.top: testata.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // Il registro è uno solo per tutta la finestra: quello che succede in
        // una pagina si legge anche tornando nell'altra.
        onScrivi: (riga) => diario.scrivi(riga)
        onCambiato: Qt.callLater(finestra.ridipingiTutto)
    }

    Rectangle {
        id: fondo
        visible: finestra.pagina === "spazio"
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
            visible: !finestra.chiedoConferma

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Misure.peso(finestra.spuntati)
                color: Theme.Colors.accent
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeLG
                font.weight: Theme.Typography.weightBold
                font.features: ({ "tnum": 1 })
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "spuntati su " + Misure.peso(finestra.totale)
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: finestra.vuoleLaPassword
                text: "· una parte chiederà la password"
                color: Theme.Colors.warning
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space5
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.Effects.space2
            visible: !finestra.chiedoConferma

            Ui.SpineButton {
                anchors.verticalCenter: parent.verticalCenter
                onClicked: finestra.nessuna()
                // Niente misure e niente ancore sul contenuto: il pulsante si
                // misura da sé sul testo (`holder.childrenRect`), e un
                // `anchors.centerIn: parent` qui dentro è un anello — la
                // larghezza dipende dal figlio e il figlio si centra sulla
                // larghezza. Qt lo dice a voce alta: «Binding loop detected».
                content: Text {
                    text: "Togli le spunte"
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }
            }

            Ui.SpineButton {
                anchors.verticalCenter: parent.verticalCenter
                onClicked: finestra.scegliLeSicure()
                content: Text {
                    text: "Solo quelle sicure"
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }
            }

            // ── Il pulsante che fa la cosa ──────────────────────────────
            //
            // Dice **quanto** libererà, e lo dice prima: «Pulisci» e basta
            // sarebbe un pulsante che chiede fiducia senza averla guadagnata.
            // Ed è spento quando non c'è niente da togliere, invece di
            // esserci e non fare niente.
            Pulsante {
                anchors.verticalCenter: parent.verticalCenter
                primario: true
                attivo: finestra.spuntati > 0
                        && !finestra.pulendo && !finestra.caricando
                testo: finestra.pulendo
                       ? "Sto togliendo…"
                       : (finestra.spuntati > 0
                          ? "Pulisci " + Misure.peso(finestra.spuntati)
                          : "Niente da pulire")
                onScelto: finestra.chiedoConferma = true
            }
        }

        // ── La conferma ─────────────────────────────────────────────────
        //
        // Prende il posto della riga di sotto invece di comparire in una
        // finestrella sopra: quello che stai per fare si legge dove stavi già
        // guardando, e il conto resta sotto gli occhi mentre decidi.
        //
        // Dice per esteso anche quello che **non** farà. Se hai spuntato i
        // pacchetti scaricati e il registro, quelle due voci restano dove
        // sono — e saperlo dopo, guardando un totale che non è sceso quanto
        // promesso, sarebbe il modo migliore per non fidarsi più.
        Row {
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space5
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space5
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.Effects.space3
            visible: finestra.chiedoConferma

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: fondo.width - 420
                wrapMode: Text.WordWrap
                text: {
                    var quante = finestra.idScelti.length;
                    var frase = "Tolgo " + quante + (quante === 1 ? " voce" : " voci")
                                + " per " + Misure.peso(finestra.spuntati) + ".";
                    // Se c'è roba di sistema si dice PRIMA che comparirà la
                    // finestrella della password: una richiesta che arriva
                    // senza preavviso, mentre credi di aver già finito, è il
                    // modo migliore per farla annullare per riflesso.
                    if (finestra.quanteConPassword > 0)
                        frase += " Per " + finestra.quanteConPassword
                               + (finestra.quanteConPassword === 1
                                  ? " di queste" : " di queste")
                               + " ti chiederà la password di amministratore.";
                    return frase;
                }
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            Pulsante {
                anchors.verticalCenter: parent.verticalCenter
                testo: "Lascia stare"
                onScelto: finestra.chiedoConferma = false
            }

            Pulsante {
                anchors.verticalCenter: parent.verticalCenter
                primario: true
                testo: "Sì, togli"
                onScelto: finestra.pulisci()
            }
        }
    }

    component Scheda: Rectangle {
        id: scheda
        property string quale: ""
        property string testo: ""

        readonly property bool suo: finestra.pagina === scheda.quale

        implicitWidth: nome.implicitWidth + Theme.Effects.space4 * 2
        implicitHeight: 32
        radius: Theme.Effects.radiusFull
        color: scheda.suo ? Theme.Colors.selected
                          : (area.containsMouse ? Theme.Colors.hover
                                                : "transparent")

        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

        Text {
            id: nome
            anchors.centerIn: parent
            text: scheda.testo
            color: scheda.suo ? Theme.Colors.accent : Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            font.weight: scheda.suo ? Theme.Typography.weightSemiBold
                                    : Theme.Typography.weightMedium
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: finestra.pagina = scheda.quale
        }
    }

    // ── Un pulsante, e basta ─────────────────────────────────────────────
    //
    // Lo stesso di `permessi.qml`, e per la stessa ragione: `ui/SpineButton`
    // è il pulsante della barra — sobrio apposta — e qui serve una cosa che
    // si veda. Giacomo, guardando la prima versione: «vedo adesso il grafico
    // e poi no vedo dove cliccare per procedere».
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

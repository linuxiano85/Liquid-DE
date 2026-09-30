import QtQuick
import Quickshell

import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Minerva Fucina — kernel su misura per questo computer.
//
// ── Da dove nasce ──────────────────────────────────────────────────────────
//
// Giacomo, 30 settembre 2026: una utility «per creare kernel ultra snelli e
// ottimizzati per il computer, con i moduli necessari per leggere tutto
// l'hardware», che tolga quello che non si usa «in modo per avere un kernel
// più snello possibile e quindi meno attaccabile», e che non faccia perdere
// un'ora per ogni prova.
//
// ── Le quattro pagine, nell'ordine in cui si usano ───────────────────────
//
//   · **Macchina** — che cosa c'è: processore, disco d'avvio, attrezzi per
//     compilare, dispositivi rimasti senza driver. Solo lettura.
//   · **Moduli** — che cosa resta nel kernel, famiglia per famiglia, con il
//     perché di ognuno; le scorte (quello che si tiene anche se oggi non è
//     collegato) e i preset.
//   · **Compila** — sorgente, versione, compilatore, nome; il piano, passo
//     per passo, PRIMA di premere; e il diario mentre compila.
//   · **Kernel** — quelli pronti e quelli installati; installare, togliere,
//     e la verifica al primo avvio.
//
// ── Le regole di Manutenzione, che valgono anche qui ─────────────────────
//
//   1. **Niente si tocca senza averlo mostrato prima.** Il piano con i
//      comandi si vede mentre si sceglie; «Compila» chiede conferma;
//      «Installa» e «Togli» chiedono conferma e poi la password.
//   2. **La finestra manda scelte, mai comandi.** Il demone ricalcola la
//      ricetta da sé: da qui non può partire un comando che non sia suo.
//   3. **Si dice quello che non si sa.** La prima compilazione non ha un
//      fondo scala, e la barra non se lo inventa.
//   4. **Il kernel della distribuzione non si raggiunge.** Non compare, non
//      si sovrascrive, non si toglie: è quello che ti riporta a casa.
FloatingWindow {
    id: finestra

    visible: Core.Ipc.prontoADipingere && !finestra.dormiente
    property bool dormiente: false

    title: "Minerva · Fucina"
    implicitWidth: 1180
    implicitHeight: 800
    minimumSize: Qt.size(920, 620)
    color: Theme.Colors.window

    signal requestClose()
    onClosed: finestra.requestClose()

    // ── Il pennello che cancella le scie ─────────────────────────────────
    //
    // Lo stesso di Manutenzione, per la stessa ragione (vedi il commento
    // lungo in `manutenzione/Manutenzione.qml`): col renderer software, dove
    // qualcosa scorre possono restare pixel vecchi che nessuno ridipinge.
    // Venti scatti in cui il fondo cambia di un livello su 255 costringono Qt
    // a ridisegnare tutta la finestra.
    property bool _altraTinta: false

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

    Rectangle {
        anchors.fill: parent
        z: -1
        color: finestra._altraTinta ? Qt.rgba(0, 0, 0, 1 / 255)
                                    : Qt.rgba(0, 0, 0, 2 / 255)
    }

    onPaginaChanged: Qt.callLater(finestra.ridipingiTutto)

    // ── I dati dal demone ────────────────────────────────────────────────

    property var rilievo: null
    property bool guardando: false
    property var versioni: []
    property string versioniErrore: ""
    property var ricetta: null
    property string ricettaErrore: ""
    property var kernel: []
    property string inUso: ""
    property var verifica: null

    /// `macchina`, `moduli`, `compila`, `kernel`.
    property string pagina: "macchina"

    // ── L'officina ───────────────────────────────────────────────────────

    property bool compilando: false
    /// Lo stato di ogni passo per id: `via`, `fatto`, `saltato`, `fallito`.
    property var passi: ({})
    property string passoAttuale: ""
    property var esito: null
    property int secondi: 0
    property int fatti: 0
    property int attesi: 0
    property string fase: ""
    property bool chiedoConferma: false

    Timer {
        interval: 1000
        repeat: true
        running: finestra.compilando
        onTriggered: finestra.secondi++
    }

    // ── Le scelte ────────────────────────────────────────────────────────
    //
    // Mappe e non elenchi, e ogni cambiamento fa una mappa NUOVA: in QML una
    // `property var` riassegnata allo stesso oggetto non sveglia nessun
    // legame (la trappola di Manutenzione del 9 settembre, «non riesco a
    // selezionare una singola voce»).

    property var tolti: ({})
    property var aggiunti: ({})
    property var scorte: ({})
    property var preset: ({})
    property string sorgente: "vanilla"
    property string versione: ""
    property string base: "in-uso"
    property string compilatore: "gcc"
    property bool lto: false
    property bool provaVeloce: false
    property bool nativo: false
    property string nome: "prova"

    /// La versione l'ha scelta chi guarda: allora l'elenco che arriva dopo
    /// non gliela cambia sotto il naso.
    property bool versioneScelta: false

    readonly property bool nomeBuono: /^[a-z0-9]([a-z0-9-]{0,22}[a-z0-9])?$/.test(finestra.nome)
    readonly property bool versioneBuona: /^[1-9][0-9]?\.[0-9]{1,3}(\.[0-9]{1,4})?$/.test(finestra.versione)
    readonly property string rilascio: finestra.versione + "-fucina-" + finestra.nome

    function _copia(m) {
        var fuori = ({});
        for (var k in m) fuori[k] = m[k];
        return fuori;
    }

    function _chiavi(m) {
        var fuori = [];
        for (var k in m) if (m[k] === true) fuori.push(k);
        fuori.sort();
        return fuori;
    }

    function scelte() {
        return {
            "tolti": finestra._chiavi(finestra.tolti),
            "aggiunti": finestra._chiavi(finestra.aggiunti),
            "scorte": finestra._chiavi(finestra.scorte),
            "preset": finestra._chiavi(finestra.preset),
            "sorgente": finestra.sorgente,
            "versione": finestra.versione,
            "base": finestra.base,
            "compilatore": finestra.compilatore,
            "lto": finestra.lto && finestra.compilatore === "clang",
            "provaVeloce": finestra.provaVeloce,
            "nativo": finestra.nativo,
            "nome": finestra.nome
        };
    }

    /// Un modulo del rilievo si tiene o no. Quello di serie si toglie; un
    /// candidato si aggiunge. Gli essenziali non arrivano qui: la casella è
    /// bloccata.
    function commutaModulo(m) {
        if (!m || m.essenziale === true) return;
        if (m.diSerie === true) {
            var t = finestra._copia(finestra.tolti);
            t[m.nome] = t[m.nome] !== true;
            finestra.tolti = t;
        } else {
            var a = finestra._copia(finestra.aggiunti);
            a[m.nome] = a[m.nome] !== true;
            finestra.aggiunti = a;
        }
    }

    /// Tutti i moduli di una famiglia insieme: se ce n'è anche uno tenuto si
    /// tolgono tutti (tranne gli essenziali), altrimenti si tengono tutti.
    function commutaFamiglia(moduli) {
        var qualcuno = false;
        for (var i = 0; i < moduli.length; i++)
            if (finestra.tenuto(moduli[i]) && moduli[i].essenziale !== true)
                qualcuno = true;
        var t = finestra._copia(finestra.tolti);
        var a = finestra._copia(finestra.aggiunti);
        for (var j = 0; j < moduli.length; j++) {
            var m = moduli[j];
            if (m.essenziale === true) continue;
            if (m.diSerie === true) t[m.nome] = qualcuno;
            else a[m.nome] = !qualcuno;
        }
        finestra.tolti = t;
        finestra.aggiunti = a;
    }

    function commutaMappa(quale, chiave) {
        var m = finestra._copia(finestra[quale]);
        m[chiave] = m[chiave] !== true;
        finestra[quale] = m;
    }

    /// I moduli che la ricetta tiene, per nome. Finché la ricetta non è
    /// arrivata si usa la regola di serie, che è la stessa del demone.
    readonly property var tenuti: {
        var fuori = ({});
        if (!finestra.ricetta || !finestra.ricetta.moduli) return fuori;
        var l = finestra.ricetta.moduli;
        for (var i = 0; i < l.length; i++) fuori[l[i]] = true;
        return fuori;
    }

    /// Vero dal clic fino all'arrivo del piano ricalcolato. In quel mezzo
    /// secondo la spunta segue la regola semplice — quella del demone, meno i
    /// preset — invece di restare ferma sul piano vecchio: una casella che non
    /// si spunta quando la si clicca sembra rotta.
    property bool pianoVecchio: false

    function tenuto(m) {
        if (finestra.ricetta && finestra.ricetta.moduli && !finestra.pianoVecchio)
            return finestra.tenuti[m.nome] === true;
        if (m.essenziale === true) return true;
        if (finestra.tolti[m.nome] === true) return false;
        if (m.diSerie === true) return true;
        return finestra.aggiunti[m.nome] === true;
    }

    // ── Ricalcolare il piano mentre si sceglie ───────────────────────────
    //
    // Un attimo dopo l'ultimo clic, non a ogni clic: dieci spunte di fila
    // sono una richiesta, non dieci.

    Timer {
        id: ricalcolo
        interval: 350
        onTriggered: finestra._calcolaOra()
    }

    function ricalcola() {
        finestra.pianoVecchio = true;
        ricalcolo.restart();
    }

    function _calcolaOra() {
        if (!finestra.rilievo) return;
        if (!finestra.versioneBuona) {
            finestra.ricettaErrore = "Scegli una versione del kernel.";
            return;
        }
        if (!finestra.nomeBuono) {
            finestra.ricettaErrore = "Il nome può avere lettere minuscole, cifre e "
                                     + "trattini (da 1 a 24), senza trattini ai lati.";
            return;
        }
        Core.Ipc.fucinaCalcola(finestra.scelte());
    }

    onToltiChanged: finestra.ricalcola()
    onAggiuntiChanged: finestra.ricalcola()
    onScorteChanged: finestra.ricalcola()
    onPresetChanged: finestra.ricalcola()
    onSorgenteChanged: finestra.ricalcola()
    onVersioneChanged: finestra.ricalcola()
    onBaseChanged: finestra.ricalcola()
    onCompilatoreChanged: {
        if (finestra.compilatore !== "clang") finestra.lto = false;
        finestra.ricalcola();
    }
    onLtoChanged: finestra.ricalcola()
    onProvaVeloceChanged: finestra.ricalcola()
    onNativoChanged: finestra.ricalcola()
    onNomeChanged: finestra.ricalcola()

    // ── Le azioni ────────────────────────────────────────────────────────

    function rileggi() {
        if (finestra.guardando) return;
        finestra.guardando = true;
        Core.Ipc.fucinaRileva();
    }

    function compila() {
        finestra.chiedoConferma = false;
        if (finestra.compilando || !finestra.ricetta) return;
        finestra.passi = ({});
        finestra.esito = null;
        finestra.secondi = 0;
        finestra.fatti = 0;
        finestra.attesi = 0;
        finestra.fase = "";
        paginaCompila.diario.pulisci();
        paginaCompila.diario.scrivi("Comincio: " + finestra.rilascio + ".");
        finestra.pagina = "compila";
        Core.Ipc.fucinaAvvia(finestra.scelte());
    }

    function ferma() {
        paginaCompila.diario.scrivi("Fermo la compilazione.");
        Core.Ipc.fucinaFerma();
    }

    /// Il testo sopra la barra: il passo, il conto, il tempo.
    function _statoDiario() {
        if (!finestra.compilando) return "";
        var t = Math.floor(finestra.secondi / 60) + ":"
                + ("0" + (finestra.secondi % 60)).slice(-2);
        var conto = "";
        if (finestra.fase === "compila" && finestra.fatti > 0)
            conto = finestra.attesi > 0
                    ? finestra.fatti + " di circa " + finestra.attesi + " file"
                    : finestra.fatti + " file";
        else if (finestra.fase === "scarica" && finestra.attesi > 0)
            conto = Math.round(finestra.fatti / 1048576) + " di "
                    + Math.round(finestra.attesi / 1048576) + " MB";
        return [finestra.passoAttuale, conto, t].filter(function (x) { return x !== ""; })
                                                  .join(" · ");
    }

    // ── Il collegamento col demone ───────────────────────────────────────

    Connections {
        target: Core.Ipc

        function onFucinaGuardo(p) {
            if (p) paginaMacchina.racconto = String(p.testo || "");
        }

        function onFucinaRilievo(r) {
            finestra.guardando = false;
            if (!r) return;
            finestra.rilievo = r;
            paginaMacchina.racconto = "";
            // Le scorte di serie, solo la prima volta: rileggendo non si butta
            // via quello che si era appena scelto a mano.
            if (finestra._primaVolta) {
                finestra._primaVolta = false;
                var s = ({});
                var l = r.scorte || [];
                for (var i = 0; i < l.length; i++)
                    if (l[i].predefinita === true) s[l[i].id] = true;
                finestra.scorte = s;
                if (finestra.versione === "") finestra.versione = finestra._versioneInUso();
            }
            finestra.ricalcola();
        }

        function onFucinaVersioni(v) {
            if (!v) return;
            finestra.versioni = v.versioni || [];
            finestra.versioniErrore = v.ok === true ? "" : String(v.errore || "");
            // L'ultima stabile, se chi guarda non ne ha scelta una sua.
            if (!finestra.versioneScelta && finestra.versioni.length > 0) {
                for (var i = 0; i < finestra.versioni.length; i++) {
                    var x = finestra.versioni[i];
                    if (x.tipo === "stable" && x.finita !== true) {
                        finestra.versione = x.versione;
                        break;
                    }
                }
            }
        }

        function onFucinaRicetta(r) {
            if (!r) return;
            if (r.ok !== true) {
                finestra.ricettaErrore = String(r.errore || "Non riesco a fare il piano.");
                return;
            }
            finestra.ricettaErrore = "";
            finestra.ricetta = r;
            finestra.pianoVecchio = false;
        }

        function onFucinaAvviata(r) {
            if (!r) return;
            if (r.ok !== true) {
                paginaCompila.diario.scrivi("Non parte: " + (r.errore || "non so perché"));
                return;
            }
            finestra.compilando = true;
        }

        function onFucinaPasso(p) {
            if (!p) return;
            var m = finestra._copia(finestra.passi);
            m[p.id] = p.stato;
            finestra.passi = m;
            if (p.stato === "via") {
                finestra.passoAttuale = String(p.titolo || "");
                finestra.fase = p.id === "scarica" ? "scarica"
                              : p.id === "compila" ? "compila" : "";
                finestra.fatti = 0;
            } else if (p.stato === "fallito") {
                paginaCompila.diario.scrivi("⚠ Non riuscito: " + (p.titolo || p.id));
            }
        }

        function onFucinaRighe(p) {
            if (p && p.righe) paginaCompila.diario.scriviMolte(p.righe);
        }

        function onFucinaAvanzamento(p) {
            if (!p) return;
            finestra.fase = String(p.fase || "");
            finestra.fatti = Number(p.fatti) || 0;
            finestra.attesi = Number(p.attesi) || 0;
        }

        function onFucinaFatto(e) {
            if (!e) return;
            finestra.compilando = false;
            finestra.esito = e;
            finestra.passoAttuale = "";
            finestra.fase = "";
            var min = Math.round((Number(e.secondi) || 0) / 60);
            if (e.ok === true)
                paginaCompila.diario.scrivi("Fatto in " + (min < 1 ? "meno di un minuto"
                                            : min + " minuti") + ": " + e.rilascio
                                            + " è pronto da installare.");
            else if (e.annullato === true)
                paginaCompila.diario.scrivi("Fermata. L'albero resta: la prossima volta "
                                            + "si riparte da dove si era arrivati.");
            else
                paginaCompila.diario.scrivi("⚠ " + (e.errore || "Non è andata."));
            Core.Ipc.fucinaChiediKernel();
        }

        function onFucinaFermata(e) {
            if (e && e.eraInCorso !== true)
                paginaCompila.diario.scrivi("Non c'era niente da fermare.");
        }

        // La finestra che si riapre a compilazione in corso: si riprende il
        // racconto da dove è arrivato.
        function onFucinaStato(s) {
            if (!s) return;
            if (s.inCorso === true) {
                finestra.compilando = true;
                finestra.secondi = Number(s.secondi) || 0;
                finestra.passoAttuale = String(s.passo || "");
                paginaCompila.diario.pulisci();
                paginaCompila.diario.scriviMolte(s.righe || []);
                finestra.pagina = "compila";
            } else if (s.esito) {
                finestra.esito = s.esito;
            }
        }

        function onFucinaKernel(k) {
            if (!k) return;
            finestra.kernel = k.kernel || [];
            finestra.inUso = String(k.inUso || "");
        }

        function onFucinaVerifica(v) {
            if (v) finestra.verifica = v;
        }

        function onAzioneFallita(azione, perche) {
            if (String(azione).indexOf("fucina_") !== 0) return;
            if (azione === "fucina_rileva") finestra.guardando = false;
            paginaCompila.diario.scrivi("⚠ Il demone non ce l'ha fatta (" + azione + "): "
                                        + (perche || "non so perché"));
        }
    }

    property bool _primaVolta: true

    /// `6.17.2-arch1-1` → `6.17.2`: la versione del kernel che gira adesso,
    /// da proporre se kernel.org non risponde.
    function _versioneInUso() {
        var r = finestra.rilievo ? String(finestra.rilievo.rilascio || "") : "";
        var m = r.match(/^([1-9][0-9]?\.[0-9]{1,3}(\.[0-9]{1,4})?)/);
        return m ? m[1] : "";
    }

    Component.onCompleted: {
        finestra.rileggi();
        Core.Ipc.fucinaChiediVersioni();
        Core.Ipc.fucinaChiediStato();
        Core.Ipc.fucinaChiediKernel();
    }

    // ── La barra del titolo ──────────────────────────────────────────────

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
                text: "Fucina"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXL
                font.weight: Theme.Typography.weightSemiBold
            }

            Text {
                text: "Un kernel su misura per questo computer"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: Theme.Effects.space1

            Scheda { quale: "macchina"; testo: "Macchina"; sua: finestra.pagina === "macchina"; onScelta: finestra.pagina = "macchina" }
            Scheda { quale: "moduli"; testo: "Moduli"; sua: finestra.pagina === "moduli"; onScelta: finestra.pagina = "moduli" }
            Scheda { quale: "compila"; testo: "Compila"; sua: finestra.pagina === "compila"; onScelta: finestra.pagina = "compila" }
            Scheda { quale: "kernel"; testo: "Kernel"; sua: finestra.pagina === "kernel"; onScelta: finestra.pagina = "kernel" }
        }

        Pulsante {
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space5
            anchors.verticalCenter: parent.verticalCenter
            attivo: !finestra.guardando && !finestra.compilando
            testo: finestra.guardando ? "Sto guardando…" : "Rileggi"
            onScelto: finestra.rileggi()
        }
    }

    // ── Le pagine ────────────────────────────────────────────────────────

    Item {
        id: corpo
        anchors.top: testata.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: fondo.top

        PaginaMacchina {
            id: paginaMacchina
            anchors.fill: parent
            visible: finestra.pagina === "macchina"
            f: finestra
        }

        PaginaModuli {
            id: paginaModuli
            anchors.fill: parent
            visible: finestra.pagina === "moduli"
            f: finestra
        }

        PaginaCompila {
            id: paginaCompila
            anchors.fill: parent
            visible: finestra.pagina === "compila"
            f: finestra
        }

        PaginaKernel {
            id: paginaKernel
            anchors.fill: parent
            visible: finestra.pagina === "kernel"
            f: finestra
        }
    }

    // ── Il fondo: quanto resta, come si chiamerà, e il pulsante ──────────
    //
    // Uguale in tutte le pagine: si sceglie nei Moduli e si compila senza
    // cambiare pagina, e il numero dei moduli tenuti resta sotto gli occhi
    // mentre si tolgono.

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
            visible: !finestra.chiedoConferma

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: finestra.ricetta ? String(finestra.ricetta.quanti) : "—"
                color: Theme.Colors.accent
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeLG
                font.weight: Theme.Typography.weightBold
                font.features: ({ "tnum": 1 })
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    var tot = finestra.rilievo && finestra.rilievo.moduli
                              ? finestra.rilievo.moduli.length : 0;
                    return "moduli tenuti" + (tot > 0 ? " (il rilievo ne ha visti " + tot + ")" : "")
                           + " · " + finestra.rilascio;
                }
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: finestra.ricettaErrore !== ""
                text: "· " + finestra.ricettaErrore
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

            Pulsante {
                visible: finestra.compilando
                testo: "Ferma"
                onScelto: finestra.ferma()
            }

            Pulsante {
                primario: true
                attivo: !finestra.compilando && finestra.ricetta !== null
                        && finestra.ricettaErrore === ""
                testo: finestra.compilando ? "Sto compilando…" : "Compila"
                onScelto: finestra.chiedoConferma = true
            }
        }

        // ── La conferma ──────────────────────────────────────────────────
        //
        // Dice che cosa succederà e che cosa NON succederà: compilare non
        // tocca il sistema. Installare è un'altra cosa, e chiede la password.
        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space5
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space5
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.Effects.space3
            visible: finestra.chiedoConferma

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: fondo.width - 380
                wrapMode: Text.WordWrap
                text: "Compilo " + finestra.rilascio + " con "
                      + (finestra.ricetta ? finestra.ricetta.quanti : "?") + " moduli. "
                      + "Si lavora nella tua cartella di cache: il sistema non cambia "
                      + "finché non installi."
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
                testo: "Sì, compila"
                onScelto: finestra.compila()
            }
        }
    }

    // ── Le schede in cima ────────────────────────────────────────────────
    //
    // Chi è la scheda attiva e che cosa fare al clic arrivano da fuori, e non
    // da `finestra` letto qui dentro: un componente in linea non condivide
    // gli id del file che lo contiene, e un difetto che dipende da quanto una
    // versione di Qt è indulgente è un difetto che aspetta la sua versione.
    component Scheda: Rectangle {
        id: scheda
        property string quale: ""
        property string testo: ""
        property bool sua: false
        signal scelta()

        implicitWidth: nomeScheda.implicitWidth + Theme.Effects.space4 * 2
        implicitHeight: 32
        radius: Theme.Effects.radiusFull
        color: scheda.sua ? Theme.Colors.selected
                          : (dito.containsMouse ? Theme.Colors.hover : "transparent")

        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

        Text {
            id: nomeScheda
            anchors.centerIn: parent
            text: scheda.testo
            color: scheda.sua ? Theme.Colors.accent : Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            font.weight: scheda.sua ? Theme.Typography.weightSemiBold
                                    : Theme.Typography.weightMedium
        }

        MouseArea {
            id: dito
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: scheda.scelta()
        }
    }
}

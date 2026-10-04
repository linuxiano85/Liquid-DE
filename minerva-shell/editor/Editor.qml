import QtQuick
import Quickshell
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Editor — Un posto dove scrivere e leggere testo.
//
// Tre cose fatte bene: aprire, scrivere, salvare. Il resto — schede per più
// documenti, trova e sostituisci... no: trova, senza sostituire; l'involucro
// del testo va a capo o no; il punto sporco nel titolo che dice quando
// manca un salvataggio. Niente che un editor non debba avere, niente che un
// editor non debba avere.
//
// La scrittura passa dal demone, che salva su un file temporaneo e poi lo
// sposta sopra il vero: un salvataggio interrotto a metà non tronca il
// documento. È la stessa scelta del gestore file, per la stessa ragione.
FloatingWindow {
    id: editor

    visible: Core.Ipc.prontoADipingere && !editor.dormiente

    // ── Accesa e nascosta ────────────────────────────────────────────────
    //
    // Vera quando il programma c'è ma non si deve vedere: è così che una app
    // «tenuta pronta» aspetta di essere richiamata senza pagare i 539 ms di
    // ricostruzione. La decisione sta tutta in `core/TenutaPronta.qml`, qui
    // c'è solo l'interruttore della luce.
    property bool dormiente: false

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
    implicitWidth: 860
    implicitHeight: 600

    signal requestClose()
    // La × della barra disegnata dal compositore chiude la finestra da fuori,
    // e Quickshell non lascia trattenerla: c'è solo `closed`, a cose fatte.
    // Con qualcosa di non salvato la finestra si rimostra subito, con la
    // domanda; senza, si chiude come prima.
    onClosed: {
        if (editor.qualcosaDaSalvare()) {
            editor.visible = true;
            editor.daChiudere = -1;
            return;
        }
        editor.requestClose();
    }

    /// Il documento su cui aprirsi, dall'ambiente.
    property string initialFile: ""

    /// I caratteri installati, dal demone. Il menù li mostra.
    property var caratteri: []

    Connections {
        target: Core.Ipc
        function onFontsReceived(payload) {
            editor.caratteri = (payload && payload.fonts) ? payload.fonts : [];
        }
    }



    /// Quanti documenti si possono tenere aperti. È un editor, non un
    /// contenitore di documenti: oltre le otto schede non si leggono più i
    /// nomi.
    readonly property int maxTabs: 8

    readonly property bool it: Core.Strings.lang === "it"

    // ── I documenti ──────────────────────────────────────────────────────

    property ListModel docs: ListModel {}

    property int currentIndex: 0

    /// Vero mentre il testo viene cambiato DAL PROGRAMMA (un documento
    /// caricato): il punto sporco non si accende per colpa nostra.
    property bool inCaricamento: false

    /// Il testo e lo stato del documento ATTIVO, tenuti qui e non letti
    /// da `docs.get()`: gli oggetti di `ListModel.get()` sono fotografie, e
    /// una proprietà che li legge non si accorge quando il modello cambia
    /// — il testo restava quello del primo istante, per sempre.
    property string testoAttivo: ""
    property string percorsoAttivo: ""
    property bool sporcoAttivo: false

    onCurrentIndexChanged: editor.riprendiStato()

    function riprendiStato() {
        var d = editor.docs.get(editor.currentIndex);
        if (!d) {
            editor.testoAttivo = "";
            editor.percorsoAttivo = "";
            editor.sporcoAttivo = false;
            return;
        }
        editor.testoAttivo = d.text || "";
        editor.percorsoAttivo = d.path || "";
        editor.sporcoAttivo = d.dirty === true;
    }

    function ricordaTesto(testoNuovo) {
        editor.docs.setProperty(editor.currentIndex, "text", testoNuovo);
    }

    function segnaSporco(si) {
        editor.docs.setProperty(editor.currentIndex, "dirty", si === true);
        editor.sporcoAttivo = si === true;
    }

    // ── `title:` e NON `property string title:` ──────────────────────────
    //
    // `FloatingWindow` un `title` ce l'ha già. Dichiararne un altro qui non
    // dà errore: QML crea una proprietà NUOVA che copre quella della finestra,
    // e la finestra vera resta col suo titolo di fabbrica — «quickshell».
    //
    // Si vedeva: la barra del titolo dell'editor diceva «quickshell» invece
    // del nome del file, e le altre tre app ospitate no, perché loro
    // assegnano. È lo stesso inganno di `finestra: finestra`, che si legava a
    // sé stessa: in QML una proprietà che esiste già si ASSEGNA, non si
    // ridichiara.
    title: {
        var nome = editor.percorsoAttivo === ""
                   ? (editor.it ? "Senza nome" : "Untitled")
                   : editor.nomeFile(editor.percorsoAttivo);
        return "Minerva · " + nome
               + (editor.sporcoAttivo ? " ●" : "");
    }

    function nomeFile(path) {
        var p = String(path || "");
        var cut = p.lastIndexOf("/");
        return cut < 0 ? p : p.substring(cut + 1);
    }

    function isDirty() {
        return editor.sporcoAttivo;
    }

    /// Una scheda nuova, col suo documento vuoto o col file chiesto.
    function addTab(path) {
        if (editor.docs.count >= editor.maxTabs)
            return;
        editor.docs.append({ "path": path || "", "text": "", "dirty": false });
        editor.currentIndex = editor.docs.count - 1;
        if (path)
            editor.apri(path);
    }

    // ── Chiudere senza perdere niente ────────────────────────────────────
    //
    // `isDirty()` c'era e non la chiamava nessuno: Ctrl+W, la × di una scheda
    // e la × della finestra buttavano le modifiche senza una parola (segnalato
    // dal PC di prova, J1). Adesso, se c'è qualcosa di non salvato, si chiede.
    /// Cosa si sta per chiudere: -2 niente, -1 la finestra, ≥0 una scheda.
    property int daChiudere: -2

    function closeTab(index, forza) {
        if (editor.docs.count <= 1 || index < 0 || index >= editor.docs.count)
            return;
        if (forza !== true && editor.docs.get(index).dirty === true) {
            editor.daChiudere = index;
            return;
        }
        editor.docs.remove(index);
        // L'indice resta lo stesso NUMERO ma ora indica un altro documento:
        // senza questo, togliendo una scheda prima di quella attiva, il testo
        // mostrato restava quello vecchio.
        if (index < editor.currentIndex)
            editor.currentIndex--;
        if (editor.currentIndex >= editor.docs.count)
            editor.currentIndex = editor.docs.count - 1;
        editor.riprendiStato();
    }

    function qualcosaDaSalvare() {
        for (var i = 0; i < editor.docs.count; i++)
            if (editor.docs.get(i).dirty === true)
                return true;
        return false;
    }

    function chiudiFinestra(forza) {
        if (forza !== true && editor.qualcosaDaSalvare()) {
            editor.daChiudere = -1;
            return;
        }
        editor.daChiudere = -2;
        editor.requestClose();
    }

    function confermaChiusura() {
        var quale = editor.daChiudere;
        editor.daChiudere = -2;
        if (quale === -1)
            editor.chiudiFinestra(true);
        else if (quale >= 0)
            editor.closeTab(quale, true);
    }

    function segnaDirty(si) {
        editor.segnaSporco(si);
    }

    function apri(path) {
        if (!path)
            return;
        Core.Ipc.fsRead(path);
    }

    /// Salva. Senza percorso, prima si chiede dove.
    function salva() {
        if (editor.percorsoAttivo === "") {
            editor.chiediPercorso("salva");
            return;
        }
        editor.scrivi(editor.percorsoAttivo);
    }

    function scrivi(path) {
        editor.docs.setProperty(editor.currentIndex, "path", path);
        editor.percorsoAttivo = path;
        // ── Se il file è stato aperto da amministratore ──────────────────
        //
        // Si risalva per la stessa strada. Salvarlo per quella normale
        // fallirebbe con «permesso negato» DOPO aver scritto — cioè dopo che
        // chi scriveva credeva di aver finito.
        if (editor.daRoot.indexOf(path) >= 0) {
            Core.Ipc.radiceScrivi(path, editor.testoAttivo);
            return;
        }
        Core.Ipc.fsWrite(path, editor.testoAttivo);
    }

    // ── I file aperti da amministratore ──────────────────────────────────
    //
    // Giacomo, 23 agosto 2026: «inserendo la password posso aprire anche file
    // di configurazione come root con il lettore di testi».
    //
    // Si tiene l'elenco dei percorsi aperti così, per due motivi. Il primo è
    // il salvataggio qui sopra. Il secondo è che va DETTO a schermo: un file
    // di `/etc` aperto in una finestra identica a tutte le altre è un file che
    // si modifica senza ricordarsi che cos'è.
    property var daRoot: []

    /// Vero quando l'aiutante di root è installato.
    property bool radiceCE: false

    /// Vero quando il file che si sta guardando ha bisogno di root: o non si
    /// è riuscito a leggerlo, o è già stato aperto così.
    property bool serveRoot: false


    /// Riapre da amministratore il file che si sta guardando.
    ///
    /// Serve quando l'apertura normale è fallita per i permessi — che è
    /// esattamente quando compare la voce di menu.
    function apriDaRoot(path) {
        var p = path || editor.percorsoAttivo;
        if (!p || p === "")
            return;
        editor.attesaRoot = p;
        Core.Ipc.radiceLeggi(p);
    }

    /// Il file che si sta aspettando dall'aiutante. Uno per volta: la
    /// finestrella della password è modale, e chiederne due insieme
    /// vorrebbe dire due finestrelle sovrapposte.
    property string attesaRoot: ""

    /// Un file che non si è potuto leggere. Se l'aiutante c'è, invece di dire
    /// soltanto «permesso negato» si dice anche cosa si può fare — che è la
    /// differenza fra un messaggio d'errore e un aiuto.
    function nonSiLegge(path, errore) {
        var m = String(errore || (editor.it ? "Non si può leggere."
                                            : "Cannot read."));
        editor.serveRoot = editor.radiceCE;
        editor.problema(editor.serveRoot
            ? m + (editor.it
                   ? "  Prova «Apri come amministratore»."
                   : "  Try “Open as administrator”.")
            : m);
    }

    function segnaDaRoot(p) {
        editor.serveRoot = true;
        if (editor.daRoot.indexOf(p) >= 0)
            return;
        var e = editor.daRoot.slice();
        e.push(p);
        editor.daRoot = e;
    }

    function salvaCome() {
        editor.chiediPercorso("salva");
    }

    function nuovo() {
        if (editor.docs.count >= editor.maxTabs)
            return;
        editor.docs.append({ "path": "", "text": "", "dirty": false });
        editor.currentIndex = editor.docs.count - 1;
        testo.forceActiveFocus();
    }

    function apriConPercorso() {
        editor.chiediPercorso("apri");
    }

    // ── Le risposte del demone ───────────────────────────────────────────

    Connections {
        target: Core.Ipc
        function onFileTextReceived(payload) {
            if (!payload || payload.path === undefined)
                return;
            // Si cerca la scheda che stava aspettando questo documento.
            for (var i = 0; i < editor.docs.count; i++) {
                if (editor.docs.get(i).path === payload.path) {
                    if (payload.ok === true) {
                        editor.docs.setProperty(i, "text", payload.text || "");
                        editor.docs.setProperty(i, "dirty", false);
                        editor.currentIndex = i;
                        editor.riprendiStato();
                    } else {
                        editor.currentIndex = i;
                        editor.nonSiLegge(payload.path, payload.error);
                    }
                    return;
                }
            }
            // Nessuna scheda: era un'apertura diretta.
            if (payload.ok === true) {
                editor.docs.append({ "path": payload.path,
                                     "text": payload.text || "",
                                     "dirty": false });
                editor.currentIndex = editor.docs.count - 1;
                editor.riprendiStato();
            } else {
                editor.nonSiLegge(payload.path, payload.error);
            }
        }
        function onRadiceStato(info) {
            editor.radiceCE = info && info.disponibile === true;
        }

        function onRadiceTesto(info) {
            if (!info || String(info.path || "") !== editor.attesaRoot)
                return;
            var p = editor.attesaRoot;
            editor.attesaRoot = "";
            if (info.ok !== true) {
                editor.problema(String(info.error
                    || (editor.it ? "Non si può leggere." : "Cannot read.")));
                return;
            }
            editor.segnaDaRoot(p);
            for (var i = 0; i < editor.docs.count; i++) {
                if (editor.docs.get(i).path === p) {
                    editor.docs.setProperty(i, "text", info.text || "");
                    editor.docs.setProperty(i, "dirty", false);
                    editor.currentIndex = i;
                    editor.riprendiStato();
                    return;
                }
            }
            editor.docs.append({ "path": p, "text": info.text || "",
                                 "dirty": false });
            editor.currentIndex = editor.docs.count - 1;
            editor.riprendiStato();
        }

        function onRadiceEsito(info) {
            // La risposta a un salvataggio fatto da amministratore.
            if (!info || String(info.path || "") !== editor.percorsoAttivo)
                return;
            if (info.ok === true)
                editor.segnaDirty(false);
            else if (info.annullato !== true)
                editor.problema(String(info.error
                    || (editor.it ? "Non salvato." : "Not saved.")));
        }

        function onFileResultReceived(result) {
            // La risposta a un salvataggio: il punto sporco si spegne solo
            // se è andata davvero bene.
            if (result && result.ok === true
                && result.path === editor.percorsoAttivo)
                editor.segnaDirty(false);
            else if (result && result.ok === false && result.error)
                editor.problema(result.error);
        }
    }

    // ── Il punto sporco va segnato a ogni battuta ────────────────────────

    /// Ricontare a ogni battuta costa una scansione della stringa, ed è meno
    /// di quanto costi mostrare numeri vecchi di un secondo: su un file di
    /// diecimila righe sono diecimila confronti di carattere, cioè niente
    /// rispetto al ridisegno che avviene comunque a ogni tasto.
    function suTestoCambiato(nuovo) {
        // Il testo attivo segue la tastiera: senza, «salva» scriverebbe
        // l'ultima versione caricata invece di quella che si sta guardando.
        editor.testoAttivo = nuovo;
        // DOPO, non prima: `contaRighe` legge `testoAttivo`, e contando prima
        // dell'assegnamento la colonna resterebbe indietro di una battuta —
        // cioè lo stesso difetto del timer, in versione più difficile da
        // vedere.
        editor.contaRighe();
        editor.ricordaTesto(nuovo);
        // Un documento appena caricato non è «sporco»: il cambiamento è
        // nostro, non di chi scrive.
        if (!editor.inCaricamento && editor.sporcoAttivo !== true)
            editor.segnaSporco(true);
    }

    // ── La richiesta di un percorso ──────────────────────────────────────

    property string richiestaPer: ""   // "apri", "salva" o "riga"

    function chiediPercorso(cosa) {
        editor.richiestaPer = cosa;
        richiestaPercorso.visible = true;
        richiestaInput.text = "";
        richiestaInput.forceActiveFocus();
    }

    function accettaPercorso() {
        var p = richiestaInput.text.trim();
        richiestaPercorso.visible = false;
        if (p === "")
            return;
        // Un nome senza percorso è relativo alla HOME: il demone non sa da
        // dove è stato lanciato l'editor, e scriverebbe accanto a sé.
        if (p.charAt(0) !== "/")
            p = Quickshell.env("HOME") + "/" + p;
        if (editor.richiestaPer === "apri") {
            editor.docs.setProperty(editor.currentIndex, "path", p);
            editor.percorsoAttivo = p;
            editor.apri(p);
        } else if (editor.richiestaPer === "riga") {
            editor.vaiAllaRiga(parseInt(p, 10));
        } else {
            editor.scrivi(p);
        }
    }

    // ── Vai alla riga ────────────────────────────────────────────────────

    function chiediRiga() {
        editor.richiestaPer = "riga";
        richiestaPercorso.visible = true;
        richiestaInput.text = "";
        richiestaInput.forceActiveFocus();
    }

    function vaiAllaRiga(n) {
        if (isNaN(n) || n < 1)
            return;
        var t = editor.testoAttivo;
        var riga = 1;
        var pos = 0;
        while (riga < n && pos < t.length) {
            if (t.charAt(pos) === "\n")
                riga++;
            pos++;
        }
        testo.cursorPosition = pos;
        testo.forceActiveFocus();
    }

    // ── La posizione del cursore ─────────────────────────────────────────

    property int rigaCursore: 1
    property int colonnaCursore: 1

    function aggiornaPosizione() {
        var t = editor.testoAttivo;
        var p = Math.min(testo.cursorPosition, t.length);
        var riga = 1;
        var inizio = 0;
        for (var i = 0; i < p; i++) {
            if (t.charAt(i) === "\n") {
                riga++;
                inizio = i + 1;
            }
        }
        editor.rigaCursore = riga;
        editor.colonnaCursore = p - inizio + 1;
    }

    // ── La striscia dei problemi ─────────────────────────────────────────

    property string guasto: ""

    function problema(testo) {
        editor.guasto = testo;
        problemaTimer.restart();
    }

    Timer {
        id: problemaTimer
        interval: 7000
        onTriggered: editor.guasto = ""
    }

    // ── Trova ────────────────────────────────────────────────────────────

    property bool cercando: false
    property string cercaTesto: ""

    function trova(avanti) {
        var testoDoc = editor.testoAttivo;
        var cerca = editor.cercaTesto;
        if (cerca === "" || testoDoc === "")
            return;
        var da = testo.cursorPosition;
        if (avanti) {
            var trovato = testoDoc.indexOf(cerca, da);
            if (trovato < 0)
                trovato = testoDoc.indexOf(cerca, 0);
            if (trovato >= 0) {
                testo.cursorPosition = trovato;
                testo.select(trovato, trovato + cerca.length);
            }
        } else {
            var indietro = testoDoc.lastIndexOf(cerca, Math.max(0, da - 1));
            if (indietro < 0)
                indietro = testoDoc.lastIndexOf(cerca);
            if (indietro >= 0) {
                testo.cursorPosition = indietro;
                testo.select(indietro, indietro + cerca.length);
            }
        }
    }

    function apriTrova() {
        editor.cercando = true;
        trovaInput.forceActiveFocus();
        if (editor.cercaTesto !== "")
            trovaInput.selectAll();
    }

    function chiudiTrova() {
        editor.cercando = false;
        editor.cercaTesto = "";
        testo.forceActiveFocus();
    }

    // ── Sostituisci ──────────────────────────────────────────────────────
    //
    // La sorella del trova: stessa barra, un campo in più e due azioni —
    // una per la prossima occorrenza, una per tutte. Senza sostituire,
    // «trova» è mezza funzione.

    property bool sostituendo: false
    property string sostituisciTesto: ""

    function apriSostituisci() {
        editor.sostituendo = true;
        editor.cercando = false;
        trovaInput.forceActiveFocus();
        if (editor.cercaTesto !== "")
            trovaInput.selectAll();
    }

    function chiudiSostituisci() {
        editor.sostituendo = false;
        editor.sostituisciTesto = "";
        testo.forceActiveFocus();
    }

    function sostituisciProssima() {
        var t = editor.testoAttivo;
        var cerca = editor.cercaTesto;
        if (cerca === "")
            return;
        var da = testo.selectionStart >= 0 ? testo.selectionStart : testo.cursorPosition;
        var trovato = t.indexOf(cerca, da);
        if (trovato < 0)
            trovato = t.indexOf(cerca, 0);
        if (trovato < 0)
            return;
        var nuovo = t.substring(0, trovato) + editor.sostituisciTesto
                    + t.substring(trovato + cerca.length);
        editor.inCaricamento = false;
        editor.testoAttivo = nuovo;
        editor.ricordaTesto(nuovo);
        editor.segnaSporco(true);
        testo.cursorPosition = trovato + editor.sostituisciTesto.length;
    }

    function sostituisciTutte() {
        var cerca = editor.cercaTesto;
        if (cerca === "")
            return;
        var t = editor.testoAttivo;
        var nuovo = t.split(cerca).join(editor.sostituisciTesto);
        if (nuovo === t)
            return;
        editor.testoAttivo = nuovo;
        editor.ricordaTesto(nuovo);
        editor.segnaSporco(true);
    }

    // ── Le righe e le colonne ────────────────────────────────────────────
    //
    // Contare le righe a ogni battuta su un documento lungo costa una
    // scansione: si conta solo per la barra di stato, una volta al secondo.

    property int righe: 1
    property string numeriRiga: "1"

    function contaRighe() {
        var t = editor.testoAttivo;
        var n = 1;
        for (var i = 0; i < t.length; i++)
            if (t.charAt(i) === "\n")
                n++;
        editor.righe = n;
        // I numeri per il bordo: uno per riga. Duemila righe sono poche
        // righe di stringa; diecimila ancora accettabili.
        var colonna = "";
        for (var r = 1; r <= n; r++)
            colonna += (r === 1 ? "" : "\n") + r;
        editor.numeriRiga = colonna;
    }

    Component.onCompleted: {
        Core.Ipc.fontsList();
        // Se l'aiutante di root non c'è, «Apri come amministratore» non
        // compare: un pulsante che non può funzionare è peggio di uno che
        // manca.
        Core.Ipc.radiceDisponibile();
        if (editor.initialFile !== "")
            editor.addTab(editor.initialFile);
        else
            editor.addTab("");
    }

    // ── La barra del titolo ──────────────────────────────────────────────

    Ui.WindowTitleBar {
        id: titolo
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        label: editor.title
        onCloseRequested: editor.chiudiFinestra(false)
    }

    // ── Le schede ────────────────────────────────────────────────────────

    Item {
        id: schede
        anchors.top: titolo.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: editor.docs.count > 1 ? 34 : 0
        clip: true

        Rectangle {
            anchors.fill: parent
            color: Theme.Colors.membrane
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.Colors.edge
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: Theme.Effects.space2
            spacing: 2

            Repeater {
                model: editor.docs

                delegate: Rectangle {
                    id: scheda
                    required property int index
                    required property string path
                    required property string text
                    required property bool dirty

                    height: 26
                    anchors.verticalCenter: parent.verticalCenter
                    width: schedaTesto.implicitWidth + Theme.Effects.space3 * 2 + (scheda.dirty ? 10 : 0)
                    radius: Theme.Effects.radiusXS
                    color: index === editor.currentIndex
                           ? Theme.Colors.raised : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Text {
                        id: schedaTesto
                        anchors.centerIn: parent
                        text: (scheda.path === "" ? (editor.it ? "Senza nome" : "Untitled")
                                                  : editor.nomeFile(scheda.path))
                              + (scheda.dirty ? " ●" : "")
                        color: index === editor.currentIndex ? Theme.Colors.text
                                                             : Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            editor.currentIndex = scheda.index;
                            testo.forceActiveFocus();
                        }
                    }
                }
            }
        }
    }

    // ── La barra dei comandi ─────────────────────────────────────────────

    Item {
        id: barra
        anchors.top: schede.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 42
        z: 1

        Rectangle {
            anchors.fill: parent
            color: Theme.Colors.membrane
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.Colors.edge
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.Effects.space1

            Repeater {
                // ── «Apri come amministratore» compare solo quando serve ──
                //
                // Cioè quando il file che si sta guardando non si è potuto
                // leggere, o si è potuto leggere ma non si potrà salvare.
                // Tenerlo sempre lì vorrebbe dire offrire i privilegi di root
                // come un pulsante fra gli altri, e la mano ci finisce sopra
                // per abitudine.
                model: {
                    var m = [
                        { "id": "nuovo", "icon": "document", "it": "Nuovo", "en": "New", "tasto": "Ctrl+N" },
                        { "id": "apri", "icon": "folder", "it": "Apri…", "en": "Open…", "tasto": "Ctrl+O" },
                        { "id": "salva", "icon": "check", "it": "Salva", "en": "Save", "tasto": "Ctrl+S" },
                        { "id": "salvaCome", "icon": "back", "it": "Salva con nome…", "en": "Save as…", "tasto": "Ctrl+Maiusc+S" },
                        { "id": "trova", "icon": "search", "it": "Trova", "en": "Find", "tasto": "Ctrl+F" }
                    ];
                    if (editor.radiceCE && editor.serveRoot)
                        m.push({ "id": "radice", "icon": "lock",
                                 "it": "Apri come amministratore",
                                 "en": "Open as administrator", "tasto": "" });
                    return m;
                }

                delegate: Rectangle {
                    id: comando
                    required property var modelData

                    width: comandoTesto.implicitWidth + Theme.Effects.space3 * 2
                    height: 28
                    radius: Theme.Effects.radiusXS
                    color: comandoMouse.containsMouse
                           ? Qt.alpha(Theme.Colors.accent, 0.16) : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.Effects.space2

                        Ui.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14; height: 14
                            name: comando.modelData.icon
                            color: comandoMouse.containsMouse ? Theme.Colors.accent
                                                              : Theme.Colors.textFaint
                        }

                        Text {
                            id: comandoTesto
                            anchors.verticalCenter: parent.verticalCenter
                            text: editor.it ? comando.modelData.it : comando.modelData.en
                            color: comandoMouse.containsMouse ? Theme.Colors.text
                                                              : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                    }

                    Ui.ToolTipHint {
                        text: comando.modelData.tasto
                        shown: comandoMouse.containsMouse
                    }

                    MouseArea {
                        id: comandoMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            switch (comando.modelData.id) {
                            case "nuovo": editor.nuovo(); break;
                            case "apri": editor.apriConPercorso(); break;
                            case "salva": editor.salva(); break;
                            case "salvaCome": editor.salvaCome(); break;
                            case "trova": editor.apriTrova(); break;
                            case "radice": editor.apriDaRoot(); break;
                            }
                        }
                    }
                }
            }
        }

        // La larghezza del testo e il modo di andare a capo.
        Row {
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.Effects.space1

            Rectangle {
                id: boldBtn
                height: 28
                width: 30
                radius: Theme.Effects.radiusXS
                color: editor.grassetto ? Qt.alpha(Theme.Colors.accent, 0.22)
                     : boldMouse.containsMouse ? Theme.Colors.hover : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "B"
                    color: editor.grassetto ? Theme.Colors.accent : Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    font.weight: Theme.Typography.weightSemiBold
                }
                Ui.ToolTipHint {
                    text: editor.it ? "Grassetto" : "Bold"
                    shown: boldMouse.containsMouse
                }
                MouseArea {
                    id: boldMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editor.commutaGrassetto()
                }
            }

            Rectangle {
                id: italicBtn
                height: 28
                width: 30
                radius: Theme.Effects.radiusXS
                color: editor.corsivo ? Qt.alpha(Theme.Colors.accent, 0.22)
                     : italicMouse.containsMouse ? Theme.Colors.hover : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "I"
                    color: editor.corsivo ? Theme.Colors.accent : Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    font.italic: true
                }
                Ui.ToolTipHint {
                    text: editor.it ? "Corsivo" : "Italic"
                    shown: italicMouse.containsMouse
                }
                MouseArea {
                    id: italicMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editor.commutaCorsivo()
                }
            }

            Rectangle {
                id: coloreBtn
                height: 28
                width: 34
                radius: Theme.Effects.radiusXS
                color: coloreMouse.containsMouse ? Theme.Colors.hover : "transparent"
                Rectangle {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    radius: 8
                    color: editor.tintaTesto
                    border.width: 1
                    border.color: Theme.Colors.edge
                }
                Ui.ToolTipHint {
                    text: editor.it ? "Colore del testo" : "Text colour"
                    shown: coloreMouse.containsMouse
                }
                MouseArea {
                    id: coloreMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tavolozzaTesto.visible = !tavolozzaTesto.visible
                }
            }

            Rectangle {
                id: fontBtn
                height: 28
                width: fontNome.implicitWidth + Theme.Effects.space3 * 2
                radius: Theme.Effects.radiusXS
                color: fontMouse.containsMouse ? Theme.Colors.hover : "transparent"
                Text {
                    id: fontNome
                    anchors.centerIn: parent
                    text: editor.carattere !== "" ? editor.carattere
                                                  : (editor.it ? "Monospazio" : "Monospace")
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    elide: Text.ElideRight
                    width: Math.min(140, implicitWidth)
                }
                Ui.ToolTipHint {
                    text: editor.it ? "Carattere" : "Font"
                    shown: fontMouse.containsMouse
                }
                MouseArea {
                    id: fontMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: menùCaratteri.visible = !menùCaratteri.visible
                }
            }

            Rectangle {
                id: fondoBtn
                height: 28
                width: 34
                radius: Theme.Effects.radiusXS
                color: fondoMouse.containsMouse ? Theme.Colors.hover : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: editor.it ? "Fondo" : "Bg"
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }
                Ui.ToolTipHint {
                    text: editor.fondoScuro ? (editor.it ? "Fondo scuro: passa al chiaro"
                                                         : "Dark background: switch to light")
                                            : (editor.it ? "Fondo chiaro: passa allo scuro"
                                                         : "Light background: switch to dark")
                    shown: fondoMouse.containsMouse
                }
                MouseArea {
                    id: fondoMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editor.commutaFondo()
                }
            }

            Rectangle {
                id: piega
                height: 28
                width: piegaTesto.implicitWidth + Theme.Effects.space3 * 2
                radius: Theme.Effects.radiusXS
                color: editor.piega ? Qt.alpha(Theme.Colors.accent, 0.18)
                     : piegaMouse.containsMouse ? Theme.Colors.hover : "transparent"

                Text {
                    id: piegaTesto
                    anchors.centerIn: parent
                    text: editor.it ? "A capo" : "Wrap"
                    color: editor.piega ? Theme.Colors.accent : Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                MouseArea {
                    id: piegaMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Si scrive nelle impostazioni e non nella proprietà:
                    // la proprietà ci è legata, e chi sceglie una volta lo
                    // ritrova alla finestra dopo.
                    onClicked: Core.Ipc.setSetting("editor.piega", !editor.piega)
                }
            }

            Rectangle {
                height: 28
                width: 30
                radius: Theme.Effects.radiusXS
                color: menoMouse.containsMouse ? Theme.Colors.hover : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "−"
                    color: Theme.Colors.textMuted
                    font.pixelSize: Theme.Typography.sizeMD
                }
                MouseArea {
                    id: menoMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editor.zoomTesto(-1)
                }
            }

            Rectangle {
                height: 28
                width: 30
                radius: Theme.Effects.radiusXS
                color: piuMouse.containsMouse ? Theme.Colors.hover : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: Theme.Colors.textMuted
                    font.pixelSize: Theme.Typography.sizeMD
                }
                MouseArea {
                    id: piuMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editor.zoomTesto(1)
                }
            }
        }
    }

    // ── La forma del testo ──────────────────────────────────────────────
    //
    // Tutto dalle impostazioni: chi sceglie un carattere o un colore li
    // ritrova alla prossima finestra, su qualunque documento. Il peso e il
    // corsivo sono del FOGLIO, non del documento: l'editor non salva la
    // formattazione dentro il file — per quello c'è un elaboratore di testi.

    /// L'a-capo automatico. Nasce SPENTO, e la ragione non è il gusto: i
    /// numeri di riga e l'a-capo non possono stare insieme.
    ///
    /// Con l'a-capo acceso una riga del documento ne occupa tre sullo schermo,
    /// e la colonna dei numeri — che di righe ne conta una per ritorno a capo
    /// — smette di corrispondere a qualunque cosa. È il motivo per cui Kate,
    /// VS Code e quasi ogni editor mai scritto nascono senza. Prima qui nasceva
    /// acceso, e quindi i numeri di riga c'erano e non si vedevano mai.
    property bool piega: Core.Ipc.get("editor.piega", false)

    property string carattere: Core.Ipc.get("editor.font", "")
    property int dimensioneTesto: Core.Ipc.get("editor.size", 14)
    property bool grassetto: Core.Ipc.get("editor.bold", false)
    property bool corsivo: Core.Ipc.get("editor.italic", false)
    property string coloreTesto: Core.Ipc.get("editor.colore", "")
    property bool fondoScuro: Core.Ipc.get("editor.fondoScuro", true)

    function zoomTesto(delta) {
        editor.dimensioneTesto = Math.max(10, Math.min(28,
            editor.dimensioneTesto + delta));
        Core.Ipc.setSetting("editor.size", editor.dimensioneTesto);
    }

    function impostaCarattere(famiglia) {
        editor.carattere = famiglia;
        Core.Ipc.setSetting("editor.font", famiglia);
    }

    function commutaGrassetto() {
        editor.grassetto = !editor.grassetto;
        Core.Ipc.setSetting("editor.bold", editor.grassetto);
    }

    function commutaCorsivo() {
        editor.corsivo = !editor.corsivo;
        Core.Ipc.setSetting("editor.italic", editor.corsivo);
    }

    function impostaColore(colore) {
        editor.coloreTesto = colore;
        Core.Ipc.setSetting("editor.colore", colore);
    }

    function commutaFondo() {
        editor.fondoScuro = !editor.fondoScuro;
        Core.Ipc.setSetting("editor.fondoScuro", editor.fondoScuro);
    }

    /// Il colore che il testo ha DAVVERO: quello scelto, o quello del tema.
    readonly property color tintaTesto:
        editor.coloreTesto !== "" ? editor.coloreTesto
                                  : Theme.Colors.text

    // ── Il testo ─────────────────────────────────────────────────────────

    // Un testo lungo senza barra non dice né a che punto si è né
    // quanto manca. Fuori dal Flickable, non dentro: i suoi figli si
    // spostano già di `-contentY` — il commento più sotto lo racconta
    // per esteso, ed è costato un contenuto che si muoveva il doppio.
    Ui.Scorrimento {
        bersaglio: rotolo
        anchors {
            right: rotolo.right
            top: rotolo.top
            bottom: rotolo.bottom
        }
    }

    Flickable {
        id: rotolo
        anchors.top: barra.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: stato.top
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: editor.piega ? width : Math.max(width, testo.contentWidth + Theme.Effects.space5 * 2)
        contentHeight: Math.max(height, testo.contentHeight + Theme.Effects.space5 * 2)

        // ── I numeri di riga ─────────────────────────────────────────────
        //
        // Un foglio di numeri che scorre insieme al testo. C'erano già, e
        // sbagliavano in QUATTRO modi diversi, misurati il 18 agosto 2026.
        // Tre stavano in queste dieci righe; il quarto — l'unico che li
        // rendeva invisibili del tutto — sta poco più sotto, sul rettangolo
        // del fondo.
        //
        // **Primo, e il peggiore: la colonna scorreva al doppio della
        // velocità.** Stava scritto `y: space2 - rotolo.contentY`, e i figli
        // di un `Flickable` stanno dentro il suo contenuto, che si sposta già
        // di `-contentY` per conto proprio. Sottrarlo una seconda volta a mano
        // vuol dire muoversi il doppio: bastava scorrere di cento pixel perché
        // i numeri fossero duecento pixel più in su del testo. In cima al file
        // tornava tutto a posto, ed è il motivo per cui poteva passare
        // inosservato.
        //
        // **Secondo: il corpo era diverso** — `pixelSize * 0.86`. Un corpo
        // diverso è un'interlinea diversa: alla decima riga la differenza è di
        // un paio di pixel, alla cinquantesima è una riga intera. `lineHeight`
        // fissata alla misura VERA del testo toglie il problema alla radice,
        // e vale anche se il grassetto cambia le metriche del carattere.
        //
        // **Terzo: si ricontavano una volta al secondo**, con un `Timer`.
        // Scrivendo, la colonna restava indietro fino a un secondo intero.
        //
        // E la colonna sparisce con l'a-capo acceso: là una riga del documento
        // ne occupa tre sullo schermo, e non c'è nessun numero giusto da
        // scrivere. Vedi `editor.piega`.
        readonly property bool numeriVisibili: !editor.piega

        property int margineRighe: rotolo.numeriVisibili ? 52 : 0

        /// L'altezza vera di una riga di testo, misurata sul testo stesso.
        /// Senza a-capo `lineCount` sono le righe del documento, quindi il
        /// conto è esatto per costruzione.
        readonly property real altezzaRiga: testo.lineCount > 0
            ? testo.contentHeight / testo.lineCount
            : testo.font.pixelSize * 1.35

        // Il fondo del foglio: scuro o chiaro, come si sceglie nella barra.
        // È del FOGLIO (tutto il contenuto scorre sopra), non della finestra.
        //
        // E sta PRIMO fra i figli, che in QML vuol dire «sotto tutti gli
        // altri». Stava dopo la colonna dei numeri, cioè sopra: i numeri
        // c'erano, erano giusti, e nessuno li ha mai visti — un rettangolo
        // opaco grande quanto tutto il foglio ci stava davanti. È il quarto
        // difetto di questa colonna, e l'unico che spiega perché a Giacomo
        // sembrasse che i numeri di riga non ci fossero proprio.
        Rectangle {
            x: 0
            y: 0
            width: rotolo.contentWidth
            height: rotolo.contentHeight
            color: editor.fondoScuro ? Theme.Colors.base
                                     : Theme.Colors._bianco
        }

        Text {
            id: righe
            visible: rotolo.numeriVisibili
            x: Theme.Effects.space2
            y: Theme.Effects.space2
            width: rotolo.margineRighe - Theme.Effects.space2
            horizontalAlignment: Text.AlignRight
            font.family: testo.font.family
            font.pixelSize: testo.font.pixelSize
            lineHeightMode: Text.FixedHeight
            lineHeight: rotolo.altezzaRiga
            color: Theme.Colors.textFaint
            text: editor.numeriRiga
        }

        Rectangle {
            visible: rotolo.numeriVisibili
            x: rotolo.margineRighe
            y: 0
            width: 1
            height: Math.max(rotolo.height, rotolo.contentHeight)
            color: Theme.Colors.edge
        }

        TextEdit {
            id: testo
            x: Theme.Effects.space3 + rotolo.margineRighe
            y: Theme.Effects.space2
            width: editor.piega ? rotolo.width - Theme.Effects.space3 * 2
                                : Math.max(rotolo.width - Theme.Effects.space3 * 2, contentWidth)
            wrapMode: editor.piega ? TextEdit.WrapAtWordBoundaryOrAnywhere : TextEdit.NoWrap
            text: editor.testoAttivo
            color: editor.tintaTesto
            selectionColor: Qt.alpha(Theme.Colors.accent, 0.4)
            selectedTextColor: Theme.Colors.text
            selectByMouse: true
            selectByKeyboard: true
            persistentSelection: true
            focus: true
            font.family: editor.carattere !== "" ? editor.carattere
                                                 : Theme.Typography.fontMono
            font.pixelSize: editor.dimensioneTesto
            font.bold: editor.grassetto
            font.italic: editor.corsivo
            cursorVisible: activeFocus

            onTextChanged: {
                editor.suTestoCambiato(testo.text);
            }
        }
    }

    // ── La riga di stato ─────────────────────────────────────────────────

    Item {
        id: stato
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 24

        Rectangle {
            anchors.fill: parent
            color: Theme.Colors.membrane
        }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.Colors.edge
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            text: {
                var it = editor.it;
                var r = editor.righe;
                var c = editor.testoAttivo.length;
                if (editor.percorsoAttivo !== "")
                    return editor.percorsoAttivo + "  ·  "
                           + r + (it ? " righe" : " lines") + " · "
                           + c + (it ? " caratteri" : " characters");
                return (it ? "Non ancora salvato  ·  " : "Not saved yet  ·  ")
                       + r + (it ? " righe" : " lines") + " · "
                       + c + (it ? " caratteri" : " characters");
            }
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
            elide: Text.ElideRight
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            text: (editor.it ? "Riga " : "Line ") + editor.rigaCursore
                  + (editor.it ? ", colonna " : ", column ") + editor.colonnaCursore
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontMono
            font.pixelSize: Theme.Typography.sizeXS
            visible: editor.guasto === ""
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            text: editor.guasto
            color: Theme.Colors.danger
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
            elide: Text.ElideRight
        }
    }

    // ── La riga del trova ────────────────────────────────────────────────

    Rectangle {
        id: trovaBar
        anchors.top: barra.bottom
        anchors.right: parent.right
        anchors.rightMargin: Theme.Effects.space3
        anchors.topMargin: Theme.Effects.space2
        width: editor.sostituendo ? 430 : 320
        height: 34
        radius: Theme.Effects.radiusSM
        visible: editor.cercando || editor.sostituendo
        color: Theme.Colors.panel
        border.width: 1
        border.color: Theme.Colors.edgeAccent
        z: 5

        Row {
            anchors.fill: parent
            anchors.margins: Theme.Effects.space2
            spacing: Theme.Effects.space2

            TextInput {
                id: trovaInput
                width: parent.width - (editor.sostituendo ? 96 : 0) - 96
                height: parent.height
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                text: editor.cercaTesto

                onTextChanged: editor.cercaTesto = trovaInput.text
                Keys.onTabPressed: {
                    if (editor.sostituendo) {
                        sostituisciInput.forceActiveFocus();
                        sostituisciInput.selectAll();
                    }
                }
                onAccepted: editor.sostituendo ? editor.sostituisciProssima()
                                               : editor.trova(true)
                Keys.onEscapePressed: editor.sostituendo ? editor.chiudiSostituisci()
                                                         : editor.chiudiTrova()
            }

            TextInput {
                id: sostituisciInput
                visible: editor.sostituendo
                width: editor.sostituendo ? 90 : 0
                height: parent.height
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                text: editor.sostituisciTesto

                onTextChanged: editor.sostituisciTesto = sostituisciInput.text
                onAccepted: editor.sostituisciProssima()
                KeyNavigation.tab: chiudiBtn
            }

            Rectangle {
                height: 26
                width: 26
                radius: Theme.Effects.radiusXS
                color: suMouse.containsMouse ? Theme.Colors.hover : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "↑"
                    color: Theme.Colors.textMuted
                    font.pixelSize: Theme.Typography.sizeSM
                }
                MouseArea {
                    id: suMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editor.trova(false)
                }
            }

            Rectangle {
                height: 26
                width: 26
                radius: Theme.Effects.radiusXS
                color: giuMouse.containsMouse ? Theme.Colors.hover : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "↓"
                    color: Theme.Colors.textMuted
                    font.pixelSize: Theme.Typography.sizeSM
                }
                MouseArea {
                    id: giuMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editor.trova(true)
                }
            }

            Rectangle {
                visible: editor.sostituendo
                height: 26
                width: 64
                radius: Theme.Effects.radiusXS
                color: tuttiMouse.containsMouse ? Qt.alpha(Theme.Colors.accent, 0.18)
                                                : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: editor.it ? "Tutti" : "All"
                    color: Theme.Colors.accent
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }
                MouseArea {
                    id: tuttiMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editor.sostituisciTutte()
                }
            }

            Rectangle {
                height: 26
                width: 26
                radius: Theme.Effects.radiusXS
                color: chiudiMouse.containsMouse ? Theme.Colors.hover : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: Theme.Colors.textMuted
                    font.pixelSize: Theme.Typography.sizeSM
                }
                MouseArea {
                    id: chiudiMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editor.sostituendo ? editor.chiudiSostituisci()
                                                  : editor.chiudiTrova()
                }
                Item { id: chiudiBtn; focus: true }
            }
        }
    }

    // ── La tavolozza dei colori del testo ────────────────────────────────

    Rectangle {
        id: tavolozzaTesto
        anchors.top: barra.bottom
        anchors.right: parent.right
        anchors.rightMargin: Theme.Effects.space3
        anchors.topMargin: Theme.Effects.space2
        width: 250
        height: 54
        radius: Theme.Effects.radiusSM
        visible: false
        color: Theme.Colors.panel
        border.width: 1
        border.color: Theme.Colors.edge
        z: 6

        readonly property var colori: [
            "#22D3EE", "#8B5CF6", "#EC4899", "#F59E0B", "#22C55E",
            "#EF4444", "#EEF4FF", "#C7D2E4", "#3B4252", "#11151D"
        ]

        Row {
            anchors.centerIn: parent
            spacing: Theme.Effects.space2

            Repeater {
                model: tavolozzaTesto.colori

                delegate: Rectangle {
                    required property var modelData

                    width: 20
                    height: 20
                    radius: 10
                    color: modelData
                    border.width: 1
                    border.color: Theme.Colors.edge

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            editor.impostaColore(modelData);
                            tavolozzaTesto.visible = false;
                        }
                    }
                }
            }
        }
    }

    // ── Il menù dei caratteri ────────────────────────────────────────────

    Rectangle {
        id: menùCaratteri
        anchors.top: barra.bottom
        anchors.right: parent.right
        anchors.rightMargin: Theme.Effects.space3
        anchors.topMargin: Theme.Effects.space2
        width: 280
        height: 300
        radius: Theme.Effects.radiusMD
        visible: false
        color: Theme.Colors.panel
        border.width: 1
        border.color: Theme.Colors.edge
        z: 6

        property string filtro: ""

        TextInput {
            id: filtroCaratteri
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.Effects.space2
            height: 28
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            onTextChanged: menùCaratteri.filtro = filtroCaratteri.text
        }

        Rectangle {
            anchors.top: filtroCaratteri.bottom
            anchors.topMargin: Theme.Effects.space2
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: Theme.Effects.space2
            anchors.rightMargin: Theme.Effects.space2
            anchors.bottomMargin: Theme.Effects.space2
            radius: Theme.Effects.radiusSM
            color: Theme.Colors.sunken
            clip: true

            Ui.Scorrimento {
                bersaglio: elencoCaratteri
                anchors {
                    right: elencoCaratteri.right
                    top: elencoCaratteri.top
                    bottom: elencoCaratteri.bottom
                }
            }

            ListView {
                id: elencoCaratteri
                anchors.fill: parent
                anchors.margins: 2
                clip: true
                model: {
                    var f = menùCaratteri.filtro.toLowerCase();
                    var fuori = [];
                    for (var i = 0; i < editor.caratteri.length; i++) {
                        var n = String(editor.caratteri[i]);
                        if (f === "" || n.toLowerCase().indexOf(f) !== -1)
                            fuori.push(n);
                    }
                    return fuori;
                }

                delegate: Rectangle {
                    id: rigaCarattere
                    required property var modelData

                    width: elencoCaratteri.width
                    height: 30
                    radius: Theme.Effects.radiusXS
                    color: rigaMouse.containsMouse ? Qt.alpha(Theme.Colors.accent, 0.16)
                                                   : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.Effects.space3
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData
                        color: Theme.Colors.text
                        font.family: modelData
                        font.pixelSize: Theme.Typography.sizeMD
                        elide: Text.ElideRight
                        width: parent.width - Theme.Effects.space3 * 2
                    }

                    MouseArea {
                        id: rigaMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            editor.impostaCarattere(modelData);
                            menùCaratteri.visible = false;
                        }
                    }
                }
            }
        }
    }

    // ── «Chiudere senza salvare?» ────────────────────────────────────────

    Rectangle {
        id: conferma
        anchors.fill: parent
        color: Theme.Colors.scrim
        visible: editor.daChiudere !== -2
        z: 11

        MouseArea {
            anchors.fill: parent
            onClicked: editor.daChiudere = -2
        }

        Rectangle {
            anchors.centerIn: parent
            width: 440
            height: 132
            radius: Theme.Effects.radiusMD
            color: Theme.Colors.panel
            border.width: 1
            border.color: Theme.Colors.edge

            MouseArea { anchors.fill: parent }

            Text {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                wrapMode: Text.WordWrap
                text: {
                    if (editor.daChiudere === -1)
                        return editor.it ? "Ci sono modifiche non salvate. Chiudere lo stesso?"
                                         : "There are unsaved changes. Close anyway?";
                    var d = editor.daChiudere >= 0 ? editor.docs.get(editor.daChiudere) : null;
                    var nome = d && d.path ? editor.nomeFile(d.path)
                                           : (editor.it ? "Senza nome" : "Untitled");
                    return editor.it ? "«" + nome + "» ha modifiche non salvate. Chiudere lo stesso?"
                                     : "“" + nome + "” has unsaved changes. Close anyway?";
                }
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.Effects.space4
                spacing: Theme.Effects.space2

                Repeater {
                    model: [
                        { "id": "annulla", "it": "Annulla", "en": "Cancel" },
                        { "id": "chiudi", "it": "Chiudi senza salvare", "en": "Close without saving" }
                    ]
                    delegate: Rectangle {
                        id: bottone
                        required property var modelData
                        width: etichetta.implicitWidth + Theme.Effects.space4 * 2
                        height: 32
                        radius: Theme.Effects.radiusXS
                        color: bottone.modelData.id === "chiudi"
                               ? Qt.alpha(Theme.Colors.danger, area.containsMouse ? 0.32 : 0.22)
                               : (area.containsMouse ? Theme.Colors.sunken : "transparent")
                        border.width: 1
                        border.color: Theme.Colors.edge

                        Text {
                            id: etichetta
                            anchors.centerIn: parent
                            text: editor.it ? bottone.modelData.it : bottone.modelData.en
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                        MouseArea {
                            id: area
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (bottone.modelData.id === "chiudi")
                                    editor.confermaChiusura();
                                else
                                    editor.daChiudere = -2;
                            }
                        }
                    }
                }
            }
        }
    }

    // ── La richiesta del percorso ────────────────────────────────────────

    Rectangle {
        id: richiestaPercorso
        anchors.fill: parent
        color: Theme.Colors.scrim
        visible: false
        z: 10

        MouseArea {
            anchors.fill: parent
            onClicked: richiestaPercorso.visible = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: 420
            height: 118
            radius: Theme.Effects.radiusMD
            color: Theme.Colors.panel
            border.width: 1
            border.color: Theme.Colors.edge

            MouseArea { anchors.fill: parent }

            Text {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                text: editor.richiestaPer === "apri"
                      ? (editor.it ? "Aprire quale documento?" : "Open which document?")
                      : (editor.it ? "Salvare dove?" : "Save where?")
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: Theme.Effects.space4 + 26
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space4
                height: 34
                radius: Theme.Effects.radiusXS
                color: Theme.Colors.sunken
                border.width: 1
                border.color: Qt.alpha(Theme.Colors.accent, 0.45)

                TextInput {
                    id: richiestaInput
                    anchors.fill: parent
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.rightMargin: Theme.Effects.space3
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeSM
                    onAccepted: editor.accettaPercorso()
                    Keys.onEscapePressed: richiestaPercorso.visible = false
                }
            }
        }
    }

    // ── Scorciatoie ──────────────────────────────────────────────────────

    Shortcut { sequence: "Ctrl+N"; onActivated: editor.nuovo() }
    Shortcut { sequence: "Ctrl+O"; onActivated: editor.apriConPercorso() }
    Shortcut { sequence: "Ctrl+S"; onActivated: editor.salva() }
    Shortcut { sequence: "Ctrl+Shift+S"; onActivated: editor.salvaCome() }
    Shortcut { sequence: "Ctrl+F"; onActivated: editor.apriTrova() }
    Shortcut { sequence: "Ctrl+H"; onActivated: editor.apriSostituisci() }
    Shortcut { sequence: "Ctrl+L"; onActivated: editor.chiediRiga() }
    Shortcut { sequence: "Ctrl+B"; onActivated: editor.commutaGrassetto() }
    Shortcut { sequence: "Ctrl+I"; onActivated: editor.commutaCorsivo() }
    Shortcut { sequence: "Ctrl+W"; onActivated: editor.closeTab(editor.currentIndex) }
    Shortcut { sequence: "Ctrl+Plus"; onActivated: editor.zoomTesto(1) }
    Shortcut { sequence: "Ctrl+Minus"; onActivated: editor.zoomTesto(-1) }
    Shortcut { sequence: "Ctrl+Z"; onActivated: testo.undo() }
    Shortcut { sequence: "Ctrl+Shift+Z"; onActivated: testo.redo() }
}

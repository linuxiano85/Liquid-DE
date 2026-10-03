//@ pragma AppId minerva-app
// app.qml — Quattro programmi di Minerva, un processo solo.
//
// Qui dentro vivono Calcolatrice, Editor, Anteprima e Attività. Non è un
// contenitore per comodità: è la risposta a un numero misurato.
//
// ── Il numero ───────────────────────────────────────────────────────────────
//
// Misurato il 18 agosto 2026 sulla macchina vera, memoria privata:
//
//     un processo `qs` con UNA finestra vuota      73 MB
//     un processo `qs` con TRE finestre vuote      83 MB
//
// **Una finestra in più nello stesso processo costa 5 MB. Un processo in più
// ne costa 70.** Quattordici volte tanto.
//
// E provato per davvero con tre delle nostre app aperte insieme:
//
//     Editor + Anteprima + Attività, processi separati   250 MB   1097 ms
//     le stesse tre in questo processo                   107 MB    377 ms
//
// Centoquarantatré megabyte e settecento millisecondi, per la sola ragione
// che il pavimento di Qt — 31 MB di motore grafico, librerie e primo
// fotogramma — si paga UNA volta invece di tre. Lo stesso vale per il canale
// col demone (11 MB), per lo strato `ui` e per le 88 librerie che Qt apre
// alla prima icona di un tema classico.
//
// ── Il prezzo, e perché la barra non lo paga ────────────────────────────────
//
// Un errore QML in una di queste quattro le chiude tutte e quattro. È
// esattamente il difetto per cui a suo tempo si erano separati i processi —
// «un errore in un punto qualunque non buttava giù una finestra: buttava giù
// l'ambiente intero, e con lui la barra da cui si sarebbe potuto rimediare».
//
// Quella ragione resta valida ed è il motivo per cui **la shell non è qui
// dentro**: barra, dock e scrivania restano un processo loro, e non cadono
// mai per colpa di una calcolatrice. Restano fuori anche il gestore file e le
// Impostazioni, che sono quelle che si toccano di più, e che spesso stanno
// aperte mentre si fa altro.
//
// Scelta di Giacomo il 18 agosto 2026: «sì, ma per gradi e con una rete».
//
// ── Come si usa ─────────────────────────────────────────────────────────────
//
//     qs -d -n -p .../minerva-shell/app.qml            lo avvia
//     qs ipc -p .../app.qml call app apri calcolatrice
//     qs ipc -p .../app.qml call app apri editor /tmp/note.txt
//
// e gli script `scripts/minerva-{calcolatrice,editor,viewer,monitor}` fanno
// esattamente questo.
import QtQuick
import Quickshell
import Quickshell.Io

import "theme" as Theme
import "core" as Core
import "calcolatrice"
import "editor"
import "viewer"
import "monitor"
import "custodia"
import "manutenzione"
import "fucina"
import "terminale"

ShellRoot {
    id: app

    // Le stesse ragioni di `shell.qml`: il ricaricamento automatico chiude le
    // finestre sotto le mani di chi lavora.
    Component.onCompleted: {
        Quickshell.watchFiles = false;
        app._primaRichiesta();
    }

    // ── Con che cosa nasce ───────────────────────────────────────────────
    //
    // Chi avvia questo processo vuole qualcosa: non esiste un motivo per
    // accendere l'ospite e basta — infatti se nessuna delle quattro finestre è
    // costruita, `_valutaSeRestare()` lo fa uscire.
    //
    // Le richieste sono DUE e vanno tenute distinte, perché è qui che il
    // preload si era rotto:
    //
    //   · `MINERVA_APP_APRI`    — aprila e portala davanti (l'utente l'ha
    //                             chiesta adesso);
    //   · `MINERVA_APP_PREPARA` — costruiscila e NON mostrarla (l'utente l'ha
    //                             messa fra quelle da tenere pronte).
    //
    // Prima ce n'era una sola. `core/AppPronte.qml` lanciava lo script con
    // `MINERVA_CALCOLATRICE_DORMIENTE=1`, ma lo script — da quando le quattro
    // app vivono in questo stesso processo — quella variabile non la guarda
    // più: impostava `MINERVA_APP_APRI`, e qui si finiva dritti in `apri()`,
    // che chiama `risveglia()`. Risultato: chi accendeva «tienila pronta» si
    // vedeva la finestra spuntare in faccia quattro secondi dopo l'accesso,
    // cioè l'esatto contrario di quello che aveva chiesto.
    //
    // `preparaDormiente()` esisteva già e non la chiamava nessuno.
    //
    // La richiesta arriva nell'ambiente e non sulla riga di comando perché la
    // riga di comando è di `qs`, non nostra: `qs -p app.qml calcolatrice` non
    // passerebbe niente a noi, proverebbe a leggerlo come un'opzione sua. È la
    // stessa ragione per cui il gestore file legge `MINERVA_FILES_PATH`.
    function _primaRichiesta() {
        var quale = "";
        var prepara = "";
        var arg = "";
        try {
            quale = String(Quickshell.env("MINERVA_APP_APRI") || "");
            prepara = String(Quickshell.env("MINERVA_APP_PREPARA") || "");
            arg = String(Quickshell.env("MINERVA_APP_ARG") || "");
        } catch (e) {
            quale = "";
            prepara = "";
        }
        // Se ci sono tutte e due vince «apri»: una richiesta esplicita
        // dell'utente batte sempre una preparazione di sfondo.
        if (quale !== "")
            app.apri(quale, arg);
        else if (prepara !== "")
            app.preparaDormiente(prepara);
    }

    // ── Il colore di Minerva ─────────────────────────────────────────────
    //
    // Qui i legami si scrivono UNA volta per quattro programmi, mentre prima
    // erano ripetuti in quattro punti d'ingresso che non potevano leggersi le
    // proprietà a vicenda. È il primo vantaggio che si vede leggendo, e non
    // il più importante.

    Binding {
        target: Core.Strings
        property: "requestedLanguage"
        value: Core.Ipc.get("general.language", "auto")
    }

    // ── Il tema ──────────────────────────────────────────────────────────
    //
    // Un oggetto solo al posto dei blocchi di `Binding` che stavano qui: la
    // tavolozza non legge le impostazioni, e chi fa il legame lo fa in un
    // posto solo per tutti e sei i punti d'ingresso. Vedi `theme/LegaTema.qml`.
    Theme.LegaTema { }






    // ── Le quattro finestre ──────────────────────────────────────────────
    //
    // Ognuna dentro un `Loader` spento. **Spento è la parte importante**: un
    // `Loader` con `active: false` non costruisce niente, e le tre app che non
    // hai aperto non ti costano nulla. Aprirne una la costruisce, chiuderla la
    // smonta — a meno che tu l'abbia chiesta pronta, e allora resta costruita
    // e nascosta, che è tutto il senso di `core/TenutaPronta.qml`.
    //
    // Il `Loader` sta qui e non dentro le app perché è chi ospita a sapere
    // quali finestre esistono; le app non sanno di essere ospitate, e infatti
    // nessuna di loro è cambiata per stare qui dentro.

    Loader {
        id: calcolatrice
        active: false
        // `Component` e non l'oggetto nudo: `sourceComponent` vuole una
        // ricetta, e un oggetto scritto lì si costruirebbe SUBITO — cioè
        // esattamente quello che questo `Loader` esiste per non fare.
        sourceComponent: Component {
            Calcolatrice {
                dormiente: prontaCalcolatrice.dormiente
                onRequestClose: prontaCalcolatrice.chiudi()
            }
        }
    }

    Loader {
        id: editor
        active: false
        // `Component` e non l'oggetto nudo: `sourceComponent` vuole una
        // ricetta, e un oggetto scritto lì si costruirebbe SUBITO — cioè
        // esattamente quello che questo `Loader` esiste per non fare.
        sourceComponent: Component {
            Editor {
                dormiente: prontaEditor.dormiente
                onRequestClose: prontaEditor.chiudi()
            }
        }
    }

    Loader {
        id: anteprima
        active: false
        // `Component` e non l'oggetto nudo: `sourceComponent` vuole una
        // ricetta, e un oggetto scritto lì si costruirebbe SUBITO — cioè
        // esattamente quello che questo `Loader` esiste per non fare.
        sourceComponent: Component {
            Viewer {
                dormiente: prontaAnteprima.dormiente
                onRequestClose: prontaAnteprima.chiudi()
            }
        }
    }

    Loader {
        id: custodiaL
        active: false
        // `Component` e non l'oggetto nudo: `sourceComponent` vuole una
        // ricetta, e un oggetto scritto lì si costruirebbe SUBITO — cioè
        // esattamente quello che questo `Loader` esiste per non fare.
        sourceComponent: Component {
            Custodia {
                dormiente: prontaCustodia.dormiente
                onRequestClose: prontaCustodia.chiudi()
            }
        }
    }

    Loader {
        id: manutenzioneL
        active: false
        // `Component` e non l'oggetto nudo: `sourceComponent` vuole una
        // ricetta, e un oggetto scritto lì si costruirebbe SUBITO — cioè
        // esattamente quello che questo `Loader` esiste per non fare.
        sourceComponent: Component {
            Manutenzione {
                dormiente: prontaManutenzione.dormiente
                onRequestClose: prontaManutenzione.chiudi()
            }
        }
    }

    Loader {
        id: attivita
        active: false
        // `Component` e non l'oggetto nudo: `sourceComponent` vuole una
        // ricetta, e un oggetto scritto lì si costruirebbe SUBITO — cioè
        // esattamente quello che questo `Loader` esiste per non fare.
        sourceComponent: Component {
            Monitor {
                dormiente: prontaAttivita.dormiente
                onRequestClose: prontaAttivita.chiudi()
            }
        }
    }

    // La Fucina (30 settembre 2026): kernel su misura. Nell'ospite e non in
    // un processo suo per la ragione scritta in cima a questo file: una
    // finestra in più qui costa 5 MB, un processo in più 70. La compilazione
    // non vive qui ma nel demone, quindi chiudere la finestra non la ferma.
    Loader {
        id: fucinaL
        active: false
        sourceComponent: Component {
            Fucina {
                dormiente: prontaFucina.dormiente
                onRequestClose: prontaFucina.chiudi()
            }
        }
    }

    // Il Terminale (15 settembre 2026). Una finestra con le schede: aprire
    // «un altro terminale» è una scheda in più nella stessa, non un altro
    // processo — e `addTab` con una cartella o `esegui://cmd` la apre lì.
    Loader {
        id: terminaleL
        active: false
        sourceComponent: Component {
            Terminale {
                dormiente: prontaTerminale.dormiente
                onRequestClose: prontaTerminale.chiudi()
            }
        }
    }

    // ── Chi decide se restano accese ─────────────────────────────────────
    //
    // Uno per app, perché la scelta «tienila pronta» è per app: chi vuole la
    // calcolatrice istantanea non deve per forza tenersi anche Anteprima con
    // le sue miniature.
    //
    // `chiudi()` qui non fa uscire il processo — glielo dice `esceDaSola:
    // false` — perché uscire chiuderebbe anche le altre tre. Chi decide se il
    // processo ha ancora un motivo di esistere è `_valutaSeRestare()` più
    // sotto, che le guarda tutte insieme.

    Core.TenutaPronta {
        id: prontaCalcolatrice
        nome: "calcolatrice"
        esceDaSola: false
        laFinestra: calcolatrice.item
        onSpenta: calcolatrice.active = false
    }

    Core.TenutaPronta {
        id: prontaEditor
        nome: "editor"
        esceDaSola: false
        laFinestra: editor.item
        onSpenta: editor.active = false
    }

    Core.TenutaPronta {
        id: prontaAnteprima
        nome: "anteprima"
        esceDaSola: false
        laFinestra: anteprima.item
        onSpenta: anteprima.active = false
    }

    Core.TenutaPronta {
        id: prontaCustodia
        nome: "custodia"
        esceDaSola: false
        laFinestra: custodiaL.item
        onSpenta: custodiaL.active = false
    }

    Core.TenutaPronta {
        id: prontaManutenzione
        nome: "manutenzione"
        esceDaSola: false
        laFinestra: manutenzioneL.item
        onSpenta: manutenzioneL.active = false
    }

    Core.TenutaPronta {
        id: prontaAttivita
        nome: "attivita"
        esceDaSola: false
        laFinestra: attivita.item
        onSpenta: attivita.active = false
    }

    Core.TenutaPronta {
        id: prontaFucina
        nome: "fucina"
        esceDaSola: false
        laFinestra: fucinaL.item
        onSpenta: fucinaL.active = false
    }

    Core.TenutaPronta {
        id: prontaTerminale
        nome: "terminale"
        esceDaSola: false
        laFinestra: terminaleL.item
        onSpenta: terminaleL.active = false
    }

    // ── Aprire ───────────────────────────────────────────────────────────

    /// Accende una delle quattro e la porta davanti.
    ///
    /// `argomento` vuol dire cose diverse per ognuna — un file per l'editor,
    /// una cartella o un'immagine per Anteprima, niente per le altre due — e
    /// si passa alla finestra solo dopo averla costruita.
    function apri(quale, argomento) {
        switch (quale) {
        case "calcolatrice":
            calcolatrice.active = true;
            prontaCalcolatrice.risveglia();
            break;
        case "editor":
            editor.active = true;
            if (argomento && argomento !== "")
                editor.item.addTab(argomento);
            prontaEditor.risveglia();
            break;
        case "anteprima":
            anteprima.active = true;
            if (argomento && argomento !== "")
                anteprima.item.show(argomento);
            prontaAnteprima.risveglia();
            break;
        case "anteprima-cartella":
            anteprima.active = true;
            if (argomento && argomento !== "")
                anteprima.item.apriCartella(argomento);
            prontaAnteprima.risveglia();
            break;
        case "attivita":
            attivita.active = true;
            prontaAttivita.risveglia();
            break;
        case "terminale":
            // La finestra apre da sola una scheda a casa appena nasce; con un
            // argomento (una cartella, o `esegui://cmd`) `addTab` decide se
            // aggiungerne una o sostituire quella automatica.
            terminaleL.active = true;
            if (terminaleL.item)
                terminaleL.item.addTab(argomento || "");
            prontaTerminale.risveglia();
            break;
        case "custodia":
            custodiaL.active = true;
            prontaCustodia.risveglia();
            break;
        case "manutenzione":
            manutenzioneL.active = true;
            prontaManutenzione.risveglia();
            break;
        case "fucina":
            fucinaL.active = true;
            prontaFucina.risveglia();
            break;
        default:
            return false;
        }
        return true;
    }

    /// Costruisce una finestra senza mostrarla: è il preload.
    ///
    /// Chiamata da `core/AppPronte.qml` all'accesso, per le app che l'utente
    /// ha chiesto pronte. Costruire e non mostrare è esattamente la differenza
    /// fra 34 ms e 400 alla prima apertura.
    ///
    /// ── Su una già costruita non fa NIENTE ───────────────────────────────
    ///
    /// Preparare vuol dire «costruiscila se non c'è». Se c'è già, non c'è
    /// niente da preparare — e toccarla sarebbe un danno: `addormenta()` su
    /// una finestra aperta la fa sparire sotto le mani di chi ci sta
    /// scrivendo.
    ///
    /// Non è un caso di scuola, è successo: ricaricando la shell,
    /// `core/AppPronte.qml` rifà il giro del preload, e l'editor che era
    /// aperto con un documento dentro è svanito. La finestra non era chiusa —
    /// era dormiente — ma per chi guarda è la stessa cosa.
    function preparaDormiente(quale) {
        var caricatore = null;
        var pronta = null;
        switch (quale) {
        case "calcolatrice": caricatore = calcolatrice; pronta = prontaCalcolatrice; break;
        case "editor":       caricatore = editor;       pronta = prontaEditor;       break;
        case "anteprima":    caricatore = anteprima;    pronta = prontaAnteprima;    break;
        case "attivita":     caricatore = attivita;     pronta = prontaAttivita;     break;
        case "terminale":    caricatore = terminaleL;   pronta = prontaTerminale;    break;
        default: return false;
        }
        // Già costruita: che sia sveglia o dormiente, è pronta. Si lascia stare.
        if (caricatore.active)
            return true;
        caricatore.active = true;
        pronta.addormenta();
        return true;
    }

    // ── E quando non serve più a nessuno, esce ───────────────────────────
    //
    // Un processo senza finestre che resta in memoria è un programma che
    // l'utente crede di aver chiuso e invece no. Vale per quattro app come
    // valeva per una: si esce quando NESSUNA delle quattro è costruita.
    //
    // ── Perché si guarda il `Loader` e non l'impostazione ────────────────
    //
    // Prima la condizione era `caricatori[i].active || tutte[i].tenerlaPronta`,
    // e quel secondo termine teneva in vita l'ospite per sempre. Basta seguire
    // cosa succede dopo i minuti di pazienza: `TenutaPronta` chiama `smetti()`
    // → `spenta()` → `loader.active = false`. La finestra viene smontata, e
    // quindi da quel momento l'app **non è più pronta**. Ma `tenerlaPronta`
    // resta vero — è l'interruttore nelle Impostazioni, non lo stato — e
    // l'ospite restava acceso: 31 MB di pavimento Qt per zero finestre e zero
    // vantaggio alla prossima apertura. L'interruttore prometteva una cosa che
    // dopo mezz'ora non era più vera.
    //
    // Guardando solo i `Loader` si esce, e la prossima apertura ricrea
    // l'ospite — che è la stessa spesa di prima, ma pagata quando serve.
    //
    // `impostazioniArrivate` e non `prontoADipingere`: il secondo è vero anche
    // per scadenza, e con i valori di ripiego si deciderebbe sul falso. Qui la
    // decisione è «resto o me ne vado», e sul falso si esce mentre l'utente
    // sta guardando la finestra aprirsi.

    readonly property var tutte: [prontaCalcolatrice, prontaEditor,
                                  prontaAnteprima, prontaAttivita]

    function _valutaSeRestare() {
        if (!Core.Ipc.impostazioniArrivate)
            return;
        // Ogni finestra nuova va aggiunta QUI, o il processo esce con quella
        // finestra aperta sotto le mani di chi la sta usando. È l'elenco che
        // si dimentica, quindi c'è una guardia in `scripts/prove.sh` che
        // conta i `Loader` e verifica che siano tutti nominati.
        var caricatori = [calcolatrice, editor, anteprima, attivita, custodiaL,
                          manutenzioneL, terminaleL, fucinaL];
        for (var i = 0; i < caricatori.length; i++) {
            if (caricatori[i].active)
                return;
        }
        Qt.quit();
    }

    Connections {
        target: Core.Ipc
        function onImpostazioniArrivateChanged() { app._valutaSeRestare(); }
    }

    Connections { target: prontaCalcolatrice; function onSpenta() { app._valutaSeRestare(); } }
    Connections { target: prontaEditor;       function onSpenta() { app._valutaSeRestare(); } }
    Connections { target: prontaAnteprima;    function onSpenta() { app._valutaSeRestare(); } }
    Connections { target: prontaAttivita;     function onSpenta() { app._valutaSeRestare(); } }
    Connections { target: prontaCustodia;     function onSpenta() { app._valutaSeRestare(); } }
    Connections { target: prontaManutenzione; function onSpenta() { app._valutaSeRestare(); } }
    Connections { target: prontaFucina;       function onSpenta() { app._valutaSeRestare(); } }
    // Il Terminale era rimasto fuori da questo elenco: chiuso per ultimo,
    // lasciava l'ospite acceso senza finestre. Trovato il 30 settembre 2026
    // aggiungendo la Fucina, contando le righe accanto.
    Connections { target: prontaTerminale;    function onSpenta() { app._valutaSeRestare(); } }

    // ── Comandi dall'esterno ─────────────────────────────────────────────

    IpcHandler {
        target: "app"

        function apri(quale: string, argomento: string): string {
            return app.apri(quale, argomento) ? "ok" : "sconosciuta";
        }

        function prepara(quale: string): string {
            return app.preparaDormiente(quale) ? "ok" : "sconosciuta";
        }

        /// Serve a chi ci lancia per sapere che siamo vivi senza aprire niente.
        function ping(): string {
            return "ok";
        }
    }
}

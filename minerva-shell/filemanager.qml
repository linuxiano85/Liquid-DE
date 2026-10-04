//@ pragma AppId minerva-files
// filemanager.qml — Minerva Files, come processo a sé.
//
// Questo file è un SECONDO punto d'ingresso di Minerva. Non è una variante di
// `shell.qml`: è un altro programma, che per caso è scritto con gli stessi
// pezzi.
//
// Perché esiste. Fino a ieri barra, dock, scrivania, Impostazioni e gestore
// file vivevano dentro lo stesso processo `qs`. Un errore QML in un punto
// qualunque — una riga sbagliata nell'elenco dei file, una divisione per zero
// in una griglia — non buttava giù una finestra: buttava giù l'ambiente
// intero, e con lui la barra da cui si sarebbe potuto rimediare. Reggeva
// l'attenzione di chi scriveva, non l'architettura.
//
// Il gestore file è il primo pezzo a uscire, per tre motivi in fila:
//
//  · è quello che si tocca di più e quindi quello che cambia di più;
//  · è già una finestra normale, non un pannello agganciato alla barra, quindi
//    non ha niente da chiedere alla shell per esistere;
//  · è quello che si apre da fuori — un doppio clic su una cartella in un
//    altro programma — e un'applicazione vera si deve poter avviare da sola,
//    senza che ci sia una shell in ascolto.
//
// Si avvia così, ed è quello che fa lo script `minerva-files`:
//
//     MINERVA_FILES_PATH=/home/tizio/Immagini \
//         qs -d -p .../minerva-shell/filemanager.qml
//
// e chi è già aperto si comanda così:
//
//     qs ipc -p .../minerva-shell/filemanager.qml call files open /tmp
//
// Quello che la shell e il gestore file continuano a condividere è il DEMONE:
// le impostazioni, l'elenco dei dischi, le copie in corso stanno lì e sono le
// stesse per tutti e due. Due processi che disegnano, uno che sa le cose.
import QtQuick
import Quickshell
import Quickshell.Io

import "theme" as Theme
import "core" as Core
import "files"

ShellRoot {
    id: app

    // Le stesse ragioni di `shell.qml`: il ricaricamento automatico chiude le
    // finestre sotto le mani di chi lavora. Qui farebbe anche di peggio —
    // ricaricare mentre una copia da due gigabyte è a metà.
    Component.onCompleted: {
        Quickshell.watchFiles = false;
    }

    // ── Quello che si prende dalle impostazioni ──────────────────────────
    //
    // Ripetute da `shell.qml` e non condivise: sono due processi, e un
    // processo non può leggere le proprietà dell'altro. La sorgente però è la
    // stessa — il demone — quindi cambiare l'accento nelle Impostazioni tinge
    // tutti e due senza che nessuno dei due sappia dell'altro.

    Binding {
        target: Core.Strings
        property: "requestedLanguage"
        value: Core.Ipc.get("general.language", "auto")
    }

    // ── Il colore di Minerva ─────────────────────────────────────────────
    //
    // Tema, accento e trasparenze si legano QUI e non dentro la palette,
    // perché la palette non deve conoscere il demone: un tema che sa dove
    // stanno le impostazioni è un tema che non si può riusare. E si ripete in
    // tutti e tre i punti d'ingresso perché sono processi diversi, che non
    // possono leggersi le proprietà a vicenda — la sorgente però è la stessa,
    // quindi cambiare tema li ridipinge tutti nello stesso istante.
    // Il tema di colore: una tinta e un verso, e da lì escono tutte le
    // superfici. Sta prima dell'accento di proposito — l'accento predefinito
    // è quello suggerito dal tema, e chi non ne ha scelto uno suo deve
    // vedersi arrivare quello giusto insieme al resto.

    // ── Il tema ──────────────────────────────────────────────────────────
    //
    // Un oggetto solo al posto dei blocchi di `Binding` che stavano qui: la
    // tavolozza non legge le impostazioni, e chi fa il legame lo fa in un
    // posto solo per tutti e sei i punti d'ingresso. Vedi `theme/LegaTema.qml`.
    Theme.LegaTema { }






    // ── La finestra ──────────────────────────────────────────────────────

    // ── Chiuso, ma pronto ────────────────────────────────────────────────
    //
    // Il gestore file è arrivato per primo, il 16 agosto, con questo
    // meccanismo scritto a mano qui dentro. Adesso è un componente che usano
    // tutte e sei le app — ma le sue due chiavi restano quelle di allora:
    // `files.tieniAcceso` è già nelle Impostazioni di Giacomo e
    // `MINERVA_FILES_DORMIENTE` è già nell'avvio automatico. Rinominarle per
    // simmetria avrebbe spento in silenzio una scelta già fatta.
    //
    // Ed è l'unica accesa di fabbrica, per la stessa ragione di allora:
    // l'attesa la paga ogni volta chi usa il computer, la memoria la paga solo
    // chi ne ha poca — e quello la spegne nelle Impostazioni.
    Core.TenutaPronta {
        id: pronta
        nome: "file"
        chiave: "files.tieniAcceso"
        variabile: "MINERVA_FILES_DORMIENTE"
        ripiego: true
        laFinestra: manager

        // Si riparte puliti: schede in più chiuse e ricerca spenta. Ritrovare
        // la finestra com'era tre giorni fa non è memoria, è disordine — e chi
        // riapre il gestore file quasi sempre sta cominciando un'altra cosa.
        onAddormentata: manager.addormenta()
    }

    FileManager {
        id: manager

        /// La cartella su cui aprirsi, passata nell'ambiente da chi ci lancia.
        ///
        /// Nell'ambiente e non sulla riga di comando perché la riga di comando
        /// è di `qs`, non nostra: `qs -p file.qml /home/tizio` non passerebbe
        /// niente a noi, proverebbe a leggerlo come un'opzione sua.
        initialPath: {
            // Se la variabile manca del tutto, `Quickshell.env` può non
            // restituire una stringa vuota ma fallire, e un errore dentro
            // un binding è veleno per il disegno: la finestra resta al
            // primo fotogramma e i dialoghi non compaiono mai. Meglio
            // blindarlo: senza variabile si parte da casa, che è quello
            // che farebbe chiunque.
            var start = "";
            try {
                start = Quickshell.env("MINERVA_FILES_PATH") || "";
            } catch (e) {
                start = "";
            }
            return start;
        }

        dormiente: pronta.dormiente

        // ── Chiudere ─────────────────────────────────────────────────────
        //
        // Qui c'era `Qt.quit()`, con una ragione giusta scritta accanto: «un
        // processo senza finestre che resta in memoria è un programma che
        // l'utente crede di aver chiuso e invece no».
        //
        // Resta giusta, e resta il motivo per cui questo non si fa di
        // nascosto: si spegne davvero, a meno che l'utente abbia chiesto di
        // tenerlo pronto. In quel caso la finestra si toglie di mezzo e il
        // programma resta — e si vede in `Minerva Attività`, che è il posto
        // dove si va a cercare chi occupa la memoria.
        onRequestClose: pronta.chiudi()
    }

    // ── Una finestra IN PIÙ, nello stesso processo ──────────────────────
    //
    // «Apri una nuova finestra» dalla dock riportava davanti quella che
    // c'era (Giacomo, 29 settembre 2026): questo processo apre schede, non
    // finestre. Ne nasce una qui dentro e non un secondo processo: le
    // strutture di Qt, il tema e il canale col demone ci sono già, e una
    // finestra in più costa pochi megabyte invece di un'app intera.
    //
    // Le finestre in più non si tengono pronte: chiuse, spariscono. Quella
    // che resta pronta è sempre e solo la prima.
    Component {
        id: altraFinestra
        FileManager {
            onRequestClose: destroy()
        }
    }

    /// Quante finestre in più sono aperte adesso: per le prove.
    property int altre: 0

    function nuovaFinestra(path) {
        // La prima dorme (tenuta pronta): per chi guarda non c'è nessuna
        // finestra, quindi la «nuova» è lei.
        if (manager.dormiente || !manager.visible) {
            manager.risveglia(path || "");
            pronta.risveglia();
            return;
        }
        var w = altraFinestra.createObject(app, { "initialPath": path || "" });
        if (!w)
            return;
        app.altre++;
        w.Component.destruction.connect(function () { app.altre--; });
    }

    /// Porta la finestra davanti. Il come — e il perché una volta sola non
    /// basta — stanno in `core/TenutaPronta.qml`.
    function raise() {
        pronta.risveglia();
    }

    // ── Comandi dall'esterno ─────────────────────────────────────────────
    //
    // Il secondo `minerva-files` non avvia un secondo gestore file: chiede a
    // questo di aprire una scheda in più. Venti cartelle aperte da un altro
    // programma sono venti schede in una finestra, non venti finestre.
    IpcHandler {
        target: "files"

        // Completion of a cold start, including a race won by preload.
        // Reuse the initial tab instead of adding a duplicate of initialPath.
        function avvia(path: string): string {
            manager.risveglia(path);
            pronta.risveglia();
            return "ok";
        }

        function open(path: string): string {
            // Dormiente: non si aggiunge una scheda, si RIUSA quella che c'è.
            // Aggiungerla lascerebbe aperta anche la scheda di casa che
            // nessuno ha chiesto — lo stesso difetto per cui `initialPath`
            // esiste invece di un `addTab` all'avvio.
            if (manager.dormiente)
                manager.risveglia(path);
            else if (path && path !== "")
                manager.addTab(path);
            pronta.risveglia();
            return "ok";
        }

        /// Una finestra in più (non una scheda): «Apri una nuova finestra».
        function finestra(path: string): string {
            app.nuovaFinestra(path);
            return "finestre in più: " + app.altre;
        }

        /// Serve a chi ci lancia per sapere che siamo vivi senza aprire
        /// niente: se questa risponde, il processo c'è.
        function ping(): string {
            return "ok";
        }

        /// Per le prove: dove sta l'icona di un file nella finestra («x y»).
        function posto(nome: string): string {
            var p = manager.current ? manager.current.centroDi(nome) : null;
            return p ? Math.round(p.x) + " " + Math.round(p.y) : "non si vede";
        }

        /// Per le prove: il menù dopo un rilascio — vuoto per leggerlo,
        /// «copia» o «sposta» per sceglierlo.
        function rilascio(azione: string): string {
            return manager.menuRilascio(azione);
        }
    }
}


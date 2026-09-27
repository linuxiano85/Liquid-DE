import QtQuick
import Quickshell
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui
// Senza alias: `files` è un modulo con un singleton, e con un alias il
// singleton si troverebbe sotto un doppio nome (`Files.Files`) — le funzioni
// di Files risulterebbero «non funzioni». Il gestore file fa così.
import "../files"

// DesktopIcons — Le icone dei file sulla scrivania.
//
// La scrivania è una cartella come le altre: qui si mostra il suo contenuto
// come icone, come su ogni ambiente classico. Non è un secondo gestore file
// in miniatura: è il gesto che la scrivania rende possibile — vedere cosa
// c'è, aprirlo con un doppio clic, spostarlo fra un'icona e l'altra — e
// nient'altro. Tutto il resto sta nel gestore file, che è a un doppio clic
// sulla cartella di casa.
//
// ── LA GRIGLIA, CHE PRIMA NON C'ERA ────────────────────────────────────────
//
// Fino al 16 agosto 2026 il posto di un'icona era il punto esatto in cui era
// stata lasciata: due pixel di differenza fra due icone restavano due pixel di
// differenza per sempre. Non era «disposizione libera», era assenza di
// disposizione — e a occhio si legge come sciatteria, perché l'occhio nota
// l'allineamento mancato molto prima di notare l'allineamento riuscito.
//
// Adesso la scrivania ha delle CELLE, e tre modi che sono quelli classici:
//
//   · **disposizione automatica** — le icone riempiono la griglia
//     nell'ordine scelto (nome, tipo, peso, data). Non si spostano a mano
//     perché non c'è un «a mano»: è l'elenco che decide.
//   · **allineate alla griglia** — si mettono dove si vuole, e si posano
//     nella cella più vicina che sia libera. È il modo di fabbrica.
//   · **libere** — dove si lascia l'icona, lì resta, al pixel.
//
// Sono due interruttori indipendenti e non tre scelte in fila, perché è così
// che li conosce chi arriva da Windows, da KDE o da GNOME 2: «disposizione
// automatica» e «allinea alla griglia», con la prima che vince sulla seconda.
//
// ── DOVE COMINCIA LA GRIGLIA ───────────────────────────────────────────────
//
// Non in cima allo schermo: sotto la barra, e sopra la dock. Quanto si sono
// presi lo dice il compositore (`Core.Windows.spaziPerMonitor`), che è lo
// stesso numero da cui dipende «ingrandisci». Qui c'era un difetto silenzioso:
// la prima riga di icone partiva da y=12, cioè **sotto la barra alta 44**, e
// la si scopriva solo quando la prima icona finiva mezza coperta.
//
// ── PERCHÉ LE POSIZIONI RESTANO IN PIXEL ───────────────────────────────────
//
// Salvare la cella (colonna, riga) sarebbe più elegante e si romperebbe di
// meno cambiando risoluzione. Ma la disposizione libera esiste apposta per
// tenere un'icona in un punto che una cella non descrive, e due depositi —
// uno a celle e uno a pixel — vorrebbero dire due verità sullo stesso fatto.
// Restano i pixel; quando l'allineamento è acceso, si riagganciano alla
// griglia **in lettura**, quindi cambiare risoluzione o dimensione delle icone
// le rimette in riga da sé invece di lasciarle sparse.
Item {
    id: icons

    /// La cartella della scrivania, dalla shell.
    property string cartella: ""

    /// Il nome del monitor su cui stiamo, per sapere quanto spazio si sono
    /// presi la barra e la dock.
    property string monitor: ""

    /// I file dentro. Dal demone, come un riquadro del gestore file.
    property var entries: []

    /// Dove sta ogni icona, per nome: { "foto.jpg": [120, 80], ... }
    ///
    /// Legata all'impostazione e MAI assegnata: fino al 28 settembre 2026
    /// `ricorda` ci scriveva sopra, e un'assegnazione in QML rompe il legame —
    /// dopo il primo trascinamento la scrivania non seguiva più niente di
    /// quello che arrivava da fuori (il riordino, l'altro schermo, il demone).
    property var posizioni: Core.Ipc.get("files.desktopPositions", ({}))
    /// Le mosse appena fatte, finché il demone non le conferma: senza,
    /// l'icona lasciata tornerebbe indietro per il tempo di un giro col
    /// demone e poi salterebbe dove è stata messa. Si svuota quando arriva
    /// la conferma (`onPosizioniChanged`).
    property var _appena: ({})
    onPosizioniChanged: icons._appena = ({})

    /// Nome dell'icona che si sta rinominando, o vuoto.
    property string rinomina: ""

    readonly property bool it: Core.Strings.lang === "it"

    // ── I due interruttori, e l'ordine ───────────────────────────────────
    //
    // Legate alle impostazioni ma NON `readonly`: le prove
    // (`prove-scrivania.qml`) le fissano a mano per provare la griglia senza
    // un demone, e una proprietà di sola lettura costringerebbe a provare
    // quello che il demone dice oggi invece di quello che il codice fa. In
    // produzione nessuno ci scrive: si passa da `eseguiDisposizione`, che
    // scrive l'impostazione e lascia che sia il legame a riportarla qui.

    /// Le icone riempiono la griglia da sole, nell'ordine scelto.
    property bool autoDisponi: Core.Ipc.get("desktop.iconAutoArrange", false)
    /// Si posano nella cella più vicina invece che al pixel. Vince
    /// `autoDisponi`, che è già allineato per costruzione.
    property bool allinea: Core.Ipc.get("desktop.iconSnap", true)
    /// "name", "type", "size", "modified" — gli stessi nomi del gestore file,
    /// e la stessa funzione che li ordina.
    property string ordine: Core.Ipc.get("desktop.iconSort", "name")
    property bool ordineDesc: Core.Ipc.get("desktop.iconSortDesc", false)
    /// Il lato del disegno dell'icona. La cella si ricava da qui.
    property int lato: Core.Ipc.get("desktop.iconSize", 46)

    // ── L'elenco ─────────────────────────────────────────────────────────

    function ricarica() {
        if (icons.cartella !== "" && Core.Ipc.connected)
            Core.Ipc.fsList(icons.cartella, false, "scrivania");
    }

    Connections {
        target: Core.Ipc
        function onFileListingReceived(listing) {
            if (listing.pane !== "scrivania")
                return;
            icons.entries = listing.entries || [];
        }
        // Copiato qualcosa sulla scrivania, cestinato, rinominato: l'elenco
        // si riaggiorna da solo, o l'icona nuova compare solo al riavvio.
        function onFileResultReceived() { icons.ricarica(); }
        function onFileJobChanged(job) {
            if (job.state === "done" || job.state === "cancelled")
                icons.ricarica();
        }
        function onConnectedChanged() {
            if (Core.Ipc.connected)
                icons.ricarica();
        }
    }

    onCartellaChanged: icons.ricarica()

    // ── Le modifiche fatte DA FUORI ───────────────────────────────────────
    //
    // Il demone annuncia quello che succede dalle nostre finestre; un file
    // creato dal terminale o da un altro programma non lo annuncia nessuno.
    // Ogni quindici secondi si rilegge la cartella: costa una domanda al
    // demone e tiene la scrivania sincera. (Il gestore file rilegge per gli
    // stessi eventi, e questa rete vale anche per lui quando è aperto.)
    Timer {
        interval: 15000
        repeat: true
        running: icons.cartella !== ""
        onTriggered: icons.ricarica()
    }

    // ── La griglia ───────────────────────────────────────────────────────
    //
    // Tutto deriva da `lato`: cambiare la dimensione delle icone cambia la
    // cella, e quindi quante ne stanno per colonna. Un numero solo da
    // regolare, e niente che possa divergere.

    /// Il quadrato colorato dietro l'icona, che è anche il bersaglio.
    readonly property int riquadro: Math.round(icons.lato * 1.9)
    readonly property int cellaW: icons.riquadro + 30
    readonly property int cellaH: icons.riquadro + 41

    /// Il margine dai bordi dello schermo.
    readonly property int bordo: 10

    /// Lo spazio utile di questo monitor, com'è per il compositore: lo schermo
    /// meno la barra in alto e la dock in basso. Nullo finché non risponde.
    readonly property var spazio: {
        var lista = Core.Windows.spaziPerMonitor || [];
        for (var i = 0; i < lista.length; i++)
            if (lista[i].nome === icons.monitor)
                return lista[i];
        return null;
    }

    /// Quanto si è presa la barra in cima. Il ripiego non è zero ma l'altezza
    /// della barra: se il compositore non ha ancora risposto, mettere le icone
    /// in cima allo schermo vuol dire mettercele SOTTO — e la prima riga
    /// nascerebbe coperta per poi saltare giù un istante dopo.
    ///
    /// E il ripiego guarda DOVE sta la barra, o sposta il buco dalla parte
    /// sbagliata: con la barra in fondo, tenere 44 pixel in cima vuol dire una
    /// riga di icone in meno E la prima riga coperta lo stesso.
    readonly property int sopra: icons.spazio
            ? Math.max(0, icons.spazio.y - icons.spazio.sy) + icons.bordo
            : (Core.Posizioni.barraInBasso
               ? icons.bordo : Theme.Effects.barHeight + icons.bordo)

    /// E quanto si è presa la dock in fondo.
    readonly property int sotto: icons.spazio
            ? Math.max(0, (icons.spazio.sy + icons.spazio.sh)
                          - (icons.spazio.y + icons.spazio.h)) + icons.bordo
            : (Core.Posizioni.barraInBasso
               ? Theme.Effects.barHeight + icons.bordo : icons.bordo)

    readonly property int colonne: Math.max(1,
            Math.floor((icons.width - icons.bordo * 2) / icons.cellaW))
    readonly property int righe: Math.max(1,
            Math.floor((icons.height - icons.sopra - icons.sotto) / icons.cellaH))

    function puntoDiCella(c, r) {
        return Qt.point(icons.bordo + c * icons.cellaW,
                        icons.sopra + r * icons.cellaH);
    }

    /// La cella in cui cade un punto. Arrotonda al più vicino e non taglia
    /// verso il basso: lasciando un'icona appena oltre la metà di una cella si
    /// intende quella dopo, non quella da cui si è appena usciti.
    function cellaDiPunto(x, y) {
        var c = Math.round((x - icons.bordo) / icons.cellaW);
        var r = Math.round((y - icons.sopra) / icons.cellaH);
        return Qt.point(Math.max(0, Math.min(icons.colonne - 1, c)),
                        Math.max(0, Math.min(icons.righe - 1, r)));
    }

    /// La cella libera più vicina a un punto.
    ///
    /// Si allarga a cerchi finché non ne trova una: senza, due icone lasciate
    /// nella stessa zona si sovrapporrebbero esattamente, e la seconda
    /// sembrerebbe sparita.
    function cellaLibera(x, y, occupate) {
        var p = icons.cellaDiPunto(x, y);
        if (!occupate[p.x + "," + p.y])
            return p;
        var raggio = Math.max(icons.colonne, icons.righe);
        for (var d = 1; d <= raggio; d++) {
            for (var dc = -d; dc <= d; dc++) {
                for (var dr = -d; dr <= d; dr++) {
                    // Solo il bordo del quadrato: l'interno l'ha già guardato
                    // il giro precedente.
                    if (Math.abs(dc) !== d && Math.abs(dr) !== d)
                        continue;
                    var c = p.x + dc, r = p.y + dr;
                    if (c < 0 || r < 0 || c >= icons.colonne || r >= icons.righe)
                        continue;
                    if (!occupate[c + "," + r])
                        return Qt.point(c, r);
                }
            }
        }
        return p;
    }

    /// La prima cella libera in ordine di colonna: dall'alto in basso, poi a
    /// destra. È l'ordine in cui nascono le scrivanie classiche.
    function primaCellaLibera(occupate) {
        for (var c = 0; c < icons.colonne; c++)
            for (var r = 0; r < icons.righe; r++)
                if (!occupate[c + "," + r])
                    return Qt.point(c, r);
        return Qt.point(0, 0);
    }

    // ── Dove sta ogni icona ──────────────────────────────────────────────
    //
    // Calcolata TUTTA INSIEME, una volta per cambiamento, e non icona per
    // icona. Qui c'era un conto quadratico: ogni icona senza posto scorreva
    // l'intero elenco e l'intera mappa delle posizioni per sapere dove stare,
    // e lo rifaceva a ogni ridisegno. Con trenta icone sono novecento giri per
    // fotogramma, per una risposta che è la stessa finché non cambia niente.
    readonly property var disposizione: {
        var out = {};
        var lista = icons.entries || [];
        if (lista.length === 0)
            return out;

        // ── Disposizione automatica ──────────────────────────────────────
        //
        // Il deposito delle posizioni non si guarda nemmeno: è l'elenco
        // ordinato a dire dove sta cosa. Non si cancella però, così spegnendo
        // l'automatismo si ritrova la scrivania com'era.
        if (icons.autoDisponi) {
            var ord = Files.sortEntries(lista, icons.ordine, icons.ordineDesc);
            for (var i = 0; i < ord.length; i++) {
                // Colonna piena, poi la successiva. Con più icone di quante ne
                // stiano, le ultime proseguono oltre il bordo destro — come su
                // ogni scrivania classica, e come lì si risolve togliendo roba.
                out[ord[i].name] = icons.puntoDiCella(
                        Math.floor(i / icons.righe), i % icons.righe);
            }
            return out;
        }

        var salvate = {};
        var fonti = [icons.posizioni || ({}), icons._appena || ({})];
        for (var f = 0; f < fonti.length; f++)
            for (var chiave in fonti[f])
                salvate[chiave] = fonti[f][chiave];
        var occupate = {};
        var senzaPosto = [];

        for (var k = 0; k < lista.length; k++) {
            var nome = lista[k].name;
            var p = salvate[nome];
            if (!p || p.length !== 2 || p[0] < 0 || p[1] < 0) {
                senzaPosto.push(nome);
                continue;
            }
            if (icons.allinea) {
                var cel = icons.cellaLibera(p[0], p[1], occupate);
                occupate[cel.x + "," + cel.y] = true;
                out[nome] = icons.puntoDiCella(cel.x, cel.y);
            } else {
                // Libere al pixel — ma la loro cella si segna occupata lo
                // stesso, o un file nuovo nascerebbe sotto un'icona che c'è
                // già solo perché quella non sta in griglia.
                var q = icons.cellaDiPunto(p[0], p[1]);
                occupate[q.x + "," + q.y] = true;
                out[nome] = Qt.point(p[0], p[1]);
            }
        }

        // Chi non ha un posto ricordato lo prende adesso, in ordine di elenco.
        // Una cella per icona: qui c'era il difetto per cui ognuna prendeva la
        // PRIMA libera — cioè la stessa — e si accatastavano tutte in alto a
        // sinistra.
        for (var n = 0; n < senzaPosto.length; n++) {
            var libera = icons.primaCellaLibera(occupate);
            occupate[libera.x + "," + libera.y] = true;
            out[senzaPosto[n]] = icons.puntoDiCella(libera.x, libera.y);
        }
        return out;
    }

    function postoPer(nome) {
        var p = icons.disposizione[nome];
        return p ? p : Qt.point(icons.bordo, icons.sopra);
    }

    /// Scrive un nuovo deposito di posizioni: subito qui (`_appena`) e al
    /// demone. La mappa si COPIA: quella che dà `Core.Ipc.get` è la sua, e
    /// cambiarla sul posto vorrebbe dire credere confermato quello che il
    /// demone non ha ancora visto.
    function _scrivi(m) {
        icons._appena = m;
        Core.Ipc.setSetting("files.desktopPositions", m);
    }

    /// Mette `nome` nel punto (x, y) — l'angolo dell'icona — SENZA muovere
    /// nessun'altra.
    ///
    /// ── Perché si fissa tutto ────────────────────────────────────────────
    ///
    /// Giacomo, 27 settembre 2026: spostando Stumble Guys a destra è sparita,
    /// spostando FORScan è ricomparsa a destra, e rimettendola a posto
    /// «ricompariva in automatico a destra ogni volta». Le posizioni erano
    /// pixel fuori griglia (FORScan [100, 35], Stumble Guys [63, 134]) e i
    /// conflitti si risolvevano a ogni ridisegno, nell'ordine dell'elenco:
    /// due icone nella stessa cella, e quale delle due si spostava lo
    /// decideva chi veniva prima. Qualunque cambiamento rimescolava tutto —
    /// riprodotto con la sua scrivania copiata in una prova: un trascinamento
    /// solo, e FORScan, The Big Catch e Tomba cambiavano posto.
    ///
    /// Adesso, a ogni mossa, la disposizione COM'È si scrive per intero, in
    /// celle esatte; l'icona mossa prende la cella libera più vicina al punto
    /// in cui è stata lasciata; le altre restano dove le si vede.
    function ricorda(nome, x, y) {
        var d = icons.disposizione;
        var m = {};
        var occupate = {};
        for (var altro in d) {
            if (altro === nome)
                continue;
            m[altro] = [Math.round(d[altro].x), Math.round(d[altro].y)];
            if (icons.allinea) {
                var c = icons.cellaDiPunto(d[altro].x, d[altro].y);
                occupate[c.x + "," + c.y] = true;
            }
        }
        // Chi non è sulla scrivania adesso (un file tolto) non si perde: se
        // torna, torna al suo posto.
        var prima = icons.posizioni || ({});
        for (var k in prima)
            if (m[k] === undefined && k !== nome)
                m[k] = prima[k];
        if (icons.allinea) {
            var libera = icons.cellaLibera(x, y, occupate);
            var punto = icons.puntoDiCella(libera.x, libera.y);
            m[nome] = [punto.x, punto.y];
        } else {
            m[nome] = [Math.round(x), Math.round(y)];
        }
        icons._scrivi(m);
    }

    /// Scrive nel deposito le posizioni che le icone hanno ADESSO.
    ///
    /// Serve a non perdere la disposizione quando si spegne l'automatismo: chi
    /// lo spegne vuole cominciare a spostare le icone, non vederle saltare
    /// tutte insieme dove stavano tre settimane fa.
    function fissaDisposizioneCorrente() {
        var m = JSON.parse(JSON.stringify(icons.posizioni || ({})));
        var d = icons.disposizione;
        for (var nome in d)
            m[nome] = [Math.round(d[nome].x), Math.round(d[nome].y)];
        icons._scrivi(m);
    }

    /// «Riordina adesso»: mette tutto in griglia nell'ordine scelto, e lo
    /// SCRIVE. Funziona anche a disposizione libera — anzi, è lì che serve —
    /// e da lì in poi le icone si possono spostare di nuovo a mano.
    function riordina() {
        var ord = Files.sortEntries(icons.entries || [], icons.ordine,
                                    icons.ordineDesc);
        var m = {};
        for (var i = 0; i < ord.length; i++) {
            var p = icons.puntoDiCella(Math.floor(i / icons.righe),
                                       i % icons.righe);
            m[ord[i].name] = [p.x, p.y];
        }
        icons._scrivi(m);
    }

    // ── Aprire ───────────────────────────────────────────────────────────

    function apri(voce) {
        if (!voce)
            return;
        if (voce.isDir) {
            // Le cartelle le apre la shell: è lei che sa far venire avanti
            // il gestore file già aperto invece di aprirne un secondo.
            icons.apriCartella(voce.path);
            return;
        }
        // Un launcher non si «apre»: si lancia. Il demone legge il .desktop
        // e ne esegue il comando, come per le voci del menu.
        if (icons.isLauncher(voce.name)) {
            Core.Ipc.launchDesktop(voce.path);
            return;
        }
        // Un file che si può eseguire fa fermare a chiedere, come nel gestore
        // file: la scrivania è il posto dove la gente tiene proprio gli script
        // che lancia spesso.
        if (icons.eseguibile(voce)) {
            icons.apriConRichiesto(voce.path, true);
            return;
        }
        Core.Ipc.openDefault([voce.path]);
    }

    /// Vero se la voce ha il permesso di esecuzione. `mode` arriva già
    /// nell'elenco (`rwxr-xr-x`) e per un pezzo non lo leggeva nessuno.
    function eseguibile(voce) {
        if (!voce || voce.isDir)
            return false;
        return String(voce.mode || "").indexOf("x") !== -1;
    }

    // ── «Con che cosa lo apro?» ──────────────────────────────────────────
    //
    // Qui prima non c'era NIENTE: `openDefault` partiva e la risposta
    // `needsChoice` non la ascoltava nessuno. Doppio clic su un file di tipo
    // sconosciuto, sulla scrivania, non faceva assolutamente niente — nemmeno
    // la finestra sbagliata che si apriva nel gestore file.

    /// «Con che cosa lo apro?» lo chiede la shell, non la scrivania.
    ///
    /// Il pannello stava QUI, ed era invisibile: il livello della scrivania sta
    /// in fondo a tutto (`hyprctl layers`: «Layer level 1 (bottom)»), quindi si
    /// disegnava dietro a ogni finestra aperta. Con lo schermo sgombro
    /// funzionava, ed è il motivo per cui è passato inosservato. Adesso vive in
    /// `shell.qml`, dentro una finestra di sovrapposizione vera.
    signal apriConRichiesto(string percorso, bool eseguibile)

    property var rendiEseguibile: Core.Exec {}

    /// Il `chmod +x`, chiesto dal pannello che ora sta nella shell.
    function rendiEseguibileOra(percorso) {
        icons.rendiEseguibile.shArgs('chmod +x -- "$1" 2>&1', [percorso]);
    }

    Connections {
        target: Core.Ipc
        function onFileResultReceived(result) {
            if (result.needsChoice !== true)
                return;
            var paths = result.paths || [];
            if (paths.length === 0)
                return;
            // Solo se il file è QUI: la scrivania e il gestore file ascoltano
            // lo stesso canale, e una finestrella che si apre sulla scrivania
            // per un file aperto altrove è una finestrella che nessuno ha
            // chiesto.
            for (var i = 0; i < icons.entries.length; i++) {
                if (icons.entries[i].path === paths[0]) {
                    icons.apriConRichiesto(
                        paths[0], icons.eseguibile(icons.entries[i]));
                    return;
                }
            }
        }
    }

    /// Come nel gestore file: si entra nella cartella dello script, e il
    /// terminale resta aperto a mostrare il codice d'uscita.
    function eseguiNelTerminale(percorso) {
        var term = Core.Ipc.get("launcher.defaultTerminal", "minerva-terminale");
        var it = Core.Strings.lang === "it";
        Quickshell.execDetached([
            term, "-e", "sh", "-c",
            'cd "$(dirname "$1")" || exit 1; "$1"; s=$?; echo; '
            + 'printf "%s %s — " "' + (it ? "uscita" : "exit") + '" "$s"; '
            + 'printf "%s" "' + (it ? "premi Invio" : "press Enter")
            + '"; read _',
            "sh", percorso]);
    }

    function isLauncher(nome) {
        return /\.desktop$/.test(String(nome || ""));
    }

    // ── Le mani ──────────────────────────────────────────────────────────
    //
    // ── PERCHÉ NON SI USA IL TRASCINAMENTO DI SISTEMA PER SPOSTARE ─────────
    //
    // Perché spostare un'icona sulla propria scrivania non è consegnare un
    // file a qualcun altro: è muovere una cosa dentro la finestra in cui sta
    // già. Il trascinamento di sistema (`Drag.Automatic`) invece è una
    // TRATTATIVA fra due programmi, e fatta per questo dava tre difetti
    // insieme — tutti e tre segnalati da Giacomo il 16 agosto 2026:
    //
    //  1. **l'icona non seguiva la mano.** `startDrag()` di Qt entra in un
    //     ciclo di eventi suo e non torna finché non si lascia: fra la presa e
    //     il rilascio non c'era nessun fotogramma in cui disegnare l'icona
    //     altrove. «Si sposta solo dopo averla rilasciata.»
    //  2. **niente da guardare.** Il fardello è un `Item` di un pixel senza
    //     figli: il compositore mostrava il puntatore e basta.
    //  3. **lo schermo diventava azzurrino.** Entrando nel `DropArea` della
    //     scrivania si accendeva la cornice «puoi lasciare qui», che è larga
    //     quanto tutto lo schermo — cioè identica all'anteprima dell'aggancio
    //     in alto che disegna il compositore. Stesso disegno, due significati.
    //
    // Adesso lo spostamento è un movimento e basta: si tiene dove sta il
    // puntatore, l'icona ci si disegna sotto, e al rilascio atterra. Nessun
    // ciclo di eventi, nessuna trattativa, nessun bersaglio da accendere.
    //
    // Il trascinamento di sistema resta per il caso in cui SERVE — portare un
    // file dentro un altro programma — e ci si passa nel momento in cui il
    // puntatore entra nella finestra di quel programma. Vedi `passaAlSistema`.

    /// Il nome dell'icona sotto la mano, o vuoto.
    property string preso: ""
    /// Vera quando la soglia è stata superata: da lì è un trascinamento e non
    /// un clic con la mano che trema.
    property bool inMano: false
    /// Dove sta il puntatore, in coordinate della scrivania.
    property real manoX: 0
    property real manoY: 0
    /// Dove, dentro l'icona, è stata afferrata.
    property real presaDx: 0
    property real presaDy: 0

    /// Vera dal momento in cui il gesto è passato al sistema. Serve a due
    /// cose, e senza tutte e due il gesto si sdoppia: a non consegnare due
    /// volte (il movimento arriva a ogni pixel, non una volta sola), e a non
    /// far atterrare l'icona sulla scrivania quando il rilascio arriva mentre
    /// la consegna è ancora in corso.
    property bool consegnato: false

    function lascia() {
        icons.preso = "";
        icons.inMano = false;
        icons.consegnato = false;
        // Il gesto di sistema finisce QUI e non un battito dopo essere
        // partito: `Drag.active` non blocca. La fotografia sotto il dito si
        // butta adesso, o si trascinerebbe un'icona invisibile.
        // NON si spegne `trascinando` qui: `lascia()` la chiamano il rilascio
        // e l'annullamento della `MouseArea`, e l'annullamento arriva proprio
        // perché il trascinamento di sistema è partito e le ha tolto la presa.
        // Spegnerlo da qui lo annullerebbe — vedi `files/Pane.qml`.
    }

    /// Posa l'icona: la memoria la aggiorna `spostaIcona`, che sa anche che
    /// cosa fare se la disposizione automatica è accesa.
    function posa(nome, x, y) {
        // `spostaIcona` ragiona sul PUNTATORE e centra da sé; qui l'angolo lo
        // conosciamo già, quindi si rifà il conto al contrario invece di
        // scrivere due volte la stessa regola.
        icons.spostaIcona(nome, x + icons.cellaW / 2, y + icons.riquadro / 2);
    }

    /// C'è una finestra di un altro programma sotto questo punto?
    ///
    /// La scrivania sta sotto tutto, quindi mentre si trascina il puntatore
    /// può passare sopra qualunque finestra senza che noi smettiamo di
    /// ricevere il movimento (la presa del mouse è nostra). Chi c'è sotto ce
    /// lo dice il compositore, che è l'unico a saperlo.
    function sopraUnaFinestra(x, y) {
        var lista = Core.Windows.all || [];
        var qui = Core.Compositore.scrivaniaAttiva;
        for (var i = 0; i < lista.length; i++) {
            var w = lista[i];
            if (w.minimized || w.w <= 0 || w.h <= 0)
                continue;
            // Solo la scrivania che si sta guardando: le finestre delle altre
            // hanno coordinate vere e sarebbero bersagli invisibili.
            if (qui !== undefined && w.workspace !== qui)
                continue;
            if (x >= w.x && x <= w.x + w.w && y >= w.y && y <= w.y + w.h)
                return true;
        }
        return false;
    }

    /// Da qui in poi il gesto lo gestisce il sistema: il file può finire nel
    /// gestore file, in un browser, in un programma di posta.
    ///
    /// L'immagine da mostrare sotto il puntatore si ricava fotografando
    /// l'icona stessa (`grabToImage`): senza, il compositore mostra il
    /// puntatore nudo e non si sa che cosa si sta portando in giro.
    /// `Drag.active` va acceso DENTRO la risposta, o si partirebbe con
    /// l'immagine non ancora pronta.
    function passaAlSistema(icona) {
        if (!icona || !icona.voce || icons.consegnato)
            return;
        icons.consegnato = true;
        fardello.percorsi = [icona.voce.path];
        // La fotografia si scatta PRIMA di lasciare la presa: mollandola
        // subito, l'icona tornerebbe nella sua cella per un fotogramma e la
        // foto ritrarrebbe una cella vuota.
        // La misura si dà QUI e non con `sourceSize` sull'immagine dopo: Qt
        // rifiuta di ridimensionare una fotografia presa così («Ignoring
        // sourceSize request for image url that came from grabToImage») e
        // lascia un avviso nel registro a ogni trascinamento. Il doppio dei
        // pixel perché sotto il puntatore la si guarda da vicino.
        icona.grabToImage(function (esito) {
            // L'esito va tenuto vivo finché dura il trascinamento: è un
            // oggetto con un ciclo di vita, non un indirizzo.
            fardello.fotografia = esito;
            fardello.Drag.imageSource = esito.url;
            // Si accende e basta: `Drag.active` NON blocca, misurato il
            // 7 settembre 2026 col registro alla mano. Spegnerlo subito dopo
            // annullava il trascinamento un battito dopo averlo acceso — vedi
            // il perché per esteso in `files/Pane.qml`.
            //
            // La fotografia sotto il dito resta viva finché dura il gesto, e
            // si butta quando finisce: buttarla qui vorrebbe dire trascinare
            // un'icona invisibile.
            icons.trascinando = true;
        }, Qt.size(icona.width * 2, icona.height * 2));
    }

    property bool trascinando: false

    Item {
        id: fardello
        width: 1
        height: 1
        property var percorsi: []
        /// La fotografia dell'icona, tenuta viva per la durata del gesto.
        property var fotografia: null

        Drag.active: icons.trascinando
        // L'unico che sa quando il gesto di sistema è finito davvero.
        Drag.onDragFinished: {
            icons.trascinando = false;
            fardello.fotografia = null;
        }
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
        Drag.mimeData: ({ "text/uri-list": fardello.uriList })

        readonly property string uriList: {
            var righe = [];
            for (var i = 0; i < fardello.percorsi.length; i++)
                righe.push("file://" + encodeURI(fardello.percorsi[i]));
            return righe.join("\r\n");
        }
    }

    signal apriCartella(string percorso)

    // ── Le icone ─────────────────────────────────────────────────────────

    Repeater {
        model: icons.entries

        delegate: Item {
            id: icona
            required property var modelData

            readonly property var voce: icona.modelData
            readonly property string nome: icona.voce ? icona.voce.name : ""
            readonly property bool selezionata: icons.selezione === nome
            readonly property bool siRinomina: icons.rinomina === nome

            /// Quello che si legge sotto l'icona.
            ///
            /// Per un `.desktop` è il nome del PROGRAMMA — «Steam», non
            /// `steam.desktop`. Un file .desktop non è un file: è il biglietto
            /// da visita di un programma, e mostrarne il nome del file è come
            /// stampare il codice a barre invece della copertina. Il nome
            /// arriva dal demone insieme all'elenco (vedi `_vestiILauncher`).
            readonly property string etichetta:
                (icona.voce && icona.voce.appName) ? icona.voce.appName
                                                   : icona.nome

            /// L'icona vera del programma, come immagine su disco. Vuota per
            /// tutto ciò che non è un launcher.
            readonly property string iconaApp:
                (icona.voce && icona.voce.appIcon) ? icona.voce.appIcon : ""

            /// La miniatura, per le immagini. Stessa levetta del gestore file:
            /// su una scrivania piena di fotografie su un disco lento ogni
            /// miniatura è una lettura.
            readonly property bool miniatura:
                icona.voce && !icona.voce.isDir
                && Files.isImage(icona.nome)
                && Core.Ipc.get("files.anteprime", true)

            /// In volo: la si sta trascinando adesso. Vedi «Le mani», più su.
            readonly property bool inVolo: icons.inMano && icons.preso === icona.nome

            width: icons.cellaW - 12
            height: icons.cellaH - 12

            // Mentre è in mano segue il puntatore al pixel, e non passa dalla
            // griglia: la griglia è dove ATTERRA, non dove vola.
            x: icona.inVolo ? icons.manoX - icons.presaDx : icons.postoPer(nome).x
            y: icona.inVolo ? icons.manoY - icons.presaDy : icons.postoPer(nome).y
            z: icona.inVolo ? 10 : 0
            scale: icona.inVolo ? 1.08 : 1
            opacity: icona.inVolo ? 0.85 : 1

            Behavior on scale { NumberAnimation { duration: Theme.Motion.instant } }
            Behavior on opacity { NumberAnimation { duration: Theme.Motion.instant } }

            // L'animazione dell'atterraggio, non del volo: seguire il
            // puntatore con un'animazione vuol dire seguirlo IN RITARDO, e
            // l'icona sembrerebbe legata al mouse con un elastico.
            Behavior on x { enabled: !icona.inVolo
                            NumberAnimation { duration: Theme.Motion.quick
                                              easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !icona.inVolo
                            NumberAnimation { duration: Theme.Motion.quick
                                              easing.type: Easing.OutCubic } }

            // Il fondo della selezione: l'icona scelta si vede da lontano.
            Rectangle {
                id: riquadro
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                width: icons.riquadro
                height: icons.riquadro
                radius: Theme.Effects.radiusSM
                color: icona.selezionata ? Qt.alpha(Theme.Colors.accent, 0.18)
                                         : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                // ── Tre modi di mostrare un file, in ordine di verità ──────
                //
                // L'icona del programma se è un launcher, la fotografia se è
                // una fotografia, il nostro tracciato per tutto il resto. Il
                // primo che c'è vince: sono sempre più specifici.

                Image {
                    anchors.centerIn: parent
                    width: icons.lato
                    height: icons.lato
                    visible: icona.iconaApp !== "" && status !== Image.Error
                    source: icona.iconaApp !== "" ? "file://" + icona.iconaApp : ""
                    fillMode: Image.PreserveAspectFit
                    // Senza `sourceSize` un SVG si rasterizza alla sua
                    // dimensione naturale e poi si scala: a icone piccole si
                    // vede la differenza fra nitido e molle.
                    sourceSize.width: Math.round(icons.lato * 2)
                    sourceSize.height: Math.round(icons.lato * 2)
                    smooth: true
                    mipmap: true
                    asynchronous: true
                    cache: true
                }

                Image {
                    id: provino
                    anchors.centerIn: parent
                    width: icons.riquadro - 10
                    height: icons.riquadro - 10
                    visible: icona.miniatura && status === Image.Ready
                    source: icona.miniatura ? Files.fileUrl(icona.voce.path) : ""
                    fillMode: Image.PreserveAspectCrop
                    clip: true
                    sourceSize.width: Math.round(icons.riquadro * 1.5)
                    sourceSize.height: Math.round(icons.riquadro * 1.5)
                    asynchronous: true
                    cache: true
                }

                Ui.Icon {
                    anchors.centerIn: parent
                    width: icons.lato
                    height: icons.lato
                    visible: icona.iconaApp === "" && !provino.visible
                    name: Files.iconFor(icona.voce)
                    color: icona.voce && icona.voce.isDir ? Theme.Colors.accent
                                                          : Theme.Colors.textFaint
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: riquadro.bottom
                anchors.topMargin: 3
                width: parent.width - 4
                horizontalAlignment: Text.AlignHCenter
                maximumLineCount: 2
                wrapMode: Text.Wrap
                elide: Text.ElideMiddle
                text: icona.etichetta
                color: icona.selezionata ? Theme.Colors.text
                                         : Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            // La rinomina: il nome diventa un campo, come sul desktop di
            // ogni ambiente. Chi preme Invio conferma, Esc lascia perdere.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                visible: icona.siRinomina
                width: Math.min(parent.width + 8, 140)
                height: 26
                radius: Theme.Effects.radiusXS
                color: Theme.Colors.sunken
                border.width: 1
                border.color: Qt.alpha(Theme.Colors.accent, 0.5)
                z: 3

                TextInput {
                    id: nomeNuovo
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    text: icona.nome
                    selectByMouse: true

                    function finisci(accetta) {
                        icons.rinomina = "";
                        if (!accetta)
                            return;
                        var nuovo = nomeNuovo.text.trim();
                        if (nuovo === "" || nuovo === icona.nome || nuovo.indexOf("/") !== -1)
                            return;
                        Core.Ipc.fsRename(icona.voce.path,
                                          Files.parentPath(icona.voce.path) + "/" + nuovo);
                    }

                    onAccepted: nomeNuovo.finisci(true)
                    Keys.onEscapePressed: nomeNuovo.finisci(false)
                }
            }

            MouseArea {
                id: presa
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                // Il gesto è nostro dal primo pixel: senza, un movimento
                // ampio finisce interpretato da qualcun altro a metà strada e
                // l'icona resta in aria.
                preventStealing: true

                property point partenza: Qt.point(0, 0)

                onPressed: function (m) {
                    icons.selezione = icona.nome;
                    presa.partenza = Qt.point(m.x, m.y);
                    if (m.button === Qt.RightButton) {
                        icons.menuSu(icona.nome, mapToGlobal(m.x, m.y));
                        return;
                    }
                    icons.preso = icona.nome;
                    // Il punto in cui l'icona è stata AFFERRATA. Senza, al
                    // primo movimento l'icona salta col suo angolo sotto il
                    // puntatore: si prende per il centro e scatta di mezza
                    // cella prima di cominciare a seguire la mano.
                    icons.presaDx = m.x;
                    icons.presaDy = m.y;
                }

                onPositionChanged: function (m) {
                    if (!pressed || icons.preso !== icona.nome)
                        return;
                    if (!icons.inMano
                        && Math.abs(m.x - presa.partenza.x) < 8
                        && Math.abs(m.y - presa.partenza.y) < 8)
                        return;
                    icons.inMano = true;
                    var p = mapToItem(icons, m.x, m.y);
                    icons.manoX = p.x;
                    icons.manoY = p.y;
                    // Passata sopra la finestra di un altro programma: da lì
                    // in poi il gesto non è più nostro. Vedi `passaAlSistema`.
                    if (icons.sopraUnaFinestra(p.x, p.y))
                        icons.passaAlSistema(icona);
                }

                onReleased: function (m) {
                    if (icons.preso !== icona.nome || icons.consegnato)
                        return;
                    if (icons.inMano) {
                        // Si posa dove sta l'icona, non dove sta il puntatore:
                        // sono due punti diversi di mezza cella, ed è quello
                        // che si sta guardando a dover atterrare.
                        icons.posa(icona.nome,
                                   icons.manoX - icons.presaDx,
                                   icons.manoY - icons.presaDy);
                    }
                    icons.lascia();
                }

                // Il gesto interrotto da fuori — un pannello che si apre, la
                // sessione che si blocca — non deve lasciare un'icona in volo
                // per sempre.
                onCanceled: {
                    if (!icons.consegnato)
                        icons.lascia();
                }

                onDoubleClicked: icons.apri(icona.voce)
            }
        }
    }

    // ── Lasciare DENTRO la scrivania ─────────────────────────────────────
    //
    // Due casi, riconosciuti da chi trascina: le nostre icone si SPOSTANO —
    // il posto nuovo si ricorda — ; i file che arrivano da fuori — il gestore
    // file, Dolphin, il browser — passano alla shell, che chiede se copiare
    // o spostare. È la stessa domanda del gestore file, e per lo stesso
    // motivo: il gesto è identico per due esiti molto diversi.

    property bool bersaglio: false

    signal ricevuti(var urls, int x, int y)

    DropArea {
        anchors.fill: parent
        keys: ["minerva/file", "text/uri-list"]

        onEntered: icons.bersaglio = true
        onExited: icons.bersaglio = false
        onDropped: function (d) {
            icons.bersaglio = false;
            if (d.source && d.source === fardello && fardello.percorsi.length === 1) {
                // Un'icona nostra, lasciata dentro la scrivania: si sposta.
                var nome = Files.baseName(fardello.percorsi[0]);
                fardello.percorsi = [];
                icons.spostaIcona(nome, d.x, d.y);
                d.accept();
                return;
            }
            var urls = d.urls || [];
            if (urls.length > 0)
                icons.ricevuti(urls, Math.round(d.x), Math.round(d.y));
            d.accept();
        }
    }

    /// Mette un'icona dove è stata lasciata.
    ///
    /// Il punto è quello del PUNTATORE, e l'icona va centrata su di esso: il
    /// trascinamento di sistema non conserva il punto in cui l'icona era stata
    /// afferrata, quindi l'unica ipotesi onesta è «al centro della mano».
    ///
    /// A disposizione automatica non c'è un posto da ricordare — è l'ordine a
    /// decidere. Invece di non fare niente in silenzio, l'automatismo si
    /// SPEGNE e la scrivania resta esattamente com'era: chi trascina un'icona
    /// sta chiedendo di poterle spostare, e questa è la risposta a quella
    /// domanda. Il menu del tasto destro lo dice, e da lì si riaccende.
    function spostaIcona(nome, px, py) {
        if (icons.autoDisponi) {
            icons.fissaDisposizioneCorrente();
            Core.Ipc.setSetting("desktop.iconAutoArrange", false);
        }
        icons.ricorda(nome, px - icons.cellaW / 2, py - icons.riquadro / 2);
    }

    // ── «Puoi lasciare qui», detto senza imitare nessuno ─────────────────
    //
    // Qui c'era una cornice larga quanto tutto lo schermo, due pixel color
    // accento, angoli arrotondati. È esattamente il disegno con cui il
    // compositore annuncia l'aggancio in alto, cioè «questa finestra diventa
    // grande così»: trascinando un'icona lo schermo si accendeva tutto e
    // sembrava di stare per ingrandire qualcosa. Giacomo, 16 agosto: «lo
    // schermo diventa tutto azzurrino come se volessi passare una finestra a
    // schermo intero».
    //
    // Due disegni identici per due significati diversi non si distinguono
    // studiandoli: si distinguono cambiandone uno. Questa pastiglia dice la
    // stessa cosa con le parole, e non somiglia a niente altro.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: icons.sotto + Theme.Effects.space5

        width: quiDentro.implicitWidth + Theme.Effects.space5 * 2
        height: 38
        radius: Theme.Effects.radiusFull
        color: Theme.Colors.membrane
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edgeAccent

        visible: opacity > 0
        opacity: icons.bersaglio ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.Motion.instant } }

        Text {
            id: quiDentro
            anchors.centerIn: parent
            text: icons.it ? "Rilascia qui per metterlo sulla Scrivania"
                           : "Drop here to put it on the Desktop"
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    /// L'icona selezionata, per nome. Una sola per tutta la scrivania.
    property string selezione: ""

    /// Il menu su un'icona: lo chiede alla shell, che ha il ContextMenu.
    signal menuSu(string nome, point dove)

    /// «Questo file è una fotografia?»
    ///
    /// Esiste per `shell.qml`, che costruisce il menu del tasto destro ma non
    /// importa il modulo del gestore file: gli import di QML non si ereditano,
    /// e tirarsi dentro tutto `files/` per una riga sarebbe un modulo intero
    /// caricato per una domanda.
    function eImmagine(nome) {
        return Files.isImage(nome);
    }

    function voceSelezionata() {
        for (var i = 0; i < icons.entries.length; i++)
            if (icons.entries[i].name === icons.selezione)
                return icons.entries[i];
        return null;
    }

    function iniziaRinomina() {
        if (icons.selezione !== "")
            icons.rinomina = icons.selezione;
    }

    function cestina() {
        var v = icons.voceSelezionata();
        if (v)
            Core.Ipc.fsTrash([v.path]);
    }

    function elimina() {
        var v = icons.voceSelezionata();
        if (v)
            Core.Ipc.fsDelete([v.path]);
    }

    function copiaPercorso() {
        var v = icons.voceSelezionata();
        if (v)
            Quickshell.clipboardText = v.path;
    }

    // ── Le voci del menu «Disposizione icone» ────────────────────────────
    //
    // Stanno qui e non nella shell perché è qui che si sa che cosa è acceso
    // adesso: un menu di scelte che non mostra quella corrente costringe a
    // provare per scoprirlo. La spunta è l'icona `check` sulla riga attiva —
    // le altre righe lasciano il posto vuoto, così restano incolonnate.
    function vociDisposizione() {
        var it = icons.it;
        function segno(acceso) { return acceso ? "check" : ""; }

        var voci = [
            { "label": it ? "Disposizione automatica" : "Auto arrange",
              "icon": segno(icons.autoDisponi), "action": "auto" },
            { "label": it ? "Allinea alla griglia" : "Align to grid",
              "icon": segno(icons.allinea && !icons.autoDisponi),
              "action": "allinea" },
            { "label": it ? "Riordina adesso" : "Clean up now",
              "icon": "sort", "action": "riordina" },
            { "separator": true },
            { "label": it ? "Ordina per nome" : "Sort by name",
              "icon": segno(icons.ordine === "name"), "action": "ord:name" },
            { "label": it ? "Ordina per tipo" : "Sort by type",
              "icon": segno(icons.ordine === "type"), "action": "ord:type" },
            { "label": it ? "Ordina per dimensione" : "Sort by size",
              "icon": segno(icons.ordine === "size"), "action": "ord:size" },
            { "label": it ? "Ordina per data" : "Sort by date",
              "icon": segno(icons.ordine === "modified"), "action": "ord:modified" },
            { "label": it ? "Ordine inverso" : "Reversed",
              "icon": segno(icons.ordineDesc), "action": "inverti" },
            { "separator": true },
            { "label": it ? "Icone piccole" : "Small icons",
              "icon": segno(icons.lato <= 34), "action": "lato:34" },
            { "label": it ? "Icone medie" : "Medium icons",
              "icon": segno(icons.lato > 34 && icons.lato < 64), "action": "lato:46" },
            { "label": it ? "Icone grandi" : "Large icons",
              "icon": segno(icons.lato >= 64), "action": "lato:64" }
        ];
        return voci;
    }

    /// Esegue una voce di quel menu. Anche questo sta qui: la shell non deve
    /// conoscere i nomi delle impostazioni delle icone per poterle mostrare.
    function eseguiDisposizione(azione) {
        if (azione === "auto") {
            var acceso = !icons.autoDisponi;
            // Spegnendolo si tiene la disposizione che si sta guardando,
            // invece di far saltare tutto alle posizioni di prima.
            if (!acceso)
                icons.fissaDisposizioneCorrente();
            Core.Ipc.setSetting("desktop.iconAutoArrange", acceso);
            return;
        }
        if (azione === "allinea") {
            // Spegnere l'allineamento su icone che stanno in griglia le
            // lascia dove sono, e da lì si muovono al pixel: ma solo se le
            // posizioni in griglia sono state SCRITTE, o si tornerebbe ai
            // pixel disordinati di prima.
            if (icons.allinea)
                icons.fissaDisposizioneCorrente();
            Core.Ipc.setSetting("desktop.iconSnap", !icons.allinea);
            return;
        }
        if (azione === "riordina") {
            icons.riordina();
            return;
        }
        if (azione === "inverti") {
            Core.Ipc.setSetting("desktop.iconSortDesc", !icons.ordineDesc);
            // A disposizione libera l'ordine non sposta niente da solo: chi
            // lo cambia sta chiedendo di VEDERE l'effetto, non di impostare
            // una preferenza per il futuro. Si può riordinare nella riga
            // successiva perché `setSetting` aggiorna la copia locale prima
            // di scrivere al demone — senza quello, si ordinerebbe col valore
            // vecchio e il comando sembrerebbe non aver fatto niente.
            if (!icons.autoDisponi)
                icons.riordina();
            return;
        }
        if (azione.indexOf("ord:") === 0) {
            Core.Ipc.setSetting("desktop.iconSort", azione.substring(4));
            if (!icons.autoDisponi)
                icons.riordina();
            return;
        }
        if (azione.indexOf("lato:") === 0) {
            Core.Ipc.setSetting("desktop.iconSize", parseInt(azione.substring(5)));
            return;
        }
    }

    // Il clic sul VUOTO della scrivania toglie la selezione.
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: icons.selezione = ""
    }
}

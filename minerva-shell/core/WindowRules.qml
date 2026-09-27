import QtQuick
import "." as Core
import "../theme" as Theme

// WindowRules — Le regole del compositore che dipendono dalle Impostazioni.
//
// Due cose che Hyprland deve sapere e che non può indovinare:
//
//  · quanto spazio lasciare LIBERO sopra ogni finestra, perché è lì che la
//    shell disegna la barra del titolo. Senza questo margine la barra
//    coprirebbe il contenuto del programma, ed è la differenza fra una
//    cornice e un adesivo;
//
//  · che ogni finestra nuova nasca LIBERA. Hyprland nasce affiancando, e
//    l'affiancamento va tolto a ognuna appena compare — non c'è un
//    interruttore che lo spenga una volta per tutte.
//
// ── PERCHÉ NON SI CHIAMA MAI `hyprctl reload` ────────────────────────────
//
// Perché su questa configurazione rileggere l'intero file fa ripartire gli
// `exec-once`, e gli `exec-once` di Minerva avviano la shell e il demone. Un
// «ricarica» innocente si porterebbe dietro una seconda shell e un secondo
// demone che si contendono lo stesso socket, e da lì non si torna indietro
// senza uscire dalla sessione.
//
// Quindi due strade separate:
//
//  · SUBITO, senza rileggere niente: `hyprctl keyword`, una impostazione per
//    volta. È il modo giusto di cambiare qualcosa in un compositore che sta
//    già girando.
//
//  · PER LA PROSSIMA VOLTA: il file `minerva-windows.conf`, che Hyprland legge
//    all'avvio. Serve perché al login i margini devono essere già giusti prima
//    ancora che la shell parta, altrimenti le prime finestre nascono senza
//    posto per la loro barra.
QtObject {
    id: rules

    property bool titleBars: true
    property int titleHeight: 34

    // ── Le finestre sono LIBERE. Tutte. Sempre. ──────────────────────────
    //
    // Qui c'erano due modi, «affiancate» e «libere», con una scorciatoia per
    // passare dall'uno all'altro. Sulla carta era la cosa giusta: il tiling è
    // comodissimo per chi lo conosce, e Hyprland nasce così.
    //
    // In pratica non ha mai funzionato bene, e il difetto era strutturale.
    // Una finestra può diventare libera in cinque modi diversi — la
    // scorciatoia del modo, `Super+T` su una sola finestra, una regola per i
    // dialoghi, un trascinamento dalla barra del titolo, una app che si
    // dichiara tale — e nessuno di quei cinque sapeva degli altri. Il
    // risultato sullo schermo era un miscuglio dei due modi che nessuna
    // impostazione sembrava spiegare, e trovare quale dei cinque avesse
    // agito significava indovinare. Parole di Giacomo, due volte a distanza
    // di ore: «non ho capito perché a volte le finestre sono in modalità
    // tiling, a volte modalità libera», poi «deve scomparire completamente il
    // tiling delle finestre non lo voglio più».
    //
    // Un modo solo non è una rinuncia: è ciò che rende prevedibile tutto il
    // resto. Ogni finestra è libera, sta dove la si mette, e l'ordine di
    // sovrapposizione è quello dei fuochi — che è anche l'unica ipotesi su
    // cui si regge il calcolo di chi copre chi delle barre del titolo.

    /// Rimette libere tutte le finestre aperte.
    ///
    /// Si saltano le ridotte a icona: vivono in una scrivania nascosta, e
    /// toccarle le farebbe ricomparire addosso a chi non le ha chieste.
    function liberaTutte() {
        var all = Core.Windows.all || [];
        for (var i = 0; i < all.length; i++) {
            var w = all[i];
            if (!w.address || w.address === "" || w.minimized || w.floating)
                continue;
            Compositore.libera(w.address);
        }
        Core.Windows.refresh();
    }

    // Anche all'avvio, e non solo per le finestre nuove: una finestra rimasta
    // affiancata dalla sessione prima resterebbe tale per sempre.
    //
    // Il ritardo serve perché all'avvio l'elenco delle finestre non è ancora
    // stato letto: chiedere subito vorrebbe dire agire su uno schermo vuoto.
    property Timer _atStart: Timer {
        interval: 2500
        running: true
        onTriggered: {
            Core.Windows.refresh();
            riallinea.restart();
        }
    }

    property Timer _riallinea: Timer {
        id: riallinea
        interval: 400
        onTriggered: rules.liberaTutte()
    }

    // ── La cornice delle finestre ────────────────────────────────────────
    //
    // La disegna Hyprland, non noi: è l'unica parte della finestra che sta
    // fuori dal programma e sotto il compositore. Ma il COLORE lo decidiamo
    // qui, e deve essere lo stesso accento del resto di Minerva.
    //
    // Non è cosmesi. La barra del titolo che disegniamo noi e la cornice che
    // disegna Hyprland si toccano: se sono di due colori diversi, il punto in
    // cui si incontrano diventa una riga che taglia in due l'oggetto, e la
    // finestra torna a leggersi come «un programma con un cappello sopra».
    // Era un gradiente ciano-viola fisso, scritto in `hyprland.conf`; adesso
    // segue il colore scelto nelle Impostazioni.

    /// Da un colore QML alla forma del verbo `bordo` del compositore:
    /// `rgba(RRGGBBAA)`.
    function rgbaEsa(c, alpha) {
        function due(v) {
            var s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16);
            return s.length < 2 ? "0" + s : s;
        }
        return "rgba(" + due(c.r) + due(c.g) + due(c.b) + due(alpha) + ")";
    }

    readonly property string borderActive: rules.rgbaEsa(Theme.Colors.accent, 0.95)

    /// La cornice di una finestra che non ha il fuoco è una velatura, e come
    /// tutte le velature deve andare NEL VERSO del tema: bianca su fondo
    /// scuro, nera su fondo chiaro. Qui era `rgba(1,1,1,0.13)` scritto a
    /// mano, e sul tema chiaro sarebbe stato un bianco su bianco — cioè
    /// nessuna cornice, e nessun modo di vedere dove finisce una finestra
    /// appoggiata su un'altra.
    readonly property string borderInactive:
        rules.rgbaEsa(Theme.Colors.scura ? Qt.rgba(1, 1, 1, 1)
                                           : Qt.rgba(0, 0, 0, 1),
                        Theme.Colors.scura ? 0.13 : 0.16)

    // ── La cornice attorno alla finestra attiva ──────────────────────────
    //
    // «spento» (come nasce), «fisso» (la tinta dell'accento) o «gira» (la
    // striscia LED: la tinta fa il giro dello spettro). Il colore lo prende
    // dall'accento, e non è una manopola in meno per pigrizia: una cornice di
    // un colore e un accento di un altro sono due segni che dicono «questa è
    // quella attiva» litigando fra loro.
    //
    // Il giro lo fa il COMPOSITORE. Da qui parte un messaggio quando si
    // cambia idea, non dodici al secondo.
    property string cornice: "spento"

    /// Quanto è spesso il bordo colorato, in pixel. Il compositore lo tiene
    /// fra 1 e 20: sopra non è più un bordo, è una seconda finestra intorno
    /// alla finestra — e sarebbe anche una banda in cui il clic non arriva
    /// più al programma, perché la presa per ridimensionare lo segue.
    property int corniceSpessore: 6

    /// I colori che si alternano girando. Vuoto è lo spettro intero.
    property var corniceTinte: []

    /// Quanto è accesa la cornice sulle finestre che non hanno il fuoco.
    /// Zero: solo quella attiva.
    property real corniceSpente: 0
    /// Millisecondi per un giro intero. Il compositore rifiuta sotto i due
    /// secondi: più veloce non è un colore che gira, è un lampeggio.
    property int cornicePeriodo: 8000

    /// ── Quanto tremano le finestre ───────────────────────────────────────
    ///
    /// Zero spento. Trascinando, la finestra resta indietro rispetto al dito
    /// e al rilascio rimbalza. Il conto lo fa il compositore, in `molla.c`:
    /// da qui parte un numero quando si cambia idea, non centoventicinque
    /// messaggi al secondo.
    property real elastico: 0
    /// Le finestre che nascono come una goccia e si riducono con un
    /// risucchio (il «respiro», nel compositore). Segue l'interruttore delle
    /// animazioni: chi le spegne — anche perché il movimento gli fa male —
    /// non deve ritrovarselo.
    property bool respiro: true
    property real rigidita: 1
    property real smorzamento: 0.42
    property real blurIntensita: 50

    /// Margine fra le finestre, ai lati e in basso.
    // `gap` e `gapOut` restano come NUMERI e non come manopola: li legge
    // ancora chi disegna, e il file di configurazione non li offre più.
    property int gap: 5
    /// Margine attorno al gruppo, contro i bordi dello schermo.
    property int gapOut: 12

    // ── Sfocatura ────────────────────────────────────────────────────────
    //
    // Le finestre di Minerva sono trasparenti: barra, dock, pannelli, gestore
    // file e Impostazioni lasciano vedere quello che hanno dietro. Senza
    // sfocatura quel «dietro» è testo di altri programmi che passa attraverso
    // il nostro, e diventa tutto illeggibile; con troppa sfocatura la scheda
    // grafica lavora a ogni pixel che si muove.
    //
    // Quanta sfocatura sia giusta dipende dallo sfondo, dal monitor e dagli
    // occhi di chi guarda: non è una cosa che si possa decidere una volta per
    // tutti. Quattro scatti, dal niente al molto.
    //
    // Vale per TUTTE le finestre e non solo per le nostre, perché Hyprland la
    // sfocatura la sa fare a livello di compositore e non di finestra: si può
    // togliere a una finestra (`noblur`), non regolarla diversamente per una.
    // In pratica si vede quasi solo sulle nostre, che sono le uniche
    // trasparenti.
    // ── Qui c'erano i quattro scatti della sfocatura ─────────────────────
    //
    // `blurLevel` da 0 a 3, e una tabella di `{enabled, size, passes}` che si
    // mandava a Hyprland. Sotto minerva-wayland non arrivava da nessuna parte:
    // `Compositore.sfocatura()` è un buco. Restava un'impostazione visibile nel
    // pannello che si poteva cambiare senza che cambiasse niente — il difetto
    // che questo progetto si è messo per iscritto di non commettere.
    //
    // Al suo posto c'è `effetto`, che il nostro compositore capisce davvero.
    // Quando ci sarà il blur vero entrerà come terzo valore di QUESTA
    // proprietà: sarà un passaggio di rendering dentro il compositore, non
    // tre numeri da mandare a qualcun altro, quindi quella tabella non
    // servirebbe comunque.

    /// «nessuno» o «vetro». Col vetro il compositore mette UNA trasparenza su
    /// tutto l'albero della finestra — barra e contenuto insieme — invece di
    /// due attaccate con una linea in mezzo.
    property string effetto: "nessuno"
    property real effettoOpacita: 0.88

    // ── Qui c'erano `topGap`, `gapsIn` e `gapsOut`, ed erano una strada morta
    //
    // I margini valevano solo per le finestre AFFIANCATE, e restavano
    // «perché Hyprland può affiancarne una per conto suo». Hyprland non c'è
    // più dal 2 settembre 2026, e il nostro compositore risponde
    // `«margini» non ha una strada` — lo scrive nel registro a ogni avvio.
    //
    // Restava quindi una manopola (`windows.gap`) che si poteva scrivere nel
    // file, che tre proprietà calcolavano, che un verbo mandava, e che non
    // cambiava un pixel. Il banco delle manopole l'ha vista per quello che è:
    // «windows.gap 1 → 3, non muove, 0,000 %».
    //
    // Lo spazio sopra le finestre libere lo mette `abbassa()` in
    // `spine/TitleBars.qml`, che è dove è sempre stato per davvero.

    // ── Applicazione immediata ───────────────────────────────────────────

    // Erano `onBlurLevelChanged`. `blurLevel` non esiste più (vedi il blocco
    // sopra), e un gestore per una proprietà che non c'è è un errore che QML
    // segnala solo caricando il file: cambiare l'effetto non sarebbe arrivato
    // al compositore, e nemmeno il resto di questi.
    onEffettoChanged: applySoon.restart()
    onElasticoChanged: applySoon.restart()
    onRespiroChanged: applySoon.restart()
    onRigiditaChanged: applySoon.restart()
    onSmorzamentoChanged: applySoon.restart()
    onBlurIntensitaChanged: applySoon.restart()
    onEffettoOpacitaChanged: applySoon.restart()
    onBorderActiveChanged: applySoon.restart()
    // Anche quella spenta, e non è pignoleria: passando da un tema scuro a
    // uno chiaro senza toccare l'accento, `borderActive` non cambia — cambia
    // solo questa. Senza la riga, le finestre in secondo piano restavano
    // orlate di bianco su un fondo bianco, cioè senza cornice.
    onBorderInactiveChanged: applySoon.restart()
    onCorniceChanged: applySoon.restart()
    onCornicePeriodoChanged: applySoon.restart()
    onCorniceSpessoreChanged: applySoon.restart()
    onCorniceTinteChanged: applySoon.restart()
    onCorniceSpenteChanged: applySoon.restart()
    Component.onCompleted: applySoon.restart()

    property Timer _applySoon: Timer {
        id: applySoon
        // Le impostazioni arrivano dal demone una alla volta: si aspetta che
        // abbiano finito invece di riscrivere a ogni singolo valore.
        interval: 500
        onTriggered: rules.write()
    }

    // ── Finestre libere: questa è la RETE, non la regola ─────────────────
    //
    // La regola vera sta nella configurazione — `windowrule { name =
    // tutte-libere; match:class = .*; float = true }` — e non va tolta mai.
    // Quello che si fa qui è dirlo una seconda volta a ogni finestra che
    // nasce, per quelle che alla regola sfuggono.
    //
    // Il commento che stava qui diceva «non con una `windowrule`», e mandava
    // a cercare una regola che invece c'è: la ragione era vera quando
    // esistevano i due modi («affiancate» e «libere») e bisognava poterli
    // commutare al volo senza rileggere tutta la configurazione. Quei due modi
    // non ci sono più, quindi la ragione è scaduta ma il codice resta utile —
    // cambia solo il suo NOME: da regola a rete.
    //
    // Costa un messaggio per finestra aperta, e per le finestre che la regola
    // ha già liberato non costa niente: `liberaTutte` salta quelle già
    // libere.

    property Connections _newWindows: Connections {
        target: Compositore
        function onEvento(nome, dati) {
            if (nome !== "openwindow")
                return;
            // openwindow>>INDIRIZZO,scrivania,classe,titolo — l'indirizzo
            // arriva senza il prefisso `0x`, che i comandi invece vogliono.
            var addr = String(dati || "").split(",")[0].trim();
            if (addr === "")
                return;
            var sel = "address:0x" + addr.replace(/^0x/, "");
            Compositore.libera(sel);
            // Le finestre che nascono grandi come un francobollo: vedi
            // `_nateMinuscole`. Si guarda dopo, non adesso: nell'istante in
            // cui l'evento arriva il programma non ha ancora detto quanto è
            // grande, e si leggerebbe zero.
            rules._daGuardare = sel;
            rules._guarda.restart();
        }
    }

    // ── Le finestre che nascono grandi come un francobollo ───────────────
    //
    // Konsole si apre a 263×100 pixel. Ogni volta, misurato. Non è un capriccio
    // suo: è un programma KDE, abituato a un compositore che gli sceglie una
    // dimensione quando lui non ne chiede una sensata. Hyprland invece gli dà
    // quello che chiede, e quello che chiede è quasi niente.
    //
    // Parole di Giacomo: «konsole quando lo avvio si avvia sempre piccolissimo
    // e devo sempre ridimensionarlo o passarlo a schermo intero».
    //
    // La regola è generale e non una toppa su Konsole: QUALUNQUE finestra che
    // nasce sotto una certa misura viene portata a una dimensione decente e
    // centrata. Una finestra di trecento pixel per centottanta non è una
    // scelta di nessuno — è un programma che non ha saputo dirlo.
    //
    // La soglia è bassa apposta. Ci sono finestrelle legittime — una richiesta
    // di password, un contagocce — e quelle stanno sopra: sotto i 300×180 non
    // ci sta nemmeno una riga di testo con un pulsante.
    readonly property int minimaLarghezza: 300
    readonly property int minimaAltezza: 180

    property string _daGuardare: ""

    property Timer _guarda: Timer {
        // Mezzo secondo: il tempo che un programma ci mette a dire quanto è
        // grande dopo essersi mostrato. Chiedendolo subito si legge zero, e
        // si finirebbe per ingrandire ogni finestra del mondo.
        interval: 500
        onTriggered: {
            var sel = rules._daGuardare;
            rules._daGuardare = "";
            if (sel === "")
                return;
            var w = Core.Windows.find(sel);
            if (!w || w.minimized || w.modoSchermo !== 0)
                return;

            // ── Nata CENTRATA da una regola ───────────────────────────────
            //
            // `center = true` nella configurazione centra la finestra, e la
            // barra del titolo di Minerva sta FUORI da lei, SOPRA: il blocco
            // che si vede sporge in alto, e il suo centro sale di mezza barra.
            // Ventun pixel più in ALTO, misurati il 12 agosto 2026 su
            // pavucontrol — non si notano in una schermata, si notano in un
            // dialogo che si apre cento volte al giorno sempre un po' alto.
            //
            // Come si riconosce che è stata una REGOLA: alla nascita, il
            // centro coincide col centro dello spazio utile al pixel. Un
            // programma che sceglie da sé esattamente quel punto non esiste;
            // e se esistesse, spostarlo di ventun pixel gli farebbe ottenere
            // proprio quello che voleva.
            //
            // Il posto giusto sarebbe il plugin, che agisce PRIMA del primo
            // fotogramma e non fa saltare niente. Qui si vede un piccolo
            // scatto: è la stessa scelta già fatta per le finestre nate
            // minuscole — il plugin lo fa bene, questa è la rete.
            if (rules._eraCentrata(w))
                Core.Windows.centra(w.address);

            if (w.w >= rules.minimaLarghezza && w.h >= rules.minimaAltezza)
                return;

            var u = Core.Windows.spazioPer(w) || Core.Windows.usable;
            if (!u)
                return;
            // Sei decimi dello spazio, con un minimo che resta usabile anche
            // su uno schermo piccolo.
            var nw = Math.max(800, Math.round(u.w * 0.6));
            var nh = Math.max(520, Math.round(u.h * 0.6));
            nw = Math.min(nw, u.w - 40);
            nh = Math.min(nh, u.h - 40);
            var nx = Math.round(u.x + (u.w - nw) / 2);
            var ny = Math.round(u.y + (u.h - nh) / 2);
            console.log("[MINERVA][FINESTRE] " + (w.appClass || "?")
                        + " è nata " + w.w + "×" + w.h
                        + ": la porto a " + nw + "×" + nh + ".");
            Compositore.ridimensiona(sel, nw, nh);
            Compositore.sposta(sel, nx, ny);
        }
    }

    /// Vero quando il centro della finestra coincide, al pixel, con quello
    /// dello spazio utile: alla nascita vuol dire che l'ha centrata una regola.
    ///
    /// Due pixel di tolleranza: lo schermo è ingrandito di un quarto, e fra
    /// pixel logici e fisici gli arrotondamenti non tornano sempre.
    function _eraCentrata(w) {
        if (!w || Core.Windows.barSopra(w) <= 0)
            return false;
        var u = Core.Windows.spazioPer(w) || Core.Windows.usable;
        if (!u)
            return false;
        return Math.abs((w.x + w.w / 2) - (u.x + u.w / 2)) <= 2
            && Math.abs((w.y + w.h / 2) - (u.y + u.h / 2)) <= 2;
    }

    // ── Qui c'era `conf` e il file di Hyprland ───────────────────────────
    //
    // Costruiva `~/.config/hypr/minerva-windows.conf` — margini, colori del
    // bordo, sfocatura — e lo faceva includere da `minerva-user.conf`, perché
    // Hyprland lo leggesse all'avvio: al login i margini devono essere giusti
    // PRIMA che la shell parta, o le prime finestre nascono senza posto per la
    // loro barra.
    //
    // Hyprland non c'è più dal 2 settembre 2026. Quel file non lo legge
    // nessuno: restava una `sh` lanciata a ogni cambio di impostazione per
    // scrivere un documento a cui non risponde niente, e — peggio — una
    // seconda sorgente di verità per margini e colori. Due sorgenti divergono
    // sempre, e questa divergeva già: il compositore prendeva i valori dal
    // canale, il file quelli di prima.
    //
    // La ragione per cui esisteva vale ancora, e adesso ha una risposta
    // migliore: minerva-wayland riceve tutto dal canale appena la shell si
    // collega, e finché non è collegata usa i suoi valori di partenza — che
    // sono gli stessi. Stessa scelta già presa in `sections/Power.qml`, dove
    // `writeLid()` scriveva `minerva-lid.conf`.

    /// Applica subito e lascia scritto per la prossima volta, in un colpo solo.
    ///
    /// `hyprctl keyword` e non `Hyprland.dispatch`: `dispatch` manda un
    /// COMANDO al compositore (sposta, chiudi, affianca), mentre `keyword`
    /// cambia una IMPOSTAZIONE. Passare l'uno per l'altro non dà errore, non
    /// fa niente, e si scopre solo andando a rileggere il valore.
    function write() {
        // ── Le regole delle finestre le manda la SCRIVANIA, non ogni app ──
        //
        // Questo file sta dentro ogni nostra applicazione, e
        // `Component.onCompleted` lo fa partire in tutte. Fino al 31 agosto
        // 2026 il risultato era che aprire il gestore file:
        //
        //   * rimandava al compositore margini, colori e sfocatura di TUTTA
        //     la sessione — impostazioni che non sono affare di una finestra;
        //   * lanciava una shell per riscrivere
        //     `~/.config/hypr/minerva-windows.conf`, a ogni apertura di ogni
        //     app;
        //   * e dal giorno in cui è arrivato un verbo nuovo, stampava
        //     «no verbo «aspetto» sconosciuto» finché il compositore non
        //     veniva riavviato — che è il modo in cui il difetto si è visto.
        //
        // Le regole restano LEGGIBILI da tutti (le barre del titolo ne hanno
        // bisogno): quello che si limita è chi le SCRIVE.
        if (!Compositore.scrivania)
            return;
        Compositore.coloriBordo(rules.borderActive, rules.borderInactive);
        Compositore.effetto(rules.effetto, rules.effettoOpacita);
        Compositore.cornice(rules.cornice, rules.cornicePeriodo,
                            Theme.Colors.accent, rules.corniceSpessore);
        Compositore.corniceColori(rules.corniceTinte);
        Compositore.corniceSpente(rules.corniceSpente);
        Compositore.elastico(rules.elastico);
        Compositore.respiro(rules.respiro);
        Compositore.parametriEffetti(rules.blurIntensita, rules.rigidita, rules.smorzamento);
    }
}

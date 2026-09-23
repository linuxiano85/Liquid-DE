import QtQuick
import Quickshell
import "core" as Core

// ProveMedia — Le prove del lettore: quale, fra quelli aperti, prende i tasti.
//
//     qs -p minerva-shell/prove-media.qml
//
// ── Perché proprio questa parte ────────────────────────────────────────────
//
// Perché è l'unica che può sbagliare in modo invisibile. Leggere MPRIS lo fa
// Quickshell e o funziona o non c'è; disegnare il riquadro si vede a occhio.
// La SCELTA del lettore no: con una scheda di YouTube ferma e la musica che
// va, premere Pausa deve fermare la musica — e se ferma il video nessuno
// capisce perché, perché non c'è niente da guardare che lo spieghi.
//
// D-Bus non si finge, ma non serve: `Core.Media.scegli()` riceve una lista e
// un ricordo e non tocca il bus. Le prove le passano oggetti semplici.
ShellRoot {
    id: banco

    property int passate: 0
    property int fallite: 0

    function verifica(nome, condizione, dettaglio) {
        if (condizione) {
            banco.passate++;
            console.log("  ok   " + nome);
        } else {
            banco.fallite++;
            console.log("  NO   " + nome + (dettaglio ? "  → " + dettaglio : ""));
        }
    }

    /// Un lettore finto: solo le due cose che la regola guarda.
    function lettore(nome, suona) {
        return { "dbusName": nome, "isPlaying": suona };
    }

    Component.onCompleted: {
        console.log("── Prove del lettore multimediale ──");

        var M = Core.Media;

        // ── Nessun lettore ───────────────────────────────────────────────

        banco.verifica("senza lettori non c'è niente da comandare",
                       M.scegli([], "") === null);
        banco.verifica("una lista nulla non fa esplodere niente",
                       M.scegli(null, "") === null);

        // ── Uno solo ─────────────────────────────────────────────────────

        var solo = [banco.lettore("org.mpris.MediaPlayer2.vlc", false)];
        banco.verifica("con uno solo si comanda quello, anche in pausa",
                       M.scegli(solo, "") === solo[0]);

        // ── Il caso che conta: musica che va, video fermo ────────────────
        //
        // L'ordine è quello sbagliato di proposito: il video viene PRIMA
        // nella lista. Chi prendesse «il primo» fermerebbe il video.

        var video = banco.lettore("org.mpris.MediaPlayer2.firefox", false);
        var musica = banco.lettore("org.mpris.MediaPlayer2.spotify", true);
        var due = [video, musica];

        banco.verifica("fra un video fermo e la musica che va, comanda la musica",
                       M.scegli(due, "") === musica,
                       "ha scelto " + (M.scegli(due, "") || {}).dbusName);

        // ── Due che suonano: vince quello ricordato ──────────────────────
        //
        // «Ricordato» vuol dire l'ultimo che ha COMINCIATO: se metti su la
        // musica mentre un video va già, i tasti devono seguire la musica.

        var videoAcceso = banco.lettore("org.mpris.MediaPlayer2.firefox", true);
        var dueAccesi = [videoAcceso, musica];

        banco.verifica("se suonano in due, comanda l'ultimo che è partito",
                       M.scegli(dueAccesi, musica.dbusName) === musica);
        banco.verifica("…e se l'ultimo partito è il video, comanda il video",
                       M.scegli(dueAccesi, videoAcceso.dbusName) === videoAcceso);

        // ── Il motivo per cui serve la memoria ───────────────────────────
        //
        // Metti in pausa Spotify. Adesso non suona più niente. Senza memoria
        // il tasto Play riaccenderebbe il primo della lista — il video — e
        // partirebbe un audio che non avevi chiesto.

        var duePausa = [video, banco.lettore("org.mpris.MediaPlayer2.spotify", false)];

        banco.verifica("in pausa i tasti restano su chi suonava, non saltano al primo",
                       M.scegli(duePausa, "org.mpris.MediaPlayer2.spotify") === duePausa[1],
                       "ha scelto " + (M.scegli(duePausa, "org.mpris.MediaPlayer2.spotify") || {}).dbusName);

        // ── Il ricordato che se n'è andato ───────────────────────────────
        //
        // Spotify chiuso: il ricordo punta a un lettore che non esiste più.
        // Non deve restare `null`, o i tasti smetterebbero di funzionare
        // finché non si riapre proprio quel programma.

        banco.verifica("se chi era ricordato è stato chiuso, si passa a quel che resta",
                       M.scegli([video], "org.mpris.MediaPlayer2.spotify") === video);

        // ── Chi suona batte chi è ricordato ──────────────────────────────
        //
        // Il ricordo non deve MAI vincere su qualcosa che sta suonando ora:
        // sarebbe il difetto originale al contrario.

        banco.verifica("chi sta suonando batte sempre il ricordo di chi è fermo",
                       M.scegli([video, musica], "org.mpris.MediaPlayer2.firefox") === musica);

        // ── I comandi senza lettore non devono rompere niente ────────────
        //
        // I tasti della tastiera li chiamano anche quando non c'è nessun
        // lettore aperto: se lanciassero un'eccezione, il gestore della
        // scorciatoia morirebbe e il tasto resterebbe morto fino al riavvio
        // della shell.

        var esploso = false;
        try {
            M.riproduci(); M.successivo(); M.precedente(); M.ferma(); M.mostra();
        } catch (e) {
            esploso = true;
        }
        banco.verifica("i comandi a vuoto non lanciano eccezioni", !esploso);

        // ── Il riquadro compila ──────────────────────────────────────────
        //
        // Non lo si costruisce: lo si COMPILA. Basta a prendere il difetto che
        // costa di più in QML — un nome di proprietà che non esiste — senza
        // aprire nessuna finestra, quindi la prova gira anche di corsa. Il
        // riquadro vive dentro il pannello di controllo, che sta nella shell:
        // se si rompesse, ci si accorgerebbe solo al prossimo accesso.
        // ── Il nome del file tagliato ────────────────────────────────────
        //
        // Viene dal titolo di un brano, cioè da fuori, e finisce dentro un
        // percorso composto nello script (`"$c/$7"`). Una barra dentro
        // sposterebbe il file in un'altra cartella; `..` lo porterebbe fuori
        // da Musica.
        var motore = Qt.createComponent("media/MediaBackend.qml");
        banco.verifica("il motore del lettore compila",
                       motore.status === Component.Ready, motore.errorString());
        if (motore.status === Component.Ready) {
            var mb = motore.createObject(banco);
            banco.verifica("una barra nel titolo non sposta il file",
                           mb._nomeTagliato("/x/a/b.mp3", 0, 1).indexOf("/") < 0,
                           mb._nomeTagliato("/x/a/b.mp3", 0, 1));
            banco.verifica("un titolo con barre dentro viene ripulito",
                           mb._nomeTagliato("/x/..%2F../evasione.mp3", 0, 1)
                             .indexOf("/") < 0);
            banco.verifica("un titolo vuoto non dà un nome vuoto",
                           mb._nomeTagliato("/x/.mp3", 0, 1).length > 4,
                           mb._nomeTagliato("/x/.mp3", 0, 1));
            banco.verifica("il colore che entra nel filtro è solo esadecimale",
                           /^[0-9A-F]{6}$/.test(mb._hex("#ff00ff; rm -rf")),
                           mb._hex("#ff00ff; rm -rf"));
            mb.destroy();
        }

        var pezzo = Qt.createComponent("ui/MediaCard.qml");
        banco.verifica("il riquadro del lettore compila",
                       pezzo.status === Component.Ready,
                       pezzo.errorString());

        // Il resto guarda lo stato VERO del computer, e va aspettato: vedi
        // il commento sul temporizzatore qui sotto.
        attesa.start();
    }

    // ── Lo stato vero, dopo aver dato tempo a D-Bus ──────────────────────
    //
    // La prima versione di questa prova guardava `Media.lettori` dentro
    // `Component.onCompleted` e trovava sempre la lista vuota — anche con un
    // lettore acceso e funzionante, verificato sul bus nello stesso istante.
    // Quickshell interroga D-Bus in modo asincrono: al momento in cui il QML
    // finisce di caricarsi le risposte non sono ancora arrivate.
    //
    // Il guaio è che la prova PASSAVA lo stesso, prendendo il ramo «non c'è
    // nessun lettore». Una prova che si accontenta del ritardo non prova
    // niente e lo dice col tono di chi ha provato tutto. È il terzo caso di
    // questo tipo in questo progetto: vedi `minerva-trappole-prove`.
    property Timer attesa: Timer {
        interval: 1500
        repeat: false

        onTriggered: {
            var M = Core.Media;

            if (M.lettori.length === 0) {
                console.log("  --   nessun lettore aperto: le prove sullo stato "
                            + "vero sono saltate");
                banco.verifica("senza lettori il riquadro sparisce e il titolo è vuoto",
                               M.titolo === "" && !M.cQualcosa && !M.inRiproduzione);
            } else {
                // Il titolo non deve MAI restare vuoto: è la riga che fa
                // sembrare rotto il pannello quando un lettore manda metadati
                // incompleti — una radio, un video appena aperto.
                banco.verifica("con un lettore vero il titolo non è mai vuoto",
                               M.cQualcosa && M.titolo.length > 0,
                               "titolo «" + M.titolo + "»");
                banco.verifica("il lettore scelto è uno di quelli vivi",
                               M.lettori.indexOf(M.attivo) >= 0);
            }

            console.log("──");
            console.log(banco.fallite === 0
                        ? "TUTTE PASSATE (" + banco.passate + ")"
                        : "FALLITE " + banco.fallite + " su "
                          + (banco.passate + banco.fallite));
            Qt.exit(banco.fallite === 0 ? 0 : 1);
        }
    }
}

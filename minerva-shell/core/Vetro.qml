pragma Singleton
import QtQuick
import "." as Core

// Vetro — Lo sfondo già sfocato, dietro la barra e la dock.
//
// ── Perché un'immagine, e non un effetto ─────────────────────────────────
//
// Perché col processore un effetto non esiste. La shell gira con
// `QT_QUICK_BACKEND=software` — vale 38 MB, ed è una scelta — e lì dentro
// `layer.effect` non c'è. Il 31 agosto 2026 è stata provata anche la strada
// nuova di Qt 6.8, `ShapePath.fillItem`: col renderer software la forma esce
// **vuota**, mentre la stessa forma con un colore pieno si disegna
// perfettamente. Misurato con una cattura, non supposto.
//
// Un'immagine invece si disegna. La prepara il demone quando cambia lo
// sfondo — ridotta e sfocata, qualche decina di kilobyte — e da lì in poi
// disegnarla **costa zero a fotogramma**. La sfocatura di Hyprland invece
// erano due passaggi a schermo pieno dietro ogni superficie appoggiata, a
// ogni fotogramma, per sempre, su una Intel Iris Plus G1 integrata.
//
// ── Cosa si perde, detto qui e non scoperto dopo ─────────────────────────
//
// Il vetro vero mostra le finestre che ci passano sotto; questo mostra lo
// sfondo. La differenza è più piccola di quanto sembri: la barra ha una zona
// riservata di layer-shell, quindi le finestre normali **non ci passano
// sotto**. Si perde solo dietro le finestre a schermo intero, dove la barra
// si nasconde comunque.
QtObject {
    id: vetro

    /// ── Da quando il compositore sfoca DAVVERO ──────────────────────────
    ///
    /// Il 9 settembre 2026 SceneFX è entrato nel compositore e `windows.effetto
    /// = blur` sfoca per davvero quello che sta dietro una superficie. Da quel
    /// momento questo vetro finto non è più un ripiego: è un MURO. È
    /// un'immagine OPACA dipinta dentro una membrana opaca al 93 %, cioè
    /// esattamente la cosa che impedisce alla sfocatura vera di arrivare
    /// all'occhio.
    ///
    /// Misurato sulla sessione viva passando da `vetro` a `blur` e
    /// confrontando due fotografie pixel per pixel:
    ///
    ///     fascia della barra    0,0 % dei pixel cambia   (0 su 84.480)
    ///     dock                  0,3 %
    ///     dentro una finestra   54,3 %                   ← lì il vetro finto non c'è
    ///
    /// Il blur funzionava dal primo minuto. Non si vedeva perché glielo
    /// coprivamo noi.
    ///
    /// E si guadagna proprio quello che il commento qui sopra dichiarava
    /// perso: «il vetro vero mostra le finestre che ci passano sotto, questo
    /// mostra lo sfondo». Adesso ci passano sotto, e si vedono.
    /// Che effetto il compositore mette sulle finestre: «nessuno», «vetro» o
    /// «blur». Si legge QUI e in un posto solo: tre file che chiedono la
    /// stessa chiave con tre ripieghi diversi sono tre risposte diverse il
    /// giorno che il ripiego conta.
    readonly property string effettoChiesto:
        String(Core.Ipc.get("windows.effetto", "nessuno"))

    /// ── Chiesto e disegnato ─────────────────────────────────────────────
    ///
    /// Dal 23 settembre 2026 non sono sempre la stessa cosa: a batteria bassa
    /// il compositore abbassa l'effetto a «nessuno» da sé (il modo risparmio,
    /// `compositore/src/energia.h`). Chi DISEGNA — la membrana, le finestre —
    /// deve seguire quello disegnato: una barra a 0,68 pensata per stare
    /// sopra un fondo sfocato, senza sfocatura sotto, non si legge. Chi
    /// mostra le MANOPOLE deve seguire quello chiesto: durante il risparmio
    /// l'intensità del blur si regola lo stesso, e vale da quando si esce.
    readonly property bool blurChiesto: vetro.effettoChiesto === "blur"
    /// Blur e acquerello sono tutti e due un FILTRO dietro la superficie:
    /// per chi disegna sopra valgono uguale (niente quadro finto sotto la
    /// tinta, membrana che si apre). Differiscono solo nella manopola
    /// dell'intensità, che è del blur: l'acquerello prende il colore e basta.
    readonly property bool filtroChiesto: vetro.effettoChiesto === "blur"
                                          || vetro.effettoChiesto === "acquerello"
    readonly property bool effettoChiestoAcceso: vetro.effettoChiesto !== "nessuno"

    readonly property bool inRisparmio: Core.Compositore.risparmio
                                        && Core.Compositore.risparmio.attivo === true
    readonly property string effetto: vetro.inRisparmio ? "nessuno" : vetro.effettoChiesto

    readonly property bool filtroVero: vetro.effetto === "blur"
                                       || vetro.effetto === "acquerello"

    /// Vero quando la trasparenza delle finestre la mette IL COMPOSITORE.
    ///
    /// ── Perché conta, e perché è una sola ───────────────────────────────
    ///
    /// Perché fino al 9 settembre 2026 una finestra di Minerva era trasparente
    /// DUE volte: `shell.windowOpacity` nel colore di fondo del QML, e
    /// `windows.effettoOpacita` che il compositore mette su tutto l'albero
    /// della finestra. Le due si moltiplicano: 0,90 × 0,73 = **0,66**, mentre
    /// Chrome — che di `windowOpacity` non sa niente — restava a 0,73. Due
    /// finestre affiancate, due trasparenze diverse, e nessuno dei due cursori
    /// lo diceva.
    ///
    /// Col compositore acceso la trasparenza la mette lui e basta, come per
    /// qualunque altro programma. `shell.windowOpacity` non muore: è la
    /// manopola del vetro quando l'effetto è «nessuno», cioè quando il
    /// compositore non ci mette niente.
    ///
    /// E c'è la ragione tecnica, che viene prima del gusto: il blur di SceneFX
    /// si vede **solo dove la superficie è trasparente**. La trasparenza serve
    /// al compositore per lavorare; una seconda in QML non aggiunge effetto,
    /// toglie solo leggibilità.
    readonly property bool effettoAcceso: vetro.effetto !== "nessuno"

    /// Quello che chi disegna deve mettere sotto la tinta: il quadro sfocato,
    /// oppure NIENTE quando a sfocare ci pensa il compositore.
    ///
    /// È una proprietà a parte e non `percorso` azzerato, perché le due cose
    /// sono diverse: `percorso` è la risposta del demone e resta vera anche
    /// col blur acceso (si torna a `vetro` senza rifare il conto).
    readonly property string daDisegnare: vetro.filtroVero ? "" : vetro.percorso

    /// Il percorso della copia sfocata, o "" finché non c'è.
    ///
    /// Vuoto è un caso normale, non un guasto: succede nel primo mezzo secondo
    /// di ogni sessione, e per sempre su una macchina senza `magick`. Chi
    /// disegna deve saper stare senza — e infatti sotto resta il colore della
    /// membrana, che è quello di prima.
    property string percorso: ""

    /// L'ultimo sfondo per cui si è chiesta la sfocatura, per non richiederla
    /// in continuazione.
    property string _chiesto: ""

    /// ── Lo chiede solo la SCRIVANIA ─────────────────────────────────────
    ///
    /// Questo file sta in `core/`, e `core/` è importato da ogni applicazione
    /// di Minerva: senza questa riga il gestore file, la calcolatrice e
    /// l'anteprima chiederebbero tutte la sfocatura dello sfondo appena si
    /// collegano — una cosa che non disegnano e non disegneranno mai. Il
    /// vetro lo mettono in due soli posti, `spine/Spine.qml` e `dock/Dock.qml`,
    /// e tutti e due stanno nella scrivania.
    ///
    /// Costa poco (il demone risponde dalla cache), ma è la stessa famiglia
    /// del difetto chiuso la mattina del 31 agosto 2026: le impostazioni di
    /// sistema partivano da OGNI app. Un file di `core/` che parla col demone
    /// deve dire per chi lo fa.
    function _chiedi() {
        if (!Core.Compositore.scrivania)
            return;
        // Col blur vero non serve a nessuno: sarebbe far lavorare il demone e
        // `magick` per un'immagine che nessuno disegna.
        if (vetro.filtroVero)
            return;
        var s = String(Core.Wallpaper.current || "");
        if (s === "" || s === vetro._chiesto)
            return;
        vetro._chiesto = s;
        // Non si azzera `percorso` qui: durante il calcolo si continua a
        // mostrare quello di prima invece di far lampeggiare la barra. È
        // sbagliato per un istante, ed è meglio di un salto di colore.
        Core.Ipc.chiediSfondoSfocato(s);
    }

    property Connections _sfondo: Connections {
        target: Core.Wallpaper
        function onCurrentChanged() { vetro._chiedi(); }
    }

    /// Spegnendo il blur il quadro va richiesto: mentre era acceso `_chiedi`
    /// tornava indietro subito, e senza questa riga la barra resterebbe senza
    /// vetro fino al prossimo cambio di sfondo — cioè, con la rotazione
    /// spenta, per sempre.
    onFiltroVeroChanged: {
        if (!vetro.filtroVero) {
            vetro._chiesto = "";
            vetro._chiedi();
        }
    }

    property Connections _canale: Connections {
        target: Core.Ipc
        // Il demone può rispondere solo quando c'è: la shell parte quasi
        // sempre prima di lui.
        function onConnectedChanged() {
            if (Core.Ipc.connected) {
                vetro._chiesto = "";
                vetro._chiedi();
            }
        }
        function onSfondoSfocato(esito) {
            if (!esito || esito.ok !== true)
                return;
            // Si controlla che sia la risposta allo sfondo di ADESSO: le
            // richieste tornano fuori ordine, e con la rotazione degli sfondi
            // accesa la risposta di due sfondi fa potrebbe arrivare per ultima.
            if (String(esito.sfondo || "") !== vetro._chiesto)
                return;
            vetro.percorso = String(esito.percorso || "");
        }
    }
}

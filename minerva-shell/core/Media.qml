pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Media — Chi sta suonando, e i comandi per fermarlo.
//
// MPRIS è il modo in cui su Linux un programma che riproduce qualcosa lo
// annuncia al resto del sistema: Firefox, Spotify, VLC, un video in una
// scheda del browser. Ognuno espone su D-Bus il titolo, l'artista, la
// copertina e i comandi. Minerva finora non lo ascoltava affatto.
//
// ── Il difetto che questo file chiude ────────────────────────────────────
//
// I tasti Play/Avanti/Indietro della tastiera erano legati in `keybinds.conf`
// a `playerctl`, che **su questa macchina non è installato**. Premerli non
// faceva nulla e non diceva nulla: il caso peggiore, perché sembra che il
// tasto sia rotto. Adesso passano dalla shell come già facevano volume e
// luminosità, e non serve nessun programma in più.
//
// ── QUALE lettore, quando ce n'è più d'uno ───────────────────────────────
//
// È la sola decisione difficile qui dentro, e sbagliarla si nota subito: con
// una scheda di YouTube ferma e la musica che va, premere Pausa deve fermare
// LA MUSICA. La regola, in ordine:
//
//  1. se qualcosa sta suonando, quello — e fra più cose che suonano, l'ultima
//     che ha cominciato;
//  2. se non suona niente, l'ULTIMO che ha suonato, finché è vivo. Così la
//     musica messa in pausa resta sotto le dita e Play la riprende, invece di
//     far ripartire un video di cui ci si era dimenticati;
//  3. se non ne abbiamo mai visto suonare nessuno, il primo che c'è.
//
// Il punto 2 è la ragione per cui serve `ricordato`: senza memoria, mettere in
// pausa Spotify farebbe saltare i comandi su un altro lettore qualunque, e il
// tasto Play riaccenderebbe la cosa sbagliata.
//
// ── Perché la memoria non si aggiorna dentro il legame ───────────────────
//
// `attivo` è un legame: si ricalcola da solo quando cambia qualcosa che ha
// letto. Scrivere `ricordato` lì dentro vorrebbe dire modificare, durante il
// calcolo, un valore da cui il calcolo dipende — un anello che si riavvolge da
// solo. Se ne occupa `_spia`, che sta a guardare `isPlaying` di ogni lettore e
// scrive il nome quando qualcuno parte.
QtObject {
    id: media

    /// Tutti i lettori vivi in questo momento.
    readonly property var lettori: Mpris.players ? Mpris.players.values : []

    /// Il nome sul bus dell'ultimo lettore che ha suonato. Vuoto all'avvio.
    property string ricordato: ""

    /// Il lettore su cui agiscono i comandi. `null` se non c'è musica in giro.
    readonly property var attivo: media.scegli(media.lettori, media.ricordato)

    /// La regola scritta sopra, e nient'altro.
    ///
    /// Sta in una funzione a parte, che riceve TUTTO ciò che le serve, per una
    /// ragione sola: così si può provare. D-Bus non si finge, ma una lista di
    /// oggetti con `isPlaying` e `dbusName` sì — e la parte che si sbaglia è
    /// questa, non la lettura del bus. Vedi `prove-media.qml`.
    function scegli(v, ricordato) {
        if (!v || v.length === 0)
            return null;

        // 1. Chi suona adesso. Fra più d'uno vince quello ricordato, che è
        //    l'ultimo ad aver cominciato.
        var chiSuona = null;
        for (var i = 0; i < v.length; i++) {
            if (!v[i].isPlaying)
                continue;
            if (v[i].dbusName === ricordato)
                return v[i];
            if (chiSuona === null)
                chiSuona = v[i];
        }
        if (chiSuona !== null)
            return chiSuona;

        // 2. L'ultimo che ha suonato, se è ancora vivo.
        for (var j = 0; j < v.length; j++)
            if (v[j].dbusName === ricordato)
                return v[j];

        // 3. Il primo che c'è.
        return v[0];
    }

    /// C'è qualcosa da mostrare? Il riquadro nel pannello di controllo compare
    /// solo se sì: uno spazio vuoto intitolato «Musica» è peggio di niente.
    readonly property bool cQualcosa: media.attivo !== null

    readonly property bool inRiproduzione: media.attivo !== null && media.attivo.isPlaying

    /// Il titolo, con un ripiego che non lascia mai la riga vuota.
    ///
    /// Molti lettori mandano metadati incompleti — un flusso radio senza
    /// titolo, un video appena aperto — e una riga vuota fa sembrare il
    /// riquadro rotto. Il nome del programma è sempre disponibile ed è
    /// un'informazione vera.
    readonly property string titolo: {
        if (media.attivo === null)
            return "";
        if (media.attivo.trackTitle && media.attivo.trackTitle.length > 0)
            return media.attivo.trackTitle;
        return media.attivo.identity || "";
    }

    readonly property string artista: {
        if (media.attivo === null)
            return "";
        // `trackArtist` è già la lista unita quando gli artisti sono più d'uno.
        if (media.attivo.trackArtist && media.attivo.trackArtist.length > 0)
            return media.attivo.trackArtist;
        // Senza artista si dice da dove viene: «Firefox» sotto il titolo di un
        // video è esattamente ciò che serve sapere.
        return media.attivo.trackTitle && media.attivo.trackTitle.length > 0
               ? (media.attivo.identity || "") : "";
    }

    /// L'indirizzo della copertina. Può essere un file locale o un indirizzo
    /// di rete: Spotify e i browser mandano spesso `https://…`.
    readonly property string copertina:
        media.attivo !== null && media.attivo.trackArtUrl ? media.attivo.trackArtUrl : ""

    // ── I comandi ────────────────────────────────────────────────────────
    //
    // Tutti controllano prima di agire. Un lettore può dichiarare di non
    // saper fare qualcosa (`canGoNext` falso su una radio, che non ha un
    // «brano successivo»), e chiamarglielo lo stesso è un errore su D-Bus che
    // finisce nel registro senza che nessuno lo veda.

    function riproduci() {
        if (media.attivo !== null && media.attivo.canTogglePlaying)
            media.attivo.togglePlaying();
    }

    function successivo() {
        if (media.attivo !== null && media.attivo.canGoNext)
            media.attivo.next();
    }

    function precedente() {
        if (media.attivo !== null && media.attivo.canGoPrevious)
            media.attivo.previous();
    }

    /// Ferma davvero, non mette in pausa: alcune tastiere hanno il tasto
    /// quadrato accanto agli altri e finora non era legato a niente.
    function ferma() {
        if (media.attivo !== null && media.attivo.canControl)
            media.attivo.stop();
    }

    /// Porta in primo piano la finestra del lettore. Non tutti sanno farlo.
    function mostra() {
        if (media.attivo !== null && media.attivo.canRaise)
            media.attivo.raise();
    }

    // ── La spia che tiene aggiornato `ricordato` ─────────────────────────
    //
    // Un `Instantiator` costruisce un oggetto per ogni lettore vivo e lo
    // distrugge quando sparisce: è il modo di stare in ascolto di una
    // proprietà su un insieme che cambia da solo. Non disegna niente e non
    // costa niente finché non ci sono lettori.
    property Instantiator _spia: Instantiator {
        model: Mpris.players

        delegate: QtObject {
            id: sentinella
            required property var modelData

            // Un lettore già in riproduzione quando la shell parte non emette
            // nessun cambiamento: va guardato subito, o dopo un riavvio della
            // shell la musica in corso non sarebbe «ricordata».
            Component.onCompleted: {
                if (sentinella.modelData && sentinella.modelData.isPlaying)
                    media.ricordato = sentinella.modelData.dbusName;
            }

            property Connections _ascolto: Connections {
                target: sentinella.modelData

                function onIsPlayingChanged() {
                    if (sentinella.modelData.isPlaying)
                        media.ricordato = sentinella.modelData.dbusName;
                }
            }
        }
    }
}

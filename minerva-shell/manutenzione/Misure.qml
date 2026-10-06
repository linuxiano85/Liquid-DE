pragma Singleton

import QtQuick

import "../theme" as Theme
import "../core" as Core

// Misure — i byte in parole, e le famiglie in colori.
//
// ── Perché un posto solo ───────────────────────────────────────────────────
//
// Perché il numero grande in cima, la fetta dell'anello, la barretta di riga e
// il conto di quello che hai spuntato devono dire **la stessa cosa**. Sono
// quattro punti diversi dello schermo che parlano dello stesso byte: se
// ognuno lo arrotondasse a modo suo, l'anello direbbe 6,9 GB e l'elenco 6,93,
// e chi guarda avrebbe ragione a non fidarsi di nessuno dei due.
//
// È la stessa ragione per cui il riassunto per famiglia lo fa il demone e non
// la finestra.
QtObject {
    id: misure

    // ── I byte ──────────────────────────────────────────────────────────
    //
    // In base **mille** e non 1024, perché è quello che dice `du -sb` e
    // quello che dicono i produttori di dischi. Mescolare le due basi vuol
    // dire che il totale della finestra non torna con quello di un terminale
    // aperto di fianco, ed è il genere di differenza che non si spiega mai.
    //
    // Le cifre dopo la virgola scendono man mano che il numero cresce: «4,24
    // GB» si legge, «4,238 GB» è rumore, e «724 MB» non ha bisogno di
    // decimali perché il megabyte in più non cambia nessuna decisione.
    function peso(byte) {
        var b = Number(byte) || 0;
        if (b <= 0) return "0";
        if (b < 1000) return b + " B";
        if (b < 1000000) return Math.round(b / 1000) + " KB";
        if (b < 1000000000) return Math.round(b / 1000000) + " MB";
        var g = b / 1000000000;
        return (g < 10 ? g.toFixed(2) : g.toFixed(1)).replace(".", ",") + " GB";
    }

    // ── Le famiglie ─────────────────────────────────────────────────────
    //
    // I nomi arrivano dal demone come parole fisse (`cache`, `sviluppo`, …) e
    // qui diventano una frase. Le parole fisse non si traducono mai: sono
    // quelle che un giorno arriveranno all'aiutante di root.

    readonly property var _ordine: ["cache", "sviluppo", "pacchetti", "lingue",
                                    "miniature", "registri", "temporanei",
                                    "cestino"]

    /// L'ordine in cui si mostrano. **Non** quello alfabetico e nemmeno
    /// quello del peso: è l'ordine di quanto è facile decidere. Le cache si
    /// buttano senza pensarci; il cestino, che l'hai riempito tu, per ultimo.
    function ordine() { return misure._ordine; }

    function nome(cat) {
        switch (cat) {
        case "cache":      return Core.Strings.lang === "it" ? "Cache dei programmi" : "Program caches";
        case "sviluppo":   return Core.Strings.lang === "it" ? "Roba di sviluppo" : "Development leftovers";
        case "pacchetti":  return Core.Strings.lang === "it" ? "Pacchetti scaricati" : "Downloaded packages";
        case "lingue":     return Core.Strings.lang === "it" ? "Lingue che non usi" : "Languages you don't use";
        case "miniature":  return Core.Strings.lang === "it" ? "Miniature" : "Thumbnails";
        case "registri":   return Core.Strings.lang === "it" ? "Registri" : "Logs";
        case "temporanei": return Core.Strings.lang === "it" ? "File temporanei" : "Temporary files";
        case "cestino":    return Core.Strings.lang === "it" ? "Cestino" : "Trash";
        }
        return cat;
    }

    /// Una riga che dice cosa succede a buttarla. Non è decorazione: è
    /// l'unica cosa che distingue «4 GB di cache» da «4 GB di roba di
    /// sviluppo», che sono due decisioni diverse.
    function spiega(cat) {
        switch (cat) {
        case "cache":      return Core.Strings.lang === "it" ? "I programmi se la rifanno da soli usandoli." : "Programs rebuild it by themselves as you use them.";
        case "sviluppo":   return Core.Strings.lang === "it" ? "Si rifà, ma ci vuole tempo: la prossima compilazione sarà lenta." : "It comes back, but it takes time: the next build will be slow.";
        case "pacchetti":  return Core.Strings.lang === "it" ? "I file scaricati per installare i programmi. I programmi restano dove sono." : "The files downloaded to install programs. The programs stay where they are.";
        case "lingue":     return Core.Strings.lang === "it" ? "Traduzioni delle altre lingue. Tornano da sole se non si dice a pacman di lasciar perdere." : "Translations into other languages. They come back unless pacman is told to skip them.";
        case "miniature":  return Core.Strings.lang === "it" ? "Le anteprime delle immagini. Tornano riaprendo una cartella." : "Image previews. They come back when a folder is reopened.";
        case "registri":   return Core.Strings.lang === "it" ? "Servono a capire cosa è successo quando qualcosa va storto." : "They help to understand what happened when something goes wrong.";
        case "temporanei": return Core.Strings.lang === "it" ? "File di lavoro rimasti per terra. Si svuota comunque al riavvio." : "Work files left lying around. It is emptied at restart anyway.";
        case "cestino":    return Core.Strings.lang === "it" ? "Quello che c'è dentro l'hai buttato tu." : "You put what is in there yourself.";
        }
        return "";
    }

    // ── Il colore ───────────────────────────────────────────────────────
    //
    // Non otto colori scritti a mano: otto **giri** intorno all'accento che
    // ha scelto Giacomo. Con una tavolozza fissa, il giorno che l'accento
    // diventa rosa l'anello resta ciano e verde, e la finestra smette di
    // appartenere al resto della scrivania — è la regola di
    // `minerva-temi-colore`, «un tema è una tinta e un verso».
    //
    // Saturazione e luce sono invece fisse, e per una ragione misurabile: le
    // fette devono staccarsi dal fondo in tutti e due i temi, e un colore che
    // eredita anche la luce dell'accento su un tema chiaro diventa una
    // macchia pallida su bianco.
    function colore(cat) {
        var i = misure._ordine.indexOf(cat);
        if (i < 0) i = misure._ordine.length;
        var giro = [0.0, 0.10, 0.55, 0.78, 0.30, 0.66, 0.88, 0.44][i % 8];
        var h = Theme.Colors.accent.hslHue;
        if (h < 0) h = 0.5;  // un accento grigio non ha tinta: si parte dal ciano
        var t = (h + giro) % 1.0;
        return Theme.Colors.scura ? Qt.hsla(t, 0.62, 0.62, 1.0)
                                  : Qt.hsla(t, 0.66, 0.42, 1.0);
    }
}

pragma Singleton
import QtQuick
import "." as Core

// Posizioni — Da che parte stanno la barra e la dock.
//
// Due booleani, e un file intero per loro. La ragione non è la quantità di
// codice: è che la stessa domanda se la fanno in sei posti diversi — la Spine,
// la Dock, gli avvisi, la griglia della scrivania, il promemoria dei tasti, le
// Impostazioni — e ognuno dovrebbe ripetere la stessa conversione.
//
// ── Perché una conversione, e non il valore così com'è ──────────────────────
//
// `bar.position` era dichiarata `'top'` fin dal primo giorno e non la leggeva
// nessuno. Adesso vale `'alto'` o `'basso'`, come `windows.buttonsSide` dice
// `'destra'` e `'sinistra'`: sono parole che si scrivono a mano in un file di
// impostazioni, e in Minerva quel file è in italiano.
//
// Ma chi ha già `'top'` scritto nel proprio non deve accorgersi di niente, e
// nemmeno chi domani ricopierà `'bottom'` da un esempio in rete. I due nomi
// vecchi valgono ancora, e valgono QUI: un `=== 'basso'` sparso in sei file è
// il modo in cui cinque posti si aggiornano e uno no.
QtObject {
    id: posizioni

    /// Dove la barra è stata CHIESTA, prima della regola qui sotto.
    readonly property bool _barraDetta:
        posizioni._verso(Core.Ipc.get("bar.position", "alto"), "basso", "bottom")

    /// La dock sta in cima allo schermo invece che in fondo.
    readonly property bool dockInAlto:
        posizioni._verso(Core.Ipc.get("dock.position", "basso"), "alto", "top")

    /// La dock c'è. Spenta, la barra va dove vuole: non c'è niente da evitare.
    readonly property bool dockAccesa: Core.Ipc.get("dock.enabled", true) === true

    /// Vero quando barra e dock erano state chieste dalla STESSA parte.
    ///
    /// ── Qui c'era il contrario, ed era scritto per esteso ────────────────
    ///
    /// «Non lo si impedisce — impedirlo vuol dire decidere per chi ha due
    /// schermi e una barra sola — ma le Impostazioni lo dicono a parole prima
    /// che succeda, che è l'unico avviso che serve.»
    ///
    /// Giacomo ha deciso il contrario, due volte. Il 4 settembre 2026: «non mi
    /// è piaciuto ad esempio il fatto che posso mettere in alto anche insieme
    /// la dock e la barra uno sopra l'altro, o ci sta uno o l'altro, se metto
    /// la dock in alto in automatico in basso deve starci la barra».
    ///
    /// E il ragionamento di prima non regge nemmeno da solo: chi ha due
    /// schermi ha comunque **una** barra e **una** dock, e metterle una
    /// sull'altra non serve a nessuno. Un avviso che spiega perché la tua
    /// scrivania è rotta non è meglio di una scrivania che non si può
    /// rompere.
    readonly property bool sovrapposte:
        posizioni.dockAccesa && posizioni._barraDetta !== posizioni.dockInAlto

    /// La barra sta in fondo allo schermo invece che in cima.
    ///
    /// ── La regola: se si scontrano, vince la dock ───────────────────────
    ///
    /// E sta QUI, non nelle Impostazioni: `settings.json` si scrive anche a
    /// mano, e una regola che vive solo nei pannelli è una regola che si
    /// aggira aprendo un editor di testi. Questo file è l'unico posto da cui
    /// passano tutti e sei quelli che hanno un verso — la barra, la dock, gli
    /// avvisi, la griglia della scrivania, il promemoria dei tasti e le
    /// Impostazioni.
    ///
    /// Vince la dock perché è quella che si sposta per scelta: la barra
    /// «sta dall'altra parte» è la conseguenza, non una seconda decisione.
    readonly property bool barraInBasso:
        posizioni.sovrapposte ? posizioni.dockInAlto : posizioni._barraDetta

    function _verso(valore, nostro, straniero) {
        var v = String(valore);
        return v === nostro || v === straniero;
    }
}

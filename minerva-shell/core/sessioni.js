.pragma library

// sessioni.js — Quale scrivania risulta già scelta nella schermata di accesso.
//
// Stava dentro `greeter/Greeter.qml` (`qualeSessione`). Il 28 settembre 2026
// la pagina Accesso delle Impostazioni mostrava la sessione di partenza con
// un ripiego suo («minerva», che non esiste più): nessuna scelta accesa, e
// nessun modo di sapere in cosa si entra premendo Invio. Una regola, due
// posti che la mostrano: sta qui.
//
// L'ordine, e perché:
//  · quella salvata, se c'è ancora e non è una riga di comando;
//  · poi le nostre, Liquid DE per prima — questo è il suo progetto: fino al
//    28 settembre il ripiego era «minerva-wayland», cioè la shell VECCHIA;
//  · poi la prima scrivania vera che non sia una via di scorta (il
//    recupero: il compositore con dentro un terminale e nient'altro);
//  · e solo se non resta altro, quello che c'è.

var NOSTRE = ["liquid-de", "minerva-wayland", "minerva"];

function diScorta(id) {
    return id === "minerva-recupero" || id === "liquid-de-recupero";
}

function scegli(elenco, voluta) {
    if (!elenco || elenco.length === 0)
        return 0;

    function trova(id) {
        for (var i = 0; i < elenco.length; i++)
            if (elenco[i].id === id) return i;
        return -1;
    }

    var i = trova(voluta);
    if (i >= 0 && elenco[i].tipo !== "tty") return i;

    for (var k = 0; k < NOSTRE.length; k++) {
        i = trova(NOSTRE[k]);
        if (i >= 0) return i;
    }

    for (var j = 0; j < elenco.length; j++) {
        if (elenco[j].tipo !== "tty" && !diScorta(elenco[j].id))
            return j;
    }

    for (var m = 0; m < elenco.length; m++)
        if (elenco[m].tipo !== "tty") return m;

    return 0;
}

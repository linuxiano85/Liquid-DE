pragma Singleton

import QtQuick

// Tempo — «tre ore fa», non «2026-08-24T17:25:03.000Z».
//
// ── Perché una data assoluta è quasi sempre la risposta sbagliata ──────────
//
// Perché la domanda che uno si fa guardando un salvataggio non è *quando è
// stato*, è *quanto tempo è passato*. «24 agosto, 17:25» costringe chi legge a
// fare una sottrazione, e a farla anche solo per capire se è roba di oggi.
//
// L'ora esatta serve in un caso solo — quando si deve scegliere fra due
// salvataggi dello stesso pomeriggio — e per quello c'è `quandoPreciso()`.
QtObject {
    id: tempo

    function _minuti(iso) {
        var d = new Date(iso);
        if (isNaN(d.getTime())) return -1;
        return Math.floor((Date.now() - d.getTime()) / 60000);
    }

    /// Per i riquadri e le righe: corto, e mai più lungo di tre parole.
    function quandoBreve(iso, it) {
        var m = tempo._minuti(iso);
        if (m < 0) return "";
        if (m < 1)  return it ? "adesso" : "just now";
        if (m < 60) return m + (it ? " min fa" : "m ago");
        var o = Math.floor(m / 60);
        if (o < 24) return o + (it ? (o === 1 ? " ora fa" : " ore fa")
                                   : "h ago");
        var g = Math.floor(o / 24);
        if (g < 7)  return g + (it ? (g === 1 ? " giorno fa" : " giorni fa")
                                   : "d ago");
        if (g < 31) {
            var set = Math.floor(g / 7);
            return set + (it ? (set === 1 ? " settimana fa" : " settimane fa")
                             : "w ago");
        }
        var me = Math.floor(g / 30);
        if (me < 12) return me + (it ? (me === 1 ? " mese fa" : " mesi fa")
                                     : "mo ago");
        var a = Math.floor(g / 365);
        return a + (it ? (a === 1 ? " anno fa" : " anni fa") : "y ago");
    }

    /// Quando bisogna distinguere due cose dello stesso giorno.
    function quandoPreciso(iso, it) {
        var d = new Date(iso);
        if (isNaN(d.getTime())) return "";
        function due(v) { return (v < 10 ? "0" : "") + v; }
        var oggi = new Date();
        var stessoGiorno = d.getFullYear() === oggi.getFullYear()
                        && d.getMonth() === oggi.getMonth()
                        && d.getDate() === oggi.getDate();
        var ora = due(d.getHours()) + ":" + due(d.getMinutes());
        if (stessoGiorno) return (it ? "oggi alle " : "today at ") + ora;

        var mesi = it
            ? ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno",
               "luglio", "agosto", "settembre", "ottobre", "novembre",
               "dicembre"]
            : ["January", "February", "March", "April", "May", "June", "July",
               "August", "September", "October", "November", "December"];
        var giorno = d.getDate() + " " + mesi[d.getMonth()];
        if (d.getFullYear() !== oggi.getFullYear()) {
            giorno += " " + d.getFullYear();
        }
        return giorno + (it ? ", " : ", ") + ora;
    }
}

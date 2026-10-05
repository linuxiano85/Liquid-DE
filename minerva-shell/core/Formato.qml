pragma Singleton
import QtQuick
import "." as Core

// Formato — Come la shell scrive i numeri che mostra.
//
// Prima ogni finestra aveva la sua funzione per i byte, e lo stesso file
// risultava «45 MB» nel gestore file e «45.3 MB» nel monitor. Qui c'è la
// regola sola. La Manutenzione resta a parte di proposito: conta in base
// mille per tornare con `du -sb` (vedi `manutenzione/Misure.qml`).
QtObject {
    /// Byte in una misura che si legge: unità binarie con i nomi che la gente
    /// riconosce (KB, MB), un decimale sotto il cento, nessuno sopra.
    /// Vuota se il numero non c'è: chi chiama decide se mostrare «—».
    function peso(byte) {
        var v = Number(byte);
        if (byte === undefined || byte === null || byte === "" || isNaN(v))
            return "";
        if (v < 0) v = 0;
        var u = ["B", "KB", "MB", "GB", "TB"];
        var i = 0;
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
        return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)) + " " + u[i];
    }

    /// Un tempo lungo in parole brevi: «3 g 4 h», «2 h 15 min», «7 min».
    /// Serve a «acceso da …»: i secondi lì sono rumore.
    function durata(secondi) {
        var s = Math.max(0, Math.round(Number(secondi) || 0));
        var it = Core.Strings.lang === "it";
        var g = Math.floor(s / 86400);
        var h = Math.floor((s % 86400) / 3600);
        var m = Math.floor((s % 3600) / 60);
        if (g > 0)
            return g + (it ? " g " : " d ") + h + " h";
        if (h > 0)
            return h + " h " + m + " min";
        return m + " min";
    }
}

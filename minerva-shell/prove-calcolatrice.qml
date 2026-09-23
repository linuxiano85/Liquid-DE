import QtQuick
import Quickshell
import "theme" as Theme
import "core" as Core

// ProveCalcolatrice — Le prove del calcolo.
//
//     qs -p minerva-shell/prove-calcolatrice.qml
//
// L'analizzatore della calcolatrice è una funzione pura: gli si dà una
// stringa e risponde con un numero o un errore. Le prove non aprono nessuna
// finestra e non toccano niente — coprono la precedenza, le parentesi, i
// segni, la divisione per zero e le sciocchezze.
ShellRoot {
    id: banco

    property int passate: 0
    property int fallite: 0

    // La stessa macchina della calcolatrice, copiata qui perché una prova
    // che importa il componente proverebbe anche la finestra, e la finestra
    // ha bisogno di un compositore. La macchina invece no.
    function calcola(testo) {
        var p = { "s": testo, "i": 0 };

        function saltaSpazi() {
            while (p.i < p.s.length && p.s.charAt(p.i) === " ")
                p.i++;
        }

        function numero() {
            saltaSpazi();
            if (p.s.indexOf("π", p.i) === p.i) {
                p.i++;
                return { "valore": Math.PI };
            }
            var inizio = p.i;
            while (p.i < p.s.length
                   && ((p.s.charAt(p.i) >= "0" && p.s.charAt(p.i) <= "9")
                       || p.s.charAt(p.i) === "."))
                p.i++;
            if (p.i === inizio)
                return { "errore": true };
            var v = parseFloat(p.s.substring(inizio, p.i));
            if (isNaN(v))
                return { "errore": true };
            return { "valore": v };
        }

        function fattore() {
            saltaSpazi();
            if (p.i < p.s.length && p.s.charAt(p.i) === "(") {
                p.i++;
                var dentro = somma();
                if (dentro.errore)
                    return dentro;
                saltaSpazi();
                if (p.i >= p.s.length || p.s.charAt(p.i) !== ")")
                    return { "errore": true };
                p.i++;
                return dentro;
            }
            if (p.i < p.s.length && (p.s.charAt(p.i) === "-"
                        || p.s.charAt(p.i) === "−")) {
                p.i++;
                var n = fattore();
                if (n.errore)
                    return n;
                return { "valore": -n.valore };
            }
            if (p.i < p.s.length && p.s.charAt(p.i) === "+") {
                p.i++;
                return fattore();
            }
            if (p.i < p.s.length && p.s.charAt(p.i) === "√") {
                p.i++;
                var sotto = fattore();
                if (sotto.errore || sotto.valore < 0)
                    return { "errore": true };
                return { "valore": Math.sqrt(sotto.valore) };
            }
            return numero();
        }

        function prodotto() {
            var sinistra = fattore();
            if (sinistra.errore)
                return sinistra;
            saltaSpazi();
            if (p.i < p.s.length && p.s.charAt(p.i) === "²") {
                p.i++;
                sinistra = { "valore": sinistra.valore * sinistra.valore };
            } else if (p.i + 1 < p.s.length && p.s.charAt(p.i) === "⁻"
                       && p.s.charAt(p.i + 1) === "¹") {
                p.i += 2;
                if (sinistra.valore === 0)
                    return { "errore": true };
                sinistra = { "valore": 1 / sinistra.valore };
            }
            while (true) {
                saltaSpazi();
                var op = p.i < p.s.length ? p.s.charAt(p.i) : "";
                if (op !== "×" && op !== "*" && op !== "÷" && op !== "/") {
                    // La moltiplicazione implicita: 2π, 3√4, 2(3+1).
                    if (op === "π" || op === "√" || op === "("
                        || (op >= "0" && op <= "9") || op === ".") {
                        var implicita = fattore();
                        if (implicita.errore)
                            return implicita;
                        sinistra = { "valore": sinistra.valore * implicita.valore };
                        continue;
                    }
                    break;
                }
                p.i++;
                var destra = fattore();
                if (destra.errore)
                    return destra;
                if ((op === "÷" || op === "/") && destra.valore === 0)
                    return { "errore": true };
                sinistra = { "valore": (op === "×" || op === "*")
                             ? sinistra.valore * destra.valore
                             : sinistra.valore / destra.valore };
            }
            return sinistra;
        }

        function somma() {
            var sinistra = prodotto();
            if (sinistra.errore)
                return sinistra;
            while (true) {
                saltaSpazi();
                var op = p.i < p.s.length ? p.s.charAt(p.i) : "";
                if (op !== "+" && op !== "-" && op !== "−")
                    break;
                p.i++;
                var destra = prodotto();
                if (destra.errore)
                    return destra;
                sinistra = { "valore": op === "+"
                             ? sinistra.valore + destra.valore
                             : sinistra.valore - destra.valore };
            }
            return sinistra;
        }

        var esito = somma();
        saltaSpazi();
        if (!esito.errore && p.i < p.s.length)
            return { "errore": true };
        return esito;
    }

    function verifica(nome, condizione, dettaglio) {
        if (condizione) {
            banco.passate++;
            console.log("  ok   " + nome);
        } else {
            banco.fallite++;
            console.log("  NO   " + nome + (dettaglio ? "  → " + dettaglio : ""));
        }
    }

    function atteso(testo, valore) {
        var e = banco.calcola(testo);
        if (e.errore)
            return { "ok": false, "chi": "errore invece di " + valore };
        return Math.abs(e.valore - valore) < 1e-9
            ? { "ok": true } : { "ok": false, "chi": "ha dato " + e.valore };
    }

    Component.onCompleted: {
        console.log("── Prove della calcolatrice ───────────────────────");

        var r = atteso("27*13", 351);
        verifica("moltiplicazione semplice", r.ok, r.chi);

        r = atteso("2+3*4", 14);
        verifica("la moltiplicazione viene prima dell'addizione", r.ok, r.chi);

        r = atteso("(2+3)*4", 20);
        verifica("le parentesi cambiano l'ordine", r.ok, r.chi);

        r = atteso("10/4", 2.5);
        verifica("la divisione dà i decimali", r.ok, r.chi);

        r = atteso("10 ÷ 2", 5);
        verifica("il segno della calcolatrice divide", r.ok, r.chi);

        r = atteso("2 − 5", -3);
        verifica("il segno della calcolatrice sottrae", r.ok, r.chi);

        r = atteso(" 7 + 2 ", 9);
        verifica("gli spazi non contano", r.ok, r.chi);

        r = atteso("-5+10", 5);
        verifica("il segno davanti al numero", r.ok, r.chi);

        r = atteso("0.5+0.25", 0.75);
        verifica("i decimali col punto", r.ok, r.chi);

        r = atteso("2+(3*4)-6/2", 11);
        verifica("tutto insieme", r.ok, r.chi);

        var e = banco.calcola("10/0");
        verifica("dividere per zero è un errore", e.errore);

        e = banco.calcola("2+");
        verifica("un'addizione a metà è un errore", e.errore);

        e = banco.calcola("(2+3");
        verifica("una parentesi aperta è un errore", e.errore);

        e = banco.calcola("ciao");
        verifica("una parola è un errore", e.errore);

        e = banco.calcola("");
        verifica("il vuoto è un errore", e.errore);

        r = atteso("((((2))))", 2);
        verifica("parentesi annidate", r.ok, r.chi);

        r = atteso("√16", 4);
        verifica("la radice quadrata", r.ok, r.chi);

        r = atteso("5²", 25);
        verifica("il quadrato", r.ok, r.chi);

        r = atteso("5⁻¹", 0.2);
        verifica("il reciproco", r.ok, r.chi);
        r = atteso("2⁻¹", 0.5);
        verifica("il reciproco dopo un numero", r.ok, r.chi);
        r = atteso("2 ⁻¹", 0.5);
        verifica("il reciproco staccato da uno spazio", r.ok, r.chi);

        r = atteso("2π", 2 * Math.PI);
        verifica("pi greco", r.ok, r.chi);

        r = atteso("√9+1", 4);
        verifica("radice e somma insieme", r.ok, r.chi);

        e = banco.calcola("0⁻¹");
        verifica("il reciproco di zero è un errore", e.errore);

        e = banco.calcola("√-4");
        verifica("la radice di un negativo è un errore", e.errore);

        console.log("");
        if (banco.fallite > 0)
            console.log("FALLITE " + banco.fallite + " su "
                        + (banco.passate + banco.fallite));
        else
            console.log("TUTTE PASSATE (" + banco.passate + ")");
    }
}

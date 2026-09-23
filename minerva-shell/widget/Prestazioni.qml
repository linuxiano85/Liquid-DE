import QtQuick
import "../theme" as Theme
import "../core" as Core

// Prestazioni — Il tabellone di come sta lavorando il computer.
//
// Giacomo, 14 settembre 2026: «uno per le prestazioni che si vedano le varie
// misurazioni». In cima il processore, grande, con i core e il carico; poi
// memoria, GPU, temperatura, disco e rete, ognuna col suo simbolo, la sua
// barra e una parola — «basso», «medio», «alto» — che dice se preoccuparsi;
// in fondo quattro minuti di storia del processore.
//
// I numeri e le parole vengono da `Contenuto`, uno per grandezza, usato solo
// per i suoi conti: è la stessa scelta di `Riassunto.qml`, e la ragione è la
// stessa — due tabelle dei valori sarebbero due verità.
Tabellone {
    id: prestazioni

    readonly property bool it: Core.Strings.lang === "it"

    icona: "cpu"
    titolo: prestazioni.it ? "Prestazioni" : "Performance"
    iconaGrande: "cpu"

    Contenuto { id: cpu;  tipo: "processore";  visible: false }
    Contenuto { id: mem;  tipo: "memoria";     visible: false }
    Contenuto { id: gpu;  tipo: "gpu";         visible: false }
    Contenuto { id: temp; tipo: "temperatura"; visible: false }
    Contenuto { id: disc; tipo: "disco";       visible: false }
    Contenuto { id: rete; tipo: "rete";        visible: false }

    valore: cpu.valore
    sotto: {
        var m = Core.Macchina;
        var pezzi = [];
        if (m.core > 0)
            pezzi.push(m.core + (prestazioni.it ? " core" : " cores"));
        if (m.pronta)
            pezzi.push((prestazioni.it ? "carico " : "load ")
                       + (Math.round(m.carico * 100) / 100));
        return pezzi.join(" · ");
    }
    quota: cpu.quota
    tinta: cpu.tinta

    /// La parola accanto al numero. Tre gradini, e le soglie sono quelle
    /// dei colori in `Contenuto.tinta`: la parola e il colore devono dire
    /// la stessa cosa, o uno dei due mente.
    function parola(q) {
        if (q < 0) return "";
        if (q >= 0.92) return prestazioni.it ? "Al limite" : "At the limit";
        if (q >= 0.75) return prestazioni.it ? "Alto" : "High";
        if (q >= 0.35) return prestazioni.it ? "Medio" : "Medium";
        return prestazioni.it ? "Basso" : "Low";
    }

    righe: [
        { "icona": mem.icona,  "nome": mem.nome,  "valore": mem.valore,
          "quota": mem.quota,  "tinta": mem.tinta,  "stato": prestazioni.parola(mem.quota) },
        { "icona": gpu.icona,  "nome": gpu.nome,  "valore": gpu.valore,
          "quota": gpu.quota,  "tinta": gpu.tinta,  "stato": prestazioni.parola(gpu.quota) },
        { "icona": temp.icona, "nome": temp.nome, "valore": temp.valore,
          "quota": temp.quota, "tinta": temp.tinta, "stato": prestazioni.parola(temp.quota) },
        // Il disco è al contrario: la barra dice quanto RESTA, e la parola
        // pure. Vedi il perché in `Contenuto.qml`.
        { "icona": disc.icona, "nome": disc.nome, "valore": disc.valore,
          "quota": disc.quota, "tinta": disc.tinta,
          "stato": disc.quota < 0 ? "" : (disc.quota <= 0.05
                   ? (prestazioni.it ? "Quasi pieno" : "Almost full")
                   : disc.quota <= 0.15 ? (prestazioni.it ? "Poco spazio" : "Low space")
                   : (prestazioni.it ? "Libero" : "Free")) },
        { "icona": rete.icona, "nome": prestazioni.it ? "Rete" : "Network",
          "valore": rete.valore, "quota": -1, "tinta": Theme.Colors.textMuted,
          "stato": rete.sotto }
    ]

    storia: "processore"
    storiaNome: prestazioni.it ? "Processore, ultimi quattro minuti"
                               : "Processor, last four minutes"

    Accessible.role: Accessible.StaticText
    Accessible.name: prestazioni.titolo
    Accessible.description: cpu.nome + " " + cpu.valore + ", " + mem.nome + " "
                            + mem.valore + ", " + temp.nome + " " + temp.valore
}

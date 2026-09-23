import QtQuick
import Quickshell
import "core" as Core

// ProveNotificheBlocco — Cosa arriva alla schermata di blocco, per ogni
// livello di privacy.
//
//     qs -p minerva-shell/prove-notifiche-blocco.qml
//
// La promessa della pagina Notifiche è una sola e va provata sul serio: con
// «Solo quante» il TESTO non esce dalla shell. Non «non si vede»: non c'è
// proprio nel file che la schermata di blocco legge. Qui si danno notifiche
// finte a `Core.Notifications`, si cambia il livello, e si guarda dentro
// quello che verrebbe scritto — cercando il testo, non fidandosi dei campi.
//
// Il file vero NON si scrive: il percorso si spegne per primo, o la prova
// finirebbe sulla schermata di blocco di chi la lancia.
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

    readonly property string segreto: "La password del conto è 1234"

    function livello(l) {
        var s = JSON.parse(JSON.stringify(Core.Ipc.settings || {}));
        s.notifications = s.notifications || {};
        s.notifications.bloccoMostra = l;
        Core.Ipc.settings = s;
    }

    Component.onCompleted: {
        // Per primo: niente file vero.
        Core.Notifications._fileBlocco.path = "";

        var t = Date.now();
        Core.Notifications.items = [
            { "appName": "Thunderbird", "summary": "Vecchia", "body": "già letta", "time": t - 9000 },
            { "appName": "Thunderbird", "summary": "Banca", "body": banco.segreto, "time": t - 3000 },
            { "appName": "Telegram", "summary": "Marco", "body": "Stasera partita?", "time": t - 2000 },
            { "appName": "Thunderbird", "summary": "Anna", "body": "La cena di sabato", "time": t - 1000 }
        ];
        // Le ultime tre non sono ancora state viste; la prima sì.
        Core.Notifications.unread = 3;

        banco.livello("numero");
        var n = Core.Notifications._perIlBlocco();
        var tn = JSON.stringify(n);
        banco.verifica("«numero»: due programmi, in ordine dal più recente",
                       n.gruppi.length === 2 && n.gruppi[0].app === "Thunderbird"
                       && n.gruppi[1].app === "Telegram", tn);
        banco.verifica("«numero»: Thunderbird conta 2 (la letta non si ripete)",
                       n.gruppi[0].quante === 2, tn);
        banco.verifica("«numero»: Thunderbird è posta, Telegram no",
                       n.gruppi[0].posta === true && n.gruppi[1].posta === false, tn);
        banco.verifica("«numero»: il testo NON è nel file",
                       tn.indexOf("1234") < 0 && tn.indexOf("Banca") < 0
                       && tn.indexOf("Stasera") < 0, tn);
        banco.verifica("«numero»: nessuna voce singola", n.voci.length === 0, tn);

        banco.livello("tutto");
        var a = Core.Notifications._perIlBlocco();
        banco.verifica("«tutto»: tre voci, la più recente prima",
                       a.voci.length === 3 && a.voci[0].titolo === "Anna",
                       JSON.stringify(a.voci));
        banco.verifica("«tutto»: il testo c'è",
                       JSON.stringify(a).indexOf("1234") >= 0);

        banco.livello("niente");
        var z = Core.Notifications._perIlBlocco();
        banco.verifica("«niente»: vuoto, e nemmeno i nomi dei programmi",
                       z.gruppi.length === 0 && z.voci.length === 0
                       && JSON.stringify(z).indexOf("Thunderbird") < 0, JSON.stringify(z));

        banco.livello("numero");
        Core.Notifications.unread = 0;
        var v = Core.Notifications._perIlBlocco();
        banco.verifica("viste tutte nel pannello: il blocco non ne mostra",
                       v.gruppi.length === 0, JSON.stringify(v));

        console.log("──");
        console.log(banco.fallite === 0
                    ? "TUTTE PASSATE (" + banco.passate + ")"
                    : "FALLITE " + banco.fallite + " su "
                      + (banco.passate + banco.fallite));
        Qt.exit(banco.fallite === 0 ? 0 : 1);
    }
}

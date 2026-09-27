import QtQuick
import Quickshell
import Quickshell.Services.Pam

// ProveBlocco — Le prove della schermata di blocco, SENZA bloccare niente.
//
//     qs -p minerva-shell/prove-blocco.qml
//
// ── Cosa si può provare e cosa no ──────────────────────────────────────────
//
// La password giusta non si può provare: la sa Giacomo e non deve passare da
// qui. Quello che si può provare — ed è il pezzo che conta — è che la
// CATENA arrivi fino a PAM e ne riceva una risposta.
//
// La differenza fra le due risposte è tutto:
//
//   · `Failed`  → PAM ha guardato la password e ha detto di no. La catena
//                 funziona; l'unica cosa che manca è la password giusta.
//   · `error`   → PAM non ha nemmeno potuto guardare: file mancante,
//                 permessi, servizio sbagliato. Qui uno schermo bloccato
//                 non si aprirebbe MAI, nemmeno con la password giusta.
//
// Un blocco schermo che confonde le due è un computer perso: chi guarda
// ridigita all'infinito una password giusta. Per questo la schermata dice due
// cose diverse, e per questo la prova le distingue.
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

    function fine() {
        console.log("");
        if (banco.fallite > 0)
            console.log("FALLITE " + banco.fallite + " su "
                        + (banco.passate + banco.fallite));
        else
            console.log("TUTTE PASSATE (" + banco.passate + ")");
        Qt.exit(0);
    }

    // Il servizio PAM NON si sceglie qui. Lo dice `scripts/minerva-blocca
    // --quale-pam`, che è lo stesso codice che lo sceglie quando si blocca
    // davvero, e `scripts/prove.sh` lo passa in `MINERVA_PAM`.
    //
    // Prima questa riga diceva `return "hyprlock"`, scritto a mano. Sembrava
    // innocuo ed era la cosa peggiore: il 17 agosto 2026 il blocco vero era
    // già passato a un altro file PAM e questa prova continuava a dire
    // «tutte passate» provando quello di prima. Una prova che sceglie da sé
    // cosa provare non prova il programma: prova sé stessa.
    readonly property string servizio: Quickshell.env("MINERVA_PAM") || "liquid-de"

    PamContext {
        id: pam
        config: banco.servizio
        user: Quickshell.env("USER") || "nessuno"

        // Una password che non può essere di nessuno. Non si prova la
        // password giusta: si prova che PAM RISPONDA.
        onResponseRequiredChanged: if (pam.responseRequired)
            pam.respond("password-che-non-esiste-" + Date.now())

        onCompleted: function (result) {
            banco.verifica("PAM risponde invece di rompersi",
                           result === PamResult.Failed || result === PamResult.MaxTries,
                           "risposta: " + PamResult.toString(result));
            banco.verifica("e la risposta a una password inventata NON è «giusta»",
                           result !== PamResult.Success,
                           "PAM ha accettato una password a caso: è gravissimo");
            banco.fine();
        }

        onError: function (e) {
            banco.verifica("PAM è raggiungibile", false,
                           "errore " + PamError.toString(e)
                           + " — con questo, uno schermo bloccato non si "
                           + "aprirebbe nemmeno con la password giusta");
            banco.fine();
        }
    }

    Component.onCompleted: {
        console.log("── Prove del blocco schermo ──────────────────────────");
        banco.verifica("il servizio PAM è dichiarato", banco.servizio !== "");
        if (!pam.start()) {
            banco.verifica("PAM si avvia", false,
                           "start() ha detto di no: il servizio «"
                           + banco.servizio + "» non è utilizzabile");
            banco.fine();
        }
    }

    // Se PAM non risponde affatto, la prova non deve restare appesa per
    // sempre: un banco di prova che non finisce blocca la suite.
    Timer {
        interval: 15000
        running: true
        onTriggered: {
            banco.verifica("PAM risponde entro quindici secondi", false,
                           "nessuna risposta: la catena è interrotta");
            banco.fine();
        }
    }
}

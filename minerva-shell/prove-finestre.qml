import QtQuick
import Quickshell
import "core" as Core

// ProveFinestre — Le prove di «dove può stare una finestra».
//
//     qs -p minerva-shell/prove-finestre.qml
//
// ── Perché proprio questa parte ────────────────────────────────────────────
//
// Perché è il difetto che Giacomo vede ogni giorno, e perché per mesi la
// garanzia che doveva impedirlo lo CAUSAVA.
//
// Guardava un bordo solo. Se una finestra stava troppo in alto — sotto la
// barra della scrivania, quindi senza maniglia — la spingeva giù. Ma spostare
// non è ridimensionare: una finestra alta quanto tutto lo schermo, spinta giù
// di quarantaquattro pixel, esce dal bordo basso di quarantaquattro pixel.
// Il difetto si spostava, non spariva. Misurato il 10 agosto 2026:
// `at: -2,44  size: 1536,864` su uno schermo alto 864.
//
// `dentroLoSpazio()` è pura apposta — prende numeri, restituisce numeri — così
// che queste prove non debbano aprire nessuna finestra vera.
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

    /// Lo schermo di Giacomo: 1920×1080 a scala 1,25 → 1536×864 logici, con
    /// 44 px riservati in cima dalla barra della scrivania.
    readonly property var spazio: ({ "x": 0, "y": 44, "w": 1536, "h": 820 })

    function dentro(r, u) {
        return r.x >= u.x && r.y >= u.y
            && r.x + r.w <= u.x + u.w
            && r.y + r.h <= u.y + u.h;
    }

    Component.onCompleted: {
        console.log("── Prove delle finestre ──────────────────────────────");

        var W = Core.Windows;
        var u = banco.spazio;

        // ── Il difetto #14, coi numeri veri di quel giorno ────────────────
        var r = W.dentroLoSpazio({ "x": -2, "y": 44, "w": 1536, "h": 864 }, u, 0);
        verifica("la finestra alta quanto lo schermo viene rimpicciolita",
                 r !== null && r.h === 820,
                 r ? ("altezza " + r.h + ", attesa 820") : "non ha corretto niente");
        verifica("e non esce più dal bordo basso",
                 r !== null && banco.dentro(r, u),
                 r ? ("bordo basso a " + (r.y + r.h) + ", massimo 864") : "");

        // ── Una finestra normale non si tocca ─────────────────────────────
        verifica("una finestra che ci sta già viene lasciata stare",
                 W.dentroLoSpazio({ "x": 300, "y": 200, "w": 900, "h": 600 }, u, 0) === null);

        // ── I quattro bordi, uno per uno ──────────────────────────────────
        var alto = W.dentroLoSpazio({ "x": 100, "y": 0, "w": 400, "h": 300 }, u, 0);
        verifica("sopra la linea: scende sotto la barra della scrivania",
                 alto !== null && alto.y === 44, alto ? ("y " + alto.y) : "");

        var basso = W.dentroLoSpazio({ "x": 100, "y": 700, "w": 400, "h": 300 }, u, 0);
        verifica("sotto il bordo: risale invece di sporgere",
                 basso !== null && basso.y + basso.h === 864,
                 basso ? ("bordo basso " + (basso.y + basso.h)) : "");

        var destra = W.dentroLoSpazio({ "x": 1400, "y": 200, "w": 400, "h": 300 }, u, 0);
        verifica("oltre il bordo destro: rientra",
                 destra !== null && destra.x + destra.w === 1536,
                 destra ? ("bordo destro " + (destra.x + destra.w)) : "");

        var sinistra = W.dentroLoSpazio({ "x": -50, "y": 200, "w": 400, "h": 300 }, u, 0);
        verifica("oltre il bordo sinistro: rientra",
                 sinistra !== null && sinistra.x === 0, sinistra ? ("x " + sinistra.x) : "");

        // ── Il margine per chi la barra ce l'ha SOPRA ─────────────────────
        //
        // Le finestre altrui ricevono una barra da noi, disegnata sopra il
        // loro bordo alto: lassù serve anche l'altezza della barra, o la
        // maniglia finisce sotto quella della scrivania.
        var conBarra = W.dentroLoSpazio({ "x": 100, "y": 10, "w": 400, "h": 900 }, u, 42);
        verifica("con la barra sopra, il bordo alto lascia posto anche a lei",
                 conBarra !== null && conBarra.y === 86,
                 conBarra ? ("y " + conBarra.y + ", attesa 86") : "");
        verifica("e l'altezza tiene conto della barra",
                 conBarra !== null && conBarra.h === 778,
                 conBarra ? ("altezza " + conBarra.h + ", attesa 778") : "");

        // ── Non si rimpicciolisce fino a farla sparire ────────────────────
        var minuscolo = W.dentroLoSpazio({ "x": 0, "y": 44, "w": 100, "h": 80 },
                                         { "x": 0, "y": 44, "w": 1536, "h": 820 }, 0);
        verifica("una finestra piccola resta piccola, non viene gonfiata",
                 minuscolo === null);

        // ── Le cose che non ci sono ───────────────────────────────────────
        verifica("senza finestra non si inventa niente",
                 W.dentroLoSpazio(null, u, 0) === null);
        verifica("senza sapere lo spazio non si tocca niente",
                 W.dentroLoSpazio({ "x": 0, "y": 0, "w": 10, "h": 10 }, null, 0) === null);

        // ── Due schermi: ognuno col suo spazio ────────────────────────────
        //
        // Il 10 agosto, appena attaccato il secondo monitor, la garanzia ha
        // trascinato sul monitor attivo anche le finestre dell'ALTRO: il
        // terminale di Giacomo, che stava sul portatile, si è ritrovato a
        // x=1536, cioè appena fuori dal suo schermo. Una garanzia che sposta
        // le finestre dove non erano è peggio del difetto che doveva
        // impedire.
        //
        // Lo scenario è quello vero di quel giorno: portatile 1536×864 con 44
        // riservati, e un secondo schermo 1920×1080 attaccato a destra.
        W.spaziPerMonitor = [
            { "id": 0, "nome": "eDP-1", "attivo": false,
              "x": 0, "y": 44, "w": 1536, "h": 820,
              "sx": 0, "sy": 0, "sw": 1536, "sh": 864 },
            { "id": 1, "nome": "HEADLESS", "attivo": true,
              "x": 1536, "y": 0, "w": 1920, "h": 1080,
              "sx": 1536, "sy": 0, "sw": 1920, "sh": 1080 }
        ];

        var suPortatile = { "x": 300, "y": 120, "w": 800, "h": 600 };
        var suEsterno = { "x": 1800, "y": 200, "w": 900, "h": 600 };

        verifica("una finestra sul portatile prende lo spazio del portatile",
                 W.spazioPer(suPortatile).nome === "eDP-1",
                 W.spazioPer(suPortatile).nome);
        verifica("una finestra sull'esterno prende lo spazio dell'esterno",
                 W.spazioPer(suEsterno).nome === "HEADLESS",
                 W.spazioPer(suEsterno).nome);

        // Il punto che è costato: il monitor ATTIVO era l'esterno, e la
        // finestra del portatile veniva portata di là.
        verifica("e quella sul portatile NON viene trascinata sull'altro schermo",
                 W.dentroLoSpazio(suPortatile, W.spazioPer(suPortatile), 0) === null);

        // Una finestra a cavallo dei due sta dove ne sta di più.
        var aCavallo = { "x": 1400, "y": 200, "w": 400, "h": 300 };
        verifica("una finestra a cavallo sta dove ne sta di più",
                 W.spazioPer(aCavallo).nome === "HEADLESS",
                 W.spazioPer(aCavallo).nome);

        // ── Il monitor sotto il PUNTATORE, per l'aggancio ─────────────────
        //
        // Con due schermi l'aggancio deve scattare sul monitor dove si mira,
        // non su quello attivo — e il punto si cerca nel contorno VERO dello
        // schermo: sopra la barra della scrivania (y=20) è ancora il
        // portatile, anche se il suo spazio utile comincia a 44.
        verifica("spazioPerPunto: il puntatore sul portatile trova il portatile",
                 W.spazioPerPunto(200, 300).nome === "eDP-1",
                 W.spazioPerPunto(200, 300).nome);
        verifica("spazioPerPunto: sopra la barra della scrivania è ancora il portatile",
                 W.spazioPerPunto(200, 20).nome === "eDP-1",
                 W.spazioPerPunto(200, 20).nome);
        verifica("spazioPerPunto: sullo schermo esterno trova l'esterno",
                 W.spazioPerPunto(2000, 500).nome === "HEADLESS",
                 W.spazioPerPunto(2000, 500).nome);

        // ── «Ingrandita» si decide sul monitor DELLA finestra ─────────────
        //
        // Il monitor ATTIVO in questo scenario è l'esterno. Una finestra
        // ingrandita sul portatile deve restare «ingrandita» anche se il
        // fuoco sta altrove: confrontandola con lo spazio attivo il pulsante
        // mostrava il segno sbagliato su ogni finestra dell'altro schermo.
        //
        // `own: true` rende le prove indipendenti dalle impostazioni: per le
        // finestre di Minerva la barra sta DENTRO, quindi il margine è zero
        // senza dover chiedere niente al demone.
        var ingranditaPortatile = W.rectMassimo(
            W.spazioPer(suPortatile), 0, W.bordo);
        var fintaSulPortatile = { "own": true,
                                  "x": ingranditaPortatile.x,
                                  "y": ingranditaPortatile.y,
                                  "w": ingranditaPortatile.w,
                                  "h": ingranditaPortatile.h };
        // «Ingrandita» è uno stato del compositore, non una geometria: una
        // finestra ridimensionata a mano fino ai bordi NON è ingrandita, e il
        // compositore non la farebbe tornare piccola trascinandola.
        verifica("ingrandita è quello che dice il compositore",
                 W.isMaximized({ "modoSchermo": 1 }));
        verifica("grande quanto lo spazio ma non ingrandita dal compositore: no",
                 !W.isMaximized({ "own": true, "modoSchermo": 0,
                                  "x": fintaSulPortatile.x, "y": fintaSulPortatile.y,
                                  "w": fintaSulPortatile.w, "h": fintaSulPortatile.h }));
        verifica("a schermo intero non è «ingrandita»",
                 !W.isMaximized({ "modoSchermo": 2 }));
        verifica("nessuna finestra, nessun ingrandimento", !W.isMaximized(null));

        // ── Le zone di aggancio, coi numeri veri ──────────────────────────
        var zonaSx = W.rectZona("left", W.spazioPer(suEsterno));
        verifica("aggancio a sinistra sull'esterno: metà sinistra del SUO spazio",
                 zonaSx.x === 1536 && zonaSx.y === 0
                 && zonaSx.w === 960 && zonaSx.h === 1080,
                 JSON.stringify(zonaSx));
        var angoloBassoDx = W.rectZona("br", W.spazioPer(suEsterno));
        verifica("aggancio nell'angolo in basso a destra: un quarto",
                 angoloBassoDx.x === 2496 && angoloBassoDx.y === 540
                 && angoloBassoDx.w === 960 && angoloBassoDx.h === 540,
                 JSON.stringify(angoloBassoDx));
        verifica("aggancio in alto è tutto lo spazio utile",
                 W.rectZona("top", W.spazioPer(suEsterno)).w === 1920
                 && W.rectZona("top", W.spazioPer(suEsterno)).h === 1080);
        verifica("una zona inventata non esiste",
                 W.rectZona("", banco.spazio) === null
                 && W.rectZona(null, banco.spazio) === null);

        // E senza secondo schermo tutto torna com'era.
        W.spaziPerMonitor = [];
        verifica("con un monitor solo si ricade sullo spazio unico",
                 W.spazioPer(suPortatile) === W.usable);

        // ── Il rettangolo di «ingrandisci» ────────────────────────────────
        //
        // È lo stesso conto di maximize, estratto in una funzione pura: deve
        // lasciare posto alla cornice (due pixel per lato) e alla barra del
        // titolo quando sta sopra.
        var massimo = W.rectMassimo(banco.spazio, 0, W.bordo);
        verifica("rectMassimo: dentro il bordo, senza barra sopra",
                 massimo.x === 2 && massimo.y === 46
                 && massimo.w === 1532 && massimo.h === 816,
                 JSON.stringify(massimo));
        var massimoConBarra = W.rectMassimo(banco.spazio, 34, W.bordo);
        verifica("rectMassimo: con la barra sopra lascia posto anche a lei",
                 massimoConBarra.y === 80 && massimoConBarra.h === 782,
                 JSON.stringify(massimoConBarra));
        verifica("rectMassimo senza spazio non inventa niente",
                 W.rectMassimo(null, 0, W.bordo) === null);

        console.log("");
        if (banco.fallite > 0)
            console.log("FALLITE " + banco.fallite + " su "
                        + (banco.passate + banco.fallite));
        else
            console.log("TUTTE PASSATE (" + banco.passate + ")");
    }
}

import QtQuick
import Quickshell
import "core" as Core

// ProveAudio — Le prove del volume: il tetto, e il muto che va tolto.
//
//     qs -p minerva-shell/prove-audio.qml
//
// ── Perché proprio questa parte ────────────────────────────────────────────
//
// Perché il 5 agosto 2026 falliva nel modo peggiore che esista: **dando
// ragione**. Giacomo mette il muto, preme «alza volume», e il numero
// sull'avviso a schermo sale — 40, 45, 50 — mentre non esce un suono. Il tasto
// non sembrava ignorato: sembrava rotto, e non c'era niente da guardare che
// spiegasse la differenza. Parole sue: «se metto muto e poi clicco su alza o
// abbassa volume rimane muto, per riavere l'audio devo premere su muto».
//
// PipeWire non si finge, ma non serve: `Core.SystemState.decidiVolume()`
// prende tre numeri e non tocca l'audio. È la stessa forma di
// `Core.Media.scegli` — la decisione separata da chi la esegue, apposta per
// poterla provare.
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

    Component.onCompleted: {
        console.log("── Prove del volume ──────────────────────────────────");

        var S = Core.SystemState;

        // ── Il difetto segnalato ─────────────────────────────────────────
        var d = S.decidiVolume(55, true, 100);
        verifica("alzare il volume mentre è muto toglie il muto",
                 d.smuta === true && d.volume === 55,
                 JSON.stringify(d));

        d = S.decidiVolume(45, true, 100);
        verifica("anche ABBASSARE toglie il muto",
                 d.smuta === true && d.volume === 45,
                 JSON.stringify(d));

        d = S.decidiVolume(55, false, 100);
        verifica("se non era muto non si tocca niente",
                 d.smuta === false, JSON.stringify(d));

        // ── Zero non è muto ──────────────────────────────────────────────
        //
        // Sono due stati diversi: da zero si risale con un tasto, dal muto no.
        // Confonderli toglie a chi ascolta il modo di distinguerli.
        d = S.decidiVolume(0, true, 100);
        verifica("portare a zero da muto NON toglie il muto",
                 d.smuta === false && d.volume === 0, JSON.stringify(d));

        d = S.decidiVolume(-5, true, 100);
        verifica("scendere sotto zero resta a zero e resta muto",
                 d.volume === 0 && d.smuta === false, JSON.stringify(d));

        // ── Il tetto ─────────────────────────────────────────────────────
        //
        // PipeWire lascia salire ben oltre il 100%: è amplificazione, e
        // premendo il tasto abbastanza volte si arrivava al 500%.
        d = S.decidiVolume(140, false, 100);
        verifica("oltre il tetto si taglia al tetto",
                 d.volume === 100 && d.tagliato === true, JSON.stringify(d));

        d = S.decidiVolume(-20, false, 100);
        verifica("sotto zero si taglia a zero, ed è «tagliato»",
                 d.volume === 0 && d.tagliato === true, JSON.stringify(d));

        d = S.decidiVolume(100, false, 100);
        verifica("esattamente al tetto NON è tagliato",
                 d.volume === 100 && d.tagliato === false, JSON.stringify(d));

        // Un tetto diverso dal 100 deve valere davvero: chi lo alza a 150
        // per un video che registra piano non deve trovarsi tagliato a 100.
        d = S.decidiVolume(130, true, 150);
        verifica("un tetto più alto viene rispettato, e smuta lo stesso",
                 d.volume === 130 && d.tagliato === false && d.smuta === true,
                 JSON.stringify(d));

        // ── I decimali ───────────────────────────────────────────────────
        //
        // Il cursore manda numeri con la virgola: un volume di 54,7 scritto
        // così com'è si trascina dietro l'errore a ogni passo.
        d = S.decidiVolume(54.7, false, 100);
        verifica("un valore con la virgola viene arrotondato",
                 d.volume === 55, JSON.stringify(d));

        console.log("");
        if (banco.fallite > 0)
            console.log("FALLITE " + banco.fallite + " su "
                        + (banco.passate + banco.fallite));
        else
            console.log("TUTTE PASSATE (" + banco.passate + ")");
    }
}

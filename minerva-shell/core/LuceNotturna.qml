pragma Singleton
import QtQuick
import Quickshell

import "." as Core

// LuceNotturna — Il filtro luce blu.
//
// ── Senza installare niente ────────────────────────────────────────────────
//
// I due programmi che fanno questo su Wayland (`wlsunset`, `gammastep`) qui
// non ci sono, e sarebbero due cose in più da installare, da far partire
// all'avvio e che possono mancare. Minerva sa già disegnare uno shader — è
// così che fa l'aurora della schermata di accesso — e Hyprland sa applicarne
// uno a tutto lo schermo (`decoration:screen_shader`).
//
// Il vantaggio non è solo una dipendenza in meno: applicato dal compositore,
// il filtro vale per OGNI cosa a schermo, giochi e filmati a schermo intero
// compresi, senza che nessun programma debba saperlo.
//
// ── Il conto della temperatura ─────────────────────────────────────────────
//
// I gradi Kelvin diventano tre moltiplicatori con l'approssimazione di Tanner
// Helland, che è quella che usano tutti e che sotto i 6500 K è indistinguibile
// dal calcolo vero. 6500 K è la luce del giorno e non tocca niente; 3400 K è
// la sera; 2000 K è quasi la luce di una candela.
QtObject {
    id: luce

    readonly property bool accesa: Core.Ipc.get("display.nightLight", false)
    readonly property int temperatura: Core.Ipc.get("display.nightLightTemp", 3800)
    /// Accende e spegne da sola all'ora scelta.
    readonly property bool automatica: Core.Ipc.get("display.nightLightAuto", false)
    readonly property int oraInizio: Core.Ipc.get("display.nightLightFrom", 21)
    readonly property int oraFine: Core.Ipc.get("display.nightLightTo", 7)

    /// Vero quando l'ora attuale è dentro la finestra scelta. Regge anche la
    /// finestra che scavalca la mezzanotte (21 → 7), che è quella normale.
    property bool dentroLOrario: false

    readonly property bool daApplicare:
        luce.accesa && (!luce.automatica || luce.dentroLOrario)

    property var _orologio: Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: luce.aggiornaOrario()
    }

    function aggiornaOrario() {
        var h = new Date().getHours();
        var a = luce.oraInizio;
        var b = luce.oraFine;
        luce.dentroLOrario = a === b ? false
            : (a < b ? (h >= a && h < b) : (h >= a || h < b));
    }

    onOraInizioChanged: luce.aggiornaOrario()
    onOraFineChanged: luce.aggiornaOrario()

    // ── I tre moltiplicatori ─────────────────────────────────────────────

    function _canale(v) { return Math.max(0, Math.min(1, v)); }

    /// Rosso, verde e blu per una temperatura in gradi Kelvin.
    function tinta(kelvin) {
        var t = Math.max(1000, Math.min(6500, kelvin)) / 100;
        var r, g, b;

        if (t <= 66) {
            r = 1;
        } else {
            r = 329.698727446 * Math.pow(t - 60, -0.1332047592) / 255;
        }

        if (t <= 66) {
            g = (99.4708025861 * Math.log(t) - 161.1195681661) / 255;
        } else {
            g = 288.1221695283 * Math.pow(t - 60, -0.0755148492) / 255;
        }

        if (t >= 66) {
            b = 1;
        } else if (t <= 19) {
            b = 0;
        } else {
            b = (138.5177312231 * Math.log(t - 10) - 305.0447927307) / 255;
        }

        return {
            "r": luce._canale(r),
            "g": luce._canale(g),
            "b": luce._canale(b)
        };
    }

    // ── Scrivere e applicare ─────────────────────────────────────────────
    //
    // Qui c'erano un modello di shader, un file generato in `~/.local/state`,
    // un `sed` dentro una shell e un `mv` atomico per non farlo mai leggere
    // vuoto. Tutta quella macchina serviva a una cosa sola: dire a Hyprland
    // una tinta, che lui accettava solo sotto forma di programma GLSL scritto
    // su disco. Dal 1º settembre 2026 non c'è più niente da aggirare — la
    // tinta va al compositore come tre numeri.
    //
    // Il cartello rosso «Screen shader parser: Error compiling shader», che
    // restava appiccicato in cima allo schermo e non se ne andava, se n'è
    // andato con loro.

    // ── Sempre l'ultima ──────────────────────────────────────────────────
    //
    // `applica()` non esegue: prenota. Muovendo il CURSORE della temperatura
    // ne parte una raffica, e al compositore va detto un colore solo: quello
    // in cui il dito si è fermato.
    //
    // La ragione ORIGINALE era peggiore, e vale la pena ricordarla perché
    // riguarda ogni `Exec` di questo progetto: `Exec.start()` assegna
    // `proc.command` su un processo che può essere ancora vivo, e Qt quel
    // comando non lo accetta — la chiamata sparisce **senza un errore**.
    // All'avvio ne bastavano due vicini perché la luce restasse spenta pur
    // essendo accesa. Trovato il 17 agosto 2026 da `prove-luce.qml`, che
    // passava da sola e falliva dopo un'altra prova. Adesso qui sotto non
    // nasce più nessun processo, ma il timer resta: la raffica c'è ancora.
    //
    // Il timer si dichiara con `running: false` esplicito e non nudo: una
    // `property var` con dentro un `Timer` senza `running` non viene
    // istanziata, e `restart()` finisce nel vuoto — provato, e per un quarto
    // d'ora è sembrato che la correzione non servisse a niente.
    property var _rimanda: Timer {
        id: rimandaTimer
        interval: 120
        repeat: false
        running: false
        onTriggered: luce._applicaDavvero()
    }

    function applica() {
        // Il valore buono è sempre l'ultimo: quelli in mezzo si possono
        // perdere, l'ultimo no.
        rimandaTimer.restart();
    }

    function _applicaDavvero() {
        // ── Non c'è nessuno shader, e non serve ──────────────────────────
        //
        // La tinta va dritta al compositore come tre moltiplicatori, e lui la
        // mette in una tabella di colore. Sono gli STESSI tre numeri che sotto
        // Hyprland finivano dentro un file GLSL: cambia solo che adesso non
        // passano da un file.
        var t = luce.daApplicare ? luce.tinta(luce.temperatura)
                                 : { "r": 1, "g": 1, "b": 1 };
        Compositore.coloreSchermo(t.r, t.g, t.b);
    }

    onDaApplicareChanged: luce.applica()
    onTemperaturaChanged: luce.applica()

    // All'avvio si applica com'è: se la sessione è ripartita di notte con la
    // luce accesa, deve essere già calda quando compare la scrivania.
    Component.onCompleted: luce.applica()
}

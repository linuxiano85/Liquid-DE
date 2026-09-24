pragma Singleton
import QtQuick

// Motion — Il vocabolario del movimento di Minerva.
//
// Un'interfaccia si riconosce da come si muove almeno quanto da come appare.
// Qui stanno le uniche durate e curve ammesse: se un'animazione ne usa altre,
// stona rispetto al resto anche quando presa da sola sembra corretta.
//
// Tre principi:
//
//  1. NIENTE SI MUOVE SENZA MOTIVO. Il movimento comunica da dove arriva una
//     cosa e dove va. I pannelli scendono dalla barra perché è lì che nascono.
//
//  2. L'USCITA È PIÙ RAPIDA DELL'ENTRATA. Chi chiude un pannello ha già deciso:
//     farlo aspettare è fastidioso. Chi lo apre sta ancora guardando.
//
//  3. UN SOLO RIMBALZO, PICCOLO. L'elastico dà vita alla superficie; se supera
//     il 6% diventa un giocattolo.
QtObject {
    id: motion

    // ── Una manopola sola per tutto il movimento ─────────────────────────
    //
    // Giacomo, 19 agosto 2026: «la disabilitazione dalla barra sul desktop e
    // nelle impostazioni non porta a nessun cambiamento».
    //
    // Aveva ragione, e la causa stava qui. I tre interruttori delle animazioni
    // scrivono `desktop.animations` e chiamano `Compositore.animazioni()`, che
    // spegne le animazioni **del compositore**: finestre che si aprono, cambio
    // scrivania, dissolvenze dei layer. Ma quello che si nota muovendosi in
    // Minerva sono le animazioni della SHELL — i pannelli che scendono, la
    // dock che si ingrandisce, i menu che compaiono — e queste durate erano
    // numeri fissi che nessuna impostazione poteva toccare.
    //
    // Adesso c'è `scala`, che le moltiplica tutte. Sessantaquattro file usano
    // questi nomi (`Theme.Motion.quick`) e non i numeri, quindi obbediscono
    // tutti senza che nessuno di loro venga toccato.
    //
    // **Zero vuol dire «niente animazioni»**: in QML una durata di zero non è
    // un'animazione lampo, è nessuna animazione — il valore arriva a
    // destinazione nello stesso fotogramma.
    //
    // Chi la lega è `shell.qml`, come fa già con `Typography.scala`: qui non
    // si sa che esistano né le impostazioni né un demone, e un vocabolario del
    // movimento che va a leggere le preferenze è un vocabolario che non si può
    // più riusare altrove.
    property real scala: 1.0

    // ── Durate (ms) ──────────────────────────────────────────────────────
    //
    // I numeri qui sotto sono il movimento a velocità normale: sono loro il
    // vocabolario, `scala` è solo il volume.

    /// Micro-reazioni: passaggio del mouse, pressione, cambio colore.
    readonly property int instant: Math.round(110 * motion.scala)
    /// Transizione standard: comparse, scambi di contenuto.
    readonly property int quick: Math.round(190 * motion.scala)
    /// Apertura di un pannello.
    readonly property int panel: Math.round(320 * motion.scala)
    /// Movimento ampio della superficie continua.
    readonly property int surface: Math.round(380 * motion.scala)
    /// Uscita: sempre più corta dell'entrata corrispondente.
    readonly property int exit: Math.round(160 * motion.scala)

    // ── La molla liquida ─────────────────────────────────────────────────
    //
    // Per quello che SCIVOLA da un posto all'altro — la goccia sotto la voce
    // scelta, sotto il puntatore, sotto la vista attiva: non ci arriva con
    // una curva di durata fissa ma con una molla, supera di un soffio e si
    // posa. È il movimento di Liquid DE («fluidità, desktop elastico, quasi
    // liquidità»), ed è una `SpringAnimation`, che col renderer software
    // costa quanto un'animazione di colore.
    //
    // La molla non ha una durata da moltiplicare: `scala` la rende più lenta
    // allentandola, e a zero la spegne del tutto (`liquido`).

    /// Falso con le animazioni spente: chi usa la molla la mette su
    /// `enabled`, e il valore arriva a destinazione nello stesso fotogramma.
    readonly property bool liquido: motion.scala > 0
    /// Rigidità: più alta, più svelta.
    readonly property real molla: 4.2 / Math.max(0.25, motion.scala)
    /// Smorzamento: sotto 1 supera il bersaglio e torna. 0.34 è un soffio.
    readonly property real smorzamento: 0.34

    // ── Curve ────────────────────────────────────────────────────────────
    // Le curve stanno come quaterne di controllo di una Bézier cubica, così
    // possono essere assegnate a `easing.bezierCurve`.

    /// Standard: parte decisa, si posa dolcemente. Per quasi tutto.
    readonly property var standard: [0.22, 0.61, 0.36, 1.0, 1.0, 1.0]

    /// Emergere: la superficie si estende con un accenno di elastico.
    readonly property var emerge: [0.18, 0.89, 0.32, 1.06, 1.0, 1.0]

    /// Ritrarsi: accelera e sparisce, senza indugio.
    readonly property var retract: [0.4, 0.0, 0.9, 0.55, 1.0, 1.0]



}

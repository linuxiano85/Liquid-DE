import QtQuick

import "../theme" as Theme

// Spunta — la casella che decide cosa si tocca e cosa no.
//
// Ha **tre** stati e non due, e il terzo è quello che la rende onesta: su una
// famiglia con dentro sei voci di cui tre spuntate, né il pieno né il vuoto
// direbbero la verità. Il trattino dice «alcune sì», ed è l'unico modo di
// guardare l'intestazione di un gruppo chiuso e sapere come sta.
//
// ── Perché il segno è fatto di RETTANGOLI e non di `Shape` ─────────────────
//
// Giacomo, 9 settembre 2026: «electron builder e pip e pacchetti già
// installati una volta cliccato lasciano residui di spunte sul grafico», e
// poco dopo: «miniature e cache addirittura risultano passare attraverso il
// grafico, facendo scroll su e giù si muovono su e giù dentro al grafico».
//
// Fotografato: scorrendo l'elenco, dentro l'anello compariva una colonna di
// spunte nere. Col renderer software una `Shape` dipinge anche **fuori dal
// ritaglio** del `Flickable` che la contiene, e lì sopra non ridipinge mai
// nessuno. È lo stesso difetto delle Impostazioni, scritto in
// `settings/sections/Page.qml` e in `minerva-residui-software`.
//
// Là la cura è ridipingere tutta la finestra mentre si scorre, e funziona —
// ma è una riparazione dopo il fatto, che a ogni fotogramma insegue una scia
// appena depositata. Qui si toglie la causa: due rettangoli girati fanno lo
// stesso segno di spunta, e un rettangolo il ritaglio lo rispetta.
//
// (Non un carattere «✓»: i caratteri di sistema non ce l'hanno tutti, e su una
// macchina senza quel glifo comparirebbe un rettangolo vuoto.)
Item {
    id: casella

    /// 0 = spenta, 1 = accesa, 2 = alcune (solo per i gruppi).
    property int stato: 0
    property bool attiva: true

    signal premuta()

    // Ventidue pixel e non venti, e un fondo che si vede: la prima versione
    // era un quadrato vuoto col bordo di `edge` — la riga sottile fatta
    // apposta per non farsi notare, cioè l'ultimo colore da dare all'unica
    // cosa su cui si deve cliccare. Giacomo: «le caselle di spunta sono quasi
    // invisibili».
    implicitWidth: 22
    implicitHeight: 22

    Rectangle {
        id: scatola
        anchors.fill: parent
        radius: Theme.Effects.radiusXS
        color: casella.stato === 0
               ? (dito.containsMouse ? Theme.Colors.hover : Theme.Colors.sunken)
               : Qt.alpha(Theme.Colors.accent, casella.attiva ? 1.0 : 0.45)
        border.width: casella.stato === 0 ? 1.5 : 0
        border.color: dito.containsMouse ? Theme.Colors.accent
                                         : Theme.Colors.edgeBright

        Behavior on color {
            ColorAnimation { duration: Theme.Motion.instant }
        }
    }

    // Il segno di spunta: due bracci girati che si incontrano in basso a
    // sinistra. Le misure sono su una griglia di 22, come la casella.
    Item {
        anchors.fill: parent
        visible: casella.stato === 1

        Rectangle {
            x: 5.2; y: 10.6
            width: 6.6; height: 2.6
            radius: 1.3
            rotation: 45
            transformOrigin: Item.Left
            color: Theme.Colors.textOnAccent
        }

        Rectangle {
            x: 9.2; y: 13.4
            width: 11.4; height: 2.6
            radius: 1.3
            rotation: -50
            transformOrigin: Item.Left
            color: Theme.Colors.textOnAccent
        }
    }

    // «Alcune sì»: un trattino, che non è né il pieno né il vuoto.
    Rectangle {
        anchors.centerIn: parent
        visible: casella.stato === 2
        width: 11; height: 2.6
        radius: 1.3
        color: Theme.Colors.textOnAccent
    }

    MouseArea {
        id: dito
        anchors.fill: parent
        // Il bersaglio è più grande del disegno: ventidue pixel sono pochi per
        // un dito, e questa finestra si usa anche col touchpad.
        anchors.margins: -6
        hoverEnabled: true
        enabled: casella.attiva
        cursorShape: Qt.PointingHandCursor
        onClicked: casella.premuta()
    }
}

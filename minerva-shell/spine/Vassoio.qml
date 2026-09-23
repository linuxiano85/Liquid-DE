import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../theme" as Theme
import "../ui" as Ui
import "../menu" as Menu

// Vassoio — le icone dei programmi che restano in vita senza finestra.
//
// ── Perché esiste ────────────────────────────────────────────────────────
//
// Giacomo, 12 agosto 2026: «una volta che premi sulla finestra per chiuderla
// dovrebbe rimanere in tray, cosa che non abbiamo».
//
// Non era una mancanza estetica. Antigravity, alla chiusura della finestra,
// non esce: si mette nel vassoio. Senza vassoio spariva e basta — sette
// processi e 605 MB vivi, nessuna finestra, nessuna icona, e nemmeno una riga
// nel gestore attività, che di serie mostra i programmi CON una finestra.
// Un programma diventato irraggiungibile dalla scrivania che lo ospita.
// Telegram, Discord, Steam, Nextcloud si comportano tutti così.
//
// ── Come funziona, per chi legge fra un anno ─────────────────────────────
//
// Il protocollo è StatusNotifierItem: il programma si registra su D-Bus, e
// chi disegna la barra («host») ne mostra l'icona. Quickshell fa da host e ci
// consegna `SystemTray.items`; qui c'è solo il disegno e i tre gesti.
//
//   clic          `activate()` — per quasi tutti vuol dire «rimettimi la
//                 finestra davanti», che è il gesto che serviva a Giacomo.
//                 Quelli che dichiarano `onlyMenu` non hanno un'azione: per
//                 loro il clic apre il menù, altrimenti non farebbe niente e
//                 sembrerebbe rotto.
//   clic destro   il menù del programma (Esci, Impostazioni, …), che arriva
//                 già fatto da D-Bus — disegnato però dal NOSTRO menù.
//   clic centrale `secondaryActivate()` — l'azione di riserva, quando c'è.
//
// ── Perché il menù ce lo disegniamo noi ──────────────────────────────────
//
// Quickshell sa aprire da sé il menù di un'icona (`QsMenuAnchor.open()`), e
// la prima versione faceva così. Non funzionava, e l'errore era esplicito:
//
//     Cannot call QsMenuAnchor.open() as quickshell was not started in
//     QApplication mode.
//
// Quella strada vuole `//@ pragma UseQApplication`, cioè QtWidgets caricato
// nella shell per tutta la sessione — memoria in più su ogni avvio per un
// menù che comparirebbe qualche volta al giorno, e per giunta con l'aspetto
// di un'altra scrivania.
//
// `QsMenuOpener` dà invece le voci come dati (testo, separatore, se ha figli)
// e le mettiamo nel `ContextMenu` di Minerva. Il contenuto è del programma,
// la forma è nostra: è la stessa divisione delle barre del titolo.
//
// ── Perché si mostrano TUTTE, anche le «passive» ─────────────────────────
//
// Il protocollo prevede uno stato `Passive` per «puoi nasconderla». Molti
// programmi lo dichiarano per distrazione e non lo cambiano mai: nasconderle
// vorrebbe dire rifare, con più lavoro, esattamente il buco che questo file
// chiude. Si vedono tutte finché non salta fuori un caso vero.
Row {
    id: vassoio

    spacing: Theme.Effects.space1
    visible: ripetitore.count > 0

    /// Le voci vive dell'ultimo menù aperto: l'azione che il ContextMenu
    /// rimanda indietro è la POSIZIONE nell'elenco, e qui si ritrova
    /// l'oggetto vero a cui dire «sei stato scelto».
    property var _voci: []

    Menu.ContextMenu {
        id: menuApp
        onTriggered: function(azione) {
            var i = parseInt(azione, 10);
            var voce = vassoio._voci[i];
            if (!voce) return;
            // Una voce con dei figli non «si attiva»: si apre. Le voci
            // arrivano da D-Bus quando servono, e al primo colpo possono non
            // esserci ancora: si riprova una volta sola, dopo un attimo.
            if (voce.hasChildren) vassoio.apri(voce, true);
            else voce.triggered();
        }
    }

    /// Mostra il menù di `radice` (l'icona, o una sua voce con figli).
    function apri(radice, ritenta) {
        var figli = radice && radice.children ? radice.children.values : [];
        if (figli.length === 0 && ritenta) {
            riprova.radice = radice;
            riprova.restart();
            return;
        }
        var voci = [];
        vassoio._voci = figli;
        for (var i = 0; i < figli.length; i++) {
            var e = figli[i];
            if (e.isSeparator) { voci.push({ "separator": true }); continue; }
            voci.push({
                // Le icone del programma hanno nomi del suo tema, non del
                // nostro: passarle a `Ui.Icon` darebbe quadrati vuoti.
                "label": e.text + (e.hasChildren ? " ›" : ""),
                "action": String(i)
            });
        }
        if (voci.length > 0) menuApp.openAtCursor(voci);
    }

    Timer {
        id: riprova
        interval: 150
        property var radice: null
        onTriggered: if (riprova.radice) vassoio.apri(riprova.radice, false)
    }

    Repeater {
        id: ripetitore
        model: SystemTray.items

        Ui.SpineButton {
            id: bottone
            required property var modelData

            anchors.verticalCenter: parent.verticalCenter
            // Stretto: qui i pulsanti sono tanti quanti i programmi aperti, e
            // con la spaziatura normale mangerebbero mezza barra.
            horizontalPadding: Theme.Effects.space1
            showGlow: false
            tooltip: bottone.modelData.tooltipTitle !== ""
                     ? bottone.modelData.tooltipTitle
                     : bottone.modelData.title

            onClicked: {
                if (bottone.modelData.onlyMenu) vassoio.apri(apritore, true);
                else bottone.modelData.activate();
            }
            onRightClicked: vassoio.apri(apritore, true)

            // Sta qui, e non nel menù, perché le voci arrivano da D-Bus con
            // calma: chiedendole solo al clic destro, il primo clic destro
            // troverebbe un menù vuoto.
            QsMenuOpener {
                id: apritore
                menu: bottone.modelData.menu
            }

            content: Item {
                width: 18
                height: 18

                // L'icona arriva dal programma, non dal nostro tema: è un
                // percorso o un'immagine passata su D-Bus. Nessun `Ui.Icon`,
                // che disegna i NOSTRI tracciati.
                Image {
                    anchors.fill: parent
                    source: bottone.modelData.icon
                    sourceSize.width: 18
                    sourceSize.height: 18
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    // Un'icona che non si carica lascerebbe un buco cliccabile
                    // e muto: meglio un punto che si vede.
                    Rectangle {
                        anchors.centerIn: parent
                        visible: parent.status !== Image.Ready
                        width: 8; height: 8; radius: 4
                        color: Theme.Colors.textMuted
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.MiddleButton
                onClicked: bottone.modelData.secondaryActivate()
            }
        }
    }
}

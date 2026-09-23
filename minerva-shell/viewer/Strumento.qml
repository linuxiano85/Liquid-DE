import QtQuick
import "../theme" as Theme
import "../ui" as Ui

// Strumento — Un pulsante della barra di Anteprima.
//
// È un `Ui.SpineButton` con dentro un'icona, e non un componente nuovo: la
// barra degli strumenti di una finestra e la barra della scrivania sono due
// posti diversi in cui si clicca la stessa cosa, e devono avere la stessa
// dimensione, lo stesso raggio e la stessa reazione. Un secondo pulsante
// disegnato a parte diverge dal primo entro un mese.
Ui.SpineButton {
    id: strumento

    /// Nome del tracciato di `Ui.Icon`.
    property string icona: ""
    /// Quarti di giro dell'icona: le due frecce sono lo stesso tracciato.
    property real giro: 0
    /// «Adesso non si può»: l'icona si spegne, il pulsante resta lì.
    property bool spento: false

    // Ruolo e nome li dà già `SpineButton`, da cui questo discende. Qui si
    // aggiunge la sola cosa che SpineButton non può sapere: quando il comando
    // non è disponibile va SALTATO, o chi naviga a tastiera ci finisce sopra e
    // preme a vuoto.
    Accessible.ignored: strumento.spento

    // Senza `anchors`: `SpineButton` misura il proprio contenuto con
    // `childrenRect`, e un figlio ancorato al genitore misura il genitore che
    // sta misurando lui — è un anello, e Qt lo dice a ogni fotogramma.
    content: Ui.Icon {
        width: 18
        height: 18
        name: strumento.icona
        // I comandi di una barra restano disegnati da noi anche con un tema di
        // icone classico: sono parte del disegno del componente, non
        // iconografia. Vedi il commento in `ui/Icon.qml`.
        alwaysDrawn: true
        rotation: strumento.giro
        color: strumento.spento ? Theme.Colors.textFaint : Theme.Colors.text
    }
}

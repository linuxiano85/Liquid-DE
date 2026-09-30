import QtQuick

// Tentativi — Quante password sbagliate di fila, e la pausa che ne viene.
//
// ── Perché uno solo per tutto il blocco, e non uno per schermo ──────────────
//
// La schermata di blocco è una per SCHERMO: il protocollo vuole una superficie
// per monitor, e `blocco.qml` ne crea una per ciascuno. Il contatore stava
// dentro ognuna, e staccando e riattaccando un monitor nasceva una superficie
// nuova con zero errori: se il compositore le dava il fuoco, la pausa
// crescente — quella che ferma chi prova password a raffica — ripartiva da
// capo. Trovato in revisione il 30 settembre 2026.
//
// Adesso il conto sta qui, uno per tutto il blocco, e le superfici lo
// guardano. Anche il TEMPO della pausa sta qui e non in una superficie: una
// superficie che sparisce a metà pausa (monitor staccato) non deve lasciare
// il campo spento per sempre — un blocco che non si apre è un computer perso,
// la regola in cima a `blocco.qml`.
QtObject {
    id: tentativi

    /// Quante volte di fila si è sbagliato.
    property int errori: 0
    /// Vero durante la pausa: il campo resta spento.
    property bool inPausa: false

    /// Cresce e si ferma a otto secondi: il perché è in `Blocco.qml`, accanto
    /// al campo.
    readonly property int pausa: tentativi.errori === 0 ? 0
        : Math.min(8000, 500 * Math.pow(2, tentativi.errori - 1))

    function sbagliato() {
        tentativi.errori++;
        tentativi.inPausa = tentativi.pausa > 0;
        if (tentativi.inPausa)
            tentativi._attesa.restart();
    }

    function giusto() {
        tentativi.errori = 0;
        tentativi.inPausa = false;
        tentativi._attesa.stop();
    }

    property Timer _attesa: Timer {
        interval: tentativi.pausa
        onTriggered: tentativi.inPausa = false
    }
}

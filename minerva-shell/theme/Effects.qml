pragma Singleton
import QtQuick

// Metriche Minerva — «Continuum»
//
// Spaziature e raggi non sono numeri liberi: appartengono a una scala. Due
// margini di 14 e 16 pixel non si distinguono a occhio, ma insieme fanno
// sembrare l'interfaccia disallineata senza che si capisca perché.
//
// Tutto qui dentro è multiplo di 4.
//
// ── SU UNA SCALA, IL GRADINO NON USATO NON È CODICE MORTO ────────────────
//
// Una scala di raggi che va da XS a LG e poi salta l'XL non è una scala: è un
// elenco di numeri che qualcuno ha usato. Il valore di avere una scala sta
// nel fatto che ESISTE PRIMA di servire — chi deve scegliere un raggio pesca
// dal vocabolario invece di inventare un 30. Quindi `radiusXL` resta anche se
// oggi nessuno lo nomina, e va escluso dalle battute sul codice inutilizzato.
//
// Quello che invece è stato tolto (3 agosto 2026) è ciò che apparteneva a
// FUNZIONI SPARITE, e non a una scala: la misura del nodo del Portal Matrix —
// il disegno sostituito dalla ricerca universale — i sei valori di due livelli
// di ombra che il Continuum ha abbandonato passando alla membrana unica, e
// un'«altezza standard di riga» che nessuna lista rispettava, cioè una
// convenzione dichiarata e mai seguita: peggio che assente.
QtObject {
    // ── Scala di spaziatura ──────────────────────────────────────────────
    readonly property int space1: 4    // fra elementi legati (icona e testo)
    readonly property int space2: 8    // dentro un componente
    readonly property int space3: 12   // fra componenti vicini
    readonly property int space4: 16   // margine interno standard
    readonly property int space5: 24   // fra gruppi
    readonly property int space6: 32   // fra sezioni
    readonly property int space7: 48   // respiro ampio

    // ── Raggi ────────────────────────────────────────────────────────────
    //
    // Generosi: è la scelta che più di ogni altra fa sembrare un'interfaccia
    // curata invece che assemblata. Il raccordo `shoulder` è quello concavo
    // che unisce i pannelli alla barra — è la firma di Minerva.
    readonly property int radiusXS:   6
    readonly property int radiusSM:   10
    readonly property int radiusMD:   16
    readonly property int radiusLG:   24
    readonly property int radiusXL:   32
    readonly property int radiusFull: 999

    /// Il raggio degli angoli di una FINESTRA.
    ///
    /// È lo stesso `BARRA_RAGGIO` del compositore (`compositore/src/barra.h`),
    /// che arrotonda la cima della barra del titolo disegnata da lui. Le
    /// nostre finestre si disegnano la propria cornice, quelle degli altri
    /// programmi la ricevono dal compositore: se i due numeri non coincidono,
    /// sulla stessa scrivania convivono due angoli diversi e si vede.
    ///
    /// Dieci e non `radiusMD`: gli altri raggi qui sopra sono per i pannelli e
    /// le schede, che sono oggetti piccoli dentro una finestra. Una finestra
    /// intera con l'angolo da sedici sembra un widget ingrandito.
    readonly property int radiusWindow: 10

    /// Raggio del raccordo concavo fra barra e pannello.
    readonly property int shoulder: 22

    // ── Struttura ────────────────────────────────────────────────────────
    readonly property int barHeight: 44
    /// Lato di un pulsante quadrato nella barra.
    readonly property int barButton: 32

    // ── Bordi ────────────────────────────────────────────────────────────
    readonly property real hairline: 1

    // ── Elevazione ───────────────────────────────────────────────────────
    // Tre soli livelli. Un'ombra più marcata di così, su fondo scuro, non si
    // vede: si percepisce solo come sporcizia attorno al bordo.

}

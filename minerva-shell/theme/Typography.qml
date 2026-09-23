pragma Singleton
import QtQuick

// Tipografia Minerva — «Continuum»
//
// Due famiglie, con ruoli separati e non intercambiabili:
//
//  · Adwaita Sans (fontDisplay) — la voce di Minerva: titoli, etichette,
//    testo dell'interfaccia.
//
//  · Noto Sans Mono (fontMono) — solo per DATI: orologio, percentuali,
//    combinazioni di tasti, valori numerici. La larghezza fissa evita che i
//    numeri «ballino» quando cambiano, che è l'unico motivo serio per usare
//    un monospace in un'interfaccia.
//
// ── Il 3 settembre 2026: perché sono cambiate tutte e due ────────────────
//
// Giacomo: «un sacco di gente sta dicendo che sembra vecchio già dalla sua
// creazione [...] dicono che ha un aspetto brutto e superato».
//
// Erano Rajdhani e Share Tech Mono. Sono due caratteri belli e sono anche una
// DATA: insieme sono la firma delle scrivanie Linux personalizzate del
// 2016-2021, e si riconoscono prima di leggerle. Un carattere non è una
// pelle che si mette sopra: `fontDisplay` compare in 468 punti, cioè È
// l'interfaccia, e qualunque cosa ci si scriva dentro eredita quell'epoca.
//
// ── E non era solo il carattere: era tutto quello che gli girava intorno ──
//
// La cosa che si è vista solo mettendo in fila i numeri. Rajdhani è
// condensato e ha aste sottili, quindi:
//
//   · a corpo 14 il testo LEGGEVA grigio (Giacomo, 10 agosto) benché il
//     colore fosse giusto — e la cura è stata portare il corpo a 500;
//   · così `weightRegular` e `weightMedium` sono diventati **lo stesso
//     numero**, in 263 punti che chiedevano due pesi diversi e ne
//     ricevevano uno: la gerarchia non esisteva per costruzione;
//   · e le crenature (1,6 sui titoli, 1,2 sulle etichette) esistevano per
//     aprire un condensato che alle misure grandi si tocca.
//
// Cioè: metà delle scelte tipografiche erano compensazioni di quella prima.
// Cambiando il carattere e basta, le compensazioni sarebbero diventate loro il
// difetto — testo spaziato, e nessuna differenza fra normale e medio. Per
// questo qui sotto cambiano insieme famiglia, pesi e crenature.
//
// ── Come si torna indietro ───────────────────────────────────────────────
//
// Rimettendo `Rajdhani` e `Share Tech Mono` qui sotto, `weightRegular` a 500 e
// le crenature a 1.6 / 0.9 / 0.5 / 1.2. Sono sei righe: è una scelta di
// Giacomo, e deve restare facile da disfare.
//
// La scala è più ampia di quella precedente. I 10–12px di prima erano scelti
// per far stare tutto; il risultato era denso e faticoso. Meglio mostrare meno
// cose, più grandi.
//
// Come in `Effects.qml`: **il gradino non usato di una scala non è codice
// morto**. `sizeDisplay`, `weightLight`, le due crenature e le due
// interlinee oggi non li nomina nessuno, e restano — una scala tipografica
// vale perché esiste prima di servire, e chi deve scegliere un corpo pesca
// da qui invece di scrivere 19. Da escludere dalle battute sull'inutilizzato.
QtObject {
    // ── Famiglie ─────────────────────────────────────────────────────────
    // Adwaita Sans è installato su questa macchina ed è la faccia
    // dell'interfaccia di GNOME dal 47 in poi — cioè un carattere che nel 2026
    // si legge come «adesso» e non come un'epoca. Ha tutti i pesi, dal
    // ExtraLight al Black, e questo conta: la gerarchia qui sotto ne usa
    // quattro, e con Rajdhani due di quei quattro erano lo stesso.
    readonly property string fontDisplay: "Adwaita Sans"
    readonly property string fontMono:    "Noto Sans Mono"

    // ── Scala ────────────────────────────────────────────────────────────
    // ── Alzata di un punto, il 2 agosto 2026 ─────────────────────────────
    //
    // Giacomo: «rendi i caratteri leggermente più grandi di base, sono poco
    // leggibili». Un punto per gradino, non due: la scala deve restare la
    // stessa proporzione, e Rajdhani è un condensato — cresce in altezza più
    // che in larghezza, quindi un punto si sente più di quanto sembri.
    // ── E ingranditi in blocco, per chi non ci arriva ────────────────────
    //
    // `scala` è un moltiplicatore che vale 1 di suo e che le Impostazioni
    // portano fino a 1.3 (Accessibilità → Dimensione del testo). La scriveva
    // qualcuno da fuori, come `scheme` e `accent`: la tipografia non deve
    // conoscere il demone, o non si potrebbe più riusare.
    //
    // Il tetto è 1.3 e non è timidezza. Molte altezze in Minerva sono numeri
    // fissi — una riga delle impostazioni è alta 44, un campo di testo 34 —
    // e oltre quel punto il testo cresciuto comincia a toccare i bordi.
    // Alzarlo vuol dire prima far crescere anche quelle, che è un lavoro suo.
    property real scala: 1.0

    readonly property int sizeDisplay: Math.round(36 * scala)  // titolo di un pannello a schermo intero
    readonly property int sizeXL:      Math.round(28 * scala)  // titolo di sezione importante
    readonly property int sizeLG:      Math.round(20 * scala)  // titolo secondario
    readonly property int sizeMD:      Math.round(16 * scala)  // testo corrente dell'interfaccia
    readonly property int sizeSM:      Math.round(14 * scala)  // testo di supporto, descrizioni
    readonly property int sizeXS:      Math.round(12 * scala)  // micro-etichette, unità di misura

    // ── Pesi ─────────────────────────────────────────────────────────────
    //
    // ── PERCHÉ IL CORPO DEL TESTO È MEDIUM E NON REGULAR ─────────────────
    //
    // Giacomo, 10 agosto 2026: «il testo dovrebbe essere più bianco perché
    // allo stato attuale sembra grigio e quindi non ben visibile».
    //
    // Il colore era già giusto, e si può dimostrare: il testo di Minerva sul
    // tema notte è #F7F7F7, e su un riquadro delle Impostazioni rende 16,6:1
    // contro una scrivania scura e 12,3:1 contro una chiara — molto sopra il
    // 7:1 che si chiede a un testo piccolo. Anche il grado più tenue sta a
    // 6,3:1.
    //
    // Il grigio non era la tinta: era il TRATTO. Rajdhani è un condensato, e
    // il suo Regular ha aste sottili; a corpo 14 l'antialiasing media metà del
    // pixel col fondo, e l'occhio legge grigio anche se il colore è bianco. Il
    // rapporto di contrasto misura il colore, non la massa dell'inchiostro.
    //
    // Quindi il corpo del testo era salito a 500. La diagnosi era giusta — non
    // era il colore, era la massa dell'inchiostro — ma la cura aveva un costo
    // che allora non si è visto: **`weightRegular` e `weightMedium` sono
    // diventati lo stesso numero**, e sono usati 205 e 58 volte. Duecento-
    // sessantatré punti che chiedevano due pesi diversi e ne ricevevano uno.
    //
    // Col carattere nuovo il problema di partenza non c'è: Adwaita Sans non è
    // condensato e il suo Regular ha aste piene, quindi a corpo 14 legge bianco
    // senza bisogno di ingrassarlo. Il 400 torna a essere il corpo del testo, e
    // i cinque gradini tornano a essere cinque cose diverse.
    readonly property int weightLight:    300
    readonly property int weightRegular:  400
    readonly property int weightMedium:   500
    readonly property int weightSemiBold: 600
    readonly property int weightBold:     700

    // ── Tracking ─────────────────────────────────────────────────────────
    //
    // Erano 1.6 / 0.9 / 0.5 / 1.2, e servivano ad aprire un condensato che
    // alle misure grandi si tocca. Su un carattere di larghezza normale quelle
    // stesse cifre fanno il danno opposto: il testo si sfilaccia e sembra
    // spaziato a mano, che è un altro modo di sembrare vecchi.
    //
    // Resta una crenatura sola che vale davvero, ed è quella delle MAIUSCOLE
    // piccole: le micro-etichette in maiuscolo hanno bisogno d'aria in
    // qualunque carattere, perché le maiuscole non hanno ascendenti e
    // discendenti a separarle. Sui titoli si va appena in negativo, che è
    // quello che si fa quando un carattere cresce di corpo.
    readonly property real trackingDisplay:  -0.4  // MAIUSCOLE grandi
    readonly property real trackingTitle:    -0.2
    readonly property real trackingSubtitle:  0.0
    readonly property real trackingLabel:     0.8  // MAIUSCOLE piccole
    readonly property real trackingBody:      0.0

    // ── Interlinea ───────────────────────────────────────────────────────
    /// Moltiplicatore da applicare a `lineHeight` nei testi su più righe.
    readonly property real leadingTight: 1.15
    readonly property real leadingBody:  1.45
}

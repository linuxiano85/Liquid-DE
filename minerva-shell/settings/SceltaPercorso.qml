import QtQuick
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui
import "." as S

// SceltaPercorso — Un percorso si SCEGLIE, non si incolla.
//
// ── Perché esiste ─────────────────────────────────────────────────────────
//
// Giacomo, 5 settembre 2026: «qualsiasi opzione dove c'è la scelta del
// percorso o del file globalmente nelle impostazioni deve avere una selezione
// che si apre il mini file manager come la scelta della cartella in aspetto
// […] ci sono parti delle impostazioni dove devi incollare il percorso e a me
// non piace perché voglio semplicità».
//
// Aveva ragione ed era incoerente: «Aspetto» aveva già «Scegli una cartella…»
// e «Scegli dal disco…», mentre lo sfondo della schermata di accesso chiedeva
// di scrivere `/usr/share/backgrounds/…` a mano — con sotto la spiegazione di
// quali cartelle sono leggibili da tutti, che è il tipo di cosa che un
// selettore non ti fa nemmeno domandare.
//
// ── Il campo resta scrivibile ────────────────────────────────────────────
//
// Chi ha già il percorso negli appunti lo incolla e ha finito. Il difetto non
// era il campo: era che il campo fosse l'UNICA strada.
//
// ── Dove vive il selettore ───────────────────────────────────────────────
//
// `Ui.Scegli` copre tutta la finestra, quindi non può stare dentro una riga
// delle impostazioni: si aggancia al contenuto della finestra, **sotto la
// barra del titolo**. È la stessa scelta della Custodia, e per la stessa
// ragione: mentre si sceglie, la finestra deve restare chiudibile e
// trascinabile come sempre.
Row {
    id: scelta

    /// Il percorso attuale.
    property string percorso: ""

    /// Cartelle invece che file.
    property bool soloCartelle: false

    /// Si sta scegliendo un'IMMAGINE: allora si apre il selettore con le
    /// anteprime, non l'elenco dei nomi.
    ///
    /// Giacomo, 5 settembre 2026: «se voglio scegliere l'immagine dell'immagine
    /// di sfondo vedo solo la lista ma senza anteprima, quindi vado alla
    /// cieca». Aveva ragione, e il selettore giusto esisteva già: è quello di
    /// «Scegli dal disco…» in «Aspetto». Scegliere una fotografia dal nome del
    /// file è come scegliere un disco dal codice a barre.
    property bool immagini: false

    /// Che cosa si sta scegliendo, mostrato in cima al selettore.
    property string titolo: ""

    /// Che cosa si vede quando il campo è vuoto.
    property string segnaposto: ""

    /// Da dove partire quando non c'è ancora niente.
    property string daDove: ""

    /// Il percorso è cambiato — scritto a mano o scelto, è la stessa cosa per
    /// chi ascolta.
    signal scelto(string percorso)

    readonly property bool it: Core.Strings.lang === "it"

    /// La cartella che contiene un percorso. Se già finisce con `/`, o non ha
    /// nessuna barra, si restituisce com'è: meglio partire da casa che da una
    /// cartella inventata.
    function _cartellaDi(p) {
        var t = String(p || "");
        if (t === "" || t.charAt(t.length - 1) === "/")
            return t;
        var i = t.lastIndexOf("/");
        return i > 0 ? t.substring(0, i) : t;
    }

    spacing: Theme.Effects.space2
    /// L'altezza dei due pezzi. Non `implicitHeight`: su una `Row` è in sola
    /// lettura — la calcola lei dai figli — e assegnarla è un avviso a runtime
    /// che porta giù tutta la pagina. Trovato il 5 settembre 2026: la sezione
    /// «Accesso» restava bianca.
    property real altezza: 34

    Ui.Campo {
        id: campo
        width: Math.max(120, scelta.width - sfoglia.width - scelta.spacing)
        height: scelta.altezza
        text: scelta.percorso
        segnaposto: scelta.segnaposto

        // ── Scrivere aggiorna il valore, non solo il campo ───────────────
        //
        // Senza questa riga `percorso` resta quello di partenza mentre nel
        // campo c'è dell'altro: chi legge il componente da fuori — per
        // esempio per accendere il pulsante «Aggiungi» — vede sempre la
        // stringa vuota, e il pulsante non si accende mai.
        onCambiato: function (t) { scelta.percorso = t; }
        onAccettato: scelta.scelto(campo.text.trim())
    }

    Rectangle {
        id: sfoglia
        width: etichetta.implicitWidth + Theme.Effects.space4 * 2
        height: scelta.altezza
        radius: Theme.Effects.radiusSM
        color: presa.containsMouse ? Theme.Colors.raisedHigh
                                   : Theme.Colors.raised
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge
        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

        Text {
            id: etichetta
            anchors.centerIn: parent
            text: scelta.it ? "Sfoglia…" : "Browse…"
            color: Theme.Colors.text
            font { family: Theme.Typography.fontDisplay
                   ; pixelSize: Theme.Typography.sizeSM
                   ; weight: Theme.Typography.weightMedium }
        }

        MouseArea {
            id: presa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                var daDove = scelta.percorso !== "" ? scelta.percorso
                                                    : scelta.daDove;
                if (scelta.immagini) {
                    // `apri()` vuole una CARTELLA. Qui `percorso` è un file —
                    // è quello che si sta cambiando — e passarglielo così
                    // aprirebbe una cartella che non esiste, cioè un elenco
                    // vuoto. Si sale di uno.
                    conAnteprime.apri(scelta._cartellaDi(daDove));
                    return;
                }
                selettore.titolo = scelta.titolo;
                selettore.soloCartelle = scelta.soloCartelle;
                selettore.apri(daDove);
            }
        }
    }

    Ui.Scegli {
        id: selettore
        // Non figlio della riga: figlio della FINESTRA. Una riga alta trenta
        // pixel non può contenere un selettore di file, e ancorarlo qui lo
        // renderebbe alto trenta pixel.
        parent: scelta.Window.contentItem
        // `anchors.fill: parent ? parent : undefined` sarebbe la trappola
        // scritta in `qml-ancore-undefined`: **`undefined` non stacca
        // un'ancora**, la lascia dov'era. Qui il genitore c'è sempre — la
        // finestra esiste prima dei suoi figli — quindi non serve la domanda.
        anchors.fill: parent
        anchors.topMargin: Core.Ipc.get("windows.titleHeight", 34)
        soloCartelle: scelta.soloCartelle
        it: scelta.it

        onScelto: function (p) { scelta.scelto(p); }
    }

    // Quello con le anteprime, per le immagini. Anche lui figlio della
    // finestra e non della riga, per la stessa ragione.
    S.SelettoreImmagine {
        id: conAnteprime
        parent: scelta.Window.contentItem
        // `anchors.fill: parent` se lo mette da sé; qui si toglie solo la
        // fascia della barra del titolo, come per `Ui.Scegli` qui sopra: si
        // sceglie un'immagine, e intanto la finestra resta chiudibile.
        anchors.topMargin: Core.Ipc.get("windows.titleHeight", 34)
        onScelta: function (p) { scelta.scelto(p); }
    }
}

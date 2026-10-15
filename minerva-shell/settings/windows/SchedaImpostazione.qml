import QtQuick
import "../../windows11" as W

// SchedaImpostazione — Una riga di Impostazioni di Windows 11 (il
// SettingsCard di WinUI): icona a sinistra, titolo e descrizione, il comando
// a destra; se porta a un'altra pagina, la freccia › e tutta la scheda si
// clicca.
//
// Misure prese dalle schermate di Impostazioni (12 ottobre 2026, vedi
// `docs/impostazioni-windows-specifica.md`): alta almeno 68 con la
// descrizione e 54 senza, icona da 20 a 16 dal bordo, testo a 56, comando a
// 16 dal bordo destro, angoli da 4, un filo di contorno.
//
// `disponibile: false` è la voce che Windows ha e Liquid non ancora: si vede,
// grigia, con «Non ancora disponibile» al posto del comando, e non si clicca.
Rectangle {
    id: scheda

    property string icona: ""
    /// Al posto dell'icona Fluent, un'immagine (le icone a colori).
    property url immagine: ""
    property bool searchHighlighted: false
    property string searchTerms: ""
    property string titolo: ""
    property string descrizione: ""
    /// Porta a un'altra pagina: freccia › e clic su tutta la scheda.
    property bool porta: false
    property bool disponibile: true
    /// Il comando c'è ma adesso non si usa (come «Mostra il colore principale
    /// su Start…» in modalità chiara): titolo spento, comando spento, e la
    /// descrizione diventa una nota con la «i» blu.
    property bool disponibileComando: true
    /// Dentro un Expander: niente contorno né angoli, un filo sopra.
    property bool interna: false
    /// Rientro del testo dentro un Expander (allineato al titolo di sopra).
    property real rientro: 0
    /// Il filo che separa una riga interna da quella di sopra.
    property bool filoSopra: interna

    default property alias comando: posto.data
    signal attivata()

    readonly property bool it: W.Style.it
    // WinUI dispone il comando sotto al testo quando la riga non offre più
    // spazio leggibile: evita descrizioni ridotte a una parola per riga.
    readonly property bool comandoSotto: posto.visible && posto.width > 0
        && width - testi.x - posto.width - 32 < 180

    width: parent ? parent.width : 400
    // Misurate su Windows: le schede alte 69 (anche senza descrizione), le
    // righe dentro un Expander 50.
    implicitHeight: Math.max(scheda.interna ? (scheda.descrizione !== "" ? 69 : 50) : 69,
                             comandoSotto ? testi.implicitHeight + posto.childrenRect.height + 36
                                          : Math.max(testi.implicitHeight, posto.childrenRect.height) + 24)
    height: implicitHeight
    radius: scheda.interna ? 0 : 4
    color: !scheda.interna && scheda.porta && scheda.disponibile && presa.containsMouse
           ? (presa.pressed ? W.Style.gettoni.cardBackgroundSecondary : W.Style.gettoni.controlFillSecondary)
           : (scheda.interna ? "transparent" : W.Style.card)
    border.width: searchHighlighted ? 2 : scheda.interna ? 0 : 1
    border.color: searchHighlighted ? W.Style.accent : W.Style.cardStroke
    opacity: scheda.disponibile ? 1 : 0.55

    // Anche i lettori di schermo devono riconoscere le funzioni assenti
    // come disabilitate, non solo osservare un MouseArea spento.
    enabled: scheda.disponibile
    activeFocusOnTab: scheda.porta && scheda.disponibile
    Accessible.role: scheda.porta ? Accessible.Button : Accessible.Grouping
    Accessible.name: scheda.titolo
    Accessible.description: scheda.disponibile ? scheda.descrizione
                            : (scheda.it ? "Non ancora disponibile" : "Not available yet")
    Keys.onReturnPressed: if (scheda.porta && scheda.disponibile) scheda.attivata()
    Keys.onSpacePressed: if (scheda.porta && scheda.disponibile) scheda.attivata()

    Rectangle {
        visible: scheda.filoSopra
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: W.Style.divider
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: 7
        color: "transparent"
        border.width: 2
        border.color: W.Style.text
        visible: scheda.activeFocus
    }

    MouseArea {
        id: presa
        anchors.fill: parent
        enabled: scheda.porta && scheda.disponibile
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: scheda.attivata()
    }

    W.Glyph {
        id: simbolo
        visible: scheda.icona !== "" && scheda.immagine.toString() === ""
        x: 17 + scheda.rientro
        anchors.verticalCenter: parent.verticalCenter
        width: 20
        height: 20
        name: scheda.icona
        color: W.Style.text
    }

    Image {
        visible: scheda.immagine.toString() !== ""
        x: 17 + scheda.rientro
        anchors.verticalCenter: parent.verticalCenter
        width: 20
        height: 20
        sourceSize: Qt.size(40, 40)
        source: scheda.immagine
    }

    Column {
        id: testi
        x: (scheda.icona !== "" || scheda.immagine.toString() !== "" ? 59 : 17) + scheda.rientro
        // x più un solo ancoraggio a destra non definisce la larghezza:
        // il testo che legge parent.width rimaneva a zero e non si vedeva.
        width: Math.max(0, (scheda.comandoSotto ? scheda.width : posto.x) - x - 16)
        y: scheda.comandoSotto ? 12 : (scheda.height - implicitHeight) / 2
        spacing: 1

        Text {
            width: parent.width
            text: scheda.titolo
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: scheda.disponibileComando ? W.Style.text : W.Style.faint
            font.family: W.Style.font
            font.pixelSize: 14
        }
        Row {
            visible: !scheda.disponibileComando && scheda.descrizione !== ""
            spacing: 6
            W.Glyph { width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter; name: "informazioni"; color: W.Style.accent }
            Text {
                text: scheda.descrizione
                textFormat: Text.PlainText
                color: W.Style.text
                font.family: W.Style.font
                font.pixelSize: 12
            }
        }
        Text {
            width: parent.width
            visible: text !== "" && scheda.disponibileComando
            text: scheda.descrizione
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: W.Style.muted
            font.family: W.Style.font
            font.pixelSize: 12
        }
    }

    Item {
        id: posto
        // Le coordinate non lasciano ancoraggi residui passando da una
        // disposizione all'altra durante il ridimensionamento della finestra.
        x: scheda.comandoSotto ? testi.x : scheda.width - (freccia.visible ? 44 : 16) - width
        y: scheda.comandoSotto ? testi.y + testi.implicitHeight + 12 : (scheda.height - height) / 2
        // childrenRect comprende la x allineata al bordo destro, che a sua
        // volta dipende da questa larghezza: misurare solo i figli spezza
        // il ciclo senza cambiare l'allineamento dei comandi.
        width: {
            var massimo = nonDisponibile.visible ? nonDisponibile.width : 0;
            for (var i = 0; i < children.length; i++) {
                if (children[i].visible)
                    massimo = Math.max(massimo, children[i].width);
            }
            return massimo;
        }
        height: childrenRect.height
        enabled: scheda.disponibile && scheda.disponibileComando
        visible: scheda.disponibile

        // I comandi si mettono da sé contro il bordo destro.
        onChildrenChanged: allinea()
        Component.onCompleted: allinea()
        function allinea() {
            for (var i = 0; i < posto.children.length; i++) {
                var c = posto.children[i];
                if (c && c.width !== undefined)
                    c.x = Qt.binding((function (el) {
                        return function () { return posto.width - el.width; };
                    })(c));
            }
        }
    }

    Text {
        id: nonDisponibile
        anchors.right: freccia.visible ? freccia.left : parent.right
        anchors.rightMargin: freccia.visible ? 12 : 16
        anchors.verticalCenter: parent.verticalCenter
        visible: !scheda.disponibile
        text: scheda.it ? "Non ancora disponibile" : "Not available yet"
        color: W.Style.muted
        font.family: W.Style.font
        font.pixelSize: 12
    }

    W.Glyph {
        id: freccia
        visible: scheda.porta
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        name: "chevronRight"
        color: W.Style.text
    }
}

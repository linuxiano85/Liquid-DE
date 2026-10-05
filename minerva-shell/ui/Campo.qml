import QtQuick
import "../theme" as Theme

// Campo — Una casella di testo di Minerva.
//
// ── Perché questo file esiste ────────────────────────────────────────────
//
// Contato il 4 settembre 2026: dentro il solo `media/MediaWindow.qml` la
// stessa casella era scritta **quattro volte identica** — riquadro incavato,
// altezza 38, raggio SM, bordo che si accende con il fuoco, un `Text` di
// segnaposto sopra un `TextInput`. E in tutta la shell il `TextInput` nudo
// compare in una ventina di file, ognuno con i suoi margini.
//
// Quattro copie della stessa cosa non sono quattro caselle: sono quattro
// caselle che un giorno saranno diverse, e la differenza si vede passando
// dall'una all'altra.
//
// ── Il segnaposto è un fratello, non una proprietà ───────────────────────
//
// `TextInput` non ha un `placeholderText` (ce l'ha `TextField` di
// QtQuick.Controls, che qui non si usa: porta con sé tutto lo stile di Qt).
// Si disegna quindi un `Text` sotto, visibile quando non c'è niente scritto —
// che è esattamente quello che facevano tutte e quattro le copie.
Item {
    id: campo

    /// Il testo scritto. Si legge e si scrive.
    property alias text: dentro.text

    /// Che cosa si vede quando è vuoto.
    property string segnaposto: ""

    /// Vero mentre ha il fuoco della tastiera.
    readonly property alias attivo: dentro.activeFocus

    /// I caratteri si vedono o si nascondono (per le password).
    property bool nascosto: false

    /// Allineamento del testo: normalmente a sinistra.
    property int allineamento: TextInput.AlignLeft

    /// Il testo si può cambiare.
    property bool modificabile: true

    /// Premuto invio.
    signal accettato()
    /// Il testo è cambiato, carattere per carattere.
    signal cambiato(string testo)

    implicitHeight: 38
    implicitWidth: 200

    /// Il fuoco si può chiedere da fuori senza sapere com'è fatto dentro.
    function prendiIlFuoco() { dentro.forceActiveFocus(); }
    function seleziona() { dentro.selectAll(); }

    Rectangle {
        anchors.fill: parent
        radius: Theme.Effects.radiusSM
        color: Theme.Colors.sunken
        // Il bordo appare col fuoco invece di esserci sempre: una fila di
        // caselle tutte bordate è un modulo da compilare.
        border.width: Theme.Effects.hairline
        border.color: dentro.activeFocus
                      ? Qt.alpha(Theme.Colors.accent, 0.6)
                      : "transparent"
        Behavior on border.color {
            ColorAnimation { duration: Theme.Motion.instant }
        }

        Text {
            textFormat: Text.PlainText
            anchors.fill: parent
            anchors.leftMargin: Theme.Effects.space3
            anchors.rightMargin: Theme.Effects.space3
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: campo.allineamento
            visible: dentro.text === ""
            text: campo.segnaposto
            // A sinistra e non a destra: un percorso lungo si riconosce dalla
            // fine, un titolo dall'inizio. Il segnaposto è sempre una frase,
            // quindi dall'inizio.
            elide: Text.ElideRight
            font { family: Theme.Typography.fontDisplay
                   ; pixelSize: Theme.Typography.sizeMD }
            color: Theme.Colors.textFaint
        }

        TextInput {
            id: dentro
            anchors.fill: parent
            anchors.leftMargin: Theme.Effects.space3
            anchors.rightMargin: Theme.Effects.space3
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: campo.allineamento
            color: Theme.Colors.text
            selectionColor: Qt.alpha(Theme.Colors.accent, 0.45)
            selectedTextColor: Theme.Colors.text
            clip: true
            selectByMouse: true
            readOnly: !campo.modificabile
            echoMode: campo.nascosto ? TextInput.Password : TextInput.Normal
            font { family: Theme.Typography.fontDisplay
                   ; pixelSize: Theme.Typography.sizeMD
                   ; weight: Theme.Typography.weightMedium }
            onAccepted: campo.accettato()
            onTextChanged: campo.cambiato(dentro.text)

            // Il cursore a I dice «qui si scrive» prima che ci si provi.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.IBeamCursor
            }
        }
    }

    Accessible.role: Accessible.EditableText
    Accessible.name: campo.segnaposto
}

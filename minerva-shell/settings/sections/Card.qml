import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui

// Card — Un gruppo di impostazioni che stanno insieme.
//
// Le impostazioni si leggono a gruppi, non a elenco: «tutto quello che
// riguarda lo schermo esterno» è un pensiero solo, e va dentro un riquadro
// solo. Un elenco piatto di venti righe costringe a leggerle tutte per capire
// quali si riferiscono a cosa.
//
// ── Si chiude (11 ottobre 2026) ──────────────────────────────────────────
//
// il manutentore: «riorganizzare totalmente con menù compressi». «Barra e dock»
// aveva dieci schede aperte una sotto l'altra: per arrivare all'ultima si
// scorreva tutto il resto. Adesso una scheda con un titolo si apre e si
// chiude cliccandolo (o con Invio e Spazio quando ha il fuoco). Di serie è
// aperta solo la prima di ogni pagina; le altre si ricordano come le si è
// lasciate, in `settings.schedeAperte`, per pagina e posizione.
//
// Chiusa, il corpo NON diventa invisibile: si ritaglia a altezza zero. Così la
// ricerca (`Page.revealSetting`) trova ancora le righe dentro e può aprire la
// scheda che le contiene; con `visible: false` le avrebbe saltate.
//
// ── Vale per certi preset ────────────────────────────────────────────────
//
// `preset` è l'elenco dei preset in cui la scheda ha senso (vedi
// `core/PresetVoci.js`). Vuoto: vale per tutti. Col preset «libero» si vede
// tutto, perché quello è il preset di chi vuole mettere le mani ovunque.
Rectangle {
    id: card

    property string heading: ""
    property string note: ""

    /// Quello che si scrive dentro la scheda va nel corpo, che si apre e si
    /// chiude.
    default property alias content: body.data

    /// I preset in cui la scheda vale. Vuoto: tutti.
    property var preset: []

    /// Si può chiudere: solo le schede con un titolo, che è la cosa da
    /// cliccare. Una scheda senza titolo resta sempre aperta.
    property bool chiudibile: heading !== ""

    /// Messi dalla pagina (`Page.qml`): chi la contiene e in che posizione.
    property Item pagina: null
    property int indice: -1

    readonly property string chiave: pagina && pagina.sezione !== "" && indice >= 0
                                     ? pagina.sezione + "#" + indice : ""

    readonly property bool valePerIlPreset: {
        var p = card.preset || [];
        var attuale = Core.DesktopStyle.attuale;
        return p.length === 0 || attuale === "libero" || p.indexOf(attuale) >= 0;
    }
    visible: valePerIlPreset

    /// Aperta. Dalle impostazioni se la si è già toccata, altrimenti solo la
    /// prima della pagina.
    /// La scelta fatta adesso, prima ancora che il demone la confermi; e
    /// l'unica che conta quando la scheda non ha una chiave (una pagina
    /// creata fuori dalle Impostazioni, come nelle prove).
    property var _scelta: undefined

    readonly property bool aperta: {
        if (!card.chiudibile)
            return true;
        if (card._scelta !== undefined)
            return card._scelta === true;
        var ricordate = Core.Ipc.get("settings.schedeAperte", ({})) || ({});
        if (card.chiave !== "" && ricordate[card.chiave] !== undefined)
            return ricordate[card.chiave] === true;
        return card.apertaDiSerie;
    }

    /// Aperta finché non la si chiude: di serie solo la prima della pagina.
    /// Una pagina la può volere aperta comunque (la scheda del preset in uso).
    property bool apertaDiSerie: indice <= 0

    function imposta(si) {
        if (!card.chiudibile || si === card.aperta)
            return;
        card._scelta = si;
        if (card.chiave === "")
            return;
        var ricordate = JSON.parse(JSON.stringify(Core.Ipc.get("settings.schedeAperte", ({})) || ({})));
        ricordate[card.chiave] = si;
        Core.Ipc.setSetting("settings.schedeAperte", ricordate);
    }
    function alterna() { card.imposta(!card.aperta); }

    /// Da 0 (chiusa) a 1 (aperta): l'altezza del corpo la segue.
    property real apertura: aperta ? 1 : 0
    Behavior on apertura {
        enabled: Core.Ipc.get("desktop.animations", true)
        NumberAnimation { duration: Theme.Motion.quick; easing.type: Easing.OutCubic }
    }

    width: parent ? parent.width : 0
    // Si somma l'altezza NATURALE dei testi, non la loro altezza vera:
    // assegnare `height` a un elemento la cui altezza qualcun altro sta già
    // leggendo chiude il cerchio, e Qt lo segnalava a ogni apertura.
    readonly property real _testa: heading !== "" ? headingText.implicitHeight : 0
    readonly property real _nota: note !== "" ? noteText.implicitHeight + Theme.Effects.space2 : 0
    // Con un titolo: la testata (margini compresi) sempre, e sotto il corpo
    // nella misura in cui la scheda è aperta. Il corpo parte `space1` sopra
    // il fondo della testata, così fra titolo e prima riga resta lo stesso
    // spazio di prima (space4 - space1 = space3).
    implicitHeight: heading !== ""
                    ? testata.height
                      + (body.implicitHeight + _nota + Theme.Effects.space4 - Theme.Effects.space1) * apertura
                    : body.implicitHeight + _nota + Theme.Effects.space4 * 2
    // Nel preset Windows è la scheda di Impostazioni di Windows 11: angoli
    // da 4 e un filo di contorno, perché sul fondo #F3F3F3 una scheda
    // bianca senza bordo non si stacca.
    readonly property bool stileWindows: Core.DesktopStyle.attuale === "windows"
    radius: card.stileWindows ? 4 : Theme.Effects.radiusMD
    color: Theme.Colors.raised
    border.width: card.stileWindows ? 1 : 0
    border.color: Theme.Colors.edge
    clip: true

    // ── La testata: si clicca per aprire e chiudere ──
    Item {
        id: testata
        objectName: "schedaTestata"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: card.heading !== "" ? card._testa + Theme.Effects.space4 * 2 : 0
        visible: card.heading !== ""
        activeFocusOnTab: card.chiudibile
        Accessible.role: Accessible.Button
        Accessible.name: card.heading
        Keys.onReturnPressed: card.alterna()
        Keys.onEnterPressed: card.alterna()
        Keys.onSpacePressed: card.alterna()

        Rectangle {
            anchors.fill: parent
            radius: card.radius
            color: presaTestata.containsMouse ? Theme.Colors.hover : "transparent"
            border.width: testata.activeFocus ? 1 : 0
            border.color: Theme.Colors.edgeAccent
        }

        Text {
            id: headingText
            anchors.left: parent.left
            anchors.right: freccia.left
            anchors.leftMargin: Theme.Effects.space4
            anchors.rightMargin: Theme.Effects.space2
            anchors.verticalCenter: parent.verticalCenter
            text: card.heading
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: card.stileWindows ? Theme.Typography.sizeSM : Theme.Typography.sizeMD
            font.weight: card.stileWindows ? Theme.Typography.weightRegular : Theme.Typography.weightSemiBold
        }

        Ui.Icon {
            id: freccia
            anchors.right: parent.right
            anchors.rightMargin: Theme.Effects.space4
            anchors.verticalCenter: parent.verticalCenter
            width: card.chiudibile ? 16 : 0
            height: 16
            visible: card.chiudibile
            name: "chevron"
            alwaysDrawn: true
            color: Theme.Colors.textMuted
            // Il simbolo punta in basso (aperta); chiusa, ruota a destra.
            // In Windows, come nell'Expander: in giù chiusa, in su aperta.
            rotation: card.stileWindows ? 180 * card.apertura : -90 * (1 - card.apertura)
        }

        MouseArea {
            id: presaTestata
            anchors.fill: parent
            enabled: card.chiudibile
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.alterna()
        }
    }

    Column {
        id: body
        anchors.top: card.heading !== "" ? testata.bottom : parent.top
        anchors.topMargin: card.heading !== "" ? -Theme.Effects.space1 : Theme.Effects.space4
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.Effects.space4
        anchors.rightMargin: Theme.Effects.space4
        spacing: Theme.Effects.space3
        // Chiusa, non si deve poter arrivare col Tab a un controllo nascosto.
        enabled: card.aperta
        opacity: card.apertura
    }

    Text {
        id: noteText
        anchors.top: body.bottom
        anchors.topMargin: Theme.Effects.space2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.Effects.space4
        anchors.rightMargin: Theme.Effects.space4
        visible: card.note !== ""
        opacity: card.apertura
        wrapMode: Text.WordWrap
        text: card.note
        color: Theme.Colors.textFaint
        font.family: Theme.Typography.fontDisplay
        font.weight: Theme.Typography.weightRegular
        font.pixelSize: Theme.Typography.sizeXS
    }
}

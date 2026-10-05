import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core

// DesktopLayer — Superficie invisibile stesa sulla scrivania vuota.
//
// Sta sotto le finestre e sopra lo sfondo. Serve solo a intercettare i clic
// sulla scrivania nuda, che altrimenti non arriverebbero a nessuno — è il
// motivo per cui su molte shell minimali il tasto destro sul desktop non fa
// niente.
//
// LIVELLO «BOTTOM», NON «BACKGROUND», e la differenza è tutt'altro che
// formale. Fra due superfici dello STESSO livello il puntatore va sempre
// all'ultima creata: chiunque agganci una superficie di sfondo dopo di noi
// senza dichiarare una regione d'ingresso vuota si prende tutti i clic. Con
// hyprpaper — che è stato tolto proprio per questo, vedi WallpaperLayer.qml —
// succedeva ogni volta che lo sfondo era una foto grande: lui la decodificava
// per qualche secondo, arrivava buon ultimo, e il tasto destro sulla scrivania
// smetteva di funzionare senza che niente fosse cambiato nella shell.
//
// Il livello «bottom» sta sopra tutto il livello di sfondo e sotto ogni
// finestra: l'ordine con lo sfondo non è una gara e i clic arrivano.
PanelWindow {
    id: desktop

    anchors { top: true; bottom: true; left: true; right: true }

    WlrLayershell.namespace: "minerva-desktop"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Copre tutto lo schermo, barra compresa: non riserva spazio proprio.
    exclusionMode: ExclusionMode.Ignore

    color: "transparent"

    signal rightClicked(int x, int y)
    signal leftClicked()
    /// Ci hanno lasciato sopra dei file trascinati da un'altra parte —
    /// dal gestore file, da Dolphin, dal browser. Gli indirizzi sono
    /// `file://`, come parlano tutti, e il punto è quello dello schermo in
    /// cui si è lasciato: lì va aperta la domanda «copiare o spostare».
    signal released(var urls, int x, int y)

    // Disattivabile dalle Impostazioni
    property bool menuEnabled: Core.Ipc.get("desktop.rightClickMenu", true)

    /// Acceso mentre un trascinamento ci passa sopra: la scrivania intera
    /// diventa un bersaglio, e chi trascina deve VEDERLO — senza, si lascia
    /// la roba al buio e si scopre dov'è finita dopo.
    property bool bersaglio: false

    /// La cartella della scrivania: chi disegna le icone la chiede qui.
    property string cartella: ""

    // ── Lo sfondo non sta più qui ────────────────────────────────────────
    //
    // Qui c'era un ciclo che chiamava `hyprpaper` fino a dieci volte,
    // aspettando un secondo fra un tentativo e l'altro, perché quel programma
    // parte insieme a noi e poteva non essere ancora pronto — e perché la sua
    // configurazione non la legge (scriveva «Monitor WAYLAND-1 has no target»
    // con qualunque forma della riga).
    //
    // Adesso lo sfondo lo disegna Minerva, in `WallpaperLayer.qml`. Non c'è
    // nessun programma da aspettare e nessun ciclo di tentativi: c'è
    // un'immagine su una superficie.

    // ── «Puoi lasciare qui» ───────────────────────────────────────────────
    //
    // Era una cornice larga quanto lo schermo, due pixel color accento: lo
    // stesso disegno con cui il compositore annuncia l'aggancio in alto.
    // Trascinare qualcosa sulla scrivania sembrava stare per ingrandire una
    // finestra. La ragione per esteso sta in `DesktopIcons.qml`, dove c'era la
    // gemella di questa cornice — due copie dello stesso equivoco.
    //
    // Questa si vede solo quando le icone della scrivania sono spente: con le
    // icone accese il bersaglio è il loro, che sta sopra.

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 72

        width: quiDentro.implicitWidth + Theme.Effects.space5 * 2
        height: 38
        radius: Theme.Effects.radiusFull
        color: Theme.Colors.membrane
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edgeAccent

        visible: opacity > 0
        opacity: desktop.bersaglio ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.Motion.instant } }

        Text {
            id: quiDentro
            anchors.centerIn: parent
            text: Core.Strings.lang === "it"
                  ? "Rilascia qui per metterlo sulla Scrivania"
                  : "Drop here to put it on the Desktop"
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    // ── Lasciare roba sulla scrivania ─────────────────────────────────────
    //
    // La scrivania È una cartella: trascinare un file sopra lo sfondo deve
    // metterlo in quella cartella, come su ogni altro ambiente. Gli
    // indirizzi arrivano come `file://` — è la lingua di tutti i programmi
    // — e la decisione «copiare o spostare» la prende la shell, che è chi
    // ha il menu per chiederlo.
    DropArea {
        anchors.fill: parent
        keys: ["minerva/file", "text/uri-list"]
        enabled: desktop.menuEnabled
        onEntered: desktop.bersaglio = true
        onExited: desktop.bersaglio = false
        onDropped: function (d) {
            desktop.bersaglio = false;
            var urls = d.urls || [];
            if (urls.length > 0)
                desktop.released(urls, Math.round(d.x), Math.round(d.y));
            d.accept();
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        enabled: desktop.menuEnabled

        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton)
                desktop.rightClicked(mouse.x, mouse.y);
            else
                desktop.leftClicked();
        }
    }

    // Suggerimento per chi arriva da un altro ambiente: appare solo in
    // modalità principiante e solo finché il menu non è mai stato usato.
    //
    // «Mai stato usato» sta nel demone e non in una proprietà: una proprietà
    // nasce col processo, e il suggerimento sarebbe tornato a ogni riavvio
    // della shell anche a chi il menu lo usa da settimane.
    property bool hintVisible: Core.Ipc.get("general.beginnerMode", true)
                               && !Core.Ipc.get("desktop.menuUsed", false)

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40

        width: hintText.implicitWidth + 32
        height: 40
        radius: Theme.Effects.radiusFull
        color: Theme.Colors.scrim
        border.width: 1
        border.color: Theme.Colors.edge

        visible: desktop.menuEnabled && desktop.hintVisible
        opacity: visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.Motion.surface }
        }

        Text {
            id: hintText
            anchors.centerIn: parent
            text: Core.Strings.lang === "it"
                  ? "Super+K per le scorciatoie · Clic destro qui per il menu"
                  : "Super+K for shortcuts · Right-click here for the menu"
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    onRightClicked: {
        if (!Core.Ipc.get("desktop.menuUsed", false))
            Core.Ipc.setSetting("desktop.menuUsed", true);
    }
}

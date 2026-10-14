import QtQuick
import "../core" as Core
import "../theme" as Theme
import "../ui" as Ui
import "../menu" as Menu

Ui.SpineButton {
    id: tilingButton
    objectName: "tilingButton"
    signal settingsRequested()
    anchors.verticalCenter: parent.verticalCenter
    visible: Core.Compositore.nostro && Core.Tiling.showButton
    active: Core.Tiling.active
    tooltip: Core.Strings.lang === "it"
        ? (active ? "Tiling: clic per modalità classica · destro per opzioni":"Classico: clic per tiling · destro per opzioni")
        : (active ? "Tiling: click for classic · right click for options":"Classic: click for tiling · right click for options")
    onClicked: Core.Tiling.toggle()
    onRightClicked: tilingMenu.openAtCursor([
        {label: Core.Strings.lang === "it" ? "Recenti a sinistra":"Recent windows on the left", icon: "window", action: "recenti"},
        {label: Core.Strings.lang === "it" ? "Ordine manuale stabile":"Stable manual order", icon: "grid", action: "manuale"},
        {separator: true},
        {label: Core.Strings.lang === "it" ? "Impostazioni finestre":"Window settings", icon: "settings", action: "settings"}
    ])
    content: Ui.Icon { name: Core.Tiling.active ? "grid":"window"; width: 18; height: 18; color: Core.Tiling.active ? Theme.Colors.accent:Theme.Colors.textMuted }
    Menu.ContextMenu {
        id: tilingMenu
        onTriggered: function(action) {
            if(action === "settings") tilingButton.settingsRequested();
            else Core.Tiling.setOrder(action);
        }
    }
}

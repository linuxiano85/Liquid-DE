// ContextMenu — Menu a comparsa riutilizzabile, posizionato dove si è cliccato.
// Le voci si passano come array di oggetti semplici:
//     items: [
//         { "label": "Nuovo terminale", "icon": "terminal", "action": "terminal" },
//         { "separator": true },
//         { "label": "Chiudi", "icon": "close", "action": "close", "danger": true }
//     ]
// `icon` è il nome di un tracciato di Ui.Icon, non un carattere: i glifi
// Unicode vengono resi da font diversi su sistemi diversi e in un elenco
// verticale la differenza di peso salta all'occhio.

import "../core" as Core
import "../files" as FilesUi
import "../theme" as Theme
import "../ui" as Ui
import "../windows11" as Windows11
import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Wayland

// Si reagisce al segnale `triggered(action)`. Le azioni sono stringhe e non
// funzioni: così restano ispezionabili nei log e il menu non trattiene
// riferimenti a oggetti che potrebbero essere già stati distrutti.
PanelWindow {
    // ── La tastiera, tutta, finché è aperto ─────────────────────────────
    // ── Aprirlo dove sta il puntatore ────────────────────────────────────
    // `openAt` vuole coordinate dello SCHERMO, perché questo menu è una
    // superficie a schermo intero. Chi lo chiama da una finestra normale non
    // ce le ha: **su Wayland una finestra non sa dove si trova**, e
    // `mapToGlobal` restituisce coordinate relative alla finestra stessa. Il
    // menu compariva quindi spostato di tutta la posizione della finestra —
    // il difetto che il manutentore aveva descritto come «menu fuori posto».
    // Nelle superfici della shell (barra, dock, scrivania) il problema non
    // c'è: quelle sono ancorate all'origine dello schermo e le due coordinate
    // coincidono. È solo nelle finestre — gestore file, Anteprima — che
    // servono queste due funzioni.
    // Chi la posizione la sa è il compositore, e gliela si chiede. Un
    // processo per ogni tasto destro è un costo che si può pagare: è un
    // gesto, non un ciclo. (Quickshell 0.3 non espone la posizione del
    // puntatore in nessun modo: cercata in tutti i moduli, non c'è.)
    // ── Se la risposta non arriva, si apre lo stesso ─────────────────────
    // Un menu che aspetta una risposta per esistere è un menu che a volte non
    // compare, e «il tasto destro non fa niente» è uno di quei difetti che
    // nessuno riesce a riprodurre a comando — perché dipende dai tempi.
    // Osservato il 4 settembre 2026 nella galleria: due tentativi su quattro,
    // stessa versione, stesso punto.
    // ── Si è aperta un'altra finestra: il menù non le resta sopra ────────

    id: menu

    property bool windowsAppearance: Core.DesktopStyle.attuale === "windows"
    // Solo i menu dei file hanno azioni principali e personalizzazione.
    property bool fileMenu: false
    property bool customizing: false
    property var originalItems: []
    readonly property bool inlineCommands: Core.Ipc.get("windows11.contextInline", false)
    readonly property bool propertiesLast: Core.Ipc.get("windows11.contextPropertiesLast", false)
    readonly property bool extensionsVisible: Core.Ipc.get("windows11.contextExtensions", true)
    readonly property var hiddenActions: Core.Ipc.get("windows11.contextHidden", [])
    readonly property var quickItems: items.filter(function(item) {
        return item.quick === true;
    })
    property alias testContent: keyCatcher
    property alias testCard: card
    /// Voci del menu
    property var items: []
    property int selectedIndex: -1
    property var rootSelection: null
    onSelectedIndexChanged: {
        var item = items[selectedIndex];
        rootSelection = item ? { action: item.action || "", label: item.label || "" } : null;
    }
    onItemsChanged: if (visible) refreshBranches()
    // Ogni colonna conserva selezione e voce del padre: tornare indietro non
    // deve ricostruire un sottomenu diverso o saltare direttamente alla radice.
    property var branches: []
    property int focusedLevel: 0
    property int layoutRevision: 0
    property int branchRevision: 0
    readonly property bool subFocus: focusedLevel > 0
    readonly property var subitems: entriesAt(focusedLevel > 0 ? focusedLevel : 1)
    readonly property int subSelectedIndex: selectedAt(focusedLevel > 0 ? focusedLevel : 1)
    /// Punto a cui il menu si aggancia, in coordinate dello schermo.
    property int menuX: 0
    property int menuY: 0
    /// Da che parte cresce il menu rispetto al punto: verso il basso (il
    /// normale tasto destro) o verso l'alto. Un menu aperto da una icona in
    /// fondo allo schermo DEVE crescere verso l'alto: se cresce verso il basso
    /// non ci sta, il vincolo lo risbatte da tutt'altra parte, e chi guarda
    /// vede il menu comparire lontano da dove ha cliccato.
    property bool growUp: false
    /// Centrato orizzontalmente sul punto invece che allineato a sinistra.
    /// Serve alle icone: il menu di una icona esce dal suo centro.
    property bool centred: false
    // I menu della tray rispettano la barra inferiore anche quando sono lunghi.
    property real bottomInset: 0
    readonly property real availableHeight: Math.max(16, height - bottomInset)
    property var _inArrivo: null
    property bool _versoAlto: false
    property bool _centrato: false
    // Con `Super+I` a menù aperto, le Impostazioni comparivano SOTTO il
    // menù, che restava lì finché non si cliccava. La finestra attiva che
    // cambia vuol dire che l'attenzione è andata altrove. Il primo attimo
    // dopo l'apertura non conta: il menù della barra del titolo dà il fuoco
    // alla finestra e subito dopo si apre, e non deve richiudersi da solo.
    property real _apertoAlle: 0

    signal triggered(string action)
    // NB: non chiamarlo `closed`: collide con un segnale di PanelWindow
    signal dismissed()

    function arrange(source) {
        if (!windowsAppearance || !fileMenu)
            return source;

        var primary = ["cut", "copy", "paste", "rename", "share", "trash"];
        var common = ["open", "openWith", "openTab", "newFolder", "newFile", "copyPath", "compress", "extract", "pin", "properties", "restore", "undo"];
        var main = [], extra = [], quick = [], properties = [];
        source.forEach(function(item) {
            if (item.separator || hiddenActions.indexOf(item.action) >= 0)
                return ;

            var copy = Object.assign({
            }, item);
            if (primary.indexOf(copy.action) >= 0) {
                copy.quick = !inlineCommands;
                quick.push(copy);
            } else if (copy.action === "properties" && propertiesLast)
                properties.push(copy);
            else if (common.indexOf(copy.action) >= 0)
                main.push(copy);
            else
                extra.push(copy);
        });
        quick.sort(function(a, b) {
            return primary.indexOf(a.action) - primary.indexOf(b.action);
        });
        // Le estensioni e la personalizzazione non devono interrompere le
        // operazioni sui file. Manteniamo anche un confine visivo dopo le icone.
        var result = quick.slice();
        if (quick.length && main.length)
            result.push({ "separator": true });
        result = result.concat(main);
        if (properties.length) {
            result.push({ "separator": true });
            result = result.concat(properties);
        }
        var additional = extensionsVisible ? extra.slice() : [];
        if (additional.length)
            additional.push({ "separator": true });
        additional.push({
            "label": Windows11.Style.label("Opzioni del menu…", "Menu options…"),
            "icon": "settings",
            "action": "__customize"
        });
        result.push({ "separator": true });
        result.push({
            "label": Windows11.Style.label("Mostra altre opzioni", "Show more options"),
            "action": "__more",
            "children": additional
        });
        return result;
    }

    function rebuild() {
        menu.items = arrange(originalItems);
        menu.branches = [];
        menu.selectedIndex = -1;
        menu.focusedLevel = 0;
    }

    function toggleAction(action, show) {
        var hidden = hiddenActions.filter(function(id) {
            return id !== action;
        });
        if (!show)
            hidden.push(action);

        Core.Ipc.setSetting("windows11.contextHidden", hidden);
        rebuild();
    }

    function entriesAt(level) {
        return level === 0 ? items : branches[level - 1] ? branches[level - 1].items : [];
    }

    function selectedAt(level) {
        return level === 0 ? selectedIndex : branches[level - 1] ? branches[level - 1].selectedIndex : -1;
    }

    function setSelection(level, index) {
        if (level === 0) {
            selectedIndex = index;
        } else if (branches[level - 1]) {
            var path = branches.slice();
            var item = entriesAt(level)[index];
            path[level - 1] = Object.assign({}, path[level - 1], { selectedIndex: index,
                selectedAction: item ? item.action || "" : "", selectedLabel: item ? item.label || "" : "" });
            branches = path;
        }
    }

    function columnAt(level) {
        var view = level > 0 ? submenuViews.itemAt(level - 1) : null;
        return level === 0 ? itemsColumn : view ? view.column : null;
    }

    function scrollAt(level) {
        var view = level > 0 ? submenuViews.itemAt(level - 1) : null;
        return level === 0 ? menuScroll : view ? view.scroller : null;
    }

    function entryAt(level, index) {
        var view = level > 0 ? submenuViews.itemAt(level - 1) : null;
        var rows = level === 0 ? rootEntries : view ? view.rows : null;
        return rows ? rows.itemAt(index) : null;
    }

    function rowOffset(level, index) {
        var revision = layoutRevision;
        var row = entryAt(level, index);
        var column = columnAt(level);
        var scroll = scrollAt(level);
        return column && scroll ? column.y + (row ? row.y : 0) - scroll.contentY : 8;
    }

    function selectEntry(level, index) {
        var previous = selectedAt(level);
        setSelection(level, index);
        focusedLevel = level;
        if (previous !== index)
            branches = branches.slice(0, level);
    }

    function previewEntry(level, index) {
        selectEntry(level, index);
        var item = entriesAt(level)[index];
        if (item && item.children && item.enabled !== false)
            openBranch(level, index, false);
        else
            branches = branches.slice(0, level);
    }

    function openBranch(level, index, keyboard) {
        var item = entriesAt(level)[index];
        if (!item || !item.children || !item.children.length || item.enabled === false)
            return;
        var previous = branches[level];
        selectEntry(level, index);
        var branch = { items: item.children,
                       revision: previous && previous.parentIndex === index && previous.parentLabel === (item.label || "") ? previous.revision : ++branchRevision,
                       selectedIndex: previous && previous.parentIndex === index ? previous.selectedIndex : -1,
                       selectedAction: previous ? previous.selectedAction : "", selectedLabel: previous ? previous.selectedLabel : "",
                       parentIndex: index, parentAction: item.action || "", parentLabel: item.label || "" };
        branches = branches.slice(0, level).concat([branch]);
        if (keyboard) {
            focusedLevel = level + 1;
            setSelection(focusedLevel, -1);
            moveSelection(1);
        }
    }

    function leaveBranch() {
        if (focusedLevel > 0) {
            branches = branches.slice(0, focusedLevel - 1);
            focusedLevel--;
        } else {
            branches = [];
        }
    }

    function findSameEntry(list, action, label) {
        var exact = list.findIndex(function(item) {
            return (item.action || "") === action && (item.label || "") === label && !item.separator;
        });
        if (exact >= 0)
            return exact;
        // Il percorso dell'azione D-Bus cambia quando il servizio riordina
        // le voci. Una sola etichetta uguale è riconoscibile; più di una no.
        var candidates = [];
        list.forEach(function(item, index) {
            if (label && item.label === label && !item.separator)
                candidates.push(index);
        });
        return candidates.length === 1 ? candidates[0] : -1;
    }

    function refreshBranches() {
        var path = [];
        var list = items;
        if (rootSelection)
            selectedIndex = findSameEntry(items, rootSelection.action, rootSelection.label);
        for (var i = 0; i < branches.length; i++) {
            var old = branches[i];
            var index = findSameEntry(list, old.parentAction, old.parentLabel);
            var parent = list[index];
            if (!parent || parent.enabled === false || !parent.children || !parent.children.length)
                break;
            var selection = old.selectedIndex < 0 ? -1 : findSameEntry(parent.children, old.selectedAction, old.selectedLabel);
            if (selection >= 0 && parent.children[selection].enabled === false)
                selection = -1;
            var item = parent.children[selection];
            path.push(Object.assign({}, old, { items: parent.children, revision: ++branchRevision, parentIndex: index,
                parentAction: parent.action || "", parentLabel: parent.label || "", selectedIndex: selection,
                selectedAction: item ? item.action || "" : "", selectedLabel: item ? item.label || "" : "" }));
            if (i === 0)
                selectedIndex = index;
            else {
                path[i - 1].selectedIndex = index;
                path[i - 1].selectedAction = parent.action || "";
                path[i - 1].selectedLabel = parent.label || "";
            }
            list = parent.children;
        }
        branches = path;
        focusedLevel = Math.min(focusedLevel, branches.length);
    }

    function moveSelection(delta) {
        var level = focusedLevel;
        var list = entriesAt(level);
        var count = list.length;
        if (!count)
            return;
        var index = selectedAt(level);
        var found = -1;
        for (var n = 0; n < count; n++) {
            index = (index + delta + count) % count;
            if (!list[index].separator && list[index].enabled !== false) {
                found = index;
                break;
            }
        }
        selectEntry(level, found);
        Qt.callLater(menu.revealSelection, level);
    }

    function revealSelection(level) {
        var row = entryAt(level, selectedAt(level));
        var scroll = scrollAt(level);
        if (!row || !scroll)
            return;
        var column = columnAt(level);
        var top = column.y + row.y;
        if (top < scroll.contentY)
            scroll.contentY = top;
        else if (top + row.height > scroll.contentY + scroll.height)
            scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height, top + row.height - scroll.height));
    }


    function activateSelection() {
        var item = entriesAt(focusedLevel)[selectedAt(focusedLevel)];
        if (!item || item.separator || item.enabled === false)
            return ;

        if (item.children) {
            openBranch(focusedLevel, selectedAt(focusedLevel), true);
            return ;
        }
        var action = item.action || "";
        if (action === "__customize") {
            branches = [];
            customizing = true;
            customInline.forceActiveFocus();
            return ;
        }
        close();
        if (action !== "")
            triggered(action);

    }

    function openAt(x, y, menuItems) {
        menu.growUp = false;
        menu.centred = false;
        menu._show(x, y, menuItems);
    }

    /// Apre il menu SOPRA il punto, centrato su di esso. È la forma giusta per
    /// qualunque cosa stia in fondo allo schermo.
    function openAbove(x, y, menuItems) {
        menu.growUp = true;
        menu.centred = true;
        menu._show(x, y, menuItems);
    }

    /// E questa è la stessa cosa allo specchio: SOTTO il punto e centrato,
    /// per quello che sta in cima allo schermo.
    ///
    /// Non è `openAt`: quello cresce verso il basso ma parte dal punto e va a
    /// destra, che è la forma giusta per il tasto destro (il menu nasce dalla
    /// punta del puntatore). Un'icona della dock non ha una punta: ha un
    /// centro, e il menu deve stare sotto di lei — se no esce dal centro
    /// dell'icona e sbanda a destra, e sull'ultima icona finisce fuori schermo.
    function openBelow(x, y, menuItems) {
        menu.growUp = false;
        menu.centred = true;
        menu._show(x, y, menuItems);
    }

    /// Apre il menu dove sta il puntatore, crescendo verso il basso.
    ///
    /// **Se sai già dove sei, usa `openAt`.** Questa versione deve chiedere al
    /// compositore dov'è il dito, cioè fare un giro di rete locale prima di
    /// far comparire un menu — e quel giro può non tornare.
    function openAtCursor(menuItems) {
        menu._inArrivo = menuItems;
        menu._versoAlto = false;
        menu._centrato = false;
        Core.Compositore.chiedi("puntatore");
        senzaRisposta.restart();
    }

    function _show(x, y, menuItems) {
        menu.originalItems = menuItems;
        menu.customizing = false;
        menu.rebuild();
        menu.selectedIndex = -1;
        menu.branches = [];
        menu.focusedLevel = 0;

        menu.menuX = x;
        menu.menuY = y;
        menu._apertoAlle = Date.now();
        menu.visible = true;
        card.scale = 0.94;
        card.opacity = 0;
        showAnim.start();
        keyCatcher.forceActiveFocus();
    }

    function close() {
        // Una risposta tardiva del puntatore non deve riaprire un menu chiuso.
        menu._inArrivo = null;
        senzaRisposta.stop();
        if (!menu.visible)
            return ;

        menu.visible = false;
        menu.branches = [];
        menu.focusedLevel = 0;
        menu.dismissed();
    }

    WlrLayershell.namespace: menu.windowsAppearance ? "liquid-windows11" : "quickshell"
    WlrLayershell.layer: WlrLayer.Overlay
    // Era `OnDemand`: il compositore dà la tastiera a una superficie così
    // solo quando la si CLICCA, e un menù aperto col tasto destro non viene
    // cliccato prima di scegliere. `Esc` finiva alla finestra di sotto e il
    // menù restava lì (PC di prova, 29 settembre 2026). Il menù esiste solo
    // da aperto, quindi prendere la tastiera non toglie niente a nessuno.
    WlrLayershell.keyboardFocus: menu.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // Copre l'intero schermo, barra compresa: senza questo il layer verrebbe
    // spinto sotto la zona esclusiva della barra e le coordinate del mouse
    // risulterebbero sfalsate di tutta l'altezza della barra stessa.
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Duecentocinquanta millisecondi: il compositore è a un socket di
    // distanza e risponde in meno di uno. Se non l'ha fatto, non lo farà, e
    // un menu nell'angolo è **molto** meno grave di nessun menu.
    Timer {
        id: senzaRisposta

        interval: 250
        onTriggered: {
            if (menu._inArrivo === null)
                return ;

            var voci = menu._inArrivo;
            menu._inArrivo = null;
            menu.growUp = menu._versoAlto;
            menu.centred = menu._centrato;
            menu._show(menu.menuX, menu.menuY, voci);
        }
    }

    Connections {
        function onRisposta(cosa, text) {
            if (cosa !== "puntatore" || menu._inArrivo === null)
                return ;

            {
                // Risposta: «1211, 94», in coordinate logiche — le stesse in
                // cui ragiona questa superficie.
                var parti = text.trim().split(",");
                var x = parseInt(parti[0]);
                var y = parseInt(parti[1]);
                if (isNaN(x) || isNaN(y)) {
                    // Senza risposta si apre comunque, in alto a sinistra:
                    // un menu nel posto sbagliato è meno grave di un tasto
                    // destro che non fa niente.
                    x = 0;
                    y = 0;
                }
                // Il puntatore è nel layout globale; il layer è locale al
                // monitor. Senza conversione i menu del secondo schermo
                // finivano sul primo, oppure contro il suo bordo destro.
                var output = Quickshell.screens.find(function(screen) {
                    return x >= screen.x && y >= screen.y &&
                        x < screen.x + screen.width && y < screen.y + screen.height;
                });
                if (output) {
                    menu.screen = output;
                    x -= output.x;
                    y -= output.y;
                }
                menu.growUp = menu._versoAlto;
                menu.centred = menu._centrato;
                var voci = menu._inArrivo;
                // Si azzera PRIMA di mostrare: la risposta «puntatore» la
                // riceve chiunque l'abbia chiesta, e senza questo un menu già
                // aperto si riaprirebbe da solo alla domanda di un altro.
                menu._inArrivo = null;
                senzaRisposta.stop();
                menu._show(x, y, voci);
            };
        }

        target: Core.Compositore
    }

    Connections {
        function onActiveAddressChanged() {
            if (menu.visible && Date.now() - menu._apertoAlle > 500)
                menu.close();

        }

        target: Core.Windows
    }

    // Chiudere cliccando fuori è il modo in cui ogni menu contestuale
    // si comporta: qui vale sia per il tasto sinistro sia per il destro.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: menu.close()
    }

    Item {
        id: keyCatcher

        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: {
            if (menu.branches.length) {
                menu.leaveBranch();
            } else {
                menu.close();
            }
        }
        Keys.onRightPressed: {
            var item = menu.entriesAt(menu.focusedLevel)[menu.selectedAt(menu.focusedLevel)];
            if (item && item.children)
                menu.activateSelection();

        }
        Keys.onLeftPressed: menu.leaveBranch()
        Keys.onDownPressed: menu.moveSelection(1)
        Keys.onUpPressed: menu.moveSelection(-1)
        Keys.onReturnPressed: menu.activateSelection()
        Keys.onEnterPressed: menu.activateSelection()
        Keys.onSpacePressed: menu.activateSelection()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                menu.setSelection(menu.focusedLevel, event.key === Qt.Key_Home ? -1 : 0);
                menu.moveSelection(event.key === Qt.Key_Home ? 1 : -1);
                event.accepted = true;
            }
        }
    }

    Rectangle {
        // ── Larga quanto la voce più lunga ───────────────────────────────
        // Era fissa a 252, e le voci più lunghe finivano con dei puntini:
        // «Trasmetti a TV camer…». Il nome di un televisore, di un programma
        // o di un file non è una cosa che si possa accorciare — è proprio
        // l'informazione per cui si è aperto il menu.
        // ── Misurata con lo STESSO elemento che poi disegna ──────────────
        // Il primo tentativo usava `FontMetrics.advanceWidth`, ed è arrivato
        // a due pixel dal risultato giusto — cioè continuava a tagliare.
        // Fra la larghezza che un `FontMetrics` calcola e quella che un
        // `Text` occupa ci sono la spaziatura fra lettere, l'arrotondamento e
        // il peso del carattere: differenze piccole, e bastano.

        id: card

        // Il menu non deve mai uscire dallo schermo. Il vincolo è l'ultima
        // parola, ma arriva DOPO aver scelto il verso giusto: rimediare col
        // solo vincolo sposta il menu, sceglierlo bene lo lascia dov'è.
        readonly property real wantX: menu.centred ? menu.menuX - width / 2 : menu.menuX
        readonly property real wantY: menu.growUp ? menu.menuY - height : menu.menuY
        /// Il contorno, contato e non stimato: margine sinistro (space3) +
        /// icona (17) + stacco (space3) + [testo] + stacco (space2) + margine
        /// destro (space3). Sono gli stessi ancoraggi della riga qui sotto —
        /// sbagliarli di dieci pixel rimette i puntini.
        readonly property real contorno: 17 + Theme.Effects.space3 * 3 + Theme.Effects.space2

        visible: !menu.customizing
        x: Math.max(8, Math.min(card.wantX, menu.width - width - 8))
        y: Math.max(8, Math.min(card.wantY, menu.availableHeight - height - 8))
        // Il minimo resta 252, perché un menu di tre voci corte non deve
        // diventare un francobollo; il massimo è 420, perché oltre non è più
        // un menu ed è meglio un nome accorciato di una lenzuola.
        width: Math.max(0, Math.min(menu.width - 16, Math.max(252, Math.min(420, Math.ceil(righello.piuLarga) + card.contorno + 10))))
        implicitHeight: itemsColumn.implicitHeight + Theme.Effects.space2 * 2
        height: Math.min(implicitHeight, menu.availableHeight - 16)
        radius: menu.windowsAppearance ? 8 : Theme.Effects.radiusMD
        color: (menu.windowsAppearance ? Windows11.Style.surface : Theme.Colors.membrane)
        border.width: 1
        border.color: (menu.windowsAppearance ? Windows11.Style.edge : Theme.Colors.edge)
        opacity: 0
        scale: 0.94
        // Il menu cresce DAL punto cliccato: l'origine della scala segue
        // l'angolo in cui è stato aperto, altrimenti sembra planarci sopra.
        transformOrigin: menu.growUp ? (menu.centred ? Item.Bottom : Item.BottomLeft) : (menu.centred ? Item.Top : Item.TopLeft)

        // Qui si misura con dei `Text` veri, invisibili e fuori dal disegno,
        // con esattamente le stesse proprietà di quelli visibili. Non è un
        // trucco: è l'unico modo di non avere due idee diverse della stessa
        // larghezza. Non c'è anello, perché questi non hanno una `width`
        // legata alla scheda — solo la loro `implicitWidth`.
        MenuMeasure {
            id: righello
            items: menu.items
            windowsAppearance: menu.windowsAppearance
        }

        Loader {
            active: menu.windowsAppearance
            z: -1

            sourceComponent: Component {
                Windows11.Shadow {
                    surface: card
                }

            }

        }

        ParallelAnimation {
            id: showAnim

            NumberAnimation {
                target: card
                property: "opacity"
                to: 1
                duration: Theme.Motion.quick
            }

            NumberAnimation {
                target: card
                property: "scale"
                to: 1
                duration: Theme.Motion.panel
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.Motion.emerge
            }

        }

        // I clic dentro al menu non devono chiuderlo prima di attivare la voce

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        Flickable {
            id: menuScroll

            anchors.fill: parent
            contentWidth: width
            contentHeight: itemsColumn.implicitHeight + 16
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: itemsColumn
                property int menuLevel: 0

                x: 4
                y: 8
                width: menuScroll.width - 8 - (menuScroll.contentHeight > menuScroll.height ? 18 : 0)
                spacing: 1

                Row {
                    visible: menu.quickItems.length > 0
                    height: visible ? 42 : 0
                    spacing: 4

                    Repeater {
                        model: menu.quickItems

                        delegate: Windows11.Button {
                            required property var modelData

                            objectName: "contextQuick-" + modelData.action
                            width: 36
                            height: 34
                            enabled: modelData.enabled !== false
                            tooltip: modelData.label
                            selected: !!menu.items[menu.selectedIndex] && menu.items[menu.selectedIndex].action === modelData.action
                            onClicked: {
                                // modelData passa da un wrapper QML: la sua
                                // identità JS non coincide con l'oggetto originale.
                                menu.selectedIndex = menu.items.findIndex(function(item) {
                                    return item.action === modelData.action;
                                });
                                menu.focusedLevel = 0;
                                menu.activateSelection();
                            }

                            FilesUi.CommandGlyph {
                                anchors.centerIn: parent
                                width: 20
                                height: 20
                                name: ({
                                    "trash": "delete"
                                })[parent.modelData.action] || parent.modelData.action
                            }

                        }

                    }

                }

                Repeater {
                    id: rootEntries
                    onItemAdded: menu.layoutRevision++
                    onItemRemoved: menu.layoutRevision++
                    model: menu.items
                    delegate: entryTemplate
                }

            }

        }

        Ui.Scorrimento {
            bersaglio: menuScroll
            tinta: menu.windowsAppearance ? Windows11.Style.muted : Theme.Colors.textMuted
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
        }

    }

    Repeater {
        id: submenuViews
        // Un modello numerico mantiene vive le colonne quando cambia solo
        // la selezione. Un array qui le ricreerebbe sotto il puntatore.
        model: menu.branches.length
        delegate: Rectangle {
            id: subcard
            required property int index
            readonly property var branch: menu.branches[index] || ({ items: [], parentIndex: -1 })
            readonly property int contentRevision: branch.revision || 0
            property var dataItems: []
            property bool componentReady: false
            onContentRevisionChanged: if (componentReady) syncItems()
            Component.onCompleted: {
                componentReady = true;
                syncItems();
            }
            function syncItems() {
                var previousScroll = subScroll.contentY;
                dataItems = branch.items;
                var level = index + 1;
                var revision = contentRevision;
                var views = submenuViews;
                var owner = menu;
                Qt.callLater(function() {
                    var view = views ? views.itemAt(level - 1) : null;
                    if (!view || view.contentRevision !== revision)
                        return;
                    view.scroller.contentY = Math.max(0, Math.min(previousScroll, view.scroller.contentHeight - view.scroller.height));
                    if (owner)
                        owner.revealSelection(level);
                });
            }
            readonly property var ownerCard: index === 0 ? card : submenuViews.itemAt(index - 1)
            readonly property bool preferLeft: index === 0 ? false : ownerCard ? ownerCard.openedLeft : false
            readonly property real rightX: ownerCard ? ownerCard.x + ownerCard.width + 4 : 8
            readonly property real leftX: ownerCard ? ownerCard.x - width - 4 : 8
            readonly property bool openedLeft: preferLeft ? leftX >= 8 || rightX + width > menu.width - 8 : rightX + width > menu.width - 8 && leftX >= 8
            property alias column: submenuColumn
            property alias scroller: subScroll
            property alias rows: branchRows
            objectName: "contextMenuBranch-" + (index + 1)
            visible: !menu.customizing
            z: index + 1
            x: Math.max(8, Math.min(openedLeft ? leftX : rightX, menu.width - width - 8))
            y: Math.max(8, Math.min((ownerCard ? ownerCard.y : 0) + menu.rowOffset(index, branch.parentIndex) - 8,
                                   menu.availableHeight - height - 8))
            width: Math.max(0, Math.min(menu.width - 16, Math.max(252, Math.min(420, Math.ceil(branchMeasure.piuLarga) + card.contorno + 10))))
            height: Math.min(submenuColumn.implicitHeight + 16, menu.availableHeight - 16)
            radius: menu.windowsAppearance ? 8 : Theme.Effects.radiusMD
            color: menu.windowsAppearance ? Windows11.Style.surface : Theme.Colors.membrane
            border.color: menu.windowsAppearance ? Windows11.Style.edge : Theme.Colors.edge

            MenuMeasure {
                id: branchMeasure
                items: subcard.dataItems
                windowsAppearance: menu.windowsAppearance
            }
            Loader {
                active: menu.windowsAppearance && subcard.visible
                z: -1
                sourceComponent: Component {
                    Windows11.Shadow { surface: subcard }
                }
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }
            Flickable {
                id: subScroll
                anchors.fill: parent
                contentWidth: width
                contentHeight: submenuColumn.implicitHeight + 16
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: submenuColumn
                    property int menuLevel: subcard.index + 1
                    x: 4
                    y: 8
                    width: subScroll.width - 8 - (subScroll.contentHeight > subScroll.height ? 18 : 0)
                    spacing: 1
                    Repeater {
                        id: branchRows
                        onItemAdded: menu.layoutRevision++
                        onItemRemoved: menu.layoutRevision++
                        model: subcard.dataItems
                        delegate: entryTemplate
                    }
                }
            }
            Ui.Scorrimento {
                bersaglio: subScroll
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
            }
        }
    }

    Component {
        id: entryTemplate

        Rectangle {
            id: entry

            required property var modelData
            required property int index
            readonly property int level: parent ? parent.menuLevel : 0
            readonly property bool secondary: level > 0
            readonly property bool isSeparator: modelData.separator === true
            readonly property bool danger: modelData.danger === true
            readonly property color tone: danger ? Theme.Colors.danger : hover.containsMouse ? (menu.windowsAppearance ? Windows11.Style.text : Theme.Colors.accent) : (menu.windowsAppearance ? Windows11.Style.muted : Theme.Colors.textMuted)

            objectName: "contextMenu-" + (modelData.action || "submenu")
            width: parent ? parent.width : 0
            visible: modelData.quick !== true
            height: !visible ? 0 : isSeparator ? 9 : 34
            radius: menu.windowsAppearance ? 4 : Theme.Effects.radiusSM
            opacity: modelData.enabled === false ? 0.45 : 1
            enabled: !isSeparator && modelData.enabled !== false
            Accessible.role: modelData.checkable ? (modelData.radio ? Accessible.RadioButton : Accessible.CheckBox) : Accessible.MenuItem
            Accessible.name: modelData.label || ""
            Accessible.checkable: modelData.checkable === true
            Accessible.checked: modelData.checked === true
            Accessible.ignored: isSeparator
            Accessible.onPressAction: activateEntry()
            Accessible.onToggleAction: activateEntry()

            function activateEntry() {
                menu.selectEntry(entry.level, entry.index);
                menu.activateSelection();
            }
            color: (!isSeparator && (hover.containsMouse || menu.selectedAt(entry.level) === index)) ? (danger ? Qt.alpha(Theme.Colors.danger, 0.16) : (menu.windowsAppearance ? Windows11.Style.hover : Theme.Colors.hover)) : "transparent"

            // Separatore
            Rectangle {
                anchors.centerIn: parent
                width: parent.width - Theme.Effects.space4
                height: 1
                color: (menu.windowsAppearance ? Windows11.Style.edge : Theme.Colors.edge)
                visible: entry.isSeparator
            }

            Loader {
                id: entryIcon

                property string iconName: entry.modelData.icon || ""

                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space3
                anchors.verticalCenter: parent.verticalCenter
                width: 17
                height: 17
                visible: !entry.isSeparator && (iconName !== "" || !!entry.modelData.iconUrl || entry.modelData.checkable === true)
                sourceComponent: entry.modelData.checkable ? checkIndicator
                                 : entry.modelData.iconUrl ? suppliedIcon
                                 : menu.windowsAppearance ? fluentMenuIcon : liquidMenuIcon

                Component {
                    id: suppliedIcon
                    Image {
                        source: entry.modelData.iconUrl || ""
                        sourceSize: Qt.size(34, 34)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                }
                Component {
                    id: checkIndicator
                    Item {
                        Windows11.Glyph {
                            anchors.fill: parent
                            name: "check"
                            color: entry.tone
                            visible: entry.modelData.checked === true && !entry.modelData.radio
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: entry.modelData.radio ? 7 : 10
                            height: entry.modelData.radio ? 7 : 2
                            radius: entry.modelData.radio ? width / 2 : 0
                            color: entry.tone
                            visible: entry.modelData.radio ? entry.modelData.checked === true : entry.modelData.mixed === true
                        }
                    }
                }

                Component {
                    id: fluentMenuIcon

                    FilesUi.CommandGlyph {
                        name: ({
                            "screen": "monitor",
                            "trash": "delete"
                        })[entryIcon.iconName] || entryIcon.iconName
                        color: entry.tone
                    }

                }

                Component {
                    id: liquidMenuIcon

                    Ui.Icon {
                        name: entryIcon.iconName
                        color: entry.tone
                    }

                }

            }

            Text {
                textFormat: Text.PlainText
                anchors.left: entryIcon.right
                anchors.leftMargin: Theme.Effects.space3
                anchors.right: shortcutText.left
                anchors.rightMargin: Theme.Effects.space2
                anchors.verticalCenter: parent.verticalCenter
                text: entry.modelData.label || ""
                color: entry.danger ? Theme.Colors.danger : (menu.windowsAppearance ? Windows11.Style.text : Theme.Colors.text)
                font.family: (menu.windowsAppearance ? Windows11.Style.font : Theme.Typography.fontDisplay)
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: (menu.windowsAppearance ? 14 * Windows11.Style.textScale : Theme.Typography.sizeMD)
                elide: Text.ElideRight
                visible: !entry.isSeparator
            }

            // Promemoria della scorciatoia equivalente: è così che si
            // impara la tastiera continuando a usare il mouse.
            Text {
                id: shortcutText

                anchors.right: parent.right
                anchors.rightMargin: entry.modelData.children ? 32 : Theme.Effects.space3
                anchors.verticalCenter: parent.verticalCenter
                text: entry.modelData.shortcut || ""
                color: (menu.windowsAppearance ? Windows11.Style.muted : Theme.Colors.textFaint)
                font.family: menu.windowsAppearance ? Windows11.Style.font : Theme.Typography.fontMono
                font.pixelSize: menu.windowsAppearance ? 12 * Windows11.Style.textScale : Theme.Typography.sizeXS
                visible: !entry.isSeparator
            }

            Windows11.Glyph {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                name: "chevronRight"
                color: entry.tone
                visible: !entry.isSeparator && !!entry.modelData.children
            }

            MouseArea {
                id: hover

                anchors.fill: parent
                hoverEnabled: true
                enabled: !entry.isSeparator && entry.modelData.enabled !== false
                onEntered: menu.previewEntry(entry.level, entry.index)
                cursorShape: Qt.PointingHandCursor
                onClicked: entry.activateEntry()
            }

            Behavior on color {
                ColorAnimation {
                    duration: Theme.Motion.instant
                }

            }

        }

    }

    Rectangle {
        id: customization

        objectName: "contextCustomize"
        visible: menu.customizing
        width: Math.min(420, menu.width - 16)
        height: Math.min(520, menu.height - 16)
        anchors.centerIn: parent
        radius: 8
        color: Windows11.Style.surface
        border.color: Windows11.Style.edge

        Windows11.Shadow {
            surface: customization
        }

        MouseArea {
            anchors.fill: parent
        }

        Flickable {
            id: customScroll

            anchors.fill: parent
            anchors.margins: 16
            anchors.rightMargin: 32
            anchors.bottomMargin: 66
            contentWidth: width
            contentHeight: customColumn.implicitHeight
            clip: true

            Column {
                id: customColumn

                width: customScroll.width
                spacing: 8

                Text {
                    text: Windows11.Style.label("Personalizza menu", "Customize menu")
                    color: Windows11.Style.text
                    font.family: Windows11.Style.font
                    font.pixelSize: 20
                }

                Controls.CheckBox {
                    id: customInline

                    palette.text: Windows11.Style.text
                    palette.highlight: Windows11.Style.accent
                    font.family: Windows11.Style.font
                    objectName: "contextCustomize-inline"
                    width: parent.width
                    text: Windows11.Style.label("Comandi principali come testo", "Main commands as text")
                    checked: menu.inlineCommands
                    onToggled: {
                        Core.Ipc.setSetting("windows11.contextInline", checked);
                        menu.rebuild();
                    }
                }

                Controls.CheckBox {
                    palette.text: Windows11.Style.text
                    palette.highlight: Windows11.Style.accent
                    font.family: Windows11.Style.font
                    objectName: "contextCustomize-properties"
                    width: parent.width
                    text: Windows11.Style.label("Proprietà in fondo", "Properties at the bottom")
                    checked: menu.propertiesLast
                    onToggled: {
                        Core.Ipc.setSetting("windows11.contextPropertiesLast", checked);
                        menu.rebuild();
                    }
                }

                Controls.CheckBox {
                    palette.text: Windows11.Style.text
                    palette.highlight: Windows11.Style.accent
                    font.family: Windows11.Style.font
                    objectName: "contextCustomize-extensions"
                    width: parent.width
                    text: Windows11.Style.label("Mostra altre azioni", "Show other actions")
                    checked: menu.extensionsVisible
                    onToggled: {
                        Core.Ipc.setSetting("windows11.contextExtensions", checked);
                        menu.rebuild();
                    }
                }

                Repeater {
                    model: menu.originalItems.filter(function(item) {
                        return !!item.action;
                    })

                    delegate: Controls.CheckBox {
                        required property var modelData

                        palette.text: Windows11.Style.text
                        palette.highlight: Windows11.Style.accent
                        font.family: Windows11.Style.font
                        objectName: "contextCustomize-action-" + modelData.action
                        width: customColumn.width
                        text: modelData.label
                        checked: menu.hiddenActions.indexOf(modelData.action) < 0
                        onToggled: menu.toggleAction(modelData.action, checked)
                    }

                }

            }

        }

        Windows11.Button {
            objectName: "contextCustomize-done"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            text: Windows11.Style.label("Fine", "Done")
            onClicked: {
                menu.customizing = false;
                keyCatcher.forceActiveFocus();
            }
        }

        Ui.Scorrimento {
            bersaglio: customScroll
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
        }

        Shortcut {
            sequence: "Escape"
            enabled: menu.visible && menu.customizing
            onActivated: {
                menu.customizing = false;
                keyCatcher.forceActiveFocus();
            }
        }

    }

}

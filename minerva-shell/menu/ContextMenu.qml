import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// ContextMenu — Menu a comparsa riutilizzabile, posizionato dove si è cliccato.
//
// Le voci si passano come array di oggetti semplici:
//
//     items: [
//         { "label": "Nuovo terminale", "icon": "terminal", "action": "terminal" },
//         { "separator": true },
//         { "label": "Chiudi", "icon": "close", "action": "close", "danger": true }
//     ]
//
// `icon` è il nome di un tracciato di Ui.Icon, non un carattere: i glifi
// Unicode vengono resi da font diversi su sistemi diversi e in un elenco
// verticale la differenza di peso salta all'occhio.
//
// Si reagisce al segnale `triggered(action)`. Le azioni sono stringhe e non
// funzioni: così restano ispezionabili nei log e il menu non trattiene
// riferimenti a oggetti che potrebbero essere già stati distrutti.
PanelWindow {
    id: menu

    anchors { top: true; bottom: true; left: true; right: true }

    WlrLayershell.namespace: "quickshell"
    WlrLayershell.layer: WlrLayer.Overlay
    // ── La tastiera, tutta, finché è aperto ─────────────────────────────
    //
    // Era `OnDemand`: il compositore dà la tastiera a una superficie così
    // solo quando la si CLICCA, e un menù aperto col tasto destro non viene
    // cliccato prima di scegliere. `Esc` finiva alla finestra di sotto e il
    // menù restava lì (PC di prova, 29 settembre 2026). Il menù esiste solo
    // da aperto, quindi prendere la tastiera non toglie niente a nessuno.
    WlrLayershell.keyboardFocus: menu.visible ? WlrKeyboardFocus.Exclusive
                                              : WlrKeyboardFocus.None

    // Copre l'intero schermo, barra compresa: senza questo il layer verrebbe
    // spinto sotto la zona esclusiva della barra e le coordinate del mouse
    // risulterebbero sfalsate di tutta l'altezza della barra stessa.
    exclusionMode: ExclusionMode.Ignore

    color: "transparent"
    visible: false

    /// Voci del menu
    property var items: []

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

    signal triggered(string action)
    // NB: non chiamarlo `closed`: collide con un segnale di PanelWindow
    signal dismissed()

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

    // ── Aprirlo dove sta il puntatore ────────────────────────────────────
    //
    // `openAt` vuole coordinate dello SCHERMO, perché questo menu è una
    // superficie a schermo intero. Chi lo chiama da una finestra normale non
    // ce le ha: **su Wayland una finestra non sa dove si trova**, e
    // `mapToGlobal` restituisce coordinate relative alla finestra stessa. Il
    // menu compariva quindi spostato di tutta la posizione della finestra —
    // il difetto che Giacomo aveva descritto come «menu fuori posto».
    //
    // Nelle superfici della shell (barra, dock, scrivania) il problema non
    // c'è: quelle sono ancorate all'origine dello schermo e le due coordinate
    // coincidono. È solo nelle finestre — gestore file, Anteprima — che
    // servono queste due funzioni.
    //
    // Chi la posizione la sa è il compositore, e gliela si chiede. Un
    // processo per ogni tasto destro è un costo che si può pagare: è un
    // gesto, non un ciclo. (Quickshell 0.3 non espone la posizione del
    // puntatore in nessun modo: cercata in tutti i moduli, non c'è.)

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

    /// Come sopra, ma il menu cresce verso l'alto e centrato.
    function openAboveCursor(menuItems) {
        menu._inArrivo = menuItems;
        menu._versoAlto = true;
        menu._centrato = true;
        Core.Compositore.chiedi("puntatore");
        senzaRisposta.restart();
    }

    property var _inArrivo: null
    property bool _versoAlto: false
    property bool _centrato: false

    // ── Se la risposta non arriva, si apre lo stesso ─────────────────────
    //
    // Un menu che aspetta una risposta per esistere è un menu che a volte non
    // compare, e «il tasto destro non fa niente» è uno di quei difetti che
    // nessuno riesce a riprodurre a comando — perché dipende dai tempi.
    // Osservato il 4 settembre 2026 nella galleria: due tentativi su quattro,
    // stessa versione, stesso punto.
    //
    // Duecentocinquanta millisecondi: il compositore è a un socket di
    // distanza e risponde in meno di uno. Se non l'ha fatto, non lo farà, e
    // un menu nell'angolo è **molto** meno grave di nessun menu.
    Timer {
        id: senzaRisposta
        interval: 250
        onTriggered: {
            if (menu._inArrivo === null)
                return;
            var voci = menu._inArrivo;
            menu._inArrivo = null;
            menu.growUp = menu._versoAlto;
            menu.centred = menu._centrato;
            menu._show(menu.menuX, menu.menuY, voci);
        }
    }

    Connections {
        target: Core.Compositore
        function onRisposta(cosa, text) {
            if (cosa !== "puntatore" || menu._inArrivo === null)
                return;
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
                    x = 0; y = 0;
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
            }
        }
    }

    function _show(x, y, menuItems) {
        menu.items = menuItems;
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
        if (!menu.visible)
            return;
        menu.visible = false;
        menu.dismissed();
    }

    // ── Si è aperta un'altra finestra: il menù non le resta sopra ────────
    //
    // Con `Super+I` a menù aperto, le Impostazioni comparivano SOTTO il
    // menù, che restava lì finché non si cliccava. La finestra attiva che
    // cambia vuol dire che l'attenzione è andata altrove. Il primo attimo
    // dopo l'apertura non conta: il menù della barra del titolo dà il fuoco
    // alla finestra e subito dopo si apre, e non deve richiudersi da solo.
    property real _apertoAlle: 0
    Connections {
        target: Core.Windows
        function onActiveAddressChanged() {
            if (menu.visible && Date.now() - menu._apertoAlle > 500)
                menu.close();
        }
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
        Keys.onEscapePressed: menu.close()
    }

    Rectangle {
        id: card

        // Il menu non deve mai uscire dallo schermo. Il vincolo è l'ultima
        // parola, ma arriva DOPO aver scelto il verso giusto: rimediare col
        // solo vincolo sposta il menu, sceglierlo bene lo lascia dov'è.
        readonly property real wantX: menu.centred ? menu.menuX - width / 2 : menu.menuX
        readonly property real wantY: menu.growUp ? menu.menuY - height : menu.menuY

        x: Math.max(8, Math.min(card.wantX, menu.width - width - 8))
        y: Math.max(8, Math.min(card.wantY, menu.height - height - 8))

        // ── Larga quanto la voce più lunga ───────────────────────────────
        //
        // Era fissa a 252, e le voci più lunghe finivano con dei puntini:
        // «Trasmetti a TV camer…». Il nome di un televisore, di un programma
        // o di un file non è una cosa che si possa accorciare — è proprio
        // l'informazione per cui si è aperto il menu.
        //
        // ── Misurata con lo STESSO elemento che poi disegna ──────────────
        //
        // Il primo tentativo usava `FontMetrics.advanceWidth`, ed è arrivato
        // a due pixel dal risultato giusto — cioè continuava a tagliare.
        // Fra la larghezza che un `FontMetrics` calcola e quella che un
        // `Text` occupa ci sono la spaziatura fra lettere, l'arrotondamento e
        // il peso del carattere: differenze piccole, e bastano.
        //
        // Qui si misura con dei `Text` veri, invisibili e fuori dal disegno,
        // con esattamente le stesse proprietà di quelli visibili. Non è un
        // trucco: è l'unico modo di non avere due idee diverse della stessa
        // larghezza. Non c'è anello, perché questi non hanno una `width`
        // legata alla scheda — solo la loro `implicitWidth`.
        Item {
            id: righello
            visible: false
            width: 0
            height: 0

            readonly property real piuLarga: {
                var w = 0;
                for (var i = 0; i < misure.count; i++) {
                    var t = misure.itemAt(i);
                    if (t)
                        w = Math.max(w, t.quanto);
                }
                return w;
            }

            Repeater {
                id: misure
                model: menu.items
                Item {
                    required property var modelData
                    readonly property real quanto: modelData
                        && modelData.separator !== true
                        ? etichetta.implicitWidth + tasti.implicitWidth
                          + (tasti.text !== "" ? Theme.Effects.space4 : 0)
                        : 0
                    Text {
                        id: etichetta
                        text: (modelData && modelData.label) || ""
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeMD
                    }
                    Text {
                        id: tasti
                        text: (modelData && modelData.shortcut) || ""
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }
            }
        }

        /// Il contorno, contato e non stimato: margine sinistro (space3) +
        /// icona (17) + stacco (space3) + [testo] + stacco (space2) + margine
        /// destro (space3). Sono gli stessi ancoraggi della riga qui sotto —
        /// sbagliarli di dieci pixel rimette i puntini.
        readonly property real contorno:
            17 + Theme.Effects.space3 * 3 + Theme.Effects.space2

        // Il minimo resta 252, perché un menu di tre voci corte non deve
        // diventare un francobollo; il massimo è 420, perché oltre non è più
        // un menu ed è meglio un nome accorciato di una lenzuola.
        width: Math.max(252, Math.min(420,
                        Math.ceil(righello.piuLarga) + card.contorno + 2))
        implicitHeight: itemsColumn.implicitHeight + Theme.Effects.space2 * 2
        height: implicitHeight

        radius: Theme.Effects.radiusMD
        color: Theme.Colors.membrane
        border.width: 1
        border.color: Theme.Colors.edge

        opacity: 0
        scale: 0.94
        // Il menu cresce DAL punto cliccato: l'origine della scala segue
        // l'angolo in cui è stato aperto, altrimenti sembra planarci sopra.
        transformOrigin: menu.growUp
                         ? (menu.centred ? Item.Bottom : Item.BottomLeft)
                         : (menu.centred ? Item.Top : Item.TopLeft)

        ParallelAnimation {
            id: showAnim
            NumberAnimation {
                target: card; property: "opacity"; to: 1
                duration: Theme.Motion.quick
            }
            NumberAnimation {
                target: card; property: "scale"; to: 1
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

        Column {
            id: itemsColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: Theme.Effects.space2
            anchors.leftMargin: Theme.Effects.space1
            anchors.rightMargin: Theme.Effects.space1
            spacing: 1

            Repeater {
                model: menu.items

                delegate: Rectangle {
                    id: entry
                    required property var modelData

                    readonly property bool isSeparator: modelData.separator === true
                    readonly property bool danger: modelData.danger === true
                    readonly property color tone: danger ? Theme.Colors.danger
                                                : hover.containsMouse ? Theme.Colors.accent
                                                : Theme.Colors.textMuted

                    width: itemsColumn.width
                    height: isSeparator ? 9 : 34
                    radius: Theme.Effects.radiusSM

                    color: (!isSeparator && hover.containsMouse)
                           ? (danger ? Qt.alpha(Theme.Colors.danger, 0.16)
                                     : Theme.Colors.hover)
                           : "transparent"

                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    // Separatore
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - Theme.Effects.space4
                        height: 1
                        color: Theme.Colors.edge
                        visible: entry.isSeparator
                    }

                    Ui.Icon {
                        id: entryIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.Effects.space3
                        anchors.verticalCenter: parent.verticalCenter
                        width: 17; height: 17
                        name: entry.modelData.icon || ""
                        color: entry.tone
                        visible: !entry.isSeparator
                    }

                    Text {
                        anchors.left: entryIcon.right
                        anchors.leftMargin: Theme.Effects.space3
                        anchors.right: shortcutText.left
                        anchors.rightMargin: Theme.Effects.space2
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.label || ""
                        color: entry.danger ? Theme.Colors.danger : Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeMD
                        elide: Text.ElideRight
                        visible: !entry.isSeparator
                    }

                    // Promemoria della scorciatoia equivalente: è così che si
                    // impara la tastiera continuando a usare il mouse.
                    Text {
                        id: shortcutText
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.Effects.space3
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.shortcut || ""
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: Theme.Typography.sizeXS
                        visible: !entry.isSeparator
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !entry.isSeparator
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var action = entry.modelData.action || "";
                            menu.close();
                            if (action !== "")
                                menu.triggered(action);
                        }
                    }
                }
            }
        }
    }
}

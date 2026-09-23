import QtQuick
import Quickshell
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// SelettoreImmagine — Scegliere un'immagine senza uscire da dove si sta.
//
// ── Perché non si apre il gestore file ─────────────────────────────────────
//
// Perché ci si apriva, e non funzionava. Il bottone «Scegli dal disco» in
// Impostazioni → Utente lanciava `minerva-files` sulla cartella delle
// immagini, e il commento accanto lo ammetteva già: «Non è un selettore: si
// copia il percorso col tasto destro e lo si incolla sopra».
//
// Giacomo, provandolo: «scegli da disco apre il file manager e da lì non posso
// cliccare su seleziona». È esattamente quello: un gestore file non ha modo di
// restituire una scelta a chi l'ha aperto. Servirebbe il portale del desktop
// (`xdg-desktop-portal`), che è un'altra cosa e un altro lavoro.
//
// Qui si sceglie dentro le Impostazioni, come si sceglie già la cartella degli
// sfondi in `sections/Appearance.qml` — da cui viene tutto quello che c'è
// sotto: `Core.Ipc.fsList` con un'etichetta, e `onFileListingReceived` che
// scarta le risposte degli altri.
//
// ── La trappola, pagata una volta e scritta lì ─────────────────────────────
//
// `visible: false` NASCONDE, NON SOSPENDE. Un `Repeater` di anteprime dentro
// un riquadro invisibile costruisce le sue celle e DECODIFICA le sue immagini
// come se fosse in primo piano: nella cartella di Giacomo erano trecentoundici
// fotografie. Per questo il modello è vuoto finché non si apre, e non basta
// nascondere la griglia.
Rectangle {
    id: selettore

    /// Il file scelto. Chi ascolta decide cosa farne.
    signal scelta(string percorso)

    anchors.fill: parent
    color: Theme.Colors.scrim
    visible: false
    z: 30

    property string cartella: ""
    property var cartelle: []
    property var immagini: []
    property bool caricando: false

    /// L'etichetta con cui si riconoscono le NOSTRE risposte. Il demone serve
    /// tre finestre e la stessa `fsList` la chiedono in quattro punti diversi.
    readonly property string etichetta: "selettoreImmagine"

    readonly property bool it: Core.Strings.lang === "it"

    readonly property var estensioni: [
        ".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif", ".avif", ".jxl"
    ]

    function eImmagine(nome) {
        var b = nome.toLowerCase();
        for (var i = 0; i < selettore.estensioni.length; i++) {
            var e = selettore.estensioni[i];
            if (b.lastIndexOf(e) === b.length - e.length)
                return true;
        }
        return false;
    }

    function apri(inizio) {
        selettore.cartella = inizio && inizio !== "" ? inizio
                                                     : Quickshell.env("HOME");
        selettore.visible = true;
        selettore.leggi();
    }

    function chiudi() {
        selettore.visible = false;
        // Si lascia la cartella dove si era: riaprire il selettore e ritrovarsi
        // in casa dopo aver navigato tre livelli è il modo di farlo usare una
        // volta sola. Le anteprime invece si buttano, o restano decodificate in
        // memoria per una finestra che non si vede.
        selettore.cartelle = [];
        selettore.immagini = [];
    }

    function leggi() {
        selettore.caricando = true;
        selettore.cartelle = [];
        selettore.immagini = [];
        Core.Ipc.fsList(selettore.cartella, false, selettore.etichetta);
    }

    function su() {
        var p = selettore.cartella;
        if (p.length > 1 && p.charAt(p.length - 1) === "/")
            p = p.substring(0, p.length - 1);
        var taglio = p.lastIndexOf("/");
        selettore.cartella = taglio <= 0 ? "/" : p.substring(0, taglio);
        selettore.leggi();
    }

    Connections {
        target: Core.Ipc
        function onFileListingReceived(elenco) {
            if (elenco.pane !== selettore.etichetta)
                return;
            var dirs = [];
            var imgs = [];
            var voci = elenco.entries || [];
            for (var i = 0; i < voci.length; i++) {
                var v = voci[i];
                if (v.name.charAt(0) === ".")
                    continue;
                if (v.isDir)
                    dirs.push(v);
                else if (selettore.eImmagine(v.name))
                    imgs.push(v);
            }
            selettore.cartelle = dirs;
            selettore.immagini = imgs;
            selettore.caricando = false;
        }
    }

    // Il clic sul velo chiude. Prende anche tutti i clic che passerebbero alla
    // pagina sotto, che è metà del motivo per cui questo riquadro esiste.
    MouseArea {
        anchors.fill: parent
        onClicked: selettore.chiudi()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.Effects.space6, 720)
        height: Math.min(parent.height - Theme.Effects.space6, 560)
        radius: Theme.Effects.radiusMD
        color: Theme.Colors.panel
        border.width: 1
        border.color: Theme.Colors.edge

        MouseArea { anchors.fill: parent }

        // ── Dove siamo ───────────────────────────────────────────────────
        Item {
            id: testa
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.Effects.space3
            height: 34

            Rectangle {
                id: bottoneSu
                width: 34
                height: 34
                radius: Theme.Effects.radiusXS
                color: suMouse.containsMouse ? Theme.Colors.raisedHigh
                                             : Theme.Colors.raised
                border.width: Theme.Effects.hairline
                border.color: Theme.Colors.edge

                // `Ui.Icon` è un `Item`: si misura con width/height, non con
                // un `size` che non esiste. Scritto `size: 16` al primo giro,
                // e QML non lo perdona — una proprietà inesistente non è un
                // avviso, è il file che non si carica.
                Ui.Icon {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    name: "chevron"
                    rotation: -90
                    color: Theme.Colors.text
                }

                MouseArea {
                    id: suMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: selettore.su()
                }
            }

            Text {
                anchors.left: bottoneSu.right
                anchors.leftMargin: Theme.Effects.space3
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: selettore.cartella
                elide: Text.ElideMiddle
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXS
            }
        }

        // ── Quello che c'è dentro ────────────────────────────────────────
        Ui.Scorrimento {
            bersaglio: lista
            anchors {
                right: lista.right
                top: lista.top
                bottom: lista.bottom
            }
        }

        Flickable {
            id: lista
            anchors.top: testa.bottom
            anchors.topMargin: Theme.Effects.space3
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: piede.top
            anchors.leftMargin: Theme.Effects.space3
            anchors.rightMargin: Theme.Effects.space3
            anchors.bottomMargin: Theme.Effects.space2
            clip: true
            contentHeight: dentro.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: dentro
                width: lista.width
                spacing: Theme.Effects.space2

                Text {
                    visible: selettore.caricando
                    text: selettore.it ? "Sto guardando…" : "Looking…"
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Text {
                    visible: !selettore.caricando
                             && selettore.cartelle.length === 0
                             && selettore.immagini.length === 0
                    text: selettore.it ? "Qui non ci sono immagini."
                                       : "No images here."
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                // Le cartelle in riga, piccole: si passa di lì, non ci si resta.
                Flow {
                    width: parent.width
                    spacing: Theme.Effects.space1

                    Repeater {
                        // Vuoto a finestra chiusa: vedi la nota in cima.
                        model: selettore.visible ? selettore.cartelle : []

                        delegate: Rectangle {
                            required property var modelData
                            height: 30
                            width: nomeCartella.width + 42
                            radius: Theme.Effects.radiusXS
                            color: cartMouse.containsMouse ? Theme.Colors.raisedHigh
                                                           : Theme.Colors.raised
                            border.width: Theme.Effects.hairline
                            border.color: Theme.Colors.edge

                            Ui.Icon {
                                id: iconaCartella
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14
                                height: 14
                                name: "folder"
                                color: Theme.Colors.accent
                            }

                            Text {
                                id: nomeCartella
                                anchors.left: iconaCartella.right
                                anchors.leftMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                                color: Theme.Colors.text
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeXS
                            }

                            MouseArea {
                                id: cartMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    selettore.cartella = modelData.path;
                                    selettore.leggi();
                                }
                            }
                        }
                    }
                }

                Grid {
                    id: griglia
                    width: parent.width
                    columns: 4
                    spacing: Theme.Effects.space2

                    readonly property real cella:
                        (width - spacing * (columns - 1)) / columns

                    Repeater {
                        model: selettore.visible ? selettore.immagini : []

                        delegate: Rectangle {
                            required property var modelData
                            width: griglia.cella
                            height: griglia.cella
                            radius: Theme.Effects.radiusSM
                            color: Theme.Colors.sunken
                            border.width: 1
                            border.color: fotoMouse.containsMouse
                                          ? Theme.Colors.accent : Theme.Colors.edge
                            clip: true

                            Image {
                                anchors.fill: parent
                                anchors.margins: 1
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                // Si decodifica alla misura della cella e non a
                                // quella del file: una cartella di fotografie da
                                // dodici megapixel, decodificate intere, sono
                                // centinaia di megabyte per delle miniature.
                                sourceSize.width: 320
                                source: "file://" + modelData.path
                            }

                            MouseArea {
                                id: fotoMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    selettore.scelta(modelData.path);
                                    selettore.chiudi();
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Il piede ─────────────────────────────────────────────────────
        Item {
            id: piede
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.Effects.space3
            height: 34

            Rectangle {
                anchors.right: parent.right
                width: 110
                height: 34
                radius: Theme.Effects.radiusSM
                color: chiudiMouse.containsMouse ? Theme.Colors.raisedHigh
                                                 : Theme.Colors.raised
                border.width: Theme.Effects.hairline
                border.color: Theme.Colors.edge

                Text {
                    anchors.centerIn: parent
                    text: selettore.it ? "Lascia perdere" : "Never mind"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }

                MouseArea {
                    id: chiudiMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: selettore.chiudi()
                }
            }
        }
    }
}

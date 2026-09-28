import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui

// Defaults — Chi apre che cosa.
//
// Nasce dal difetto più fastidioso che Minerva abbia avuto: le immagini si
// aprivano con Google Chrome. Non per una scelta sbagliata, ma perché non
// c'era nessun posto dove farla — e in mancanza di una scelta vince il primo
// programma che dichiara di saper leggere quel tipo, che è quasi sempre un
// browser, perché un browser dichiara di saper leggere quasi tutto.
//
// ── PERCHÉ SI SCEGLIE PER GRUPPI ─────────────────────────────────────────
//
// Un pannello che elenca `image/png`, `image/jpeg`, `image/webp`… è il file
// `mimeapps.list` ridisegnato con i bordi arrotondati. Chi lo apre non pensa
// «voglio Gwenview per i PNG»: pensa «voglio Gwenview per le foto». Se poi il
// primo JPEG torna nel browser, l'impressione è che l'impostazione non abbia
// funzionato — e in un certo senso è vero.
//
// Quindi si sceglie una volta per gruppo e il demone scrive tutti i tipi del
// gruppo in un colpo solo. I tipi sparsi che restano da prima si vedono: la
// riga lo dice invece di far finta di niente.
//
// ── E PERCHÉ I GRUPPI STANNO IN FAMIGLIE ─────────────────────────────────
//
// Perché da nove sono diventati sedici, e sedici righe in fila sono un elenco
// da scorrere. Giacomo, 17 agosto 2026: «riorganizza questa sezione per tipi
// affini, mettiamo delle tendine espandibili dove poi aprire e scegliere i
// programmi… così la sezione sarà più compatta e semplice sapendo che tipo di
// app cerchi».
//
// Cinque tendine — Internet, Documenti, Immagini/musica/video, Testo e codice,
// Sistema — e dentro ognuna i suoi gruppi. Chi cerca il lettore video sa dove
// guardare prima di aprire qualcosa, che è tutto il punto.
//
// La divisione la decide il DEMONE insieme ai gruppi (`MimeService.famiglie`).
// Se la decidesse questa pagina, il giorno che qualcuno aggiunge un gruppo
// nella tabella del demone quel gruppo sparirebbe dalle impostazioni senza che
// nessuno se ne accorga.
//
// ── IL TERMINALE STA QUI DENTRO ──────────────────────────────────────────
//
// Non è un tipo di file e non passa da `mimeapps.list`: nessuno «apre» un
// terminale, lo si chiama. Ma è la stessa domanda — chi fa questa cosa — e per
// un po' è stato in una carta tutta sua in fondo alla pagina. Parole di
// Giacomo: «il terminale non lo tenere da parte, hai fatto una sezione
// staccata». Adesso è una riga dentro «Sistema», accanto a Cartelle e Archivi,
// e l'unica differenza è dove va a finire la scelta.
Page {
    id: page

    title: Core.Strings.lang === "it" ? "App predefinite" : "Default apps"
    subtitle: Core.Strings.lang === "it"
              ? "Con che cosa si aprono immagini, video, pagine web"
              : "What opens images, video, web pages"

    readonly property bool it: Core.Strings.lang === "it"

    property var categories: []
    property var famiglie: []

    /// Una famiglia aperta per volta, e dentro un gruppo per volta. Sedici
    /// elenchi di candidati aperti insieme sono cinquecento righe da scorrere
    /// per cambiare una cosa.
    property string openFamily: ""
    property string openId: ""

    function refresh() {
        if (Core.Ipc.connected)
            Core.Ipc.mimeCategories();
    }

    Component.onCompleted: page.refresh()

    Connections {
        target: Core.Ipc
        function onConnectedChanged() { page.refresh(); }
        function onMimeCategoriesReceived(cats, fam) {
            page.categories = cats || [];
            page.famiglie = fam || [];
        }
    }

    // ── Il terminale, che non è un tipo di file ──────────────────────────
    //
    // Si trova per la categoria `TerminalEmulator` dei `.desktop`, che è il
    // campo fatto apposta. Non per un elenco di nomi scritto qui dentro: un
    // elenco di nomi conosce i terminali che conoscevo io il giorno che l'ho
    // scritto, e chi ne installa un altro non lo vede comparire.

    readonly property string terminaleOra:
        Core.Ipc.get("launcher.defaultTerminal", "minerva-terminale")

    /// Il comando da lanciare, ricavato dal `.desktop`.
    ///
    /// Solo la prima parola: quello che segue sono i codici di campo (`%u`,
    /// `%F`) e le opzioni per aprire un file — roba che a un terminale
    /// lanciato da solo non serve, e che passata così com'è lo fa partire con
    /// un argomento che non capisce.
    function comandoDi(a) {
        var e = String(a.exec || "").trim();
        if (e === "")
            return "";
        return e.split(/\s+/)[0];
    }

    readonly property var vociTerminale: {
        var fuori = [];
        var tutti = Core.Apps.all;
        for (var i = 0; i < tutti.length; i++) {
            var a = tutti[i];
            var c = a.categories || [];
            if (c.indexOf("TerminalEmulator") === -1)
                continue;
            var cmd = page.comandoDi(a);
            if (cmd === "")
                continue;
            fuori.push({
                "id": cmd,
                "name": a.name,
                // Le voci dei gruppi portano `iconPath`; qui l'icona già
                // risolta si chiama `icon`. Si uniforma qui e non nel
                // delegato, che deve restare uno solo.
                "iconPath": a.icon || ""
            });
        }
        fuori.sort(function (x, y) {
            return String(x.name).localeCompare(String(y.name));
        });
        return fuori;
    }

    readonly property var rigaTerminale: {
        var scelto = null;
        for (var i = 0; i < page.vociTerminale.length; i++) {
            if (page.vociTerminale[i].id === page.terminaleOra)
                scelto = page.vociTerminale[i];
        }
        return {
            "id": "terminale",
            "tipo": "terminale",
            "famiglia": "sistema",
            "it": "Il terminale",
            "en": "The terminal",
            "icon": "terminal",
            // Se il comando impostato non risulta installato, `defaultApp`
            // resta pieno e `defaultName` mostra il comando così com'è: dire
            // «da scegliere» sarebbe falso, e mostrare una riga senza spunta
            // lascerebbe credere che non sia stato scelto niente.
            "defaultApp": page.terminaleOra,
            "defaultName": scelto ? scelto.name : page.terminaleOra,
            "defaultIcon": scelto ? scelto.iconPath : "",
            "mancante": scelto === null,
            "mixed": false,
            "candidates": page.vociTerminale
        };
    }

    /// I gruppi di una famiglia, col terminale infilato dove va.
    function gruppiDi(idFamiglia) {
        var fuori = [];
        for (var i = 0; i < page.categories.length; i++) {
            var c = page.categories[i];
            if (c.famiglia === idFamiglia) {
                c.tipo = "mime";
                fuori.push(c);
            }
        }
        if (idFamiglia === "sistema")
            fuori.push(page.rigaTerminale);
        return fuori;
    }

    function scegli(gruppo, appId) {
        if (gruppo.tipo === "terminale")
            Core.Ipc.setSetting("launcher.defaultTerminal", appId);
        else
            Core.Ipc.mimeSetCategory(gruppo.id, appId);
    }

    Card {
        heading: page.it ? "Aprire i file" : "Opening files"
        note: page.it
              ? "La scelta si scrive in ~/.config/mimeapps.list, il file "
                + "che tutti gli ambienti grafici leggono: vale anche fuori "
                + "da Minerva, e le scelte fatte altrove si vedono qui."
              : "The choice is written to ~/.config/mimeapps.list, the file "
                + "every desktop reads: it applies outside Minerva too, and "
                + "choices made elsewhere show up here."

        Column {
            width: parent.width
            spacing: 2

            Text {
                width: parent.width
                visible: page.famiglie.length === 0
                wrapMode: Text.WordWrap
                text: page.it ? "Sto leggendo l'elenco dei programmi…"
                              : "Reading the list of programs…"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            // ── Primo livello: la famiglia ───────────────────────────────
            Repeater {
                model: page.famiglie

                delegate: Rectangle {
                    id: famiglia
                    required property var modelData

                    readonly property bool aperta:
                        page.openFamily === famiglia.modelData.id
                    readonly property var gruppi:
                        page.gruppiDi(famiglia.modelData.id)

                    width: parent.width
                    implicitHeight: pila.implicitHeight + Theme.Effects.space2
                    radius: Theme.Effects.radiusSM
                    color: famiglia.aperta ? Theme.Colors.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Column {
                        id: pila
                        anchors.top: parent.top
                        anchors.topMargin: 4
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 4

                        Item {
                            width: parent.width
                            height: 44

                            Ui.Icon {
                                id: iconaFamiglia
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.Effects.space2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20; height: 20
                                name: famiglia.modelData.icon
                                color: famiglia.aperta ? Theme.Colors.accent
                                                       : Theme.Colors.textFaint
                            }

                            Text {
                                anchors.left: iconaFamiglia.right
                                anchors.leftMargin: Theme.Effects.space3
                                anchors.verticalCenter: parent.verticalCenter
                                text: page.it ? famiglia.modelData.it
                                              : famiglia.modelData.en
                                color: Theme.Colors.text
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeMD
                                font.weight: Theme.Typography.weightMedium
                            }

                            Text {
                                id: quanti
                                anchors.right: frecciaFamiglia.left
                                anchors.rightMargin: Theme.Effects.space3
                                anchors.verticalCenter: parent.verticalCenter
                                text: famiglia.gruppi.length
                                color: Theme.Colors.textFaint
                                font.family: Theme.Typography.fontMono
                                font.pixelSize: Theme.Typography.sizeXS
                            }

                            Ui.Icon {
                                id: frecciaFamiglia
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.Effects.space2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14; height: 14
                                name: famiglia.aperta ? "chevronUp" : "chevron"
                                color: Theme.Colors.textFaint
                                alwaysDrawn: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    page.openFamily = famiglia.aperta
                                                      ? "" : famiglia.modelData.id;
                                    // Chiudendo la famiglia si chiude anche il
                                    // gruppo che era aperto dentro: riaprirla e
                                    // ritrovare un elenco di candidati spalancato
                                    // fa sembrare che si sia cliccato due volte.
                                    page.openId = "";
                                }
                            }
                        }

                        // ── Secondo livello: i gruppi ────────────────────
                        Column {
                            width: parent.width
                            visible: famiglia.aperta
                            spacing: 1

                            Repeater {
                                model: famiglia.aperta ? famiglia.gruppi : []

                                delegate: Rectangle {
                                    id: group
                                    required property var modelData

                                    readonly property bool open:
                                        page.openId === group.modelData.id
                                    readonly property bool empty:
                                        !group.modelData.candidates
                                        || group.modelData.candidates.length === 0

                                    width: parent.width
                                    implicitHeight: stack.implicitHeight + 4
                                    radius: Theme.Effects.radiusXS
                                    color: group.open ? Theme.Colors.raised : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                                    Column {
                                        id: stack
                                        anchors.top: parent.top
                                        anchors.topMargin: 2
                                        anchors.left: parent.left
                                        anchors.leftMargin: Theme.Effects.space3
                                        anchors.right: parent.right
                                        spacing: 4

                                        // ── La riga del gruppo ───────────
                                        Item {
                                            id: rigaGruppo
                                            width: parent.width
                                            height: 40

                                            Ui.Icon {
                                                id: groupIcon
                                                anchors.left: parent.left
                                                anchors.leftMargin: Theme.Effects.space2
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 18; height: 18
                                                name: group.modelData.icon
                                                color: group.open ? Theme.Colors.accent
                                                                  : Theme.Colors.textFaint
                                            }

                                            Text {
                                                id: groupName
                                                anchors.left: groupIcon.right
                                                anchors.leftMargin: Theme.Effects.space3
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: page.it ? group.modelData.it
                                                              : group.modelData.en
                                                color: Theme.Colors.text
                                                font.family: Theme.Typography.fontDisplay
                                                font.pixelSize: Theme.Typography.sizeSM
                                                font.weight: Theme.Typography.weightMedium
                                            }

                                            Ui.Icon {
                                                id: groupChevron
                                                anchors.right: parent.right
                                                anchors.rightMargin: Theme.Effects.space2
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 14; height: 14
                                                visible: !group.empty
                                                name: group.open ? "chevronUp" : "chevron"
                                                color: Theme.Colors.textFaint
                                                alwaysDrawn: true
                                            }

                                            // Chi apre adesso. Il nome per
                                            // esteso, non l'identificativo del
                                            // .desktop: `Gwenview` dice
                                            // qualcosa, `org.kde.gwenview.desktop` no.
                                            Row {
                                                anchors.right: groupChevron.left
                                                anchors.rightMargin: Theme.Effects.space2
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 6

                                                Image {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 18; height: 18
                                                    source: group.modelData.defaultIcon
                                                            && group.modelData.defaultIcon !== ""
                                                            ? "file://" + group.modelData.defaultIcon : ""
                                                    fillMode: Image.PreserveAspectFit
                                                    asynchronous: true
                                                    visible: status === Image.Ready
                                                }

                                                // Un tetto alla larghezza: senza,
                                                // «GNU Image Manipulation Program»
                                                // si allungava verso sinistra fino
                                                // a scriversi SOPRA il nome del
                                                // gruppo. La metà della riga, meno
                                                // quello che serve al nome.
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: Math.min(implicitWidth,
                                                                    Math.max(60, rigaGruppo.width
                                                                             - groupName.x
                                                                             - groupName.implicitWidth
                                                                             - 170))
                                                    elide: Text.ElideRight
                                                    text: {
                                                        if (group.empty)
                                                            return page.it ? "niente di installato"
                                                                           : "nothing installed";
                                                        if (group.modelData.defaultApp === "")
                                                            return page.it ? "da scegliere" : "not set";
                                                        return group.modelData.defaultName;
                                                    }
                                                    color: group.modelData.defaultApp === ""
                                                           ? Theme.Colors.textFaint
                                                           : Theme.Colors.textMuted
                                                    font.family: Theme.Typography.fontDisplay
                                                    font.weight: Theme.Typography.weightRegular
                                                    font.pixelSize: Theme.Typography.sizeSM
                                                }

                                                // Un sistema vissuto ha quasi
                                                // sempre i tipi sparpagliati —
                                                // le foto a Gwenview tranne i
                                                // SVG finiti a Inkscape.
                                                // Mostrare solo il primo direbbe
                                                // una cosa falsa; dirlo permette
                                                // di sistemarlo con un clic.
                                                Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: (group.modelData.mixed === true
                                                              || group.modelData.mancante === true)
                                                             && !group.empty
                                                    width: mixedText.implicitWidth + 12
                                                    height: 18
                                                    radius: 9
                                                    color: group.modelData.mancante === true
                                                           ? Qt.alpha(Theme.Colors.danger, 0.16)
                                                           : Qt.alpha(Theme.Colors.accent, 0.16)

                                                    Text {
                                                        id: mixedText
                                                        anchors.centerIn: parent
                                                        text: group.modelData.mancante === true
                                                              ? (page.it ? "non installato" : "not installed")
                                                              : (page.it ? "non per tutti" : "not for all")
                                                        color: group.modelData.mancante === true
                                                               ? Theme.Colors.danger : Theme.Colors.accent
                                                        font.family: Theme.Typography.fontDisplay
                                                        font.weight: Theme.Typography.weightRegular
                                                        font.pixelSize: Theme.Typography.sizeXS
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: group.empty ? Qt.ArrowCursor
                                                                         : Qt.PointingHandCursor
                                                enabled: !group.empty
                                                onClicked: page.openId = group.open
                                                           ? "" : group.modelData.id
                                            }
                                        }

                                        // ── I candidati ──────────────────
                                        Column {
                                            width: parent.width
                                            visible: group.open
                                            spacing: 1

                                            Repeater {
                                                model: group.open ? group.modelData.candidates : []

                                                delegate: Rectangle {
                                                    id: cand
                                                    required property var modelData

                                                    readonly property bool chosen:
                                                        group.modelData.defaultApp === cand.modelData.id
                                                        && group.modelData.mixed !== true

                                                    width: parent.width
                                                    height: 34
                                                    radius: Theme.Effects.radiusXS
                                                    color: candMouse.containsMouse
                                                           ? Qt.alpha(Theme.Colors.accent, 0.14)
                                                           : (cand.chosen ? Theme.Colors.raisedHigh
                                                                          : "transparent")
                                                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                                                    Ui.Icon {
                                                        id: candMark
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: Theme.Effects.space3
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 13; height: 13
                                                        visible: cand.chosen
                                                        name: "check"
                                                        color: Theme.Colors.accent
                                                    }

                                                    Image {
                                                        id: candIcon
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: Theme.Effects.space3 + 20
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 18; height: 18
                                                        source: cand.modelData.iconPath
                                                                && cand.modelData.iconPath !== ""
                                                                ? "file://" + cand.modelData.iconPath : ""
                                                        fillMode: Image.PreserveAspectFit
                                                        asynchronous: true
                                                        visible: status === Image.Ready
                                                    }

                                                    Text {
                                                        anchors.left: candIcon.right
                                                        anchors.leftMargin: Theme.Effects.space2
                                                        anchors.right: candComando.left
                                                        anchors.rightMargin: Theme.Effects.space2
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        elide: Text.ElideRight
                                                        text: cand.modelData.name
                                                        color: cand.chosen ? Theme.Colors.text
                                                                           : Theme.Colors.textMuted
                                                        font.family: Theme.Typography.fontDisplay
                                                        font.weight: Theme.Typography.weightRegular
                                                        font.pixelSize: Theme.Typography.sizeSM
                                                    }

                                                    // Solo per il terminale: il
                                                    // comando vero. Due terminali
                                                    // possono chiamarsi quasi
                                                    // uguale, e quello che parte
                                                    // davvero è questo.
                                                    Text {
                                                        id: candComando
                                                        anchors.right: parent.right
                                                        anchors.rightMargin: Theme.Effects.space3
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        visible: group.modelData.tipo === "terminale"
                                                        text: visible ? cand.modelData.id : ""
                                                        color: Theme.Colors.textFaint
                                                        font.family: Theme.Typography.fontMono
                                                        font.pixelSize: Theme.Typography.sizeXS
                                                    }

                                                    MouseArea {
                                                        id: candMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        // Niente conferma e niente
                                                        // attesa: il demone
                                                        // risponde con l'elenco già
                                                        // aggiornato, e la riga
                                                        // cambia da sé.
                                                        onClicked: page.scegli(group.modelData,
                                                                               cand.modelData.id)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

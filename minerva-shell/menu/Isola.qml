import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// ── L'Isola ──────────────────────────────────────────────────────────────
//
// Giacomo, 24 settembre 2026: «Il meteo?». Nell'Isola: la capsula in mezzo
// alla barra, con l'ora, la data e il tempo che fa. Toccata, la capsula
// CRESCE — la stessa forma che si allarga con la molla, non un pannello che
// compare sotto — e racconta la giornata: che tempo fa adesso, le prossime
// dodici ore, l'alba e il tramonto, i giorni che vengono.
//
// Come il Centro, una finestra sola a tutto schermo che esiste solo mentre
// l'Isola è aperta: il fondo raccoglie i clic fuori. La carta nasce sopra la
// capsula della barra (`origine`, detta da chi la apre) e ci torna dentro
// quando si chiude.
PanelWindow {
    id: isola

    property bool aperto: false
    property bool mostrato: false
    /// Spazio da lasciare in alto (la barra) e in basso (la dock).
    property real margineAlto: 0
    property real margineBasso: 0
    /// La barra sta in basso: l'Isola cresce verso l'alto.
    property bool dalBasso: false
    /// Il rettangolo della capsula sulla barra, in coordinate dello schermo.
    property rect origine: Qt.rect(isola.width / 2 - 80, 6, 160, 32)

    /// Che faccia mostra la carta: «giorno» (il tempo della giornata) o
    /// «mese» (il calendario). Si riapre sempre sulla giornata.
    property string faccia: "giorno"
    /// Il primo del mese mostrato sulla faccia «mese».
    property date mese: new Date()

    function sfoglia(quanti) {
        var d = new Date(isola.mese.getFullYear(), isola.mese.getMonth() + quanti, 1);
        isola.mese = d;
    }
    /// Via subito, senza animazione: prima di una schermata.
    function sparisci() {
        isola.aperto = false;
        isola.mostrato = false;
        spegni.stop();
    }

    /// La carta sulla schermata: la apre il tasto Stamp.
    property int ritardoSchermata: 0
    function apriSchermata(dove) {
        if (dove !== undefined && dove !== null && dove.width > 0)
            isola.origine = dove;
        isola.apri();
        isola.faccia = "schermata";
    }

    /// La carta sulle notifiche: la apre la campanella dell'Isola.
    function apriNotifiche(dove) {
        if (dove !== undefined && dove !== null && dove.width > 0)
            isola.origine = dove;
        isola.apri();
        isola.faccia = "notifiche";
        Core.Notifications.markAllRead();
    }
    function giraSu(faccia) {
        isola.faccia = faccia;
        if (faccia === "mese")
            isola.mese = new Date(isola.oggi.getFullYear(), isola.oggi.getMonth(), 1);
    }
    /// Scegliere una località: lo fanno le Impostazioni.
    signal impostazioniChieste()
    /// Scattare una schermata: la scatta la shell, dopo che l'Isola se n'è
    /// andata (`sparisci`), o finirebbe dentro la fotografia.
    signal schermataChiesta(string modo, int ritardo)

    function apriDa(dove) {
        if (dove !== undefined && dove !== null && dove.width > 0)
            isola.origine = dove;
        isola.apri();
    }
    /// La stessa carta, girata sul calendario: la apre l'ora nell'Isola.
    function apriCalendario(dove) {
        isola.apriDa(dove);
        isola.giraSu("mese");
    }
    function apri() {
        if (isola.aperto) return;
        isola.oggi = new Date();
        isola.faccia = "giorno";
        isola.mostrato = true;
        isola.aperto = true;
        spegni.stop();
        Core.Meteo.aggiorna();
    }
    function chiudi() {
        if (!isola.aperto) return;
        isola.aperto = false;
        spegni.restart();
    }
    function commuta() { isola.aperto ? isola.chiudi() : isola.apri(); }

    /// Per le prove: che cosa si vede.
    function riassunto() {
        var o = isola.origine;
        var r = ["aperta: " + isola.aperto + " · faccia: " + isola.faccia
                 + (isola.faccia === "mese" ? " (" + isola.mese.toLocaleDateString(isola._locale, "MMMM yyyy") + ")" : ""),
                 "capsula: " + Math.round(o.x) + "," + Math.round(o.y) + " " + Math.round(o.width) + "x" + Math.round(o.height)];
        if (Core.Meteo.pronto) {
            var a = Core.Meteo.adesso;
            r.push("adesso: " + Core.Meteo.gradi(a.temperatura) + " "
                   + Core.Meteo.descrizione(a.codice) + " · " + Core.Meteo.luogo);
            r.push("ore: " + Core.Meteo.ore.map(function(o) {
                return o.ora + " " + Core.Meteo.gradi(o.temperatura);
            }).join(", "));
            if (Core.Meteo.giorni.length > 0)
                r.push("alba " + Core.Meteo.giorni[0].alba + " · tramonto " + Core.Meteo.giorni[0].tramonto);
        } else {
            r.push(Core.Meteo.attivo ? "meteo: in arrivo" : "meteo: nessuna località");
        }
        return r.join("\n");
    }

    property date oggi: new Date()
    readonly property var _locale: Core.Strings.lang === "it" ? Qt.locale("it_IT") : Qt.locale("en_GB")

    visible: isola.mostrato
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    WlrLayershell.namespace: "liquid-isola"
    WlrLayershell.layer: WlrLayer.Overlay
    // La tastiera subito, come il Centro (qml-fuoco-annulla-clic).
    WlrLayershell.keyboardFocus: isola.aperto ? WlrKeyboardFocus.Exclusive
                                              : WlrKeyboardFocus.None

    Timer { id: spegni; interval: Theme.Motion.liquido ? 600 : 0; onTriggered: if (!isola.aperto) isola.mostrato = false }

    MouseArea {
        id: fuoriIsola
        anchors.fill: parent
        enabled: isola.aperto
        onPressed: isola.chiudi()
    }

    // ── La capsula resta cliccabile ─────────────────────────────────────
    //
    // La carta copre tutto lo schermo per chiudersi al tocco fuori, e così
    // copriva anche la capsula da cui è uscita: toccare l'ora col meteo
    // aperto chiudeva invece di girare sul calendario. Il buco lascia
    // passare i tocchi alla capsula, che sa quale faccia chiedere.
    mask: Region {
        item: fuoriIsola
        Region {
            intersection: Intersection.Subtract
            x: isola.origine.x
            y: isola.origine.y
            width: isola.origine.width
            height: isola.origine.height
        }
    }
    Item {
        anchors.fill: parent
        focus: isola.aperto
        Keys.onEscapePressed: isola.chiudi()
        Keys.onLeftPressed: if (isola.faccia === "mese") isola.sfoglia(-1)
        Keys.onRightPressed: if (isola.faccia === "mese") isola.sfoglia(1)
    }

    // ── La carta ────────────────────────────────────────────────────────
    //
    // Chiusa ha la forma della capsula, aperta la sua. Tre molle — altezza,
    // larghezza, e il bordo verso la barra — e il raggio che segue l'altezza: la capsula è
    // tonda, la carta ha gli angoli del resto della riva.
    Rectangle {
        id: carta
        readonly property real larga: Math.min(560, isola.width - 2 * Theme.Effects.space4)
        readonly property real alta: corpo.implicitHeight + 2 * Theme.Effects.space4
        readonly property real finaleY: isola.dalBasso
            ? isola.height - isola.margineBasso - Theme.Effects.space2 - carta.alta
            : isola.margineAlto + Theme.Effects.space2

        // Il centro sta fermo sulla capsula e la carta cresce dai due lati
        // insieme. Con una molla anche sulla x, posizione e larghezza
        // arrivavano in tempi diversi e la carta scivolava di lato crescendo.
        // Solo se non ci sta, si sposta quanto basta per restare dentro.
        readonly property real centro: isola.origine.x + isola.origine.width / 2
        x: Math.max(Theme.Effects.space2,
                    Math.min(isola.width - Theme.Effects.space2 - width, carta.centro - width / 2))
        // Il bordo che si muove con la molla è quello verso la barra: con
        // la barra in basso è il bordo di SOTTO. Animando la y di sopra, con
        // la barra in basso la carta arrivava in cima prima di essere
        // cresciuta e si staccava dalla barra a metà corsa.
        property real bordo: isola.aperto
            ? (isola.dalBasso ? carta.finaleY + carta.alta : carta.finaleY)
            : (isola.dalBasso ? isola.origine.y + isola.origine.height : isola.origine.y)
        // Le molle solo a Isola visibile: da nascosta la carta deve SALTARE
        // sulla capsula. Prima la prima apertura partiva dal rettangolo di
        // fabbrica di `origine`, in cima allo schermo: con la barra in basso
        // la carta attraversava tutto lo schermo per arrivare alla capsula.
        readonly property bool _molle: Theme.Motion.liquido && isola.mostrato
        Behavior on bordo { enabled: carta._molle; SpringAnimation { spring: Theme.Motion.molla * 0.7; damping: 0.38 } }
        y: isola.dalBasso ? carta.bordo - height : carta.bordo
        width: isola.aperto ? carta.larga : isola.origine.width
        height: isola.aperto ? carta.alta : isola.origine.height
        radius: Math.min(height / 2, Theme.Effects.radiusLG)
        opacity: isola.aperto ? 1 : 0
        clip: true

        Behavior on width { enabled: carta._molle; SpringAnimation { spring: Theme.Motion.molla * 0.7; damping: 0.38 } }
        Behavior on height { enabled: carta._molle; SpringAnimation { spring: Theme.Motion.molla * 0.7; damping: 0.38 } }
        Behavior on opacity { NumberAnimation { duration: isola.aperto ? 90 : 420; easing.type: Easing.InQuad } }

        color: Qt.rgba(Theme.Colors.panel.r, Theme.Colors.panel.g, Theme.Colors.panel.b,
                       Math.max(Theme.Colors.panel.a, 0.98))
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge

        MouseArea { anchors.fill: parent; onClicked: {} }

        // Il contenuto è largo quanto la carta APERTA fin dall'inizio, e sta
        // in mezzo: mentre la carta cresce si scopre dal centro, invece di
        // ridisporsi a ogni fotogramma.
        Column {
            id: corpo
            x: carta.width / 2 - corpo.width / 2
            // Attaccato al lato della barra: con la barra in basso si scopre
            // dal fondo, cioè dalla capsula da cui la carta sta uscendo.
            y: isola.dalBasso ? carta.height - Theme.Effects.space4 - corpo.implicitHeight
                              : Theme.Effects.space4
            width: carta.larga - 2 * Theme.Effects.space4
            spacing: Theme.Effects.space4
            opacity: isola.aperto ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: isola.aperto ? 260 : 80 } }

            // La data, e il calendario.
            Item {
                width: parent.width
                height: 28
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (isola.faccia === "notifiche")
                            return "Notifiche";
                        if (isola.faccia === "schermata")
                            return "Schermata";
                        var s = isola.oggi.toLocaleDateString(isola._locale, "dddd d MMMM");
                        return s.charAt(0).toUpperCase() + s.slice(1);
                    }
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeLG
                    font.weight: Theme.Typography.weightMedium
                }
                Capsula {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    testo: isola.faccia === "giorno" ? "Calendario" : "Giornata"
                    onScelta: isola.giraSu(isola.faccia === "giorno" ? "mese" : "giorno")
                }
                Capsula {
                    id: svuotaNotifiche
                    visible: isola.faccia === "notifiche" && Core.Notifications.items.length > 0
                    anchors.right: parent.right
                    anchors.rightMargin: 96
                    anchors.verticalCenter: parent.verticalCenter
                    testo: "Svuota"
                    onScelta: Core.Notifications.clear()
                }
            }

            // ── Senza località: una domanda, non un buco ──
            Column {
                visible: !Core.Meteo.attivo && isola.faccia === "giorno"
                width: parent.width
                spacing: Theme.Effects.space2
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Il meteo non parte finché non scegli un posto: senza, non si chiede niente a nessuno."
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }
                Capsula {
                    testo: "Scegli la località"
                    onScelta: { isola.chiudi(); isola.impostazioniChieste(); }
                }
            }
            Text {
                visible: Core.Meteo.attivo && !Core.Meteo.pronto && isola.faccia === "giorno"
                text: "Il tempo sta arrivando…"
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            // ── Adesso ──
            Item {
                id: adesso
                visible: Core.Meteo.pronto && isola.faccia === "giorno"
                width: parent.width
                height: 76
                readonly property var a: Core.Meteo.adesso || ({})
                readonly property var g: Core.Meteo.giorni.length > 0 ? Core.Meteo.giorni[0] : ({})

                Ui.Icon {
                    id: grande
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 56; height: 56
                    name: Core.Meteo.icona(adesso.a.codice, adesso.a.giorno)
                    color: Theme.Colors.accent
                }
                Text {
                    id: gradi
                    anchors.left: grande.right
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    text: Core.Meteo.gradi(adesso.a.temperatura)
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeDisplay + 8
                    font.weight: Theme.Typography.weightMedium
                }
                Column {
                    anchors.left: gradi.right
                    anchors.leftMargin: Theme.Effects.space4
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: Core.Meteo.descrizione(adesso.a.codice)
                              + (Core.Meteo.vecchio ? " · non aggiornato" : "")
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeMD
                        font.weight: Theme.Typography.weightMedium
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: Core.Meteo.luogo + " · massima " + Core.Meteo.gradi(adesso.g.max)
                              + ", minima " + Core.Meteo.gradi(adesso.g.min)
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: "Percepita " + Core.Meteo.gradi(adesso.a.percepita)
                              + " · umidità " + Math.round(adesso.a.umidita || 0) + "%"
                              + " · vento " + Math.round(adesso.a.vento || 0) + " km/h"
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }
            }

            // ── Le prossime ore ──
            //
            // Una colonna per ora: l'ora, il simbolo, i gradi, e la pioggia
            // solo quando c'è — uno «0%» ripetuto dodici volte è rumore.
            Rectangle {
                visible: Core.Meteo.pronto && Core.Meteo.ore.length > 0 && isola.faccia === "giorno"
                width: parent.width
                height: 92
                radius: Theme.Effects.radiusMD
                color: Theme.Colors.raised

                Row {
                    id: fila
                    anchors.fill: parent
                    anchors.leftMargin: Theme.Effects.space2
                    anchors.rightMargin: Theme.Effects.space2
                    readonly property int quante: Math.min(13, Core.Meteo.ore.length)
                    Repeater {
                        model: Core.Meteo.ore.slice(0, fila.quante)
                        delegate: Column {
                            id: ora
                            required property var modelData
                            required property int index
                            width: fila.width / fila.quante
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: ora.index === 0 ? "Ora" : ora.modelData.ora.substring(0, 2)
                                color: ora.index === 0 ? Theme.Colors.accent : Theme.Colors.textMuted
                                font.family: Theme.Typography.fontMono
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                            Ui.Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 20; height: 20
                                name: Core.Meteo.icona(ora.modelData.codice, ora.modelData.giorno)
                                color: Theme.Colors.text
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Core.Meteo.gradi(ora.modelData.temperatura)
                                color: Theme.Colors.text
                                font.family: Theme.Typography.fontMono
                                font.pixelSize: Theme.Typography.sizeSM
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: (ora.modelData.pioggia || 0) >= 10
                                      ? Math.round(ora.modelData.pioggia) + "%" : " "
                                color: Theme.Colors.accent
                                font.family: Theme.Typography.fontMono
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                        }
                    }
                }
            }

            // ── L'alba e il tramonto ──
            Row {
                visible: Core.Meteo.pronto && adesso.g.alba !== undefined && adesso.g.alba !== null && isola.faccia === "giorno"
                spacing: Theme.Effects.space5
                Row {
                    spacing: Theme.Effects.space2
                    Ui.Icon { width: 16; height: 16; name: "sun"; color: Theme.Colors.textMuted; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Alba " + (adesso.g.alba || "")
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                }
                Row {
                    spacing: Theme.Effects.space2
                    Ui.Icon { width: 16; height: 16; name: "moon"; color: Theme.Colors.textMuted; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Tramonto " + (adesso.g.tramonto || "")
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                }
            }

            // ── I giorni che vengono ──
            Row {
                id: giorni
                visible: Core.Meteo.pronto && Core.Meteo.giorni.length > 1 && isola.faccia === "giorno"
                width: parent.width
                readonly property var prossimi: Core.Meteo.giorni.slice(1, 7)
                Repeater {
                    model: giorni.prossimi
                    delegate: Column {
                        id: giorno
                        required property var modelData
                        width: giorni.width / Math.max(1, giorni.prossimi.length)
                        spacing: 4
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: {
                                var d = new Date(giorno.modelData.data + "T12:00:00");
                                return d.toLocaleDateString(isola._locale, "ddd");
                            }
                            color: Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                        Ui.Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 18; height: 18
                            name: Core.Meteo.icona(giorno.modelData.codice, true)
                            color: Theme.Colors.text
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Core.Meteo.gradi(giorno.modelData.max) + " "
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontMono
                            font.pixelSize: Theme.Typography.sizeXS
                            Text {
                                anchors.left: parent.right
                                text: Core.Meteo.gradi(giorno.modelData.min)
                                color: Theme.Colors.textFaint
                                font: parent.font
                            }
                        }
                    }
                }
            }

            // ── La schermata ──
            //
            // Stamp non scatta: CHIEDE. Tutto lo schermo, una porzione, una
            // finestra; e fra quanto. Le stesse scelte del pannello di prima
            // (`spine/panels/ScreenshotPanel.qml`), dentro l'Isola.
            Column {
                id: schermata
                visible: isola.faccia === "schermata"
                width: parent.width
                spacing: Theme.Effects.space2

                Repeater {
                    model: [
                        { "id": "schermo",  "icona": "screen", "it": "Tutto lo schermo",  "nota": "Così com'è adesso" },
                        { "id": "area",     "icona": "crop",   "it": "Una porzione",      "nota": "La scegli trascinando col mouse" },
                        { "id": "finestra", "icona": "window", "it": "Solo una finestra", "nota": "Quella attiva, senza il resto della scrivania" }
                    ]
                    delegate: Rectangle {
                        id: scelta
                        required property var modelData
                        width: schermata.width
                        height: 52
                        radius: Theme.Effects.radiusMD
                        color: sceltaMouse.containsMouse ? Theme.Colors.hover : Theme.Colors.raised
                        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
                        Ui.Icon {
                            id: sceltaIcona
                            x: Theme.Effects.space3
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20
                            name: scelta.modelData.icona
                            color: Theme.Colors.text
                        }
                        Column {
                            anchors.left: sceltaIcona.right
                            anchors.leftMargin: Theme.Effects.space3
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: scelta.modelData.it
                                color: Theme.Colors.text
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                                font.weight: Theme.Typography.weightMedium
                            }
                            Text {
                                text: scelta.modelData.nota
                                color: Theme.Colors.textMuted
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                        }
                        MouseArea {
                            id: sceltaMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var ritardo = isola.ritardoSchermata;
                                isola.sparisci();
                                isola.schermataChiesta(scelta.modelData.id, ritardo);
                            }
                        }
                    }
                }

                Row {
                    spacing: Theme.Effects.space2
                    topPadding: Theme.Effects.space1
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Fra quanto"
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                        rightPadding: Theme.Effects.space2
                    }
                    Repeater {
                        model: [ { "v": 0, "it": "Subito" }, { "v": 3, "it": "3 s" }, { "v": 10, "it": "10 s" } ]
                        delegate: Capsula {
                            required property var modelData
                            testo: modelData.it
                            color: isola.ritardoSchermata === modelData.v ? Qt.alpha(Theme.Colors.accent, 0.28)
                                                                          : Theme.Colors.raised
                            onScelta: isola.ritardoSchermata = modelData.v
                        }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Si salva in Immagini › Schermate, e una copia va anche negli appunti."
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }

            // ── Le notifiche ──
            //
            // Dalla più recente. Un tocco apre quello di cui parla (l'azione
            // del programma, o il file); la crocetta la toglie.
            Column {
                id: notifiche
                visible: isola.faccia === "notifiche"
                width: parent.width
                spacing: Theme.Effects.space2
                readonly property var elenco: Core.Notifications.items.slice().reverse().slice(0, 8)

                Text {
                    visible: notifiche.elenco.length === 0
                    width: parent.width
                    topPadding: Theme.Effects.space3
                    bottomPadding: Theme.Effects.space3
                    horizontalAlignment: Text.AlignHCenter
                    text: Core.Notifications.doNotDisturb
                          ? "Niente notifiche. «Non disturbare» è acceso: arrivano senza farsi vedere."
                          : "Niente notifiche."
                    wrapMode: Text.WordWrap
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Repeater {
                    model: notifiche.elenco
                    delegate: Rectangle {
                        id: nota
                        required property var modelData
                        width: notifiche.width
                        height: testoNota.implicitHeight + 2 * Theme.Effects.space3
                        radius: Theme.Effects.radiusMD
                        color: notaMouse.containsMouse ? Theme.Colors.hover : Theme.Colors.raised
                        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                        Column {
                            id: testoNota
                            x: Theme.Effects.space3
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 2 * Theme.Effects.space3 - 28
                            spacing: 2
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: nota.modelData.appName + " · " + new Date(nota.modelData.time).toLocaleTimeString(isola._locale, "HH:mm")
                                color: nota.modelData.urgency === 2 ? Theme.Colors.danger : Theme.Colors.textMuted
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                            Text {
                                width: parent.width
                                visible: text !== ""
                                elide: Text.ElideRight
                                text: nota.modelData.summary || ""
                                color: Theme.Colors.text
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                                font.weight: Theme.Typography.weightMedium
                            }
                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: nota.modelData.body || ""
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                color: Theme.Colors.textMuted
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                        }
                        MouseArea {
                            id: notaMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: Core.Notifications.siPuoAprire(nota.modelData) ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                // Il dato si prende PRIMA di chiudere: chiudendo,
                                // questa voce può essere distrutta mentre il suo
                                // codice gira ancora (vedi widget/Widgets.qml).
                                var n = nota.modelData;
                                if (!Core.Notifications.siPuoAprire(n))
                                    return;
                                isola.chiudi();
                                Core.Notifications.apri(n);
                            }
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.Effects.space2
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24; radius: 12
                            color: viaMouse.containsMouse ? Qt.alpha(Theme.Colors.danger, 0.8) : "transparent"
                            opacity: notaMouse.containsMouse || viaMouse.containsMouse ? 1 : 0
                            Ui.Icon {
                                anchors.centerIn: parent
                                width: 11; height: 11
                                name: "close"
                                color: viaMouse.containsMouse ? Theme.Colors.textOnAccent : Theme.Colors.textMuted
                            }
                            MouseArea {
                                id: viaMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var tutte = Core.Notifications.items;
                                    for (var i = 0; i < tutte.length; i++)
                                        if (tutte[i].id === nota.modelData.id && tutte[i].time === nota.modelData.time) {
                                            Core.Notifications.remove(i);
                                            break;
                                        }
                                }
                            }
                        }
                    }
                }
                Text {
                    visible: Core.Notifications.items.length > notifiche.elenco.length
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "e altre " + (Core.Notifications.items.length - notifiche.elenco.length)
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }

            // ── Il mese ──
            //
            // Un mese alla volta, la settimana da lunedì. Niente appuntamenti:
            // non c'è un'agenda da cui prenderli, e un calendario che finge
            // di averla è peggio di uno che non ci prova. C'è invece il tempo:
            // sui giorni che hanno una previsione, sotto il numero, il suo
            // simbolo — «che tempo fa sabato?» è la domanda che si fa
            // guardando il calendario.
            Column {
                id: calendario
                visible: isola.faccia === "mese"
                width: parent.width
                spacing: Theme.Effects.space2

                readonly property int anno: isola.mese.getFullYear()
                readonly property int numero: isola.mese.getMonth()
                readonly property int vuote: (new Date(anno, numero, 1).getDay() + 6) % 7
                readonly property int quanti: new Date(anno, numero + 1, 0).getDate()
                readonly property bool questo: anno === isola.oggi.getFullYear()
                                               && numero === isola.oggi.getMonth()
                /// «2026-09-26» → il giorno di previsione.
                readonly property var previsti: {
                    var m = {};
                    var g = Core.Meteo.giorni || [];
                    for (var i = 0; i < g.length; i++)
                        m[g[i].data] = g[i];
                    return m;
                }
                function chiave(giorno) {
                    function due(n) { return n < 10 ? "0" + n : "" + n; }
                    return calendario.anno + "-" + due(calendario.numero + 1) + "-" + due(giorno);
                }

                Item {
                    width: parent.width
                    height: 32
                    Freccia {
                        id: prima
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        verso: -1
                        onScelta: isola.sfoglia(-1)
                    }
                    Text {
                        anchors.left: prima.right
                        anchors.leftMargin: Theme.Effects.space2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 180
                        horizontalAlignment: Text.AlignHCenter
                        text: {
                            var s = isola.mese.toLocaleDateString(isola._locale, "MMMM yyyy");
                            return s.charAt(0).toUpperCase() + s.slice(1);
                        }
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeMD
                        font.weight: Theme.Typography.weightMedium
                    }
                    Freccia {
                        anchors.left: prima.right
                        anchors.leftMargin: Theme.Effects.space2 * 2 + 180
                        anchors.verticalCenter: parent.verticalCenter
                        verso: 1
                        onScelta: isola.sfoglia(1)
                    }
                    Capsula {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !calendario.questo
                        testo: "Torna a oggi"
                        onScelta: isola.giraSu("mese")
                    }
                }

                Row {
                    Repeater {
                        model: ["L", "M", "M", "G", "V", "S", "D"]
                        delegate: Text {
                            id: sett
                            required property string modelData
                            required property int index
                            width: calendario.width / 7
                            horizontalAlignment: Text.AlignHCenter
                            text: sett.modelData
                            color: sett.index >= 5 ? Theme.Colors.accent : Theme.Colors.textFaint
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                            font.weight: Theme.Typography.weightMedium
                        }
                    }
                }

                Grid {
                    columns: 7
                    Repeater {
                        // Sempre sei righe: un mese che ne vuole cinque non
                        // deve far saltare l'altezza della carta sfogliando.
                        model: 42
                        delegate: Item {
                            id: casella
                            required property int index
                            readonly property int giorno: casella.index - calendario.vuote + 1
                            readonly property bool vero: casella.giorno >= 1 && casella.giorno <= calendario.quanti
                            readonly property bool oggi: casella.vero && calendario.questo
                                                        && casella.giorno === isola.oggi.getDate()
                            readonly property var tempo: casella.vero ? calendario.previsti[calendario.chiave(casella.giorno)] : undefined
                            width: calendario.width / 7
                            height: 46

                            Rectangle {
                                anchors.centerIn: parent
                                width: 44; height: 44
                                radius: 22
                                visible: casella.oggi
                                color: Theme.Colors.accent
                            }
                            Column {
                                anchors.centerIn: parent
                                spacing: 1
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: casella.vero ? casella.giorno : ""
                                    color: casella.oggi ? Theme.Colors.textOnAccent
                                         : (casella.index % 7) >= 5 ? Theme.Colors.textMuted
                                         : Theme.Colors.text
                                    font.family: Theme.Typography.fontMono
                                    font.pixelSize: Theme.Typography.sizeSM
                                    font.weight: casella.oggi ? Theme.Typography.weightMedium
                                                              : Theme.Typography.weightRegular
                                }
                                Ui.Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 15; height: 15
                                    visible: casella.tempo !== undefined
                                    name: casella.tempo ? Core.Meteo.icona(casella.tempo.codice, true) : "nuvole"
                                    color: casella.oggi ? Theme.Colors.textOnAccent : Theme.Colors.textMuted
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Un bottone a capsula ─────────────────────────────────────────────
    component Capsula: Rectangle {
        id: cap
        property string testo: ""
        signal scelta()
        height: 28
        width: capTesto.implicitWidth + 2 * Theme.Effects.space3
        radius: height / 2
        color: capMouse.containsMouse ? Theme.Colors.hover : Theme.Colors.raised
        Text {
            id: capTesto
            anchors.centerIn: parent
            text: cap.testo
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
            font.weight: Theme.Typography.weightMedium
        }
        MouseArea {
            id: capMouse
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cap.scelta()
        }
    }

    // ── Una freccia per sfogliare ────────────────────────────────────────
    component Freccia: Rectangle {
        id: fr
        property int verso: 1
        signal scelta()
        width: 32; height: 32; radius: 16
        color: frMouse.containsMouse ? Theme.Colors.hover : "transparent"
        Ui.Icon {
            anchors.centerIn: parent
            width: 22; height: 22
            // `chevron` punta in giù: girato di un quarto a destra punta a
            // sinistra. «prev» e «next» sono i tasti del lettore (|◀ ▶|).
            name: "chevron"
            rotation: fr.verso < 0 ? 90 : -90
            color: Theme.Colors.text
        }
        MouseArea {
            id: frMouse
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onClicked: fr.scelta()
        }
    }
}

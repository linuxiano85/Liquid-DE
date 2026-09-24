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

    /// Il calendario: lo apre la barra, che ha il pannello.
    signal calendarioChiesto()
    /// Scegliere una località: lo fanno le Impostazioni.
    signal impostazioniChieste()

    function apriDa(dove) {
        if (dove !== undefined && dove !== null && dove.width > 0)
            isola.origine = dove;
        isola.apri();
    }
    function apri() {
        if (isola.aperto) return;
        isola.oggi = new Date();
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
        var r = ["aperta: " + isola.aperto,
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
        anchors.fill: parent
        enabled: isola.aperto
        onPressed: isola.chiudi()
    }
    Item {
        anchors.fill: parent
        focus: isola.aperto
        Keys.onEscapePressed: isola.chiudi()
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
                    testo: "Calendario"
                    onScelta: { isola.chiudi(); isola.calendarioChiesto(); }
                }
            }

            // ── Senza località: una domanda, non un buco ──
            Column {
                visible: !Core.Meteo.attivo
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
                visible: Core.Meteo.attivo && !Core.Meteo.pronto
                text: "Il tempo sta arrivando…"
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            // ── Adesso ──
            Item {
                id: adesso
                visible: Core.Meteo.pronto
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
                visible: Core.Meteo.pronto && Core.Meteo.ore.length > 0
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
                visible: Core.Meteo.pronto && adesso.g.alba !== undefined && adesso.g.alba !== null
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
                visible: Core.Meteo.pronto && Core.Meteo.giorni.length > 1
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
}

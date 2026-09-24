import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui
import "../spine" as Spine

// ── L'Isola, al posto della barra ────────────────────────────────────────
//
// La Riva: «l'Isola al posto della barra: ora, segni di stato, trascinabile
// in alto o in basso; si allarga sulle notifiche e sulla musica». Una
// capsula che galleggia in mezzo, e ai lati niente: il menù sta nell'angolo
// (e su Super), le stanze sul bordo sinistro, gli appunti sul destro, lo
// spegnimento nel Centro.
//
// Dentro, da sinistra: l'ora e il tempo (toccati, la capsula cresce nella
// giornata: `Isola.qml`), la musica quando suona, i programmi del vassoio, i
// segni di stato (toccati, il Centro) e la campanella (toccata, la carta
// dell'Isola sulle notifiche).
//
// Quando arriva una notifica la capsula si allarga e la racconta per qualche
// secondo; toccandola si apre quello di cui parla.
//
// Riserva la stessa fascia della barra di prima (`Theme.Effects.barHeight`):
// le finestre, il menù e il Centro si mettono dove si mettevano.
PanelWindow {
    id: isolaBarra

    property bool inBasso: false

    /// Toccata l'ora: l'Isola cresce da qui (rettangolo in coordinate dello
    /// schermo).
    signal giornataChiesta(rect dove)
    signal notificheChieste(rect dove)
    signal centroChiesto()
    /// Trascinata dall'altra parte dello schermo.
    signal spostaChiesto(bool inBasso)

    // ── A scomparsa ──────────────────────────────────────────────────────
    //
    // Giacomo, 25 settembre 2026: «l'isola alta centrale la vorrei a
    // scomparsa, e passando sulla parte alta deve ricomparire, così
    // recuperiamo spazio». Di serie sta nascosta oltre il bordo e non
    // riserva la fascia: le finestre arrivano fino in cima. Scende con una
    // sosta del puntatore sul bordo (l'evento `bordo` «alto» del
    // compositore, `svela()`), resta finché il puntatore ci sta sopra, e
    // risale un attimo dopo che se n'è andato.
    //
    // ── La riva riservata ────────────────────────────────────────────────
    //
    // Con una finestra che riempie lo schermo il compositore non annuncia il
    // bordo se non con Super giù; e tenendo Super (`consenso`) l'Isola sale
    // anche sopra lo schermo intero — per questo, finché dura, sta sul piano
    // più alto.
    /// `bar.aScomparsa`: nascosta finché non la si chiama.
    property bool aScomparsa: true
    /// Una finestra ingrandita o a schermo intero: niente la fa comparire da
    /// sola (le notifiche comprese).
    property bool riservata: false
    /// Super tenuto con la riva riservata: sale, sopra a tutto.
    property bool consenso: false
    /// Qualcosa la tiene su: la sua carta aperta, per esempio.
    property bool tenuta: false

    property bool svelata: false
    readonly property bool su: !isolaBarra.aScomparsa || isolaBarra.svelata
                               || isolaBarra.consenso || isolaBarra.tenuta
                               || (isolaBarra.arrivata !== null && !isolaBarra.riservata)
    function svela() {
        isolaBarra.svelata = true;
        cala.restart();
    }
    Timer {
        id: cala
        interval: 1400
        onTriggered: {
            if (sopra.hovered || trascina.pressed)
                cala.restart();
            else
                isolaBarra.svelata = false;
        }
    }
    // Finito il consenso (Super lasciato) resta su finché ci si sta sopra.
    onConsensoChanged: if (!isolaBarra.consenso) isolaBarra.svela()
    onTenutaChanged: if (!isolaBarra.tenuta) isolaBarra.svela()

    anchors { top: !isolaBarra.inBasso; bottom: isolaBarra.inBasso; left: true; right: true }
    implicitHeight: Theme.Effects.barHeight
    exclusiveZone: isolaBarra.aScomparsa ? 0 : Theme.Effects.barHeight
    color: "transparent"
    WlrLayershell.namespace: "liquid-isola-barra"
    WlrLayershell.layer: isolaBarra.consenso ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Solo la capsula prende il puntatore, e solo quando c'è: nascosta, il
    // bordo è delle finestre.
    mask: Region { item: isolaBarra.su ? capsula : null }

    // ── La notifica che arriva ───────────────────────────────────────────
    property var arrivata: null
    Connections {
        target: Core.Notifications
        function onArrived(item) {
            isolaBarra.arrivata = item;
            racconta.interval = item && item.urgency === 2 ? 10000 : 5000;
            racconta.restart();
        }
    }
    Timer { id: racconta; onTriggered: isolaBarra.arrivata = null }

    function _rettangolo(voce) {
        var p = voce.mapToItem(null, 0, 0);
        var sotto = isolaBarra.inBasso && isolaBarra.screen
                    ? isolaBarra.screen.height - isolaBarra.height : 0;
        return Qt.rect(p.x, p.y + sotto, voce.width, voce.height);
    }

    /// Il rettangolo della capsula, in coordinate dello schermo.
    function rettangoloCapsula() { return isolaBarra._rettangolo(capsula); }

    /// Fine di un trascinamento di `dy` pixel: un quarto di schermo verso
    /// l'altro bordo sposta l'Isola di là.
    function trascinata(dy) {
        var soglia = isolaBarra.screen ? isolaBarra.screen.height / 4 : 200;
        if (!isolaBarra.inBasso && dy > soglia)
            isolaBarra.spostaChiesto(true);
        else if (isolaBarra.inBasso && dy < -soglia)
            isolaBarra.spostaChiesto(false);
    }

    /// Per le prove: che cosa mostra.
    function riassunto() {
        var r = [];
        r.push("isola " + (isolaBarra.inBasso ? "in basso" : "in alto")
               + " · " + (isolaBarra.su ? "su" : "nascosta")
               + " · larga " + Math.round(capsula.width));
        if (isolaBarra.arrivata)
            r.push("notifica: " + isolaBarra.arrivata.appName + " — " + isolaBarra.arrivata.summary);
        if (musica.visible)
            r.push("musica: " + Core.Media.titolo);
        r.push("da leggere: " + Core.Notifications.unread);
        return r.join("\n");
    }

    Rectangle {
        id: capsula
        readonly property real alta: Theme.Effects.barHeight - 8
        height: capsula.alta
        // Su: in mezzo alla fascia. Nascosta: oltre il bordo, con la molla.
        y: {
            var dentro = (isolaBarra.height - capsula.alta) / 2;
            var fuori = isolaBarra.inBasso ? isolaBarra.height + 10 : -capsula.alta - 10;
            return isolaBarra.su ? dentro : fuori;
        }
        Behavior on y {
            enabled: Theme.Motion.liquido
            SpringAnimation { spring: Theme.Motion.molla * 0.8; damping: 0.4 }
        }
        HoverHandler {
            id: sopra
            onHoveredChanged: if (!hovered) cala.restart()
        }
        x: (isolaBarra.width - width) / 2
        width: riga.implicitWidth + 2 * Theme.Effects.space2
        radius: height / 2
        color: Qt.rgba(Theme.Colors.panel.r, Theme.Colors.panel.g, Theme.Colors.panel.b,
                       Math.max(Theme.Colors.panel.a, 0.96))
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge
        clip: true

        // Si allarga e si stringe con la molla: è la stessa capsula che
        // cambia forma, non pezzi che compaiono.
        Behavior on width {
            enabled: Theme.Motion.liquido
            SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
        }

        // Trascinarla dall'altra parte dello schermo: da qui (gli spazi fra i
        // pulsanti) e da ogni `Voce`, che distingue il tocco dal trascinamento.
        MouseArea {
            id: trascina
            anchors.fill: parent
            property real inizio: 0
            property real scarto: 0
            preventStealing: true
            cursorShape: pressed && Math.abs(scarto) > 20 ? Qt.ClosedHandCursor : Qt.ArrowCursor
            onPressed: function(m) { inizio = m.y; scarto = 0; }
            onPositionChanged: function(m) { scarto = m.y - inizio; }
            onReleased: { isolaBarra.trascinata(trascina.scarto); trascina.scarto = 0; }
        }

        Row {
            id: riga
            x: Theme.Effects.space2
            height: parent.height
            spacing: Theme.Effects.space1

            // ── La notifica che arriva: prende il posto di tutto ──
            Voce {
                id: avviso
                onTrascinata: function(dy) { isolaBarra.trascinata(dy); }
                visible: isolaBarra.arrivata !== null
                onScelta: {
                    var a = isolaBarra.arrivata;
                    isolaBarra.arrivata = null;
                    if (a && Core.Notifications.siPuoAprire(a))
                        Core.Notifications.apri(a);
                    else
                        isolaBarra.notificheChieste(isolaBarra._rettangolo(capsula));
                }
                Row {
                    spacing: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    Ui.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16; height: 16
                        name: "bell"
                        color: Theme.Colors.accent
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 420)
                        elide: Text.ElideRight
                        text: isolaBarra.arrivata
                              ? (isolaBarra.arrivata.appName + " · " + (isolaBarra.arrivata.summary || isolaBarra.arrivata.body))
                              : ""
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                        font.weight: Theme.Typography.weightMedium
                    }
                }
            }

            // ── L'ora, la data, il tempo ──
            Voce {
                id: giornata
                onTrascinata: function(dy) { isolaBarra.trascinata(dy); }
                visible: !avviso.visible
                onScelta: isolaBarra.giornataChiesta(isolaBarra._rettangolo(capsula))
                Row {
                    spacing: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    Spine.ClockCluster {
                        anchors.verticalCenter: parent.verticalCenter
                        dimmed: false
                        // Senza la data, se la si è tolta (Impostazioni › La Riva).
                        compatto: !Core.Riva.isolaData
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Core.Riva.isolaMeteo && Core.Meteo.attivo && Core.Meteo.pronto
                        spacing: Theme.Effects.space1
                        Ui.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 18
                            name: Core.Meteo.pronto
                                  ? Core.Meteo.icona(Core.Meteo.adesso.codice, Core.Meteo.adesso.giorno)
                                  : "nuvole"
                            color: Theme.Colors.textMuted
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Core.Meteo.pronto ? Core.Meteo.gradi(Core.Meteo.adesso.temperatura) : ""
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontMono
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                    }
                }
            }

            // ── La musica, quando suona ──
            Voce {
                id: musica
                onTrascinata: function(dy) { isolaBarra.trascinata(dy); }
                visible: !avviso.visible && Core.Riva.isolaMusica
                         && Core.Media.cQualcosa && Core.Media.inRiproduzione
                onScelta: isolaBarra.centroChiesto()
                Row {
                    spacing: Theme.Effects.space2
                    anchors.verticalCenter: parent.verticalCenter
                    // Tre barrette che respirano: dice «sta suonando» senza
                    // parole. Si muovono solo mentre suona.
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                id: barretta
                                required property int index
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3; radius: 1.5
                                color: Theme.Colors.accent
                                height: 6
                                SequentialAnimation on height {
                                    running: musica.visible && Theme.Motion.liquido
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 14 - barretta.index * 3; duration: 380 + barretta.index * 90; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 5; duration: 420 + barretta.index * 70; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 200)
                        elide: Text.ElideRight
                        text: Core.Media.titolo
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                }
            }

            // ── I programmi del vassoio ──
            Spine.Vassoio {
                anchors.verticalCenter: parent.verticalCenter
                visible: !avviso.visible && Core.Riva.isolaVassoio
            }

            // ── I segni di stato: il Centro ──
            Spine.StatusCluster {
                anchors.verticalCenter: parent.verticalCenter
                visible: !avviso.visible && Core.Riva.isolaStato
                onClicked: isolaBarra.centroChiesto()
            }

            // ── La campanella ──
            Voce {
                id: campana
                onTrascinata: function(dy) { isolaBarra.trascinata(dy); }
                visible: !avviso.visible
                onScelta: isolaBarra.notificheChieste(isolaBarra._rettangolo(capsula))
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18
                    Ui.Icon {
                        anchors.fill: parent
                        name: "bell"
                        color: Core.Notifications.unread > 0 ? Theme.Colors.text : Theme.Colors.textMuted
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: -1
                        anchors.topMargin: -1
                        width: 7; height: 7
                        radius: 3.5
                        color: Theme.Colors.accentWarm
                        visible: Core.Notifications.unread > 0
                    }
                }
            }
        }
    }

    // ── Una parte della capsula che si tocca ────────────────────────────
    component Voce: Item {
        id: voce
        default property alias contenuto: dentro.data
        signal scelta()
        /// Premuta e portata via di `dy` pixel: non è un tocco.
        signal trascinata(real dy)
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        // Un componente in linea non vede gli id del file: l'altezza si
        // ricava dal tema, come la capsula.
        height: Theme.Effects.barHeight - 14
        width: dentro.childrenRect.width + 2 * Theme.Effects.space3
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: voceMouse.pressed ? Theme.Colors.pressed
                 : voceMouse.containsMouse ? Theme.Colors.hover : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
        }
        Item {
            id: dentro
            x: Theme.Effects.space3
            height: parent.height
            width: childrenRect.width
        }
        MouseArea {
            id: voceMouse
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            property real _inizio: 0
            onPressed: function(m) { voceMouse._inizio = m.y; }
            onReleased: function(m) {
                if (Math.abs(m.y - voceMouse._inizio) > 40)
                    voce.trascinata(m.y - voceMouse._inizio);
            }
            onClicked: voce.scelta()
        }
    }
}

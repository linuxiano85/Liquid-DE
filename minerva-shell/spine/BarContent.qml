import QtQuick
import Quickshell
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// BarContent — La disposizione della barra.
//
// Tre zone, con una regola per ciascuna:
//
//  SINISTRA — dove si AGISCE. Il pulsante Minerva e le scrivanie: le due cose
//            che si toccano più spesso, nell'angolo più facile da colpire
//            (il puntatore ci si ferma da solo contro lo spigolo).
//
//  CENTRO   — dove si LEGGE. Orario e finestra attiva. Non si clicca: se il
//            centro fosse cliccabile, ogni clic a vuoto sulla barra farebbe
//            succedere qualcosa.
//
//  DESTRA   — dove si CONTROLLA. Stato del sistema e pannelli di controllo.
//
// La separazione non è estetica: rende prevedibile dove cercare una cosa
// senza doverla leggere.
Item {
    id: bar

    required property var spine

    /// Numero di notifiche non lette, impostato dalla shell.
    property int unreadCount: 0

    signal cheatsheetRequested()

    // ── Ancoraggio delle lingue ──────────────────────────────────────────
    //
    // La lingua di ciascun pannello scende da sotto il proprio pulsante. Le
    // posizioni si ricalcolano in blocco e MAI con `onXChanged` sul singolo
    // pulsante: dentro una Row ancorata a destra il primo figlio ha x = 0 e
    // non cambia mai: è la Row a spostarsi. Quel segnale non arriverebbe e i
    // pannelli resterebbero incollati al bordo sinistro dello schermo.
    function syncAnchors() {
        if (!bar.spine)
            return;
        function put(name, item) {
            var left = item.mapToItem(bar, 0, 0).x;
            bar.spine.registerAnchor(name, left, left + item.width);
        }
        put("minimized",     minimizedButton);
        put("calendar",      clockButton);
        put("meteo",         clockButton);
        put("clipboard",     clipButton);
        put("notifications", bellButton);
        put("power",         powerButton);
    }

    onWidthChanged: syncAnchors()
    Component.onCompleted: Qt.callLater(syncAnchors)

    // ── Zona sinistra ────────────────────────────────────────────────────
    Row {
        id: leftZone
        anchors.left: parent.left
        anchors.leftMargin: Theme.Effects.space2
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.Effects.space2
        onWidthChanged: bar.syncAnchors()

        // Pulsante Minerva: il punto di partenza per chi non sa nulla.
        Ui.SpineButton {
            id: launcherButton
            anchors.verticalCenter: parent.verticalCenter
            // ── Un'impostazione che esisteva e non faceva niente ─────────
            //
            // `bar.showAppMenuButton` stava nei valori di fabbrica dal primo
            // giorno e la sua UNICA occorrenza in tutto il progetto era la
            // riga che la dichiarava. Si poteva scrivere, e il pulsante
            // restava lì: il tipo di bugia che nessun errore segnala, e che
            // questo file condanna per iscritto a proposito di
            // `bar.position`.
            visible: Core.Ipc.get("bar.showAppMenuButton", true) === true
            tooltip: Core.Strings.t("apps")
            horizontalPadding: Theme.Effects.space2
            onClicked: bar.spine.menuAppChiesto()

            content: MinervaMark {
                width: 20
                height: 20
                lit: launcherButton.active || launcherButton.hovered
            }
        }

        Workspaces {
            anchors.verticalCenter: parent.verticalCenter
        }

        // ── Le finestre aperte, per chi non ha la dock ───────────────────
        //
        // Spenta di suo: con la dock accesa sarebbe la stessa cosa detta due
        // volte. La accende lo stile «Windows».
        ListaFinestre {
            anchors.verticalCenter: parent.verticalCenter
            accesa: Core.Ipc.get("bar.listaFinestre", false) === true
            // Lo spazio che può prendersi: da dove finisce quello che sta
            // alla sua sinistra fino a metà barra, che è dove comincia
            // l'orologio. Non oltre: il centro è dove si LEGGE, e una fila di
            // pulsanti che ci arriva sotto lo rende illeggibile.
            spazio: Math.max(120, bar.width / 2 - x - Theme.Effects.space6)
        }

        // Pescatore delle finestre ridotte a icona. Compare solo quando ce
        // n'è almeno una: un pulsante che non fa mai niente occupa spazio e
        // insegna a ignorare quella zona della barra.
        Ui.SpineButton {
            id: minimizedButton
            anchors.verticalCenter: parent.verticalCenter
            visible: Core.Windows.minimized.length > 0
            active: bar.spine.activePanel === "minimized"
            tooltip: Core.Strings.lang === "it" ? "Finestre ridotte a icona"
                                                : "Minimised windows"
            onClicked: bar.spine.toggle("minimized")

            content: Row {
                spacing: Theme.Effects.space1
                Ui.Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 17; height: 17
                    name: "restore"
                    color: minimizedButton.active ? Theme.Colors.accent
                                                  : Theme.Colors.textMuted
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Core.Windows.minimized.length
                    color: minimizedButton.active ? Theme.Colors.accent
                                                  : Theme.Colors.textMuted
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeSM
                }
            }
        }

        WindowChip {
            id: windowChip
            anchors.verticalCenter: parent.verticalCenter
            spine: bar.spine
            onMenuRequested: function(where) { bar.windowMenuRequested(where); }
        }
    }

    /// Il tasto destro sul nome della finestra chiede il menu alla shell.
    signal windowMenuRequested(point where)

    // ── Zona centrale ────────────────────────────────────────────────────
    //
    // L'orologio è l'unica cosa cliccabile al centro, e apre il calendario.
    // È dove chiunque cerca di cliccare per sapere che giorno è il 14.
    Item {
        id: centreZone
        anchors.verticalCenter: parent.verticalCenter
        // ── Centrato finché ci sta, poi SCIVOLA ──────────────────────────
        //
        // Qui c'era `anchors.horizontalCenter`, cioè in mezzo allo SCHERMO
        // sempre, con la sola difesa di una larghezza che si restringeva. Non
        // bastava per due ragioni insieme: restringere il riquadro non
        // restringe la `Row` che ci sta dentro (quella conserva la sua
        // larghezza e straborda), e comunque un oggetto centrato sullo
        // schermo, se la zona destra passa la metà, non ci sta e basta.
        //
        // Visto il 9 settembre 2026 mettendo tre valori di sistema nella zona
        // destra: «mer 9 set» stampato sopra «94 %». Il difetto però non è
        // dei widget — sarebbe uscito uguale con un nome di località lungo nel
        // meteo, o con l'elenco delle finestre acceso.
        //
        // Adesso fa quello che fanno tutte le barre: sta in mezzo finché in
        // mezzo ci sta, e quando non ci sta più si sposta invece di
        // sovrapporsi. Restare centrato «per principio» sopra un altro
        // pulsante non è simmetria: è un difetto simmetrico.
        readonly property real disponibile:
            bar.width - leftZone.width - rightZone.width - Theme.Effects.space6

        width: Math.max(0, Math.min(clockButton.implicitWidth,
                                    centreZone.disponibile))
        height: parent.height

        x: Math.max(leftZone.width + Theme.Effects.space3,
             Math.min(bar.width - rightZone.width - centreZone.width
                        - Theme.Effects.space3,
                      (bar.width - centreZone.width) / 2))
        onWidthChanged: bar.syncAnchors()
        onXChanged: bar.syncAnchors()

        // ── L'Isola ──────────────────────────────────────────────────
        //
        // L'ora, la data e il tempo che fa, in una capsula sola: toccata,
        // cresce nella giornata intera (`menu/Isola.qml`). Il calendario è
        // lì dentro, a un tocco. Il meteo non c'è finché non si sceglie una
        // località: chi non lo vuole non vede nemmeno il posto dove starebbe.
        Ui.SpineButton {
            id: clockButton
            anchors.centerIn: parent
            active: bar.spine.activePanel === "calendar"
            tooltip: Core.Meteo.pronto
                     ? Core.Meteo.descrizione(Core.Meteo.adesso.codice) + " · " + Core.Meteo.luogo
                     : (Core.Strings.lang === "it" ? "Oggi" : "Today")
            horizontalPadding: Theme.Effects.space3
            onClicked: {
                var w = clockButton.Window.window;
                var p = clockButton.mapToItem(null, 0, 0);
                // Coordinate della finestra della barra → dello schermo: la
                // barra in basso ha la finestra in fondo allo schermo.
                var sotto = w ? clockButton.Screen.height - w.height : 0;
                bar.spine.isolaChiesta(Qt.rect(p.x, p.y + (bar.spine.inBasso ? sotto : 0),
                                               clockButton.width, clockButton.height));
            }

            content: Row {
                spacing: Theme.Effects.space2

                ClockCluster {
                    id: clockCluster
                    anchors.verticalCenter: parent.verticalCenter
                    dimmed: clockButton.active || clockButton.hovered
                    // Senza spazio per tutto, resta l'ora e se ne va la data.
                    // Il perché per esteso sta in `ClockCluster.qml`.
                    compatto: centreZone.disponibile
                              < clockCluster.larghezzaPiena + tempo.width + Theme.Effects.space2
                                + clockButton.horizontalPadding * 2
                }

                Row {
                    id: tempo
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Core.Meteo.attivo && Core.Meteo.pronto
                    width: visible ? implicitWidth : 0
                    spacing: Theme.Effects.space1

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1; height: 14
                        color: Theme.Colors.edge
                    }
                    Item { width: Theme.Effects.space1; height: 1 }
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
    }

    // ── Zona destra ──────────────────────────────────────────────────────
    Row {
        id: rightZone
        anchors.right: parent.right
        anchors.rightMargin: Theme.Effects.space2
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.Effects.space1
        onWidthChanged: bar.syncAnchors()

        // ── I valori di sistema ──────────────────────────────────────
        //
        // Gli stessi della scrivania, scelti in Impostazioni → Scrivania.
        // Primi della zona destra, cioè il più lontano possibile dal tasto
        // di spegnimento: sono la cosa che si guarda, e quello è la cosa che
        // non si vuole sfiorare.
        WidgetBarra {
            anchors.verticalCenter: parent.verticalCenter
            spine: bar.spine
        }

        // ── Il cartello del demone muto ──────────────────────────────
        //
        // 31 agosto 2026. Giacomo: «sia qui che nella sessione wlroot non ho
        // la dock e nemmeno le voci nel menu delle applicazioni».
        //
        // Il demone era caduto e la shell non era più riuscita a ritrovarlo.
        // Da fuori non si vedeva NIENTE: nessun errore, nessun avviso — solo
        // una scrivania senza dock, con la barra al suo posto e i tasti che
        // rispondevano. Sembrava un difetto del disegno, e infatti si è
        // andati a cercarlo lì.
        //
        // Le due cause sono riparate. Questo cartello serve al giorno in cui
        // si romperà un'altra cosa: **un guasto che non si annuncia si
        // scambia per un difetto di ciò che si vede**, e manda a cercare nel
        // posto sbagliato. Costa un rettangolo e dice la verità.
        //
        // Dopo tre secondi e non subito: fra la partenza della shell e quella
        // del demone c'è quasi sempre un attimo in cui non si parlano ancora,
        // e un cartello che compare a ogni accesso è un cartello che si
        // impara a non leggere.
        Rectangle {
            id: cartelloDemone
            visible: !Core.Ipc.connected && attesa.scaduta
            anchors.verticalCenter: parent.verticalCenter
            width: testoDemone.implicitWidth + Theme.Effects.space2 * 2
            height: testoDemone.implicitHeight + Theme.Effects.space1
            radius: height / 2
            color: Theme.Colors.warning
            opacity: 0.9

            Text {
                id: testoDemone
                anchors.centerIn: parent
                text: "demone assente · riprovo"
                // Il colore d'avviso è un ambra chiaro sul tema scuro: sopra
                // ci va testo scuro, non bianco. Si sceglie in base alla
                // luminosità del fondo invece che a occhio, così vale anche
                // sul tema chiaro, dove l'ambra diventa scuro.
                color: cartelloDemone.color.hslLightness > 0.55
                       ? "#1a1a1a" : "#ffffff"
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
                font.weight: Theme.Typography.weightMedium
            }

            QtObject {
                id: attesa
                property bool scaduta: false
            }

            Timer {
                interval: 3000
                repeat: false
                running: !Core.Ipc.connected
                onTriggered: attesa.scaduta = true
                onRunningChanged: if (!running) attesa.scaduta = false
            }
        }

        // ── Ricarica la scrivania ────────────────────────────────────
        //
        // Giacomo, 2 settembre 2026: «mettiamo un tasto disattivabile accanto
        // al meteo dove posso riavviare la shell».
        //
        // ── Ricarica, non riavvia, e la differenza si vede ───────────────
        //
        // `Quickshell.reload(false)` rilegge i QML **restando vivo**: la barra
        // non sparisce, i pannelli aperti si richiudono e tornano. Ammazzare
        // il processo e rifarlo partire farebbe mezzo secondo di schermo senza
        // scrivania, e su una scrivania che si sta costruendo quel mezzo
        // secondo lo si vede cento volte al giorno.
        //
        // ── Perché si può spegnere ───────────────────────────────────────
        //
        // Perché è un attrezzo da officina in mezzo agli attrezzi di casa. Chi
        // usa Minerva e basta non ha nessun motivo di ricaricarla, e un
        // pulsante che non si sa cosa faccia è un pulsante che prima o poi si
        // preme per curiosità.
        Ui.SpineButton {
            id: riavvioBottone
            anchors.verticalCenter: parent.verticalCenter
            visible: Core.Ipc.get("shell.tastoRiavvio", true) === true
            tooltip: Core.Strings.lang === "it" ? "Ricarica la scrivania"
                                                : "Reload the desktop"
            // Nessun avviso prima: ricaricandosi la shell butta via anche
            // quello, e resterebbe una scritta a mezz'aria. La conferma è la
            // ricarica stessa — dura un battito e si vede.
            onClicked: Quickshell.reload(false)
            content: Ui.Icon {
                name: "restart"
                width: 18; height: 18
                color: Theme.Colors.textMuted
            }
        }

        // I programmi che vivono senza finestra. Sta PRIMA dello stato del
        // sistema perché appartiene ai programmi, non alla macchina: a destra
        // di qui comincia Minerva, a sinistra ci sono ancora loro.
        Vassoio {
            anchors.verticalCenter: parent.verticalCenter
        }

        // Stato del sistema, in un unico bersaglio: rete, audio e batteria
        // insieme aprono il pannello di controllo. Tre pulsanti separati per
        // tre pannelli diversi sarebbero tre cose da imparare invece di una.
        StatusCluster {
            id: statusCluster
            anchors.verticalCenter: parent.verticalCenter
            onClicked: bar.spine.centroChiesto()
        }

        Ui.SpineButton {
            id: clipButton
            anchors.verticalCenter: parent.verticalCenter
            tooltip: Core.Strings.lang === "it" ? "Appunti" : "Clipboard"
            onClicked: bar.spine.cassettoChiesto()
            content: Ui.Icon {
                name: "clipboard"
                width: 19; height: 19
                color: Theme.Colors.textMuted
            }
        }

        Ui.SpineButton {
            id: bellButton
            anchors.verticalCenter: parent.verticalCenter
            active: bar.spine.activePanel === "notifications"
            tooltip: Core.Strings.lang === "it" ? "Notifiche" : "Notifications"
            onClicked: bar.spine.toggle("notifications")

            content: Item {
                width: 19; height: 19
                Ui.Icon {
                    anchors.fill: parent
                    name: "bell"
                    color: bellButton.active ? Theme.Colors.accent : Theme.Colors.textMuted
                }
                // Pastiglia del contatore, senza numero: quanti siano esattamente
                // non cambia cosa fare, e un numero a questa dimensione è illeggibile.
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -1
                    anchors.topMargin: -1
                    width: 7; height: 7
                    radius: 3.5
                    color: Theme.Colors.accentWarm
                    visible: bar.unreadCount > 0
                    border.width: 1.5
                    border.color: Theme.Colors.membrane
                }
            }
        }

        Ui.SpineButton {
            id: helpButton
            anchors.verticalCenter: parent.verticalCenter
            visible: Core.Ipc.get("cheatsheet.enabled", true)
            tooltip: Core.Strings.t("shortcuts") + "  ·  F1"
            onClicked: bar.cheatsheetRequested()
            content: Ui.Icon {
                name: "keyboard"
                width: 19; height: 19
                color: helpButton.hovered ? Theme.Colors.accent : Theme.Colors.textMuted
            }
        }

        Ui.SpineButton {
            id: powerButton
            anchors.verticalCenter: parent.verticalCenter
            active: bar.spine.activePanel === "power"
            accent: Theme.Colors.danger
            tooltip: Core.Strings.t("power")
            onClicked: bar.spine.toggle("power")
            content: Ui.Icon {
                name: "power"
                width: 18; height: 18
                color: powerButton.active || powerButton.hovered ? Theme.Colors.danger
                                                                 : Theme.Colors.textMuted
            }
        }
    }
}

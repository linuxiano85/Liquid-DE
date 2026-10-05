import QtQuick
import Quickshell

import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Monitor — Il gestore attività di Minerva.
//
// Due domande, e le fa nell'ordine in cui vengono in mente:
//
//   1. «il computer sta facendo fatica?»  → il cruscotto in alto
//   2. «chi è che me lo sta rallentando?» → l'elenco sotto, ordinato per costo
//
// ── Perché le APPLICAZIONI prima dei processi ───────────────────────────────
//
// Un elenco di processi è la verità, e quasi sempre la verità sbagliata: fra
// duecento righe con nomi come `gvfsd-trash` e `xdg-desktop-portal-gtk` non si
// trova quello che si stava cercando, che è «il browser». La vista predefinita
// mostra i programmi CON UNA FINESTRA — quelli che si sono aperti apposta — e
// tutto il resto sta a un clic di distanza.
//
// ── Perché due pulsanti per chiudere, e non uno ─────────────────────────────
//
// «Chiudi» chiede al programma di andarsene (SIGTERM) e gli lascia il tempo di
// salvare. «Termina» lo ammazza (SIGKILL) e quello che non era salvato è perso.
// Un solo pulsante costringerebbe a scegliere per l'utente: gentile e a volte
// inefficace, o brutale e a volte distruttivo. Qui il secondo compare solo dopo
// che il primo non ha funzionato, che è anche l'unico momento in cui serve.
FloatingWindow {
    id: monitor

    // Non ci si mostra col tema di fabbrica.
    //
    // I colori arrivano dal demone. Finché non sono arrivati, il tema è quello
    // di ripiego (`notte`, ciano): chi ne ha scelto un altro vedeva la
    // finestra aprirsi del colore sbagliato e poi scattare. Misurato, le
    // impostazioni vincevano la corsa per SEDICI MILLISECONDI — un fotogramma,
    // cioè per caso. All'accesso, con più finestre insieme e il demone che sta
    // ancora partendo, quel margine non c'è.
    //
    // `Core.Ipc.prontoADipingere` scade da solo dopo un quarto di secondo, così
    // un demone spento non lascia senza finestra: vedi `core/Ipc.qml`.
    visible: Core.Ipc.prontoADipingere && !monitor.dormiente

    // ── Accesa e nascosta ────────────────────────────────────────────────
    //
    // Vera quando il programma c'è ma non si deve vedere: è così che una app
    // «tenuta pronta» aspetta di essere richiamata senza pagare i 492 ms di
    // ricostruzione. La decisione sta tutta in `core/TenutaPronta.qml`, qui
    // c'è solo l'interruttore della luce.
    property bool dormiente: false

    readonly property bool it: Core.Strings.lang === "it"

    title: "Minerva · " + (monitor.it ? "Attività" : "Activity")
    implicitWidth: 1180
    implicitHeight: 760
    // ── Il colore lo mette la FINESTRA, e costa quindici megabyte di meno ─
    //
    // Il 2 settembre 2026 qui c'era `color: "transparent"` più un
    // `Ui.FondoFinestra` — un rettangolo a tutta finestra col raggio — per
    // arrotondare gli angoli, che Giacomo aveva chiesto.
    //
    // Funzionava, e si è visto nelle fotografie. Costava però **quindici
    // megabyte per applicazione**, misurati: 55 MB senza, 69-72 con. Provato
    // in quattro modi per isolarne la causa — raggio zero, finestra opaca,
    // senza `z: -1` — e il conto non cambiava: in Qt Quick col renderer
    // software un rettangolo grande quanto la finestra costa così, comunque
    // lo si scriva.
    //
    // Su una scrivania che pesa 430 MB, quindici per applicazione non è un
    // prezzo che si paga per un angolo tondo. Gli angoli si faranno nel
    // COMPOSITORE, dove costano una volta sola e valgono anche per i
    // programmi degli altri — che è poi dove deve stare anche il «corpo
    // unico» fra barra e finestra.
    color: Theme.Colors.window

    signal requestClose()
    onClosed: monitor.requestClose()

    // ── I dati ───────────────────────────────────────────────────────────
    //
    // Stanno in `Processi.qml`, insieme al pannello della shell che mostra
    // le stesse cose. Qui restano i nomi di prima, che rimandano là.
    Processi {
        id: dati
        attivo: true
        ordineFermo: elenco.moving || sopraElenco.hovered
    }

    property alias macchina: dati.macchina
    property alias processi: dati.processi
    readonly property alias storiaCpu: dati.storiaCpu
    readonly property alias storiaMem: dati.storiaMem
    readonly property alias storiaRete: dati.storiaRete
    readonly property alias storiaTemp: dati.storiaTemp
    readonly property alias risparmio: dati.risparmio
    property alias filtro: dati.filtro
    property alias vista: dati.vista
    property alias conSistema: dati.conSistema
    readonly property alias quantiDiSistema: dati.quantiDiSistema
    property alias ordine: dati.ordine
    readonly property alias pidOstinato: dati.pidOstinato
    readonly property alias righe: dati.righe
    property alias inPausa: dati.inPausa

    /// Per le prove (`prove-attivita.qml`): la lista, per leggerne la
    /// posizione e il modello.
    property alias elencoVista: elenco
    readonly property alias modelloRighe: dati.modello

    // ── Il cruscotto ─────────────────────────────────────────────────────

    Ui.WindowTitleBar {
        id: barra
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        label: monitor.title
        // Senza questa riga la × non chiude niente. La barra non chiude da sé
        // di proposito — chi ha una copia in corso vuole poter chiedere prima
        // — ma allora ogni finestra DEVE rispondere, e questa non rispondeva:
        // il gestore attività si chiudeva solo con Super+C.
        onCloseRequested: monitor.requestClose()
    }

    // ── Come sta il computer, in una frase ────────────────────────────────
    //
    // Cinque piastrelle con cinque percentuali rispondono a «quanto». Nessuna
    // risponde a «chi», che è la domanda per cui un gestore attività si apre:
    // la ventola gira, e si vuole sapere di chi è la colpa.
    //
    // La frase la scrive il demone (`processi_umani.dart`), perché è una
    // decisione con delle soglie e le soglie vanno provate — `dart test` le
    // prova, una riga di QML no.
    //
    // Quando non c'è niente da dire dice «Tutto tranquillo» e basta. Un
    // cruscotto che grida sempre non lo guarda più nessuno.
    Text {
        id: comeSta
        anchors.top: barra.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.Effects.space4
        anchors.rightMargin: Theme.Effects.space4
        anchors.topMargin: Theme.Effects.space3
        elide: Text.ElideRight
        // Da quanto è acceso sta QUI, accanto a come sta: stava sotto la
        // temperatura, dove si leggeva «47 °C — acceso da 17m» come se le due
        // cose avessero a che fare l'una con l'altra.
        text: String(monitor.macchina.comeSta || "").replace(/\.$/, "")
              + (monitor.macchina.acceso
                 ? (monitor.macchina.comeSta ? "  ·  " : "")
                   + (monitor.it ? "acceso da " : "up ")
                   + Core.Formato.durata(monitor.macchina.acceso)
                 : "")
        visible: text !== ""
        color: monitor.allarmato ? Theme.Colors.warning : Theme.Colors.textMuted
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: Theme.Typography.sizeMD
        font.weight: Theme.Typography.weightMedium
    }

    /// Vero quando la frase sta segnalando qualcosa, non descrivendo la calma.
    /// Il colore non si sceglie leggendo il testo: si sceglie dagli stessi
    /// numeri che l'hanno prodotto.
    readonly property bool allarmato:
        (monitor.macchina.cpu || 0) >= 60
        || (monitor.macchina.memoriaTotale > 0
            && monitor.macchina.memoriaUsata / monitor.macchina.memoriaTotale >= 0.9)

    Row {
        id: cruscotto
        anchors.top: comeSta.visible ? comeSta.bottom : barra.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.Effects.space4
        anchors.topMargin: Theme.Effects.space3
        spacing: Theme.Effects.space3

        readonly property int quante: monitor.macchina.temperatura !== undefined ? 5 : 4
        readonly property real largo:
            (width - spacing * (quante - 1)) / quante

        StatTile {
            width: cruscotto.largo
            titolo: monitor.it ? "PROCESSORE" : "CPU"
            valore: monitor.macchina.cpu !== undefined
                    ? Math.round(monitor.macchina.cpu) : "—"
            unita: "%"
            sotto: (monitor.macchina.core || 0) + (monitor.it ? " core · carico "
                                                             : " cores · load ")
                   + (monitor.macchina.carico !== undefined
                      ? monitor.macchina.carico.toFixed(2) : "—")
            punti: monitor.storiaCpu
            massimo: 100
            allarme: (monitor.macchina.cpu || 0) > 85
        }

        StatTile {
            width: cruscotto.largo
            titolo: monitor.it ? "MEMORIA" : "MEMORY"
            valore: monitor.macchina.memoriaTotale > 0
                    ? Math.round(monitor.macchina.memoriaUsata
                                 / monitor.macchina.memoriaTotale * 100) : "—"
            unita: "%"
            sotto: Core.Formato.peso(monitor.macchina.memoriaUsata || 0) + " / "
                   + Core.Formato.peso(monitor.macchina.memoriaTotale || 0)
                   + (monitor.macchina.memoriaCache
                      ? " · cache " + Core.Formato.peso(monitor.macchina.memoriaCache || 0) : "")
                   // Il respiro, quando c'è qualcosa di compresso: vedi
                   // Processi.risparmio.
                   + (dati.risparmio.pagine > 0
                      ? (monitor.it ? " · respiro −" : " · breathing −")
                        + Core.Formato.peso((dati.risparmio.pagine - dati.risparmio.occupa) || 0) : "")
            punti: monitor.storiaMem
            massimo: 100
            colore: Theme.Colors.accentAlt !== undefined
                    ? Theme.Colors.accentAlt : Theme.Colors.accent
            allarme: monitor.macchina.memoriaTotale > 0
                     && monitor.macchina.memoriaUsata
                        / monitor.macchina.memoriaTotale > 0.9
        }

        StatTile {
            width: cruscotto.largo
            titolo: monitor.it ? "RETE" : "NETWORK"
            valore: Core.Formato.peso((monitor.macchina.reteGiu || 0)
                              + (monitor.macchina.reteSu || 0))
            unita: "/s"
            sotto: "↓ " + Core.Formato.peso(monitor.macchina.reteGiu || 0) + "/s   ↑ "
                   + Core.Formato.peso(monitor.macchina.reteSu || 0) + "/s"
            punti: monitor.storiaRete
            // Fondoscala automatico: la rete non ha un tetto, e fissarne uno
            // vorrebbe dire una linea piatta in basso per il 99% del tempo.
            massimo: 0
        }

        StatTile {
            width: cruscotto.largo
            titolo: monitor.it ? "SCAMBIO" : "SWAP"
            valore: monitor.macchina.scambioTotale > 0
                    ? Math.round(monitor.macchina.scambioUsato
                                 / monitor.macchina.scambioTotale * 100) : "0"
            unita: "%"
            sotto: monitor.macchina.scambioTotale > 0
                   ? Core.Formato.peso(monitor.macchina.scambioUsato || 0) + " / "
                     + Core.Formato.peso(monitor.macchina.scambioTotale || 0)
                   : (monitor.it ? "nessuno" : "none")
            punti: []
            allarme: monitor.macchina.scambioTotale > 0
                     && monitor.macchina.scambioUsato
                        / monitor.macchina.scambioTotale > 0.5
        }

        StatTile {
            visible: monitor.macchina.temperatura !== undefined
            width: visible ? cruscotto.largo : 0
            titolo: monitor.it ? "TEMPERATURA" : "TEMPERATURE"
            valore: monitor.macchina.temperatura !== undefined
                    ? Math.round(monitor.macchina.temperatura) : "—"
            unita: "°C"
            // Una parola che dice se preoccuparsi: il numero da solo lo
            // capisce chi sa quanto scalda questo processore.
            sotto: {
                var t = monitor.macchina.temperatura || 0;
                if (t > 80) return monitor.it ? "calda: guarda chi usa il processore" : "hot";
                if (t > 65) return monitor.it ? "tiepida" : "warm";
                return monitor.it ? "fresca" : "cool";
            }
            punti: monitor.storiaTemp
            massimo: 100
            allarme: (monitor.macchina.temperatura || 0) > 80
        }
    }

    // ── Comandi ──────────────────────────────────────────────────────────

    Item {
        id: comandi
        anchors.top: cruscotto.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.Effects.space4
        anchors.topMargin: Theme.Effects.space3
        height: 36

        Row {
            id: viste
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Repeater {
                model: [
                    { "id": "app",   "it": "Applicazioni", "en": "Applications" },
                    { "id": "tutti", "it": "Tutti i processi", "en": "All processes" }
                ]

                delegate: Rectangle {
                    required property var modelData
                    readonly property bool scelta: monitor.vista === modelData.id

                    width: testo.implicitWidth + Theme.Effects.space5
                    height: 34
                    radius: Theme.Effects.radiusSM
                    color: scelta ? Qt.alpha(Theme.Colors.accent, 0.18)
                         : mouse.containsMouse ? Theme.Colors.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Text {
                        id: testo
                        anchors.centerIn: parent
                        text: monitor.it ? parent.modelData.it : parent.modelData.en
                        color: parent.scelta ? Theme.Colors.text : Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeMD
                        font.weight: parent.scelta ? Theme.Typography.weightSemiBold
                                                   : Theme.Typography.weightMedium
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: monitor.vista = parent.modelData.id
                    }
                }
            }
        }

        // ── «e altri N del sistema» ──────────────────────────────────────
        //
        // Sta accanto alle due linguette, non fra le impostazioni: è una cosa
        // che si guarda mentre si guarda l'elenco, e va accesa e spenta senza
        // andarla a cercare.
        //
        // Il numero c'è sempre, anche da spenta: così non sembra che manchino
        // dei processi — si sa che ci sono e si sa dove sono.
        Rectangle {
            id: interruttoreSistema
            visible: monitor.vista === "tutti" && monitor.quantiDiSistema > 0
            anchors.left: viste.right
            anchors.leftMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            height: 30
            width: etichettaSistema.implicitWidth + Theme.Effects.space4
            radius: height / 2
            color: monitor.conSistema ? Qt.alpha(Theme.Colors.accent, 0.16)
                                      : "transparent"
            border.width: Theme.Effects.hairline
            border.color: monitor.conSistema ? Qt.alpha(Theme.Colors.accent, 0.5)
                                             : Theme.Colors.edge
            Behavior on color { ColorAnimation { duration: Theme.Motion.quick } }

            Text {
                id: etichettaSistema
                anchors.centerIn: parent
                text: (monitor.conSistema
                       ? (monitor.it ? "nascondi il sistema" : "hide system")
                       : (monitor.it ? "e altri " : "and ") + monitor.quantiDiSistema
                         + (monitor.it ? " del sistema" : " system"))
                color: monitor.conSistema ? Theme.Colors.text : Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                font.weight: Theme.Typography.weightMedium
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: monitor.conSistema = !monitor.conSistema
            }
        }

        // La ricerca sta a destra e non al centro: la mano che la usa arriva
        // dalla tastiera, non dal mouse, e il centro è già occupato dal
        // significato — quale vista si sta guardando.
        Rectangle {
            id: cerca
            anchors.right: ordinatore.left
            anchors.rightMargin: Theme.Effects.space3
            anchors.verticalCenter: parent.verticalCenter
            width: 260
            height: 34
            radius: Theme.Effects.radiusSM
            color: Theme.Colors.raised
            border.width: Theme.Effects.hairline
            border.color: campo.activeFocus ? Qt.alpha(Theme.Colors.accent, 0.55)
                                            : Theme.Colors.edge
            Behavior on border.color { ColorAnimation { duration: Theme.Motion.quick } }

            Ui.Icon {
                id: lente
                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space3
                anchors.verticalCenter: parent.verticalCenter
                width: 15; height: 15
                name: "search"
                color: Theme.Colors.textFaint
                alwaysDrawn: true
            }

            TextInput {
                id: campo
                anchors.left: lente.right
                anchors.leftMargin: Theme.Effects.space2
                anchors.right: parent.right
                anchors.rightMargin: Theme.Effects.space3
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                text: monitor.filtro
                onTextChanged: monitor.filtro = text
                color: Theme.Colors.text
                selectionColor: Qt.alpha(Theme.Colors.accent, 0.35)
                selectedTextColor: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeMD

                Text {
                    anchors.fill: parent
                    visible: campo.text === ""
                    verticalAlignment: Text.AlignVCenter
                    text: monitor.it ? "Cerca…" : "Search…"
                    color: Theme.Colors.textFaint
                    font: campo.font
                }
            }
        }

        Row {
            id: ordinatore
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            // «Pausa»: ferma la lista, numeri compresi, per leggerla con
            // calma. Acceso si vede — una lista ferma che sembra viva è un
            // modo di mentire.
            Rectangle {
                width: pausaTesto.implicitWidth + Theme.Effects.space4
                height: 34
                radius: Theme.Effects.radiusSM
                color: monitor.inPausa ? Qt.alpha(Theme.Colors.warning, 0.20)
                     : pausaMouse.containsMouse ? Theme.Colors.hover : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                Text {
                    id: pausaTesto
                    anchors.centerIn: parent
                    text: monitor.inPausa ? (monitor.it ? "Riprendi" : "Resume")
                                          : (monitor.it ? "Pausa" : "Pause")
                    color: monitor.inPausa ? Theme.Colors.text : Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }

                MouseArea {
                    id: pausaMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: monitor.inPausa = !monitor.inPausa
                }
            }

            Rectangle {
                width: Theme.Effects.hairline
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.Colors.edge
            }

            Repeater {
                model: [
                    { "id": "cpu",     "it": "CPU",     "en": "CPU" },
                    { "id": "memoria", "it": "Memoria", "en": "Memory" },
                    { "id": "nome",    "it": "Nome",    "en": "Name" }
                ]

                delegate: Rectangle {
                    required property var modelData
                    readonly property bool scelta: monitor.ordine === modelData.id

                    width: eti.implicitWidth + Theme.Effects.space4
                    height: 34
                    radius: Theme.Effects.radiusSM
                    color: scelta ? Qt.alpha(Theme.Colors.accent, 0.18)
                         : m2.containsMouse ? Theme.Colors.hover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                    Text {
                        id: eti
                        anchors.centerIn: parent
                        text: monitor.it ? parent.modelData.it : parent.modelData.en
                        color: parent.scelta ? Theme.Colors.text : Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    MouseArea {
                        id: m2
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: monitor.ordine = parent.modelData.id
                    }
                }
            }
        }
    }

    // ── L'elenco ─────────────────────────────────────────────────────────

    Rectangle {
        id: cornice
        anchors.top: comandi.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: pieDiPagina.top
        anchors.margins: Theme.Effects.space4
        anchors.topMargin: Theme.Effects.space2
        radius: Theme.Effects.radiusMD
        color: Theme.Colors.raised
        border.width: Theme.Effects.hairline
        border.color: Theme.Colors.edge
        clip: true

        // Intestazione delle colonne. Fissa: scorrendo duecento processi si
        // perde subito quale numero è quale.
        Rectangle {
            id: intestazione
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 32
            color: "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.Effects.space4 + 30
                anchors.verticalCenter: parent.verticalCenter
                text: monitor.it ? "NOME" : "NAME"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
                font.letterSpacing: Theme.Typography.trackingLabel
            }

            // I bordi destri delle colonne, contati da destra come li mette
            // `ProcessRow` (margine, pulsanti, e le tre colonne coi loro
            // spazi). Erano due numeri scritti a mano, e la colonna del PID
            // non aveva titolo: un numero senza nome in fondo a ogni riga.
            // Stesse misure di `ProcessRow` (pulsanti 96, PID 60, memoria 90):
            // se cambiano là, vanno cambiate qui.
            readonly property int bordoPid: Theme.Effects.space4 + 96 + Theme.Effects.space3
            readonly property int bordoMem: bordoPid + 60 + Theme.Effects.space3
            readonly property int bordoCpu: bordoMem + 90 + Theme.Effects.space3

            Text {
                anchors.right: parent.right
                anchors.rightMargin: intestazione.bordoPid
                anchors.verticalCenter: parent.verticalCenter
                text: "PID"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
                font.letterSpacing: Theme.Typography.trackingLabel
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: intestazione.bordoCpu
                anchors.verticalCenter: parent.verticalCenter
                text: "CPU"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
                font.letterSpacing: Theme.Typography.trackingLabel
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: intestazione.bordoMem
                anchors.verticalCenter: parent.verticalCenter
                text: monitor.it ? "MEMORIA" : "MEMORY"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
                font.letterSpacing: Theme.Typography.trackingLabel
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: Theme.Effects.hairline
                color: Theme.Colors.edge
            }
        }

        // Centinaia di processi: è la lista più lunga della scrivania.
        Ui.Scorrimento {
            bersaglio: elenco
            anchors {
                right: elenco.right
                top: elenco.top
                bottom: elenco.bottom
            }
        }

        ListView {
            id: elenco
            anchors.top: intestazione.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            model: dati.modello
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: 400

            HoverHandler { id: sopraElenco }

            delegate: ProcessRow {
                required property var model
                width: ListView.view.width
                riga: model.riga
                ostinato: monitor.pidOstinato === model.riga.pid
                onChiudi: function(pid, forza) {
                    Core.Ipc.killProcess(pid, forza);
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: monitor.righe.length === 0
            text: monitor.filtro !== ""
                  ? (monitor.it ? "Nessun processo con questo nome"
                                : "No process with that name")
                  : (monitor.it ? "In attesa dei dati…" : "Waiting for data…")
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeMD
        }
    }

    // ── Piè di pagina ────────────────────────────────────────────────────

    Item {
        id: pieDiPagina
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.Effects.space4
        anchors.bottomMargin: Theme.Effects.space3
        height: 20

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: {
                var n = monitor.righe.length;
                var t = monitor.processi.length;
                var fermo = monitor.inPausa ? (monitor.it ? "  ·  in pausa" : "  ·  paused") : "";
                if (monitor.vista === "app")
                    return (monitor.it
                        ? n + (n === 1 ? " applicazione · " : " applicazioni · ")
                          + t + " processi in tutto"
                        : n + (n === 1 ? " application · " : " applications · ")
                          + t + " processes in total") + fermo;
                return (monitor.it ? n + (n === 1 ? " processo" : " processi")
                                   : n + (n === 1 ? " process" : " processes")) + fermo;
            }
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: monitor.it ? "aggiornato ogni 2 secondi" : "updated every 2 seconds"
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeXS
        }
    }

    // ── Tastiera ─────────────────────────────────────────────────────────

    Shortcut {
        sequence: "Escape"
        onActivated: monitor.filtro !== "" ? monitor.filtro = "" : monitor.requestClose()
    }
    Shortcut {
        sequence: "Ctrl+F"
        onActivated: campo.forceActiveFocus()
    }

    // ── Iscrizione ───────────────────────────────────────────────────────
    //
    // Ci si iscrive all'apertura e ci si toglie alla chiusura: il demone legge
    // `/proc` solo mentre questa finestra è viva. Un monitor che continua a
    // misurare dopo essere stato chiuso è esattamente il tipo di programma che
    // questo monitor serve a trovare.
    Component.onCompleted: campo.forceActiveFocus()
}

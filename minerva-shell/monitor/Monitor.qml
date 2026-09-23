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

    property var macchina: ({})
    property var processi: []

    /// Storie per i grafici. Sessanta campioni a due secondi l'uno fanno due
    /// minuti di passato, che è la finestra in cui si riconosce «sta salendo».
    readonly property int storiaMax: 60
    property var storiaCpu: []
    property var storiaMem: []
    property var storiaRete: []
    property var storiaTemp: []

    property string filtro: ""
    /// "app" mostra solo i programmi con una finestra, "tutti" ogni processo.
    property string vista: "app"
    /// In vista «tutti»: mostrare anche i processi del sistema.
    property bool conSistema: false

    /// Quanti processi di sistema si stanno tenendo chiusi.
    readonly property int quantiDiSistema: {
        var n = 0;
        for (var i = 0; i < monitor.processi.length; i++)
            if (monitor.processi[i].sistema
                && monitor.pidConFinestra[monitor.processi[i].pid] === undefined)
                n++;
        return n;
    }
    /// "cpu", "memoria" o "nome".
    property string ordine: "cpu"

    /// Il PID su cui il primo «chiudi» non ha funzionato: solo a lui si offre
    /// di terminare a forza.
    property int pidOstinato: -1

    Connections {
        target: Core.Ipc
        function onProcessesReceived(dati) {
            monitor.macchina = dati.macchina || ({});
            monitor.processi = dati.processi || [];
            monitor.aggiungiStorie();
        }
        function onProcessKilled(pid, ok, force) {
            // Se il gentile non ha funzionato, la riga si offre di insistere.
            if (!force)
                monitor.pidOstinato = ok ? -1 : pid;
        }
    }

    function aggiungiStorie() {
        var m = monitor.macchina;
        monitor.storiaCpu = monitor.appendi(monitor.storiaCpu, m.cpu !== undefined ? m.cpu : 0);
        var memPerc = (m.memoriaTotale > 0)
                      ? (m.memoriaUsata / m.memoriaTotale * 100) : 0;
        monitor.storiaMem = monitor.appendi(monitor.storiaMem, memPerc);
        monitor.storiaRete = monitor.appendi(monitor.storiaRete,
                                             (m.reteGiu || 0) + (m.reteSu || 0));
        if (m.temperatura !== undefined)
            monitor.storiaTemp = monitor.appendi(monitor.storiaTemp, m.temperatura);
    }

    function appendi(storia, valore) {
        var s = storia.slice();
        s.push(valore);
        while (s.length > monitor.storiaMax)
            s.shift();
        return s;
    }

    // ── Chi ha una finestra ──────────────────────────────────────────────
    //
    // Il compositore sa il numero di processo di ogni finestra aperta. È
    // l'unico modo onesto di distinguere «un programma che ho aperto io» da
    // «un servizio che gira per conto suo»: il nome non basta — `chrome` è
    // undici processi, e uno solo ha la finestra.
    readonly property var pidConFinestra: {
        var s = {};
        var f = Core.Windows.all || [];
        for (var i = 0; i < f.length; i++)
            if (f[i].pid)
                s[f[i].pid] = f[i].appClass || "";
        return s;
    }

    /// Le righe da mostrare, filtrate e ordinate.
    ///
    /// I processi di uno stesso programma si SOMMANO in una riga sola: un
    /// browser con dodici schede sono dodici processi che nessuno vuole
    /// contare, e la domanda vera è quanto costa il browser.
    readonly property var righe: {
        var dentro = [];
        var ago = monitor.filtro.trim().toLowerCase();
        var gruppi = {};

        for (var i = 0; i < monitor.processi.length; i++) {
            var p = monitor.processi[i];
            var haFinestra = monitor.pidConFinestra[p.pid] !== undefined;

            if (monitor.vista === "app" && !haFinestra)
                continue;

            // ── Il sistema sta chiuso finché non lo si chiede ────────────
            //
            // «Tutti i processi» ne mostrava duecentodue, e centottanta erano
            // `kworker/3:1H`, `systemd-udevd`, `irq/142-nvme0q3`. Nessuno di
            // quelli si chiude, nessuno di quelli è la risposta a «perché la
            // ventola gira», e stanno lì solo a far scorrere.
            //
            // Non si tolgono: si chiudono. Chi li vuole ha una levetta, e
            // sotto c'è scritto quanti sono — così non sembra che manchino.
            // Cercando invece si trova tutto: chi scrive «kworker» sa quello
            // che sta cercando.
            if (monitor.vista === "tutti" && !monitor.conSistema && ago === ""
                && p.sistema && !haFinestra)
                continue;
            if (ago !== "" && (p.nome || "").toLowerCase().indexOf(ago) === -1
                && (p.comando || "").toLowerCase().indexOf(ago) === -1)
                continue;

            // In vista «tutti» non si raggruppa: lì si guarda il dettaglio, ed
            // è proprio il dettaglio che si è venuti a cercare.
            //
            // ── Perché la chiave non è (solo) il nome ────────────────────
            //
            // Il nome del processo identifica il PROGRAMMA solo finché un
            // programma è un binario. Le finestre di Minerva sono cinque
            // applicazioni diverse eseguite tutte da `qs`: raggruppate per
            // nome diventavano una riga sola, «qs ×5», con le memorie sommate
            // — ed è da lì che veniva il «450 MB» di Anteprima, che non era
            // Anteprima. Quando una finestra c'è, è la sua CLASSE a dire di
            // quale applicazione si tratta.
            var classe = monitor.pidConFinestra[p.pid] || "";
            var chiave = monitor.vista !== "app" ? String(p.pid)
                       : (classe !== "" ? classe : (p.nome || "?"));
            var privata = Math.max(0, (p.memoria || 0) - (p.memoriaCondivisa || 0));
            // ── Il numero equo, quando il demone è riuscito a prenderlo ───
            //
            // `memoriaEqua` è il PSS: le pagine condivise divise fra chi le
            // usa. È additivo — sommare i PSS di più processi dà un numero
            // vero — e quindi non ha bisogno del giro qui sotto sul massimo.
            // Manca per i processi di altri utenti (`smaps_rollup` non è
            // leggibile) e per quelli piccoli, che il demone non interroga: lì
            // si torna alla stima privata + condivisa.
            var equa = p.memoriaEqua || 0;
            var g = gruppi[chiave];
            if (g === undefined) {
                gruppi[chiave] = {
                    "chiave": chiave,
                    "pid": p.pid,
                    "nome": p.nome,
                    "comando": p.comando,
                    // Li calcola il demone, e vanno portati fin qui: senza,
                    // l'aggregazione li lasciava per strada e la riga tornava
                    // a mostrare la riga di comando.
                    "etichetta": p.etichetta,
                    "descrizione": p.descrizione,
                    "sistema": p.sistema,
                    "cpu": p.cpu,
                    // Vedi `memoria` più sotto: si tengono separate la parte
                    // privata (che si somma) e quella condivisa (che no).
                    "privata": privata,
                    "condivisa": p.memoriaCondivisa || 0,
                    "equa": equa,
                    "quanti": 1,
                    "finestra": haFinestra,
                    "classe": classe
                };
            } else {
                g.cpu = (g.cpu === null || g.cpu === undefined)
                        ? p.cpu : (g.cpu + (p.cpu || 0));
                g.privata += privata;
                // ── La memoria condivisa NON si somma ────────────────────
                //
                // Dentro l'RSS ci sono le librerie — Qt e Mesa sono
                // centoventi megabyte — che stanno in memoria una volta sola
                // e vengono contate in ogni processo che le usa. Sommare
                // l'RSS di dodici processi di un browser dà un numero che non
                // esiste in nessuna parte del computer. Del pezzo condiviso
                // si tiene il massimo del gruppo: è una stima per difetto,
                // ma è dalla parte giusta.
                g.condivisa = Math.max(g.condivisa, p.memoriaCondivisa || 0);
                g.equa += equa;
                g.quanti++;
                if (haFinestra && !g.finestra) {
                    g.finestra = true;
                    g.pid = p.pid;
                    g.classe = classe;
                }
            }
        }

        for (var k in gruppi) {
            var r = gruppi[k];
            // Il PSS quando c'è, la stima quando manca. Mai la somma dei due
            // e mai l'RSS crudo: era quello a far sembrare 183 MB una
            // finestra che di suo ne occupa quarantadue.
            r.memoria = r.equa > 0 ? r.equa : (r.privata + r.condivisa);
            dentro.push(r);
        }

        dentro.sort(function(a, b) {
            if (monitor.ordine === "nome")
                return (a.nome || "").localeCompare(b.nome || "");
            if (monitor.ordine === "memoria")
                return (b.memoria || 0) - (a.memoria || 0);
            return (b.cpu || 0) - (a.cpu || 0);
        });
        return dentro;
    }

    // ── Formattazione ────────────────────────────────────────────────────

    function byte(v) {
        if (!v || v <= 0) return "0";
        var u = ["B", "KB", "MB", "GB", "TB"];
        var i = 0;
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
        return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)) + " " + u[i];
    }

    function durata(secondi) {
        if (!secondi) return "—";
        var g = Math.floor(secondi / 86400);
        var o = Math.floor((secondi % 86400) / 3600);
        var m = Math.floor((secondi % 3600) / 60);
        if (g > 0) return g + (monitor.it ? " g " : "d ") + o + "h";
        if (o > 0) return o + "h " + m + "m";
        return m + "m";
    }

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
        text: monitor.macchina.comeSta || ""
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
            sotto: monitor.byte(monitor.macchina.memoriaUsata) + " / "
                   + monitor.byte(monitor.macchina.memoriaTotale)
                   + (monitor.macchina.memoriaCache
                      ? (monitor.it ? " · cache " : " · cache ")
                        + monitor.byte(monitor.macchina.memoriaCache) : "")
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
            valore: monitor.byte((monitor.macchina.reteGiu || 0)
                                 + (monitor.macchina.reteSu || 0))
            unita: "/s"
            sotto: "↓ " + monitor.byte(monitor.macchina.reteGiu) + "/s   ↑ "
                   + monitor.byte(monitor.macchina.reteSu) + "/s"
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
                   ? monitor.byte(monitor.macchina.scambioUsato) + " / "
                     + monitor.byte(monitor.macchina.scambioTotale)
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
            sotto: monitor.it ? "acceso da " + monitor.durata(monitor.macchina.acceso)
                              : "up " + monitor.durata(monitor.macchina.acceso)
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

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 300
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
                anchors.rightMargin: 190
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
            model: monitor.righe
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: 400

            delegate: ProcessRow {
                required property var modelData
                width: ListView.view.width
                riga: modelData
                ostinato: monitor.pidOstinato === modelData.pid
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
                if (monitor.vista === "app")
                    return monitor.it
                        ? n + " applicazioni · " + t + " processi in tutto"
                        : n + " applications · " + t + " processes in total";
                return monitor.it ? n + " processi" : n + " processes";
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
    Component.onCompleted: {
        Core.Ipc.subscribeProcesses();
        campo.forceActiveFocus();
    }
    Component.onDestruction: Core.Ipc.unsubscribeProcesses()
}

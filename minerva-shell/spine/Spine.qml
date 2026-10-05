import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// Spine — La barra di Minerva e tutto ciò che ne discende.
//
// ARCHITETTURA, ed è il punto centrale di tutto il progetto:
//
// Barra e pannelli a tendina NON sono finestre separate. Sono una sola
// superficie layer-shell, alta quanto lo schermo, su cui viene disegnato un
// unico tracciato: la striscia della barra più la «lingua» che scende quando
// un pannello è aperto, raccordata da fillet concavi.
//
// Perché una finestra sola:
//
//  · Nessuna cucitura. Due superfici allineate al pixel mostrano comunque il
//    punto di giunzione — il blur si interrompe, le trasparenze si sommano
//    dove si sovrappongono. Un tracciato solo non ha giunzioni.
//
//  · Il passaggio da un pannello all'altro diventa una MORFOSI. Aprendo le
//    impostazioni mentre è aperto il menu app, la lingua scivola e si
//    ridimensiona invece di chiudersi e riaprirsi altrove.
//
//  · Un solo rettangolo di blur da calcolare per il compositore.
//
// Il prezzo è che la finestra copre lo schermo pur essendo quasi tutta
// trasparente: senza correttivi intercetterebbe ogni clic sulla scrivania.
// Da qui la `mask`, che dichiara al compositore quali sono le uniche due zone
// realmente cliccabili — la barra e la lingua.
PanelWindow {
    id: spine

    // ── Da che parte sta la barra ────────────────────────────────────────
    //
    // La superficie è alta quanto lo schermo in tutti e due i casi, quindi le
    // coordinate del puntatore e delle maschere non cambiano: cambia solo a
    // quale bordo si ancora, e quindi da quale parte il compositore riserva lo
    // spazio esclusivo. Tutto il resto qui dentro si specchia da sé, perché
    // ogni `y` passa da `bordoBarra`.
    property bool inBasso: false

    /// Dove comincia la barra, in coordinate della finestra.
    readonly property real bordoBarra: spine.inBasso
                                       ? spine.height - spine.barHeight : 0
    anchors { top: !spine.inBasso; bottom: spine.inBasso; left: true; right: true }

    WlrLayershell.namespace: "quickshell"
    WlrLayershell.layer: WlrLayer.Top
    // ── Esclusivo, non «a richiesta» ─────────────────────────────────────
    //
    // `OnDemand` vuol dire: il compositore ti dà la tastiera QUANDO L'UTENTE
    // CI CLICCA SOPRA. Era la ragione per cui il menu delle app si apriva e
    // non si poteva scrivere: bisognava prima cliccare nella casella. Il
    // fuoco dentro QML c'era già — era la superficie a non avere la tastiera.
    //
    // `Exclusive` la prende all'apertura. Si può fare perché da un pannello
    // aperto si esce sempre in due modi indipendenti: Esc (gestito da
    // `panelArea` qui sotto, che è antenato di qualunque pannello) e un clic
    // fuori (il `dismissCatcher` in fondo al file). Senza una di queste due
    // vie, prendersi la tastiera per sempre sarebbe un modo di bloccare la
    // sessione.
    WlrLayershell.keyboardFocus: activePanel !== ""
                                 ? WlrKeyboardFocus.Exclusive
                                 : WlrKeyboardFocus.None

    color: "transparent"

    // La barra riserva il proprio spazio; la lingua no, altrimenti tutte le
    // finestre scenderebbero ogni volta che si apre un pannello.
    exclusiveZone: Theme.Effects.barHeight
    implicitHeight: screen ? screen.height : 1080

    // ── Stato ────────────────────────────────────────────────────────────

    // I pannelli a schermo intero (scorciatoie, impostazioni) non vivono
    // dentro la Spine: li possiede la shell. I pannelli a tendina che li
    // vogliono aprire lo chiedono da qui.
    signal cheatsheetRequested()
    signal settingsRequested()
    /// Il pulsante del menù delle app: il menù è il Sottomarino, che non
    /// vive nella barra (`menu/Sottomarino.qml`).
    signal menuAppChiesto()
    /// I segni di stato: aprono il Centro di controllo (`menu/Centro.qml`).
    signal centroChiesto()
    /// Il pulsante degli appunti: apre il Cassetto (`menu/Cassetto.qml`).
    signal cassettoChiesto()
    /// La capsula in mezzo: apre l'Isola (`menu/Isola.qml`), che nasce dal
    /// rettangolo della capsula, in coordinate dello schermo.
    signal isolaChiesta(rect dove)
    signal monitorRequested()
    /// Tasto destro sul nome della finestra attiva, in coordinate globali.
    signal windowMenuRequested(point where)
    /// Tasto destro sul vuoto della barra: chi ascolta apre il suo menù.
    signal menuBarraChiesto(point dove)

    /// Il pannello delle schermate chiede di scattare. Non scatta lui, e non
    /// è una preferenza di stile: scattare vuol dire prima chiudere il
    /// pannello — altrimenti finisce dentro la fotografia — e chiudersi vuol
    /// dire farsi scaricare dal Loader qui sotto, cioè smettere di esistere
    /// insieme al proprio conto alla rovescia. Il primo tentativo teneva il
    /// timer dentro al pannello: il pannello spariva, il timer con lui, e non
    /// scattava niente. Chi aspetta deve sopravvivere all'attesa.
    signal screenshotRequested(string modo, int ritardo)

    /// Identificatore del pannello aperto ("" = nessuno).
    property string activePanel: ""

    /// Rettangolo che il raccoglitore di clic non deve coprire, in coordinate
    /// dello schermo. Ce lo passa la shell: è la dock.
    property rect keepClickable: Qt.rect(0, 0, 0, 0)

    /// La striscia della dock, che resta sensibile al puntatore anche quando
    /// la maschera si allarga a tutto lo schermo.
    property rect dockBand: Qt.rect(0, 0, 0, 0)

    /// Geometria richiesta dal pannello attivo, animata dalla membrana.
    property real targetX: 0
    property real targetWidth: 0
    property real targetHeight: 0

    readonly property int barHeight: Theme.Effects.barHeight

    /// Registro dei pannelli. Ogni voce dichiara larghezza, altezza massima,
    /// da quale lato si ancora e quale file caricare.
    readonly property var registry: ({
        "control": {
            "width": 420, "height": 470, "align": "right",
            "source": "panels/ControlPanel.qml"
        },
        "notifications": {
            "width": 400, "height": 480, "align": "right",
            "source": "panels/NotificationsPanel.qml"
        },
        "power": {
            "width": 300, "height": 300, "align": "right",
            "source": "panels/PowerPanel.qml"
        },
        "minimized": {
            "width": 340, "height": 420, "align": "left",
            "source": "panels/MinimizedPanel.qml"
        },
        "meteo": {
            "width": 380, "height": 460, "align": "right",
            "source": "panels/WeatherPanel.qml"
        },
        "calendar": {
            // 510 e non 420: sotto il mese c'è adesso la striscia di come sta
            // il computer, e l'altezza qui è un TETTO — `layoutPanel` prende
            // comunque il minimo fra questo e l'altezza vera del contenuto.
            // Lasciandolo a 420 la striscia veniva tagliata a metà.
            "width": 330, "height": 510, "align": "center",
            "source": "panels/CalendarPanel.qml"
        },
        "schermata": {
            "width": 400, "height": 400, "align": "center",
            "source": "panels/ScreenshotPanel.qml"
        }
    })

    /// Bordi orizzontali di ciascun pulsante che apre un pannello, in
    /// coordinate della barra. La lingua si allinea al pulsante che l'ha
    /// aperta: è ciò che rende evidente da dove è scesa.
    ///
    /// Si registrano entrambi i bordi e non il centro: un pannello largo
    /// centrato su un pulsante vicino a un lato dello schermo ne uscirebbe, e
    /// il clamp finale lo sposterebbe altrove rompendo l'allineamento. Con i
    /// bordi il pannello si aggancia al lato giusto e basta.
    property var anchors_: ({})

    function registerAnchor(name, leftX, rightX) {
        var a = spine.anchors_;
        a[name] = { "left": leftX, "right": rightX };
        spine.anchors_ = a;
        if (spine.activePanel === name)
            spine.layoutPanel();
    }

    // ── Un solo giro per volta ───────────────────────────────────────────
    //
    // `layoutPanel()` scrive `targetHeight`, e `targetHeight` arriva fino
    // all'altezza del pannello: se il pannello, ridimensionandosi, cambia il
    // proprio `implicitPanelHeight`, si ritorna qui dentro mentre siamo
    // ancora qui dentro.
    //
    // Succede davvero, e non per un errore di scrittura: `contentHeight` di
    // un ListView con voci di altezza diversa è una STIMA, calcolata sui
    // delegati che esistono in quel momento — e quanti ne esistono dipende da
    // quanto è alta la vista. Elenco più alto, stima diversa, altezza nuova.
    //
    // La ricorsione si ferma qui invece che sperare che converga: si calcola
    // una volta con le misure di adesso, e se nel frattempo il contenuto è
    // cambiato lo dirà il prossimo segnale.
    property bool _staDisponendo: false

    function layoutPanel() {
        if (spine._staDisponendo)
            return;
        spine._staDisponendo = true;
        try {
            spine._layoutPanel();
        } finally {
            spine._staDisponendo = false;
        }
    }

    function _layoutPanel() {
        var def = spine.registry[spine.activePanel];
        if (!def) {
            spine.targetHeight = 0;
            return;
        }

        var margin = Theme.Effects.space3;
        var w = Math.min(def.width, spine.width - margin * 2);
        var a = spine.anchors_[spine.activePanel];

        var x;
        if (a === undefined) {
            x = def.align === "right" ? spine.width - w - margin
              : def.align === "center" ? (spine.width - w) / 2
              : margin;
        } else if (def.align === "right") {
            x = a.right - w;
        } else if (def.align === "center") {
            // Centrato sul pulsante, non sullo schermo: l'orologio sta al
            // centro ma un giorno potrebbe non starci più, e la lingua deve
            // continuare a scendere da dove è stata aperta.
            x = (a.left + a.right) / 2 - w / 2;
        } else {
            x = a.left;
        }

        // ── Quanto scende la lingua ──────────────────────────────────────
        //
        // Se il pannello sa quanto è alto il suo contenuto, si ferma lì: una
        // lingua lunga con mezzo pannello vuoto è la cosa che più fa sembrare
        // una shell approssimativa.
        //
        // ── E il numero del registro NON è più un tetto ──────────────────
        //
        // Lo era, e il 2 settembre 2026 si è visto cosa vuol dire. Il registro
        // diceva `"control": { height: 470 }`, il pannello Controlli nel
        // frattempo era cresciuto — la riga di cosa sta suonando, «Trasmetti»,
        // «Animazioni» — e `Math.min` tagliava il resto. Sullo schermo restava
        // una fila di tre pulsanti (Impostazioni, Scorciatoie, Sistema)
        // **tagliata a metà**, visibile per pochi pixel.
        //
        // Giacomo: «non si adatta al contenuto la sezione del desktop dedicata
        // alla connessione trasmetti eccetera perché i 3 tasti sotto sono a
        // malapena visibili». Nessun errore da nessuna parte: un numero scritto
        // a mano che il contenuto ha superato, e che nessuno aggiorna perché
        // nessuno sa che esiste.
        //
        // Adesso il tetto è lo SPAZIO CHE C'È — lo schermo meno la barra e i
        // margini — e il numero del registro serve solo a chi non sa dire
        // quanto è alto. Un pannello che cresce si adatta; un pannello più
        // alto dello schermo si ferma allo schermo, e da lì in poi tocca a lui
        // farsi scorrere.
        var tetto = Math.max(120, spine.height - spine.barHeight - margin * 2);
        var h = Math.min(def.height, tetto);
        var item = panelLoader.item;
        if (item && item.implicitPanelHeight !== undefined && item.implicitPanelHeight > 0)
            h = Math.min(tetto, item.implicitPanelHeight);

        spine.targetX = Math.max(margin, Math.min(x, spine.width - w - margin));
        spine.targetWidth = w;
        spine.targetHeight = h;
    }

    function open(name) {
        if (spine.registry[name] === undefined)
            return;
        Core.Overlays.claim("spine:" + name);
        spine.activePanel = name;
        spine.layoutPanel();
    }

    function close() {
        if (spine.activePanel === "")
            return;
        Core.Overlays.release("spine:" + spine.activePanel);
        spine.activePanel = "";
        spine.targetHeight = 0;
    }

    function toggle(name) {
        if (spine.activePanel === name)
            spine.close();
        else
            spine.open(name);
    }

    onWidthChanged: layoutPanel()

    Connections {
        target: Core.Overlays
        function onDismissOthers(keep) {
            if (spine.activePanel !== "" && keep !== "spine:" + spine.activePanel)
                spine.close();
        }
    }

    // ── Zone realmente cliccabili ────────────────────────────────────────
    //
    // Senza questa maschera la finestra, alta quanto lo schermo, ingoierebbe
    // ogni clic destinato alle finestre sottostanti.
    mask: Region {
        // La barra, sempre.
        Region {
            x: 0
            y: spine.bordoBarra
            width: spine.width
            height: spine.barHeight
        }
        // La lingua del pannello. Un margine in più include i raccordi
        // concavi, che sporgono lateralmente oltre il rettangolo.
        //
        // La lingua è quella ANIMATA (`membrane.panelHeight`), non il
        // bersaglio: mentre scende o sale la zona cliccabile deve coincidere
        // con quello che si vede, non con dove arriverà.
        Region {
            x: membrane.panelX - Theme.Effects.shoulder
            y: spine.inBasso ? spine.bordoBarra - membrane.panelHeight
                             : spine.barHeight
            width: membrane.panelWidth + Theme.Effects.shoulder * 2
            height: membrane.panelHeight
        }
        // ── E con un pannello aperto, tutto il resto fino alla dock ──────
        //
        // Serve per ricevere il clic che chiude il pannello. Mentre un
        // pannello è aperto il fuoco ce l'ha questa superficie, e sotto
        // Hyprland una superficie separata non riceveva mai un clic: provate
        // e buttate, il 2 agosto, tre versioni diverse.
        //
        // Arriva fino in FONDO, dock compresa. Sembra sbagliato e non lo è:
        // con il fuoco esclusivo la dock il puntatore non lo vedrebbe comunque
        // (verificato rimettendo la maschera com'era: restava giù lo stesso).
        // Vedendolo noi, possiamo dirglielo — vedi `puntatoreInBasso`.
        Region {
            x: 0
            y: spine.inBasso ? 0 : spine.barHeight
            width: spine.activePanel !== "" ? spine.width : 0
            height: Math.max(0, spine.height - spine.barHeight)
        }
    }

    // ── La superficie ────────────────────────────────────────────────────

    // Il raccoglitore dei clic fuori. Sta PRIMA della membrana, quindi sotto:
    // i clic sulla barra e dentro il pannello li prende la membrana, tutto il
    // resto arriva qui.
    // ── Il raccoglitore, e la dock ───────────────────────────────────────
    //
    // Sta PRIMA della membrana, quindi sotto: i clic sulla barra e dentro il
    // pannello li prende la membrana, tutto il resto arriva qui e chiude.
    //
    // Riferisce anche dove sta il puntatore, e serve a rimettere in piedi una
    // cosa che era rotta da prima: **con un pannello aperto la dock non usciva
    // più al passaggio del mouse**. La ragione è che questa superficie prende
    // il fuoco in modo esclusivo (per poter scrivere nella ricerca senza
    // cliccare), e da quel momento la dock — che è un'altra superficie — il
    // puntatore non lo vede più.
    //
    // Verificato che non fosse colpa della maschera: rimettendola esattamente
    // com'era prima, la dock restava giù lo stesso.
    //
    // Siccome il puntatore lo riceviamo noi, lo diciamo noi alla dock.
    MouseArea {
        id: raccoglitore
        anchors.fill: parent
        enabled: spine.activePanel !== ""
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onPressed: spine.close()
    }

    /// Il puntatore è dove aspetta la dock.
    ///
    /// ── Perché deve dirglielo la Spine ───────────────────────────────────
    ///
    /// Con un pannello aperto questa superficie ha il fuoco ESCLUSIVO, e
    /// questa superficie copre tutto fino alla dock (vedi sopra): gli eventi
    /// del puntatore li riceve lei, anche sopra la dock.
    ///
    /// Conseguenza: con il menu aperto la dock non usciva più al passaggio del
    /// mouse, perché il puntatore non lo vedeva più. Siccome lo vediamo noi,
    /// glielo passiamo.
    /// ── E perché adesso è un contenimento e non un «più in basso di» ─────
    ///
    /// Diceva `mouseY >= dockBand.y`, cioè «il puntatore è sceso oltre la cima
    /// della dock»: vero finché la dock stava in fondo e basta. Con la dock in
    /// alto quella condizione è vera su tutto lo schermo TRANNE la dock — la
    /// risposta esatta al contrario, e senza nessun errore da nessuna parte.
    /// Si guarda se il punto sta dentro il rettangolo, che è quello che la
    /// domanda ha sempre voluto dire.
    readonly property bool puntatoreSullaDock:
        spine.activePanel !== "" && raccoglitore.containsMouse
        && raccoglitore.mouseX >= spine.dockBand.x
        && raccoglitore.mouseX <= spine.dockBand.x + spine.dockBand.width
        && raccoglitore.mouseY >= spine.dockBand.y
        && raccoglitore.mouseY <= spine.dockBand.y + spine.dockBand.height



    Ui.Membrane {
        id: membrane
        anchors.fill: parent
        barHeight: spine.barHeight
        inBasso: spine.inBasso

        panelX: spine.targetX
        panelWidth: spine.targetWidth
        panelHeight: spine.targetHeight

        // La lingua si estende con un accenno di elastico e si ritira secca.
        Behavior on panelHeight {
            NumberAnimation {
                duration: spine.targetHeight > 0 ? Theme.Motion.surface
                                                 : Theme.Motion.exit
                easing.type: Easing.Bezier
                easing.bezierCurve: spine.targetHeight > 0 ? Theme.Motion.emerge
                                                           : Theme.Motion.retract
            }
        }

        // Passando da un pannello all'altro la lingua SCIVOLA invece di
        // chiudersi e riaprirsi: è la morfosi che rende la superficie viva.
        //
        // ── MA SOLO SE C'ERA GIÀ UNA LINGUA ──────────────────────────────
        //
        // `close()` azzera l'altezza e lascia dov'erano la posizione e la
        // larghezza. Riaprendo un ALTRO pannello, quei due valori partivano
        // quindi da quelli del pannello di prima: la lingua nasceva sotto il
        // pulsante sbagliato e ci scivolava sopra mentre cresceva. Giacomo:
        // «l'animazione parte dalla penultima voce per poi ingrandirsi mano
        // mano verso quello che clicco, il che è strano».
        //
        // Ha ragione, ed è strano perché racconta una cosa falsa: quel
        // pannello non stava lì un istante prima, era chiuso. Lo scivolamento
        // ha senso solo fra due pannelli entrambi APERTI — lì la superficie si
        // trasforma davvero. A lingua chiusa, posizione e larghezza saltano al
        // punto giusto senza animarsi, e cresce solo l'altezza: la lingua
        // scende da sotto il pulsante che si è premuto, che è la verità.
        Behavior on panelX {
            enabled: membrane.panelHeight > 0.5
            NumberAnimation {
                duration: Theme.Motion.panel
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.Motion.standard
            }
        }
        Behavior on panelWidth {
            enabled: membrane.panelHeight > 0.5
            NumberAnimation {
                duration: Theme.Motion.panel
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.Motion.standard
            }
        }
    }

    // ── Contenuto della barra ────────────────────────────────────────────

    Item {
        id: barArea
        width: parent.width
        y: spine.bordoBarra
        height: spine.barHeight

        // Cliccare un punto VUOTO della barra chiude il pannello aperto.
        //
        // Il raccoglitore di clic «fuori dal pannello» copre tutto lo schermo
        // tranne la barra — deve, o si mangerebbe i clic sui pulsanti della
        // barra stessa. Il risultato però era che la barra restava l'unico
        // posto dove cliccare non chiudeva niente: aperto il calendario, si
        // cliccava accanto all'orologio e non succedeva nulla. Segnalato da
        // Giacomo: «se clicco su calendario e poi su una parte vuota della
        // barra dovrebbe chiudersi».
        //
        // Dichiarata PRIMA di `BarContent`, quindi sotto: i pulsanti si
        // prendono i loro clic e qui arriva solo ciò che non ha colpito
        // niente.
        MouseArea {
            anchors.fill: parent
            enabled: spine.activePanel !== ""
            acceptedButtons: Qt.LeftButton
            onClicked: spine.close()
        }

        // ── Il tasto destro sulla barra ──────────────────────────────────
        //
        // Giacomo, 9 settembre 2026: «tranne il caso in cui io decida di
        // sbloccarli via tasto destro sulla barra e cliccare personalizza
        // desktop».
        //
        // Sotto `BarContent`, come quella qui sopra: i pulsanti si prendono i
        // loro clic e qui arriva solo il tasto destro sul vuoto della barra —
        // che è dove uno lo cerca, perché sui pulsanti si aspetta il menù del
        // pulsante.
        //
        // La posizione si passa in coordinate dello SCHERMO: il menù nasce
        // dove è nato il clic, e la barra può stare in alto o in basso.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: function (mouse) {
                var p = mapToGlobal(mouse.x, mouse.y);
                spine.menuBarraChiesto(Qt.point(p.x, p.y));
            }
        }

        BarContent {
            anchors.fill: parent
            spine: spine
            unreadCount: Core.Notifications.unread
            onCheatsheetRequested: spine.cheatsheetRequested()
            onWindowMenuRequested: function(where) { spine.windowMenuRequested(where); }
        }
    }

    // ── Contenuto del pannello ───────────────────────────────────────────

    // È un `FocusScope` e non un `Item` per una ragione precisa: dentro ci
    // sta il pannello, e alcuni pannelli hanno una casella in cui si scrive.
    // Uno scope passa il fuoco al proprio figlio che lo chiede (la casella di
    // ricerca) e se lo tiene lui quando nessuno lo chiede (il calendario) —
    // così i tasti arrivano sempre a qualcuno, e quelli che nessuno consuma
    // risalgono fin qui, dove Esc chiude.
    //
    // Prima l'Esc stava su un Item fratello con `focus: true`, che era
    // esattamente il modo di strappare il fuoco alla casella di ricerca un
    // istante dopo che se l'era preso.
    FocusScope {
        id: panelArea
        x: membrane.panelX
        // Con la barra in basso la lingua sale: il suo bordo ALTO si muove
        // mentre cresce, e va legato all'altezza animata — non al bersaglio,
        // o il contenuto scivolerebbe di quanto manca all'arrivo.
        y: spine.inBasso ? spine.bordoBarra - membrane.panelHeight
                         : spine.barHeight
        width: membrane.panelWidth
        height: membrane.panelHeight
        clip: true

        focus: spine.activePanel !== ""
        Keys.onEscapePressed: spine.close()

        Loader {
            id: panelLoader

            // ── Le misure di DESTINAZIONE, non quelle animate ────────────
            //
            // Il contenuto si dispone subito nella forma finale e viene
            // svelato dalla lingua che scende, invece di riorganizzarsi a
            // ogni frame. `panelArea` ritaglia (`clip`), quindi finché la
            // lingua è a metà se ne vede la metà: è esattamente l'effetto
            // voluto.
            //
            // ── E soprattutto: qui si chiudeva un anello ─────────────────
            //
            // C'era scritto `anchors.fill: parent`, sopra questo commento che
            // diceva già il contrario — il codice era stato cambiato e il
            // commento lasciato lì, che è il modo in cui un commento comincia
            // a mentire.
            //
            // L'anello era questo, e girava sessanta volte al secondo:
            //
            //     targetHeight → panelHeight (animata) → panelArea.height
            //       → altezza del Loader → il pannello si ridispone
            //       → implicitPanelHeight cambia → onImplicitPanelHeightChanged
            //       → layoutPanel() → targetHeight
            //
            // Ogni fotogramma dell'animazione ne cambiava il bersaglio.
            // Quickshell lo diceva: «Binding loop detected for property
            // panelHeight». Legandosi al bersaglio invece che al valore
            // animato, l'anello si spezza nel punto giusto: il contenuto ha
            // una misura sola per tutta la discesa.
            //
            // ── E la `y` invece segue la lingua, ma solo in basso ────────
            //
            // Con la barra in alto la lingua scende: il bordo ALTO di
            // `panelArea` sta fermo, il contenuto si appoggia lì e viene
            // svelato. Con la barra in basso la lingua sale, e il bordo che
            // sta fermo è quello DI SOTTO: un contenuto appoggiato in cima
            // scivolerebbe verso l'alto insieme alla lingua invece di essere
            // scoperto. Si appoggia al bordo fermo, e si scopre dal lato che
            // tocca la barra — che è la stessa cosa che succede in alto,
            // vista allo specchio.
            //
            // Questa `y` usa l'altezza ANIMATA e non il bersaglio, e non
            // riapre l'anello descritto qui sopra: il Loader resta alto
            // `targetHeight`, quindi il pannello si dispone una volta sola.
            // Si muove il punto in cui è appeso, non la sua misura.
            x: 0
            y: spine.inBasso ? panelArea.height - spine.targetHeight : 0
            width: spine.targetWidth
            height: spine.targetHeight

            asynchronous: false
            active: spine.activePanel !== ""
            source: spine.activePanel !== "" && spine.registry[spine.activePanel]
                    ? spine.registry[spine.activePanel].source
                    : ""

            onLoaded: {
                if (item && item.spine !== undefined)
                    item.spine = spine;
                spine.layoutPanel();
            }
        }

        // Il contenuto di alcuni pannelli cambia altezza mentre sono aperti
        // (l'elenco appunti che arriva, la conferma di spegnimento che si
        // espande): la lingua li segue invece di lasciare un vuoto.
        Connections {
            target: panelLoader.item
            ignoreUnknownSignals: true
            function onImplicitPanelHeightChanged() { spine.layoutPanel(); }
        }

        // Il contenuto entra dopo che la lingua ha cominciato a scendere:
        // vederlo comparire nel vuoto rovinerebbe l'illusione della superficie
        // che si estende.
        opacity: membrane.panelHeight > 40 ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.Motion.quick }
        }
    }

    // ── Chiusura ─────────────────────────────────────────────────────────

    // Superficie invisibile che copre il resto dello schermo per raccogliere
    // i clic fuori dal pannello. Vive in una finestra a parte perché la
    // maschera della Spine esclude di proposito tutto il resto.
    //
    // Sta su `Overlay` e NON su `Bottom`, ed è tutta la differenza fra un
    // pannello che si chiude cliccando fuori e uno che non si chiude mai. Il
    // livello `Bottom` sta SOTTO le finestre dei programmi: un raccoglitore
    // di clic messo lì non riceve niente, perché qualunque finestra aperta
    // intercetta il clic prima di lui, e la scrivania se lo prende comunque.
    // Sopra tutto, invece, il clic arriva sempre.
    //
    // Il prezzo è che una superficie sopra tutto si mangerebbe anche i clic
    // sulla barra e sul pannello stesso. Da qui la maschera: dichiara come
    // cliccabile TUTTO TRANNE la barra, la lingua e la dock. È il negativo
    // esatto della maschera della Spine.
}

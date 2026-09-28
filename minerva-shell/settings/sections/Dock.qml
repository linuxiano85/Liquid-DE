import QtQuick
import Quickshell
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// Barra, dock e bordi — tutto quello che sta attorno alle finestre: la barra,
// la dock, la Riva (angoli, bordi, l'Isola) e il menù delle applicazioni.
// Dal 28 settembre 2026 raccoglie «Dock e barra», «La Riva» e il menù che
// stava in «Minerva».
Page {
    id: page

    title: Core.Strings.lang === "it" ? "Barra, dock e bordi" : "Bar, dock and edges"
    subtitle: Core.Strings.lang === "it"
              ? "La barra, la dock, gli angoli e i bordi dello schermo, il menù delle applicazioni"
              : "The bar, the dock, the screen corners and edges, the application menu"

    readonly property bool it: Core.Strings.lang === "it"
    /// Vero con l'acquerello dietro barra e pannelli: la trasparenza della
    /// barra ha allora una memoria sua (vedi `theme/LegaTema.qml`).
    readonly property bool _colFiltro: Core.Vetro.filtroChiesto
    /// Il modo in vigore, leggendo anche il valore vecchio.
    ///
    /// Chi aveva già Minerva installata ha `dock.autoHide` e non ha mai
    /// sentito parlare di `dock.modo`: leggendo solo la chiave nuova, la sua
    /// dock cambierebbe comportamento da sola al primo avvio. Lo stesso conto
    /// sta in `shell.qml`, ed è l'unico posto in cui è ripetuto — qui serve a
    /// mostrare la voce giusta come già selezionata.
    readonly property string modo: {
        var m = String(Core.Ipc.get("dock.modo", ""));
        if (m === "sempre" || m === "nascondi" || m === "elude")
            return m;
        return Core.Ipc.get("dock.autoHide", false) ? "nascondi" : "sempre";
    }
    /// L'angolo toccato nella miniatura: la scelta qui sotto è la sua.
    property string angoloScelto: "bassoSx"
    readonly property var nomiAngoli: ({
        "altoSx": "in alto a sinistra", "altoDx": "in alto a destra",
        "bassoSx": "in basso a sinistra", "bassoDx": "in basso a destra"
    })
    /// Le categorie del menu applicazioni che si possono nascondere.
    /// «Preferiti» e «Tutte» non ci sono di proposito: sono le vie d'uscita.
    ///
    /// Stanno anche in `spine/panels/AppsPanel.qml`, e si ripetono qui per una
    /// ragione sola: quel pannello vive e muore con la propria apertura, e le
    /// Impostazioni devono poterle elencare anche a menu chiuso.
    function categoriaVisibile(id) {
        return Core.Ipc.get("launcher.hiddenCategories", []).indexOf(id) === -1;
    }
    function mostraCategoria(id, mostra) {
        var nascoste = Core.Ipc.get("launcher.hiddenCategories", []).slice();
        var i = nascoste.indexOf(id);
        if (mostra && i !== -1)
            nascoste.splice(i, 1);
        else if (!mostra && i === -1)
            nascoste.push(id);
        Core.Ipc.setSetting("launcher.hiddenCategories", nascoste);
    }
    /// Le categorie fra cui si può scegliere quella d'apertura. Una categoria
    /// nascosta non c'è: il menu si aprirebbe su una voce che nella colonna
    /// non esiste più.
    function opzioniApertura() {
        var o = [
            { "value": "favorites", "label": page.it ? "Preferiti" : "Favourites" },
            { "value": "all",       "label": page.it ? "Tutte" : "All" }
        ];
        // L'elenco può non esserci ancora: questa funzione viene chiamata
        // mentre la pagina si costruisce, e una proprietà dichiarata più sotto
        // a quel punto è `undefined`. Senza la rete, le Impostazioni si
        // aprivano con un avviso e la scelta vuota.
        var tutte = page.categorieMenu || [];
        for (var i = 0; i < tutte.length; i++) {
            var c = tutte[i];
            if (!page.categoriaVisibile(c.id))
                continue;
            o.push({ "value": c.id, "label": page.it ? c.it : c.en });
        }
        return o;
    }
    readonly property var categorieMenu: [
        { "id": "internet",    "it": "Internet",   "en": "Internet" },
        { "id": "development", "it": "Sviluppo",   "en": "Development" },
        { "id": "office",      "it": "Ufficio",    "en": "Office" },
        { "id": "graphics",    "it": "Grafica",    "en": "Graphics" },
        { "id": "media",       "it": "Multimedia", "en": "Media" },
        { "id": "games",       "it": "Giochi",     "en": "Games" },
        { "id": "system",      "it": "Sistema",    "en": "System" },
        { "id": "utility",     "it": "Utility",    "en": "Utility" }
    ]
    // ── Dove stanno ──────────────────────────────────────────────────────
    //
    // `bar.position` esisteva dal primo giorno, valeva `'top'`, si poteva
    // scrivere — e non la leggeva nessuno. Una impostazione che si può
    // cambiare e non fa niente è peggio di una che manca: chi la cambia
    // conclude che la scrivania è rotta, e ha ragione.
    //
    // I lati non ci sono, e non per dimenticanza: barra e dock sono costruite
    // in orizzontale — la lingua dei pannelli scende, le icone crescono verso
    // l'interno — e metterle di fianco non è un ancoraggio diverso, è
    // un'altra geometria. Prometterlo qui con una voce che poi fa una cosa
    // storta sarebbe lo stesso difetto di prima.
    Card {
        heading: page.it ? "Dove stanno" : "Where they sit"

        // ── Non si può più metterle una sull'altra ───────────────────────
        //
        // Qui c'era un avviso: «mettere le due cose dalla stessa parte è
        // permesso — con due schermi può perfino servire — ma chi lo fa deve
        // saperlo». Giacomo ha deciso il contrario, e il ragionamento non
        // reggeva comunque: chi ha due schermi ha una barra sola e una dock
        // sola, e sovrapporle non serve a nessuno.
        //
        // Adesso spostarne una **sposta l'altra**, e il riquadro lo dice
        // prima. La regola vera non è qui, è in `core/Posizioni.qml`: questo
        // file scrive le due chiavi in coppia perché il movimento si VEDA,
        // ma anche scrivendo `settings.json` a mano non si torna indietro.
        note: page.it
              ? "Stanno sempre su bordi opposti: spostandone una, l'altra la segue."
              : "They always sit on opposite edges: move one and the other follows."

        S.SettingRow {
            width: parent.width
            label: page.it ? "La barra" : "The bar"
            description: page.it
                ? "L'orologio, la rete, il volume, e i pannelli che ne scendono"
                : "The clock, network, volume, and the panels that drop from it"
            controlWidth: 260
            control: S.ChoicePicker {
                value: Core.Posizioni.barraInBasso ? "basso" : "alto"
                options: [
                    { "value": "alto",  "label": page.it ? "In alto" : "Top" },
                    { "value": "basso", "label": page.it ? "In basso" : "Bottom" }
                ]
                onPicked: function(v) {
                    // In coppia, e in un messaggio solo: due `setSetting` di
                    // fila sarebbero due scritture su disco e due
                    // ricostruzioni del tema, con un istante in cui la
                    // scrivania è mezza in un modo e mezza nell'altro.
                    if (Core.Ipc.get("dock.enabled", true))
                        Core.Ipc.setSettings({
                            "bar.position": v,
                            "dock.position": v === "alto" ? "basso" : "alto"
                        });
                    else
                        Core.Ipc.setSetting("bar.position", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("dock.enabled", true)
            label: page.it ? "La dock" : "The dock"
            description: page.it
                ? "Le icone crescono verso l'interno dello schermo, da qualunque parte stia"
                : "Icons grow towards the middle of the screen, whichever side it is on"
            controlWidth: 260
            control: S.ChoicePicker {
                value: Core.Posizioni.dockInAlto ? "alto" : "basso"
                options: [
                    { "value": "basso", "label": page.it ? "In basso" : "Bottom" },
                    { "value": "alto",  "label": page.it ? "In alto" : "Top" }
                ]
                onPicked: function(v) {
                    Core.Ipc.setSettings({
                        "dock.position": v,
                        "bar.position": v === "alto" ? "basso" : "alto"
                    });
                }
            }
        }
    }
    Card {
        heading: page.it ? "Come sta sullo schermo" : "How it sits on screen"

        S.SettingRow {
            width: parent.width
            label: page.it ? "Mostra la dock" : "Show the dock"
            description: page.it
                ? "La fila di icone in basso: cosa sta girando e cosa si apre spesso"
                : "The row of icons at the bottom: what is running and what you open often"
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("dock.enabled", true)
                onToggled: function(v) { Core.Ipc.setSetting("dock.enabled", v); }
            }
        }

        // ── I tre modi ───────────────────────────────────────────────────
        //
        // Non una levetta «si nasconde sì/no»: sono tre situazioni diverse, e
        // la terza — quella che Giacomo ha chiesto — non si può dire con un
        // sì e un no.
        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("dock.enabled", true)
            label: page.it ? "Quando si toglie di mezzo" : "When it steps aside"
            description: page.it
                ? "«Elude le finestre» è il modo di tutti i giorni: la dock c'è quando lo schermo è libero, e si ritira quando una finestra arriva sopra di lei"
                : "“Dodge windows” is the everyday choice: the dock is there when the screen is free, and steps back when a window reaches it"
            // ── Trecento non bastavano ───────────────────────────────
            //
            // Con tre voci e questi nomi, a `controlWidth: 300` la terza
            // usciva dal bordo: sullo schermo si leggeva «Si nascon…».
            // Visto guardando la fotografia, non leggendo il codice — ed è
            // esattamente il tipo di difetto per cui questo piano ha la
            // regola di guardare.
            //
            // Il numero è la larghezza che serve alle tre voci più lunghe in
            // italiano; l'inglese è più corto e ci sta comodo.
            controlWidth: 400

            control: S.ChoicePicker {
                value: page.modo
                options: [
                    { "value": "sempre",
                      "label": page.it ? "Sempre" : "Always" },
                    { "value": "elude",
                      "label": page.it ? "Elude le finestre" : "Dodge windows" },
                    { "value": "nascondi",
                      "label": page.it ? "Si nasconde" : "Hide" }
                ]
                onPicked: function(v) {
                    Core.Ipc.setSetting("dock.modo", v);
                    // Si tiene allineato anche il valore vecchio: se un giorno
                    // si torna indietro con una versione di prima, la dock si
                    // comporta come ci si aspetta invece di dimenticarsene.
                    Core.Ipc.setSetting("dock.autoHide", v === "nascondi");
                }
            }
        }
    }
    // ── La barra ─────────────────────────────────────────────────────────
    //
    // `bar.showAppMenuButton` stava nei valori di fabbrica dal primo giorno e
    // per mesi la sua UNICA occorrenza in tutto il progetto era la riga che la
    // dichiarava. È stata collegata al pulsante il 4 settembre 2026, e da
    // allora funziona — ma restava senza un posto da cui toccarla, che è
    // mezza correzione.
    Card {
        heading: page.it ? "La barra" : "The bar"

        S.SettingRow {
            width: parent.width
            label: page.it ? "Il pulsante del menu applicazioni"
                           : "The application-menu button"
            description: page.it
                ? "Il rombo di Minerva in alto a sinistra. Il menu si apre "
                  + "comunque con Super."
                : "Minerva's mark at the top left. The menu still opens with Super."
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("bar.showAppMenuButton", true)
                onToggled: function(v) {
                    Core.Ipc.setSetting("bar.showAppMenuButton", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Pulsanti della finestra nella barra" : "Window buttons in the bar"
            description: Core.Strings.t("windowControlsDesc")
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("windowControls.enabled", true)
                onToggled: function(v) { Core.Ipc.setSetting("windowControls.enabled", v); }
            }
        }

        // ── Un attrezzo da officina, e si può riporre ────────────────────
        //
        // Giacomo, 2 settembre 2026: «mettiamo un tasto disattivabile accanto
        // al meteo dove posso riavviare la shell».
        //
        // Sta fra le voci della barra e non fra quelle degli sviluppatori
        // perché è una cosa che si VEDE: chi lo spegne lo spegne perché non
        // vuole quel simbolo lì, non perché ha smesso di sviluppare.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Tasto «ricarica» nella barra"
                           : "«Reload» button in the bar"
            description: page.it
                ? "Accanto al meteo. Rilegge la scrivania restando viva: la barra non sparisce"
                : "Next to the weather. Re-reads the desktop while staying alive: the bar never disappears"
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("shell.tastoRiavvio", true)
                onToggled: function(v) { Core.Ipc.setSetting("shell.tastoRiavvio", v); }
            }
        }

        // ── UN cursore, DUE memorie ──────────────────────────────────────
        //
        // La stessa riga scrive due chiavi diverse secondo cosa c'è dietro la
        // barra, e cambia anche gli estremi. Non è una raffinatezza: col blur
        // acceso il cursore andava da 0,75 a 1,00 e **non faceva niente**,
        // perché la shell teneva comunque il valore sotto 0,75. Misurato il
        // 9 settembre 2026 muovendolo da un capo all'altro: 0,0 % di pixel
        // diversi nella fascia della barra. Un cursore che si gira e non
        // cambia niente è il difetto che questo progetto si è messo per
        // iscritto di non commettere.
        //
        // Senza blur dietro c'è una fotografia nitida e sotto 0,75 il testo si
        // perde (il conto sta in `theme/Colors.qml`). Col blur dietro c'è una
        // macchia morbida e scurita, e si può scendere molto di più: misurato
        // il 9 settembre 2026 sulla scrivania di Giacomo, a 0,50 il testo
        // della barra sta a **10,2:1**, cioè più del doppio della soglia di
        // 4,5:1. Sotto quel valore non si scende, ed è prudenza dichiarata:
        // il contrasto dipende dalla FOTOGRAFIA, e la sfocatura appiattisce i
        // dettagli ma non schiarisce né scurisce la media. Su uno sfondo
        // molto chiaro lo stesso 0,50 sarebbe stretto — come del resto lo è
        // già il 0,75 di adesso, che nessuno ha mai misurato su un muro
        // bianco.
        S.SettingRow {
            width: parent.width
            label: Core.Strings.t("membraneOpacity")
            description: page._colFiltro
                ? (page.it
                   ? "Con l'acquerello dietro si può scendere molto di più: "
                     + "quello che passa è una macchia morbida, non una fotografia"
                   : "With watercolour behind you can go much lower: what "
                     + "shows through is a soft wash, not a photograph")
                : Core.Strings.t("membraneOpacityDesc")
            controlWidth: 220

            control: S.ValueSlider {
                width: 220
                from: page._colFiltro ? 0.50 : 0.75
                to: 1.0
                value: page._colFiltro
                       ? Core.Ipc.get("shell.membraneOpacityBlur", 0.68)
                       : Core.Ipc.get("shell.membraneOpacity", 0.93)
                onReleased: function(v) {
                    Core.Ipc.setSetting(page._colFiltro
                                        ? "shell.membraneOpacityBlur"
                                        : "shell.membraneOpacity",
                                        Math.round(v * 100) / 100);
                }
            }
        }
    }
    Card {
        heading: page.it ? "Aspetto" : "Look"
        visible: Core.Ipc.get("dock.enabled", true)

        S.SettingRow {
            width: parent.width
            label: page.it ? "Dimensione delle icone" : "Icon size"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 32
                to: 72
                unit: "pixel"
                value: Core.Ipc.get("dock.iconSize", 48)
                onReleased: function(v) {
                    Core.Ipc.setSetting("dock.iconSize", Math.round(v));
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Ingrandimento al passaggio" : "Magnification"
            description: page.it
                ? "Quanto cresce l'icona sotto il puntatore. Tutto a sinistra: spento"
                : "How much the icon under the pointer grows. Fully left: off"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                // Uno esatto vuol dire «non crescere»: il cursore ha lo
                // spegnimento dentro di sé invece di in un interruttore a parte.
                from: 1.0
                to: 2.0
                value: Core.Ipc.get("dock.magnification", 1.6)
                onReleased: function(v) {
                    Core.Ipc.setSetting("dock.magnification",
                                        Math.round(v * 20) / 20);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Estensione dell'ingrandimento" : "Magnification reach"
            description: page.it
                ? "Quante icone attorno a quella puntata si sollevano con lei"
                : "How many icons around the pointed one rise with it"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 1.0
                to: 4.0
                unit: "numero"
                value: Core.Ipc.get("dock.reach", 2.2)
                onReleased: function(v) {
                    Core.Ipc.setSetting("dock.reach", Math.round(v * 10) / 10);
                }
            }
        }

        // Un cursore, due memorie: col blur vero del compositore dietro, la
        // dock si può aprire molto di più. Vedi la stessa riga in
        // `sections/Appearance.qml`, dove c'è il perché per esteso.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Trasparenza della dock" : "Dock transparency"
            description: Core.Vetro.filtroChiesto
                ? (page.it
                   ? "Con l'acquerello dietro si può scendere molto di più"
                   : "With watercolour behind you can go much lower")
                : ""
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 0.4
                to: 1.0
                value: Core.Vetro.filtroChiesto
                       ? Core.Ipc.get("dock.opacityBlur", 0.68)
                       : Core.Ipc.get("dock.opacity", 0.90)
                onReleased: function(v) {
                    Core.Ipc.setSetting(Core.Vetro.filtroChiesto
                                        ? "dock.opacityBlur" : "dock.opacity",
                                        Math.round(v * 100) / 100);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Nome al passaggio" : "Name on hover"
            description: page.it
                ? "L'etichetta col nome del programma sopra l'icona puntata"
                : "The label with the program name above the pointed icon"
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("dock.showLabels", true)
                onToggled: function(v) {
                    Core.Ipc.setSetting("dock.showLabels", v);
                }
            }
        }
    }
    // ── Lo schermo in miniatura ─────────────────────────────────────────
    Card {
        heading: page.it ? "Il tuo schermo" : "Your screen"
        note: page.it
            ? "Tocca un angolo e scegli che cosa fa. Tocca l'Isola per nasconderla o tenerla sempre. ⇄ scambia i bordi."
            : "Tap a corner and choose what it does. Tap the Island to hide it or keep it. ⇄ swaps the edges."

        Item {
            id: miniatura
            width: parent.width
            height: Math.min(340, Math.round(width * 0.56))

            readonly property bool dockInAlto: Core.Posizioni.dockInAlto
            readonly property bool barraInBasso: Core.Posizioni.barraInBasso

            // Lo schermo: un fondo che prende l'accento, come uno sfondo.
            Rectangle {
                id: schermo
                anchors.fill: parent
                anchors.margins: 2
                radius: 20
                clip: true
                border.width: 1
                border.color: Theme.Colors.edge
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Qt.tint(Theme.Colors.raised, Qt.alpha(Theme.Colors.accent, 0.30)) }
                    GradientStop { position: 1.0; color: Qt.tint(Theme.Colors.sunken, Qt.alpha(Theme.Colors.accent, 0.08)) }
                }

                // Il TUO sfondo: la miniatura deve sembrare il tuo schermo, non
                // uno schema. Disegnato in una Canvas tagliata a rettangolo
                // tondo: col renderer del processore `clip` taglia diritto, e
                // coprire gli angoli col colore della carta non si può — la
                // finestra può essere trasparente, e sotto c'è la scrivania.
                // La Canvas disegna una copia piccola (640 px, `fonte`), non
                // lo sfondo intero.
                // La copia piccola sta fuori dallo schermo (tagliata via dal
                // `clip`) e se ne fa una fotografia (`grabToImage`): la Canvas
                // disegna la fotografia, non un Image — un Image passato a
                // `drawImage` qui non si disegnava. Caricare lo sfondo intero
                // nella Canvas funzionerebbe, ma sono 33 MB per uno sfondo 4K
                // solo per disegnare una miniatura.
                Image {
                    id: fonte
                    x: -width - 10
                    width: 640; height: 360
                    source: Core.Wallpaper.current !== "" ? "file://" + Core.Wallpaper.current : ""
                    sourceSize.width: 640
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    property string foto: ""
                    onStatusChanged: {
                        if (status !== Image.Ready)
                            return;
                        // La fotografia si salva in un file piccolo: la Canvas
                        // non sa leggere gli indirizzi `itemgrabber:` (provato:
                        // la foto c'è, `onImageLoaded` non arriva mai).
                        fonte.grabToImage(function(risultato) {
                            var file = Core.Ipc.cartellaRuntime + "/miniatura-sfondo"
                                       + (Quickshell.env("MINERVA_PROVA") ? "-prova" : "") + ".png";
                            if (!risultato.saveToFile(file))
                                return;
                            // Un numero in coda perché la Canvas non riusi la
                            // copia vecchia quando lo sfondo cambia.
                            fonte.foto = "file://" + file + "?" + Date.now();
                            tela.loadImage(fonte.foto);
                        });
                    }
                }
                Canvas {
                    id: tela
                    anchors.fill: parent
                    onImageLoaded: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        var w = width, h = height, r = schermo.radius;
                        ctx.beginPath();
                        ctx.roundedRect(0.5, 0.5, w - 1, h - 1, r, r);
                        ctx.clip();
                        if (fonte.foto !== "" && isImageLoaded(fonte.foto)) {
                            // La fotografia è 640×360, già ritagliata come
                            // `PreserveAspectCrop`: qui si adatta allo schermo
                            // in miniatura, tagliando in mezzo quel che avanza.
                            var iw = 640, ih = 360;
                            var s = Math.max(w / iw, h / ih);
                            var sw = w / s, sh = h / s;
                            ctx.drawImage(fonte.foto, (iw - sw) / 2, (ih - sh) / 2, sw, sh, 0, 0, w, h);
                        }
                        // Il velo, perché bolle e scritte si leggano su
                        // qualunque sfondo.
                        var g = ctx.createLinearGradient(0, 0, 0, h);
                        g.addColorStop(0, "rgba(0,0,0,0.25)");
                        g.addColorStop(1, "rgba(0,0,0,0.45)");
                        ctx.fillStyle = g;
                        ctx.fillRect(0, 0, w, h);
                    }
                }

                // Una finestra, per dare la misura.
                Rectangle {
                    x: parent.width * 0.26; y: parent.height * 0.26
                    width: parent.width * 0.48; height: parent.height * 0.46
                    radius: 10
                    color: Qt.alpha(Theme.Colors.panel, 0.85)
                    border.width: 1
                    border.color: Theme.Colors.edge
                    Rectangle {
                        width: parent.width; height: 14; radius: 10
                        color: Qt.alpha(Theme.Colors.text, 0.06)
                    }
                }

                // La dock.
                Rectangle {
                    visible: Core.Ipc.get("dock.enabled", true) === true
                    width: parent.width * 0.44; height: 16; radius: 8
                    x: (parent.width - width) / 2
                    y: miniatura.dockInAlto ? 10 : parent.height - height - 10
                    color: Qt.alpha(Theme.Colors.panel, 0.9)
                    border.width: 1
                    border.color: Theme.Colors.edge
                    Row {
                        anchors.centerIn: parent
                        spacing: 5
                        Repeater {
                            model: 7
                            delegate: Rectangle { width: 8; height: 8; radius: 3; color: Qt.alpha(Theme.Colors.accent, 0.5 + (index % 3) * 0.15) }
                        }
                    }
                }

                // L'Isola: a scomparsa sbuca per metà dal bordo.
                Rectangle {
                    id: isolaMini
                    readonly property bool nascosta: Core.Ipc.get("bar.aScomparsa", true) === true
                    width: parent.width * 0.3; height: 20; radius: 10
                    x: (parent.width - width) / 2
                    y: miniatura.barraInBasso
                       ? (isolaMini.nascosta ? parent.height - 8 : parent.height - height - 34)
                       : (isolaMini.nascosta ? -12 : 8)
                    Behavior on y {
                        enabled: Theme.Motion.liquido
                        SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
                    }
                    color: Theme.Colors.panel
                    border.width: 1
                    border.color: isolaMouse.containsMouse ? Theme.Colors.accent : Theme.Colors.edge
                    Text {
                        anchors.centerIn: parent
                        visible: !isolaMini.nascosta
                        text: Qt.formatTime(new Date(), "HH:mm") + "  ·  ☁ 22°"
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: 10
                    }
                    MouseArea {
                        id: isolaMouse
                        anchors.fill: parent
                        anchors.margins: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Core.Ipc.setSetting("bar.aScomparsa", !isolaMini.nascosta)
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: miniatura.barraInBasso ? parent.height - 30 : 14
                    visible: isolaMini.nascosta
                    text: page.it ? "l'Isola, a scomparsa" : "the Island, auto-hidden"
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }

                // I bordi di lato: le Stanze e il Cassetto.
                Repeater {
                    model: [ { "sx": true }, { "sx": false } ]
                    delegate: Item {
                        id: bordo
                        required property var modelData
                        readonly property bool cassetto: bordo.modelData.sx === Core.Riva.cassettoASinistra
                        width: 60; height: parent.height * 0.36
                        x: bordo.modelData.sx ? 6 : parent.width - width - 6
                        y: (parent.height - height) / 2
                        Rectangle {
                            width: 6; height: parent.height; radius: 3
                            x: bordo.modelData.sx ? 0 : parent.width - width
                            color: Qt.alpha(Theme.Colors.accent, 0.55)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            x: bordo.modelData.sx ? 12 : parent.width - width - 12
                            text: bordo.cassetto ? (page.it ? "Appunti" : "Clipboard")
                                                 : (page.it ? "Stanze" : "Rooms")
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                            font.weight: Theme.Typography.weightMedium
                        }
                    }
                }

                // ⇄: scambia i bordi.
                Rectangle {
                    width: 34; height: 34; radius: 17
                    x: (parent.width - width) / 2
                    y: parent.height * 0.72 + 8
                    color: scambioMouse.containsMouse ? Qt.alpha(Theme.Colors.accent, 0.3) : Theme.Colors.raised
                    border.width: 1
                    border.color: Theme.Colors.edge
                    Text {
                        anchors.centerIn: parent
                        text: "⇄"
                        color: Theme.Colors.text
                        font.pixelSize: 16
                    }
                    MouseArea {
                        id: scambioMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Core.Ipc.setSetting("riva.cassetto",
                                                       Core.Riva.cassettoASinistra ? "destra" : "sinistra")
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: schermo.radius
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.Colors.edge
                    z: 3
                }

                // Gli angoli: bolle che si toccano.
                Repeater {
                    model: [
                        { "chiave": "altoSx",  "sx": true,  "alto": true },
                        { "chiave": "altoDx",  "sx": false, "alto": true },
                        { "chiave": "bassoSx", "sx": true,  "alto": false },
                        { "chiave": "bassoDx", "sx": false, "alto": false }
                    ]
                    delegate: Item {
                        id: bolla
                        required property var modelData
                        readonly property var azione: {
                            Core.Riva.altoSx; Core.Riva.altoDx; Core.Riva.bassoSx; Core.Riva.bassoDx;
                            return Core.Riva.azione(Core.Riva.angolo(bolla.modelData.chiave));
                        }
                        readonly property bool scelta: page.angoloScelto === bolla.modelData.chiave
                        width: 44; height: 44
                        x: bolla.modelData.sx ? 10 : parent.width - width - 10
                        y: bolla.modelData.alto ? 10 : parent.height - height - 10
                        z: 2

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: bolla.scelta ? Theme.Colors.accent
                                 : bolla.azione.id === "niente" ? Qt.alpha(Theme.Colors.panel, 0.55)
                                 : Theme.Colors.panel
                            border.width: bolla.scelta ? 0 : 1
                            border.color: bollaMouse.containsMouse ? Theme.Colors.accent : Theme.Colors.edge
                            scale: bolla.scelta ? 1.12 : (bollaMouse.pressed ? 0.92 : 1)
                            Behavior on scale {
                                enabled: Theme.Motion.liquido
                                SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
                            }
                            Behavior on color { ColorAnimation { duration: Theme.Motion.quick } }
                            Ui.Icon {
                                anchors.centerIn: parent
                                width: 18; height: 18
                                name: bolla.azione.icona
                                color: bolla.scelta ? Theme.Colors.textOnAccent
                                     : bolla.azione.id === "niente" ? Theme.Colors.textFaint
                                     : Theme.Colors.text
                            }
                        }
                        Text {
                            x: bolla.modelData.sx ? parent.width + 8 : -width - 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.it ? bolla.azione.it : bolla.azione.en
                            color: bolla.scelta ? Theme.Colors.accent : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                            font.weight: Theme.Typography.weightMedium
                        }
                        MouseArea {
                            id: bollaMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.angoloScelto = bolla.modelData.chiave
                        }
                    }
                }
            }
        }

        // La scelta per l'angolo toccato.
        Column {
            width: parent.width
            spacing: Theme.Effects.space2
            topPadding: Theme.Effects.space3
            Text {
                text: (page.it ? "L'angolo " : "The corner ") + page.nomiAngoli[page.angoloScelto]
                      + (page.it ? ": una sosta del puntatore lì" : ": rest the pointer there")
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeMD
                font.weight: Theme.Typography.weightMedium
            }
            S.ChoicePicker {
                width: parent.width
                value: {
                    Core.Riva.altoSx; Core.Riva.altoDx; Core.Riva.bassoSx; Core.Riva.bassoDx;
                    return Core.Riva.angolo(page.angoloScelto);
                }
                options: Core.Riva.azioni.map(function(a) {
                    return { "value": a.id, "label": page.it ? a.it : a.en };
                })
                onPicked: function(v) { Core.Ipc.setSetting("riva.angoli." + page.angoloScelto, v); }
            }
            Text {
                text: page.it ? "↺ Torna agli angoli di serie" : "↺ Back to default corners"
                color: angoliMouse.containsMouse ? Theme.Colors.accent : Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                MouseArea {
                    id: angoliMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Core.Riva.angoliDiSerie()
                }
            }
        }
    }
    // ── La molla ────────────────────────────────────────────────────────
    Card {
        heading: page.it ? "La molla" : "The spring"
        note: page.it
            ? "Com'è il movimento di tutta la riva: menù, Centro, Isola, Cassetto, Stanze. La pallina te lo fa vedere."
            : "How the whole shore moves: menu, Centre, Island, drawer, rooms. The ball shows you."

        // La pallina che va e viene con la molla scelta.
        Item {
            width: parent.width
            height: 56
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: 12; width: parent.width - 24; height: 2; radius: 1
                color: Theme.Colors.edge
            }
            Rectangle {
                id: pallina
                property bool destra: false
                width: 26; height: 26; radius: 13
                anchors.verticalCenter: parent.verticalCenter
                x: pallina.destra ? parent.width - width - 12 : 12
                color: Theme.Colors.accent
                Behavior on x {
                    enabled: Theme.Motion.liquido
                    SpringAnimation { spring: Theme.Motion.molla; damping: Theme.Motion.smorzamento }
                }
                Timer {
                    interval: 1500
                    running: page.visible
                    repeat: true
                    onTriggered: pallina.destra = !pallina.destra
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Carattere" : "Character"
            description: page.it
                ? "Calma si posa senza rimbalzo; Liquida supera di un soffio e torna; Viva è svelta e ondeggia."
                : "Calm settles without bouncing; Liquid overshoots a breath and returns; Lively is quick and sways."
            controlWidth: 280
            control: S.ChoicePicker {
                value: Core.Riva.molla
                options: [
                    { "value": "calma",   "label": page.it ? "Calma" : "Calm" },
                    { "value": "liquida", "label": page.it ? "Liquida" : "Liquid" },
                    { "value": "viva",    "label": page.it ? "Viva" : "Lively" }
                ]
                onPicked: function(v) { Core.Ipc.setSetting("riva.molla", v); }
            }
        }
    }
    // ── L'Isola ─────────────────────────────────────────────────────────
    Card {
        heading: page.it ? "L'Isola" : "The Island"
        visible: Core.Ipc.get("bar.stile", "isola") !== "classica"

        S.SettingRow {
            width: parent.width
            label: page.it ? "A scomparsa" : "Auto-hide"
            description: page.it
                ? "Nascosta oltre il bordo, torna fermando il puntatore lassù: le finestre usano tutto lo schermo."
                : "Hidden past the edge, it comes back when the pointer rests up there."
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("bar.aScomparsa", true) === true
                onToggled: function(v) { Core.Ipc.setSetting("bar.aScomparsa", v); }
            }
        }

        Repeater {
            model: [
                { "chiave": "data",    "it": "La data",            "en": "The date",        "d": "Accanto all'ora" },
                { "chiave": "meteo",   "it": "Il tempo che fa",     "en": "The weather",     "d": "Il simbolo e i gradi" },
                { "chiave": "musica",  "it": "La musica",           "en": "Music",           "d": "Quando qualcosa suona, il titolo e le barrette che respirano" },
                { "chiave": "vassoio", "it": "I programmi del vassoio", "en": "Tray apps",   "d": "Le icone dei programmi che vivono senza finestra" },
                { "chiave": "stato",   "it": "I segni di stato",    "en": "Status",          "d": "Rete, Bluetooth, volume e batteria: toccati, il Centro" }
            ]
            delegate: S.SettingRow {
                required property var modelData
                width: parent.width
                label: page.it ? modelData.it : modelData.en
                description: modelData.d
                controlWidth: 60
                control: S.ToggleSwitch {
                    checked: Core.Ipc.get("isola.mostra." + modelData.chiave, true) !== false
                    onToggled: function(v) { Core.Ipc.setSetting("isola.mostra." + modelData.chiave, v); }
                }
            }
        }

        Text {
            text: page.it ? "↺ L'Isola come di serie" : "↺ Default Island"
            color: isolaSerieMouse.containsMouse ? Theme.Colors.accent : Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            MouseArea {
                id: isolaSerieMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Core.Riva.isolaDiSerie()
            }
        }
    }
    // ── I bordi e il consenso ───────────────────────────────────────────
    Card {
        heading: page.it ? "I bordi" : "The edges"

        S.SettingRow {
            width: parent.width
            label: page.it ? "Da che parte gli appunti" : "Clipboard side"
            description: page.it
                ? "Spingendo il puntatore contro un bordo escono gli Appunti, contro l'altro le Stanze. Si scambiano anche trascinandoli."
                : "Push against one edge for the clipboard, the other for the rooms. Drag them to swap."
            controlWidth: 240
            control: S.ChoicePicker {
                value: Core.Riva.cassettoASinistra ? "sinistra" : "destra"
                options: [
                    { "value": "sinistra", "label": page.it ? "A sinistra" : "Left" },
                    { "value": "destra",   "label": page.it ? "A destra" : "Right" }
                ]
                onPicked: function(v) { Core.Ipc.setSetting("riva.cassetto", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Il consenso di Super" : "Super's consent"
            description: page.it
                ? "Con una finestra che riempie lo schermo, angoli e bordi rispondono solo tenendo Super: niente compare passando col mouse. Tenendo Super salgono l'Isola e la dock."
                : "With a window filling the screen, corners and edges answer only while Super is held."
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Riva.conConsenso
                onToggled: function(v) { Core.Ipc.setSetting("riva.consenso", v); }
            }
        }
    }
    // ── Il menu delle applicazioni ───────────────────────────────────────
    Card {
        heading: page.it ? "Menu applicazioni" : "Application menu"

        S.SettingRow {
            width: parent.width
            label: page.it ? "La rotellina cambia categoria"
                           : "Wheel switches category"
            description: page.it
                ? "Girando la rotellina sul menu si passa da una categoria all'altra, invece di doverle cliccare"
                : "Scrolling over the menu moves between categories instead of clicking them"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("launcher.wheelCategories", true)
                onToggled: function(v) {
                    Core.Ipc.setSetting("launcher.wheelCategories", v);
                }
            }
        }

        // La sorella della riga qui sopra, e stava nei valori di fabbrica
        // senza un posto da cui toccarla: `AppsPanel.qml` la legge, e chi
        // trovava le categorie che cambiano al solo passaggio del mouse non
        // aveva modo di spegnerle.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Basta passarci sopra"
                           : "Hovering is enough"
            description: page.it
                ? "La categoria cambia al solo passaggio del mouse, senza cliccare"
                : "The category changes on hover, without clicking"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("launcher.hoverCategories", true)
                onToggled: function(v) {
                    Core.Ipc.setSetting("launcher.hoverCategories", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Categoria all'apertura" : "Category on opening"
            description: page.it
                ? "Con quale categoria si apre il menu"
                : "Which category the menu opens on"
            controlWidth: 320
            control: S.ChoicePicker {
                value: Core.Ipc.get("launcher.startCategory", "favorites")
                options: page.opzioniApertura()
                onPicked: function(v) {
                    Core.Ipc.setSetting("launcher.startCategory", v);
                }
            }
        }

        // ── Quali categorie si vedono ────────────────────────────────────
        //
        // Erano otto righe con otto interruttori — «Mostra Internet»,
        // «Mostra Sviluppo»… — cioè mezza pagina per una domanda sola. Dal
        // 28 settembre 2026 è una riga con otto pastiglie: accesa, la
        // categoria si vede; un tocco la spegne. Giacomo: «servirebbe
        // riorganizzare tutto in maniera più semplice e compatta».
        S.SettingRow {
            width: parent.width
            label: page.it ? "Categorie nella colonna" : "Categories in the column"
            description: page.it
                ? "Accese si vedono, spente spariscono. «Preferiti» e «Tutte» restano sempre."
                : "Lit ones show, unlit ones disappear. “Favourites” and “All” always stay."
            searchTerms: "categorie menu mostra nascondi internet sviluppo ufficio grafica multimedia giochi sistema utility"
            controlWidth: 380

            control: Flow {
                width: parent ? parent.width : implicitWidth
                spacing: 6

                Repeater {
                    model: page.categorieMenu

                    delegate: Rectangle {
                        id: pastiglia
                        required property var modelData
                        readonly property bool accesa: page.categoriaVisibile(modelData.id)

                        implicitWidth: nomeCat.implicitWidth + 24
                        width: implicitWidth
                        height: 30
                        radius: Theme.Effects.radiusSM
                        color: accesa ? Qt.alpha(Theme.Colors.accent, 0.18)
                                      : (tocco.containsMouse ? Theme.Colors.hover : Theme.Colors.raised)
                        border.width: 1
                        border.color: accesa ? Theme.Colors.accent : Theme.Colors.edge
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: nomeCat.text
                        Accessible.checked: accesa

                        Text {
                            id: nomeCat
                            anchors.centerIn: parent
                            text: page.it ? pastiglia.modelData.it : pastiglia.modelData.en
                            color: pastiglia.accesa ? Theme.Colors.accent : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        MouseArea {
                            id: tocco
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.mostraCategoria(pastiglia.modelData.id, !pastiglia.accesa)
                        }
                    }
                }
            }
        }

    }
}

import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// Aspetto — com'è fatta la scrivania: lo stile, il tema, i colori, le icone, il
// movimento. Dal 28 settembre 2026 qui dentro ci sono anche «Stile» e il
// «Movimento» di «Effetti e animazioni»; lo sfondo e le icone della scrivania
// sono andati in «Scrivania», le finestre in «Finestre». Giacomo: «è diventato
// tutto troppo confusionario e servirebbe riorganizzare tutto in maniera più
// semplice e compatta».
Page {
    id: page

    title: Core.Strings.lang === "it" ? "Aspetto" : "Appearance"
    subtitle: Core.Strings.lang === "it"
              ? "Lo stile, il tema, i colori, le icone e il movimento"
              : "The style, the theme, the colours, the icons and motion"

    readonly property bool it: Core.Strings.lang === "it"
    /// Le chiavi che uno stile tocca. Sono anche quelle che «Libero» si
    /// ricorda: l'elenco è uno solo apposta, o le due cose divergono e
    /// tornando a «Libero» si riprende metà scrivania.
    readonly property var _chiavi: [
        "bar.position", "bar.listaFinestre", "bar.stile",
        "dock.enabled", "dock.position", "dock.modo",
        "dock.iconSize", "dock.magnification",
        "windows.buttonsSide"
    ]
    readonly property var _stili: ({
        // La Riva: al posto della barra l'Isola, una capsula che galleggia in
        // mezzo con l'ora, il tempo, i segni di stato e le notifiche.
        "liquid": {
            "bar.position": "alto",
            "bar.stile": "isola",
            "bar.listaFinestre": false,
            "dock.enabled": true,
            "dock.position": "basso",
            "dock.modo": "sempre",
            "dock.iconSize": 48,
            "dock.magnification": 1.5,
            "windows.buttonsSide": "destra"
        },
        "minerva": {
            "bar.position": "alto",
            "bar.stile": "classica",
            "bar.listaFinestre": false,
            "dock.enabled": true,
            "dock.position": "basso",
            "dock.modo": "sempre",
            "dock.iconSize": 48,
            "dock.magnification": 1.5,
            "windows.buttonsSide": "destra"
        },
        "mac": {
            "bar.position": "alto",
            "bar.stile": "classica",
            "bar.listaFinestre": false,
            "dock.enabled": true,
            "dock.position": "basso",
            // «Elude» e non «sempre»: sul Mac la dock si toglie di mezzo
            // quando una finestra le arriva addosso.
            "dock.modo": "elude",
            "dock.iconSize": 52,
            "dock.magnification": 1.9,
            // Il semaforo sta a sinistra. È la cosa che si nota per prima, e
            // l'unica che nessun altro stile fa.
            "windows.buttonsSide": "sinistra"
        },
        "windows": {
            // Una barra sola, in basso, con dentro le finestre aperte. La
            // dock non c'è: sarebbe la stessa cosa detta due volte.
            "bar.position": "basso",
            "bar.stile": "classica",
            "bar.listaFinestre": true,
            "dock.enabled": false,
            "dock.position": "alto",
            "dock.modo": "sempre",
            "dock.iconSize": 48,
            "dock.magnification": 1.0,
            "windows.buttonsSide": "destra"
        }
    })
    readonly property string attuale: Core.Ipc.get("stile.attuale", "libero")
    /// Fotografa com'è adesso, per poterci tornare.
    function _fotografa() {
        var f = ({});
        for (var i = 0; i < page._chiavi.length; i++) {
            var k = page._chiavi[i];
            f[k] = Core.Ipc.get(k, null);
        }
        return f;
    }
    function applica(nome) {
        if (nome === page.attuale)
            return;

        var mappa = ({});

        // ── Si salva PRIMA di cambiare, e solo la prima volta ────────────
        //
        // Se si è già dentro uno stile, la fotografia da tenere è quella che
        // c'era prima di entrarci: risalvare adesso vorrebbe dire che
        // «Libero» riporta a Mac, cioè che il tuo l'hai perso.
        //
        // La fotografia viaggia come TESTO e non come mappa annidata: le
        // chiavi hanno il punto dentro (`bar.position`), e il demone il punto
        // lo legge come «scendi di un livello». Una riga di JSON non ha
        // questo problema e non chiede di inventarsi un carattere al posto
        // del punto.
        if (page.attuale === "libero")
            mappa["stile.libero"] = JSON.stringify(page._fotografa());

        if (nome === "libero") {
            // Si rimette quello che c'era. Chi non ha mai salvato niente
            // resta com'è: meglio non fare niente che riportare a valori
            // inventati.
            var salvato = null;
            try {
                var testo = String(Core.Ipc.get("stile.libero", ""));
                if (testo !== "")
                    salvato = JSON.parse(testo);
            } catch (e) {
                // Una fotografia illeggibile non deve impedire di cambiare
                // stile: si torna a «libero» senza spostare niente, che è
                // meglio che restare bloccati dentro Windows.
                console.warn("[MINERVA][Stile] fotografia illeggibile:", e);
            }
            if (salvato) {
                for (var chiave in salvato) {
                    if (salvato[chiave] !== null && salvato[chiave] !== undefined)
                        mappa[chiave] = salvato[chiave];
                }
            }
        } else {
            var s = page._stili[nome];
            if (!s)
                return;
            for (var kk in s)
                mappa[kk] = s[kk];
        }

        mappa["stile.attuale"] = nome;
        Core.Ipc.setSettings(mappa);
    }
    readonly property bool accese: Core.Ipc.get("desktop.animations", true)
    // ── I colori messi a mano ────────────────────────────────────────────
    //
    // La mappa sta in `shell.scavalca`, e si scrive intera ogni volta: il
    // demone SOSTITUISCE il valore in fondo al percorso invece di fonderlo,
    // quindi è anche l'unico modo di togliere una voce. Fonderla vorrebbe dire
    // che «rimetti a posto» aggiunge invece di levare.
    readonly property var scavalca: Core.Ipc.get("shell.scavalca", ({})) || ({})
    function _copiaScavalca() {
        var fuori = {};
        var m = page.scavalca;
        for (var k in m)
            if (m[k] !== undefined && m[k] !== null && String(m[k]) !== "")
                fuori[k] = m[k];
        return fuori;
    }
    function mettiColore(nome, esa) {
        var m = page._copiaScavalca();
        m[nome] = String(esa).toUpperCase();
        Core.Ipc.setSetting("shell.scavalca", m);
    }
    function togliColore(nome) {
        var m = page._copiaScavalca();
        delete m[nome];
        Core.Ipc.setSetting("shell.scavalca", m);
    }
    /// Quale riga ha il selettore aperto. Una sola per volta: due quadrati
    /// aperti insieme fanno una pagina alta il doppio dello schermo, e si
    /// perde di vista quello che si sta cambiando.
    property string coloreAperto: ""
    /// «Colori a mano» aperti: acceso se qualche colore è già stato scelto.
    property bool _coloriAMano: Object.keys(page.scavalca || {}).length > 0
    Card {
        heading: page.it ? "Stile della scrivania" : "Desktop style"
        note: page.it
              ? "Scegliendo uno stile, la scrivania che hai adesso viene messa da parte: «Libero» la riprende."
              : "Picking a style puts your current desktop aside: “Free” brings it back."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Stile" : "Style"
            // Cosa cambia lo stile SCELTO, e non tutti e cinque sempre in
            // vista: c'era una scheda intera, «Che cosa cambia», con le
            // cinque spiegazioni aperte (28 settembre 2026).
            description: {
                var d = {
                    "liquid": page.it
                        ? "Al posto della barra l'Isola: una capsula che galleggia in mezzo con l'ora, il tempo, i segni di stato e le notifiche. Si trascina in alto o in basso."
                        : "Instead of the bar, the Island: a capsule floating in the middle with the time, the weather, the status and the notifications. Drag it up or down.",
                    "minerva": page.it
                        ? "Barra in alto, dock in fondo sempre visibile, comandi delle finestre a destra."
                        : "Bar on top, dock always visible at the bottom, window controls on the right.",
                    "mac": page.it
                        ? "Come Minerva, ma la dock ingrandisce di più e si toglie di mezzo quando una finestra le arriva addosso, e i comandi delle finestre stanno a sinistra."
                        : "Like Minerva, but the dock magnifies more and gets out of the way, and the window controls sit on the left.",
                    "windows": page.it
                        ? "Una barra sola in fondo, con dentro le finestre aperte. Niente dock."
                        : "A single bar at the bottom holding the open windows. No dock.",
                    "libero": page.it
                        ? "Quello che avevi messo tu, ripreso com'era."
                        : "Whatever you had set up, brought back as it was."
                };
                return d[page.attuale] || "";
            }
            controlWidth: 460
            control: S.ChoicePicker {
                value: page.attuale
                options: [
                    { "value": "liquid",  "label": "Liquid" },
                    { "value": "minerva", "label": "Minerva" },
                    { "value": "mac",     "label": "Mac" },
                    { "value": "windows", "label": "Windows" },
                    { "value": "libero",  "label": page.it ? "Libero" : "Free" }
                ]
                onPicked: function (v) { page.applica(v); }
            }
        }
    }
    // ── Il tema di colore ────────────────────────────────────────────────
    //
    // Sta per primo, prima ancora dello sfondo, ed è una scelta: è la cosa
    // che cambia di più l'aspetto di Minerva, e chi apre questa pagina di
    // solito è venuto per quella.
    //
    // Le anteprime sono i colori veri del tema, non dei quadratini decisi a
    // parte: il fondo, la superficie dei pannelli, l'accento. Un elenco di
    // NOMI («Rosa», «Ametista») non dice niente finché non lo si prova, e
    // provarlo vuol dire ridipingere tutto lo schermo per scoprire che non
    // era quello.
    Card {
        heading: page.it ? "Tema" : "Theme"
        note: page.it
              ? "Cambia tutta Minerva: barra, pannelli, finestre e icone."
              : "Changes all of Minerva: bar, panels, windows and icons."

        Flow {
            width: parent.width
            spacing: 10

            Repeater {
                model: Object.keys(Theme.Colors.schemes)

                delegate: Rectangle {
                    id: chip
                    required property var modelData

                    readonly property var tema: Theme.Colors.schemes[chip.modelData]
                    readonly property bool selected:
                        Core.Ipc.get("shell.scheme", "notte") === chip.modelData

                    width: 132
                    height: 84
                    radius: Theme.Effects.radiusMD
                    color: chip.tema.base
                    border.width: chip.selected ? 2 : 1
                    border.color: chip.selected ? Theme.Colors.accent
                                                : Theme.Colors.edge
                    Behavior on border.color {
                        ColorAnimation { duration: Theme.Motion.instant }
                    }

                    // La superficie dei pannelli, dentro il fondo: è ciò che
                    // distingue un tema chiaro con vetro da uno piatto, e a
                    // parole non si spiega.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 8
                        height: 30
                        radius: Theme.Effects.radiusSM
                        color: chip.tema.scura ? Qt.rgba(1, 1, 1, 0.10)
                                               : Qt.rgba(1, 1, 1, 0.75)

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 7
                            width: 12; height: 12; radius: 6
                            color: chip.tema.accento
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 25
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            elide: Text.ElideRight
                            text: page.it ? chip.tema.it : chip.tema.en
                            color: chip.tema.scura ? "#F2F4F8" : "#1B1D22"
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                            font.weight: Theme.Typography.weightMedium
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // Anche l'accento, e non è invadenza: l'accento
                            // salvato vince sempre su quello del tema, quindi
                            // senza questa riga si sceglie «Rosa» e resta il
                            // ciano di prima acceso in mezzo al rosa. Chi ne
                            // vuole un altro lo cambia qui sotto, e da quel
                            // momento è suo.
                            Core.Ipc.setSetting("shell.scheme", chip.modelData);
                            Core.Ipc.setSetting("shell.accent", chip.tema.accento);
                        }
                    }
                }
            }

            // ── Il settimo, che è tuo ────────────────────────────────
            //
            // Sta nella stessa fila degli altri sei e non in un riquadro a
            // parte: è un tema come loro, e metterlo altrove direbbe che è
            // una cosa da esperti. L'anteprima è la tinta VERA che si è
            // scelta, come per gli altri.
            //
            // L'accento non si riscrive scegliendolo — a differenza dei sei.
            // Quelli portano l'accento che sta bene con la loro tinta, che è
            // una scelta nostra; qui la tinta la sceglie chi guarda, e
            // decidere anche l'accento vorrebbe dire cancellargli una scelta
            // che ha già fatto.
            Rectangle {
                id: chipMio

                readonly property bool selected:
                    Core.Ipc.get("shell.scheme", "notte") === "personale"
                readonly property color tinta:
                    Theme.Colors.tinta(Core.Ipc.get("shell.tintaPersonale",
                                                    "#101018"))
                readonly property bool scuro:
                    Core.Ipc.get("shell.versoPersonale", true)

                width: 132
                height: 84
                radius: Theme.Effects.radiusMD
                color: chipMio.tinta
                border.width: chipMio.selected ? 2 : 1
                border.color: chipMio.selected ? Theme.Colors.accent
                                               : Theme.Colors.edge

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    height: 30
                    radius: Theme.Effects.radiusSM
                    color: chipMio.scuro ? Qt.rgba(1, 1, 1, 0.10)
                                         : Qt.rgba(1, 1, 1, 0.75)

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 7
                        width: 12; height: 12; radius: 6
                        color: Theme.Colors.accent
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 25
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        elide: Text.ElideRight
                        text: page.it ? "Personale" : "Personal"
                        color: chipMio.scuro ? "#F2F4F8" : "#1B1D22"
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                        font.weight: Theme.Typography.weightMedium
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Core.Ipc.setSetting("shell.scheme", "personale")
                }
            }
        }

        // ── La tinta e il verso, solo quando serve ───────────────────────
        //
        // Compaiono scegliendo «Personale» e spariscono altrimenti: mostrarli
        // sempre vorrebbe dire due manopole che non fanno niente per sei temi
        // su sette, ed è la forma esatta del difetto di `bar.position`.
        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("shell.scheme", "notte") === "personale"
            label: page.it ? "Chiaro o scuro" : "Light or dark"
            description: page.it
                ? "Non si indovina dalla tinta: un grigio medio sta bene in tutti e due i modi, e da questo dipende il verso di veli, bordi e testo"
                : "It cannot be guessed from the tint: a mid grey works either way, and the direction of veils, borders and text depends on it"
            controlWidth: 240
            control: S.ChoicePicker {
                value: Core.Ipc.get("shell.versoPersonale", true) ? "scuro"
                                                                  : "chiaro"
                options: [
                    { "value": "scuro",  "label": page.it ? "Scuro" : "Dark" },
                    { "value": "chiaro", "label": page.it ? "Chiaro" : "Light" }
                ]
                onPicked: function(v) {
                    Core.Ipc.setSetting("shell.versoPersonale", v === "scuro");
                }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("shell.scheme", "notte") === "personale"
            label: page.it ? "La tinta" : "The tint"
            description: page.it
                ? "Il colore del vetro. Superfici, veli, bordi e testo escono da qui"
                : "The colour of the glass. Surfaces, veils, borders and text all derive from it"
            control: Rectangle {
                width: 44; height: 30
                radius: Theme.Effects.radiusXS
                color: Theme.Colors.tinta(Core.Ipc.get("shell.tintaPersonale",
                                                       "#101018"))
                border.width: page.coloreAperto === "tinta" ? 2 : 1
                border.color: page.coloreAperto === "tinta"
                              ? Theme.Colors.accent : Theme.Colors.edge

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.coloreAperto =
                        (page.coloreAperto === "tinta") ? "" : "tinta"
                }
            }
        }

        S.SelettoreColore {
            width: parent.width
            visible: page.coloreAperto === "tinta"
                     && Core.Ipc.get("shell.scheme", "notte") === "personale"
            valore: Theme.Colors.tinta(Core.Ipc.get("shell.tintaPersonale",
                                                    "#101018"))
            onScelto: function(c) {
                Core.Ipc.setSetting("shell.tintaPersonale",
                                    c.toString().toUpperCase());
            }
        }
    }
    Card {
        heading: page.it ? "Colore d'accento" : "Accent colour"
        note: page.it
              ? "È il colore di ciò che è attivo: la scrivania in uso, il pannello "
                + "aperto, il cursore che stai trascinando."
              : "The colour of whatever is active: the current desktop, the open "
                + "panel, the slider you are dragging."

        Row {
            width: parent.width
            spacing: Theme.Effects.space2

            Repeater {
                model: [
                    { "value": "#22D3EE", "it": "Ciano",    "en": "Cyan" },
                    { "value": "#38BDF8", "it": "Azzurro",  "en": "Sky" },
                    { "value": "#818CF8", "it": "Indaco",   "en": "Indigo" },
                    { "value": "#A78BFA", "it": "Viola",    "en": "Violet" },
                    { "value": "#F472B6", "it": "Rosa",     "en": "Pink" },
                    { "value": "#34D399", "it": "Verde",    "en": "Green" },
                    { "value": "#FBBF24", "it": "Ambra",    "en": "Amber" },
                    { "value": "#FB7185", "it": "Corallo",  "en": "Coral" }
                ]

                delegate: Rectangle {
                    id: swatch
                    required property var modelData

                    readonly property bool chosen:
                        Core.Ipc.get("shell.accent", "#22D3EE") === modelData.value

                    width: 44; height: 44
                    radius: 22
                    color: modelData.value
                    border.width: chosen ? 3 : 0
                    border.color: Theme.Colors.text

                    scale: swatchMouse.containsMouse ? 1.1 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.Motion.instant } }

                    Ui.Icon {
                        anchors.centerIn: parent
                        width: 18; height: 18
                        name: "check"
                        visible: swatch.chosen
                        color: "#04121A"
                        thickness: 2.4
                    }

                    MouseArea {
                        id: swatchMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Core.Ipc.setSetting("shell.accent",
                                                       swatch.modelData.value)
                    }
                }
            }

            // ── E il nono, che è qualunque ───────────────────────────
            //
            // Le otto restano perché scelgono BENE: sono accenti che stanno
            // insieme a tutti e sei i temi, e chi non ha voglia di scegliere
            // un colore non deve essere costretto a farlo. Questo è per chi
            // ce l'ha già in mano — il colore di un logo, di un'altra
            // scrivania, di una fotografia.
            Rectangle {
                id: altroAccento

                readonly property bool aperto: page.coloreAperto === "accento"
                /// Nessuna delle otto: allora è uno suo, e va mostrato acceso.
                readonly property bool suo: {
                    var a = String(Core.Ipc.get("shell.accent", "#22D3EE"))
                            .toUpperCase();
                    var otto = ["#22D3EE", "#38BDF8", "#818CF8", "#A78BFA",
                                "#F472B6", "#34D399", "#FBBF24", "#FB7185"];
                    return otto.indexOf(a) < 0;
                }

                width: 44; height: 44
                radius: 22
                color: altroAccento.suo ? Theme.Colors.accent
                                        : Theme.Colors.raised
                border.width: (altroAccento.suo || altroAccento.aperto) ? 3 : 1
                border.color: altroAccento.suo ? Theme.Colors.text
                                               : Theme.Colors.edge

                scale: altroMouse.containsMouse ? 1.1 : 1
                Behavior on scale { NumberAnimation { duration: Theme.Motion.instant } }

                Ui.Icon {
                    anchors.centerIn: parent
                    width: 18; height: 18
                    name: "plus"
                    visible: !altroAccento.suo
                    color: Theme.Colors.textMuted
                    thickness: 2.0
                    alwaysDrawn: true
                }

                MouseArea {
                    id: altroMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.coloreAperto =
                        altroAccento.aperto ? "" : "accento"
                }
            }
        }

        S.SelettoreColore {
            width: parent.width
            visible: page.coloreAperto === "accento"
            valore: Theme.Colors.tinta(Core.Ipc.get("shell.accent", "#22D3EE"))
            onScelto: function(c) {
                Core.Ipc.setSetting("shell.accent", c.toString().toUpperCase());
            }
        }
    }
    // ── I colori messi a mano ────────────────────────────────────────────
    //
    // Fin qui si sceglie una TINTA e tutto il resto si ricava: è il modo in cui
    // Minerva resta coerente da sola, e per quasi tutti è quello giusto. Ma
    // «coerente da sola» vuol dire anche «non puoi avere i caratteri viola su
    // un fondo rosa», e ogni tanto è proprio quello che si vuole.
    //
    // Qui la derivazione si scavalca, uno per uno. Sette e non quaranta:
    // questi sono i sette da cui escono tutti gli altri, e una pagina con
    // quaranta quadratini non è più libertà — è un lavoro.
    Card {
        heading: page.it ? "Colori a mano" : "Colours by hand"
        note: page.it
              ? "Ogni colore qui vince sul conto che lo avrebbe calcolato. "
                + "Quei conti erano misurati: sotto ogni scelta trovi il "
                + "contrasto che ne esce, e un avviso quando scende sotto la "
                + "soglia in cui un testo piccolo si legge senza sforzo."
              : "Each colour here overrides the value that would have been "
                + "derived. Those derivations were measured: under each choice "
                + "you get the resulting contrast, and a warning when it drops "
                + "below what small text needs."

        // Sette colori da esperti sempre aperti erano la metà di questa
        // pagina. Dal 28 settembre 2026 stanno dietro un interruttore, che
        // parte acceso solo se qualcuno ne è già stato scelto a mano.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Scegli i colori a mano" : "Pick the colours by hand"
            description: page.it ? "Il fondo, i caratteri, i contorni e i colori degli avvisi"
                                 : "The background, the text, the outlines and the alert colours"
            searchTerms: "colori a mano fondo caratteri contorni barra pannelli va bene attenzione pericolo"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: page._coloriAMano
                onToggled: function (v) { page._coloriAMano = v; }
            }
        }

        Repeater {
            model: [
                { "nome": "base",     "it": "Il fondo",
                  "en": "The background",
                  "itd": "La tinta del vetro: la usano finestre, pannelli e barra",
                  "end": "The tint of the glass: windows, panels and bar all use it" },
                { "nome": "testo",    "it": "I caratteri",
                  "en": "The text",
                  "itd": "Anche le due gradazioni più smorzate escono da qui",
                  "end": "The two dimmer grades derive from this one" },
                { "nome": "membrana", "it": "Barra e pannelli",
                  "en": "Bar and panels",
                  "itd": "La superficie continua. La trasparenza resta la sua",
                  "end": "The continuous surface. Transparency stays its own" },
                { "nome": "bordo",    "it": "I contorni",
                  "en": "The outlines",
                  "itd": "Il filo che fa cogliere la curvatura delle superfici",
                  "end": "The hairline that makes the curvature readable" },
                { "nome": "positivo", "it": "Va bene",
                  "en": "All good",
                  "itd": "Connesso, carico, riuscito",
                  "end": "Connected, charged, succeeded" },
                { "nome": "avviso",   "it": "Attenzione",
                  "en": "Careful",
                  "itd": "Batteria bassa, spazio che finisce",
                  "end": "Low battery, running out of room" },
                { "nome": "pericolo", "it": "Pericolo",
                  "en": "Danger",
                  "itd": "Cancella, chiudi senza salvare, disconnetti",
                  "end": "Delete, close without saving, disconnect" }
            ]

            delegate: Column {
                id: riga
                required property var modelData
                visible: page._coloriAMano

                width: parent.width
                spacing: Theme.Effects.space2

                readonly property string nome: riga.modelData.nome
                readonly property string messo:
                    String(page.scavalca[riga.nome] || "")
                readonly property bool aperto: page.coloreAperto === riga.nome

                /// Il colore che si vede adesso, scavalcato o derivato. Si
                /// chiede alla tavolozza invece di rifare il conto: rifarlo
                /// qui vorrebbe dire una seconda verità, e il quadratino
                /// mostrerebbe un colore che sullo schermo non c'è.
                readonly property color ora: {
                    switch (riga.nome) {
                    case "base":     return Theme.Colors.base;
                    case "testo":    return Theme.Colors.text;
                    case "membrana": return Theme.Colors.membrane;
                    case "bordo":    return Theme.Colors.edge;
                    case "positivo": return Theme.Colors.positive;
                    case "avviso":   return Theme.Colors.warning;
                    }
                    return Theme.Colors.danger;
                }

                S.SettingRow {
                    width: parent.width
                    label: page.it ? riga.modelData.it : riga.modelData.en
                    description: page.it ? riga.modelData.itd
                                         : riga.modelData.end
                    controlWidth: 108

                    control: Row {
                        spacing: Theme.Effects.space2

                        // Il quadratino: si apre e si chiude.
                        Rectangle {
                            width: 44; height: 30
                            radius: Theme.Effects.radiusXS
                            color: riga.ora
                            border.width: riga.aperto ? 2 : 1
                            border.color: riga.aperto ? Theme.Colors.accent
                                                      : Theme.Colors.edge

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.coloreAperto =
                                    riga.aperto ? "" : riga.nome
                            }
                        }

                        // ── E il modo di tornare indietro ────────────
                        //
                        // Sta accanto alla scelta e non solo in fondo alla
                        // pagina: chi ha appena sbagliato un colore vuole
                        // disfare QUELLO, non tutto.
                        Rectangle {
                            width: 30; height: 30
                            radius: Theme.Effects.radiusXS
                            visible: riga.messo !== ""
                            color: rimettiMouse.containsMouse
                                   ? Theme.Colors.hover : "transparent"
                            border.width: 1
                            border.color: Theme.Colors.edge

                            Ui.Icon {
                                anchors.centerIn: parent
                                width: 14; height: 14
                                name: "close"
                                color: Theme.Colors.textMuted
                                thickness: 2.0
                                alwaysDrawn: true
                            }

                            MouseArea {
                                id: rimettiMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.togliColore(riga.nome)
                            }
                        }
                    }
                }

                S.SelettoreColore {
                    width: parent.width
                    visible: riga.aperto
                    valore: riga.ora
                    onScelto: function(c) {
                        page.mettiColore(riga.nome, c.toString());
                    }
                }

                // ── Il contrasto, mentre lo si sceglie ───────────────
                //
                // Non dopo, e non in una nota: qui, sotto il quadrato aperto,
                // col numero. È il conto che ha già corretto due volte questa
                // tavolozza a colpi di misura, e lasciarlo fuori vorrebbe dire
                // rifare a occhio proprio ciò che era stato tolto dall'occhio.
                Text {
                    width: parent.width
                    visible: riga.aperto
                             && (riga.nome === "testo" || riga.nome === "base"
                                 || riga.nome === "membrana")
                    wrapMode: Text.WordWrap
                    text: {
                        var r = Theme.Colors.contrasto(Theme.Colors.text,
                                                       Theme.Colors.membrane);
                        var n = Math.round(r * 10) / 10;
                        if (r >= 4.5)
                            return page.it
                                ? "Testo sui pannelli: contrasto " + n
                                  + ":1 — si legge."
                                : "Text on panels: contrast " + n
                                  + ":1 — readable.";
                        return page.it
                            ? "⚠ Testo sui pannelli: contrasto " + n + ":1. "
                              + "Sotto 4,5 un testo piccolo non si legge senza "
                              + "sforzo. Puoi tenerlo lo stesso."
                            : "⚠ Text on panels: contrast " + n + ":1. "
                              + "Below 4.5 small text is hard to read. You can "
                              + "keep it anyway.";
                    }
                    color: Theme.Colors.contrasto(Theme.Colors.text,
                                                  Theme.Colors.membrane) >= 4.5
                           ? Theme.Colors.textFaint : Theme.Colors.warning
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }
        }

        // ── La via d'uscita, che non si può perdere ──────────────────────
        //
        // Si disegna con i colori DI FABBRICA e non con quelli scelti: se si
        // vestisse come il resto, la prima cosa a sparire dietro una
        // combinazione illeggibile sarebbe proprio il modo di uscirne.
        Rectangle {
            width: 220
            height: 34
            radius: Theme.Effects.radiusSM
            visible: Object.keys(page.scavalca).length > 0
            color: rimettiTuttoMouse.containsMouse ? "#2A2F3A" : "#1B1F27"
            border.width: 1
            border.color: "#4A5162"

            Text {
                anchors.centerIn: parent
                text: page.it ? "Rimetti tutti i colori a posto"
                              : "Reset every colour"
                color: "#EEF4FF"
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                font.weight: Theme.Typography.weightMedium
            }

            MouseArea {
                id: rimettiTuttoMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Core.Ipc.setSetting("shell.scavalca", ({}));
                    page.coloreAperto = "";
                }
            }
        }
    }
    // ── Icone ────────────────────────────────────────────────────────────
    //
    // Le icone di Minerva sono disegnate da noi: tratto sottile, luminoso,
    // tutte con lo stesso peso. È una scelta di stile, e come tutte le scelte
    // di stile non va bene a tutti — a qualcuno quel tratto sembra freddo, e
    // preferisce le icone che ha già visto per anni. Non c'è ragione di
    // imporre le nostre: qui si sceglie.
    //
    // Il ripiego non è un dettaglio da mettere in una nota a piè di pagina, ed
    // è per questo che c'è scritto nel riquadro: nessun tema di icone copre
    // tutti i nomi che usiamo, e le icone che mancano restano disegnate. Chi
    // non lo sa pensa che il tema si sia installato a metà.

    Card {
        heading: page.it ? "Icone" : "Icons"
        note: page.it
            ? "Le icone che un tema non ha restano disegnate da Minerva: nessun "
              + "tema copre tutto, e un'icona fuori stile si guarda meglio di un buco."
            : "Icons a theme does not provide stay drawn by Minerva: no theme covers "
              + "everything, and an icon in the wrong style beats an empty space."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Come sono disegnate" : "How they are drawn"
            description: page.it
                ? "Le nostre, a tratto sottile, oppure quelle del tema installato sul computer"
                : "Ours, thin-stroked, or those of the icon theme installed on this computer"
            controlWidth: 260

            control: S.ChoicePicker {
                value: Core.Ipc.get("icons.style", "minerva")
                options: [
                    { "value": "minerva",   "label": page.it ? "Minerva"   : "Minerva" },
                    { "value": "classiche", "label": page.it ? "Classiche" : "Classic" }
                ]
                onPicked: function(v) { Core.Ipc.setSetting("icons.style", v); }
            }
        }

        // ── Quanto copre il tema scelto ──────────────────────────────────
        //
        // «Ci sono icone che non si trovano» è una sensazione finché non c'è
        // un numero. Il demone lo sa già — lo scrive nel registro a ogni
        // risoluzione — e da qui in poi lo dice anche a chi guarda.
        Item {
            width: parent.width
            visible: Core.Ipc.get("icons.style", "minerva") !== "minerva"
                     && Core.Ipc.iconChieste > 0
            height: visible ? copertura.implicitHeight + Theme.Effects.space2 : 0

            Text {
                id: copertura
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeXS
                text: {
                    var tot = Core.Ipc.iconChieste;
                    var mancano = Core.Ipc.iconMancanti || [];
                    var ha = tot - mancano.length;
                    var tema = Core.Ipc.iconTheme || "?";
                    if (mancano.length === 0)
                        return page.it
                            ? "Con «" + tema + "» tutte e " + tot + " le icone vengono dal tema."
                            : "With “" + tema + "” all " + tot + " icons come from the theme.";
                    return (page.it
                        ? "Con «" + tema + "», " + ha + " icone su " + tot
                          + " vengono dal tema. Queste " + mancano.length
                          + " il tema non le ha, e restano disegnate da Minerva: "
                        : "With “" + tema + "”, " + ha + " icons out of " + tot
                          + " come from the theme. The theme does not have these "
                          + mancano.length + ", so Minerva keeps drawing them: ")
                        + mancano.join(", ") + ".";
                }
            }
        }

        // L'elenco dei temi si chiede una volta sola, aprendo la pagina: è
        // una lettura del disco, e i temi non si installano da soli mentre
        // si guardano le impostazioni.
        Component.onCompleted: Core.Ipc.requestIconThemes()

        Connections {
            target: Core.Ipc
            // Se il demone non era ancora in piedi quando la pagina si è
            // aperta, la richiesta di prima è andata persa. Senza questo, la
            // scelta del tema resta una riga vuota fino alla riapertura.
            function onConnectedChanged() {
                if (Core.Ipc.connected) Core.Ipc.requestIconThemes();
            }
            // Un tema tolto (o installato dal gestore file): si rilegge
            // l'elenco, o la riga resterebbe lì a promettere un tema che non c'è.
            function onIconeEsito(esito) { Core.Ipc.requestIconThemes(); }
        }

        Item {
            width: parent.width
            height: themeFlow.implicitHeight + themeLabel.implicitHeight + 10
            // Scegliere il tema mentre le icone sono le nostre non cambierebbe
            // niente sullo schermo, e una scelta che non fa niente è peggio di
            // una scelta assente.
            visible: Core.Ipc.get("icons.style", "minerva") !== "minerva"

            Text {
                id: themeLabel
                width: parent.width
                text: page.it ? "Da quale tema" : "From which theme"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeMD
                font.weight: Theme.Typography.weightMedium
            }

            // Un `Flow` e non una tendina: i temi installati sono pochi, e
            // vederli tutti insieme vuol dire poterli provare uno dietro
            // l'altro guardando la barra dietro questa finestra cambiare.
            // Una tendina obbligherebbe a un clic in più per ogni prova.
            Flow {
                id: themeFlow
                anchors.top: themeLabel.bottom
                anchors.topMargin: 10
                width: parent.width
                spacing: 6

                Repeater {
                    // La prima voce non è un tema: è «quello che ho già
                    // scelto altrove». Salvata come stringa vuota, così se
                    // domani si cambia tema da qualche altra parte Minerva
                    // segue senza che nessuno debba tornare qui.
                    model: [""].concat(Core.Ipc.iconThemes)

                    delegate: Rectangle {
                        id: themeChip
                        required property var modelData

                        readonly property bool isAuto: themeChip.modelData === ""
                        // Si confronta con la famiglia che il demone dice di
                        // aver preso, non con il nome salvato: nelle
                        // impostazioni può esserci ancora una variante
                        // («Colloid-Light») scritta quando l'elenco le
                        // mostrava, e nessuna voce si accenderebbe.
                        readonly property bool selected:
                            Core.Ipc.iconChosen === themeChip.modelData

                        implicitWidth: chipLabel.implicitWidth + 24
                        height: 30
                        radius: Theme.Effects.radiusSM

                        color: themeChip.selected ? Qt.alpha(Theme.Colors.accent, 0.18)
                                                  : (chipArea.containsMouse ? Theme.Colors.hover
                                                                            : Theme.Colors.raised)
                        border.width: 1
                        border.color: themeChip.selected ? Theme.Colors.accent
                                                         : Theme.Colors.edge

                        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

                        Text {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: themeChip.isAuto
                                  ? (page.it ? "Come il sistema" : "Follow the system")
                                  : themeChip.modelData
                            color: themeChip.selected ? Theme.Colors.accent
                                                      : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                            font.weight: Theme.Typography.weightMedium
                        }

                        MouseArea {
                            id: chipArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Core.Ipc.setSetting("icons.theme",
                                                           themeChip.modelData)
                        }
                    }
                }
            }
        }

        // ── I temi nella tua cartella, e toglierli ───────────────────────
        //
        // Si installano dal gestore file (tasto destro su un archivio) e fino
        // al 5 ottobre 2026 non si toglievano da nessuna parte: il demone lo
        // sapeva fare, mancava il pulsante. Solo quelli in
        // `~/.local/share/icons`: i temi di sistema non sono nostri.
        //
        // Togliere cancella una cartella, e non si torna indietro: il primo
        // clic chiede «Sicuro?», il secondo — entro quattro secondi — toglie.
        Column {
            width: parent.width
            spacing: 6
            visible: Core.Ipc.iconeInstallate.length > 0

            Text {
                width: parent.width
                text: page.it ? "Temi nella tua cartella" : "Themes in your folder"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeMD
                font.weight: Theme.Typography.weightMedium
            }

            Repeater {
                model: Core.Ipc.iconeInstallate

                delegate: Item {
                    id: installato
                    required property var modelData
                    property bool armato: false

                    width: parent.width
                    height: 32

                    Timer {
                        id: disarma
                        interval: 4000
                        onTriggered: installato.armato = false
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.right: togli.left
                        anchors.rightMargin: Theme.Effects.space2
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: installato.modelData.nome
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    Rectangle {
                        id: togli
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: togliTesto.implicitWidth + 20
                        height: 26
                        radius: Theme.Effects.radiusSM
                        color: installato.armato || togliArea.containsMouse
                               ? Qt.alpha(Theme.Colors.danger, 0.16) : Theme.Colors.raised
                        border.width: 1
                        border.color: installato.armato ? Theme.Colors.danger : Theme.Colors.edge

                        Text {
                            id: togliTesto
                            anchors.centerIn: parent
                            text: installato.armato ? (page.it ? "Sicuro?" : "Sure?")
                                                    : (page.it ? "Togli" : "Remove")
                            color: installato.armato || togliArea.containsMouse
                                   ? Theme.Colors.danger : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        MouseArea {
                            id: togliArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!installato.armato) {
                                    installato.armato = true;
                                    disarma.restart();
                                    return;
                                }
                                installato.armato = false;
                                Core.Ipc.iconeDisinstalla(installato.modelData.cartella);
                            }
                        }
                    }
                }
            }
        }
    }
    // ── L'elenco vivo, per «Avanzate» ────────────────────────────────────
    //
    // Si chiede al compositore all'apertura della pagina. Finché non risponde
    // resta vuoto e la sezione non compare: meglio niente che un elenco
    // inventato.

    // ── L'interruttore che vale per TUTTO ────────────────────────────────

    Card {
        heading: page.it ? "Movimento" : "Motion"

        S.SettingRow {
            width: parent.width
            label: page.it ? "Effetti e animazioni" : "Effects and animations"
            description: page.it
                ? "Vale sia per le finestre sia per i pannelli di Minerva"
                : "Applies both to windows and to Minerva's own panels"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: page.accese
                onToggled: function (v) {
                    Core.Ipc.setSetting("desktop.animations", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: page.accese
            label: page.it ? "Velocità" : "Speed"
            description: page.it
                ? "Più a destra, più lente. Vale per i pannelli e i menu"
                : "Further right is slower. Applies to panels and menus"
            controlWidth: 320

            // Il numero mostrato è il MOLTIPLICATORE della durata, quindi
            // «2,0×» vuol dire il doppio del tempo, cioè metà velocità. Lo
            // dice la descrizione, perché il numero da solo si legge al
            // contrario.
            control: S.ValueSlider {
                from: 0.5; to: 2.0
                // Il normale sta in mezzo e ci si torna col dito, come per la
                // sensibilità del puntatore. Vedi `settings/ValueSlider.qml`.
                aggancioA: 1.0
                unit: "numero"
                value: Core.Ipc.get("desktop.animationSpeed", 1.0)
                onReleased: function (v) {
                    Core.Ipc.setSetting("desktop.animationSpeed",
                                        Math.round(v * 20) / 20);
                }
            }
        }

    }
}

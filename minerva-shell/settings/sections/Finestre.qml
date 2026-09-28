import QtQuick
import Quickshell
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// Finestre — come sono fatte e come si muovono: la barra del titolo e i suoi
// pulsanti, il materiale (l'effetto, la trasparenza, Mercurio), il colore
// attorno a quella attiva, l'elasticità. Nata il 28 settembre 2026 dai pezzi
// che stavano in «Aspetto», «Effetti e animazioni» e «Minerva».
Page {
    id: page

    title: Core.Strings.lang === "it" ? "Finestre" : "Windows"
    subtitle: Core.Strings.lang === "it"
              ? "La barra del titolo, il materiale, la cornice e l'elasticità"
              : "The title bar, the material, the frame and the elasticity"
    /// Vero quando la trasparenza delle finestre la mette il compositore.
    /// Vedi `Core.Vetro.effettoChiestoAcceso`: da lì in poi «Vetro delle finestre di
    /// Minerva» non ha più niente da regolare.
    readonly property bool _effettoAcceso: Core.Vetro.effettoChiestoAcceso
    // ── Qui c'era la dock, e adesso ha una pagina sua ────────────────────
    //
    // Sette voci — mostra, si nasconde, dimensione, ingrandimento, estensione,
    // trasparenza, nome al passaggio — dentro una pagina da milleseicento
    // righe. C'erano tutte, e Giacomo dopo settimane d'uso ha scritto: «la
    // dock ancora non si nasconde da sola e non ci sono impostazioni per
    // essa». Nel suo file `dock.autoHide` era `false`: era spenta, non rotta.
    //
    // Un'opzione che non si trova è un'opzione che non esiste, e questo non è
    // un difetto di chi guarda. Le voci si sono spostate in
    // `sections/Dock.qml`, che nell'elenco di sinistra ha il suo nome.
    //
    // NON si lascia una copia qui: due posti per la stessa impostazione sono
    // due posti che divergono, ed è un difetto che questo progetto ha già
    // pagato più di una volta.

    readonly property bool it: Core.Strings.lang === "it"
    /// Vero quando la cornice si muove: «gira» o «striscia». Le due manopole
    /// del giro — quanto ci mette e con che colori — valgono per tutte e due.
    readonly property bool _corniceGira: {
        var c = String(Core.Ipc.get("windows.cornice", "spento"));
        return c === "gira" || c === "striscia";
    }
    /// Le pasticche che si possono aggiungere. Sono i colori dell'accento di
    /// Minerva più l'accento scelto adesso: chi vuole «i miei colori invece
    /// dell'arcobaleno» quasi sempre vuole questi.
    readonly property var tinteProposte: [
        String(Theme.Colors.accent), "#22D3EE", "#F97316", "#A855F7",
        "#22C55E", "#EF4444", "#EAB308", "#EC4899", "#3B82F6"
    ]
    function tintaTogli(colore) {
        var l = Core.Ipc.get("windows.corniceTinte", []).slice();
        var i = l.indexOf(colore);
        if (i < 0)
            return;
        l.splice(i, 1);
        Core.Ipc.setSetting("windows.corniceTinte", l);
    }
    function tintaAggiungi(colore) {
        var l = Core.Ipc.get("windows.corniceTinte", []).slice();
        // Otto è il tetto del compositore: sopra, girando, non si distinguono
        // più l'uno dall'altro.
        if (l.length >= 8 || l.indexOf(colore) >= 0)
            return;
        l.push(colore);
        Core.Ipc.setSetting("windows.corniceTinte", l);
    }
    /// Toglie un programma dall'elenco di quelli che si disegnano la barra da
    /// soli. Da quel momento la barra gliela mette Minerva — al PROSSIMO
    /// avvio di quella finestra: la decisione si prende quando la finestra
    /// nasce (`finestra_decidi_barra`), e cambiarla a metà vita vorrebbe dire
    /// una finestra che si ridisegna sotto le dita.
    function csdTogli(nome) {
        var l = Core.Ipc.get("windows.csdApps", []).slice();
        var i = l.indexOf(nome);
        if (i < 0)
            return;
        l.splice(i, 1);
        Core.Ipc.setSetting("windows.csdApps", l);
    }
    /// E ne aggiunge uno. Uno spazio dentro il nome spezzerebbe la riga che va
    /// al compositore in due nomi: si rifiuta invece di mandare una cosa che
    /// là dentro diventa un'altra.
    function csdAggiungi(nome) {
        var v = String(nome || "").trim().toLowerCase();
        if (v === "" || v.indexOf(" ") >= 0)
            return;
        var l = Core.Ipc.get("windows.csdApps", []).slice();
        if (l.indexOf(v) >= 0)
            return;
        l.push(v);
        Core.Ipc.setSetting("windows.csdApps", l);
    }
    Card {
        heading: page.it ? "Barra del titolo" : "Title bar"

        // ── I programmi che si disegnano la barra da soli ─────────────────
        //
        // `windows.csdApps` esisteva dal primo giorno, la legge il compositore
        // e decide chi tiene la propria barra del titolo invece della nostra
        // — i browser, Thunderbird, i programmi GNOME. E in `main.c:521` c'è
        // scritto per iscritto che è «modificabile dal pannello Impostazioni».
        //
        // Non lo era. Il compositore dichiarava una cosa che non esisteva, ed
        // è il difetto peggiore della famiglia: non una funzione mancante, ma
        // una promessa scritta.
        //
        // Si scrive per NOME del programma — quello che appare nella classe
        // della finestra — e basta un pezzo del nome: «firefox» prende anche
        // «firefox-esr». Uno spazio dentro spezzerebbe la riga che va al
        // compositore in due nomi, e per questo si rifiuta.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Programmi con la barra loro"
                           : "Programs with their own title bar"
            description: page.it
                ? "Chrome, Firefox e gli altri disegnano già i propri pulsanti: "
                  + "dare loro anche la nostra barra vorrebbe dire due barre "
                  + "una sopra l'altra"
                : "Chrome, Firefox and the others already draw their own "
                  + "buttons: giving them our bar too would mean two bars"
            controlWidth: 0
        }

        Item {
            width: parent.width
            height: csdFlow.implicitHeight + 40

            Flow {
                id: csdFlow
                width: parent.width
                spacing: Theme.Effects.space2

                Repeater {
                    model: Core.Ipc.get("windows.csdApps", [])
                    delegate: Rectangle {
                        required property var modelData
                        height: 28
                        // Margine sinistro, nome, stacco, croce, margine destro:
                        // con «+ space4» soltanto la croce finiva sopra la
                        // fine del nome («firefox×», 28 settembre 2026).
                        width: Theme.Effects.space3 + nome.implicitWidth
                               + Theme.Effects.space2 + croce.implicitWidth
                               + Theme.Effects.space3
                        radius: Theme.Effects.radiusFull
                        color: Theme.Colors.raised
                        border.width: 1
                        border.color: Theme.Colors.edge

                        Text {
                            id: nome
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.Effects.space3
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(parent.modelData)
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontMono
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        // La crocetta è un testo e non un tracciato: col
                        // renderer software una `Shape` dentro una lista
                        // deposita copie di sé sopra il resto. Vedi
                        // `minerva-residui-software`.
                        Text {
                            id: croce
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.Effects.space2
                            anchors.verticalCenter: parent.verticalCenter
                            text: "✕"
                            color: viaMouse.containsMouse
                                   ? Theme.Colors.danger : Theme.Colors.textMuted
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        MouseArea {
                            id: viaMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.csdTogli(String(parent.modelData))
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: 34
                anchors.bottom: parent.bottom

                Ui.Campo {
                    id: csdNuovo
                    anchors.fill: parent
                    segnaposto: page.it
                        ? "Aggiungi un programma (per esempio: thunderbird)"
                        : "Add a program (for example: thunderbird)"
                    onAccettato: {
                        page.csdAggiungi(csdNuovo.text);
                        csdNuovo.text = "";
                    }
                }
            }
        }

        // ── Il colore intorno ────────────────────────────────────────────
        //
        // Giacomo, 3 settembre 2026: «se voglio che il colore intorno diventi
        // tipo rgb e cambi colore costantemente oppure che giri sempre come
        // una striscia led?».
        //
        // Non c'è niente di nuovo da disegnare: attorno a ogni finestra c'è
        // già un anello di sei pixel — quello con cui la si prende per
        // ridimensionarla — ed era trasparente.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Il colore intorno alla finestra attiva"
                           : "The colour around the active window"
            description: page.it
                ? "Solo intorno a quella attiva: un arcobaleno attorno a otto finestre insieme non è un effetto"
                : "Only around the active one: a rainbow around eight windows at once is not an effect"
            controlWidth: 340
            control: S.ChoicePicker {
                value: Core.Ipc.get("windows.cornice", "spento")
                options: [
                    { "value": "spento", "label": page.it ? "Niente" : "None" },
                    { "value": "fisso",  "label": page.it ? "L'accento"
                                                          : "The accent" },
                    { "value": "gira",   "label": page.it ? "Gira" : "Cycles" },
                    { "value": "striscia", "label": page.it ? "Striscia LED"
                                                            : "LED strip" }
                ]
                onPicked: function(v) {
                    Core.Ipc.setSetting("windows.cornice", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: page._corniceGira
            label: page.it ? "Quanto ci mette a fare il giro"
                           : "How long a full cycle takes"
            description: page.it
                ? "Sotto i due secondi non è un colore che gira, è un lampeggio, e il compositore lo rifiuta"
                : "Under two seconds it is not a cycle but a flicker, and the compositor refuses it"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 2
                to: 120
                // «secondi» non è un'unità di `ValueSlider`: cadeva nel caso
                // di ripiego e otto secondi si leggevano «800%». Il nome
                // dell'unità è un termine fisso — è il suffisso che si
                // traduce.
                unit: "intero"
                suffix: page.it ? "s" : "s"
                value: Core.Ipc.get("windows.cornicePeriodo", 8000) / 1000
                onReleased: function(v) {
                    Core.Ipc.setSetting("windows.cornicePeriodo",
                                        Math.round(v) * 1000);
                }
            }
        }

        // ── Lo spessore ──────────────────────────────────────────────────
        //
        // Giacomo, 9 settembre 2026: «voglio poter regolare lo spessore del
        // colore intorno alla finestra attiva».
        //
        // Era sei pixel fissi, e non per scelta: era lo STESSO numero della
        // presa per ridimensionare, che è una misura per le dita. Adesso sono
        // due cose, e la presa segue il più grande dei due — un bordo che si
        // vede e non si afferra sarebbe peggio di uno che non si vede.
        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("windows.cornice", "spento") !== "spento"
            label: page.it ? "Quanto è spesso" : "How thick"
            description: page.it
                ? "Sopra i venti pixel non è più un bordo, ed è anche una "
                  + "banda in cui il clic non arriva più al programma"
                : "Over twenty pixels it stops being a border"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 1
                to: 20
                unit: "pixel"
                value: Core.Ipc.get("windows.corniceSpessore", 6)
                onReleased: function(v) {
                    Core.Ipc.setSetting("windows.corniceSpessore",
                                        Math.round(v));
                }
            }
        }

        // ── Anche attorno a quelle che non hanno il fuoco ────────────────
        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("windows.cornice", "spento") !== "spento"
            label: page.it ? "Anche attorno alle altre finestre"
                           : "Around the other windows too"
            description: page.it
                ? "Il bordo serve a dire QUALE finestra risponde alla "
                  + "tastiera: acceso su tutte, smette di dirlo. Con una "
                  + "velatura bassa diventa il contorno di ognuna."
                : "The border says which window has the keyboard: on all of "
                  + "them, it stops saying it."
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 0
                to: 0.60
                value: Core.Ipc.get("windows.corniceSpente", 0)
                onReleased: function(v) {
                    Core.Ipc.setSetting("windows.corniceSpente",
                                        Math.round(v * 100) / 100);
                }
            }
        }

        // ── I colori che si alternano ────────────────────────────────────
        //
        // Vuoto è lo SPETTRO intero — l'arcobaleno di sempre — e resta il
        // ripiego: chi non sceglie niente lo vede. Da un colore in su, il giro
        // passa per quelli e per nessun altro; con uno solo si ottiene una
        // striscia di un colore che scorre, che è una cosa che si può volere.
        S.SettingRow {
            width: parent.width
            visible: page._corniceGira
            label: page.it ? "I colori che si alternano"
                           : "The colours that take turns"
            description: page.it
                ? "Nessuno scelto: l'arcobaleno intero"
                : "None chosen: the whole spectrum"
            controlWidth: 0
        }

        Item {
            width: parent.width
            visible: page._corniceGira
            height: tinteFlow.implicitHeight + 12

            Flow {
                id: tinteFlow
                width: parent.width
                spacing: Theme.Effects.space2

                Repeater {
                    model: Core.Ipc.get("windows.corniceTinte", [])
                    delegate: Rectangle {
                        required property var modelData
                        width: 54
                        height: 28
                        radius: Theme.Effects.radiusFull
                        color: String(parent.modelData)
                        border.width: 1
                        border.color: Theme.Colors.edge

                        // La crocetta è un testo e non un tracciato: col
                        // renderer software una `Shape` dentro una lista
                        // deposita copie di sé sopra il resto.
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: viaTinta.containsMouse
                                   ? Theme.Colors._bianco : "transparent"
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        MouseArea {
                            id: viaTinta
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.tintaTogli(String(parent.modelData))
                        }
                    }
                }

                // Otto pasticche pronte, e l'accento in cima: scegliere un
                // colore qualunque vuole il selettore, e il selettore vuole
                // una finestra sua. Otto colori che stanno bene insieme sono
                // la risposta giusta per il novanta per cento di chi vuole
                // «i miei colori invece dell'arcobaleno».
                Repeater {
                    model: page.tinteProposte
                    delegate: Rectangle {
                        required property var modelData
                        width: 28
                        height: 28
                        radius: Theme.Effects.radiusFull
                        color: String(modelData)
                        opacity: 0.55
                        border.width: 1
                        border.color: Theme.Colors.edge

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.tintaAggiungi(String(parent.modelData))
                        }
                    }
                }
            }
        }


        S.SettingRow {
            width: parent.width
            label: page.it ? "Barra del titolo su ogni finestra"
                           : "A title bar on every window"
            description: page.it
                ? "Nome, icona e i tre pulsanti sopra ogni finestra. Serve anche per spostarle e agganciarle ai bordi"
                : "Name, icon and the three buttons above every window. Also how you move and snap them"
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("windows.titleBars", true)
                onToggled: function(v) { Core.Ipc.setSetting("windows.titleBars", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Altezza della barra del titolo" : "Title bar height"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 26
                to: 46
                unit: "pixel"
                value: Core.Ipc.get("windows.titleHeight", 34)
                onReleased: function(v) {
                    Core.Ipc.setSetting("windows.titleHeight", Math.round(v));
                }
            }
        }

        // ── Da che parte stanno i pulsanti ───────────────────────────────
        //
        // Qui c'era la scelta fra finestre affiancate e libere. Non c'è più:
        // in Minerva le finestre sono libere e basta. Il perché sta in
        // `core/WindowRules.qml`, e in breve è che una finestra poteva
        // diventare libera in cinque modi che non si conoscevano fra loro.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Pulsanti della finestra"
                           : "Window buttons"
            description: page.it
                ? "Riduci, ingrandisci, schermo intero e chiudi: a destra come "
                  + "su Windows, a sinistra come su macOS"
                : "Minimise, maximise, full screen and close: on the right like "
                  + "Windows, on the left like macOS"
            controlWidth: 300

            control: S.ChoicePicker {
                value: Core.Ipc.get("windows.buttonsSide", "destra")
                options: [
                    { "value": "destra",   "label": page.it ? "A destra"   : "Right" },
                    { "value": "sinistra", "label": page.it ? "A sinistra" : "Left" }
                ]
                onPicked: function(v) { Core.Ipc.setSetting("windows.buttonsSide", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "A schermo intero" : "In fullscreen"
            description: page.it
                ? "A schermo intero il compositore copre tutto: questa barra è l'unico modo di tornare indietro col mouse"
                : "In fullscreen the compositor covers everything: this bar is the only way back with the mouse"
            controlWidth: 380
            control: S.ChoicePicker {
                value: Core.Ipc.get("windows.fullscreenBar", "hover")
                options: [
                    { "value": "hover",
                      "label": page.it ? "Compare in cima" : "Appears at the top" },
                    { "value": "always",
                      "label": page.it ? "Sempre visibile" : "Always visible" },
                    { "value": "off",
                      "label": page.it ? "Mai" : "Never" }
                ]
                onPicked: function(v) { Core.Ipc.setSetting("windows.fullscreenBar", v); }
            }
        }
    }
    // ── La lingua stava anche qui ────────────────────────────────────────
    //
    // C'era una carta «Lingua» identica a quella di «Lingua e regione», con
    // le stesse tre scelte scritte con parole diverse («Automatica
    // (sistema)» contro «Come il sistema»). Scrivevano la stessa chiave,
    // quindi non si contraddicevano mai — ma due posti per la stessa cosa
    // sono due posti da cercare, ed è il difetto che i due livelli e la
    // ricerca esistono per togliere. La casa della lingua è «Ora e lingua ›
    // Lingua e regione»; questa pagina parla del comportamento della barra,
    // dei pannelli e degli avvisi, e la sua sottotitolo lo dice.

    // ── Trasparenza ──────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Materiale" : "Material"


        // Le finestre sono un problema diverso dalla barra, e per mesi hanno
        // avuto un'impostazione che nessuno poteva toccare: `shell.windowOpacity`
        // esisteva, la shell la leggeva, e non c'era un cursore da nessuna
        // parte. La barra deve restare leggibile sopra qualunque cosa; una
        // finestra ha dietro solo la scrivania e può permettersi molto di più.
        // ── E sparisce quando la trasparenza la mette il COMPOSITORE ─────
        //
        // Con un effetto acceso questa manopola non farebbe più niente: la
        // trasparenza delle finestre — di TUTTE le finestre, le nostre e
        // quelle degli altri — è quella della riga «Quanto si vede
        // attraverso», due righe più in basso. Lasciarla qui vorrebbe dire un
        // cursore che si gira a vuoto, che è il difetto che questo progetto si
        // è messo per iscritto di non commettere.
        S.SettingRow {
            width: parent.width
            visible: !page._effettoAcceso
            label: page.it ? "Vetro delle finestre di Minerva"
                           : "Minerva window glass"
            description: page.it
                ? "Gestore file, Impostazioni e le altre finestre nostre"
                : "The file manager, Settings and Minerva's other windows"
            controlWidth: 220

            control: S.ValueSlider {
                width: 220
                // Come per la membrana, il minimo non è la trasparenza massima
                // possibile ma l'ultima che si legge ancora — vedi
                // `windowOpacityMin` in `theme/Colors.qml`, dove c'è il conto.
                // Prima arrivava a 0,55 e chi ci arrivava si ritrovava le
                // proprie finestre grigie sopra uno sfondo chiaro, col testo
                // piccolo che spariva. Non era una scelta estetica: era un
                // cursore che poteva rompere le finestre.
                from: Theme.Colors.windowOpacityMin
                to: 1.0
                value: Core.Ipc.get("shell.windowOpacity", 0.88)
                onReleased: function(v) {
                    Core.Ipc.setSetting("shell.windowOpacity",
                                        Math.round(v * 100) / 100);
                }
            }
        }

        // ── L'effetto sulle finestre ─────────────────────────────────────
        //
        // Qui c'era «Sfocatura», quattro scatti da «Nessuna» a «Molta». Erano
        // i numeri che si mandavano a Hyprland, e sotto minerva-wayland non
        // arrivavano da nessuna parte: si sceglieva, e non cambiava niente.
        //
        // Giacomo, 2 settembre 2026: «ci vorrebbero delle impostazioni per
        // mettere nessun effetto o blur o vetro e queste impostazioni si
        // dovrebbero applicare alle finestre e in blur o vetro dovrebbero far
        // vedere un solo corpo trasparente [...] la barra e la finestra senza
        // stacchi di blur o trasparenza».
        //
        // «Blur» ha detto «non ancora» per settimane, ed era la risposta
        // giusta: una voce che dice «non ancora» è un'informazione, una voce
        // che manca è un dubbio. Dal 9 settembre 2026 c'è — un nodo che sfoca
        // dentro il compositore — e dal 20 settembre lo sfoca il NOSTRO
        // fork di wlroots, non più SceneFX. Questa scheda stava in «Aspetto»;
        // sta qui dal 22 settembre 2026, accanto all'elasticità, perché
        // Giacomo ha chiesto un posto solo per gli effetti.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Effetto delle finestre" : "Window effect"
            description: page.it
                ? "Col vetro la finestra e la sua barra sono un corpo solo: "
                  + "una trasparenza sola, senza stacchi in mezzo. "
                  + "L'acquerello prende solo il COLORE di quello che sta "
                  + "dietro e lo stende morbido: niente forme dietro il testo."
                : "With glass, a window and its title bar are one body: a "
                  + "single transparency, with no seam between them. "
                  + "Watercolour takes only the COLOUR of what's behind and "
                  + "spreads it softly: no shapes behind the text."
            searchTerms: "effetto vetro blur acquerello trasparenza materiale sfocatura"
            controlWidth: 340

            control: S.ChoicePicker {
                value: Core.Vetro.effettoChiesto
                options: [
                    { "value": "nessuno", "label": page.it ? "Nessuno" : "None" },
                    { "value": "vetro",   "label": page.it ? "Vetro"   : "Glass" },
                    { "value": "acquerello", "label": page.it ? "Acquerello" : "Watercolour" }
                ]
                onPicked: function(v) {
                    Core.Ipc.setSetting("windows.effetto", v);
                }
            }
        }

        // Mercurio, il secondo materiale di Liquid (27 settembre 2026): le
        // finestre vicine si fondono. Non segue l'interruttore delle
        // animazioni, perché non si muove da solo: è la forma delle finestre.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Mercurio" : "Mercury"
            description: page.it
                ? "Le finestre vicine si fondono con un raccordo morbido, come "
                  + "due gocce che si toccano, e si staccano allontanandole"
                : "Nearby windows melt together with a soft fillet, like two "
                  + "touching drops, and come apart as you move them away"
            searchTerms: "mercurio gocce fondono raccordo finestre vicine liquido"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("windows.mercurio", true)
                onToggled: function (v) {
                    Core.Ipc.setSetting("windows.mercurio", v);
                }
            }
        }

        // Quanto si vede attraverso, col vetro acceso. Sotto il 50% una
        // finestra smette di essere una finestra: si legge lo sfondo
        // attraverso il testo. Il compositore rifiuta comunque sotto 0,50.
        //
        // Ed è UNA per tutte: dal 9 settembre 2026 vale anche per le finestre
        // di Minerva, che prima ne avevano una loro in più e finivano più
        // trasparenti di quelle degli altri senza che nessuno lo dicesse.
        S.SettingRow {
            width: parent.width
            visible: page._effettoAcceso
            label: page.it ? "Quanto si vede attraverso" : "How much shows through"
            description: page.it
                ? "Vale per tutte le finestre allo stesso modo: le nostre e "
                  + "quelle degli altri programmi"
                : "It applies to every window alike: ours and other apps'"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 0.50
                to: 1.00
                value: Core.Ipc.get("windows.effettoOpacita", 0.88)
                onReleased: function(v) {
                    Core.Ipc.setSetting("windows.effettoOpacita",
                                        Math.round(v * 100) / 100);
                }
            }
        }
    }
    Card {
        heading: page.it ? "Elasticità delle finestre" : "Window elasticity"
        S.WobblyControls { width: parent.width }
    }
}

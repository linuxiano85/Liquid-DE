import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import ".." as S

// Animazioni — Come si muove Minerva.
//
// ── Da dove nasce ─────────────────────────────────────────────────────────
//
// Giacomo, 19 agosto 2026: «la disabilitazione dalla barra sul desktop e nelle
// impostazioni non porta a nessun cambiamento [...] non so quali animazioni ho
// a disposizione e voglio poter disabilitare abilitare o cambiare un tipo di
// animazione».
//
// Aveva ragione su tutto e due. L'interruttore c'era ma toccava solo metà del
// movimento (vedi `theme/Motion.qml`), e di quale fosse l'altra metà non c'era
// modo di sapere niente.
//
// ── Perché due elenchi e non uno ──────────────────────────────────────────
//
// Il movimento di Minerva viene da due posti che non si somigliano:
//
//  · la SHELL anima i pannelli, la dock, i menu (durate di `Theme.Motion`);
//  · il COMPOSITORE anima le finestre, le scrivanie, le dissolvenze.
//
// Chi guarda lo schermo non lo sa e non deve saperlo: qui in cima c'è un
// interruttore solo, che li spegne tutti e due. È il difetto che si stava
// riparando — spegnerne uno solo e chiamarlo «animazioni» è quello che non
// portava a nessun cambiamento.
//
// ── E perché «Avanzate» parla un'altra lingua, dichiarandolo ──────────────
//
// I gruppi qui sopra hanno parole nostre, e la tabella verso i nomi di
// Hyprland vive in `core/Compositore.qml` — l'unico posto che può conoscerla.
// Ma le animazioni vere sono trentacinque, e nasconderne ventinove per pulizia
// vorrebbe dire rispondere «non lo so» alla domanda che ha aperto questa
// pagina.
//
// Quindi stanno sotto, chieste al compositore e non scritte da noi, con detto
// a chiare lettere che sono nomi SUOI: cambiano se cambia lui, e non promettono
// di sopravvivere a un cambio di compositore.
Page {
    id: page

    title: Core.Strings.lang === "it" ? "Effetti e animazioni" : "Effects and animations"
    subtitle: Core.Strings.lang === "it"
              ? "Come si muovono le finestre, i pannelli e le scrivanie"
              : "How windows, panels and workspaces move"

    readonly property bool it: Core.Strings.lang === "it"

    readonly property bool accese: Core.Ipc.get("desktop.animations", true)

    /// Vero quando dietro le superfici della scrivania c'è un filtro VERO del
    /// compositore, blur o acquerello. Cambia cosa vogliono dire i cursori
    /// della trasparenza — vedi la scheda «Trasparenza» qui sotto. Deve essere
    /// la stessa domanda che si fa `theme/LegaTema.qml`, o il cursore scrive
    /// una chiave e la membrana ne legge un'altra: si gira e non cambia niente.
    readonly property bool _colFiltro: Core.Vetro.filtroChiesto

    /// Vero quando la trasparenza delle finestre la mette il compositore.
    /// Vedi `Core.Vetro.effettoChiestoAcceso`: da lì in poi «Vetro delle finestre di
    /// Minerva» non ha più niente da regolare.
    readonly property bool _effettoAcceso: Core.Vetro.effettoChiestoAcceso

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

    // ── Trasparenza ──────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Trasparenza" : "Transparency"

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
                   ? "Con l'acquerello o il blur dietro si può scendere molto "
                     + "di più: quello che passa è una macchia morbida, non "
                     + "una fotografia"
                   : "With watercolour or blur behind you can go much lower: "
                     + "what shows through is a soft wash, not a photograph")
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
                  + "dietro e lo stende morbido: niente forme dietro il testo. "
                  + "Il blur lo sfoca, e si vedono ancora le forme."
                : "With glass, a window and its title bar are one body: a "
                  + "single transparency, with no seam between them. "
                  + "Watercolour takes only the COLOUR of what's behind and "
                  + "spreads it softly: no shapes behind the text. Blur "
                  + "softens it, and the shapes still show."
            searchTerms: "effetto vetro blur acquerello trasparenza materiale sfocatura"
            controlWidth: 340

            control: S.ChoicePicker {
                value: String(Core.Ipc.get("windows.effetto", "nessuno"))
                options: [
                    { "value": "nessuno", "label": page.it ? "Nessuno" : "None" },
                    { "value": "vetro",   "label": page.it ? "Vetro"   : "Glass" },
                    { "value": "acquerello", "label": page.it ? "Acquerello" : "Watercolour" },
                    { "value": "blur",    "label": "Blur" }
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

        // ── Quanto sfoca, che NON è quanto si vede attraverso ────────────
        //
        // Giacomo, 20 settembre 2026: «l'opzione quanto si vede attraverso
        // non regola l'intensità del blur». Aveva ragione: erano due cose in
        // una riga sola. Questa è la forza della sfocatura (il raggio del
        // filtro, nel compositore `blur_intensita * 0.06`); quella sotto è la
        // trasparenza. Zero spegne il filtro e lascia il vetro.
        S.SettingRow {
            width: parent.width
            // Solo del blur: l'acquerello non sfoca, prende il colore.
            visible: Core.Vetro.blurChiesto
            label: page.it ? "Intensità della sfocatura" : "Blur strength"
            description: page.it
                ? "Quanto è morbido quello che sta dietro. A zero non sfoca, "
                  + "resta solo la trasparenza"
                : "How soft what's behind becomes. At zero nothing is blurred, "
                  + "only the transparency remains"
            searchTerms: "blur sfocatura intensità forza raggio"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 0
                to: 100
                unit: "intero"
                suffix: "%"
                value: Core.Ipc.get("windows.blurIntensita", 50)
                onReleased: function(v) {
                    Core.Ipc.setSetting("windows.blurIntensita", Math.round(v));
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

    // Qui c'erano «Che cosa si anima» (sei interruttori, uno per gruppo) e
    // «Avanzate» (le animazioni col nome del compositore), con la «scia»
    // sopra. Erano le animazioni di Hyprland: sotto il nostro compositore
    // gli interruttori non mandavano niente, e la chiave `desktop.anim.*`
    // non esisteva fra i valori di fabbrica, quindi il demone non la salvava
    // nemmeno — sei levette sempre accese che non cambiavano niente. Tolte il
    // 27 settembre 2026. I movimenti liquidi delle finestre (Tappa 3)
    // avranno le loro, una per movimento, quando ci saranno.
}

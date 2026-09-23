import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import ".." as S

// Input — Tastiera, touchpad e mouse.
//
// Tutto qui dentro finisce in ~/.config/hypr/minerva-input.conf e viene
// applicato subito con `hyprctl keyword`. Il file si riscrive per intero a
// ogni modifica: è corto, e rigenerarlo evita di doverlo saper leggere.
Page {
    id: page

    title: Core.Strings.lang === "it" ? "Tastiera e mouse" : "Keyboard & mouse"
    subtitle: Core.Strings.lang === "it"
              ? "Disposizione dei tasti, touchpad e velocità del puntatore"
              : "Keyboard layout, touchpad and pointer speed"

    readonly property bool it: Core.Strings.lang === "it"

    // Le impostazioni vivono nel demone, così il pannello le ritrova uguali
    // alla riapertura e il file di Hyprland resta una conseguenza, non la
    // fonte della verità.
    readonly property string layout:      Core.Ipc.get("input.layout", "it")
    readonly property int    repeatRate:  Core.Ipc.get("input.repeatRate", 25)
    readonly property int    repeatDelay: Core.Ipc.get("input.repeatDelay", 600)
    readonly property real   sensitivity: Core.Ipc.get("input.sensitivity", 0)
    readonly property bool   naturalScroll:   Core.Ipc.get("input.naturalScroll", true)
    readonly property bool   tapToClick:      Core.Ipc.get("input.tapToClick", true)
    readonly property bool   disableTyping:   Core.Ipc.get("input.disableWhileTyping", true)

    Core.Exec { id: writer }

    function set(key, value) {
        Core.Ipc.setSetting("input." + key, value);
        applySoon.restart();
    }

    Timer {
        id: applySoon
        interval: 250
        onTriggered: page.apply()
    }

    function apply() {
        var lines = [
            "# Tastiera e mouse — scritto dal pannello Impostazioni di Minerva.",
            "input {",
            "    kb_layout = " + page.layout,
            "    repeat_rate = " + page.repeatRate,
            "    repeat_delay = " + page.repeatDelay,
            "    sensitivity = " + page.sensitivity,
            // ── DUE, e non uno ───────────────────────────────────────────
            //
            // Qui c'era `1`, cioè «il fuoco segue il puntatore», mentre la
            // configurazione principale sceglie `2` con mezza pagina di
            // ragioni («è il modo di Windows, di KDE e di GNOME»). Questo file
            // viene letto DOPO, quindi bastava salvare una qualunque
            // impostazione di tastiera o mouse perché la scelta di fondo
            // saltasse in silenzio.
            //
            // Che cosa si vedeva: con due finestre sovrapposte, spostando il
            // puntatore fuori da quella attiva il fuoco passava a quella
            // dietro — e la barra del titolo di quella davanti spariva,
            // perché per noi «chi copre chi» si stima dall'ordine del fuoco.
            // Parole di Giacomo: «appena sposto il mouse dalla finestra
            // scompare la barra del titolo». Non era la barra: era il fuoco.
            "    follow_mouse = 2",
            // Per la stessa ragione della riga sopra: rimetteva il fuoco sotto
            // il cursore quando una finestra cambiava modo, cioè quando
            // nessuno aveva cliccato niente.
            "    float_switch_override_focus = 0",
            "    accel_profile = flat",
            "    touchpad {",
            "        natural_scroll = " + (page.naturalScroll ? "true" : "false"),
            "        tap-to-click = " + (page.tapToClick ? "true" : "false"),
            "        disable_while_typing = " + (page.disableTyping ? "true" : "false"),
            "        scroll_factor = 0.6",
            "    }",
            "}"
        ];

        var body = lines.join("\n").replace(/'/g, "'\\''");

        // ── Il file, che è la memoria ────────────────────────────────────
        writer.fireSh(
            "d=\"${XDG_CONFIG_HOME:-$HOME/.config}/hypr\"; mkdir -p \"$d\"; " +
            "printf '%s\\n' '" + body + "' > \"$d/.minerva-input.tmp\" && " +
            "mv \"$d/.minerva-input.tmp\" \"$d/minerva-input.conf\"");

        // ── E l'effetto, subito ──────────────────────────────────────────
        //
        // Uno per uno e non con `hyprctl reload`, che rileggerebbe tutto e
        // farebbe ripartire gli `exec-once`: una seconda shell e un secondo
        // demone.
        //
        // Passano dalla porta, e adesso sono ARGOMENTI e non pezzi di una
        // riga di shell. Non è solo ordine: la disposizione della tastiera la
        // sceglie chi usa il computer, e un valore che finisce dentro una
        // riga eseguita da `sh` è un valore che può eseguire — vedi la
        // stessa lezione in `Core.Exec.shArgs`.
        // ── Una funzione sola, non un elenco copiato ─────────────────────
        //
        // Le stesse quattro manopole vanno mandate anche all'AVVIO della
        // sessione, o sotto minerva-wayland restano «non dette» e il tocco del
        // trackpad non clicca finché non si apre questa pagina. Chiamando la
        // stessa funzione che usa `Compositore.applicaIngresso()` non ci sono
        // due elenchi che un giorno non sono più d'accordo: qui si legge dal
        // pannello, là dal demone, ma la riga che parte è la stessa.
        Core.Compositore.applicaIngresso();
    }

    // ── Tastiera ─────────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Tastiera" : "Keyboard"

        S.SettingRow {
            width: parent.width
            label: page.it ? "Disposizione dei tasti" : "Keyboard layout"
            description: page.it
                         ? "Cambia dove stanno le lettere accentate e i simboli"
                         : "Changes where accented letters and symbols live"
            controlWidth: 320

            control: S.ChoicePicker {
                value: page.layout
                options: [
                    { "value": "it",    "label": "Italiano" },
                    { "value": "us",    "label": "English (US)" },
                    { "value": "gb",    "label": "English (UK)" },
                    { "value": "de",    "label": "Deutsch" },
                    { "value": "fr",    "label": "Français" },
                    { "value": "es",    "label": "Español" }
                ]
                onPicked: function(v) { page.set("layout", v); }
            }
        }

        Item {
            width: parent.width
            height: 50

            Text {
                id: rateLabel
                anchors.left: parent.left
                anchors.top: parent.top
                text: page.it ? "Velocità di ripetizione" : "Repeat speed"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeMD
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: rateLabel.verticalCenter
                text: page.repeatRate + (page.it ? " al secondo" : "/s")
                color: Theme.Colors.accent
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeSM
            }

            S.ValueSlider {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                from: 10; to: 60
                // Il numero è già scritto sopra, con le sue parole.
                unit: "niente"
                value: page.repeatRate
                onReleased: function(v) { page.set("repeatRate", Math.round(v)); }
            }
        }

        Item {
            width: parent.width
            height: 50

            Text {
                id: delayLabel
                anchors.left: parent.left
                anchors.top: parent.top
                text: page.it ? "Attesa prima di ripetere" : "Delay before repeating"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeMD
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: delayLabel.verticalCenter
                text: page.repeatDelay + " ms"
                color: Theme.Colors.accent
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeSM
            }

            S.ValueSlider {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                from: 200; to: 1000
                unit: "niente"
                value: page.repeatDelay
                onReleased: function(v) { page.set("repeatDelay", Math.round(v)); }
            }
        }
    }

    // ── Touchpad ─────────────────────────────────────────────────────────

    Card {
        heading: "Touchpad"
        note: page.it
              ? "«Scorrimento naturale» muove il contenuto come su un telefono: "
                + "due dita in giù portano la pagina in giù."
              : "“Natural scrolling” moves the content like on a phone: two "
                + "fingers down move the page down."

        // ── L'interruttore del touchpad ─────────────────────────────
        //
        // `input.touchpadOn` la legge `core/SystemState.qml` ed è quella che
        // muove la scorciatoia «spegni il touchpad». Non aveva una riga qui:
        // chi lo spegneva per sbaglio con la scorciatoia non aveva modo di
        // riaccenderlo se non ritrovando la scorciatoia.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Touchpad acceso" : "Touchpad on"
            description: page.it
                ? "La stessa cosa che fa la scorciatoia, per chi non se la ricorda"
                : "The same thing the shortcut does, for when you forget it"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.SystemState.touchpadOn
                onToggled: function(v) { Core.SystemState.setTouchpad(v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Scorrimento naturale" : "Natural scrolling"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: page.naturalScroll
                onToggled: function(v) { page.set("naturalScroll", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Tocca per fare clic" : "Tap to click"
            description: page.it ? "Un tocco leggero vale come un clic"
                                 : "A light tap counts as a click"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: page.tapToClick
                onToggled: function(v) { page.set("tapToClick", v); }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Ignora il touchpad mentre scrivi"
                           : "Ignore the touchpad while typing"
            description: page.it
                         ? "Evita i salti del cursore quando il palmo lo sfiora"
                         : "Prevents cursor jumps when your palm brushes it"
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: page.disableTyping
                onToggled: function(v) { page.set("disableWhileTyping", v); }
            }
        }
    }

    // ── Puntatore ────────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Puntatore" : "Pointer"

        Item {
            width: parent.width
            height: 50

            Text {
                id: sensLabel
                anchors.left: parent.left
                anchors.top: parent.top
                text: page.it ? "Velocità del puntatore" : "Pointer speed"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeMD
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: sensLabel.verticalCenter
                // Hyprland va da -1 a 1 con 0 al centro: mostrarlo così com'è
                // farebbe pensare che «0» significhi fermo.
                text: (page.sensitivity === 0
                       ? (page.it ? "normale" : "normal")
                       : (page.sensitivity > 0 ? "+" : "") + page.sensitivity.toFixed(2))
                color: Theme.Colors.accent
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeSM
            }

            S.ValueSlider {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                from: -1; to: 1
                // Lo zero è «normale», e sta in mezzo alla corsa: senza
                // aggancio è una posizione su quarantuno, e ci si torna solo
                // per fortuna. Vedi `settings/ValueSlider.qml`.
                aggancioA: 0
                unit: "niente"
                value: page.sensitivity
                onReleased: function(v) {
                    page.set("sensitivity", Math.round(v * 20) / 20);
                }
            }
        }

        // ── Quanto è grande ──────────────────────────────────────────────
        //
        // Giacomo, 5 settembre 2026: «voglio anche un'impostazione per
        // selezionare la grandezza del puntatore». C'era già, in
        // «Accessibilità», e nessuno la cerca lì: chi vuole un puntatore più
        // grande apre la pagina del mouse. Adesso sta in tutte e due, ed è lo
        // STESSO pezzo — vedi `settings/MisuraPuntatore.qml`.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Dimensione del puntatore" : "Pointer size"
            description: page.it
                ? "Utile su schermi grandi o molto fitti"
                : "Useful on large or very dense screens"
            controlWidth: 320

            control: S.MisuraPuntatore {}
        }
    }
}

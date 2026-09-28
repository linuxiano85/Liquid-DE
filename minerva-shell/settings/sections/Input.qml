import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import ".." as S

// Input — Tastiera, touchpad e mouse.
//
// Le scelte stanno nelle impostazioni (le salva il demone) e le applica il
// compositore, subito e a ogni avvio: `Compositore.applicaIngresso()`.
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
        // Qui prima si scriveva anche `~/.config/hypr/minerva-input.conf`,
        // nella lingua di Hyprland: non lo leggeva più nessuno, e stava nella
        // cartella di un altro programma. Resta l'unica strada vera.
        //
        // Una funzione sola, non un elenco copiato: le stesse manopole vanno
        // mandate anche all'AVVIO della sessione, o restano «non dette» e il
        // tocco del touchpad non clicca finché non si apre questa pagina.
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
                // La scala va da -1 a 1 con 0 al centro: «+0.45» non diceva
                // niente a chi lo leggeva. Una parola dice quanto, e il
                // numero fra parentesi resta per chi vuole il valore esatto.
                text: {
                    var v = page.sensitivity;
                    var it = page.it;
                    var parola = Math.abs(v) < 0.05 ? (it ? "normale" : "normal")
                               : v >= 0.6 ? (it ? "molto veloce" : "very fast")
                               : v > 0 ? (it ? "più veloce" : "faster")
                               : v <= -0.6 ? (it ? "molto lento" : "very slow")
                               : (it ? "più lento" : "slower");
                    return Math.abs(v) < 0.05 ? parola
                         : parola + "  (" + (v > 0 ? "+" : "") + v.toFixed(2) + ")";
                }
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

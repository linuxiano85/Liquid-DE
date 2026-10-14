import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import ".." as S

// Scorciatoie — quali tasti sono attivi.
//
// Ogni riga è un'azione del promemoria di Super+K. Spenta, la scorciatoia non
// viene registrata nel compositore e il tasto resta libero: chi non la usa non
// se lo trova più occupato. È il posto da cui si spegne, ad esempio, Super+W
// sul Wi-Fi per chi non vuole quel tasto.
Page {
    id: page

    title: Core.Strings.lang === "it" ? "Scorciatoie" : "Shortcuts"
    subtitle: Core.Strings.lang === "it"
              ? "Quali tasti sono attivi" : "Which keys are active"

    readonly property bool it: Core.Strings.lang === "it"
    /// I `tasti` spenti, come scritti nella sorgente (`$mod W`).
    readonly property var disattivate: Core.Ipc.get("shortcuts.disabled", [])

    function spenta(tasti) {
        return tasti !== "" && page.disattivate.indexOf(tasti) >= 0;
    }

    /// Accende o spegne TUTTI i tasti di una voce (un'azione può avere più
    /// combinazioni, es. Play e Pausa per la musica): si commuta la voce
    /// intera, non un tasto alla volta, così lo stato non resta a metà.
    function commuta(voce) {
        var l = page.disattivate.slice();
        var combos = voce.combos || [];
        var tuttiAttivi = true;
        for (var i = 0; i < combos.length; i++)
            if (page.spenta(String(combos[i].tasti || ""))) { tuttiAttivi = false; break; }
        for (var j = 0; j < combos.length; j++) {
            var t = String(combos[j].tasti || "");
            if (t === "") continue;
            var at = l.indexOf(t);
            if (tuttiAttivi) { if (at < 0) l.push(t); }
            else { if (at >= 0) l.splice(at, 1); }
        }
        Core.Ipc.setSetting("shortcuts.disabled", l);
    }

    /// La combinazione di una voce, leggibile: «Super + W».
    function combinazione(combos) {
        var parti = [];
        for (var i = 0; i < combos.length; i++) {
            var c = combos[i];
            var nomi = (c.mods || []).concat([c.key || ""]);
            parti.push(nomi.filter(function (n) { return n !== ""; }).join(" + "));
        }
        return parti.join(" · ");
    }

    Card {
        heading: page.it ? "Scorciatoie" : "Shortcuts"
        note: page.it
            ? "Spenta, una scorciatoia non fa più niente e il tasto resta libero. "
              + "La riga resta nel promemoria di Super+K, spenta."
            : "Turned off, a shortcut does nothing and the key stays free. "
              + "The entry stays in the Super+K cheat sheet, dimmed."

        Repeater {
            model: Core.Ipc.keybindings
            delegate: S.SettingRow {
                required property var modelData
                width: parent.width
                label: String(modelData.description || modelData.category || "")
                description: page.it
                    ? (String(modelData.category || "") + "  ·  " + page.combinazione(modelData.combos || []))
                    : (String(modelData.category || "") + "  ·  " + page.combinazione(modelData.combos || []))
                control: S.ToggleSwitch {
                    checked: {
                        var combos = modelData.combos || [];
                        if (combos.length === 0) return true;
                        for (var i = 0; i < combos.length; i++)
                            if (page.spenta(String(combos[i].tasti || ""))) return false;
                        return true;
                    }
                    onToggled: function(v) { page.commuta(modelData); }
                }
            }
        }
    }
}

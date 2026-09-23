pragma Singleton
import QtQuick

// Strings — Testi dell'interfaccia e nomi dei tasti nella lingua dell'utente
//
// Serve due scopi:
//  1. tradurre le etichette della shell;
//  2. tradurre i NOMI DEI TASTI, che Hyprland esprime in keysym X11
//     ("Return", "slash", "XF86AudioRaiseVolume", "mouse:272"). Senza questa
//     tabella il pannello Scorciatoie mostrerebbe sigle incomprensibili a
//     chi non conosce X11.
//
// La lingua segue `general.language` nelle impostazioni; con "auto" si usa
// quella di sistema. Cambiarla aggiorna l'interfaccia all'istante, perché
// `lang` è una property e tutto il resto vi si lega.
QtObject {
    id: strings

    /// Lingue con traduzione completa. Le altre ricadono sull'inglese.
    readonly property var supported: ["it", "en"]

    /// Lingua richiesta dalle impostazioni ("auto" = lingua di sistema).
    property string requestedLanguage: "auto"

    /// Lingua effettivamente in uso: sempre una fra `supported`.
    readonly property string lang: {
        var want = requestedLanguage;
        if (!want || want === "auto")
            want = Qt.locale().name.substring(0, 2);
        return supported.indexOf(want) !== -1 ? want : "en";
    }

    // ── Nomi dei modificatori ────────────────────────────────────────────
    readonly property var _mods: ({
        "it": { "SUPER": "Super", "SHIFT": "Maiusc", "CTRL": "Ctrl", "ALT": "Alt" },
        "en": { "SUPER": "Super", "SHIFT": "Shift", "CTRL": "Ctrl", "ALT": "Alt" }
    })

    // ── Nomi dei tasti ───────────────────────────────────────────────────
    // Chiave = keysym così come appare in keybinds.conf (confronto senza
    // distinzione di maiuscole). Assente ⇒ si mostra il keysym in maiuscolo,
    // che per le lettere singole è già la cosa giusta.
    readonly property var _keys: ({
        "it": {
            "return": "Invio", "kp_enter": "Invio", "space": "Spazio",
            "tab": "Tab", "escape": "Esc", "backspace": "Backspace",
            "delete": "Canc", "insert": "Ins", "home": "Inizio", "end": "Fine",
            "prior": "Pag ↑", "next": "Pag ↓", "print": "Stamp",
            "left": "←", "right": "→", "up": "↑", "down": "↓",
            "slash": "/", "minus": "-", "plus": "+", "equal": "=",
            "comma": ",", "period": ".", "semicolon": ";", "apostrophe": "'",
            "bracketleft": "[", "bracketright": "]", "grave": "`",
            "mouse:272": "Clic sinistro", "mouse:273": "Clic destro",
            "mouse:274": "Clic centrale",
            "mouse_down": "Rotella giù", "mouse_up": "Rotella su",
            "xf86audioraisevolume": "Volume +",
            "xf86audiolowervolume": "Volume −",
            "xf86audiomute": "Muto",
            "xf86audiomicmute": "Microfono muto",
            "xf86monbrightnessup": "Luminosità +",
            "xf86monbrightnessdown": "Luminosità −",
            "xf86audioplay": "Play/Pausa",
            "xf86audionext": "Brano succ.",
            "xf86audioprev": "Brano prec."
        },
        "en": {
            "return": "Enter", "kp_enter": "Enter", "space": "Space",
            "tab": "Tab", "escape": "Esc", "backspace": "Backspace",
            "delete": "Del", "insert": "Ins", "home": "Home", "end": "End",
            "prior": "Pg Up", "next": "Pg Dn", "print": "PrtSc",
            "left": "←", "right": "→", "up": "↑", "down": "↓",
            "slash": "/", "minus": "-", "plus": "+", "equal": "=",
            "comma": ",", "period": ".", "semicolon": ";", "apostrophe": "'",
            "bracketleft": "[", "bracketright": "]", "grave": "`",
            "mouse:272": "Left click", "mouse:273": "Right click",
            "mouse:274": "Middle click",
            "mouse_down": "Wheel down", "mouse_up": "Wheel up",
            "xf86audioraisevolume": "Volume +",
            "xf86audiolowervolume": "Volume −",
            "xf86audiomute": "Mute",
            "xf86audiomicmute": "Mic mute",
            "xf86monbrightnessup": "Brightness +",
            "xf86monbrightnessdown": "Brightness −",
            "xf86audioplay": "Play/Pause",
            "xf86audionext": "Next track",
            "xf86audioprev": "Previous track"
        }
    })

    // ── Etichette dell'interfaccia ───────────────────────────────────────
    readonly property var _ui: ({
        "it": {
            "shortcuts": "Scorciatoie",
            "shortcutsHint": "Premi Esc per chiudere · Super+K per riaprire",
            "searchShortcuts": "Cerca una scorciatoia…",
            "noResults": "Nessun risultato",
            "settings": "Impostazioni",
            "apps": "Applicazioni",
            "search": "Cerca…",
            "all": "Tutte",
            "favorites": "Preferiti",
            "close": "Chiudi",
            "cancel": "Annulla",
            "reset": "Ripristina",
            "resetConfirm": "Ripristinare tutte le impostazioni?",
            "language": "Lingua",
            "languageAuto": "Automatica (sistema)",
            "appearance": "Aspetto",
            "help": "Aiuto",
            "showCheatsheet": "Pannello scorciatoie",
            "showCheatsheetDesc": "Attiva il pannello con tutte le combinazioni di tasti (Super+K)",
            "cheatsheetOpacity": "Trasparenza dello sfondo",
            "cheatsheetOpacityDesc": "Quanto si vede la scrivania dietro al pannello",
            "showOnFirstRun": "Mostra all'avvio",
            "showOnFirstRunDesc": "Apre il pannello scorciatoie al primo accesso della sessione",
            "animations": "Animazioni",
            "animationsDesc": "Effetti di apertura e chiusura delle finestre",
            "rightClickMenu": "Menu con il tasto destro",
            "rightClickMenuDesc": "Clic destro sulla scrivania per aprire il menu rapido",
            "windowControls": "Pulsanti della finestra",
            "windowControlsDesc": "Riduci a icona, ingrandisci e chiudi nella barra, accanto al nome della finestra",
            "pluginMorto": "Un'estensione si è fermata",
            "pluginMortoCorpo": "«%1» è terminata da sola. Le altre continuano.",
            "membraneOpacity": "Trasparenza della barra e dei pannelli",
            "membraneOpacityDesc": "Quanto si vede attraverso la superficie di Minerva",
            "notifications": "Notifiche",
            "doNotDisturb": "Non disturbare",
            "doNotDisturbDesc": "Le notifiche continuano ad arrivare ma non compaiono a schermo",
            "fullscreen": "Schermo intero",
            "center": "Centra",
            "newTerminal": "Nuovo terminale",
            "openFiles": "Apri i file",
            "openBrowser": "Apri il browser",
            "lockScreen": "Blocca schermo",
            "power": "Spegni…"
        },
        "en": {
            "shortcuts": "Shortcuts",
            "shortcutsHint": "Press Esc to close · Super+K to reopen",
            "searchShortcuts": "Search a shortcut…",
            "noResults": "No results",
            "settings": "Settings",
            "apps": "Applications",
            "search": "Search…",
            "all": "All",
            "favorites": "Favourites",
            "close": "Close",
            "cancel": "Cancel",
            "reset": "Reset",
            "resetConfirm": "Reset all settings?",
            "language": "Language",
            "languageAuto": "Automatic (system)",
            "appearance": "Appearance",
            "help": "Help",
            "showCheatsheet": "Shortcuts panel",
            "showCheatsheetDesc": "Enable the panel listing every key combination (Super+K)",
            "cheatsheetOpacity": "Background transparency",
            "cheatsheetOpacityDesc": "How much of the desktop shows through the panel",
            "showOnFirstRun": "Show at startup",
            "showOnFirstRunDesc": "Open the shortcuts panel on first login of the session",
            "animations": "Animations",
            "animationsDesc": "Window opening and closing effects",
            "rightClickMenu": "Right-click menu",
            "rightClickMenuDesc": "Right-click the desktop to open the quick menu",
            "windowControls": "Window buttons",
            "windowControlsDesc": "Minimise, maximise and close on the bar, next to the window name",
            "pluginMorto": "An extension stopped",
            "pluginMortoCorpo": "\u00ab%1\u00bb terminated on its own. The others keep going.",
            "membraneOpacity": "Bar and panel transparency",
            "membraneOpacityDesc": "How much shows through Minerva's surface",
            "notifications": "Notifications",
            "doNotDisturb": "Do not disturb",
            "doNotDisturbDesc": "Notifications keep arriving but no longer appear on screen",
            "fullscreen": "Fullscreen",
            "center": "Centre",
            "newTerminal": "New terminal",
            "openFiles": "Open files",
            "openBrowser": "Open browser",
            "lockScreen": "Lock screen",
            "power": "Power…"
        }
    })

    // ── Categorie delle scorciatoie ──────────────────────────────────────
    // Le categorie sono scritte in italiano dentro keybinds.conf; qui le
    // traduciamo. Una categoria non elencata viene mostrata così com'è.
    readonly property var _categories: ({
        "en": {
            "Aiuto": "Help",
            "Applicazioni": "Applications",
            "Finestre": "Windows",
            "Mouse": "Mouse",
            "Scrivanie": "Desktops",
            "Sistema": "System",
            "Multimedia": "Media"
        }
    })

    // ── API ──────────────────────────────────────────────────────────────

    /// Etichetta dell'interfaccia. `t("close")` → "Chiudi".
    function t(key) {
        var table = _ui[lang] || _ui["en"];
        if (table[key] !== undefined)
            return table[key];
        var fallback = _ui["en"][key];
        return fallback !== undefined ? fallback : key;
    }

    /// Nome leggibile di un modificatore (SUPER → "Super").
    function modName(mod) {
        var table = _mods[lang] || _mods["en"];
        return table[mod] || mod;
    }

    /// Nome leggibile di un tasto (Return → "Invio", slash → "/").
    function keyName(key) {
        if (!key)
            return "";
        var table = _keys[lang] || _keys["en"];
        var hit = table[key.toLowerCase()];
        if (hit !== undefined)
            return hit;
        // I tasti funzione e le lettere singole si mostrano in maiuscolo.
        return key.length <= 3 ? key.toUpperCase() : key;
    }

    /// Traduce il nome di una categoria di scorciatoie.
    function categoryName(category) {
        var table = _categories[lang];
        if (table && table[category] !== undefined)
            return table[category];
        return category;
    }

    /// Rende una combinazione come testo unico: "Super + Maiusc + Invio".
    function comboText(combo) {
        if (!combo)
            return "";
        var parts = [];
        var mods = combo.mods || [];
        for (var i = 0; i < mods.length; i++)
            parts.push(modName(mods[i]));
        parts.push(keyName(combo.key));
        return parts.join(" + ");
    }
}

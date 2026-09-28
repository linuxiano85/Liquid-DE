import QtQuick
import "../core" as Core
import "../theme" as Theme

// WobblyControls — Le finestre tremolanti: acceso o spento, e quanto.
//
// Giacomo, 10 settembre 2026: «voglio le finestre tremolanti». E il 12, a
// Codex: «vorrei avere l'effetto e l'impostazione della sua elasticità nelle
// impostazioni».
//
// Un pezzo a sé e non due righe dentro Animazioni, perché sono DUE manopole
// legate: l'interruttore ricorda l'ultima forza scelta (`elasticoUltimo`), e
// riaccendendo si torna lì e non a un valore di fabbrica — spegnere e
// riaccendere non deve far perdere una regolazione.
//
// La forza vale da 0,1 a 3: il compositore la accetta fino a 3 e sotto 0,1
// la molla è così rigida che non si vede niente. Il conto sta in
// `compositore/src/molla.c`, la deformazione in `wobbly.c`.
//
// Il vetro e la sfocatura restano durante la deformazione: il blur segue la
// forma piegata con la maschera di trasparenza di SceneFX (13 settembre
// 2026). Qui c'era una nota che diceva il contrario, di quando non era così.
Column {
    id: controls
    readonly property bool it: Core.Strings.lang === "it"
    readonly property bool animazioni: Core.Ipc.get("desktop.animations", true)
    readonly property real forza: Number(Core.Ipc.get("windows.elastico", 0))
    readonly property bool acceso: isFinite(forza) && forza > 0
    spacing: Theme.Effects.space3

    function limita(v) {
        return isFinite(Number(v)) ? Math.max(0.1, Math.min(3, Number(v))) : 1;
    }

    SettingRow {
        width: parent.width
        label: controls.it ? "Finestre elastiche (Wobbly Windows)" : "Wobbly Windows"
        description: !Core.Compositore.nostro
            ? (controls.it ? "Disponibile nel compositore Minerva" : "Available in the Minerva compositor")
            : !controls.animazioni
                ? (controls.it ? "In pausa: le animazioni sono disattivate" : "Paused: animations are disabled")
                : (controls.it ? "La finestra si deforma mentre la trascini e rimbalza al rilascio"
                               : "Windows bend while dragging and wobble when released")
        controlWidth: 60
        control: ToggleSwitch {
            objectName: "wobblyToggle"
            enabled: Core.Compositore.nostro
            Accessible.name: controls.it ? "Finestre elastiche" : "Wobbly Windows"
            checked: controls.acceso
            onToggled: function(v) {
                if (v) {
                    Core.Ipc.setSetting("windows.elastico",
                        controls.limita(Core.Ipc.get("windows.elasticoUltimo", 1)));
                } else {
                    Core.Ipc.setSettings({"windows.elastico": 0,
                        "windows.elasticoUltimo": controls.limita(controls.forza)});
                }
                checked = Qt.binding(function() { return controls.acceso; });
            }
        }
    }

    SettingRow {
        width: parent.width
        visible: controls.acceso
        label: controls.it ? "Elasticità" : "Elasticity"
        description: controls.it ? "Da 0,1 (rigida) a 3 (morbida). 1 è il valore normale"
                                 : "From 0.1 (stiff) to 3 (soft). 1 is the normal value"
        controlWidth: 260
        control: ValueSlider {
            objectName: "wobblyElasticity"
            enabled: Core.Compositore.nostro && controls.animazioni
            Accessible.name: controls.it ? "Elasticità delle finestre" : "Window elasticity"
            from: 0.1; to: 3; aggancioA: 1; unit: "numero"
            value: controls.limita(controls.forza)
            onReleased: function(v) {
                Core.Ipc.setSetting("windows.elastico", Math.round(controls.limita(v) * 10) / 10);
                value = Qt.binding(function() { return controls.limita(controls.forza); });
            }
        }
    }
    SettingRow {
        width: parent.width
        label: controls.it ? "Comportamento" : "Behavior"
        controlWidth: 300
        control: ChoicePicker {
            // Quello che è acceso adesso, ricavato dai numeri: fino al 28
            // settembre 2026 era sempre vuoto, e non si capiva quale dei tre
            // fosse in uso. Se i numeri non sono di nessuno dei tre (li hai
            // toccati nelle opzioni avanzate) non se ne accende nessuno.
            value: {
                var f = controls.forza;
                var s = Number(Core.Ipc.get("windows.smorzamento", 0.42));
                var r = Number(Core.Ipc.get("windows.rigidita", 1));
                function vicino(a, b) { return Math.abs(a - b) < 0.01; }
                if (!vicino(r, 1)) return "";
                if (vicino(f, 0.6) && vicino(s, 0.65)) return "gentle";
                if (vicino(f, 1) && vicino(s, 0.42)) return "normal";
                if (vicino(f, 2) && vicino(s, 0.25)) return "elastic";
                return "";
            }
            options: [{value: "gentle", label: controls.it ? "Delicato" : "Gentle"},
                      {value: "normal", label: controls.it ? "Normale" : "Normal"},
                      {value: "elastic", label: controls.it ? "Elastico" : "Elastic"}]
            onPicked: function(v) {
                var strength = v === "gentle" ? 0.6 : v === "elastic" ? 2 : 1;
                Core.Ipc.setSettings({"windows.elastico": strength,
                    "windows.elasticoUltimo": strength, "windows.rigidita": 1,
                    "windows.smorzamento": v === "gentle" ? 0.65 : v === "elastic" ? 0.25 : 0.42});
            }
        }
    }
    SettingRow {
        width: parent.width
        label: controls.it ? "Opzioni avanzate" : "Advanced options"
        control: ToggleSwitch { checked: advanced.visible; onToggled: function(v) { advanced.visible = v; } }
    }
    Column {
        id: advanced
        width: parent.width
        visible: false
        SettingRow {
            width: parent.width
            label: controls.it ? "Rigidità" : "Stiffness"
            control: ValueSlider {
                width: 260; from: 0.5; to: 2; unit: "numero"
                value: Core.Ipc.get("windows.rigidita", 1)
                onReleased: function(v) { Core.Ipc.setSetting("windows.rigidita", Math.round(v * 100) / 100); }
            }
        }
        SettingRow {
            width: parent.width
            label: controls.it ? "Smorzamento" : "Damping"
            description: controls.it ? "Più alto: meno rimbalzi" : "Higher: fewer bounces"
            control: ValueSlider {
                width: 260; from: 0.15; to: 0.95; unit: "numero"
                value: Core.Ipc.get("windows.smorzamento", 0.42)
                onReleased: function(v) { Core.Ipc.setSetting("windows.smorzamento", Math.round(v * 100) / 100); }
            }
        }
    }

}

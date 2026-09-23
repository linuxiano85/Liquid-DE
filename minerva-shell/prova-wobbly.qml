import QtQuick
import Quickshell
import "settings" as S
import "core" as Core

// Test del pannello: eseguire solo con IPC assente e sessione di prova.
ShellRoot {
    id: root
    S.WobblyControls { id: controls; width: 800 }
    function trova(item, name) {
        if (item.objectName === name) return item;
        var figli = item.children || [];
        for (var i = 0; i < figli.length; i++) {
            var found = trova(figli[i], name);
            if (found) return found;
        }
        return null;
    }
    function verifica(value, message) {
        if (!value) throw new Error("WOBBLY FAIL: " + message);
    }
    Component.onCompleted: {
        verifica(Quickshell.env("MINERVA_SESSIONE") === "prova-wobbly", "sessione isolata richiesta");
        verifica(String(Quickshell.env("MINERVA_IPC_SOCKET")).endsWith("/assente.sock"), "IPC assente richiesto");
        Core.Ipc.settings = {windows: {elastico: 0, elasticoUltimo: 1}, desktop: {animations: true}};
        Qt.callLater(function() {
            var toggle = trova(controls, "wobblyToggle");
            var slider = trova(controls, "wobblyElasticity");
            verifica(toggle && slider, "controlli caricati");
            verifica(!controls.acceso, "spento di fabbrica");
            toggle.toggled(true);
            verifica(controls.forza === 1, "attivazione");
            slider.released(2.36);
            verifica(controls.forza === 2.4, "regolazione arrotondata");
            toggle.toggled(false);
            verifica(!controls.acceso, "spegnimento");
            toggle.toggled(true);
            verifica(controls.forza === 2.4, "elasticità ricordata");
            Core.Ipc.setSetting("desktop.animations", false);
            verifica(!slider.enabled, "rispetta animazioni spente");
            verifica(controls.limita(NaN) === 1 && controls.limita(99) === 3, "limiti");
            console.log("WOBBLY OK: controlli, regolazione, memoria, animazioni e limiti");
            Qt.quit();
        });
    }
    Timer { interval: 4000; running: true; onTriggered: { console.error("WOBBLY FAIL: timeout"); Qt.quit(); } }
}

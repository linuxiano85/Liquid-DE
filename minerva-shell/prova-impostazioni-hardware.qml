import QtQuick
import Quickshell
import "settings/sections" as Pages
import "settings" as Settings

ShellRoot {
    id: root
    property int loaded: 0
    Component { id: displayPage; Pages.Display { width: 1000; height: 800 } }
    Component { id: audioPage; Pages.Audio { width: 1000; height: 800 } }
    Component { id: appearancePage; Pages.Animazioni { width: 1000; height: 800 } }
    Component { id: wobbly; Settings.WobblyControls { width: 800 } }
    property var instances: []
    Component.onCompleted: {
        if (Quickshell.env("MINERVA_SESSIONE") !== "prova-hardware" ||
                !String(Quickshell.env("MINERVA_IPC_SOCKET")).endsWith("/assente.sock"))
            throw new Error("Serve una sessione isolata");
        var components = [displayPage, audioPage, appearancePage, wobbly];
        for (var i = 0; i < components.length; i++) {
            var object = components[i].createObject(root);
            if (!object) throw new Error("Creazione pagina fallita: " + i);
            instances.push(object);
            loaded++;
        }
    }
    // ── E la pagina Schermi deve avere gli schermi ───────────────────────
    //
    // Non basta che carichi. Il 22 settembre 2026 il riquadro «Schermi» si è
    // aperto VUOTO su un computer che lo schermo ce l'ha davanti, e si
    // riempiva solo cambiando sezione e tornando indietro.
    //
    // Va detto cosa questa prova sorveglia e cosa no: qui il compositore c'è
    // (headless, una uscita) e il demone no, quindi la coda delle risposte
    // resta corta. Il caso vero — la coda piena delle novanta scorciatoie
    // dell'avvio, che faceva attribuire l'elenco a un altro verbo — non si
    // riproduce da qui, ed è coperto solo dalla difesa in `Compositore.qml`
    // (`ok [{"nome"` riconosciuto dalla forma) e dalla prova a schermo.
    Timer {
        interval: 2500; running: true
        onTriggered: {
            var schermi = root.instances.length > 0 ? root.instances[0].monitors : [];
            console.log("HARDWARE QML: " + root.loaded + "/4 pagine caricate, "
                        + schermi.length + " schermi nella pagina");
            Qt.quit();
        }
    }
}

import QtQuick
import Quickshell
import "../../minerva-shell/greeter" as Login
import "../../minerva-shell/blocco" as Lock
import "../../minerva-shell/core" as Core

ShellRoot {
    id: test
    property int stage: 0
    property int ticks: 0
    property int unlocked: 0
    property bool broken: Quickshell.env("NATIVE_BROKEN") === "1"
    property var field: null
    property int captures: 0
    function check(value, name) {
        if (!value) throw new Error(name);
        console.log("NATIVE_CHECK " + name);
    }
    function input(item) {
        if (item.echoMode !== undefined && typeof item.insert === "function") return item;
        var children = item.children || [];
        for (var i = 0; i < children.length; i++) {
            var found = input(children[i]); if (found) return found;
        }
        return null;
    }
    function snapshot(name) {
        captures++;
        var ok = canvas.grabToImage(function(result) {
            if (!result.saveToFile(Quickshell.env("NATIVE_OUTPUT") + "/" + name + ".png"))
                console.log("NATIVE_FAIL screenshot " + name);
            captures--;
        });
        check(ok, "capture-started-" + name);
    }
    FloatingWindow {
        id: window
        visible: true
        title: "Liquid native authentication tests"
        implicitWidth: 1360
        implicitHeight: 768
        color: "black"
        Item {
            id: canvas
            anchors.fill: parent
            Login.Greeter { id: login; anchors.fill: parent; visible: test.stage < 3 }
            Lock.Blocco { id: lock; anchors.fill: parent; visible: test.stage >= 3
                onSbloccato: test.unlocked++
            }
        }
    }
    Timer {
        interval: 150
        running: true
        repeat: true
        onTriggered: {
            try {
                test.ticks++;
                if (test.ticks > 200) throw new Error("native test timed out at stage " + test.stage);
                if (test.stage === 0) {
                    Core.Ipc.settings = {greeter: {meteo: false, stato: false, lato: "sinistra"}};
                    Core.Ipc.greeterInfoReceived({greetd: false, avviatore: false,
                        utenti: [{nome: "liquidci", nomeCompleto: "Liquid CI"}],
                        sessioni: [{id: "test", nome: "Liquid test", comando: "true", tipo: "wayland"}]});
                    test.stage = 1;
                } else if (test.stage === 1) {
                    test.check(login.informato && login.finto && login.domanda !== "", "production-greeter-loaded");
                    test.field = test.input(login);
                    test.check(test.field !== null && test.field.width > 0, "greeter-password-field-visible");
                    test.field.forceActiveFocus();
                    test.snapshot("greeter");
                    test.stage = 2;
                } else if (test.stage === 2 && test.captures === 0) {
                    test.field.text = "fictitious-preview-input";
                    login.rispondi(test.field.text);
                    test.check(test.field.text === "" && !login.inCorso && !login.avviato, "preview-cannot-login-and-clears-input");
                    test.stage = 3;
                } else if (test.stage === 3) {
                    test.field = test.input(lock);
                    test.check(test.field !== null && test.field.echoMode === TextInput.Password, "production-lock-loaded-masked");
                    test.field.text = ""; lock.prova();
                    test.check(!lock.inCorso && test.unlocked === 0, "empty-password-does-not-authenticate");
                    test.field.text = "wrong-ci-password";
                    lock.prova(); lock.prova();
                    test.check(lock.inCorso, "pam-started-duplicate-submit-ignored");
                    test.stage = 4;
                } else if (test.stage === 4 && !lock.inCorso) {
                    test.check(test.unlocked === 0 && test.field.text === "", "failure-keeps-lock-and-clears-input");
                    if (test.broken) {
                        test.check(lock.avviso.indexOf("Cannot verify:") === 0 || lock.avviso.indexOf("Non riesco a verificare:") === 0,
                            "pam-system-error-is-not-wrong-password");
                        test.check(lock.errori === 0 && !lock.inPausa,
                            "pam-system-error-does-not-penalize-password");
                        test.snapshot("lock-pam-error");
                        test.stage = 7; return;
                    }
                    test.check(lock.errori === 1 && lock.avviso !== "", "wrong-password-rejected-once");
                    test.snapshot("lock-wrong-password");
                    test.stage = 5;
                } else if (test.stage === 5 && !lock.inPausa && test.captures === 0) {
                    test.field.text = "Liquid-CI-only-42!";
                    lock.prova(); test.stage = 6;
                } else if (test.stage === 6 && !lock.inCorso) {
                    test.check(test.unlocked === 1 && lock.errori === 0, "real-pam-correct-password-unlocks-once");
                    test.check(test.field.text === "", "success-clears-password-field");
                    console.log("NATIVE_GRAPHICS_PAM_PASSED"); Qt.quit();
                } else if (test.stage === 7 && test.captures === 0) {
                    console.log("NATIVE_PAM_ERROR_PASSED"); Qt.quit();
                }
            } catch (error) { console.log("NATIVE_FAIL " + error); Qt.quit(); }
        }
    }
}

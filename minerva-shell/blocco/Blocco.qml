import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui
import "../greeter/aurora"
import "." as Schermo

// Blocco — La schermata di blocco di Minerva.
//
// ── Perché non basta hyprlock ──────────────────────────────────────────────
//
// Perché funziona benissimo e non è nostro. Minerva ha già una schermata di
// accesso con la sua aurora, il suo orologio, il suo ritratto; poi si preme
// Super+L e compare la schermata di un altro programma, con un altro carattere
// e un altro modo di dire «password sbagliata». È l'unico punto in cui la
// scrivania smette di somigliare a sé stessa, e capita dieci volte al giorno.
//
// ── Chi verifica la password ───────────────────────────────────────────────
//
// PAM, direttamente. NON greetd: greetd apre sessioni nuove, e qui la sessione
// c'è già ed è quella di chi sta guardando. Chiedere a greetd vorrebbe dire
// aprirne una seconda per poi buttarla via — cioè fidarsi che vada tutto bene
// in una strada che non porta da nessuna parte.
//
// Il file di configurazione è `/etc/pam.d/liquid-de`, e se non c'è si ripiega su
// quello di hyprlock — che su Arch esiste sempre ed è due righe: `auth include
// login`. Il ripiego non è pigrizia: è che un blocco schermo che non riesce a
// verificare NIENTE è un blocco schermo che non si apre più.
Item {
    id: blocco

    /// Emesso quando la password è giusta. Chi ci sta sopra scioglie il blocco.
    signal sbloccato()

    readonly property bool it: Core.Strings.lang === "it"
    readonly property string utente: Quickshell.env("USER") || "utente"

    // ── Come la schermata di accesso ─────────────────────────────────────
    //
    // Dal 23 settembre 2026 le due schermate hanno la stessa disposizione e
    // leggono le stesse chiavi (`greeter.*`, che la pagina Accesso scrive):
    // ora e password in colonna su un lato, meteo tastiera e batteria in
    // alto, e qui — dove la sessione c'è ed è accesa — le notifiche arrivate
    // mentre eri via nella metà libera.
    readonly property string lato: Core.Ipc.get("greeter.lato", "sinistra")
    readonly property real asse: blocco.lato === "destra" ? blocco.width * 0.72
                               : blocco.lato === "centro" ? blocco.width / 2
                               : blocco.width * 0.28
    readonly property bool conSaluto: Core.Ipc.get("greeter.saluto", true)

    /// Le maiuscole bloccate, indovinate dai tasti come nella schermata di
    /// accesso (vedi lì il perché): Qt non dice lo stato del Bloc Maiusc.
    property bool maiuscole: false
    property bool maiuscoleNote: false

    function saluto(ora) {
        var h = ora.getHours();
        if (h >= 5 && h < 12)  return blocco.it ? "Buongiorno" : "Good morning";
        if (h >= 12 && h < 18) return blocco.it ? "Buon pomeriggio" : "Good afternoon";
        if (h >= 18 && h < 23) return blocco.it ? "Bentornato" : "Welcome back";
        return blocco.it ? "Buonanotte" : "Good night";
    }

    // ── Lo stato ─────────────────────────────────────────────────────────

    /// Vero mentre PAM sta pensando. Il campo si chiude: una seconda password
    /// mandata mentre la prima è in volo confonde la macchina a stati di PAM.
    property bool inCorso: false
    /// Quante volte di fila si è sbagliato, e la pausa: UNO per tutto il
    /// blocco, non uno per schermo (vedi `Tentativi.qml`). `blocco.qml` passa
    /// il suo; quello di serie serve solo a chi usa questa schermata da sola.
    property Schermo.Tentativi tentativi: Schermo.Tentativi {}
    readonly property int errori: blocco.tentativi.errori
    property string avviso: ""

    // ── La pausa che cresce ──────────────────────────────────────────────
    //
    // Non è una punizione per chi digita male: è ciò che impedisce a un
    // programma di provare diecimila password al minuto su una macchina
    // lasciata accesa. Cresce e si ferma a otto secondi, perché oltre quella
    // soglia dà fastidio a chi la password la sa e non ferma di più chi non
    // la sa (a quel punto tanto vale spegnere il computer e portarselo via).
    readonly property int pausa: blocco.tentativi.pausa
    readonly property bool inPausa: blocco.tentativi.inPausa

    PamContext {
        id: pam
        // `config` è il NOME del file dentro /etc/pam.d, non un percorso.
        // Lo sceglie `scripts/minerva-blocca`, che prima va a vedere quale
        // esiste: il nostro se c'è, quello di hyprlock se no. Se non ne
        // trovasse nessuno non ci lancerebbe nemmeno.
        config: Quickshell.env("MINERVA_PAM") || "liquid-de"
        user: blocco.utente

        onCompleted: function (result) {
            blocco.inCorso = false;
            if (result === PamResult.Success) {
                blocco.tentativi.giusto();
                blocco.avviso = "";
                blocco.sbloccato();
                return;
            }
            blocco.tentativi.sbagliato();
            campo.text = "";
            blocco.avviso = result === PamResult.MaxTries
                ? (blocco.it ? "Troppi tentativi. Aspetta un momento."
                             : "Too many attempts. Wait a moment.")
                : (blocco.it ? "Password sbagliata" : "Wrong password");
            scossa.restart();
        }

        onError: function (e) {
            blocco.inCorso = false;
            // Qui NON si dice «password sbagliata»: non lo sappiamo. Un errore
            // di PAM è un guasto — file di configurazione assente, permessi —
            // e confonderlo con una password sbagliata manda chi guarda a
            // ridigitare all'infinito una password giusta.
            blocco.avviso = (blocco.it ? "Non riesco a verificare: " : "Cannot verify: ")
                            + PamError.toString(e);
        }

        // `responseRequired` è una PROPRIETÀ, non un segnale: il gestore è
        // `onResponseRequiredChanged`. Scritto come `onResponseRequired`, QML
        // rifiuta di caricare il file — e per una schermata di blocco «non si
        // carica» vuol dire che il tasto Super+L non fa niente.
        onResponseRequiredChanged: {
            if (pam.responseRequired)
                pam.respond(campo.text);
        }
    }

    function prova() {
        if (blocco.inCorso || blocco.inPausa || campo.text === "")
            return;
        blocco.avviso = "";
        blocco.inCorso = true;
        if (!pam.start()) {
            blocco.inCorso = false;
            blocco.avviso = blocco.it
                ? "PAM non risponde: il blocco non può verificare la password."
                : "PAM is not answering: this lock cannot check the password.";
        }
    }

    // ── Lo sfondo ────────────────────────────────────────────────────────

    Aurora {
        anchors.fill: parent
        forza: Core.Ipc.get("greeter.auroraStrength", 0.55)
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.28) }
            GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.38) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
        }
    }

    // ── La riga in alto: meteo, tastiera, batteria ───────────────────────

    Ui.StatoSchermata {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.Effects.space6
        it: blocco.it
        conMeteo: Core.Ipc.get("greeter.meteo", true) && Core.Meteo.attivo
        conStato: Core.Ipc.get("greeter.stato", true)
        disposizione: String(Core.Ipc.get("input.layout", "")).toUpperCase()
    }

    // ── Le notifiche, nella metà libera ──────────────────────────────────
    //
    // Al centro della metà che l'ora e la password lasciano libera. Con la
    // colonna al centro («centro») non c'è una metà libera: restano sotto,
    // strette, perché la password viene prima.
    Schermo.Notifiche {
        width: Math.min(420, Math.round(blocco.width * 0.34))
        height: blocco.height * 0.7
        anchors.verticalCenter: parent.verticalCenter
        x: blocco.lato === "destra" ? Math.round(blocco.width * 0.28 - width / 2)
         : blocco.lato === "centro" ? Math.round(blocco.width - width - Theme.Effects.space6)
         : Math.round(blocco.width * 0.72 - width / 2)
        it: blocco.it
    }

    // ── L'ora ────────────────────────────────────────────────────────────

    Column {
        id: orologio
        x: Math.round(blocco.asse - width / 2)
        anchors.bottom: colonna.top
        anchors.bottomMargin: Theme.Effects.space7
        spacing: 2

        property date adesso: new Date()
        Timer {
            interval: 1000; running: true; repeat: true
            // Si rilegge l'ora vera invece di sommare un secondo: un timer che
            // somma scivola, e questa schermata resta aperta tutta la notte.
            onTriggered: parent.adesso = new Date()
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            // ── L'orologio della SCHERMATA DI BLOCCO leggeva una chiave sua
            //
            // `shell.clock24`, che non scrive nessuno: nelle Impostazioni →
            // Data e ora si sceglie fra 12 e 24 ore, e quella riga scrive
            // `clock.format24` (la barra) e `greeter.clock24` (l'accesso).
            // Risultato: si metteva l'orologio a dodici ore e la schermata di
            // blocco restava a ventiquattro, per sempre, senza che nulla lo
            // dicesse.
            //
            // Trovato dal banco delle manopole il 9 settembre 2026 — «shell.
            // clock24 non muove» — che è esattamente il mestiere per cui è
            // stato scritto: una chiave che esiste, si legge, e non ha nessuno
            // che la scriva.
            text: Qt.formatTime(parent.adesso,
                                Core.Ipc.get("clock.format24", true) ? "HH:mm" : "h:mm AP")
            color: Theme.Colors._bianco
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Math.round(blocco.height * 0.135)
            font.weight: Theme.Typography.weightLight
            font.letterSpacing: 1
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            // `Qt.formatDate` usa la lingua DI SISTEMA, non quella di Minerva:
            // la si passa a mano, o in italiano esce «Tuesday 4 August».
            text: {
                var loc = Qt.locale(blocco.it ? "it_IT" : "en_GB");
                var d = parent.adesso.toLocaleDateString(
                            loc, blocco.it ? "dddd d MMMM" : "dddd, d MMMM");
                return d.charAt(0).toUpperCase() + d.slice(1);
            }
            color: Qt.alpha(Theme.Colors._bianco, 0.66)
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeLG
            font.weight: Theme.Typography.weightMedium
            font.letterSpacing: Theme.Typography.trackingTitle
        }
    }

    // ── Il nome e la password ────────────────────────────────────────────

    Column {
        id: colonna
        x: Math.round(blocco.asse - width / 2)
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: Math.round((orologio.height + Theme.Effects.space7) / 2)
        spacing: Theme.Effects.space4

        // Lo scatto orizzontale quando la password è sbagliata: è l'unico
        // messaggio che si capisce senza leggere. Tre scatti e basta — nella
        // schermata di accesso era senza fine, e Giacomo l'ha descritta come
        // «dolori di pancia».
        property real scarto: 0
        transform: Translate { x: colonna.scarto }

        SequentialAnimation {
            id: scossa
            loops: 3
            NumberAnimation { target: colonna; property: "scarto"; to: 10
                              duration: 45; easing.type: Easing.OutSine }
            NumberAnimation { target: colonna; property: "scarto"; to: -10
                              duration: 90; easing.type: Easing.InOutSine }
            NumberAnimation { target: colonna; property: "scarto"; to: 0
                              duration: 45; easing.type: Easing.InSine }
        }

        // ── Il ritratto ──────────────────────────────────────────────
        //
        // Lo stesso che si sceglie in Impostazioni → Utente e che si vede
        // nella schermata di accesso: è la stessa persona davanti alla stessa
        // macchina, e vederlo in uno dei due posti soltanto fa sembrare che
        // siano due programmi diversi — che è esattamente il difetto per cui
        // questa schermata è stata scritta invece di usare hyprlock.
        //
        // Si legge direttamente da `/var/lib/AccountsService/icons/<utente>`
        // senza chiedere niente al demone: quel file è di root ma leggibile da
        // tutti, la schermata di blocco gira nella sessione di chi lo possiede,
        // e una schermata di blocco che deve aspettare una risposta per
        // disegnarsi è una schermata che a demone fermo resta vuota.
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 108
            height: 108

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                visible: !ritratto.visible
                color: Qt.alpha(Theme.Colors._nero, 0.34)
                border.width: 1
                border.color: Qt.alpha(Theme.Colors._bianco, 0.20)

                Text {
                    anchors.centerIn: parent
                    text: blocco.utente.charAt(0).toUpperCase()
                    color: Theme.Colors._bianco
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: 44
                    font.weight: Theme.Typography.weightLight
                }
            }

            Image {
                id: ritratto
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
                // `~/.face` come ripiego: è la convenzione più vecchia, ed è
                // la stessa che guarda il demone per la schermata di accesso.
                //
                // Si carica solo un ritratto che c'è. Prima si provavano tutti
                // e due alla cieca, e chi non ne ha nessuno si trovava due
                // «Cannot open» nel registro a ogni blocco — proprio il
                // registro che si legge quando il blocco non va.
                source: ritrattoCercato.trovato !== "" ? "file://" + ritrattoCercato.trovato : ""

                Process {
                    id: ritrattoCercato
                    property string trovato: ""
                    running: true
                    command: ["sh", "-c",
                        "for f in \"$1\" \"$2\"; do [ -r \"$f\" ] && { printf '%s' \"$f\"; exit 0; }; done",
                        "sh",
                        "/var/lib/AccountsService/icons/" + blocco.utente,
                        Quickshell.env("HOME") + "/.face"]
                    stdout: StdioCollector {
                        onStreamFinished: ritrattoCercato.trovato = text.trim()
                    }
                }
                // Il tondo. `Image` non ritaglia da sé: la maschera è la
                // stessa che usa la schermata di accesso, e va tenuta uguale —
                // un ritratto tondo di là e quadrato di qua è il genere di
                // differenza che si nota senza saper dire cos'è.
                layer.enabled: visible
                layer.effect: MultiEffect { maskEnabled: true; maskSource: maschera }
            }

            Item {
                id: maschera
                anchors.fill: parent
                visible: false
                layer.enabled: true
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "black"
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                var n = blocco.utente.charAt(0).toUpperCase() + blocco.utente.slice(1);
                return blocco.conSaluto ? blocco.saluto(orologio.adesso) + ", " + n : n;
            }
            color: Theme.Colors._bianco
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXL
            font.weight: Theme.Typography.weightSemiBold
            font.letterSpacing: Theme.Typography.trackingTitle
        }

        // La pillola. Nessun riquadro attorno: galleggia sullo sfondo, come
        // nella schermata di accesso.
        Rectangle {
            id: pillola
            anchors.horizontalCenter: parent.horizontalCenter
            width: 320
            height: 52
            radius: height / 2
            color: Qt.alpha(Theme.Colors._nero, 0.34)
            border.width: 1
            border.color: campo.activeFocus
                ? Qt.alpha(Theme.Colors.accent, 0.75)
                : Qt.alpha(Theme.Colors._bianco, 0.20)
            opacity: blocco.inPausa ? 0.45 : 1
            Behavior on opacity { NumberAnimation { duration: 140 } }

            TextInput {
                id: campo
                anchors.fill: parent
                // I margini SOLO ai lati: `anchors.margins` toglierebbe spazio
                // anche sopra e sotto, e con `clip` acceso un carattere da 16
                // dentro 12 pixel si vede a metà. È già successo nel gestore
                // file e nella password del wi-fi.
                anchors.leftMargin: Theme.Effects.space4
                anchors.rightMargin: Theme.Effects.space4
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                echoMode: TextInput.Password
                passwordCharacter: "•"
                enabled: !blocco.inCorso && !blocco.inPausa
                color: Theme.Colors._bianco
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeMD
                selectionColor: Qt.alpha(Theme.Colors.accent, 0.5)
                onAccepted: blocco.prova()

                Keys.onPressed: function (e) {
                    if (e.key === Qt.Key_CapsLock) {
                        if (blocco.maiuscoleNote)
                            blocco.maiuscole = !blocco.maiuscole;
                        return;
                    }
                    var t = e.text;
                    if (t.length === 1 && t.toLowerCase() !== t.toUpperCase()) {
                        blocco.maiuscole = (t === t.toUpperCase())
                                           !== ((e.modifiers & Qt.ShiftModifier) !== 0);
                        blocco.maiuscoleNote = true;
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: campo.text === "" && !blocco.inCorso
                    text: blocco.it ? "Password" : "Password"
                    color: Qt.alpha(Theme.Colors._bianco, 0.42)
                    font: campo.font
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property bool soloMaiuscole: !blocco.inCorso
                && blocco.avviso === "" && blocco.maiuscole
            text: blocco.inCorso
                  ? (blocco.it ? "Verifico…" : "Checking…")
                  : soloMaiuscole ? (blocco.it ? "Maiuscole bloccate" : "Caps Lock is on")
                  : blocco.avviso
            color: soloMaiuscole ? Theme.Colors.warning
                 : blocco.avviso !== "" && !blocco.inCorso
                   ? Theme.Colors.danger : Qt.alpha(Theme.Colors._bianco, 0.7)
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            opacity: text === "" ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }

    // Il fuoco alla tastiera, e riconquistarlo se lo si perde: qui non c'è
    // nient'altro con cui parlare, e un campo senza fuoco è un blocco schermo
    // che sembra rotto.
    Component.onCompleted: campo.forceActiveFocus()
    onVisibleChanged: if (blocco.visible) campo.forceActiveFocus()
}

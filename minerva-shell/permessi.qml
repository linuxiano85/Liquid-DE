//@ pragma AppId minerva-permessi
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

import "theme" as Theme
import "core" as Core

// permessi.qml — La finestra della password di Minerva.
//
// Non si lancia a mano. La apre `minerva-polkit` quando qualcosa chiede il
// permesso di amministratore, e le passa il percorso di un socket in
// `MINERVA_POLKIT_CANALE`.
//
// ── Perché esiste ─────────────────────────────────────────────────────────
//
// Fino al 1º settembre 2026 questa finestra era di `hyprpolkitagent`, o di
// KDE, o di GNOME — `minerva-dentro-wayland` ne provava sei in fila e teneva
// il primo che trovava. Funzionava, e si vedeva: in mezzo alla scrivania di
// Minerva compariva la finestra di un altro ambiente, con un altro carattere e
// un altro modo di dire «password sbagliata». È la stessa ragione per cui il
// blocco schermo ha smesso di essere `hyprlock`.
//
// ── Quello che questa finestra NON fa ─────────────────────────────────────
//
// Non verifica niente. Raccoglie del testo e lo manda sul socket; a
// verificarlo è `polkit-agent-helper-1`, che è setuid e parla PAM, e a
// decidere è `polkitd`, che gira come root. È deliberato e sta scritto anche
// in `permessi/src/minerva-polkit.c`: polkitd non si fida di nessun agente,
// e ha ragione.
//
// Perciò qui non c'è nessuna `PamContext` — a differenza del blocco schermo,
// che invece PAM lo chiama davvero perché lì la sessione è già aperta e non
// c'è nessun polkit di mezzo.
//
// ── E il segreto? ─────────────────────────────────────────────────────────
//
// Esce da qui su un socket Unix in `$XDG_RUNTIME_DIR`, che logind crea `0700`,
// creato dall'agente con `0600` e cancellato appena la finestra si collega.
// Mai in `argv`, mai in una variabile d'ambiente, mai su disco. È la stessa
// regola di `minervad/lib/ipc/canale_segreto.dart`.
ShellRoot {
    id: radice

    // Niente ricaricamento a caldo: questa finestra vive pochi secondi, e
    // ricaricarla mentre qualcuno sta digitando vorrebbe dire perdere quello
    // che ha scritto e una richiesta di permesso appesa.
    Component.onCompleted: Quickshell.watchFiles = false

    readonly property bool it: Core.Strings.lang === "it"

    /// Il messaggio di polkit: «Autenticazione richiesta per montare…». Lo
    /// scrive chi ha definito l'azione, ed è già tradotto dal sistema.
    property string messaggio: ""
    property string utente: ""
    /// Il testo del prompt di PAM, di solito «Password: ».
    property string domanda: ""
    /// Vero quando la risposta NON va nascosta. Capita: certe configurazioni
    /// PAM chiedono un codice da leggere su un dispositivo. Mostrarlo a
    /// pallini vorrebbe dire un campo in cui non si vede cosa si sta copiando.
    property bool visibile: false
    property string avviso: ""
    property string nota: ""
    /// Vero fra il momento in cui si manda la risposta e quello in cui arriva
    /// l'esito. Il campo si chiude: una seconda password mandata mentre la
    /// prima è in volo confonde la macchina a stati di PAM — è la stessa
    /// ragione per cui il blocco schermo ha `inCorso`.
    property bool inCorso: false
    /// Vero appena c'è una domanda a cui rispondere. Prima non si mostra
    /// niente: una finestra vuota che compare e poi si riempie è peggio di una
    /// che compare già pronta.
    property bool pronta: false

    /// Cosa si sta chiedendo il permesso di fare, per esteso. Si mostra in
    /// piccolo sotto il messaggio. Dice poco a chi legge, ma è l'unica riga
    /// che il programma che chiede NON sceglie: il messaggio di `pkexec`
    /// contiene il percorso del programma, e un percorso lo decide chi lo
    /// crea (5 ottobre 2026, revisione di sicurezza).
    readonly property string azione:
        Quickshell.env("MINERVA_POLKIT_AZIONE") || ""

    // ── Il canale con l'agente ───────────────────────────────────────────

    Socket {
        id: canale
        path: Quickshell.env("MINERVA_POLKIT_CANALE") || ""
        connected: canale.path !== ""

        onConnectedChanged: {
            // Se il socket cade prima dell'esito, la richiesta è finita in un
            // modo o nell'altro e questa finestra non serve più. Restare
            // aperta vorrebbe dire una finestra della password che chiede
            // qualcosa a nessuno.
            if (!canale.connected && radice.pronta)
                Qt.quit();
        }

        parser: SplitParser {
            onRead: function(riga) { radice._riga(String(riga)); }
        }
    }

    /// Le righe dell'agente. Il formato è quello del canale del compositore —
    /// un verbo e degli argomenti, l'a-capo è il confine — e non per gusto:
    /// è già scritto, già provato, e chi legge uno dei due capisce l'altro.
    ///
    ///     richiesta "giacomo" "Autenticazione richiesta per…"
    ///     chiedi segreto "Password: "
    ///     errore "Authentication failure"
    ///     nota "…"
    ///     fatto | rifiutato
    function _riga(riga) {
        var pezzi = radice._pezzi(riga);
        if (pezzi.length === 0)
            return;
        var verbo = pezzi[0];

        if (verbo === "richiesta") {
            radice.utente = pezzi.length > 1 ? pezzi[1] : "";
            radice.messaggio = pezzi.length > 2 ? pezzi[2] : "";
            return;
        }
        if (verbo === "chiedi") {
            radice.visibile = pezzi.length > 1 && pezzi[1] === "visibile";
            radice.domanda = pezzi.length > 2 ? pezzi[2] : "";
            radice.inCorso = false;
            radice.pronta = true;
            campo.text = "";
            campo.forceActiveFocus();
            return;
        }
        if (verbo === "errore") {
            radice.inCorso = false;
            radice.avviso = pezzi.length > 1 ? pezzi[1] : "";
            campo.text = "";
            scossa.restart();
            return;
        }
        if (verbo === "nota") {
            radice.nota = pezzi.length > 1 ? pezzi[1] : "";
            return;
        }
        if (verbo === "fatto" || verbo === "rifiutato") {
            Qt.quit();
            return;
        }
    }

    /// Spezza una riga in verbo e argomenti, rispettando le virgolette.
    ///
    /// L'agente manda i testi fra virgolette con `g_strescape`, perché un
    /// messaggio di polkit contiene spazi e a volte un a-capo. Qui si fa il
    /// giro inverso: senza, «Autenticazione richiesta per montare» diventerebbe
    /// quattro argomenti e sullo schermo comparirebbe la prima parola.
    function _pezzi(riga) {
        var fuori = [];
        var i = 0;
        while (i < riga.length) {
            while (i < riga.length && riga.charAt(i) === " ")
                i++;
            if (i >= riga.length)
                break;
            if (riga.charAt(i) === "\"") {
                i++;
                var s = "";
                while (i < riga.length && riga.charAt(i) !== "\"") {
                    if (riga.charAt(i) === "\\" && i + 1 < riga.length) {
                        i++;
                        var c = riga.charAt(i);
                        // ── Le lettere accentate ──────────────────────────
                        //
                        // L'agente scrive con `g_strescape`, che manda ogni
                        // byte non ASCII come ottale: «è» arriva `\303\250`.
                        // Qui si leggevano le cifre, e il messaggio diceva
                        // «303250». Si raccolgono i byte di fila e si
                        // rileggono come UTF-8.
                        if (c >= "0" && c <= "7") {
                            var hex = "";
                            for (;;) {
                                var o = riga.substr(i, 3).match(/^[0-7]{1,3}/)[0];
                                hex += "%" + ("0" + parseInt(o, 8).toString(16)).slice(-2);
                                i += o.length;
                                var dopo = riga.charAt(i + 1);
                                if (riga.charAt(i) !== "\\" || dopo < "0" || dopo > "7")
                                    break;
                                i++;
                            }
                            try {
                                s += decodeURIComponent(hex);
                            } catch (e) {
                                s += "?";
                            }
                            continue;
                        }
                        s += c === "n" ? "\n" : c === "t" ? "\t" : c;
                    } else {
                        s += riga.charAt(i);
                    }
                    i++;
                }
                i++;
                fuori.push(s);
            } else {
                var j = riga.indexOf(" ", i);
                if (j < 0)
                    j = riga.length;
                fuori.push(riga.substring(i, j));
                i = j;
            }
        }
        return fuori;
    }

    function rispondi() {
        if (radice.inCorso || !radice.pronta)
            return;
        // Una riga sola: un a capo dentro la password incollata diventerebbe
        // una seconda risposta, o un «annulla», per l'agente.
        if (/[\r\n\u0000]/.test(campo.text)) {
            radice.avviso = radice.it ? "La password non può contenere un a capo."
                                      : "The password can't contain a line break.";
            campo.text = "";
            return;
        }
        radice.avviso = "";
        radice.inCorso = true;
        canale.write("risposta " + campo.text + "\n");
        // Il campo si svuota SUBITO, non quando arriva l'esito: fra le due
        // cose ci sono i secondi in cui PAM pensa, e in quei secondi la
        // password sta scritta in un oggetto QML che chiunque guardi lo
        // schermo può vedere a pallini ma un errore di disegno no.
        campo.text = "";
    }

    function annulla() {
        canale.write("annulla\n");
        Qt.quit();
    }

    // ── La finestra ──────────────────────────────────────────────────────
    //
    // Un layer `Overlay` con il fuoco esclusivo, non una finestra normale.
    // Tre ragioni, tutte pratiche:
    //
    //  · una richiesta di permesso non deve poter finire DIETRO la finestra
    //    che l'ha chiesta — chi guarda vede il programma bloccato e nessuna
    //    spiegazione;
    //  · il fuoco esclusivo vuol dire che si può digitare subito, senza
    //    cliccare prima: è la stessa scelta del cheatsheet e della schermata
    //    di accesso;
    //  · e vuol dire anche che nessun altro programma riceve i tasti mentre
    //    si scrive una password.
    PanelWindow {
        id: finestra
        anchors { top: true; bottom: true; left: true; right: true }

        WlrLayershell.namespace: "quickshell"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        // Copre tutto, barra compresa: senza, il layer verrebbe spinto sotto
        // la zona esclusiva della barra e le coordinate del mouse
        // risulterebbero sfalsate di tutta la sua altezza.
        exclusionMode: ExclusionMode.Ignore

        color: "transparent"
        visible: radice.pronta

        // Lo sfondo scurito. Non è decorazione: è quello che dice «adesso il
        // computer sta aspettando te e non fa altro».
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Theme.Colors._nero, 0.42)

            MouseArea {
                anchors.fill: parent
                // Un clic fuori NON annulla. Annullare per sbaglio una
                // richiesta di permesso vuol dire un'operazione a metà — un
                // disco montato a metà, un'installazione interrotta — e il
                // programma che l'aveva chiesta di solito non lo spiega.
                onClicked: scossa.restart()
            }
        }

        Rectangle {
            id: scatola
            anchors.centerIn: parent
            width: 420
            radius: Theme.Effects.radiusLG
            color: Theme.Colors.panel
            border.width: 1
            border.color: Theme.Colors.edge
            height: contenuto.implicitHeight + Theme.Effects.space6 * 2

            property real scarto: 0
            transform: Translate { x: scatola.scarto }

            // Lo scatto orizzontale quando la password è sbagliata: è l'unico
            // messaggio che si capisce senza leggere. Tre e basta — nella
            // schermata di accesso era senza fine, e Giacomo l'ha descritta
            // come «dolori di pancia».
            SequentialAnimation {
                id: scossa
                loops: 3
                NumberAnimation { target: scatola; property: "scarto"; to: 8
                                  duration: 45; easing.type: Easing.OutSine }
                NumberAnimation { target: scatola; property: "scarto"; to: -8
                                  duration: 90; easing.type: Easing.InOutSine }
                NumberAnimation { target: scatola; property: "scarto"; to: 0
                                  duration: 45; easing.type: Easing.InSine }
            }

            Column {
                id: contenuto
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.Effects.space6
                anchors.rightMargin: Theme.Effects.space6
                spacing: Theme.Effects.space4

                Text {
                    width: parent.width
                    text: radice.it ? "Serve il permesso di amministratore"
                                    : "Administrator permission needed"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeLG
                    font.weight: Theme.Typography.weightSemiBold
                    wrapMode: Text.WordWrap
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    visible: radice.messaggio !== ""
                    text: radice.messaggio
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    wrapMode: Text.WordWrap
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    visible: radice.azione !== ""
                    text: (radice.it ? "Azione: " : "Action: ") + radice.azione
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeXS
                    wrapMode: Text.WrapAnywhere
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    visible: radice.nota !== ""
                    text: radice.nota
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    wrapMode: Text.WordWrap
                }

                Text {
                    width: parent.width
                    // Di chi è la password che si sta chiedendo. Conta: polkit
                    // può chiedere quella di root invece della tua, e senza
                    // dirlo si digita la propria tre volte e si conclude che
                    // il computer è rotto.
                    visible: radice.utente !== ""
                    text: (radice.it ? "Password di " : "Password for ")
                          + radice.utente
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    elide: Text.ElideRight
                }

                Rectangle {
                    width: parent.width
                    height: 46
                    radius: Theme.Effects.radiusMD
                    color: Theme.Colors.sunken
                    border.width: 1
                    border.color: campo.activeFocus
                        ? Qt.alpha(Theme.Colors.accent, 0.75)
                        : Theme.Colors.edge
                    opacity: radice.inCorso ? 0.5 : 1
                    Behavior on opacity { NumberAnimation { duration: 140 } }

                    TextInput {
                        id: campo
                        anchors.fill: parent
                        // I margini SOLO ai lati: `anchors.margins` toglierebbe
                        // spazio anche sopra e sotto, e con `clip` acceso un
                        // carattere da 16 dentro 12 pixel si vede a metà. È già
                        // successo nel gestore file e nella password del wi-fi.
                        anchors.leftMargin: Theme.Effects.space4
                        anchors.rightMargin: Theme.Effects.space4
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        echoMode: radice.visibile ? TextInput.Normal
                                                  : TextInput.Password
                        passwordCharacter: "•"
                        enabled: !radice.inCorso
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeMD
                        selectionColor: Qt.alpha(Theme.Colors.accent, 0.5)
                        onAccepted: radice.rispondi()

                        Text {
                            textFormat: Text.PlainText
                            anchors.verticalCenter: parent.verticalCenter
                            visible: campo.text === ""
                            text: radice.domanda !== "" ? radice.domanda
                                  : (radice.it ? "Password" : "Password")
                            color: Theme.Colors.textFaint
                            font: campo.font
                        }
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    visible: radice.avviso !== ""
                    text: radice.avviso
                    color: Theme.Colors.danger
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    wrapMode: Text.WordWrap
                }

                Row {
                    anchors.right: parent.right
                    spacing: Theme.Effects.space3

                    Pulsante {
                        testo: radice.it ? "Annulla" : "Cancel"
                        onScelto: radice.annulla()
                    }
                    Pulsante {
                        testo: radice.it ? "Conferma" : "Confirm"
                        primario: true
                        attivo: !radice.inCorso
                        onScelto: radice.rispondi()
                    }
                }
            }

            // Esc annulla. È l'unica via d'uscita da tastiera, e deve
            // esserci: con il fuoco esclusivo, una finestra senza uscita è
            // una tastiera che non serve più a niente.
            Keys.onEscapePressed: radice.annulla()
        }

        Component.onCompleted: campo.forceActiveFocus()
    }

    onProntaChanged: if (radice.pronta) campo.forceActiveFocus()

    // ── Un pulsante, e basta ─────────────────────────────────────────────
    //
    // Non si importa `ui/SpineButton.qml`: quello è il pulsante della barra,
    // porta con sé tutto lo strato `ui` e con lui il tema, le icone e il
    // canale col demone. Questa finestra vive tre secondi e ne apre uno solo
    // per volta: due rettangoli e un testo costano meno di ogni alternativa.
    component Pulsante: Rectangle {
        id: pulsante
        property string testo: ""
        property bool primario: false
        property bool attivo: true
        signal scelto()

        width: etichetta.implicitWidth + Theme.Effects.space5 * 2
        height: 36
        radius: Theme.Effects.radiusMD
        opacity: pulsante.attivo ? 1 : 0.5
        color: pulsante.primario
               ? (area.containsMouse ? Qt.lighter(Theme.Colors.accent, 1.12)
                                     : Theme.Colors.accent)
               : (area.containsMouse ? Theme.Colors.hover
                                     : Theme.Colors.raised)
        border.width: pulsante.primario ? 0 : 1
        border.color: Theme.Colors.edge

        Text {
            id: etichetta
            anchors.centerIn: parent
            text: pulsante.testo
            color: pulsante.primario ? Theme.Colors.textOnAccent
                                     : Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
            font.weight: Theme.Typography.weightMedium
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            enabled: pulsante.attivo
            cursorShape: Qt.PointingHandCursor
            onClicked: pulsante.scelto()
        }
    }
}

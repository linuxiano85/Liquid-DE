import QtQuick
import Quickshell

import "../theme" as Theme
import "../ui" as Ui

// NuovoAccount — aggiungere una casella di posta.
//
// Segue le "Indicazioni per la UI" di posta/docs/stato-sviluppo.md:
// - niente timeout brevi: dopo una password sbagliata i server rallentano
//   apposta (8 secondi misurati), si mostra che si sta aspettando;
// - portachiavi bloccato ≠ password sbagliata: nel primo caso la password
//   NON si richiede, si chiede di sbloccare;
// - certificato sconosciuto: si mostra l'impronta e si chiede conferma;
// - Gmail e simili vogliono una password per le app: lo si dice prima;
// - Gmail, se il client Google è configurato: «Accedi con Google», come
//   Thunderbird. Si apre la pagina di Google nel browser (lì la conferma dal
//   telefono o il numero), e Posta riceve un token, non una password.
Item {
    id: na

    required property var canale
    property bool annullabile: true
    /// Indirizzo già scritto: rientro con Google di un account che c'è già.
    property string indirizzo: ""

    signal aggiunto(var account)
    signal annullato()

    property bool attesa: false
    property string errore: ""
    property string aiuto: ""
    property string impronta: ""
    property var trovato: null

    // «Accedi con Google»
    property bool googlePronto: false
    property bool usaPassword: false
    property string sessioneGoogle: ""
    property bool _annullatoGoogle: false
    readonly property bool modoGoogle: na.gmail && na.googlePronto && !na.usaPassword

    function _chiediGoogle() {
        na.canale.chiama("account.oauthAvailable", {}, function (r) {
            na.googlePronto = !!(r && r.google);
        }, function () { na.googlePronto = false; });
    }
    onGmailChanged: if (na.gmail) na._chiediGoogle()

    readonly property string dominio: {
        var e = email.text.trim().toLowerCase();
        var i = e.lastIndexOf("@");
        return i < 0 ? "" : e.substring(i + 1);
    }
    readonly property bool gmail: na.dominio === "gmail.com" || na.dominio === "googlemail.com"

    function _motivo(err) {
        var r = err && err.data ? err.data.reason : "";
        switch (r) {
        case "authFailed": return na.gmail
            ? "Gmail non ha accettato la password. Serve quella per le app (16 lettere), non quella con cui entri in Gmail."
            : "Password non accettata dal server.";
        case "appPasswordRequired": return "Gmail vuole la password per le app, non quella con cui entri in Gmail: "
            + "creala dal collegamento qui sopra e incollala nel campo Password.";
        case "untrustedCertificate": return "Il certificato del server non è riconosciuto.";
        // Il messaggio del servizio comincia già con «Server non raggiungibile».
        case "unreachable": return (err.message || "Server non raggiungibile.") + " Controlla la connessione.";
        case "keyringLocked": return "Il portachiavi è bloccato: sbloccalo e riprova (la password è giusta, non serve riscriverla).";
        case "keyringUnavailable": return "Serve un portachiavi per custodire la password (KWallet, gnome-keyring o KeePassXC).";
        case "duplicate": return "Questo account c'è già.";
        case "oauthUnsupported": return err.message || "Questo provider accetta solo l'accesso con il browser, non ancora disponibile.";
        case "oauthDenied": return err.message || "Google non ha concesso l'accesso.";
        case "oauthReauth": return "Google non riconosce più l'accesso: riprova.";
        case "offline": return "Il servizio della posta non risponde ancora: riprova tra un attimo.";
        default: return err && err.message ? err.message : "Non è andata.";
        }
    }

    function accedi() {
        if (na.attesa) return;
        na.errore = "";
        if (email.text.trim().indexOf("@") < 1 || password.text === "") {
            na.errore = "Scrivi indirizzo e password.";
            return;
        }
        // Google mostra la password per le app a gruppi di quattro
        // («abcd efgh ijkl mnop»): gli spazi non ne fanno parte. Se non sono
        // 16 lettere è quasi sempre la password normale, che Gmail rifiuta:
        // meglio dirlo qui che mandarla a Google.
        if (na.gmail) {
            var pulita = password.text.replace(/\s+/g, "");
            if (!/^[A-Za-z]{16}$/.test(pulita)) {
                na.errore = "La password per le app di Google è fatta di 16 lettere (qui ci sono "
                    + pulita.length + " caratteri). Non è la password con cui entri in Gmail: "
                    + "creala dal collegamento qui sopra.";
                return;
            }
        }
        na.attesa = true;
        na.canale.chiama("account.discover", { "email": email.text.trim() }, function (cfg) {
            if (!cfg) {
                na.attesa = false;
                na.errore = "Non trovo le impostazioni di questo indirizzo. Per ora servono le caselle "
                          + "dei provider noti (Gmail, Outlook, iCloud, Libero, Infomaniak…).";
                return;
            }
            na.trovato = cfg;
            na.aiuto = cfg.helpText || "";
            na._aggiungi("");
        }, function (err) {
            na.attesa = false;
            na.errore = na._motivo(err);
        });
    }

    function accediConGoogle() {
        if (na.attesa) return;
        na.errore = "";
        if (email.text.trim().indexOf("@") < 1) {
            na.errore = "Scrivi l'indirizzo Gmail.";
            return;
        }
        na.attesa = true;
        na._annullatoGoogle = false;
        na.canale.chiama("account.oauthBegin", { "email": email.text.trim() }, function (r) {
            na.sessioneGoogle = r.session;
            Qt.openUrlExternally(r.url);
            var p = { "session": r.session };
            if (nome.text.trim() !== "") p.name = nome.text.trim();
            // Risponde quando l'utente ha finito nel browser: anche minuti.
            na.canale.chiama("account.oauthFinish", p, function (acc) {
                na.attesa = false;
                na.sessioneGoogle = "";
                na.aggiunto(acc);
            }, function (err) {
                na.attesa = false;
                na.sessioneGoogle = "";
                if (!na._annullatoGoogle) na.errore = na._motivo(err);
            });
        }, function (err) {
            na.attesa = false;
            na.errore = na._motivo(err);
        });
    }

    function annullaGoogle() {
        na._annullatoGoogle = true;
        if (na.sessioneGoogle !== "")
            na.canale.chiama("account.oauthCancel", { "session": na.sessioneGoogle }, null, null);
    }

    function _aggiungi(impronta) {
        na.attesa = true;
        var pw = na.gmail ? password.text.replace(/\s+/g, "") : password.text;
        var p = { "email": email.text.trim(), "password": pw, "config": na.trovato };
        if (nome.text.trim() !== "") p.name = nome.text.trim();
        if (impronta !== "") p.trustedCertSha256 = impronta;
        na.canale.chiama("account.add", p, function (acc) {
            na.attesa = false;
            password.text = "";
            na.impronta = "";
            na.aggiunto(acc);
        }, function (err) {
            na.attesa = false;
            na.errore = na._motivo(err);
            if (err.data && err.data.reason === "untrustedCertificate" && err.data.certificateSha256)
                na.impronta = err.data.certificateSha256;
        });
    }

    Column {
        anchors.centerIn: parent
        width: Math.min(460, parent.width - Theme.Effects.space6 * 2)
        spacing: Theme.Effects.space4

        Ui.Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "mail"
            width: 44; height: 44
            color: Theme.Colors.accent
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Aggiungi la tua posta"
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXL
            font.weight: Theme.Typography.weightSemiBold
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "La password resta nel portachiavi del computer, mai in un file. "
                + "Le email restano qui: niente passa da server nostri."
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
        }

        Ui.Campo {
            id: email
            width: parent.width
            segnaposto: "Indirizzo email"
            modificabile: !na.attesa
            onAccettato: na.modoGoogle ? na.accediConGoogle() : password.prendiIlFuoco()
            Component.onCompleted: {
                if (na.indirizzo !== "") email.text = na.indirizzo;
                email.prendiIlFuoco();
            }
        }
        // Gmail: la password normale non funziona con i programmi di posta.
        Rectangle {
            visible: na.gmail && !na.modoGoogle
            width: parent.width
            height: gmailTesto.implicitHeight + Theme.Effects.space3 * 2
            radius: Theme.Effects.radiusSM
            color: Qt.alpha(Theme.Colors.accent, 0.10)
            border.color: Qt.alpha(Theme.Colors.accent, 0.35)
            Text {
                id: gmailTesto
                anchors.fill: parent
                anchors.margins: Theme.Effects.space3
                wrapMode: Text.WordWrap
                textFormat: Text.StyledText
                linkColor: Theme.Colors.accent
                text: "Gmail non accetta la password con cui entri in Gmail: ne serve una <b>per le app</b>.<br>"
                    + "1. Apri <a href=\"https://myaccount.google.com/apppasswords\">"
                    + "myaccount.google.com/apppasswords</a>. Google ti chiede di confermare "
                    + "dal telefono (o col numero che ti mostra).<br>"
                    + "2. Scrivi un nome, per esempio <i>Liquid Posta</i>, e premi <b>Crea</b>.<br>"
                    + "3. Copia le 16 lettere e incollale nel campo qui sotto."
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                onLinkActivated: function (l) { Qt.openUrlExternally(l); }
            }
        }

        // Gmail con il client Google: niente password, si entra dal browser.
        Column {
            visible: na.modoGoogle
            width: parent.width
            spacing: Theme.Effects.space3
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                text: na.attesa
                    ? "Continua nel browser: Google ti chiede di confermare dal telefono "
                      + "(o con il numero che ti mostra). Poi torna qui, Posta entra da sola."
                    : "Si apre la pagina di Google nel browser: lì confermi che sei tu, "
                      + "dal telefono o con il numero. Nessuna password da copiare."
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }
            Pulsante {
                anchors.horizontalCenter: parent.horizontalCenter
                icona: na.attesa ? "clock" : "globe"
                testo: na.attesa ? "Aspetto la conferma di Google…" : "Accedi con Google"
                active: !na.attesa
                spento: na.attesa
                onClicked: na.accediConGoogle()
            }
            Text {
                visible: !na.attesa
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.StyledText
                linkColor: Theme.Colors.textMuted
                text: "<a href=\"#\">Usa invece una password per le app</a>"
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
                onLinkActivated: na.usaPassword = true
            }
        }

        Ui.Campo {
            id: password
            visible: !na.modoGoogle
            width: parent.width
            segnaposto: na.gmail ? "Incolla qui la password per le app (16 lettere)" : "Password"
            nascosto: true
            modificabile: !na.attesa
            onAccettato: na.accedi()
        }
        Ui.Campo {
            id: nome
            width: parent.width
            segnaposto: "Facoltativo: il tuo nome, come lo vedranno gli altri"
            modificabile: !na.attesa
            onAccettato: na.accedi()
        }

        Text {
            visible: na.errore !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            // Per Gmail i passaggi sono già nel riquadro: l'aiuto ripeterebbe.
            text: na.errore + (!na.gmail && na.aiuto !== "" && na.errore.indexOf("Password") === 0 ? "\n" + na.aiuto : "")
            color: Theme.Colors.danger
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeSM
        }

        // Certificato sconosciuto (server personale, Proton Bridge): si
        // accetta solo per impronta, e solo se l'utente lo dice.
        Column {
            visible: na.impronta !== ""
            width: parent.width
            spacing: Theme.Effects.space2
            Text {
                width: parent.width
                wrapMode: Text.WrapAnywhere
                text: "Impronta SHA-256 del certificato:\n" + na.impronta
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXS
            }
            Pulsante {
                icona: "lock"
                testo: "È il mio server: mi fido di questo certificato"
                onClicked: na._aggiungi(na.impronta)
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.Effects.space3
            Pulsante {
                visible: (na.annullabile && !na.attesa) || na.sessioneGoogle !== ""
                testo: "Annulla"
                onClicked: na.sessioneGoogle !== "" ? na.annullaGoogle() : na.annullato()
            }
            Pulsante {
                visible: !na.modoGoogle
                icona: na.attesa ? "clock" : "check"
                testo: na.attesa ? "Verifico l'accesso…" : "Accedi"
                active: !na.attesa
                spento: na.attesa
                onClicked: na.accedi()
            }
        }
    }
}

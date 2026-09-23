import QtQuick
// Con un nome, e non nudo: `QtQuick.Controls` ha un suo `Page`, e importato
// senza prefisso vince su quello di `sections/Page.qml` — che è la base di
// tutte le sezioni. Il risultato non è un errore che ferma: è una pagina che
// si apre **vuota**, con un solo avviso in giornale che nessuno guarda
// («Cannot assign to non-existent property "subtitle"»). Preso a schermo, non
// leggendo.
import QtQuick.Controls as QC
import Quickshell

import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui

// Account — I servizi in rete a cui Minerva è collegata.
//
// ── Da dove nasce ──────────────────────────────────────────────────────────
//
// Parole di Giacomo, 24 agosto 2026: «perché in impostazioni non inseriamo una
// sezione account online come fa gnome e altri desktop dove poter accedere a
// vari servizi e vedere ad esempio spazio usato e rimanente, se il servizio di
// sincronizzazione per quel servizio è attivo e altre informazioni?»
//
// ── Perché è QUI e non dentro la Custodia ─────────────────────────────────
//
// Perché altrimenti si finisce a collegare kDrive **due volte**: una qui, per
// vedere lo spazio, e una nella Custodia, come posto dove mandare i backup.
// Due accessi vogliono dire due password da tenere aggiornate e due volte la
// stessa fatica. Il registro è uno solo (`services/account/registro_account.dart`)
// e questa pagina è la sua faccia; la Custodia legge lo stesso elenco.
//
// ── Le tre cose che questa pagina NON fa, e lo dice ────────────────────────
//
//  · **Non legge il portachiavi password di Google.** Non si può: quelle
//    password stanno dentro Chrome e dentro l'account Google, e non esiste
//    nessuna interfaccia per prenderle. Chi lo propone sta descrivendo un furto
//    di credenziali. La cosa che si confonde con quella — «Accedi con Google» —
//    è OAuth, e non tocca nessuna password.
//  · **Non porta dentro di sé una chiave di Google.** Google non fa entrare i
//    programmi che non si sono registrati da lei, e una chiave dentro un
//    progetto pubblico è una chiave regalata a chiunque — Google la spegne. Si
//    crea una volta sola, da qui, e resta nel portachiavi di questo computer.
//    È la stessa strada di rclone, per la stessa ragione.
//  · **Non monta una cartella nella home** se manca `rclone`. Lo dice, e dice
//    come averla.
Page {
    id: page

    title: page.it ? "Account online" : "Online accounts"
    subtitle: page.it
              ? "I servizi in rete a cui Minerva è collegata"
              : "The online services Minerva is connected to"

    readonly property bool it: Core.Strings.lang === "it"

    property var account: []
    property var puo: ({})
    /// Lo spazio letto per ogni account, quando l'abbiamo chiesto: `{id: {…}}`.
    property var spazi: ({})
    property string idChiesto: ""

    property string avviso: ""
    property bool avvisoBuono: false

    /// Il modulo aperto: "" (nessuno), "kdrive", "webdav", "google".
    property string aggiungo: ""
    property bool attesa: false

    /// I kDrive fra cui scegliere, quando l'account ne ha più d'uno.
    property var scegli: []
    /// Il numero del kDrive scritto a mano: serve solo a chi usa l'archivio
    /// di qualcun altro. Chiuso, perché la domanda giusta è «non chiedere».
    property bool numeroAMano: false
    /// Vero mentre si aspetta la risposta al salvataggio della chiave di
    /// Google: quella riuscita non deve chiudere il pannello, perché il passo
    /// dopo — «Accedi con Google» — è lì dentro.
    property bool salvandoChiave: false

    Component.onCompleted: Core.Ipc.accountVedi()

    Connections {
        target: Core.Ipc
        function onAccountElenco(r) {
            if (!r) return;
            page.account = r.account || [];
            page.puo = r.puo || ({});
        }
        function onAccountEsito(r) {
            if (!r) return;
            page.attesa = false;
            page.avvisoBuono = r.ok === true;
            page.avviso = r.ok === true
                ? (r.nota || (page.it ? "Fatto." : "Done."))
                : (r.errore || "");
            // Più di un kDrive su quell'account: non si indovina, si chiede.
            // La password è rimasta nel campo apposta — sceglierne uno rimanda
            // la stessa richiesta, e ribatterla sarebbe una punizione per una
            // domanda che abbiamo fatto noi.
            page.scegli = r.scegli || [];
            if (r.ok === true && page.salvandoChiave) {
                page.salvandoChiave = false;
                Core.Ipc.accountVedi();
                return;
            }
            page.salvandoChiave = false;
            if (r.ok === true) {
                page.aggiungo = "";
                page.scegli = [];
                // Adesso sì: la password sparisce dallo schermo. Da qui in poi
                // vive solo nel portachiavi.
                segreta.text = "";
                primo.text = "";
                chi.text = "";
                page.numeroAMano = false;
            }
            Core.Ipc.accountVedi();
        }

        // Google manda indietro un indirizzo, non una password: la pagina di
        // Google, quella vera. Si apre nel browser e il resto succede lì.
        function onAccountApriGoogle(r) {
            if (!r || !r.url) return;
            Quickshell.execDetached(["xdg-open", r.url]);
            page.avvisoBuono = true;
            page.avviso = page.it
                ? "Ho aperto la pagina di Google nel browser. Entra col tuo account e dai il permesso: quando torni, l'account è collegato. Se il browser non si è aperto, la pagina è ancora lì che aspetta per cinque minuti."
                : "I opened Google's page in your browser.";
        }
        function onAccountDettaglio(r) {
            if (!r || !r.account) return;
            var copia = {};
            for (var k in page.spazi) copia[k] = page.spazi[k];
            copia[r.account.id] = r.ok === true
                ? (r.spazio || ({}))
                : ({ "errore": r.errore || "" });
            page.spazi = copia;
            page.idChiesto = "";
            Core.Ipc.accountVedi();
        }
        function onConnectedChanged() {
            if (Core.Ipc.connected) Core.Ipc.accountVedi();
        }
    }

    /// Byte in una misura che si legge. Mai un numero dedotto: questa funzione
    /// riceve solo numeri che il server ha detto davvero.
    function misura(b) {
        if (b === undefined || b === null) return "";
        var u = ["B", "KB", "MB", "GB", "TB"];
        var i = 0;
        var v = b;
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
        return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)) + " " + u[i];
    }

    // ── L'avviso ─────────────────────────────────────────────────────────

    Card {
        visible: page.avviso !== ""
        heading: ""
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: page.avviso
            color: page.avvisoBuono ? Theme.Colors.positive : Theme.Colors.warning
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeMD
        }
    }

    // ── Quelli collegati ─────────────────────────────────────────────────

    Card {
        heading: page.it ? "Collegati" : "Connected"
        note: page.account.length === 0
              ? (page.it
                 ? "Nessun account, per ora. Collegane uno qui sotto: da quel momento la Custodia potrà mandarci i backup senza chiederti di nuovo la password."
                 : "No accounts yet.")
              : ""

        Column {
            width: parent.width
            spacing: Theme.Effects.space2

            Repeater {
                model: page.account

                Rectangle {
                    width: parent.width
                    height: riga.implicitHeight + Theme.Effects.space4 * 2
                    radius: Theme.Effects.radiusMD
                    color: Theme.Colors.sunken
                    border.width: 1
                    border.color: Theme.Colors.edge

                    readonly property var sp: page.spazi[modelData.id]

                    Column {
                        id: riga
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Theme.Effects.space4
                        spacing: Theme.Effects.space2

                        Row {
                            width: parent.width
                            spacing: Theme.Effects.space3

                            Ui.Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "cloud"
                                width: 20; height: 20
                                color: modelData.funziona === false
                                       ? Theme.Colors.warning
                                       : Theme.Colors.accent
                            }

                            Column {
                                width: parent.width - 20 - 200
                                    - Theme.Effects.space3 * 2
                                spacing: 1
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: modelData.nome
                                    color: Theme.Colors.text
                                    font.family: Theme.Typography.fontDisplay
                                    font.pixelSize: Theme.Typography.sizeMD
                                }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideMiddle
                                    text: modelData.utente + " · " + modelData.url
                                    color: Theme.Colors.textFaint
                                    font.family: Theme.Typography.fontMono
                                    font.pixelSize: Theme.Typography.sizeXS
                                }
                            }

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.Effects.space1

                                Ui.SpineButton {
                                    height: 30
                                    horizontalPadding: Theme.Effects.space3
                                    enabled: page.idChiesto === ""
                                    opacity: enabled ? 1 : 0.45
                                    onClicked: {
                                        if (!enabled) return;
                                        page.idChiesto = modelData.id;
                                        Core.Ipc.accountGuarda(modelData.id);
                                    }
                                    content: Text {
                                        text: page.idChiesto === modelData.id
                                              ? (page.it ? "Guardo…" : "Checking…")
                                              : (page.it ? "Controlla" : "Check")
                                        color: Theme.Colors.text
                                        font.family: Theme.Typography.fontDisplay
                                        font.pixelSize: Theme.Typography.sizeSM
                                    }
                                }

                                Ui.SpineButton {
                                    width: 30; height: 30
                                    onClicked: Core.Ipc.accountScollega(modelData.id)
                                    content: Ui.Icon {
                                        name: "close"
                                        width: 12; height: 12
                                        color: Theme.Colors.textMuted
                                    }
                                }
                            }
                        }

                        // ── Lo spazio, quando il server l'ha detto ───────
                        //
                        // Se non lo dice si scrive che non lo dice. Un numero
                        // dedotto sullo spazio libero è quello che fa perdere
                        // dei file: zero libero vuol dire «non mandarci più
                        // niente», zero usato vuol dire «è vuoto», e sono tutte
                        // e due bugie.
                        Text {
                            visible: parent.parent.sp !== undefined
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: {
                                var s = parent.parent.sp;
                                if (!s) return "";
                                if (s.errore) return s.errore;
                                if (!s.loDice)
                                    return page.it
                                        ? "L'accesso funziona. Quanto spazio resta, questo server non lo dice."
                                        : "Access works. This server doesn't report free space.";
                                var parti = [];
                                if (s.usati !== undefined)
                                    parti.push((page.it ? "usati " : "used ")
                                               + page.misura(s.usati));
                                if (s.liberi !== undefined)
                                    parti.push((page.it ? "liberi " : "free ")
                                               + page.misura(s.liberi));
                                if (s.totale !== undefined)
                                    parti.push((page.it ? "su " : "of ")
                                               + page.misura(s.totale));
                                return parti.join(" · ");
                            }
                            color: (parent.parent.sp && parent.parent.sp.errore)
                                   ? Theme.Colors.warning : Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        // La barra dello spazio si disegna SOLO col totale
                        // vero. Senza, non si disegna: una barra vuota dice
                        // «hai tutto lo spazio del mondo».
                        Rectangle {
                            visible: parent.parent.sp
                                     && parent.parent.sp.totale !== undefined
                                     && parent.parent.sp.totale > 0
                            width: parent.width
                            height: 6
                            radius: 3
                            color: Theme.Colors.edge
                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                width: {
                                    var s = riga.parent.sp;
                                    if (!s || !s.totale || s.usati === undefined)
                                        return 0;
                                    return parent.width * Math.min(1, s.usati / s.totale);
                                }
                                color: Theme.Colors.accent
                            }
                        }

                        Text {
                            visible: modelData.funziona === false
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: page.it
                                  ? "L'ultima volta che ho provato, questo account non rispondeva."
                                  : "Last time I checked, this account did not answer."
                            color: Theme.Colors.warning
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                    }
                }
            }
        }
    }

    // ── Collegarne uno ───────────────────────────────────────────────────

    Card {
        heading: page.it ? "Collega un servizio" : "Connect a service"

        Column {
            width: parent.width
            spacing: Theme.Effects.space3

            Row {
                spacing: Theme.Effects.space2
                visible: page.aggiungo === ""

                Ui.SpineButton {
                    height: 38
                    horizontalPadding: Theme.Effects.space4
                    onClicked: { page.aggiungo = "kdrive"; page.avviso = ""; }
                    content: Row {
                        spacing: Theme.Effects.space2
                        Ui.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "cloud"
                            width: 15; height: 15
                            color: Theme.Colors.accent
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "kDrive"
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeMD
                        }
                    }
                }

                Ui.SpineButton {
                    height: 38
                    horizontalPadding: Theme.Effects.space4
                    onClicked: { page.aggiungo = "google"; page.avviso = ""; }
                    content: Row {
                        spacing: Theme.Effects.space2
                        Ui.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "cloud"
                            width: 15; height: 15
                            color: Theme.Colors.accent
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Google Drive"
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeMD
                        }
                    }
                }

                Ui.SpineButton {
                    height: 38
                    horizontalPadding: Theme.Effects.space4
                    onClicked: { page.aggiungo = "webdav"; page.avviso = ""; }
                    content: Row {
                        spacing: Theme.Effects.space2
                        Ui.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "folder"
                            width: 15; height: 15
                            color: Theme.Colors.textMuted
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.it ? "Cartella in rete (WebDAV)"
                                          : "Network folder (WebDAV)"
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeMD
                        }
                    }
                }
            }

            // ── Il modulo ────────────────────────────────────────────
            Column {
                width: parent.width
                spacing: Theme.Effects.space3
                visible: page.aggiungo === "kdrive" || page.aggiungo === "webdav"

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: page.aggiungo === "kdrive"
                          ? (page.it
                             ? "L'email e la password del tuo account Infomaniak. Il numero del kDrive non serve: quali archivi ci sono sul tuo account me lo dice il server."
                             : "Your Infomaniak email and password. No kDrive number needed.")
                          : (page.it
                             ? "L'indirizzo del server, il nome utente e la password. Deve cominciare per «https://»: senza la esse la password viaggerebbe in chiaro."
                             : "Server address, username and password. Must start with «https://».")
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                // ── Se i kDrive sono più d'uno ───────────────────────────
                Column {
                    width: parent.width
                    spacing: Theme.Effects.space2
                    visible: page.scegli.length > 0

                    Repeater {
                        model: page.scegli

                        Ui.SpineButton {
                            width: parent.width
                            height: 38
                            horizontalPadding: Theme.Effects.space3
                            onClicked: {
                                page.attesa = true;
                                page.avviso = "";
                                Core.Ipc.accountCollega("kdrive",
                                    chi.text.trim(), segreta.text,
                                    { "numero": modelData.id,
                                      "nome": modelData.nome });
                            }
                            content: Row {
                                anchors.left: parent.left
                                spacing: Theme.Effects.space2
                                Ui.Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "cloud"
                                    width: 14; height: 14
                                    color: Theme.Colors.accent
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.nome + "  ·  " + modelData.id
                                    color: Theme.Colors.text
                                    font.family: Theme.Typography.fontDisplay
                                    font.pixelSize: Theme.Typography.sizeSM
                                }
                            }
                        }
                    }
                }

                QC.TextField {
                    id: primo
                    width: parent.width
                    visible: page.aggiungo === "webdav" || page.numeroAMano
                    placeholderText: page.aggiungo === "kdrive"
                                     ? (page.it ? "Numero del kDrive (solo cifre)"
                                                : "kDrive number (digits only)")
                                     : (page.it ? "https://…" : "https://…")
                    color: Theme.Colors.text
                    placeholderTextColor: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeSM
                    background: Rectangle {
                        radius: Theme.Effects.radiusMD
                        color: Theme.Colors.sunken
                        border.width: 1
                        border.color: primo.activeFocus ? Theme.Colors.edgeAccent
                                                        : Theme.Colors.edge
                    }
                }

                QC.TextField {
                    id: chi
                    width: parent.width
                    placeholderText: page.aggiungo === "kdrive"
                                     ? (page.it ? "Email del tuo account Infomaniak"
                                                : "Your Infomaniak email")
                                     : (page.it ? "Nome utente o email"
                                                : "Username or email")
                    color: Theme.Colors.text
                    placeholderTextColor: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeSM
                    background: Rectangle {
                        radius: Theme.Effects.radiusMD
                        color: Theme.Colors.sunken
                        border.width: 1
                        border.color: chi.activeFocus ? Theme.Colors.edgeAccent
                                                      : Theme.Colors.edge
                    }
                }

                QC.TextField {
                    id: segreta
                    width: parent.width
                    // Password apposta: una password in chiaro su uno schermo
                    // è una password che finisce in una fotografia.
                    echoMode: TextInput.Password
                    placeholderText: page.it ? "Password" : "Password"
                    color: Theme.Colors.text
                    placeholderTextColor: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeSM
                    background: Rectangle {
                        radius: Theme.Effects.radiusMD
                        color: Theme.Colors.sunken
                        border.width: 1
                        border.color: segreta.activeFocus ? Theme.Colors.edgeAccent
                                                          : Theme.Colors.edge
                    }
                    onAccepted: collega.clicked()
                }

                Row {
                    spacing: Theme.Effects.space2

                    Ui.SpineButton {
                        id: collega
                        height: 38
                        horizontalPadding: Theme.Effects.space4
                        enabled: !page.attesa && chi.text.trim() !== ""
                                 && segreta.text !== ""
                                 && (page.aggiungo !== "webdav"
                                     || primo.text.trim() !== "")
                        opacity: enabled ? 1 : 0.45
                        onClicked: {
                            if (!enabled) return;
                            page.attesa = true;
                            page.avviso = "";
                            page.scegli = [];
                            var extra = page.aggiungo === "kdrive"
                                ? { "numero": page.numeroAMano
                                              ? primo.text.trim() : "" }
                                : { "url": primo.text.trim() };
                            Core.Ipc.accountCollega(page.aggiungo,
                                                    chi.text.trim(),
                                                    segreta.text, extra);
                            // La password resta nel campo finché la risposta
                            // non arriva, e non un momento di più: se il
                            // server chiede di scegliere fra due archivi, o se
                            // il nome era sbagliato di una lettera, ribatterla
                            // sarebbe una punizione per una domanda nostra.
                            // Sparisce in `onAccountEsito`, appena è andata.
                        }
                        content: Row {
                            spacing: Theme.Effects.space2
                            Ui.Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "check"
                                width: 15; height: 15
                                color: Theme.Colors.text
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: page.attesa
                                      ? (page.it ? "Sto provando…" : "Trying…")
                                      : (page.it ? "Collega" : "Connect")
                                color: Theme.Colors.text
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeMD
                                font.weight: Theme.Typography.weightSemiBold
                            }
                        }
                    }

                    Ui.SpineButton {
                        height: 38
                        horizontalPadding: Theme.Effects.space3
                        onClicked: {
                            page.aggiungo = "";
                            page.scegli = [];
                            page.numeroAMano = false;
                            segreta.text = "";
                        }
                        content: Text {
                            text: page.it ? "Lascia stare" : "Never mind"
                            color: Theme.Colors.textFaint
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                    }
                }

                // ── Quando la password giusta non basta ──────────────────
                //
                // Compare solo dopo un rifiuto, e solo per kDrive: è la
                // risposta alla domanda che si fa in quel momento, «ma la
                // password è quella giusta». Sì, e non c'entra: il secondo
                // passaggio protegge il sito, e a kAuth nessun programma può
                // rispondere al posto tuo.
                Ui.SpineButton {
                    visible: page.aggiungo === "kdrive" && !page.avvisoBuono
                             && page.avviso !== ""
                    height: 34
                    horizontalPadding: Theme.Effects.space3
                    onClicked: Quickshell.execDetached(["xdg-open",
                        "https://manager.infomaniak.com/v3/ng/profile/user/security"])
                    content: Row {
                        spacing: Theme.Effects.space2
                        Ui.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "globe"
                            width: 14; height: 14
                            color: Theme.Colors.accent
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.it
                                  ? "Apri Infomaniak · Sicurezza, per la password delle applicazioni"
                                  : "Open Infomaniak · Security"
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                    }
                }

                Text {
                    visible: page.aggiungo === "kdrive" && !page.numeroAMano
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: page.it
                          ? "Ho il numero di un kDrive e voglio scriverlo io"
                          : "I know the kDrive number"
                    color: Theme.Colors.accent
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                    font.underline: true
                    // Non un `<a href>`: il blu dei collegamenti è quello di
                    // Qt, non il nostro, e su fondo scuro non si legge —
                    // visto a schermo il 25 agosto, non immaginato.
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.numeroAMano = true
                    }
                }
            }

            // ── Google ───────────────────────────────────────────────
            //
            // Qui non c'è nessun campo per la password, e non è una
            // dimenticanza: a Google si entra da Google. Si preme il
            // pulsante, si apre il browser sulla loro pagina — email,
            // password, e il secondo passaggio se ce l'hai — e alla fine
            // Google chiede se Minerva può entrare. Da questa parte
            // arriva solo un permesso, che si può togliere quando si
            // vuole. È anche il motivo per cui questa strada funziona
            // dove quella di kDrive inciampa: al codice di verifica
            // risponde il browser, non noi.
            Column {
                width: parent.width
                spacing: Theme.Effects.space3
                visible: page.aggiungo === "google"

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: page.it
                          ? "Minerva chiede a Google un permesso solo: vedere e scrivere <b>i file che crea lei</b>. Il resto del tuo Drive, per questo programma, non esiste — così un backup non può leggere le tue cose."
                          : "Minerva asks Google for one permission only: the files it creates itself."
                    textFormat: Text.RichText
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                // ── Quando la chiave c'è: si entra ───────────────────
                Ui.SpineButton {
                    visible: page.puo.google === true
                    height: 38
                    horizontalPadding: Theme.Effects.space4
                    enabled: !page.attesa
                    opacity: enabled ? 1 : 0.45
                    onClicked: {
                        if (!enabled) return;
                        page.attesa = true;
                        page.avviso = "";
                        Core.Ipc.accountGoogleCollega();
                    }
                    content: Row {
                        spacing: Theme.Effects.space2
                        Ui.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "globe"
                            width: 15; height: 15
                            color: Theme.Colors.accent
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.attesa
                                  ? (page.it ? "Aspetto che tu entri in Google…"
                                             : "Waiting for Google…")
                                  : (page.it ? "Accedi con Google"
                                             : "Sign in with Google")
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeMD
                            font.weight: Theme.Typography.weightSemiBold
                        }
                    }
                }

                // ── Quando manca: la chiave dell'applicazione ────────
                //
                // Google non lascia entrare un programma che non si sia
                // registrato. Minerva non può portarsi dentro una chiave
                // propria: un progetto pubblico che spedisce la sua la
                // regala a chiunque, e Google la spegne. Si fa una volta
                // sola, e vale per sempre. È la stessa strada di rclone,
                // per la stessa ragione.
                Column {
                    width: parent.width
                    spacing: Theme.Effects.space3
                    visible: page.puo.google !== true

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: page.it
                              ? "Prima però serve una chiave: Google non fa entrare i programmi che non si sono registrati da lei. Si fa una volta sola, è gratis, e resta in questo computer.<br><br>1. Apri la console di Google e crea un progetto (un nome qualsiasi).<br>2. In «Credenziali» → «Crea credenziali» → «ID client OAuth».<br>3. Come tipo scegli <b>Applicazione desktop</b>.<br>4. Copia qui sotto i due pezzi che ti dà."
                              : "First you need a key: Google doesn't let unregistered programs in. Create an OAuth client ID of type Desktop app."
                        textFormat: Text.RichText
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    Ui.SpineButton {
                        height: 34
                        horizontalPadding: Theme.Effects.space3
                        onClicked: Quickshell.execDetached(["xdg-open",
                            "https://console.cloud.google.com/apis/credentials"])
                        content: Row {
                            spacing: Theme.Effects.space2
                            Ui.Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "globe"
                                width: 14; height: 14
                                color: Theme.Colors.accent
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: page.it ? "Apri la console di Google"
                                              : "Open the Google console"
                                color: Theme.Colors.text
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                            }
                        }
                    }

                    QC.TextField {
                        id: gid
                        width: parent.width
                        placeholderText: "…apps.googleusercontent.com"
                        color: Theme.Colors.text
                        placeholderTextColor: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: Theme.Typography.sizeXS
                        background: Rectangle {
                            radius: Theme.Effects.radiusMD
                            color: Theme.Colors.sunken
                            border.width: 1
                            border.color: gid.activeFocus
                                          ? Theme.Colors.edgeAccent
                                          : Theme.Colors.edge
                        }
                    }

                    QC.TextField {
                        id: gseg
                        width: parent.width
                        echoMode: TextInput.Password
                        placeholderText: page.it ? "Il segreto del client"
                                                 : "Client secret"
                        color: Theme.Colors.text
                        placeholderTextColor: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: Theme.Typography.sizeXS
                        background: Rectangle {
                            radius: Theme.Effects.radiusMD
                            color: Theme.Colors.sunken
                            border.width: 1
                            border.color: gseg.activeFocus
                                          ? Theme.Colors.edgeAccent
                                          : Theme.Colors.edge
                        }
                        onAccepted: salvaChiave.clicked()
                    }

                    Ui.SpineButton {
                        id: salvaChiave
                        height: 36
                        horizontalPadding: Theme.Effects.space4
                        enabled: gid.text.trim() !== "" && gseg.text !== ""
                        opacity: enabled ? 1 : 0.45
                        onClicked: {
                            if (!enabled) return;
                            page.avviso = "";
                            page.salvandoChiave = true;
                            Core.Ipc.accountGoogleChiave(gid.text.trim(),
                                                         gseg.text);
                            gseg.text = "";
                        }
                        content: Text {
                            text: page.it ? "Salva la chiave" : "Save the key"
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeMD
                            font.weight: Theme.Typography.weightSemiBold
                        }
                    }
                }

                Row {
                    spacing: Theme.Effects.space2

                    Ui.SpineButton {
                        height: 34
                        horizontalPadding: Theme.Effects.space3
                        onClicked: { page.aggiungo = ""; page.attesa = false; }
                        content: Text {
                            text: page.it ? "Lascia stare" : "Never mind"
                            color: Theme.Colors.textFaint
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                    }

                    Ui.SpineButton {
                        visible: page.puo.google === true
                        height: 34
                        horizontalPadding: Theme.Effects.space3
                        onClicked: Core.Ipc.accountGoogleDimentica()
                        content: Text {
                            text: page.it ? "Dimentica la chiave"
                                          : "Forget the key"
                            color: Theme.Colors.textFaint
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                    }
                }
            }
        }
    }

    // ── Quello che oggi non si può fare ──────────────────────────────────
    //
    // Scritto e non nascosto. Un desktop che tace su quello che non sa fare
    // costringe a scoprirlo per tentativi.

    Card {
        heading: page.it ? "Quello che ancora non c'è" : "Not available yet"

        Column {
            width: parent.width
            spacing: Theme.Effects.space3

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: page.puo.montare === true
                      ? (page.it
                         ? "La cartella nella home si può fare: rclone è installato. Non è ancora collegata qui — arriva col prossimo pezzo."
                         : "A folder in your home is possible: rclone is installed.")
                      : (page.it
                         ? "Una cartella dell'account dentro la tua Home non si può ancora avere: serve «rclone», che su questa macchina non è installato. Per adesso l'account serve a mandare i backup dalla Custodia, e per quello non serve montare niente."
                         : "A folder in your home needs «rclone», which is not installed here.")
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: page.puo.google === true
                      ? (page.it
                         ? "Google Drive è collegabile: la chiave dell'applicazione c'è. Minerva vede soltanto i file che crea lei — il resto del tuo Drive, per questo programma, non esiste."
                         : "Google Drive is ready: the application key is saved.")
                      : (page.it
                         ? "Google Drive si può collegare, ma vuole una chiave che devi creare tu sulla console di Google: Minerva non può portarsene dentro una propria, perché un progetto pubblico che spedisce la sua chiave la regala a chiunque e Google la spegne. Si fa una volta sola, dal pulsante «Google Drive» qui sopra."
                         : "Google Drive needs an application key you create yourself, once.")
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: page.it
                      ? "E una cosa che non si potrà fare mai, perché non esiste il modo: usare le password salvate nel tuo account Google per entrare in altri servizi. Quelle stanno dentro Google e nessun programma può leggerle da fuori. «Accedi con Google» è un'altra cosa — è un permesso, non una password — ed è quella che trovi qui sopra."
                      : "And one thing that will never be possible: reading the passwords saved in your Google account."
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }
        }
    }
}

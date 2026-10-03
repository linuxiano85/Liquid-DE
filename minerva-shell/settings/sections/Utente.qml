import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// Utente — Chi sei per questo computer.
//
// Foto, nome per esteso, password. Tre cose che finora si potevano cambiare
// solo da riga di comando, e che si vedono tutte e tre nella schermata di
// accesso — è il motivo per cui stanno insieme.
//
// ── Chi fa il lavoro, e perché non lo facciamo noi ─────────────────────────
//
// Foto e nome passano da **AccountsService**, il servizio di sistema che
// tiene queste informazioni per tutti i programmi. Non è un giro più lungo:
// è l'unico modo perché la foto finisca in `/var/lib/AccountsService/icons/`,
// che è l'unico posto dove la SCHERMATA DI ACCESSO può leggerla. Il greeter
// gira come utente `greeter` e nella tua cartella personale non entra —
// una cartella personale è `drwx------`. Una foto messa in `~/.face` la vedresti
// solo tu, e mai al momento in cui serve.
//
// La password passa da `scripts/minerva-utente`, che è corto apposta.
//
// ── Chi chiede la password di conferma ─────────────────────────────────────
//
// polkit, con la sua finestrella. Non ce la chiediamo noi, e non la
// conserviamo: un pannello delle impostazioni che si fa dire la password di
// amministratore per poi passarla a qualcos'altro è la forma con cui si
// scrivono i programmi che la rubano.
Page {
    id: page

    title: page.it ? "Utente" : "User"
    subtitle: page.it
              ? "La tua foto, il tuo nome e la tua password"
              : "Your photo, your name and your password"

    readonly property bool it: Core.Strings.lang === "it"

    property var io: null
    property string esito: ""
    property bool esitoGrave: false

    function racconta(testo, grave) {
        page.esito = testo;
        page.esitoGrave = grave === true;
        silenzio.restart();
    }

    Timer {
        id: silenzio
        interval: 8000
        onTriggered: page.esito = ""
    }

    Connections {
        target: Core.Ipc
        function onGreeterInfoReceived(info) {
            var chi = Quickshell.env("USER");
            var utenti = info.utenti || [];
            for (var i = 0; i < utenti.length; i++) {
                if (utenti[i].nome === chi) {
                    page.io = utenti[i];
                    return;
                }
            }
            page.io = utenti.length > 0 ? utenti[0] : null;
        }
    }

    function ricarica() { Core.Ipc.greeterInfo(); }

    Component.onCompleted: page.ricarica()

    // ── Chi sei ──────────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Il tuo account" : "Your account"

        Row {
            width: parent.width
            spacing: Theme.Effects.space4

            Item {
                width: 76
                height: 76

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Qt.alpha(Theme.Colors.accent, 0.20)
                    border.width: 1
                    border.color: Theme.Colors.edge
                    visible: !miaFoto.pronto

                    Text {
                        anchors.centerIn: parent
                        text: {
                            var n = page.io
                                ? (page.io.nomeCompleto || page.io.nome) : "?";
                            return n.charAt(0).toUpperCase();
                        }
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: 32
                        font.weight: Theme.Typography.weightLight
                    }
                }

                // Tonda come nella schermata di accesso e in quella di
                // blocco. Prima era un quadrato: non si notava finché i
                // ritratti erano i nostri, che hanno il fondo tondo disegnato
                // dentro, e con una foto propria si notava subito.
                //
                // Poi è stata una `Image` con una maschera per la GPU, che è
                // il modo giusto finché la GPU c'è. Da quando le Impostazioni
                // disegnano col processore — 132 MB → 82 — quel modo non fa
                // comparire un quadrato: **non fa comparire niente**, e in
                // silenzio. Il perché sta in `ui/RitrattoTondo.qml`, insieme
                // al modo che funziona in tutti e due i casi.
                Ui.RitrattoTondo {
                    id: miaFoto
                    anchors.fill: parent
                    fonte: (page.io && page.io.ritratto) ? page.io.ritratto : ""
                    versione: page.versioneFoto
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: page.io ? (page.io.nomeCompleto !== ""
                                     ? page.io.nomeCompleto : page.io.nome)
                                  : "—"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeLG
                    font.weight: Theme.Typography.weightMedium
                }

                Text {
                    text: page.io
                          ? page.io.nome + "  ·  uid " + page.io.uid
                          : ""
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }
        }
    }

    property int versioneFoto: 0

    // ── La foto ──────────────────────────────────────────────────────────
    //
    // Qui c'era una casella dove incollare un percorso e un bottone «Scegli
    // dal disco» che apriva il GESTORE FILE. Giacomo, provandolo: «scegli da
    // disco apre il file manager e da lì non posso cliccare su seleziona». Ed
    // era vero — un gestore file non ha modo di restituire una scelta a chi
    // l'ha aperto — ma il commento accanto al codice lo sapeva già e lo dava
    // per accettabile: «si copia il percorso col tasto destro e lo si incolla
    // sopra». Nessuno cambia la propria foto così.
    //
    // Restano due strade, che è quello che ha chiesto: i ritratti che
    // viaggiano con Minerva, e una propria immagine — con il ritaglio, perché
    // «se ho un'immagine dove ho più persone e voglio selezionare la mia
    // faccia posso farlo».

    /// I ritratti di serie, disegnati da `scripts/make-ritratti.py`. L'elenco
    /// sta qui e non nello script perché qui servono anche i nomi, e uno
    /// script che genera immagini non ha motivo di sapere l'italiano.
    readonly property string cartellaRitratti:
        Quickshell.shellDir + "/assets/ritratti/"

    readonly property var ritratti: [
        { "f": "paperella.png",  "it": "Paperella",  "en": "Duckling" },
        { "f": "gattino.png",    "it": "Gattino",    "en": "Kitten" },
        { "f": "volpe.png",      "it": "Volpe",      "en": "Fox" },
        { "f": "panda.png",      "it": "Panda",      "en": "Panda" },
        { "f": "gufo.png",       "it": "Gufo",       "en": "Owl" },
        { "f": "pinguino.png",   "it": "Pinguino",   "en": "Penguin" },
        { "f": "riccio.png",     "it": "Riccio",     "en": "Hedgehog" },
        { "f": "controller.png", "it": "Controller", "en": "Controller" },
        { "f": "chitarra.png",   "it": "Chitarra",   "en": "Guitar" },
        { "f": "fotocamera.png", "it": "Fotocamera", "en": "Camera" },
        { "f": "tazza.png",      "it": "Tazza",      "en": "Cup" },
        { "f": "libro.png",      "it": "Libro",      "en": "Book" },
        { "f": "razzo.png",      "it": "Razzo",      "en": "Rocket" },
        { "f": "pianeta.png",    "it": "Pianeta",    "en": "Planet" },
        { "f": "luna.png",       "it": "Luna",       "en": "Moon" },
        { "f": "cactus.png",     "it": "Cactus",     "en": "Cactus" },
        { "f": "fungo.png",      "it": "Fungo",      "en": "Mushroom" }
    ]

    Card {
        heading: page.it ? "Foto" : "Photo"
        note: page.it
              ? "Quella che scegli viene copiata in una cartella di sistema: "
                + "è l'unico posto da cui la schermata di accesso può "
                + "leggerla, perché nella tua cartella personale non entra."
              : "The one you pick gets copied to a system folder: it is the "
                + "only place the login screen can read it from, because it "
                + "cannot enter your home folder."

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: page.it ? "Uno dei nostri" : "One of ours"
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeXS
        }

        Flow {
            width: parent.width
            spacing: Theme.Effects.space2

            Repeater {
                model: page.ritratti

                delegate: Item {
                    required property var modelData
                    width: 62
                    height: 62
                    // Chi è sotto il puntatore passa davanti: la targhetta
                    // esce SOTTO il ritratto, e in un `Flow` chi viene dopo si
                    // disegna sopra chi viene prima. Senza questa riga il nome
                    // della paperella finiva dietro la fila di sotto.
                    z: sceltoMouse.containsMouse ? 10 : 0

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: sceltoMouse.containsMouse
                                      ? Theme.Colors.accent : "transparent"
                        Behavior on border.color { ColorAnimation { duration: Theme.Motion.instant } }
                    }

                    Image {
                        anchors.fill: parent
                        anchors.margins: 3
                        asynchronous: true
                        // Si decodificano alla misura che servono: diciassette
                        // PNG da 512 tenuti interi sono venti volte la memoria
                        // di quello che si vede.
                        sourceSize.width: 128
                        source: "file://" + page.cartellaRitratti + modelData.f
                    }

                    MouseArea {
                        id: sceltoMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.cambiaFoto(
                                       page.cartellaRitratti + modelData.f)
                    }

                    // La targhetta di Minerva e non quella di
                    // `QtQuick.Controls`: l'attaccato `ToolTip` tirerebbe
                    // dentro tutto il modulo Controls per una scritta.
                    Ui.ToolTipHint {
                        text: page.it ? modelData.it : modelData.en
                        shown: sceltoMouse.containsMouse
                    }
                }
            }
        }

        Rectangle {
            width: 200
            height: 34
            radius: Theme.Effects.radiusSM
            color: miaMouse.containsMouse ? Theme.Colors.raisedHigh
                                          : Theme.Colors.raised
            border.width: Theme.Effects.hairline
            border.color: Theme.Colors.edge

            Text {
                anchors.centerIn: parent
                text: page.it ? "Scegli una tua immagine…" : "Pick your own image…"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            MouseArea {
                id: miaMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: selettore.apri(page.cartellaImmagini)
            }
        }
    }

    /// Da dove parte il selettore. `~/Immagini` se c'è, se no la casa: su un
    /// sistema in inglese quella cartella si chiama `Pictures`, e partire da
    /// una cartella che non esiste mostra un elenco vuoto.
    property string cartellaImmagini: Quickshell.env("HOME")

    Core.Exec {
        id: doveSonoLeFoto
        Component.onCompleted: doveSonoLeFoto.sh(
            'for d in "$HOME/Immagini" "$HOME/Pictures"; do '
            + '[ -d "$d" ] && { printf %s "$d"; exit 0; }; done; printf %s "$HOME"')
        onDone: function (out) {
            if (out !== "")
                page.cartellaImmagini = out;
        }
    }

    // ── Le due finestrelle ───────────────────────────────────────────────
    //
    // `parent: page` le tira fuori dalla colonna che scorre: dichiarate lì
    // dentro sarebbero due riquadri in fila alti quanto la pagina, e
    // `anchors.fill` dentro una `Column` non si può nemmeno usare.

    S.SelettoreImmagine {
        id: selettore
        parent: page
        onScelta: function (percorso) { ritaglio.apri(percorso); }
    }

    S.RitaglioRitratto {
        id: ritaglio
        parent: page
        onRitagliato: function (percorso) { page.cambiaFoto(percorso); }
    }

    // ── Il nome ──────────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Nome per esteso" : "Full name"

        S.SettingRow {
            width: parent.width
            label: page.it ? "Come ti chiami" : "Your name"
            description: page.it
                ? "È quello che compare nella schermata di accesso al posto del nome utente"
                : "This is what the login screen shows instead of the account name"
            controlWidth: 300

            control: Rectangle {
                width: 300
                height: 34
                radius: Theme.Effects.radiusXS
                color: Theme.Colors.sunken
                border.width: Theme.Effects.hairline
                border.color: nome.activeFocus ? Theme.Colors.accent
                                               : Theme.Colors.edge

                TextInput {
                    id: nome
                    anchors.fill: parent
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.rightMargin: Theme.Effects.space3
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                    text: page.io ? page.io.nomeCompleto : ""
                    onAccepted: page.cambiaNome(nome.text.trim())

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: nome.text === ""
                        text: page.io ? page.io.nome : ""
                        color: Theme.Colors.textFaint
                        font: nome.font
                    }
                }
            }
        }

        Rectangle {
            width: 130
            height: 34
            radius: Theme.Effects.radiusSM
            color: applicaNome.containsMouse ? Qt.alpha(Theme.Colors.accent, 0.35)
                                             : Qt.alpha(Theme.Colors.accent, 0.20)
            border.width: Theme.Effects.hairline
            border.color: Qt.alpha(Theme.Colors.accent, 0.5)

            Text {
                anchors.centerIn: parent
                text: page.it ? "Applica" : "Apply"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            MouseArea {
                id: applicaNome
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.cambiaNome(nome.text.trim())
            }
        }
    }

    // ── La password ──────────────────────────────────────────────────────
    //
    // ── L'ordine, che è la sicurezza ──────────────────────────────────────
    //
    // Prima c'erano i due campi sempre aperti e un pulsante che si accendeva
    // quando combaciavano. Funzionava, e sbagliava l'ordine: si scriveva la
    // password nuova PRIMA che qualcuno avesse verificato chi la stava
    // scrivendo. Chi trovava il portatile sbloccato e aperto sulle
    // Impostazioni vedeva una pagina che sembrava invitare a farlo.
    //
    // Adesso: un pulsante solo. Il sistema chiede la password ATTUALE con la
    // sua finestrella, e solo dopo compaiono i campi. Chi non la sa non arriva
    // nemmeno a vederli.
    //
    // ── Perché la finestrella compare una volta e non due ────────────────
    //
    // Perché `config/polkit/org.liquidde.utente.policy` chiede `auth_self_keep`:
    // la conferma vale qualche minuto, quindi il cambio vero che segue non la
    // ridomanda. Il programma va installato con la sua policy: la pagina
    // non esegue come root uno script modificabile nella cartella del progetto.

    /// Dove sta il programma che fa il lavoro. Quello installato per primo:
    /// è l'unico percorso che la regola di polkit può nominare.
    property string comandoUtente: ""
    property bool installato: false

    Core.Exec {
        id: doveSta
        Component.onCompleted: doveSta.sh(
            '[ -x /usr/local/bin/liquid-de-utente ] '
            + '&& printf %s /usr/local/bin/liquid-de-utente');
        onDone: function (out) {
            page.comandoUtente = out;
            page.installato = (out === "/usr/local/bin/liquid-de-utente");
        }
    }

    /// A che punto siamo: `chiusa` → `conferma` → `aperta`.
    property string passoPassword: "chiusa"

    Card {
        heading: page.it ? "Password" : "Password"

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
            lineHeight: Theme.Typography.leadingBody
            text: {
                if (page.passoPassword === "aperta")
                    return page.it
                        ? "Il sistema ti ha riconosciuto. Scrivi la nuova, due volte."
                        : "The system recognised you. Type the new one, twice.";
                if (page.passoPassword === "conferma")
                    return page.it
                        ? "Rispondi alla finestrella del sistema."
                        : "Answer the system dialog.";
                var t = page.it
                    ? "Quella attuale non si scrive qui: la chiede il sistema con la sua finestrella, e a noi non arriva mai."
                    : "You do not type the current one here: the system asks for it in its own dialog, and it never reaches us.";
                if (!page.installato)
                    t += page.it
                        ? " Il servizio per cambiare la password non è installato: completa l'installazione di Liquid DE."
                        : " The password change service is not installed: complete the Liquid DE installation.";
                return t;
            }
        }

        // ── Il pulsante, da solo ─────────────────────────────────────────
        Rectangle {
            visible: page.passoPassword !== "aperta"
            width: 190
            height: 34
            radius: Theme.Effects.radiusSM
            opacity: page.passoPassword === "conferma" ? 0.5 : 1
            color: chiediMouse.containsMouse
                   ? Qt.alpha(Theme.Colors.accent, 0.35)
                   : Qt.alpha(Theme.Colors.accent, 0.20)
            border.width: Theme.Effects.hairline
            border.color: Qt.alpha(Theme.Colors.accent, 0.5)

            Text {
                anchors.centerIn: parent
                text: page.passoPassword === "conferma"
                      ? (page.it ? "In attesa del sistema…" : "Waiting for the system…")
                      : (page.it ? "Cambia password" : "Change password")
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            MouseArea {
                id: chiediMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: page.passoPassword === "chiusa" && page.installato
                cursorShape: Qt.PointingHandCursor
                onClicked: page.chiediConferma()
            }
        }

        // ── I campi, dopo ────────────────────────────────────────────────
        S.SettingRow {
            visible: page.passoPassword === "aperta"
            width: parent.width
            label: page.it ? "Nuova password" : "New password"
            description: ""
            controlWidth: 300

            control: Rectangle {
                width: 300
                height: 34
                radius: Theme.Effects.radiusXS
                color: Theme.Colors.sunken
                border.width: Theme.Effects.hairline
                border.color: nuova.activeFocus ? Theme.Colors.accent
                                                : Theme.Colors.edge

                TextInput {
                    id: nuova
                    anchors.fill: parent
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.rightMargin: Theme.Effects.space3
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }
            }
        }

        S.SettingRow {
            visible: page.passoPassword === "aperta"
            width: parent.width
            label: page.it ? "Ripetila" : "Repeat it"
            description: page.it
                ? "Due volte, perché quello che si scrive non si vede"
                : "Twice, because you cannot see what you type"
            controlWidth: 300

            control: Rectangle {
                width: 300
                height: 34
                radius: Theme.Effects.radiusXS
                color: Theme.Colors.sunken
                border.width: Theme.Effects.hairline
                border.color: {
                    if (ripeti.text === "")
                        return ripeti.activeFocus ? Theme.Colors.accent : Theme.Colors.edge;
                    return ripeti.text === nuova.text
                           ? Theme.Colors.positive : Theme.Colors.danger;
                }

                TextInput {
                    id: ripeti
                    anchors.fill: parent
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.rightMargin: Theme.Effects.space3
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                    onAccepted: page.cambiaPassword()
                }
            }
        }

        /// Perché il pulsante è spento. Un pulsante grigio senza spiegazione
        /// costringe a indovinare, e la regola che non si rispetta è quasi
        /// sempre la lunghezza.
        Text {
            visible: page.passoPassword === "aperta" && page.motivoPassword !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: page.motivoPassword
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeXS
        }

        Row {
            visible: page.passoPassword === "aperta"
            spacing: Theme.Effects.space2

            Rectangle {
                width: 170
                height: 34
                radius: Theme.Effects.radiusSM
                // Spento finché le due non combaciano: un pulsante che si può
                // premere e non fa niente costringe a indovinare perché.
                opacity: page.passwordPronta ? 1 : 0.4
                color: applicaPass.containsMouse && page.passwordPronta
                       ? Qt.alpha(Theme.Colors.accent, 0.35)
                       : Qt.alpha(Theme.Colors.accent, 0.20)
                border.width: Theme.Effects.hairline
                border.color: Qt.alpha(Theme.Colors.accent, 0.5)

                Text {
                    anchors.centerIn: parent
                    text: page.it ? "Applica" : "Apply"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }

                MouseArea {
                    id: applicaPass
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: page.passwordPronta
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.cambiaPassword()
                }
            }

            Rectangle {
                width: 120
                height: 34
                radius: Theme.Effects.radiusSM
                color: annullaMouse.containsMouse ? Theme.Colors.raisedHigh
                                                  : Theme.Colors.raised
                border.width: Theme.Effects.hairline
                border.color: Theme.Colors.edge

                Text {
                    anchors.centerIn: parent
                    text: page.it ? "Lascia perdere" : "Never mind"
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }

                MouseArea {
                    id: annullaMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.chiudiPassword()
                }
            }
        }
    }

    /// Quello che si scrive nei campi non esce di qui se non passa di qua.
    ///
    /// Otto caratteri è il minimo, e non è l'unica regola che conta: quelle
    /// vere (parole di vocabolario, ripetizioni, la password di prima) le
    /// applica PAM quando `chpasswd` scrive, e se le rifiuta il messaggio
    /// arriva in fondo alla pagina. Qui si fermano solo i casi che si
    /// riconoscono senza chiedere a nessuno.
    readonly property bool passwordPronta:
        nuova.text.length > 0 && page.motivoPassword === ""

    readonly property string motivoPassword: {
        if (nuova.text.length === 0)
            return "";
        if (nuova.text.length < 8)
            return page.it ? "Almeno otto caratteri." : "At least eight characters.";
        if (page.io && nuova.text.toLowerCase() === String(page.io.nome).toLowerCase())
            return page.it ? "Non può essere il tuo nome utente."
                           : "It cannot be your user name.";
        if (ripeti.text.length === 0)
            return page.it ? "Manca la ripetizione." : "The repeat is missing.";
        if (nuova.text !== ripeti.text)
            return page.it ? "Le due non combaciano." : "The two do not match.";
        return "";
    }

    // ── L'esito ──────────────────────────────────────────────────────────

    Text {
        width: parent ? parent.width : 0
        wrapMode: Text.WordWrap
        visible: page.esito !== ""
        text: page.esito
        color: page.esitoGrave ? Theme.Colors.danger : Theme.Colors.positive
        font.family: Theme.Typography.fontDisplay
        font.weight: Theme.Typography.weightRegular
        font.pixelSize: Theme.Typography.sizeSM
    }

    // ── Le azioni ────────────────────────────────────────────────────────
    //
    // Ognuna passa i valori come ARGOMENTI e non incollati in una riga di
    // shell: un nome con un apostrofo o un percorso con uno spazio non devono
    // poter diventare un comando. Vedi `core/Exec.qml`.

    function percorsoUtente() {
        return "/org/freedesktop/Accounts/User" + (page.io ? page.io.uid : 0);
    }

    function cambiaFoto(via) {
        if (!page.io)
            return;
        page.racconta(page.it ? "Sto applicando la foto…" : "Applying the photo…");
        foto.shArgs(
            'test -r "$1" || { echo "NONLEGGO"; exit 0; }; ' +
            'busctl call org.freedesktop.Accounts "$2" ' +
            'org.freedesktop.Accounts.User SetIconFile s "$1" 2>&1',
            [via, page.percorsoUtente()]);
    }

    Core.Exec {
        id: foto
        onDone: function (out) {
            if (out.indexOf("NONLEGGO") !== -1) {
                page.racconta(page.it ? "Quel file non si legge."
                                      : "That file cannot be read.", true);
            } else if (out.trim() === "") {
                page.racconta(page.it ? "Foto cambiata." : "Photo changed.");
                page.versioneFoto++;
                page.ricarica();
            } else {
                page.racconta(out.trim(), true);
            }
        }
    }

    function cambiaNome(n) {
        if (!page.io)
            return;
        page.racconta(page.it ? "Sto applicando il nome…" : "Applying the name…");
        nomeExec.shArgs(
            'busctl call org.freedesktop.Accounts "$2" ' +
            'org.freedesktop.Accounts.User SetRealName s "$1" 2>&1',
            [n, page.percorsoUtente()]);
    }

    Core.Exec {
        id: nomeExec
        onDone: function (out) {
            if (out.trim() === "") {
                page.racconta(page.it ? "Nome cambiato." : "Name changed.");
                page.ricarica();
            } else {
                page.racconta(out.trim(), true);
            }
        }
    }

    // ── I due passaggi della password ────────────────────────────────────

    function chiediConferma() {
        if (!page.io || page.comandoUtente === "")
            return;
        page.passoPassword = "conferma";
        page.racconta(page.it ? "Il sistema sta chiedendo chi sei…"
                              : "The system is asking who you are…");
        conferma.command = ["pkexec", page.comandoUtente,
                            "conferma", page.io.nome];
        conferma.running = true;
    }

    function chiudiPassword() {
        page.passoPassword = "chiusa";
        nuova.text = "";
        ripeti.text = "";
    }

    Process {
        id: conferma
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.indexOf("autorizzato") !== -1) {
                    page.passoPassword = "aperta";
                    page.esito = "";
                    nuova.forceActiveFocus();
                }
            }
        }
        // `pkexec` esce 126 se la finestrella viene annullata e 127 se non è
        // riuscito ad aprirla. In tutti e due i casi non c'è niente da
        // scrivere su stdout, quindi il segnale di sopra non arriva mai: senza
        // questo la pagina resterebbe per sempre «in attesa del sistema».
        onExited: function (code) {
            if (page.passoPassword !== "aperta") {
                page.passoPassword = "chiusa";
                page.racconta(code === 126
                    ? (page.it ? "Annullato." : "Cancelled.")
                    : (page.it ? "Il sistema non ti ha riconosciuto."
                               : "The system did not recognise you."), true);
            }
        }
    }

    function cambiaPassword() {
        if (!page.passwordPronta || !page.io || page.passoPassword !== "aperta" || cambio.running)
            return;
        if (/[\r\n\u0000]/.test(nuova.text)) {
            page.racconta(page.it ? "La password contiene un carattere non valido."
                                  : "The password contains an invalid character.", true);
            return;
        }
        page.racconta(page.it ? "Sto cambiando la password…"
                              : "Changing the password…");
        // Nessun wrapper sh con la password in $1: anche gli argv del wrapper
        // sarebbero leggibili. Il segreto passa direttamente su stdin.
        page._passwordDaInviare = nuova.text;
        cambio.stdinEnabled = true;
        cambio.command = ["pkexec", page.comandoUtente, "password", page.io.nome];
        cambio.running = true;
    }

    property string _passwordDaInviare: ""

    function completaCambioPassword(code, out, err) {
        page._passwordDaInviare = "";
        if (code === 0 && out.trim() === "fatto") {
            page.racconta(page.it ? "Password cambiata." : "Password changed.");
            page.chiudiPassword();
        } else {
            var t = err.trim() || out.trim();
            page.racconta(t === ""
                ? (code === 126 ? (page.it ? "Annullato." : "Cancelled.")
                                : (page.it ? "Cambio password non riuscito." : "Password change failed."))
                : t, true);
        }
    }

    Process {
        id: cambio
        onStarted: {
            cambio.write(page._passwordDaInviare + "\n");
            page._passwordDaInviare = "";
            cambio.stdinEnabled = false;
        }
        onRunningChanged: {
            if (!running && page._passwordDaInviare !== "") {
                page._passwordDaInviare = "";
                cambio.stdinEnabled = false;
                page.racconta(page.it ? "Impossibile avviare il cambio password."
                                      : "Cannot start the password change.", true);
            }
        }
        stdout: StdioCollector {
            id: uscitaCambio
        }
        stderr: StdioCollector { id: erroreCambio }
        onExited: function(code) {
            Qt.callLater(function() {
                page.completaCambioPassword(code, uscitaCambio.text, erroreCambio.text);
            });
        }
    }
}

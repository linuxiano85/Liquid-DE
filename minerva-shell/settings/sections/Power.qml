import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import "../../ui" as Ui
import ".." as S

// Power — Profilo energetico, batteria e tempi di inattività.
//
// ── Questo pannello non applica più niente ────────────────────────────────
//
// Fino al 1º settembre 2026 qui dentro si RISCRIVEVA un file:
// `~/.config/hypr/hypridle.conf`, la configurazione di un programma di un
// altro ambiente, e poi lo si ammazzava e riavviava perché la rileggesse. A
// ogni pixel del cursore trascinato. Lo stesso valeva per il coperchio, che
// finiva in una riga `bindl = , switch:on:Lid Switch, exec, …` — sintassi di
// Hyprland, in un file di Hyprland.
//
// Adesso qui si scrive **solo l'impostazione**, e chi la applica è
// `shell.qml`: legge le tre soglie, le manda al nostro compositore con
// `sorvegliaInattivita()`, e quando lui annuncia che sono passate decide cosa
// fare. Il pannello mostra e scrive; la politica sta in un posto solo.
//
// È lo stesso confine di tutto il resto: due strade per la stessa cosa
// divergono sempre, e in questo progetto è già successo.
Page {
    id: page

    title: Core.Strings.lang === "it" ? "Alimentazione" : "Power"
    subtitle: Core.Strings.lang === "it"
              ? "Profilo energetico, batteria e cosa succede quando ti allontani"
              : "Power profile, battery, and what happens when you step away"

    readonly property bool it: Core.Strings.lang === "it"

    // ── Profilo energetico ───────────────────────────────────────────────

    property string profile: ""
    property var profiles: []

    Core.Exec {
        id: profileQuery
        onDone: function(out) {
            // `powerprofilesctl list` marca l'attivo con un asterisco e
            // rientra le proprietà: si tengono solo le righe che finiscono
            // con i due punti, che sono i nomi.
            var found = [];
            var active = "";
            var lines = out.split("\n");
            for (var i = 0; i < lines.length; i++) {
                var l = lines[i];
                var m = l.match(/^(\*?)\s*([a-z-]+):\s*$/);
                if (!m)
                    continue;
                found.push(m[2]);
                if (m[1] === "*")
                    active = m[2];
            }
            page.profiles = found;
            page.profile = active;
        }
    }

    // ── Il profilo si scrive in fila, e poi si rilegge ───────────────────
    //
    // Era `fire`, che col comando precedente ancora in corso non lanciava
    // niente: «Risparmio» e subito «Prestazioni» lasciavano la macchina in
    // risparmio con la pagina che diceva prestazioni, e nessuno la
    // rileggeva. Adesso `start` mette in fila, e a ogni comando finito si
    // chiede a `powerprofilesctl` com'è davvero — anche quando il cambio è
    // stato rifiutato (30 settembre 2026).
    Core.Exec {
        id: setter
        onCompleted: function(codice, uscita, errore) {
            if (!setter.busy)
                profileQuery.start(["powerprofilesctl", "list"]);
        }
    }

    function setProfile(name) {
        page.profile = name;
        setter.start(["powerprofilesctl", "set", name]);
    }

    readonly property var profileLabels: ({
        "power-saver": { "it": "Risparmio",  "en": "Power saver",
                         "d_it": "Meno consumi, meno prestazioni. La batteria dura di più.",
                         "d_en": "Less power, less performance. The battery lasts longer." },
        "balanced":    { "it": "Equilibrato", "en": "Balanced",
                         "d_it": "Il compromesso di tutti i giorni.",
                         "d_en": "The everyday compromise." },
        "performance": { "it": "Prestazioni", "en": "Performance",
                         "d_it": "Tutto quello che il processore può dare. Scalda e consuma.",
                         "d_en": "Everything the processor can give. It runs hot and drains." }
    })

    // ── Batteria ─────────────────────────────────────────────────────────

    property string batteryState: ""
    property string batteryTime: ""
    property string batteryHealth: ""

    // ── `upower` risponde in inglese, e con quattro decimali ─────────────
    //
    // Quello che scriveva era «5,4 hours di autonomia · salute 78,2517 %»:
    // mezza frase in inglese in mezzo a una italiana, e una percentuale di
    // salute della batteria con quattro cifre dopo la virgola, che nessuno
    // guarda e che cambia da sola ogni venti secondi.
    //
    // I numeri li lascia com'è — la virgola è già quella giusta, la mette
    // upower seguendo la lingua del sistema — e si traduce solo l'unità.

    /// «3,2 hours» → «3,2 ore». Se non riconosce l'unità lascia stare: meglio
    /// una parola inglese che una frase inventata.
    function inItaliano(t) {
        if (!page.it || t === "")
            return t;
        var voci = { "hours": "ore", "hour": "ora",
                     "minutes": "minuti", "minute": "minuto",
                     "seconds": "secondi", "second": "secondo",
                     "days": "giorni", "day": "giorno" };
        for (var k in voci) {
            if (t.endsWith(k))
                return t.substring(0, t.length - k.length) + voci[k];
        }
        return t;
    }

    /// «78,2517%» → «78%». La salute di una batteria è un numero intero:
    /// le altre cifre sono rumore che si muove da solo.
    function arrotonda(t) {
        var m = String(t).match(/^\s*(-?[0-9]+)[.,]?([0-9]*)\s*%?\s*$/);
        if (!m)
            return t;
        var n = parseFloat(m[1] + "." + (m[2] === "" ? "0" : m[2]));
        return Math.round(n) + "%";
    }

    Core.Exec {
        id: batteryQuery
        onDone: function(out) {
            function field(name) {
                var m = out.match(new RegExp(name + ":\\s*(.+)"));
                return m ? m[1].trim() : "";
            }
            page.batteryState = field("state");
            var full = field("time to full");
            var empty = field("time to empty");
            page.batteryTime = page.inItaliano(full !== "" ? full : empty);
            page.batteryHealth = page.arrotonda(field("capacity"));
        }
    }

    // ── Inattività ───────────────────────────────────────────────────────
    //
    // Tre soglie in minuti: qui si mostrano in minuti perché è così che le
    // pensa chi le sposta. `shell.qml` le legge dalle stesse chiavi, le
    // moltiplica per sessanta e le manda al compositore.

    readonly property int dimAfter:     Core.Ipc.get("power.dimAfter", 5)
    readonly property int lockAfter:    Core.Ipc.get("power.lockAfter", 10)
    readonly property int screenOffAfter: Core.Ipc.get("power.screenOffAfter", 15)
    readonly property int suspendAfter: Core.Ipc.get("power.suspendAfter", 30)

    /// Cambiare una soglia è cambiare un'impostazione, e basta.
    ///
    /// Qui c'era `writeIdle()`: sessanta righe che componevano il file di
    /// `hypridle` — `general { lock_cmd … }`, tre `listener { timeout … }` —
    /// lo scrivevano di fianco, lo rinominavano, ammazzavano il programma e lo
    /// riavviavano. Con un `Timer` da 900 ms davanti, perché altrimenti quel
    /// giro partiva cinquanta volte mentre si trascinava il cursore.
    ///
    /// Adesso il numero va nelle impostazioni e si ferma lì. `shell.qml` ha le
    /// tre soglie legate a queste stesse chiavi: appena il demone annuncia il
    /// valore nuovo, lui rimanda l'elenco al compositore. Nessun file, nessun
    /// processo da riavviare, e nessun ritardo da aspettare.
    function setIdle(key, minutes) {
        Core.Ipc.setSetting("power." + key, minutes);
    }

    // ── Aggiornamento ────────────────────────────────────────────────────

    Component.onCompleted: {
        refresh();
        Core.Compositore.chiediRisparmio();
    }

    function refresh() {
        profileQuery.start(["powerprofilesctl", "list"]);
        batteryQuery.sh("upower -i \"$(upower -e | grep -m1 BAT)\" 2>/dev/null");
    }

    Timer {
        interval: 20000
        // Solo con le Impostazioni davanti: ridotte o dietro un'altra
        // finestra non c'è nessuno a guardare. Tornandoci si aggiorna
        // subito (`triggeredOnStart`).
        running: Qt.application.state === Qt.ApplicationActive
        triggeredOnStart: true
        repeat: true
        onTriggered: page.refresh()
    }

    // ── Batteria ─────────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Batteria" : "Battery"
        visible: Core.SystemState.hasBattery

        Item {
            width: parent.width
            // ── L'altezza si CONTA, non si indovina ──────────────────────
            //
            // Erano 54 pixel fissi, e non bastavano: il sottotitolo («A
            // batteria · 3,2 ore di autonomia · salute 78%») finiva sotto la
            // barra della carica, che gli passava sopra a metà riga. In QML
            // due cose che si sovrappongono non danno nessun avviso: si
            // vedono, e basta.
            height: 6 + batPercent.height + sottoBatteria.height
                    + Theme.Effects.space2 + 6

            Ui.Icon {
                id: batIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 26; height: 26
                name: "battery"
                color: Core.SystemState.batteryPercent <= 15 && !Core.SystemState.batteryCharging
                       ? Theme.Colors.danger
                       : Core.SystemState.batteryCharging ? Theme.Colors.positive
                       : Theme.Colors.textMuted
            }

            Text {
                id: batPercent
                anchors.left: batIcon.right
                anchors.leftMargin: Theme.Effects.space3
                anchors.top: parent.top
                anchors.topMargin: 6
                text: Core.SystemState.batteryPercent + "%"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeXL
                font.weight: Theme.Typography.weightBold
            }

            Text {
                id: sottoBatteria
                anchors.left: batIcon.right
                anchors.leftMargin: Theme.Effects.space3
                anchors.top: batPercent.bottom
                anchors.right: parent.right
                elide: Text.ElideRight
                text: {
                    var s = Core.SystemState.batteryCharging
                            ? (page.it ? "In carica" : "Charging")
                            : (page.it ? "A batteria" : "On battery");
                    if (page.batteryTime !== "")
                        s += "  ·  " + page.batteryTime
                             + (Core.SystemState.batteryCharging
                                ? (page.it ? " alla carica completa" : " until full")
                                : (page.it ? " di autonomia" : " remaining"));
                    if (page.batteryHealth !== "")
                        s += "  ·  " + (page.it ? "salute " : "health ") + page.batteryHealth;
                    return s;
                }
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeSM
            }

            // Barra della carica, spessa: si legge da lontano.
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 6
                radius: 3
                color: Theme.Colors.sunken

                Rectangle {
                    // A pixel interi: col renderer software una larghezza a
                    // virgola lascia una riga di pixel che nessuno ridipinge.
                    // Vedi `ui/Slider.qml`, che sullo stesso difetto ci ha
                    // fatto perdere mezza giornata.
                    width: Math.round(parent.width
                           * Math.max(0, Core.SystemState.batteryPercent) / 100)
                    height: parent.height
                    radius: parent.radius
                    color: Core.SystemState.batteryPercent <= 15
                           && !Core.SystemState.batteryCharging
                           ? Theme.Colors.danger
                           : Core.SystemState.batteryCharging ? Theme.Colors.positive
                           : Theme.Colors.accent
                    // Niente `Behavior` sulla larghezza: vedi `ui/Slider.qml`.
                    // Una misura che cambia a ogni fotogramma lascia dietro i
                    // pixel di quelli prima, e la carica cambia ogni venti
                    // secondi — non e' un'animazione che qualcuno guarda.
                }
            }
        }
    }

    // ── Profilo ──────────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Profilo energetico" : "Power profile"
        visible: page.profiles.length > 0

        Repeater {
            model: page.profiles

            delegate: Rectangle {
                id: prof
                required property var modelData

                readonly property bool current: page.profile === modelData
                readonly property var info: page.profileLabels[modelData]
                                            || { "it": modelData, "en": modelData,
                                                 "d_it": "", "d_en": "" }

                width: parent.width
                height: 54
                radius: Theme.Effects.radiusSM
                color: current ? Qt.alpha(Theme.Colors.accent, 0.16)
                     : profMouse.containsMouse ? Theme.Colors.hover
                     : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
                border.width: 1
                border.color: current ? Qt.alpha(Theme.Colors.accent, 0.45) : "transparent"

                Ui.Icon {
                    id: profIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 19; height: 19
                    name: prof.modelData === "power-saver" ? "moon"
                        : prof.modelData === "performance" ? "cpu"
                        : "battery"
                    color: prof.current ? Theme.Colors.accent : Theme.Colors.textFaint
                }

                Column {
                    anchors.left: profIcon.right
                    anchors.leftMargin: Theme.Effects.space3
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: page.it ? prof.info.it : prof.info.en
                        color: prof.current ? Theme.Colors.text : Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeMD
                        font.weight: prof.current ? Theme.Typography.weightSemiBold
                                                  : Theme.Typography.weightMedium
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        visible: text !== ""
                        text: page.it ? prof.info.d_it : prof.info.d_en
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.weight: Theme.Typography.weightRegular
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }

                MouseArea {
                    id: profMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.setProfile(prof.modelData)
                }
            }
        }
    }

    // ── Inattività ───────────────────────────────────────────────────────

    // ── Gli effetti a batteria ───────────────────────────────────────────
    //
    // Il compositore abbassa gli effetti da sé — niente blur né trasparenza,
    // cornice ferma, elastico spento — e li rialza quando torna la corrente. Qui si sceglie
    // la regola; lo stato di adesso la pagina lo chiede al compositore,
    // perché è LUI che decide, e una pagina che lo indovinasse dalla batteria
    // direbbe il vero solo finché le due regole coincidono.
    //
    // A scrivania ferma, con blur e cornice che gira, sono 12,6 fotogrammi al
    // secondo contro zero (misurati il 23 settembre 2026).

    readonly property string risparmioModo: Core.Ipc.get("power.risparmioEffetti", "auto")
    readonly property var risparmio: Core.Compositore.risparmio || {}

    Connections {
        target: Core.Ipc
        // La regola la manda la shell, e il compositore ci mette un attimo:
        // si richiede dopo ogni scrittura, così la riga «adesso» non resta
        // indietro di una scelta.
        function onSettingsChanged() { rileggiRisparmio.restart(); }
    }
    Timer {
        id: rileggiRisparmio
        interval: 400
        onTriggered: Core.Compositore.chiediRisparmio()
    }

    // ── La memoria che respira ──────────────────────────────────────────
    //
    // Le nostre app fuori vista da un minuto si comprimono in zram: misurata
    // la Calcolatrice nascosta, da 32 MB veri a 8, e risponde in 38 ms. Il
    // lavoro lo fa il demone (`minervad/lib/services/respiro_service.dart`).
    Card {
        heading: page.it ? "Memoria" : "Memory"

        S.SettingRow {
            width: parent.width
            label: page.it ? "La memoria che respira" : "Breathing memory"
            description: page.it
                ? "Le app di Liquid che non guardi da un minuto si comprimono: occupano circa un quarto, e tornano appena le riprendi"
                : "Liquid apps you have not looked at for a minute are compressed to about a quarter, and come back as soon as you use them"
            searchTerms: "memoria ram zram comprimi respira leggero app"
            controlWidth: 260

            control: S.ChoicePicker {
                value: String(Core.Ipc.get("memoria.respiro", "delicata"))
                options: [
                    { "value": "delicata", "label": page.it ? "Accesa" : "On" },
                    { "value": "spenta",   "label": page.it ? "Spenta" : "Off" }
                ]
                onPicked: function(v) { Core.Ipc.setSetting("memoria.respiro", v); }
            }
        }
    }

    Card {
        heading: page.it ? "Effetti e batteria" : "Effects and battery"
        visible: Core.Compositore.nostro
        note: {
            var r = page.risparmio;
            if (r.attivo === undefined)
                return "";
            if (!r.attivo)
                return page.it ? "Adesso: effetti pieni." : "Now: full effects.";
            var perche = r.motivo === "batteria"
                ? (page.it ? "batteria al " + r.percento + " %" : "battery at " + r.percento + "%")
                : r.motivo === "profilo"
                ? (page.it ? "profilo risparmio energetico" : "power saver profile")
                : (page.it ? "scelto qui" : "chosen here");
            return (page.it ? "Adesso: effetti ridotti (" : "Now: effects reduced (")
                   + perche + ").";
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Riduci gli effetti" : "Reduce effects"
            description: page.it
                ? "Niente acquerello né trasparenza, cornice ferma, finestre senza elastico"
                : "No watercolour or transparency, still border, no wobbly windows"
            searchTerms: "risparmio batteria effetti acquerello trasparenza energia"
            controlWidth: 330

            control: S.ChoicePicker {
                value: page.risparmioModo
                options: [
                    { "value": "auto",   "label": page.it ? "A batteria bassa" : "On low battery" },
                    { "value": "sempre", "label": page.it ? "Sempre" : "Always" },
                    { "value": "mai",    "label": page.it ? "Mai" : "Never" }
                ]
                onPicked: function(v) {
                    Core.Ipc.setSetting("power.risparmioEffetti", v);
                }
            }
        }

        Item {
            width: parent.width
            height: 52
            visible: page.risparmioModo === "auto"

            Text {
                id: sogliaLabel
                anchors.left: parent.left
                anchors.top: parent.top
                text: page.it ? "Sotto questa carica" : "Below this charge"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.weight: Theme.Typography.weightRegular
                font.pixelSize: Theme.Typography.sizeMD
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: sogliaLabel.verticalCenter
                // `mostrato` e non `value`: il numero segue il dito mentre si
                // trascina (il cursore non scrive più il suo `value`).
                text: Math.round(sogliaCursore.mostrato) + " %"
                color: Theme.Colors.accent
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeSM
            }

            S.ValueSlider {
                id: sogliaCursore
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                from: 5
                to: 80
                unit: "niente"
                value: Core.Ipc.get("power.risparmioSoglia", 20)
                onReleased: function(v) {
                    Core.Ipc.setSetting("power.risparmioSoglia", Math.round(v));
                }
            }
        }
    }

    Card {
        heading: page.it ? "Quando ti allontani" : "When you step away"
        note: page.it
              ? "Trascina tutto a sinistra per non farlo succedere mai. "
                + "I minuti si contano da quando smetti di toccare tastiera e mouse."
              : "Drag fully left to never do it. Minutes count from the moment you "
                + "stop touching the keyboard and mouse."

        Repeater {
            model: [
                { "key": "dimAfter",
                  "it": "Abbassa la luminosità dopo", "en": "Dim the screen after",
                  "value": page.dimAfter, "max": 30 },
                { "key": "lockAfter",
                  "it": "Blocca lo schermo dopo",     "en": "Lock the screen after",
                  "value": page.lockAfter, "max": 60 },
                { "key": "screenOffAfter",
                  "it": "Spegni lo schermo dopo",     "en": "Turn the screen off after",
                  "value": page.screenOffAfter, "max": 120 },
                { "key": "suspendAfter",
                  "it": "Sospendi il computer dopo",  "en": "Suspend the computer after",
                  "value": page.suspendAfter, "max": 120 }
            ].filter(function (r) {
                // Senza una retroilluminazione (un fisso col monitor esterno)
                // «abbassa la luminosità» non ha niente da abbassare: una
                // levetta che non fa niente è peggio di nessuna levetta. La
                // stessa regola che nasconde il cursore della luminosità in
                // Schermo.
                return r.key !== "dimAfter" || Core.SystemState.hasBrightness;
            })

            delegate: Item {
                id: idle
                required property var modelData

                width: parent.width
                height: 52

                Text {
                    id: idleLabel
                    anchors.left: parent.left
                    anchors.top: parent.top
                    text: page.it ? idle.modelData.it : idle.modelData.en
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeMD
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: idleLabel.verticalCenter
                    text: idle.modelData.value <= 0
                          ? (page.it ? "mai" : "never")
                          : idle.modelData.value + (page.it ? " min" : " min")
                    color: idle.modelData.value <= 0 ? Theme.Colors.textFaint
                                                     : Theme.Colors.accent
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeSM
                }

                S.ValueSlider {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    from: 0
                    to: idle.modelData.max
                    // «mai» / «10 min» sta già sopra al cursore.
                    unit: "niente"
                    value: idle.modelData.value
                    onMoved: function(v) {
                        // Anteprima dal vivo del numero, senza scrivere niente
                        // su disco finché il dito non si stacca.
                        Core.Ipc.settings = Core.Ipc.settings;
                    }
                    onReleased: function(v) {
                        page.setIdle(idle.modelData.key, Math.round(v));
                    }
                }
            }
        }
    }

    // ── Comportamento del coperchio ──────────────────────────────────────

    Card {
        heading: page.it ? "Chiusura del coperchio" : "Closing the lid"
        visible: Core.SystemState.hasBattery

        S.SettingRow {
            width: parent.width
            label: page.it ? "Alla chiusura del coperchio" : "When the lid closes"
            controlWidth: 420

            control: S.ChoicePicker {
                value: Core.Ipc.get("power.lidAction", "suspend")
                options: [
                    { "value": "suspend", "label": page.it ? "Sospendi" : "Suspend" },
                    { "value": "lock",    "label": page.it ? "Blocca soltanto" : "Just lock" },
                    { "value": "none",    "label": page.it ? "Non fare niente" : "Do nothing" }
                ]
                onPicked: function(v) {
                    // Solo l'impostazione: la legge `shell.qml` in
                    // `onCoperchio`, quando il compositore annuncia che il
                    // coperchio si è chiuso.
                    Core.Ipc.setSetting("power.lidAction", v);
                }
            }
        }
    }

    // ── Qui c'era `writeLid()` ───────────────────────────────────────────
    //
    // Scriveva `~/.config/hypr/minerva-lid.conf` con dentro
    // `bindl = , switch:on:Lid Switch, exec, systemctl suspend`, lo faceva
    // includere da `minerva-user.conf` e chiedeva al compositore di
    // ricaricare. Tre file e una ricarica per una scelta fra tre parole.
    //
    // Il nostro compositore l'interruttore del coperchio lo guarda da sé e lo
    // annuncia (`evento coperchio`); `shell.qml` legge `power.lidAction` e
    // decide. Restava una seconda sorgente di verità per la stessa politica —
    // e due sorgenti divergono sempre.
}

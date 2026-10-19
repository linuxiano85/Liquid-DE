import QtQuick
import QtQuick.Effects
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// PaginaTv — La TV di tutto il mondo in Minerva Media.
//
// Come Hypnotix di Linux Mint, e con lo stesso catalogo: Free-TV, canali
// gratuiti e pubblici, divisi per nazione. Il catalogo lo chiede il demone
// (`minervad/lib/services/tv_service.dart`, dove c'è anche cosa esce dal
// computer); guardare lo fa il lettore di Media, lo stesso della musica:
// la pagina dice solo QUALE canale con `guarda`, e presta il suo schermo.
//
// Tre colonne: le nazioni, i canali della nazione, lo schermo. A schermo
// intero restano solo le immagini.
//
// Niente loghi dei canali, come per le radio: starebbero su cento server
// diversi, e sfogliare un elenco vorrebbe dire contattarli tutti. Al loro
// posto la sigla su un colore che viene dal nome.
//
// Richiesta del manutentore, 18 ottobre 2026: «un servizio come hypnotix di
// linux mint per poter vedere la tv, modalità a schermo intero, modalità
// pip».
Item {
    id: pagina

    /// Il canale nel lettore (il suo `id`), vuoto se nessuno.
    property string inOnda: ""
    /// Vero quando le immagini arrivano davvero, non solo scelte.
    property bool suona: false
    /// Il lettore non riesce: il suo messaggio.
    property string erroreLettore: ""
    /// La finestra è a schermo intero: si vede solo lo schermo.
    property bool pieno: false
    /// Il video è nel PiP: qui resta un segnaposto.
    property bool inPip: false
    /// Quale delle sorgenti del canale sta provando il lettore (da 1).
    property int sorgente: 0
    property int sorgenti: 0

    /// Dove il lettore appoggia il video quando si guarda la TV.
    readonly property alias schermo: schermoTv

    /// Guardare questo canale: `{id, nome, paese, nazione, url, sorgenti}`.
    signal guarda(var canale)
    signal pienoRichiesto()
    signal pipRichiesto()
    signal pausaRichiesta()

    readonly property bool it: Core.Strings.lang === "it"

    /// Il paese di chi usa il computer, dalla lingua del sistema.
    readonly property string paeseCasa: {
        var parti = Qt.locale().name.split("_");
        return parti.length > 1 && /^[A-Z]{2}$/.test(parti[1]) ? parti[1] : "";
    }

    /// «★» per i preferiti, altrimenti il codice della nazione.
    property string paese: Core.Ipc.get("media.tvPaese", "") || pagina.paeseCasa || "★"
    property var paesi: []
    property var canali: []
    property int totale: 0
    property bool altri: false
    property bool cercando: false
    property string errore: ""
    property string canaleCorrente: ""

    property var preferiti: Core.Ipc.get("media.tvPreferiti", [])

    readonly property var mostrati: {
        if (pagina.paese !== "★")
            return pagina.canali;
        var t = campo.text.trim().toLowerCase();
        return pagina.preferiti.filter(function (c) {
            return t === "" || String(c.nome).toLowerCase().indexOf(t) >= 0;
        });
    }

    // ── Il catalogo ──────────────────────────────────────────────────────

    /// La richiesta in corso: si tiene solo la risposta a questa.
    property string _chiesta: ""
    property bool _aggiungi: false
    property bool _avviata: false

    function carica(daCapo) {
        if (pagina.paese === "★" && pagina.paesi.length > 0)
            return;
        pagina._aggiungi = !daCapo;
        pagina.cercando = true;
        pagina.errore = "";
        pagina._chiesta = Core.Ipc.mediaRichiesta("media_tv", {
            "testo": campo.text.trim(),
            "paese": pagina.paese === "★" ? "" : pagina.paese,
            "inizio": daCapo ? 0 : pagina.canali.length,
            "limite": 200
        });
        if (pagina._chiesta === "")
            pagina.cercando = false;
    }

    function scegliPaese(codice) {
        pagina.paese = codice;
        Core.Ipc.setSetting("media.tvPaese", codice === "★" ? "★" : codice);
        pagina.canali = [];
        elencoCanali.positionViewAtBeginning();
        pagina.carica(true);
    }

    function avvia() {
        if (pagina._avviata)
            return;
        pagina._avviata = true;
        pagina.carica(true);
    }

    onVisibleChanged: if (visible) pagina.avvia()

    Connections {
        target: Core.Ipc
        function onMediaRisposta(r) {
            if (!r || r.request !== pagina._chiesta || pagina._chiesta === "")
                return;
            pagina.cercando = false;
            pagina.errore = r.error === "tv-catalog-unavailable"
                ? (pagina.it ? "Il catalogo dei canali non si scarica. Sei in rete?"
                             : "The channel list cannot be downloaded. Are you online?")
                : (r.error || "") !== ""
                  ? (pagina.it ? "Il catalogo non risponde." : "The catalog does not answer.")
                  : "";
            if (r.paesi && r.paesi.length)
                pagina.paesi = r.paesi;
            if (pagina.paese === "★")
                return;
            pagina.canali = pagina._aggiungi ? pagina.canali.concat(r.canali || [])
                                             : (r.canali || []);
            pagina.totale = r.totale || 0;
            pagina.altri = r.altri === true;
        }
    }

    // ── I preferiti ──────────────────────────────────────────────────────

    function preferito(id) {
        for (var i = 0; i < pagina.preferiti.length; i++)
            if (pagina.preferiti[i].id === id)
                return true;
        return false;
    }

    function alternaPreferito(c) {
        var nuovi = pagina.preferiti.filter(function (p) { return p.id !== c.id; });
        if (nuovi.length === pagina.preferiti.length)
            nuovi.push({ "id": c.id, "nome": c.nome, "paese": c.paese || "" });
        Core.Ipc.setSetting("media.tvPreferiti", nuovi);
    }

    // ── Guardare ─────────────────────────────────────────────────────────

    /// Un preferito ha solo `id` e nome: l'indirizzo lo dà il demone, che
    /// apre solo ciò che è nel catalogo.
    property string _chiestoCanale: ""

    function apri(c) {
        pagina.canaleCorrente = c.nome;
        if (c.url) {
            pagina.guarda(c);
            return;
        }
        pagina._chiestoCanale = Core.Ipc.mediaRichiesta("media_tv_canale", { "canale": c.id });
    }

    Connections {
        target: Core.Ipc
        function onMediaRisposta(r) {
            if (!r || r.request !== pagina._chiestoCanale || pagina._chiestoCanale === "")
                return;
            pagina._chiestoCanale = "";
            if (r.canale)
                pagina.guarda(r.canale);
            else
                pagina.errore = pagina.it ? "Il canale non è più nel catalogo."
                                          : "The channel is no longer in the catalog.";
        }
    }

    /// Due segni per riconoscere un canale senza il suo logo.
    function sigla(nome) {
        var parole = String(nome).replace(/\(.*?\)|\[.*?\]/g, "")
            .split(/[^A-Za-z0-9À-ÿ+]+/).filter(function (p) { return p !== ""; });
        if (parole.length === 0)
            return String(nome).charAt(0).toUpperCase();
        if (/^[0-9]+$/.test(parole[0]) || parole[0].length <= 3)
            return parole[0].substring(0, 3).toUpperCase();
        var s = parole[0].charAt(0);
        if (parole.length > 1)
            s += parole[1].charAt(0);
        return s.toUpperCase();
    }

    function tinta(nome) {
        var h = 0;
        var s = String(nome);
        for (var i = 0; i < s.length; i++)
            h = (h * 31 + s.charCodeAt(i)) % 360;
        return Qt.hsla(h / 360, 0.45, 0.40, 1);
    }

    // ── Le nazioni ───────────────────────────────────────────────────────

    Item {
        id: colonnaPaesi
        visible: !pagina.pieno
        width: pagina.pieno ? 0 : Math.min(230, pagina.width * 0.22)
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }

        Text {
            id: titoloPaesi
            text: pagina.it ? "Nazioni" : "Countries"
            font { family: Theme.Typography.fontDisplay
                   ; pixelSize: Theme.Typography.sizeSM
                   ; weight: Theme.Typography.weightSemiBold
                   ; capitalization: Font.AllUppercase }
            font.letterSpacing: Theme.Typography.trackingLabel
            color: Theme.Colors.textFaint
        }

        ListView {
            id: elencoPaesi
            anchors { left: parent.left; right: parent.right
                      top: titoloPaesi.bottom; topMargin: Theme.Effects.space2
                      bottom: parent.bottom }
            clip: true
            spacing: 2
            model: {
                var testa = [{ codice: "★", nome: pagina.it ? "Preferiti" : "Favourites",
                               canali: pagina.preferiti.length }];
                var casa = [];
                var resto = [];
                for (var i = 0; i < pagina.paesi.length; i++) {
                    var p = pagina.paesi[i];
                    if (p.codice === pagina.paeseCasa)
                        casa.push(p);
                    else
                        resto.push(p);
                }
                return testa.concat(casa, resto);
            }
            delegate: Rectangle {
                id: vocePaese
                required property var modelData
                readonly property bool scelto: modelData.codice === pagina.paese
                width: elencoPaesi.width - 10
                height: 34
                radius: Theme.Effects.radiusSM
                color: scelto ? Qt.alpha(Theme.Colors.accent, 0.22)
                     : presaPaese.containsMouse ? Theme.Colors.hover : "transparent"

                Text {
                    id: codicePaese
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    width: 26
                    text: vocePaese.modelData.codice === "ZZ" ? "🌐" : vocePaese.modelData.codice
                    font { family: Theme.Typography.fontMono
                           ; pixelSize: Theme.Typography.sizeXS
                           ; weight: Theme.Typography.weightSemiBold }
                    color: vocePaese.scelto ? Theme.Colors.accent : Theme.Colors.textFaint
                }
                Text {
                    anchors { left: codicePaese.right; leftMargin: 6
                              right: numero.left; rightMargin: 6
                              verticalCenter: parent.verticalCenter }
                    text: vocePaese.modelData.nome
                    elide: Text.ElideRight
                    font { family: Theme.Typography.fontDisplay; pixelSize: Theme.Typography.sizeSM }
                    color: Theme.Colors.text
                }
                Text {
                    id: numero
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: vocePaese.modelData.canali
                    font { family: Theme.Typography.fontDisplay; pixelSize: Theme.Typography.sizeXS }
                    color: Theme.Colors.textFaint
                }
                MouseArea {
                    id: presaPaese
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: pagina.scegliPaese(vocePaese.modelData.codice)
                }
            }
        }
        Ui.Scorrimento {
            bersaglio: elencoPaesi
            anchors { right: elencoPaesi.right; top: elencoPaesi.top; bottom: elencoPaesi.bottom }
        }
    }

    // ── I canali ─────────────────────────────────────────────────────────

    Item {
        id: colonnaCanali
        visible: !pagina.pieno
        width: pagina.pieno ? 0 : Math.min(320, pagina.width * 0.3)
        anchors { left: colonnaPaesi.right; leftMargin: pagina.pieno ? 0 : Theme.Effects.space3
                  top: parent.top; bottom: parent.bottom }

        Ui.Campo {
            id: campo
            anchors { left: parent.left; right: parent.right; top: parent.top }
            segnaposto: pagina.it ? "Cerca un canale…" : "Search a channel…"
            onAccettato: pagina.carica(true)
        }
        Timer {
            // Si cerca mentre si scrive, ma non a ogni lettera.
            id: attesaCampo
            interval: 350
            onTriggered: if (pagina.paese !== "★") pagina.carica(true)
        }
        Connections {
            target: campo
            function onCambiato(testo) { attesaCampo.restart(); }
        }

        Text {
            id: statoCanali
            anchors { left: parent.left; right: parent.right
                      top: campo.bottom; topMargin: Theme.Effects.space2 }
            wrapMode: Text.WordWrap
            text: pagina.errore !== "" ? pagina.errore
                : pagina.cercando && pagina.canali.length === 0 ? (pagina.it ? "Carico i canali…" : "Loading channels…")
                : pagina.paese === "★" && pagina.mostrati.length === 0
                  ? (pagina.it ? "Nessun preferito: tocca la stella accanto a un canale."
                               : "No favourites yet: tap the star next to a channel.")
                : pagina.paese !== "★"
                  ? (pagina.it ? pagina.totale + " canali" : pagina.totale + " channels")
                  : ""
            font { family: Theme.Typography.fontDisplay; pixelSize: Theme.Typography.sizeXS }
            color: pagina.errore !== "" ? Theme.Colors.danger : Theme.Colors.textFaint
        }

        ListView {
            id: elencoCanali
            anchors { left: parent.left; right: parent.right
                      top: statoCanali.bottom; topMargin: Theme.Effects.space2
                      bottom: parent.bottom }
            clip: true
            spacing: 2
            cacheBuffer: 600
            model: pagina.mostrati
            onAtYEndChanged: if (atYEnd && pagina.altri && !pagina.cercando
                                 && pagina.paese !== "★") pagina.carica(false)
            delegate: Rectangle {
                id: voceCanale
                required property var modelData
                readonly property bool inOnda: modelData.id === pagina.inOnda
                width: elencoCanali.width - 10
                height: 46
                radius: Theme.Effects.radiusSM
                color: inOnda ? Qt.alpha(Theme.Colors.accent, 0.22)
                     : presaCanale.containsMouse ? Theme.Colors.hover : "transparent"

                MouseArea {
                    id: presaCanale
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: pagina.apri(voceCanale.modelData)
                }
                Rectangle {
                    id: sigla
                    anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                    width: 34; height: 34
                    radius: 9
                    color: pagina.tinta(voceCanale.modelData.nome)
                    Text {
                        anchors.centerIn: parent
                        text: pagina.sigla(voceCanale.modelData.nome)
                        font { family: Theme.Typography.fontDisplay
                               ; pixelSize: text.length > 2 ? 10 : 13
                               ; weight: Theme.Typography.weightBold }
                        color: "white"
                    }
                }
                Column {
                    anchors { left: sigla.right; leftMargin: 10
                              right: stella.left; rightMargin: 6
                              verticalCenter: parent.verticalCenter }
                    Text {
                        width: parent.width
                        text: voceCanale.modelData.nome
                        elide: Text.ElideRight
                        font { family: Theme.Typography.fontDisplay; pixelSize: Theme.Typography.sizeSM
                               ; weight: voceCanale.inOnda ? Theme.Typography.weightSemiBold
                                                           : Theme.Typography.weightRegular }
                        color: Theme.Colors.text
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: voceCanale.inOnda
                              ? (pagina.suona ? (pagina.it ? "● In onda" : "● On air")
                                              : (pagina.it ? "Sintonizzo…" : "Tuning…"))
                              : pagina.paese === "★" ? (voceCanale.modelData.paese || "") : ""
                        font { family: Theme.Typography.fontDisplay; pixelSize: Theme.Typography.sizeXS }
                        color: voceCanale.inOnda ? Theme.Colors.accent : Theme.Colors.textFaint
                    }
                }
                Item {
                    id: stella
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    width: 30; height: 30
                    readonly property bool accesa: pagina.preferito(voceCanale.modelData.id)
                    visible: accesa || presaCanale.containsMouse || presaStella.containsMouse
                    Ui.Icon {
                        anchors.centerIn: parent
                        width: 16; height: 16
                        name: "star"
                        color: stella.accesa ? Theme.Colors.accent : Theme.Colors.textFaint
                    }
                    MouseArea {
                        id: presaStella
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: pagina.alternaPreferito(voceCanale.modelData)
                    }
                }
            }
        }
        Ui.Scorrimento {
            bersaglio: elencoCanali
            anchors { right: elencoCanali.right; top: elencoCanali.top; bottom: elencoCanali.bottom }
        }
    }

    // ── Lo schermo ───────────────────────────────────────────────────────

    Rectangle {
        id: palco
        anchors { left: pagina.pieno ? parent.left : colonnaCanali.right
                  leftMargin: pagina.pieno ? 0 : Theme.Effects.space3
                  right: parent.right; top: parent.top; bottom: parent.bottom }
        radius: pagina.pieno ? 0 : Theme.Effects.radiusLG
        color: "black"
        clip: true

        Item {
            id: schermoTv
            anchors.fill: parent
            // `clip` taglia a rettangolo: il video copriva gli angoli tondi
            // dello schermo. La maschera li rifà, e a schermo intero (angoli
            // vivi) non serve.
            layer.enabled: !pagina.pieno && palco.radius > 0
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: mascheraTv
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }
        Item {
            id: mascheraTv
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Rectangle { anchors.fill: parent; radius: palco.radius; color: "black" }
        }

        // Un clic mette in pausa, il doppio clic va a schermo intero: come
        // in qualunque lettore.
        MouseArea {
            id: presaPalco
            anchors.fill: parent
            hoverEnabled: true
            onDoubleClicked: pagina.pienoRichiesto()
            onPositionChanged: comandiTv.sveglia()
        }

        Column {
            anchors.centerIn: parent
            spacing: Theme.Effects.space2
            visible: pagina.inOnda === "" || pagina.inPip || !pagina.suona
                     || pagina.erroreLettore !== ""
            width: parent.width * 0.8
            Ui.Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 46; height: 46
                name: pagina.erroreLettore !== "" ? "info" : "screen"
                color: Theme.Colors.textFaint
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: pagina.inOnda === ""
                      ? (pagina.it ? "Scegli un canale" : "Pick a channel")
                      : pagina.inPip ? (pagina.it ? "In riproduzione nel PiP" : "Playing in PiP")
                      : pagina.erroreLettore !== ""
                        ? (pagina.it ? "Il canale non trasmette: " : "The channel is not on air: ")
                          + pagina.erroreLettore
                        : (pagina.it ? "Sintonizzo " : "Tuning ") + pagina.canaleCorrente + "…"
                font { family: Theme.Typography.fontDisplay; pixelSize: Theme.Typography.sizeMD }
                color: Theme.Colors.textMuted
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: pagina.inOnda !== "" && !pagina.inPip && pagina.sorgenti > 1
                         && pagina.erroreLettore === ""
                text: (pagina.it ? "sorgente " : "source ") + pagina.sorgente + "/" + pagina.sorgenti
                font { family: Theme.Typography.fontDisplay; pixelSize: Theme.Typography.sizeXS }
                color: Theme.Colors.textFaint
            }
        }

        // I comandi: il nome del canale e tre tasti, che si ritirano da soli.
        Rectangle {
            id: comandiTv
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 56
            visible: pagina.inOnda !== ""
            opacity: svegli ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.7) }
            }
            property bool svegli: true
            function sveglia() { svegli = true; riposo.restart(); }
            Timer { id: riposo; interval: 3000; onTriggered: comandiTv.svegli = presaComandi.containsMouse }

            MouseArea { id: presaComandi; anchors.fill: parent; hoverEnabled: true
                        acceptedButtons: Qt.NoButton; onEntered: comandiTv.sveglia() }

            Text {
                anchors { left: parent.left; leftMargin: Theme.Effects.space4
                          right: tastiTv.left; rightMargin: Theme.Effects.space3
                          verticalCenter: parent.verticalCenter }
                text: pagina.canaleCorrente
                elide: Text.ElideRight
                font { family: Theme.Typography.fontDisplay; pixelSize: Theme.Typography.sizeMD
                       ; weight: Theme.Typography.weightSemiBold }
                color: "white"
            }
            Row {
                id: tastiTv
                anchors { right: parent.right; rightMargin: Theme.Effects.space3
                          verticalCenter: parent.verticalCenter }
                spacing: 4
                Repeater {
                    model: [
                        { cosa: "pausa", icona: pagina.suona ? "pause" : "play" },
                        { cosa: "pip", icona: "window" },
                        { cosa: "pieno", icona: pagina.pieno ? "collapse" : "expand" }
                    ]
                    delegate: Rectangle {
                        id: tastoTv
                        required property var modelData
                        width: 38; height: 38
                        radius: 19
                        color: presaTastoTv.pressed ? Qt.rgba(1, 1, 1, 0.3)
                             : presaTastoTv.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : "transparent"
                        Ui.Icon {
                            anchors.centerIn: parent
                            width: 18; height: 18
                            name: tastoTv.modelData.icona
                            color: "white"
                        }
                        MouseArea {
                            id: presaTastoTv
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                comandiTv.sveglia();
                                if (tastoTv.modelData.cosa === "pausa") pagina.pausaRichiesta();
                                else if (tastoTv.modelData.cosa === "pip") pagina.pipRichiesto();
                                else pagina.pienoRichiesto();
                            }
                        }
                    }
                }
            }
        }
    }
}

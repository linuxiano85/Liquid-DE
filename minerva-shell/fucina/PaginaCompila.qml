import QtQuick

import "../theme" as Theme
import "../ui" as Ui

// La pagina «Compila»: da dove, con che cosa, come si chiama — e il piano,
// comando per comando, prima di premere.
//
// A sinistra le scelte. A destra, in alto, i passi della ricetta con il loro
// stato; sotto, il diario con le righe di `make`. Il piano non è un
// riassunto: sono i comandi veri che il demone lancerà, gli stessi, perché li
// ricalcola dalle stesse scelte.
Item {
    id: pagina

    property var f: null
    property alias diario: diarioInterno

    readonly property var ric: pagina.f ? pagina.f.ricetta : null

    /// La voce dell'elenco di kernel.org per la versione scelta, o null.
    readonly property var voceVersione: {
        if (!pagina.f) return null;
        var v = pagina.f.versioni || [];
        for (var i = 0; i < v.length; i++)
            if (v[i].versione === pagina.f.versione) return v[i];
        return null;
    }

    readonly property bool cachyosSi: pagina.voceVersione !== null
                                      && pagina.voceVersione.cachyos === true
    /// La serie base di CachyOS: fino alla 6.17 sì, dalla 6.18 in poi nel
    /// loro repository non c'è più, e resta solo BORE.
    readonly property bool cachyosBase: pagina.voceVersione !== null
                                        && pagina.voceVersione.cachyosBase === true

    // ── A sinistra: le scelte ────────────────────────────────────────────

    Flickable {
        id: colonna
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: 400
        clip: true
        contentWidth: width
        contentHeight: sinistra.implicitHeight + Theme.Effects.space5 * 2
        boundsBehavior: Flickable.StopAtBounds
        onContentYChanged: Qt.callLater(pagina.f.ridipingiTutto)

        Column {
            id: sinistra
            x: Theme.Effects.space5
            y: Theme.Effects.space5
            width: colonna.width - Theme.Effects.space5 * 2
            spacing: Theme.Effects.space3
            enabled: !pagina.f.compilando
            opacity: enabled ? 1 : 0.55

            Titolo { testo: "Sorgente" }

            Flow {
                width: parent.width
                spacing: Theme.Effects.space2

                Etichetta {
                    cliccabile: true
                    scelta: pagina.f.sorgente === "vanilla"
                    testo: "Linux ufficiale"
                    onPremuta: pagina.f.sorgente = "vanilla"
                }
                Etichetta {
                    cliccabile: true
                    scelta: pagina.f.sorgente === "cachyos"
                    testo: "CachyOS" + (pagina.voceVersione === null ? ""
                                        : !pagina.cachyosSi ? " · niente patch per questa serie"
                                        : pagina.cachyosBase ? " · base e BORE"
                                        : " · solo BORE")
                    tono: pagina.f.sorgente === "cachyos" && pagina.voceVersione !== null
                          && !pagina.cachyosSi ? "attenzione" : ""
                    onPremuta: pagina.f.sorgente = "cachyos"
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: pagina.f.sorgente !== "cachyos"
                      ? "L'archivio ufficiale di kernel.org, così com'è."
                      : (pagina.cachyosBase
                         ? "L'archivio ufficiale con sopra la serie base di CachyOS e lo "
                           + "scheduler BORE. Le patch seguono l'ultima versione di ogni serie."
                         : "L'archivio ufficiale con sopra lo scheduler BORE di CachyOS. La "
                           + "loro serie base, per questa versione, non la pubblicano più nel "
                           + "repository delle patch: il kernel non sarà uguale al loro.")
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }

            Titolo {
                testo: "Versione"
                sotto: pagina.f.versioniErrore !== ""
                       ? pagina.f.versioniErrore + " Puoi scriverla a mano."
                       : ""
            }

            Flow {
                width: parent.width
                spacing: Theme.Effects.space2

                Repeater {
                    model: pagina.f.versioni

                    Etichetta {
                        required property var modelData
                        cliccabile: true
                        scelta: pagina.f.versione === modelData.versione
                        testo: modelData.versione + " · "
                               + (modelData.tipo === "longterm" ? "lungo termine" : "stabile")
                               + (modelData.finita ? " · finita" : "")
                        onPremuta: {
                            pagina.f.versioneScelta = true;
                            pagina.f.versione = modelData.versione;
                        }
                    }
                }
            }

            Ui.Campo {
                id: campoVersione
                width: 160
                segnaposto: "es. 6.17.2"
                text: pagina.f.versione
                onCambiato: (t) => {
                    if (t === pagina.f.versione) return;
                    pagina.f.versioneScelta = true;
                    pagina.f.versione = t.trim();
                }
            }

            Titolo {
                testo: "Configurazione di partenza"
                sotto: "Da quella del kernel in uso si toglie quello che non serve. Da "
                       + "defconfig si parte quasi da zero: localmodconfig toglie e non "
                       + "aggiunge, quindi molti driver non ci saranno."
            }

            Flow {
                width: parent.width
                spacing: Theme.Effects.space2

                Etichetta {
                    cliccabile: true
                    scelta: pagina.f.base === "in-uso"
                    testo: "Quella del kernel in uso"
                    onPremuta: pagina.f.base = "in-uso"
                }
                Etichetta {
                    cliccabile: true
                    scelta: pagina.f.base === "defconfig"
                    testo: "defconfig"
                    onPremuta: pagina.f.base = "defconfig"
                }
            }

            Titolo { testo: "Compilatore" }

            Flow {
                width: parent.width
                spacing: Theme.Effects.space2

                Etichetta {
                    cliccabile: true
                    scelta: pagina.f.compilatore === "gcc"
                    testo: "GCC"
                    onPremuta: pagina.f.compilatore = "gcc"
                }
                Etichetta {
                    cliccabile: true
                    scelta: pagina.f.compilatore === "clang"
                    testo: "Clang"
                    onPremuta: pagina.f.compilatore = "clang"
                }
            }

            Scelta {
                testo: "LTO sottile"
                spiega: "Ottimizza fra un file e l'altro: kernel un po' più rapido, "
                        + "compilazione più lunga. Solo con Clang."
                acceso: pagina.f.lto
                attiva: pagina.f.compilatore === "clang"
                onCommutata: pagina.f.lto = !pagina.f.lto
            }

            Scelta {
                testo: "Prova veloce"
                spiega: "Niente simboli di debug: la compilazione dura molto meno. Senza, "
                        + "però, non c'è BTF, e gli scheduler sched_ext non partono. Per "
                        + "provare se si avvia sì, per tutti i giorni no."
                acceso: pagina.f.provaVeloce
                onCommutata: pagina.f.provaVeloce = !pagina.f.provaVeloce
            }

            Scelta {
                testo: "Solo per questo processore"
                spiega: "Compilato per il processore che hai (x86-64 "
                        + (pagina.f.rilievo && pagina.f.rilievo.macchina
                           ? (pagina.f.rilievo.macchina.livelloX86 || "?") : "?")
                        + "): un po' più rapido qui, e non parte su un processore più "
                        + "vecchio. Esiste dal kernel 6.16: prima, il controllo dopo la "
                        + "configurazione ti dirà che non ha preso."
                acceso: pagina.f.nativo
                onCommutata: pagina.f.nativo = !pagina.f.nativo
            }

            Titolo {
                testo: "Nome"
                sotto: "Finisce nel nome del kernel, in /boot e nel menu d'avvio. Serve a "
                       + "tenere più prove una accanto all'altra."
            }

            Ui.Campo {
                width: parent.width
                segnaposto: "prova"
                text: pagina.f.nome
                onCambiato: (t) => { if (t !== pagina.f.nome) pagina.f.nome = t; }
            }

            Text {
                width: parent.width
                wrapMode: Text.WrapAnywhere
                text: pagina.f.rilascio
                color: pagina.f.nomeBuono && pagina.f.versioneBuona ? Theme.Colors.accent
                                                                   : Theme.Colors.warning
                font.family: Theme.Typography.fontMono
                font.pixelSize: Theme.Typography.sizeSM
            }
        }
    }

    Rectangle {
        id: divisore
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: colonna.right
        width: 1
        color: Theme.Colors.edge
    }

    // ── A destra: il piano e il diario ───────────────────────────────────

    Item {
        id: destra
        anchors.top: parent.top
        anchors.left: divisore.right
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.Effects.space5

        Text {
            id: titoloPiano
            anchors.top: parent.top
            anchors.left: parent.left
            text: "IL PIANO"
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
            font.weight: Theme.Typography.weightSemiBold
            font.letterSpacing: Theme.Typography.trackingLabel
        }

        Text {
            anchors.right: parent.right
            anchors.baseline: titoloPiano.baseline
            visible: pagina.ric !== null
            text: pagina.ric ? pagina.ric.impostazioni.length + " valori nel .config" : ""
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
        }

        Flickable {
            id: piano
            anchors.top: titoloPiano.bottom
            anchors.topMargin: Theme.Effects.space2
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height * 0.48
            clip: true
            contentWidth: width
            contentHeight: elencoPassi.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            onContentYChanged: Qt.callLater(pagina.f.ridipingiTutto)

            Column {
                id: elencoPassi
                width: piano.width - Theme.Effects.space3
                spacing: Theme.Effects.space2

                // Gli avvisi della ricetta vengono prima dei passi: sono le
                // cose da sapere PRIMA di premere.
                Repeater {
                    model: pagina.ric ? pagina.ric.avvisi : []

                    Text {
                        required property var modelData
                        width: elencoPassi.width
                        wrapMode: Text.WordWrap
                        text: "⚠ " + modelData
                        color: Theme.Colors.warning
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }

                Repeater {
                    id: ripetiPassi
                    model: pagina.ric ? pagina.ric.passi : []

                    Rectangle {
                        required property var modelData
                        required property int index
                        readonly property string stato: pagina.f.passi[modelData.id] || ""
                        width: elencoPassi.width
                        implicitHeight: righePasso.implicitHeight + Theme.Effects.space2 * 2
                        radius: Theme.Effects.radiusSM
                        color: stato === "via" ? Theme.Colors.selected : Theme.Colors.raised
                        border.width: Theme.Effects.hairline
                        border.color: stato === "fallito" ? Theme.Colors.danger
                                    : (stato === "via" ? Theme.Colors.edgeAccent
                                                       : Theme.Colors.edge)

                        // Il segno dello stato: un numero finché non è partito.
                        Rectangle {
                            id: segno
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.Effects.space2
                            anchors.top: parent.top
                            anchors.topMargin: Theme.Effects.space2
                            width: 22; height: 22
                            radius: 11
                            color: stato === "fatto" ? Qt.alpha(Theme.Colors.positive, 0.2)
                                 : stato === "fallito" ? Qt.alpha(Theme.Colors.danger, 0.2)
                                 : stato === "via" ? Qt.alpha(Theme.Colors.accent, 0.25)
                                 : Theme.Colors.sunken

                            Text {
                                anchors.centerIn: parent
                                text: stato === "fatto" ? "✓"
                                    : stato === "fallito" ? "✗"
                                    : stato === "saltato" ? "–"
                                    : String(index + 1)
                                color: stato === "fatto" ? Theme.Colors.positive
                                     : stato === "fallito" ? Theme.Colors.danger
                                     : Theme.Colors.textMuted
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeXS
                                font.weight: Theme.Typography.weightSemiBold
                            }
                        }

                        Column {
                            id: righePasso
                            anchors.left: segno.right
                            anchors.leftMargin: Theme.Effects.space2
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.Effects.space2
                            anchors.top: parent.top
                            anchors.topMargin: Theme.Effects.space2
                            spacing: 2

                            Text {
                                width: parent.width
                                text: modelData.titolo
                                      + (stato === "saltato" ? " · già fatto" : "")
                                      + (modelData.soloLaPrimaVolta && stato === ""
                                         ? " · solo la prima volta" : "")
                                color: Theme.Colors.text
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                                font.weight: Theme.Typography.weightMedium
                            }
                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: modelData.spiega
                                color: Theme.Colors.textFaint
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                            Text {
                                width: parent.width
                                visible: modelData.comando.length > 0
                                wrapMode: Text.WrapAnywhere
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                text: modelData.comando.join(" ")
                                color: Theme.Colors.textMuted
                                font.family: Theme.Typography.fontMono
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                        }
                    }
                }

                Text {
                    visible: pagina.ric === null
                    width: elencoPassi.width
                    wrapMode: Text.WordWrap
                    topPadding: Theme.Effects.space5
                    text: pagina.f.ricettaErrore !== "" ? pagina.f.ricettaErrore
                                                        : "Preparo il piano…"
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }
            }
        }

        // Il passo che sta lavorando resta sotto gli occhi: la compilazione è
        // il decimo passo, e senza questo il piano mostrerebbe i primi
        // quattro — già finiti — per tutta la durata.
        Connections {
            target: pagina.f
            function onPassiChanged() { Qt.callLater(pagina._mostraPassoAttivo); }
        }

        Ui.Scorrimento {
            bersaglio: piano
            anchors { right: piano.right; top: piano.top; bottom: piano.bottom }
        }

        Diario {
            id: diarioInterno
            anchors.top: piano.bottom
            anchors.topMargin: Theme.Effects.space4
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            titolo: pagina.f.compilando ? "Sto compilando" : "Diario"
            stato: pagina.f._statoDiario()
            avanzamento: pagina.f.compilando && pagina.f.attesi > 0
                         ? Math.min(1, pagina.f.fatti / pagina.f.attesi) : -1
        }
    }

    function _mostraPassoAttivo() {
        if (!pagina.ric) return;
        var l = pagina.ric.passi;
        for (var i = 0; i < l.length; i++) {
            if (pagina.f.passi[l[i].id] !== "via") continue;
            var voce = ripetiPassi.itemAt(i);
            if (!voce) return;
            var massimo = Math.max(0, piano.contentHeight - piano.height);
            piano.contentY = Math.max(0, Math.min(massimo, voce.y - Theme.Effects.space2));
            return;
        }
    }

    // ── I pezzi ──────────────────────────────────────────────────────────

    component Titolo: Column {
        property string testo: ""
        property string sotto: ""
        width: parent ? parent.width : 0
        spacing: 2
        topPadding: Theme.Effects.space2

        Text {
            text: parent.testo
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeMD
            font.weight: Theme.Typography.weightSemiBold
        }
        Text {
            visible: parent.sotto !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: parent.sotto
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
        }
    }

    component Scelta: Item {
        id: scelta
        property string testo: ""
        property string spiega: ""
        property bool acceso: false
        property bool attiva: true
        signal commutata()

        width: parent ? parent.width : 0
        implicitHeight: testiScelta.implicitHeight + Theme.Effects.space2
        opacity: scelta.attiva ? 1 : 0.5

        Spunta {
            id: spuntaScelta
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: 2
            stato: scelta.acceso ? 1 : 0
            attiva: scelta.attiva
            onPremuta: scelta.commutata()
        }

        Column {
            id: testiScelta
            anchors.left: spuntaScelta.right
            anchors.leftMargin: Theme.Effects.space3
            anchors.right: parent.right
            spacing: 2

            Text {
                text: scelta.testo
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
                font.weight: Theme.Typography.weightMedium
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: scelta.spiega
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }
        }

        MouseArea {
            anchors.fill: testiScelta
            enabled: scelta.attiva
            cursorShape: Qt.PointingHandCursor
            onClicked: scelta.commutata()
        }
    }
}

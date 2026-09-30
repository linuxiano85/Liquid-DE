import QtQuick

import "../theme" as Theme
import "../ui" as Ui

// La pagina «Moduli»: che cosa resta nel kernel, e perché.
//
// A sinistra le scelte grosse — i preset e le scorte — che valgono per
// famiglie intere. A destra le famiglie, chiuse all'apertura come in
// Manutenzione: prima QUANTO, poi COSA. Aperta una famiglia, ogni modulo dice
// da dove viene la ragione per tenerlo:
//
//   · «in uso»     guida un dispositivo adesso (driver legato);
//   · «caricato»   è in /proc/modules;
//   · «ricordato»  è nel diario di modprobed-db;
//   · «avvio»      serve ad avviare: non si toglie;
//   · «possibile»  saprebbe guidare un dispositivo rimasto senza driver.
//
// Le parole sono quelle e non i nomi interni (`legato`, `modprobed`…) perché
// chi guarda deve capire la ragione senza aver letto il demone.
Item {
    id: pagina

    property var f: null

    readonly property var r: pagina.f ? pagina.f.rilievo : null

    /// Le famiglie presenti, nell'ordine del catalogo, con i loro moduli.
    readonly property var gruppi: {
        var fuori = [];
        if (!pagina.r) return fuori;
        var fam = pagina.r.famiglie || [];
        var moduli = pagina.r.moduli || [];
        for (var i = 0; i < fam.length; i++) {
            var dentro = [];
            for (var j = 0; j < moduli.length; j++)
                if (moduli[j].famiglia === fam[i].id) dentro.push(moduli[j]);
            if (dentro.length > 0)
                fuori.push({ "famiglia": fam[i], "moduli": dentro });
        }
        return fuori;
    }

    property var aperte: ({})

    function apriChiudi(id) {
        var m = pagina.f._copia(pagina.aperte);
        m[id] = m[id] !== true;
        pagina.aperte = m;
        Qt.callLater(pagina.f.ridipingiTutto);
    }

    function conto(moduli) {
        var n = 0;
        for (var i = 0; i < moduli.length; i++)
            if (pagina.f.tenuto(moduli[i])) n++;
        return n;
    }

    function statoFamiglia(moduli) {
        var n = pagina.conto(moduli);
        if (n === 0) return 0;
        return n === moduli.length ? 1 : 2;
    }

    function parola(fonte) {
        switch (fonte) {
        case "legato": return "in uso";
        case "caricato": return "caricato";
        case "modprobed": return "ricordato";
        case "essenziale": return "avvio";
        case "candidato": return "possibile";
        }
        return fonte;
    }

    // ── A sinistra: preset e scorte ──────────────────────────────────────

    Flickable {
        id: colonna
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: 380
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

            Titolo {
                testo: "Per che cosa lo usi"
                sotto: "Se ne possono scegliere più d'uno. Per tick e prelazione vince "
                       + "il più reattivo; una famiglia si toglie solo se la tolgono "
                       + "tutti i preset scelti. Nessuno: resta la configurazione di "
                       + "partenza."
            }

            Flow {
                width: parent.width
                spacing: Theme.Effects.space2

                Repeater {
                    model: pagina.r ? pagina.r.presets : []

                    Etichetta {
                        required property var modelData
                        cliccabile: true
                        scelta: pagina.f.preset[modelData.id] === true
                        testo: modelData.nome + " · " + modelData.hz + " Hz"
                        onPremuta: pagina.f.commutaMappa("preset", modelData.id)
                    }
                }
            }

            Repeater {
                model: pagina.r ? pagina.r.presets : []

                Text {
                    required property var modelData
                    visible: pagina.f.preset[modelData.id] === true
                    width: sinistra.width
                    wrapMode: Text.WordWrap
                    text: modelData.nome + ": " + modelData.spiega
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                topPadding: Theme.Effects.space2
                text: "Il tick a 1000 Hz «per il gaming» conta meno di quanto dicano i "
                      + "forum: la sola prova vera è misurare prima e dopo."
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
                font.italic: true
            }

            Item { width: 1; height: Theme.Effects.space3 }

            Titolo {
                testo: "Da tenere comunque"
                sotto: "Famiglie che restano anche se oggi non c'è niente collegato che "
                       + "le usi: la chiavetta exFAT del mese prossimo, il controller "
                       + "che tiri fuori il sabato."
            }

            Repeater {
                model: pagina.r ? pagina.r.scorte : []

                Rectangle {
                    required property var modelData
                    readonly property bool accesa: pagina.f.scorte[modelData.id] === true
                    // Accesa da un preset: si vede, e si spegne togliendo il preset.
                    readonly property bool daPreset: {
                        var p = pagina.r.presets || [];
                        for (var i = 0; i < p.length; i++)
                            if (pagina.f.preset[p[i].id] === true
                                && (p[i].scorte || []).indexOf(modelData.id) >= 0)
                                return true;
                        return false;
                    }
                    width: sinistra.width
                    implicitHeight: righeScorta.implicitHeight + Theme.Effects.space3 * 2
                    radius: Theme.Effects.radiusSM
                    color: ditoScorta.containsMouse ? Theme.Colors.hover : Theme.Colors.raised
                    border.width: Theme.Effects.hairline
                    border.color: accesa || daPreset ? Theme.Colors.edgeAccent : Theme.Colors.edge

                    Spunta {
                        id: spuntaScorta
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.Effects.space3
                        anchors.top: parent.top
                        anchors.topMargin: Theme.Effects.space3
                        stato: accesa || daPreset ? 1 : 0
                        bloccata: daPreset && !accesa
                        onPremuta: pagina.f.commutaMappa("scorte", modelData.id)
                    }

                    Column {
                        id: righeScorta
                        anchors.left: spuntaScorta.right
                        anchors.leftMargin: Theme.Effects.space3
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.Effects.space3
                        anchors.top: parent.top
                        anchors.topMargin: Theme.Effects.space3
                        spacing: 2

                        Text {
                            text: modelData.nome + (daPreset && !accesa ? " · dal preset" : "")
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
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            text: modelData.moduli.join(" ")
                            color: Theme.Colors.textFaint
                            font.family: Theme.Typography.fontMono
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                    }

                    MouseArea {
                        id: ditoScorta
                        anchors.fill: parent
                        z: -1
                        hoverEnabled: true
                        enabled: !(daPreset && !accesa)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pagina.f.commutaMappa("scorte", modelData.id)
                    }
                }
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

    // ── A destra: le famiglie ────────────────────────────────────────────

    Flickable {
        id: rotolo
        anchors.top: parent.top
        anchors.left: divisore.right
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        contentWidth: width
        contentHeight: destra.implicitHeight + Theme.Effects.space5 * 2
        boundsBehavior: Flickable.StopAtBounds
        onContentYChanged: Qt.callLater(pagina.f.ridipingiTutto)

        Column {
            id: destra
            x: Theme.Effects.space5
            y: Theme.Effects.space5
            width: rotolo.width - Theme.Effects.space5 * 2
            spacing: Theme.Effects.space2

            Text {
                visible: pagina.r === null
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: 80
                text: "Aspetto il rilievo…"
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeLG
            }

            // Quello che la ricetta toglie per un preset si dice in cima: è
            // l'unico caso in cui un modulo esce senza che lo si tocchi.
            Text {
                readonly property var daPreset: {
                    var fuori = [];
                    var t = pagina.f && pagina.f.ricetta ? pagina.f.ricetta.tolti : null;
                    if (!t) return fuori;
                    for (var k in t) if (String(t[k]).indexOf("preset") >= 0) fuori.push(k);
                    return fuori;
                }
                visible: daPreset.length > 0
                width: parent.width
                wrapMode: Text.WordWrap
                bottomPadding: Theme.Effects.space2
                text: "Il preset toglie " + daPreset.length + " moduli anche se sono in uso: "
                      + daPreset.join(", ") + "."
                color: Theme.Colors.warning
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }

            Repeater {
                model: pagina.gruppi

                Column {
                    required property var modelData
                    readonly property var fam: modelData.famiglia
                    readonly property var moduli: modelData.moduli
                    readonly property bool aperta: pagina.aperte[fam.id] === true
                    width: destra.width
                    spacing: 2

                    Item {
                        width: parent.width
                        height: 50

                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: -Theme.Effects.space2
                            anchors.rightMargin: -Theme.Effects.space2
                            radius: Theme.Effects.radiusSM
                            color: ditoFam.containsMouse ? Theme.Colors.hover : "transparent"
                        }

                        Spunta {
                            id: spuntaFam
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.Effects.space2
                            anchors.verticalCenter: parent.verticalCenter
                            stato: pagina.statoFamiglia(moduli)
                            onPremuta: pagina.f.commutaFamiglia(moduli)
                        }

                        // La freccia: due rettangoli, per la stessa ragione della
                        // spunta.
                        Item {
                            id: freccia
                            anchors.left: spuntaFam.right
                            anchors.leftMargin: Theme.Effects.space3
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12; height: 12
                            rotation: aperta ? 90 : 0
                            Behavior on rotation { NumberAnimation { duration: Theme.Motion.instant } }

                            Rectangle {
                                x: 3; y: 3.2; width: 7; height: 1.8; radius: 0.9
                                rotation: 45; transformOrigin: Item.Right
                                color: Theme.Colors.textMuted
                            }
                            Rectangle {
                                x: 3; y: 7; width: 7; height: 1.8; radius: 0.9
                                rotation: -45; transformOrigin: Item.Right
                                color: Theme.Colors.textMuted
                            }
                        }

                        Column {
                            anchors.left: freccia.right
                            anchors.leftMargin: Theme.Effects.space3
                            anchors.right: contoFam.left
                            anchors.rightMargin: Theme.Effects.space3
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                text: fam.nome
                                color: Theme.Colors.text
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeMD
                                font.weight: Theme.Typography.weightSemiBold
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: fam.spiega
                                color: Theme.Colors.textFaint
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                        }

                        Text {
                            id: contoFam
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.Effects.space2
                            anchors.verticalCenter: parent.verticalCenter
                            text: pagina.conto(moduli) + " di " + moduli.length
                            color: Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                            font.weight: Theme.Typography.weightSemiBold
                            font.features: ({ "tnum": 1 })
                        }

                        MouseArea {
                            id: ditoFam
                            anchors.fill: parent
                            anchors.leftMargin: spuntaFam.width + Theme.Effects.space3
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pagina.apriChiudi(fam.id)
                        }
                    }

                    Repeater {
                        model: aperta ? moduli : []

                        Item {
                            required property var modelData
                            readonly property var mod: modelData
                            readonly property bool tenutoOra: pagina.f.tenuto(mod)
                            width: destra.width
                            height: 36

                            Spunta {
                                id: spuntaMod
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.Effects.space2 + 34
                                anchors.verticalCenter: parent.verticalCenter
                                stato: tenutoOra ? 1 : 0
                                bloccata: mod.essenziale === true
                                onPremuta: pagina.f.commutaModulo(mod)
                            }

                            Text {
                                id: nomeMod
                                anchors.left: spuntaMod.right
                                anchors.leftMargin: Theme.Effects.space3
                                anchors.verticalCenter: parent.verticalCenter
                                width: 220
                                elide: Text.ElideRight
                                text: mod.nome
                                color: tenutoOra ? Theme.Colors.text : Theme.Colors.textFaint
                                font.family: Theme.Typography.fontMono
                                font.pixelSize: Theme.Typography.sizeSM
                                font.strikeout: !tenutoOra && mod.diSerie === true
                            }

                            Row {
                                anchors.left: nomeMod.right
                                anchors.leftMargin: Theme.Effects.space2
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.Effects.space1

                                Repeater {
                                    model: mod.fonti

                                    Etichetta {
                                        required property var modelData
                                        testo: pagina.parola(modelData)
                                        tono: modelData === "essenziale" ? "attenzione"
                                            : (modelData === "legato" ? "buono" : "")
                                    }
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.Effects.space2
                                anchors.verticalCenter: parent.verticalCenter
                                visible: mod.essenziale === true
                                         || (pagina.f.ricetta && pagina.f.ricetta.tolti
                                             && pagina.f.ricetta.tolti[mod.nome] !== undefined)
                                text: mod.essenziale === true
                                      ? "serve ad avviare"
                                      : (pagina.f.ricetta && pagina.f.ricetta.tolti
                                         ? String(pagina.f.ricetta.tolti[mod.nome] || "") : "")
                                color: Theme.Colors.textFaint
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                        }
                    }
                }
            }
        }
    }

    Ui.Scorrimento {
        bersaglio: rotolo
        anchors { right: rotolo.right; top: rotolo.top; bottom: rotolo.bottom }
    }

    component Titolo: Column {
        property string testo: ""
        property string sotto: ""
        width: parent ? parent.width : 0
        spacing: 2

        Text {
            text: parent.testo
            color: Theme.Colors.text
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeLG
            font.weight: Theme.Typography.weightSemiBold
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: parent.sotto
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
        }
    }
}

import QtQuick

import "../theme" as Theme
import "../ui" as Ui

// La pagina «Macchina»: che cosa c'è in questo computer.
//
// Solo lettura. Serve a due cose: a fidarsi del rilievo (si vede su che cosa
// si basa — quanti dispositivi, se modprobed c'è, qual è il disco d'avvio) e
// a sapere PRIMA di compilare se manca un programma, che è il modo più comune
// di perdere un quarto d'ora: `flex` che manca si scopre dopo aver scaricato
// centocinquanta mega.
Item {
    id: pagina

    property var f: null
    /// La riga che il demone racconta mentre guarda.
    property string racconto: ""

    readonly property var r: pagina.f ? pagina.f.rilievo : null
    readonly property var m: pagina.r ? pagina.r.macchina : null

    Flickable {
        id: rotolo
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: dentro.implicitHeight + Theme.Effects.space5 * 2
        boundsBehavior: Flickable.StopAtBounds
        onContentYChanged: if (pagina.f) Qt.callLater(pagina.f.ridipingiTutto)

        Column {
            id: dentro
            x: Theme.Effects.space5
            y: Theme.Effects.space5
            width: rotolo.width - Theme.Effects.space5 * 2
            spacing: Theme.Effects.space5

            // ── Mentre guarda, e se non ha ancora guardato ─────────────
            Text {
                visible: pagina.r === null
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: 80
                text: pagina.racconto !== "" ? pagina.racconto : "Guardo il computer…"
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeLG
            }

            // ── Le quattro tessere ─────────────────────────────────────
            Flow {
                visible: pagina.r !== null
                width: parent.width
                spacing: Theme.Effects.space3

                Tessera {
                    titolo: "PROCESSORE"
                    valore: pagina.m ? String(pagina.m.cpu || "—") : ""
                    nota: pagina.m ? (pagina.m.nuclei + " processori logici · x86-64 "
                                      + (pagina.m.livelloX86 || "?")) : ""
                }
                Tessera {
                    titolo: "MEMORIA"
                    valore: pagina.m ? pagina.m.ramGB + " GB" : ""
                    nota: pagina.m && pagina.m.uefi ? "Avvio UEFI" : "Avvio BIOS"
                }
                Tessera {
                    titolo: "KERNEL IN USO"
                    valore: pagina.r ? String(pagina.r.rilascio) : ""
                    nota: pagina.r && pagina.r.configPartenza !== ""
                          ? "Configurazione da " + pagina.r.configPartenza
                          : "Configurazione non trovata"
                }
                Tessera {
                    titolo: "DISCO D'AVVIO"
                    valore: pagina.r ? String(pagina.r.avvio.dispositivo || "—") : ""
                    nota: pagina.r ? "Filesystem " + (pagina.r.avvio.tipo || "?") : ""
                }
                Tessera {
                    titolo: "DISPOSITIVI"
                    valore: pagina.r ? String(pagina.r.dispositivi.length) : ""
                    nota: pagina.r ? (pagina.r.senzaDriver.length + " senza driver · "
                                      + pagina.r.regole + " regole nel kernel in uso") : ""
                }
                Tessera {
                    titolo: "MODPROBED-DB"
                    valore: pagina.r ? (pagina.r.modprobed.presente
                                        ? pagina.r.modprobed.voci + " moduli ricordati"
                                        : "Non c'è") : ""
                    nota: pagina.r && pagina.r.modprobed.presente
                          ? "Quello che hai usato anche quando non era collegato"
                          : "Senza, vale solo quello che è collegato adesso"
                    allarme: pagina.r !== null && !pagina.r.modprobed.presente
                }
            }

            // ── Gli avvisi ─────────────────────────────────────────────
            Repeater {
                model: pagina.r ? pagina.r.avvisi : []

                Rectangle {
                    required property var modelData
                    width: dentro.width
                    implicitHeight: testoAvviso.implicitHeight + Theme.Effects.space3 * 2
                    radius: Theme.Effects.radiusSM
                    color: Qt.alpha(Theme.Colors.warning, 0.10)
                    border.width: Theme.Effects.hairline
                    border.color: Qt.alpha(Theme.Colors.warning, 0.35)

                    Text {
                        id: testoAvviso
                        anchors.fill: parent
                        anchors.margins: Theme.Effects.space3
                        wrapMode: Text.WordWrap
                        text: modelData
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }
                }
            }

            // ── Gli attrezzi per compilare ─────────────────────────────
            Titolo {
                visible: pagina.m !== null
                testo: "Per compilare"
                sotto: {
                    var manca = pagina.mancanti();
                    return manca.length === 0
                           ? "C'è tutto quello che serve."
                           : "Mancano: " + manca.join(", ")
                             + ". Su Arch e CachyOS: sudo pacman -S --needed "
                             + manca.join(" ");
                }
            }

            Flow {
                visible: pagina.m !== null
                width: parent.width
                spacing: Theme.Effects.space2

                Repeater {
                    model: pagina.m ? pagina.m.attrezzi : []

                    Etichetta {
                        required property var modelData
                        testo: (modelData.presente ? "✓ " : "✗ ") + modelData.nome
                               + " · " + modelData.serve
                        tono: modelData.presente ? "buono"
                            : (modelData.indispensabile ? "pericolo" : "attenzione")
                    }
                }
            }

            // ── I dispositivi senza driver ─────────────────────────────
            //
            // Non si tengono da soli: un dispositivo senza driver adesso non lo
            // stai usando. Ma può essere il Bluetooth che hai spento, e allora
            // lo si aggiunge da qui con un clic.
            Titolo {
                visible: pagina.r !== null && pagina.r.senzaDriver.length > 0
                testo: "Dispositivi senza driver"
                sotto: "Nessun modulo li guida adesso, quindi di serie restano fuori. "
                       + "Se ne usi uno ogni tanto, aggiungi il suo modulo."
            }

            Repeater {
                model: pagina.r ? pagina.r.senzaDriver : []

                Rectangle {
                    required property var modelData
                    width: dentro.width
                    height: 48
                    radius: Theme.Effects.radiusSM
                    color: Theme.Colors.raised
                    border.width: Theme.Effects.hairline
                    border.color: Theme.Colors.edge

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.Effects.space3
                        anchors.right: candidati.left
                        anchors.rightMargin: Theme.Effects.space3
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            width: parent.width
                            elide: Text.ElideMiddle
                            text: modelData.bus.toUpperCase() + " · " + modelData.percorso
                            color: Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: modelData.modalias
                            color: Theme.Colors.textFaint
                            font.family: Theme.Typography.fontMono
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                    }

                    Row {
                        id: candidati
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.Effects.space3
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.Effects.space2

                        Repeater {
                            model: modelData.candidati

                            Etichetta {
                                required property var modelData
                                cliccabile: true
                                scelta: pagina.f && pagina.f.aggiunti[modelData] === true
                                testo: (scelta ? "✓ " : "+ ") + modelData
                                onPremuta: pagina.f.commutaMappa("aggiunti", modelData)
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

    function mancanti() {
        var fuori = [];
        if (!pagina.m) return fuori;
        var a = pagina.m.attrezzi || [];
        var compilatore = pagina.f ? pagina.f.compilatore : "gcc";
        for (var i = 0; i < a.length; i++) {
            if (a[i].presente === true) continue;
            if (a[i].indispensabile === true || a[i].nome === compilatore)
                fuori.push(a[i].nome);
        }
        return fuori;
    }

    component Tessera: Rectangle {
        id: tessera
        property string titolo: ""
        property string valore: ""
        property string nota: ""
        property bool allarme: false

        // Dal genitore e non da `dentro`: un componente in linea non vede gli
        // id del file che lo contiene (lo dice la documentazione di Qt), e
        // contarci è un difetto che si vede solo su un'altra versione.
        width: parent ? Math.max(250, (parent.width - Theme.Effects.space3 * 2) / 3) : 250
        height: 96
        radius: Theme.Effects.radiusMD
        color: Theme.Colors.raised
        border.width: Theme.Effects.hairline
        border.color: tessera.allarme ? Qt.alpha(Theme.Colors.warning, 0.5) : Theme.Colors.edge

        Column {
            anchors.fill: parent
            anchors.margins: Theme.Effects.space4
            spacing: Theme.Effects.space1

            Text {
                text: tessera.titolo
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
                font.weight: Theme.Typography.weightSemiBold
                font.letterSpacing: Theme.Typography.trackingLabel
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: tessera.valore
                color: tessera.allarme ? Theme.Colors.warning : Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeLG
                font.weight: Theme.Typography.weightSemiBold
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: tessera.nota
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
            }
        }
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

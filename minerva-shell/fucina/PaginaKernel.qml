import QtQuick

import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// La pagina «Kernel»: quelli della Fucina, pronti e installati.
//
// Solo i nostri — il nome contiene `-fucina-` — e il demone non ne manda
// altri. Il kernel della distribuzione non compare: è quello che ti riporta
// a casa se il nostro non parte, e un elenco dove lo si può togliere con un
// clic è un elenco dove prima o poi qualcuno lo toglie.
//
// Installare e togliere chiedono due volte: qui, con una conferma che dice
// che cosa succederà, e poi la password di amministratore. La prima è per
// chi ha sbagliato riga, la seconda è per il sistema.
Item {
    id: pagina

    property var f: null

    /// Il kernel su cui si sta chiedendo conferma, e per fare che cosa.
    property string conferma: ""
    property string azione: ""
    property string lavorando: ""
    /// Le righe che l'aiutante di root vuole far leggere, per kernel.
    property var note: ({})
    property string errore: ""

    Connections {
        target: Core.Ipc

        function onFucinaInstallato(e) { pagina._esito(e, "installato"); }
        function onFucinaTolto(e) { pagina._esito(e, "tolto"); }
    }

    function _esito(e, cosa) {
        var chi = pagina.lavorando;
        pagina.lavorando = "";
        if (!e) return;
        var n = pagina.f._copia(pagina.note);
        if (e.ok === true) {
            pagina.errore = "";
            n[chi] = (e.note || []).map(function (r) { return r.replace(/^nota: ?/, ""); });
        } else {
            pagina.errore = e.annullato === true ? "Hai annullato la richiesta della password."
                                                 : String(e.errore || "Non ce l'ho fatta.");
        }
        pagina.note = n;
        Core.Ipc.fucinaChiediKernel();
    }

    function esegui() {
        var chi = pagina.conferma;
        var cosa = pagina.azione;
        pagina.conferma = "";
        pagina.azione = "";
        if (chi === "") return;
        pagina.lavorando = chi;
        pagina.errore = "";
        if (cosa === "installa") Core.Ipc.fucinaInstalla(chi);
        else if (cosa === "togli") Core.Ipc.fucinaTogli(chi);
    }

    Flickable {
        id: rotolo
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: dentro.implicitHeight + Theme.Effects.space5 * 2
        boundsBehavior: Flickable.StopAtBounds
        onContentYChanged: Qt.callLater(pagina.f.ridipingiTutto)

        Column {
            id: dentro
            x: Theme.Effects.space5
            y: Theme.Effects.space5
            width: rotolo.width - Theme.Effects.space5 * 2
            spacing: Theme.Effects.space3

            Text {
                text: "Stai usando " + (pagina.f.inUso || "…")
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            Text {
                visible: pagina.errore !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: "⚠ " + pagina.errore
                color: Theme.Colors.warning
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            Text {
                visible: pagina.f.kernel.length === 0
                width: parent.width
                wrapMode: Text.WordWrap
                topPadding: 60
                horizontalAlignment: Text.AlignHCenter
                text: "Nessun kernel della Fucina, per ora. Quando ne compili uno, "
                      + "compare qui pronto da installare."
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeLG
            }

            Repeater {
                model: pagina.f.kernel

                Rectangle {
                    required property var modelData
                    readonly property string rel: modelData.rilascio
                    readonly property bool chiede: pagina.conferma === rel
                    readonly property var mieNote: pagina.note[rel] || []
                    width: dentro.width
                    implicitHeight: righeKernel.implicitHeight + Theme.Effects.space4 * 2
                    radius: Theme.Effects.radiusMD
                    color: Theme.Colors.raised
                    border.width: Theme.Effects.hairline
                    border.color: modelData.inUso ? Theme.Colors.edgeAccent : Theme.Colors.edge

                    Column {
                        id: righeKernel
                        anchors.left: parent.left
                        anchors.right: pulsanti.left
                        anchors.margins: Theme.Effects.space4
                        anchors.top: parent.top
                        spacing: Theme.Effects.space2

                        Row {
                            spacing: Theme.Effects.space2

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: rel
                                color: Theme.Colors.text
                                font.family: Theme.Typography.fontMono
                                font.pixelSize: Theme.Typography.sizeMD
                                font.weight: Theme.Typography.weightSemiBold
                            }
                            Etichetta {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: modelData.inUso === true
                                testo: "in uso"
                                tono: "buono"
                            }
                            Etichetta {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: modelData.installato === true
                                testo: modelData.immagine === true ? "installato"
                                                                   : "installato, senza immagine"
                                tono: modelData.immagine === true ? "" : "attenzione"
                            }
                            Etichetta {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: modelData.pronto === true && modelData.installato !== true
                                testo: "pronto da installare"
                                scelta: true
                            }
                        }

                        Text {
                            visible: String(modelData.quando || "") !== ""
                            text: "Compilato il " + String(modelData.quando).substring(0, 19).replace("T", " alle ")
                                  + (modelData.moduli ? " · " + modelData.moduli + " moduli" : "")
                            color: Theme.Colors.textFaint
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                        }

                        // La conferma, detta per esteso.
                        Text {
                            visible: chiede
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: pagina.azione === "installa"
                                  ? "Copio il kernel in /boot e i moduli in /usr/lib/modules, "
                                    + "faccio l'initramfs e aggiungo la voce al menu d'avvio. Il "
                                    + "kernel che usi adesso resta dov'è. Ti chiederà la password."
                                  : "Tolgo " + rel + " da /boot, i suoi moduli e la sua voce "
                                    + "nel menu d'avvio. Non si disfa. Ti chiederà la password."
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }

                        Repeater {
                            model: mieNote

                            Text {
                                required property var modelData
                                width: righeKernel.width
                                wrapMode: Text.WrapAnywhere
                                text: modelData
                                color: Theme.Colors.textMuted
                                font.family: Theme.Typography.fontMono
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                        }
                    }

                    Row {
                        id: pulsanti
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.Effects.space4
                        anchors.top: parent.top
                        anchors.topMargin: Theme.Effects.space4
                        spacing: Theme.Effects.space2

                        Pulsante {
                            visible: !chiede && modelData.pronto === true && modelData.inUso !== true
                            attivo: pagina.lavorando === "" && !pagina.f.compilando
                            testo: pagina.lavorando === rel ? "Sto installando…"
                                 : (modelData.installato === true ? "Reinstalla" : "Installa")
                            primario: modelData.installato !== true
                            onScelto: { pagina.conferma = rel; pagina.azione = "installa"; }
                        }
                        Pulsante {
                            visible: !chiede && modelData.installato === true && modelData.inUso !== true
                            attivo: pagina.lavorando === ""
                            testo: pagina.lavorando === rel ? "Sto togliendo…" : "Togli"
                            onScelto: { pagina.conferma = rel; pagina.azione = "togli"; }
                        }
                        Pulsante {
                            visible: chiede
                            testo: "Lascia stare"
                            onScelto: { pagina.conferma = ""; pagina.azione = ""; }
                        }
                        Pulsante {
                            visible: chiede
                            primario: pagina.azione === "installa"
                            pericolo: pagina.azione === "togli"
                            testo: pagina.azione === "installa" ? "Sì, installa" : "Sì, togli"
                            onScelto: pagina.esegui()
                        }
                    }
                }
            }

            // ── La verifica al primo avvio ─────────────────────────────
            Item { width: 1; height: Theme.Effects.space4 }

            Row {
                spacing: Theme.Effects.space3

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: "Verifica al primo avvio"
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeLG
                        font.weight: Theme.Typography.weightSemiBold
                    }
                    Text {
                        width: dentro.width - 220
                        wrapMode: Text.WordWrap
                        text: "Avviato sul kernel nuovo, controlla che ogni dispositivo che "
                              + "aveva un driver quando hai compilato ce l'abbia ancora."
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }

                Pulsante {
                    anchors.verticalCenter: parent.verticalCenter
                    testo: "Verifica adesso"
                    onScelto: Core.Ipc.fucinaVerificaOra()
                }
            }

            Text {
                readonly property var v: pagina.f.verifica
                visible: v !== null
                width: parent.width
                wrapMode: Text.WordWrap
                text: {
                    if (!v) return "";
                    if (v.applicabile !== true) return String(v.spiega || "");
                    var o = (v.orfani || []).length;
                    return o === 0
                           ? "Tutto a posto: " + v.aPosto + " dispositivi hanno il loro driver"
                             + ((v.assenti || []).length > 0
                                ? ", " + v.assenti.length + " non sono collegati adesso." : ".")
                           : o + (o === 1 ? " dispositivo è rimasto" : " dispositivi sono rimasti")
                             + " senza driver: il modulo che li guidava non è nel kernel. "
                             + "Aggiungilo nei Moduli e ricompila.";
                }
                color: v && v.applicabile === true && (v.orfani || []).length > 0
                       ? Theme.Colors.warning : Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            Repeater {
                model: pagina.f.verifica && pagina.f.verifica.orfani ? pagina.f.verifica.orfani : []

                Text {
                    required property var modelData
                    width: dentro.width
                    elide: Text.ElideMiddle
                    text: "✗ " + modelData.modulo + " · " + modelData.driver
                          + " · " + modelData.percorso
                    color: Theme.Colors.warning
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeXS
                }
            }
        }
    }

    Ui.Scorrimento {
        bersaglio: rotolo
        anchors { right: rotolo.right; top: rotolo.top; bottom: rotolo.bottom }
    }
}

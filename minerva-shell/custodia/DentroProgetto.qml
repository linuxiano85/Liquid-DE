import QtQuick
import QtQuick.Controls

import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// DentroProgetto — un progetto aperto: cosa è cambiato, e come si torna indietro.
//
// ── L'ordine della pagina è l'ordine delle domande ─────────────────────────
//
//   1. **cosa è cambiato?**      in cima, raggruppato per significato
//   2. **come lo salvo?**        la casella e il pulsante, subito sotto
//   3. **come torno indietro?**  le due liste, in fondo
//
// Le due liste sono affiancate e non mescolate, e la ragione è la stessa che
// tiene separate le due parole: un salvataggio e un punto di ritorno riportano
// indietro cose diverse. Una lista sola, ordinata per data, farebbe credere
// che siano la stessa cosa a scelta — e il giorno che uno ha bisogno del punto
// di ritorno sceglierebbe il salvataggio, che è più recente.
Flickable {
    id: pagina

    property var dati: ({})
    property string percorso: ""
    property bool it: true
    property var grossi: []
    /// La finestra: serve solo a chiedere il selettore di cartelle, che deve
    /// coprirla tutta e quindi non può vivere qui dentro.
    property var finestra: null

    readonly property var stato: pagina.dati.stato || ({})
    readonly property var gruppi: pagina.stato.gruppi || []
    readonly property bool tieneStoria: pagina.stato.tieneStoria === true
    readonly property int quante: pagina.stato.quante || 0
    readonly property var firma: pagina.dati.firma || ({})

    contentHeight: corpo.implicitHeight + Theme.Effects.space4 * 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    // La barra la disegna `Custodia.qml`, che è il nostro genitore: da
    // dentro un Flickable non si può, perché ogni figlio si sposta con
    // il contenuto.

    // ── La conferma ──────────────────────────────────────────────────────
    //
    // Una sola, per tutti e due i «torna a…». Non chiede «sei sicuro?» — a cui
    // si risponde sempre sì senza leggere — ma dice **cosa succede** e **cosa
    // resta recuperabile**, che è l'informazione con cui uno decide davvero.

    property string chiedo: ""     // "salvataggio" | "punto" | "togli"
    property string chiedoId: ""
    property string chiedoCosa: ""

    function domanda(tipo, id, cosa) {
        pagina.chiedo = tipo;
        pagina.chiedoId = id;
        pagina.chiedoCosa = cosa;
    }

    Column {
        id: corpo
        x: Theme.Effects.space4
        y: Theme.Effects.space4
        width: pagina.width - Theme.Effects.space4 * 2
        spacing: Theme.Effects.space4

        // ── Le copie costano davvero, qui? ───────────────────────────────
        //
        // Su btrfs un punto di ritorno costa zero. Altrove costa quanto la
        // cartella, e chi lo scopre col disco pieno lo scopre troppo tardi.
        Rectangle {
            width: parent.width
            visible: pagina.dati.copiaGratuita === false
            height: caro.implicitHeight + Theme.Effects.space3 * 2
            radius: Theme.Effects.radiusMD
            color: Qt.alpha(Theme.Colors.warning, 0.12)

            Text {
                id: caro
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.Effects.space3
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.WordWrap
                text: pagina.it
                      ? "Su questo disco ogni punto di ritorno è una copia vera e occupa spazio. Sul disco principale di Minerva non costerebbe niente."
                      : "On this disk each restore point is a real copy and takes up space."
                color: Theme.Colors.warning
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }
        }

        // ── 1. Cosa è cambiato ───────────────────────────────────────────

        Column {
            width: parent.width
            spacing: Theme.Effects.space2

            Text {
                text: !pagina.tieneStoria
                      ? (pagina.it ? "Questa cartella non tiene ancora una storia"
                                   : "This folder keeps no history yet")
                      : pagina.quante === 0
                        ? (pagina.it ? "Tutto salvato" : "Everything saved")
                        : (pagina.it
                           ? "Da salvare: " + pagina.quante
                             + (pagina.quante === 1 ? " cosa" : " cose")
                           : pagina.quante + " to save")
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeLG
                font.weight: Theme.Typography.weightSemiBold
            }

            // I gruppi: «14 nella scrivania, 3 nel demone». È la frase con cui
            // uno racconta la giornata, e l'elenco dei percorsi non lo è.
            Flow {
                width: parent.width
                spacing: Theme.Effects.space2
                visible: pagina.gruppi.length > 0

                Repeater {
                    model: pagina.gruppi

                    Rectangle {
                        width: eg.implicitWidth + Theme.Effects.space3 * 2
                        height: 30
                        radius: 15
                        color: Theme.Colors.raised
                        border.width: 1
                        border.color: Theme.Colors.edge

                        Row {
                            id: eg
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.quante
                                color: Theme.Colors.accent
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                                font.weight: Theme.Typography.weightBold
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: pagina.it ? modelData.nome : modelData.nome
                                color: Theme.Colors.textMuted
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: apertoGruppo.testo =
                                (apertoGruppo.testo === modelData.nome)
                                ? "" : modelData.nome
                        }
                    }
                }
            }

            QtObject { id: apertoGruppo; property string testo: "" }

            // I file veri, solo del gruppo che si è aperto. Centodieci percorsi
            // tutti insieme non li legge nessuno; i quattordici di una cartella
            // sola, sì.
            Column {
                width: parent.width
                spacing: 2
                visible: apertoGruppo.testo !== ""

                Repeater {
                    model: {
                        for (var i = 0; i < pagina.gruppi.length; i++) {
                            if (pagina.gruppi[i].nome === apertoGruppo.testo) {
                                return pagina.gruppi[i].modifiche;
                            }
                        }
                        return [];
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.Effects.space2

                        Text {
                            width: 74
                            horizontalAlignment: Text.AlignRight
                            text: modelData.parola
                            color: modelData.verso === "tolto"
                                   ? Theme.Colors.danger
                                   : modelData.verso === "aggiunto"
                                     ? Theme.Colors.positive
                                     : Theme.Colors.textFaint
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                        Text {
                            width: parent.width - 74 - Theme.Effects.space2
                            elide: Text.ElideMiddle
                            text: modelData.percorso
                            color: Theme.Colors.textMuted
                            font.family: Theme.Typography.fontMono
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                    }
                }
            }
        }

        // ── 2. Salvare ───────────────────────────────────────────────────

        Rectangle {
            width: parent.width
            visible: pagina.tieneStoria
            height: salvataggio.implicitHeight + Theme.Effects.space4 * 2
            radius: Theme.Effects.radiusLG
            color: Theme.Colors.raised
            border.width: 1
            border.color: Theme.Colors.edge

            Column {
                id: salvataggio
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Theme.Effects.space4
                spacing: Theme.Effects.space3

                // La firma: si dice PRIMA, non al primo invio fallito.
                Text {
                    width: parent.width
                    visible: pagina.firma.completa === false
                             || pagina.firma.credibile === false
                    wrapMode: Text.WordWrap
                    text: pagina.firma.completa === false
                          ? (pagina.it
                             ? "Prima dimmi come firmare i salvataggi: manca il tuo nome o la tua email."
                             : "Tell me how to sign saves first: your name or email is missing.")
                          : (pagina.it
                             ? "Firmi come «" + (pagina.firma.email || "") + "», che non è un indirizzo vero: se un giorno mandi questo progetto su internet, i salvataggi risulteranno di nessuno."
                             : "You sign as «" + (pagina.firma.email || "") + "», which is not a real address.")
                    color: Theme.Colors.warning
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                // ── E dove dirlo ─────────────────────────────────────────
                //
                // Il messaggio qui sopra c'era, il posto dove rispondere no:
                // si poteva solo aprire un terminale e scrivere `git config`
                // (PC di prova, 29 settembre 2026). Chi è entrato in GitHub
                // non arriva quasi mai qui — la firma la prende il demone dal
                // suo account; questi due campi sono per chi GitHub non lo usa.
                Column {
                    id: firmaAMano
                    width: parent.width
                    spacing: Theme.Effects.space2
                    visible: pagina.firma.completa === false
                             || pagina.firma.credibile === false

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: pagina.it
                              ? "Scrivili qui, oppure entra in GitHub da «Dove va al sicuro»: li prendo dal tuo account, senza la tua email vera."
                              : "Type them here, or sign in to GitHub below: I'll take them from your account."
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXS
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.Effects.space2

                        TextField {
                            id: firmaNome
                            width: (parent.width - firmaVai.width - 2 * parent.spacing) / 2
                            text: pagina.firma.nome || ""
                            placeholderText: pagina.it ? "Il tuo nome" : "Your name"
                            color: Theme.Colors.text
                            placeholderTextColor: Theme.Colors.textFaint
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                            background: Rectangle {
                                radius: Theme.Effects.radiusMD
                                color: Theme.Colors.sunken
                                border.width: 1
                                border.color: firmaNome.activeFocus ? Theme.Colors.edgeAccent
                                                                    : Theme.Colors.edge
                            }
                        }
                        TextField {
                            id: firmaEmail
                            width: firmaNome.width
                            text: pagina.firma.email || ""
                            placeholderText: pagina.it ? "La tua email" : "Your email"
                            color: Theme.Colors.text
                            placeholderTextColor: Theme.Colors.textFaint
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                            background: Rectangle {
                                radius: Theme.Effects.radiusMD
                                color: Theme.Colors.sunken
                                border.width: 1
                                border.color: firmaEmail.activeFocus ? Theme.Colors.edgeAccent
                                                                     : Theme.Colors.edge
                            }
                            onAccepted: firmaVai.clicked()
                        }
                        Ui.SpineButton {
                            id: firmaVai
                            height: 34
                            horizontalPadding: Theme.Effects.space3
                            enabled: firmaNome.text.trim() !== ""
                                     && firmaEmail.text.indexOf("@") > 0
                            opacity: enabled ? 1 : 0.45
                            onClicked: {
                                if (!enabled) return;
                                Core.Ipc.custodiaFirma(pagina.percorso,
                                                       firmaNome.text.trim(),
                                                       firmaEmail.text.trim());
                            }
                            content: Text {
                                text: pagina.it ? "Firma così" : "Sign like this"
                                color: Theme.Colors.text
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeSM
                                font.weight: Theme.Typography.weightSemiBold
                            }
                        }
                    }
                }

                TextField {
                    id: cosaHaiFatto
                    width: parent.width
                    enabled: pagina.quante > 0
                    placeholderText: pagina.it
                        ? "Cosa hai fatto?  (lo leggerai tu, fra un mese)"
                        : "What did you do?"
                    color: Theme.Colors.text
                    placeholderTextColor: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeMD
                    background: Rectangle {
                        radius: Theme.Effects.radiusMD
                        color: Theme.Colors.sunken
                        border.width: 1
                        border.color: cosaHaiFatto.activeFocus
                                      ? Theme.Colors.edgeAccent
                                      : Theme.Colors.edge
                    }
                    onAccepted: salvaOra.clicked()
                }

                Row {
                    spacing: Theme.Effects.space2

                    Ui.SpineButton {
                        id: salvaOra
                        enabled: pagina.quante > 0
                                 && cosaHaiFatto.text.trim() !== ""
                        opacity: enabled ? 1 : 0.45
                        height: 38
                        horizontalPadding: Theme.Effects.space4
                        onClicked: {
                            if (!enabled) return;
                            Core.Ipc.custodiaSalva(pagina.percorso,
                                                   cosaHaiFatto.text);
                            cosaHaiFatto.text = "";
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
                                text: pagina.it ? "Salva" : "Save"
                                color: Theme.Colors.text
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeMD
                                font.weight: Theme.Typography.weightSemiBold
                            }
                        }
                    }

                    Ui.SpineButton {
                        height: 38
                        horizontalPadding: Theme.Effects.space4
                        onClicked: Core.Ipc.custodiaPunto(pagina.percorso, "")
                        content: Row {
                            spacing: Theme.Effects.space2
                            Ui.Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "restore"
                                width: 15; height: 15
                                color: Theme.Colors.textMuted
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: pagina.it ? "Prendi un punto di ritorno"
                                                : "Take a restore point"
                                color: Theme.Colors.textMuted
                                font.family: Theme.Typography.fontDisplay
                                font.pixelSize: Theme.Typography.sizeMD
                            }
                        }
                    }
                }

                // «Salvalo lo stesso»: compare solo dopo un rifiuto, che è
                // anche l'unico momento in cui ha senso.
                Column {
                    width: parent.width
                    spacing: 4
                    visible: pagina.grossi.length > 0

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: (pagina.it ? "Troppo grossi: "
                                         : "Too large: ")
                              + pagina.grossi.join(", ")
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                    Ui.SpineButton {
                        height: 32
                        horizontalPadding: Theme.Effects.space3
                        onClicked: Core.Ipc.custodiaSalva(
                            pagina.percorso, cosaHaiFatto.text, true)
                        content: Text {
                            text: pagina.it ? "Salvali lo stesso"
                                            : "Save them anyway"
                            color: Theme.Colors.warning
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                    }
                }
            }
        }

        // ── Cominciare, se non c'è ancora una storia ─────────────────────

        Ui.SpineButton {
            visible: !pagina.tieneStoria && pagina.dati.motore === "git"
            height: 40
            horizontalPadding: Theme.Effects.space4
            onClicked: Core.Ipc.custodiaInizia(pagina.percorso)
            content: Text {
                text: pagina.it ? "Comincia a tenere la storia"
                                : "Start keeping history"
                color: Theme.Colors.accent
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeMD
                font.weight: Theme.Typography.weightSemiBold
            }
        }

        // ── Dove va al sicuro ────────────────────────────────────────────
        //
        // Fra «salva» e «torna indietro», e non in fondo: è la domanda che uno
        // si fa subito dopo aver salvato — «e adesso, se si rompe il computer?»

        Destinazioni {
            width: parent.width
            progetto: pagina.dati
            percorso: pagina.percorso
            it: pagina.it
            finestra: pagina.finestra
        }

        // ── 3. Tornare indietro ──────────────────────────────────────────

        Row {
            width: parent.width
            spacing: Theme.Effects.space4

            // I salvataggi
            Column {
                width: (parent.width - Theme.Effects.space4) / 2
                spacing: Theme.Effects.space2
                visible: pagina.tieneStoria

                Text {
                    text: pagina.it ? "Salvataggi" : "Saves"
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    font.letterSpacing: Theme.Typography.trackingLabel
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: pagina.it
                          ? "Riportano indietro i file che tengo nella storia."
                          : "Bring back the files I keep in history."
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }

                Repeater {
                    model: pagina.dati.storia || []
                    RigaRitorno {
                        width: parent.width
                        it: pagina.it
                        titolo: modelData.cosa
                        quando: modelData.quando
                        marchio: modelData.breve
                        onTorna: pagina.domanda("salvataggio", modelData.id,
                                                modelData.cosa)
                    }
                }
            }

            // I punti di ritorno
            Column {
                width: (parent.width - Theme.Effects.space4) / 2
                spacing: Theme.Effects.space2

                Text {
                    text: pagina.it ? "Punti di ritorno" : "Restore points"
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    font.letterSpacing: Theme.Typography.trackingLabel
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: pagina.it
                          ? "Riportano indietro la cartella intera, anche quello che non salvo mai."
                          : "Bring back the whole folder, including what I never save."
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeXS
                }

                Repeater {
                    model: pagina.dati.elencoPunti || []
                    RigaRitorno {
                        width: parent.width
                        it: pagina.it
                        titolo: modelData.nota !== ""
                                ? modelData.nota
                                : (pagina.it ? "senza nota" : "no note")
                        quando: modelData.quando
                        marchio: ""
                        onTorna: pagina.domanda("punto", modelData.id,
                                                modelData.nota)
                    }
                }
            }
        }

        // ── Smettere di custodire ────────────────────────────────────────
        //
        // Si aggiungeva e non si toglieva: il demone lo sapeva fare
        // (`custodia_togli`), mancava il pulsante (5 ottobre 2026). Toglie
        // la cartella dall'ELENCO e basta: i punti di ritorno e le copie
        // restano dove sono, e la conferma lo dice.
        Ui.SpineButton {
            height: 36
            horizontalPadding: Theme.Effects.space4
            onClicked: pagina.domanda("togli", "", pagina.dati.nome || pagina.percorso)
            content: Text {
                text: pagina.it ? "Smetti di custodire questa cartella"
                                : "Stop keeping this folder safe"
                color: Theme.Colors.textMuted
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }
        }
    }

    // ── La conferma ──────────────────────────────────────────────────────

    Rectangle {
        anchors.fill: parent
        visible: pagina.chiedo !== ""
        color: Theme.Colors.scrim

        MouseArea { anchors.fill: parent; onClicked: pagina.chiedo = "" }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(480, parent.width - Theme.Effects.space4 * 2)
            height: dialogo.implicitHeight + Theme.Effects.space4 * 2
            radius: Theme.Effects.radiusLG
            color: Theme.Colors.panel
            border.width: 1
            border.color: Theme.Colors.edge

            MouseArea { anchors.fill: parent }

            Column {
                id: dialogo
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Theme.Effects.space4
                spacing: Theme.Effects.space3

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: pagina.chiedo === "togli"
                          ? (pagina.it
                             ? "Smetto di custodire «" + pagina.chiedoCosa + "»?"
                             : "Stop keeping «" + pagina.chiedoCosa + "» safe?")
                          : pagina.chiedo === "punto"
                          ? (pagina.it
                             ? "Torno alla cartella com'era in «"
                               + pagina.chiedoCosa + "»?"
                             : "Restore the folder as it was?")
                          : (pagina.it
                             ? "Torno al salvataggio «" + pagina.chiedoCosa + "»?"
                             : "Go back to that save?")
                    color: Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeLG
                    font.weight: Theme.Typography.weightSemiBold
                }

                // Non «sei sicuro?», a cui si risponde sì senza leggere.
                // Cosa succede, e cosa resta recuperabile.
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: pagina.chiedo === "togli"
                          ? (pagina.it
                             ? "Esce dall'elenco e smetto di guardarla. La cartella non si tocca, e i punti di ritorno e le copie che ha già restano dove sono: aggiungendola di nuovo li ritrovi."
                             : "It leaves the list and I stop watching it. The folder isn't touched, and its restore points and copies stay where they are: add it again and they're back.")
                          : pagina.it
                          ? "Quello che hai fatto da allora sparisce da questa cartella — anche i file aggiunti dopo.\n\nPrima di toccare qualsiasi cosa prendo un punto di ritorno di com'è adesso, quindi puoi tornare avanti."
                          : "Everything since then goes away — including files added later.\n\nI take a restore point of the current state first, so you can come back."
                    color: Theme.Colors.textMuted
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Row {
                    anchors.right: parent.right
                    spacing: Theme.Effects.space2

                    Ui.SpineButton {
                        height: 36
                        horizontalPadding: Theme.Effects.space4
                        onClicked: pagina.chiedo = ""
                        content: Text {
                            text: pagina.it ? "Lascia stare" : "Never mind"
                            color: Theme.Colors.textMuted
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeMD
                        }
                    }

                    Ui.SpineButton {
                        height: 36
                        horizontalPadding: Theme.Effects.space4
                        accent: Theme.Colors.warning
                        onClicked: {
                            if (pagina.chiedo === "togli") {
                                Core.Ipc.custodiaTogli(pagina.percorso);
                                // Si torna all'elenco: riaprire un progetto
                                // che non è più nell'elenco darebbe errore.
                                pagina.finestra.aperto = "";
                                pagina.finestra.dettaglio = ({});
                            } else if (pagina.chiedo === "punto") {
                                Core.Ipc.custodiaTornaAPunto(pagina.percorso,
                                                             pagina.chiedoId);
                            } else {
                                Core.Ipc.custodiaTornaASalvataggio(
                                    pagina.percorso, pagina.chiedoId);
                            }
                            pagina.chiedo = "";
                        }
                        content: Text {
                            text: pagina.chiedo === "togli"
                                  ? (pagina.it ? "Smetti di custodire" : "Stop")
                                  : (pagina.it ? "Torna indietro" : "Go back")
                            color: Theme.Colors.warning
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeMD
                            font.weight: Theme.Typography.weightSemiBold
                        }
                    }
                }
            }
        }
    }
}

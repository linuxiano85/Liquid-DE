import QtQuick

import "../theme" as Theme

// RigaVoce — una cosa che occupa posto, con tutto quello che serve per
// decidere se toglierla.
//
// ── Cosa c'è dentro una riga, e perché ognuna di queste cose ───────────────
//
// Il nome non basta, e il peso nemmeno. «Shelly, 4,24 GB» non dice a nessuno
// se quei quattro giga si possono buttare. Quindi ogni riga porta:
//
//   · **dove sta**, per esteso — `cache` non vuol dire niente,
//     `/home/giacomo/.cache/Shelly` sì, e chi vuole andare a guardare può;
//   · **se torna da sola** — è la differenza fra una cosa che si rifà
//     navigando e una che, tolta, è tolta;
//   · **se serve la password** — perché sta fuori dalla tua cartella, e
//     saperlo prima cambia l'ordine in cui uno spunta le cose;
//   · **quanto pesa rispetto alle altre**, con una barretta: il numero dice
//     il valore, la barra dice il rapporto, e a colpo d'occhio serve il
//     rapporto;
//   · **un avvertimento**, quando i megabyte non dicono tutto — le lingue che
//     tornano, `ccache` che costa una compilazione lenta.
//
// Sono le stesse cinque cose che un programma di pulizia di solito nasconde
// dietro a un pulsante «Ottimizza».
Item {
    id: riga

    property var voce: ({})
    property bool scelta: false
    property color colore: Theme.Colors.accent

    /// Vero quando questa riga È la sua famiglia: le lingue, il cestino, il
    /// registro sono una voce sola, e mostrarci sopra un'intestazione con lo
    /// stesso nome e lo stesso numero vuol dire scrivere due volte la stessa
    /// riga. Allora la riga si fa capofamiglia: nome più grande, la tacca
    /// colorata, e la frase che spiega la famiglia.
    property bool capofamiglia: false
    property string spiegazione: ""

    /// Il peso della voce più grossa dell'inventario: è il fondoscala della
    /// barretta. Comune a tutte le righe e non per famiglia, o due barre
    /// lunghe uguali in due gruppi diversi direbbero pesi diversi.
    property real massimo: 1

    signal commutata()

    readonly property bool haNota: String(riga.voce.avvertenza || "") !== ""

    implicitHeight: colonna.implicitHeight + Theme.Effects.space3 * 2

    // ── Una riga scelta si vede da lontano ───────────────────────────────
    //
    // Prima la spunta cambiava e basta, e la spunta era un quadratino col
    // bordo sottile: guardando l'elenco non si capiva cosa fosse preso e cosa
    // no. Adesso tutta la riga si accende, e il fondo dell'accento al 15% è
    // lo stesso che usano le altre nostre liste per dire «questa».
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -Theme.Effects.space2
        anchors.rightMargin: -Theme.Effects.space2
        radius: Theme.Effects.radiusSM
        color: riga.scelta
               ? (dito.containsMouse ? Qt.alpha(Theme.Colors.accent, 0.22)
                                     : Theme.Colors.selected)
               : (dito.containsMouse ? Theme.Colors.hover : "transparent")
        Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
    }

    MouseArea {
        id: dito
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Tutta la riga commuta la spunta, non solo il quadratino: un
        // bersaglio da venti pixel in un elenco di ventotto voci è un elenco
        // che si usa male.
        onClicked: riga.commutata()
    }

    Rectangle {
        id: tacca
        visible: riga.capofamiglia
        anchors.left: parent.left
        anchors.leftMargin: Theme.Effects.space3 + 20 + Theme.Effects.space3
        anchors.top: parent.top
        anchors.topMargin: Theme.Effects.space3
        width: 3
        height: 26
        radius: 2
        color: riga.colore
    }

    Spunta {
        id: casella
        anchors.left: parent.left
        anchors.leftMargin: Theme.Effects.space3
        anchors.top: parent.top
        anchors.topMargin: Theme.Effects.space3 + 2
        stato: riga.scelta ? 1 : 0
        onPremuta: riga.commutata()
    }

    Text {
        id: numero
        anchors.right: parent.right
        anchors.rightMargin: Theme.Effects.space3
        anchors.top: parent.top
        anchors.topMargin: Theme.Effects.space3
        // «almeno» e non un numero secco quando `du` non ha potuto leggere
        // tutto: chi legge «6,93 GB» crede che siano tutti, e non ha modo di
        // sospettare che ce ne siano di più.
        text: (riga.voce.parziale === true ? "almeno " : "")
              + Misure.peso(riga.voce.byte)
        color: riga.scelta ? Theme.Colors.text : Theme.Colors.textMuted
        font.family: Theme.Typography.fontDisplay
        font.pixelSize: Theme.Typography.sizeMD
        font.weight: Theme.Typography.weightSemiBold
        // Le cifre in colonna vogliono la stessa larghezza, o l'elenco balla.
        font.features: ({ "tnum": 1 })
    }

    Column {
        id: colonna
        anchors.left: riga.capofamiglia ? tacca.right : casella.right
        anchors.leftMargin: Theme.Effects.space3
        anchors.right: numero.left
        anchors.rightMargin: Theme.Effects.space4
        anchors.top: parent.top
        anchors.topMargin: Theme.Effects.space3
        spacing: 3

        Row {
            spacing: Theme.Effects.space2

            Text {
                text: riga.voce.nome || ""
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: riga.capofamiglia ? Theme.Typography.sizeLG
                                                  : Theme.Typography.sizeMD
                font.weight: riga.capofamiglia
                             ? Theme.Typography.weightSemiBold
                             : Theme.Typography.weightMedium
            }

            Cartellino {
                visible: riga.voce.vuoleLaPassword === true
                testo: "password"
                tinta: Theme.Colors.warning
            }

            // ── I due casi che NON sono quello normale ────────────────
            //
            // «Si rifà da sola» non ha cartellino: è quasi tutto, e
            // un'etichetta su ogni riga è un'etichetta che non si legge.
            // Restano i due che cambiano una decisione, e sono opposti fra
            // loro — uno dice «poi non c'è più», l'altro «tanto ritorna».
            Cartellino {
                visible: riga.voce.torna === "mai"
                testo: "non torna"
                tinta: Theme.Colors.danger
            }

            Cartellino {
                visible: riga.voce.torna === "sempre"
                testo: "torna da sé"
                tinta: Theme.Colors.warning
            }

            Text {
                visible: (Number(riga.voce.quante) || 0) > 0
                text: (Number(riga.voce.quante) || 0) + " file"
                color: Theme.Colors.textFaint
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeXS
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // La spiegazione della famiglia, e SOLO se non c'è un avvertimento
        // suo: sono due frasi sullo stesso argomento, e messe una sopra
        // l'altra dicono due volte la stessa cosa. Si è visto in una
        // fotografia col cestino — «Quello che c'è dentro l'hai buttato tu»
        // scritto due volte a due righe di distanza.
        Text {
            visible: riga.capofamiglia && riga.spiegazione !== ""
                     && !riga.haNota
            width: parent.width
            text: riga.spiegazione
            color: Theme.Colors.textFaint
            wrapMode: Text.WordWrap
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
        }

        Text {
            width: parent.width
            text: riga.voce.dove || ""
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontMono
            font.pixelSize: Theme.Typography.sizeXS
            elide: Text.ElideMiddle
        }

        // ── La barretta ─────────────────────────────────────────────────
        //
        // Si anima la LARGHEZZA e non la posizione, ed è l'eccezione: qui
        // l'oggetto è alto quattro pixel e largo qualche centinaio, cioè
        // l'area che il processore ridisegna è minuscola. La regola («anima
        // la posizione, non la dimensione») vale per le superfici grandi.
        Item {
            width: parent.width
            height: 4

            Rectangle {
                anchors.fill: parent
                radius: 2
                color: Theme.Colors.sunken
            }

            Rectangle {
                height: parent.height
                radius: 2
                width: Math.max(2, parent.width
                                   * Math.min(1, (Number(riga.voce.byte) || 0)
                                                 / Math.max(1, riga.massimo)))
                color: riga.scelta ? riga.colore : Qt.alpha(riga.colore, 0.35)
                Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }
            }
        }

        Text {
            visible: riga.haNota
            width: parent.width
            text: riga.voce.avvertenza || ""
            color: Theme.Colors.textFaint
            wrapMode: Text.WordWrap
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
            font.italic: true
        }
    }

    // Un cartellino piccolo, per le due cose che cambiano una decisione.
    // Sono due e restano due: tre etichette su ogni riga sono zero etichette.
    component Cartellino: Rectangle {
        property string testo: ""
        property color tinta: Theme.Colors.textFaint

        anchors.verticalCenter: parent === null ? undefined : parent.verticalCenter
        implicitWidth: dentro.implicitWidth + Theme.Effects.space2
        implicitHeight: dentro.implicitHeight + 3
        radius: Theme.Effects.radiusFull
        color: Qt.alpha(tinta, 0.16)

        Text {
            id: dentro
            anchors.centerIn: parent
            text: parent.testo
            color: parent.tinta
            font.family: Theme.Typography.fontDisplay
            font.pixelSize: Theme.Typography.sizeXS
            font.weight: Theme.Typography.weightMedium
        }
    }
}

import QtQuick
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui
import "../widget" as W

// WidgetBarra — Gli stessi valori della scrivania, nella barra.
//
// ── Perché sulla barra, se ci sono già sulla scrivania ─────────────────────
//
// Giacomo, 9 settembre 2026: «dei widget sia sulla barra […] e vorrei avere
// dei widget sul desktop».
//
// Sono due posti per due momenti. Sulla scrivania si guardano quando la
// scrivania si vede — cioè quando non stai lavorando. Sulla barra si vedono
// **mentre** lavori, che è l'unico momento in cui sapere che il processore è
// al novanta per cento cambia qualcosa.
//
// ── E costano quanto quelli della scrivania: zero ──────────────────────────
//
// La sorgente è la stessa, `core/Macchina.qml`, con lo stesso conteggio di
// chi guarda. Metterne tre sulla barra non aggiunge nessuna lettura: il
// demone legge quattro file ogni cinque secondi, e li legge lo stesso se a
// guardare è uno o sono dieci.
//
// L'unica differenza vera, e va detta perché è un costo: la barra c'è
// **sempre**. Un widget sulla scrivania si spegne quando una finestra la
// copre; qui no. Chi ne mette uno accende quelle quattro letture per tutta la
// sessione — ed è scritto nella riga che li sceglie, nelle Impostazioni.
Row {
    id: fila

    /// Chi ospita: serve per aprire il Monitor col clic.
    property var spine: null

    /// Quali, e in che ordine. Nomi di tipo, gli stessi della scrivania.
    readonly property var quali: Core.Ipc.get("bar.widgets", [])

    /// Non si guarda mentre la barra non si vede — a schermo intero la barra
    /// se ne va, e con lei la ragione di tenere sveglio il demone.
    readonly property bool serveIlDato:
        fila.quali.length > 0 && fila.visible && !Core.Gioco.aSchermoIntero

    visible: fila.quali.length > 0
    spacing: Theme.Effects.space1

    onServeIlDatoChanged: {
        if (fila.serveIlDato)
            Core.Macchina.guarda();
        else
            Core.Macchina.nonGuardo();
    }
    Component.onCompleted: if (fila.serveIlDato) Core.Macchina.guarda()
    Component.onDestruction: if (fila.serveIlDato) Core.Macchina.nonGuardo()

    Repeater {
        model: fila.quali

        delegate: Ui.SpineButton {
            id: pillola
            required property var modelData

            readonly property string tipo: String(pillola.modelData)

            anchors.verticalCenter: parent.verticalCenter
            horizontalPadding: Theme.Effects.space2

            // Il nome per esteso e la seconda riga: sulla barra non ci
            // stanno, e sono esattamente quello che serve quando ti fermi a
            // guardare perché il numero ti ha insospettito.
            tooltip: conti.nome
                     + (conti.sotto !== "" ? " · " + conti.sotto : "")

            // ── Il clic porta dove si può fare qualcosa ─────────────────
            //
            // Un numero che dice «memoria al 94 %» e non porta da nessuna
            // parte è un allarme senza maniglia. Il Monitor è il posto in cui
            // si scopre CHI se la sta prendendo, ed è già nostro.
            onClicked: if (fila.spine) fila.spine.monitorRequested()

            // I conti li fa lo stesso pezzo della scrivania. Due tabelle dei
            // valori sarebbero due verità, e la barra e la scrivania sono
            // proprio i due posti in cui la differenza si vedrebbe.
            W.Contenuto {
                id: conti
                tipo: pillola.tipo
                visible: false
            }

            content: Row {
                spacing: Theme.Effects.space1

                // Il simbolo, PRIMA del numero: è la risposta a «di cosa?»,
                // e senza, tre numeri in fila — «6 % · 21 % · 49°» — erano
                // un indovinello. Smorzato come le altre icone della barra,
                // e acceso quando il valore è al limite, insieme al numero.
                Ui.Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16
                    name: conti.icona
                    // Sempre il nostro tracciato, anche col set classico:
                    // sulla barra sono SEGNI accanto a un numero, e un chip
                    // verde di un tema di sistema in mezzo a quattro glifi
                    // monocromi sembrava un'icona finita lì per sbaglio.
                    alwaysDrawn: true
                    color: conti.quota >= 0.92 ? Theme.Colors.danger
                                               : Theme.Colors.textMuted
                }

                // La storia, minuscola. Quattro minuti in ventotto pixel: non
                // si legge un valore, si vede una FORMA — se sale, se è un
                // picco, se è così da un pezzo. È tutto quello che serve di
                // sfuggita.
                W.Grafico {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Core.Macchina.haStoria(pillola.tipo)
                    width: 28
                    height: 14
                    quale: pillola.tipo
                    tinta: conti.tinta
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: conti.valore
                    color: conti.quota >= 0.92 ? Theme.Colors.danger
                                               : Theme.Colors.text
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeSM
                }
            }

            Accessible.role: Accessible.StaticText
            Accessible.name: conti.nome
            Accessible.description: conti.valore
        }
    }
}

import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import ".." as S

// Lingua — La lingua di Minerva e quella del sistema.
//
// Sono DUE, e tenerle in due riquadri distinti non è pignoleria: si comportano
// in modo diverso e chi le confonde crede che una delle due sia rotta.
//
//   · quella di Minerva cambia sotto le dita, all'istante, e non chiede
//     niente a nessuno: `general.language` è una proprietà a cui tutta
//     l'interfaccia è legata (vedi `core/Strings.qml`);
//   · quella del sistema vale per Firefox, per il terminale, per i menu dei
//     programmi che non sono nostri. Passa da polkit e si vede al PROSSIMO
//     ACCESSO. Non esiste modo di applicarla subito, quindi lo si scrive:
//     senza, si cambia lingua, non cambia niente, e sembra un guasto.
//
// L'impostazione della prima esisteva da sempre, con un valore di fabbrica e
// nessuna pagina che la mostrasse: si poteva cambiare solo scrivendo a mano
// nel file di configurazione del demone.
Page {
    id: page

    readonly property bool it: Core.Strings.lang === "it"

    title: page.it ? "Lingua e regione" : "Language & region"
    subtitle: page.it ? "La lingua di Minerva e quella di tutto il computer"
                      : "Minerva's language and the whole computer's"

    property string localeSistema: ""
    property var disponibili: []
    property var campi: ({})
    property string esito: ""

    Connections {
        target: Core.Ipc

        function onLocaleStateReceived(s) {
            page.localeSistema = s.lang || "";
            page.disponibili = s.disponibili || [];
            page.campi = s.campi || ({});
        }

        function onLocaleResult(r) {
            page.esito = r.ok === true
                         ? (page.it
                            ? "Fatto. La nuova lingua si vede al prossimo accesso."
                            : "Done. The new language appears at your next login.")
                         : (r.errore || (page.it ? "Non riuscito." : "Failed."));
            svanisci.restart();
        }

        function onConnectedChanged() { if (Core.Ipc.connected) Core.Ipc.localeState(); }
    }

    Timer { id: svanisci; interval: 8000; onTriggered: page.esito = "" }

    Component.onCompleted: Core.Ipc.localeState()

    /// Il nome di una lingua scritto NELLA LINGUA STESSA.
    ///
    /// «Italiano», non «Italian»: chi ha sbagliato lingua e vuole tornare
    /// indietro deve poter riconoscere la propria in un elenco che non sa
    /// leggere. È la ragione per cui lo fanno così tutti i sistemi operativi.
    function nomeLocale(l) {
        var noti = {
            "it_IT.UTF-8": "Italiano (Italia)",
            "en_US.UTF-8": "English (United States)",
            "en_GB.UTF-8": "English (United Kingdom)",
            "de_DE.UTF-8": "Deutsch (Deutschland)",
            "fr_FR.UTF-8": "Français (France)",
            "es_ES.UTF-8": "Español (España)",
            "pt_BR.UTF-8": "Português (Brasil)",
            "C.UTF-8": page.it ? "Nessuna (inglese di base)" : "None (plain English)"
        };
        return noti[l] !== undefined ? noti[l] : l;
    }

    // ── Esito, in cima ───────────────────────────────────────────────────

    Card {
        visible: page.esito !== ""
        heading: page.it ? "Esito" : "Result"

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: page.esito
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    // ── La lingua di Minerva ─────────────────────────────────────────────

    Card {
        heading: page.it ? "Lingua di Minerva" : "Minerva's language"
        note: page.it
              ? "Cambia subito, mentre guardi: riguarda solo le finestre di "
              + "Minerva — la barra, le Impostazioni, il gestore file."
              : "Changes immediately, as you watch: it only affects Minerva's "
              + "own windows — the bar, Settings, the file manager."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Lingua dell'interfaccia" : "Interface language"
            description: page.it
                         ? "«Come il sistema» segue la lingua scelta qui sotto"
                         : "«Follow the system» uses the language chosen below"
            controlWidth: 320

            control: S.ChoicePicker {
                value: Core.Ipc.get("general.language", "auto")
                options: [
                    { "value": "auto", "label": page.it ? "Come il sistema"
                                                        : "Follow the system" },
                    { "value": "it",   "label": "Italiano" },
                    { "value": "en",   "label": "English" }
                ]
                onPicked: function(v) { Core.Ipc.setSetting("general.language", v); }
            }
        }
    }

    // ── La lingua del sistema ────────────────────────────────────────────

    Card {
        heading: page.it ? "Lingua del sistema" : "System language"
        note: page.it
              ? "Vale per tutti i programmi, non solo per Minerva, e si vede "
              + "al prossimo accesso. Compaiono solo le lingue installate: "
              + "aggiungerne una vuol dire generarla sul computer."
              : "Applies to every program, not just Minerva, and takes effect "
              + "at your next login. Only installed languages are listed: "
              + "adding one means generating it on this computer."

        Repeater {
            model: page.disponibili

            delegate: Rectangle {
                id: riga
                required property string modelData

                width: parent.width
                height: 44
                radius: Theme.Effects.radiusSM
                color: riga.modelData === page.localeSistema
                       ? Qt.alpha(Theme.Colors.accent, 0.16)
                       : rigaMouse.containsMouse ? Theme.Colors.hover
                                                 : "transparent"

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.Effects.space3
                    text: page.nomeLocale(riga.modelData)
                    color: riga.modelData === page.localeSistema
                           ? Theme.Colors.accent : Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.weight: Theme.Typography.weightRegular
                    font.pixelSize: Theme.Typography.sizeSM
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.Effects.space3
                    text: riga.modelData
                    color: Theme.Colors.textFaint
                    font.family: Theme.Typography.fontMono
                    font.pixelSize: Theme.Typography.sizeXS
                }

                MouseArea {
                    id: rigaMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: riga.modelData !== page.localeSistema
                    onClicked: Core.Ipc.localeSet(riga.modelData)
                }
            }
        }

        Text {
            width: parent.width
            visible: page.disponibili.length === 0
            wrapMode: Text.WordWrap
            text: page.it
                  ? "Nessuna lingua installata risulta disponibile: forse "
                  + "«localectl» non c'è su questo sistema."
                  : "No installed language is available: «localectl» may be "
                  + "missing on this system."
            color: Theme.Colors.textFaint
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeSM
        }
    }

    // ── Che cosa segue la lingua ─────────────────────────────────────────
    //
    // Non è decorazione. Cambiare la lingua del sistema riscrive DIECI righe
    // in `/etc/locale.conf`, non una: le `LC_*` hanno la precedenza su `LANG`,
    // e finché restano inchiodate alla lingua vecchia il cambio non si vede.
    // Mostrarle qui è il modo di far vedere che cosa si sta per toccare.

    Card {
        visible: Object.keys(page.campi).length > 1
        heading: page.it ? "Che cosa segue la lingua" : "What follows the language"
        note: page.it
              ? "Numeri, date, valuta e unità di misura. Cambiando lingua "
              + "vengono aggiornati tutti insieme."
              : "Numbers, dates, currency and units. Changing the language "
              + "updates them all together."

        Column {
            width: parent.width
            spacing: 4

            Repeater {
                model: Object.keys(page.campi).sort()

                delegate: Row {
                    required property string modelData
                    width: parent.width
                    spacing: Theme.Effects.space2

                    Text {
                        width: 190
                        text: modelData
                        color: Theme.Colors.textFaint
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: Theme.Typography.sizeXS
                    }

                    Text {
                        text: page.campi[modelData]
                        color: Theme.Colors.textMuted
                        font.family: Theme.Typography.fontMono
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }
            }
        }
    }
}

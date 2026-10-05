import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import ".." as S

// Accessibilità — Vedere e usare Minerva quando serve una mano.
//
// Qui non c'era niente, ed era la lacuna più grave delle Impostazioni: un
// ambiente pensato per chi comincia che non offre un modo di ingrandire il
// testo esclude proprio le persone che ha detto di voler accogliere.
//
// Le tre cose di questa pagina hanno una proprietà in comune che vale la pena
// dire: **il compositore e la tipografia le dimenticano a ogni avvio**. Vivono
// quindi nelle impostazioni del demone, e la shell le riapplica appena il
// demone risponde (`applicaLente`, `applicaCursore` in `shell.qml`). Senza,
// chi ne ha bisogno le ritroverebbe spente ogni mattina — cioè esattamente
// chi non può rimetterle a posto da solo.
Page {
    id: page

    readonly property bool it: Core.Strings.lang === "it"

    title: page.it ? "Accessibilità" : "Accessibility"
    subtitle: page.it ? "Testo più grande, lente d'ingrandimento, puntatore"
                      : "Larger text, screen magnifier, pointer"

    readonly property real testo: Core.Ipc.get("accessibility.textScale", 1.0)
    readonly property real lente: Core.Ipc.get("accessibility.zoom", 1.0)
    // La misura del puntatore sta in `settings/MisuraPuntatore.qml`, insieme
    // al suo pezzo delicato — il nome del tema, che se sbagliato fa sparire
    // il puntatore. Da qui e da «Tastiera e mouse» si usa lo stesso pezzo:
    // due copie che divergono sono due copie di cui una mente.

    // ── Dimensione del testo ─────────────────────────────────────────────

    Card {
        heading: page.it ? "Dimensione del testo" : "Text size"
        note: page.it
              ? "Vale per tutte le finestre di Minerva e cambia mentre guardi. "
              + "Oltre il 130% le scritte comincerebbero a toccare i bordi dei "
              + "riquadri, quindi il massimo si ferma lì."
              : "Applies to every Minerva window and changes as you watch. "
              + "Beyond 130% the text would start touching the edges of the "
              + "boxes, so that is where the maximum stops."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Grandezza delle scritte" : "Text size"
            description: page.it ? "Titoli, etichette e testo di ogni finestra"
                                 : "Titles, labels and body text everywhere"
            controlWidth: 320

            control: S.ChoicePicker {
                value: String(page.testo)
                options: [
                    { "value": "1",    "label": page.it ? "Normale" : "Normal" },
                    { "value": "1.15", "label": "115%" },
                    { "value": "1.3",  "label": "130%" }
                ]
                onPicked: function(v) {
                    Core.Ipc.setSetting("accessibility.textScale", parseFloat(v));
                }
            }
        }

        // Il campione cresce insieme alla scelta: si vede l'effetto senza
        // doverlo immaginare, e senza dover chiudere le Impostazioni per
        // andare a guardare un'altra finestra.
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: page.it ? "Così si legge il testo di Minerva."
                          : "This is how Minerva's text reads."
            color: Theme.Colors.textMuted
            font.family: Theme.Typography.fontDisplay
            font.weight: Theme.Typography.weightRegular
            font.pixelSize: Theme.Typography.sizeMD
        }
    }

    // ── Lente d'ingrandimento ────────────────────────────────────────────

    Card {
        heading: page.it ? "Lente d'ingrandimento" : "Screen magnifier"
        note: page.it
              ? "Ingrandisce tutto lo schermo attorno al puntatore, comprese "
              + "le finestre dei programmi che non sono di Minerva. "
              + "Scorciatoie: Super + «+» per ingrandire, Super + «−» per "
              + "ridurre, Super + Maiusc + «−» per toglierla."
              : "Magnifies the whole screen around the pointer, including "
              + "windows of programs that are not Minerva's. Shortcuts: "
              + "Super + «+» to zoom in, Super + «−» to zoom out, "
              + "Super + Shift + «−» to switch it off."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Ingrandimento" : "Magnification"
            description: page.lente <= 1.0
                         ? (page.it ? "Spenta: lo schermo è a grandezza vera"
                                    : "Off: the screen is at its true size")
                         : Math.round(page.lente * 100) + "%"
            controlWidth: 320

            control: S.ChoicePicker {
                value: page.lente <= 1.0 ? "1"
                     : page.lente < 1.75 ? "1.5"
                     : page.lente < 2.5  ? "2"
                                         : "3"
                options: [
                    { "value": "1",   "label": page.it ? "Spenta" : "Off" },
                    { "value": "1.5", "label": "150%" },
                    { "value": "2",   "label": "200%" },
                    { "value": "3",   "label": "300%" }
                ]
                onPicked: function(v) {
                    Core.Ipc.setSetting("accessibility.zoom", parseFloat(v));
                    // Applicata da qui e non solo dalla shell: il pannello può
                    // essere aperto senza che nessuno prema una scorciatoia, e
                    // una levetta che si muove senza che lo schermo cambi
                    // sembra rotta.
                    Core.Compositore.ingrandimentoPuntatore(v);
                }
            }
        }
    }

    // ── Puntatore ────────────────────────────────────────────────────────

    Card {
        heading: page.it ? "Puntatore del mouse" : "Mouse pointer"
        note: page.it
              ? "Il disegno del puntatore resta quello scelto per il resto del "
              + "computer: qui si cambia solo quanto è grande."
              : "The pointer's design stays the one chosen for the rest of the "
              + "computer: only its size changes here."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Dimensione del puntatore" : "Pointer size"
            description: page.it ? "Utile su schermi grandi o molto fitti"
                                 : "Useful on large or very dense screens"
            controlWidth: 320

            control: S.MisuraPuntatore {}
        }
    }

    // ── Animazioni ───────────────────────────────────────────────────────
    //
    // Non è un doppione del pannello di controllo: là è una comodità fra le
    // altre, qui è il posto dove la cerca chi ha bisogno di spegnerla — il
    // movimento sullo schermo dà fastidio a chi soffre di vertigini, ed è una
    // delle voci che ogni sistema mette proprio in questa pagina.

    Card {
        heading: page.it ? "Movimento" : "Motion"
        note: page.it
              ? "Le finestre compaiono e si spostano senza animazione. "
              + "Utile a chi il movimento sullo schermo disturba."
              : "Windows appear and move without animation. Useful if motion "
              + "on screen is uncomfortable."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Animazioni delle finestre" : "Window animations"
            description: page.it ? "Spegnendole tutto compare all'istante"
                                 : "With these off everything appears instantly"

            control: S.ToggleSwitch {
                checked: Core.Ipc.get("desktop.animations", true)
                onToggled: function(v) {
                    Core.Ipc.setSetting("desktop.animations", v);
                }
            }
        }
    }
}

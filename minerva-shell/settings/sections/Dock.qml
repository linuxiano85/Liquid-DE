import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import ".." as S

// Dock — La fila di icone in fondo allo schermo.
//
// ── Perché una sezione sua ────────────────────────────────────────────────
//
// Perché queste voci esistevano già — tutte e sette — e stavano dentro
// «Aspetto», che è una pagina da milleseicento righe. Giacomo, il 2 settembre
// 2026, dopo settimane d'uso: «la dock ancora non si nasconde da sola e non ci
// sono impostazioni per essa».
//
// Le impostazioni c'erano, e nel suo file `dock.autoHide` era `false`: la dock
// non si nascondeva perché era spenta, non perché fosse rotta. Ma un'opzione
// che non si trova è un'opzione che non esiste, e sostenere il contrario vuol
// dire dare la colpa a chi guarda.
//
// La dock è il pezzo di Minerva che si tocca di più dopo la barra. Merita di
// stare nell'elenco di sinistra col suo nome.
Page {
    id: page

    title: Core.Strings.lang === "it" ? "Dock e barra" : "Dock & bar"
    subtitle: Core.Strings.lang === "it"
              ? "Dove stanno, cosa mostrano, quanto sono grandi e quando si tolgono di mezzo"
              : "Where they sit, what they show, how big they are and when they step aside"

    readonly property bool it: Core.Strings.lang === "it"

    /// Il modo in vigore, leggendo anche il valore vecchio.
    ///
    /// Chi aveva già Minerva installata ha `dock.autoHide` e non ha mai
    /// sentito parlare di `dock.modo`: leggendo solo la chiave nuova, la sua
    /// dock cambierebbe comportamento da sola al primo avvio. Lo stesso conto
    /// sta in `shell.qml`, ed è l'unico posto in cui è ripetuto — qui serve a
    /// mostrare la voce giusta come già selezionata.
    readonly property string modo: {
        var m = String(Core.Ipc.get("dock.modo", ""));
        if (m === "sempre" || m === "nascondi" || m === "elude")
            return m;
        return Core.Ipc.get("dock.autoHide", false) ? "nascondi" : "sempre";
    }

    // ── Dove stanno ──────────────────────────────────────────────────────
    //
    // `bar.position` esisteva dal primo giorno, valeva `'top'`, si poteva
    // scrivere — e non la leggeva nessuno. Una impostazione che si può
    // cambiare e non fa niente è peggio di una che manca: chi la cambia
    // conclude che la scrivania è rotta, e ha ragione.
    //
    // I lati non ci sono, e non per dimenticanza: barra e dock sono costruite
    // in orizzontale — la lingua dei pannelli scende, le icone crescono verso
    // l'interno — e metterle di fianco non è un ancoraggio diverso, è
    // un'altra geometria. Prometterlo qui con una voce che poi fa una cosa
    // storta sarebbe lo stesso difetto di prima.
    Card {
        heading: page.it ? "Dove stanno" : "Where they sit"

        // ── Non si può più metterle una sull'altra ───────────────────────
        //
        // Qui c'era un avviso: «mettere le due cose dalla stessa parte è
        // permesso — con due schermi può perfino servire — ma chi lo fa deve
        // saperlo». Giacomo ha deciso il contrario, e il ragionamento non
        // reggeva comunque: chi ha due schermi ha una barra sola e una dock
        // sola, e sovrapporle non serve a nessuno.
        //
        // Adesso spostarne una **sposta l'altra**, e il riquadro lo dice
        // prima. La regola vera non è qui, è in `core/Posizioni.qml`: questo
        // file scrive le due chiavi in coppia perché il movimento si VEDA,
        // ma anche scrivendo `settings.json` a mano non si torna indietro.
        note: page.it
              ? "Stanno sempre su bordi opposti: spostandone una, l'altra la segue."
              : "They always sit on opposite edges: move one and the other follows."

        S.SettingRow {
            width: parent.width
            label: page.it ? "La barra" : "The bar"
            description: page.it
                ? "L'orologio, la rete, il volume, e i pannelli che ne scendono"
                : "The clock, network, volume, and the panels that drop from it"
            controlWidth: 260
            control: S.ChoicePicker {
                value: Core.Posizioni.barraInBasso ? "basso" : "alto"
                options: [
                    { "value": "alto",  "label": page.it ? "In alto" : "Top" },
                    { "value": "basso", "label": page.it ? "In basso" : "Bottom" }
                ]
                onPicked: function(v) {
                    // In coppia, e in un messaggio solo: due `setSetting` di
                    // fila sarebbero due scritture su disco e due
                    // ricostruzioni del tema, con un istante in cui la
                    // scrivania è mezza in un modo e mezza nell'altro.
                    if (Core.Ipc.get("dock.enabled", true))
                        Core.Ipc.setSettings({
                            "bar.position": v,
                            "dock.position": v === "alto" ? "basso" : "alto"
                        });
                    else
                        Core.Ipc.setSetting("bar.position", v);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("dock.enabled", true)
            label: page.it ? "La dock" : "The dock"
            description: page.it
                ? "Le icone crescono verso l'interno dello schermo, da qualunque parte stia"
                : "Icons grow towards the middle of the screen, whichever side it is on"
            controlWidth: 260
            control: S.ChoicePicker {
                value: Core.Posizioni.dockInAlto ? "alto" : "basso"
                options: [
                    { "value": "basso", "label": page.it ? "In basso" : "Bottom" },
                    { "value": "alto",  "label": page.it ? "In alto" : "Top" }
                ]
                onPicked: function(v) {
                    Core.Ipc.setSettings({
                        "dock.position": v,
                        "bar.position": v === "alto" ? "basso" : "alto"
                    });
                }
            }
        }
    }

    Card {
        heading: page.it ? "Come sta sullo schermo" : "How it sits on screen"

        S.SettingRow {
            width: parent.width
            label: page.it ? "Mostra la dock" : "Show the dock"
            description: page.it
                ? "La fila di icone in basso: cosa sta girando e cosa si apre spesso"
                : "The row of icons at the bottom: what is running and what you open often"
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("dock.enabled", true)
                onToggled: function(v) { Core.Ipc.setSetting("dock.enabled", v); }
            }
        }

        // ── I tre modi ───────────────────────────────────────────────────
        //
        // Non una levetta «si nasconde sì/no»: sono tre situazioni diverse, e
        // la terza — quella che Giacomo ha chiesto — non si può dire con un
        // sì e un no.
        S.SettingRow {
            width: parent.width
            visible: Core.Ipc.get("dock.enabled", true)
            label: page.it ? "Quando si toglie di mezzo" : "When it steps aside"
            description: page.it
                ? "«Elude le finestre» è il modo di tutti i giorni: la dock c'è quando lo schermo è libero, e si ritira quando una finestra arriva sopra di lei"
                : "“Dodge windows” is the everyday choice: the dock is there when the screen is free, and steps back when a window reaches it"
            // ── Trecento non bastavano ───────────────────────────────
            //
            // Con tre voci e questi nomi, a `controlWidth: 300` la terza
            // usciva dal bordo: sullo schermo si leggeva «Si nascon…».
            // Visto guardando la fotografia, non leggendo il codice — ed è
            // esattamente il tipo di difetto per cui questo piano ha la
            // regola di guardare.
            //
            // Il numero è la larghezza che serve alle tre voci più lunghe in
            // italiano; l'inglese è più corto e ci sta comodo.
            controlWidth: 400

            control: S.ChoicePicker {
                value: page.modo
                options: [
                    { "value": "sempre",
                      "label": page.it ? "Sempre" : "Always" },
                    { "value": "elude",
                      "label": page.it ? "Elude le finestre" : "Dodge windows" },
                    { "value": "nascondi",
                      "label": page.it ? "Si nasconde" : "Hide" }
                ]
                onPicked: function(v) {
                    Core.Ipc.setSetting("dock.modo", v);
                    // Si tiene allineato anche il valore vecchio: se un giorno
                    // si torna indietro con una versione di prima, la dock si
                    // comporta come ci si aspetta invece di dimenticarsene.
                    Core.Ipc.setSetting("dock.autoHide", v === "nascondi");
                }
            }
        }
    }

    // ── La barra ─────────────────────────────────────────────────────────
    //
    // `bar.showAppMenuButton` stava nei valori di fabbrica dal primo giorno e
    // per mesi la sua UNICA occorrenza in tutto il progetto era la riga che la
    // dichiarava. È stata collegata al pulsante il 4 settembre 2026, e da
    // allora funziona — ma restava senza un posto da cui toccarla, che è
    // mezza correzione.
    Card {
        heading: page.it ? "La barra" : "The bar"

        S.SettingRow {
            width: parent.width
            label: page.it ? "Il pulsante del menu applicazioni"
                           : "The application-menu button"
            description: page.it
                ? "Il rombo di Minerva in alto a sinistra. Il menu si apre "
                  + "comunque con Super."
                : "Minerva's mark at the top left. The menu still opens with Super."
            controlWidth: 60
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("bar.showAppMenuButton", true)
                onToggled: function(v) {
                    Core.Ipc.setSetting("bar.showAppMenuButton", v);
                }
            }
        }
        }
    }

    Card {
        heading: page.it ? "Aspetto" : "Look"
        visible: Core.Ipc.get("dock.enabled", true)

        S.SettingRow {
            width: parent.width
            label: page.it ? "Dimensione delle icone" : "Icon size"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 32
                to: 72
                unit: "pixel"
                value: Core.Ipc.get("dock.iconSize", 48)
                onReleased: function(v) {
                    Core.Ipc.setSetting("dock.iconSize", Math.round(v));
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Ingrandimento al passaggio" : "Magnification"
            description: page.it
                ? "Quanto cresce l'icona sotto il puntatore. Tutto a sinistra: spento"
                : "How much the icon under the pointer grows. Fully left: off"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                // Uno esatto vuol dire «non crescere»: il cursore ha lo
                // spegnimento dentro di sé invece di in un interruttore a parte.
                from: 1.0
                to: 2.0
                value: Core.Ipc.get("dock.magnification", 1.6)
                onReleased: function(v) {
                    Core.Ipc.setSetting("dock.magnification",
                                        Math.round(v * 20) / 20);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Estensione dell'ingrandimento" : "Magnification reach"
            description: page.it
                ? "Quante icone attorno a quella puntata si sollevano con lei"
                : "How many icons around the pointed one rise with it"
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 1.0
                to: 4.0
                unit: "numero"
                value: Core.Ipc.get("dock.reach", 2.2)
                onReleased: function(v) {
                    Core.Ipc.setSetting("dock.reach", Math.round(v * 10) / 10);
                }
            }
        }

        // Un cursore, due memorie: col blur vero del compositore dietro, la
        // dock si può aprire molto di più. Vedi la stessa riga in
        // `sections/Appearance.qml`, dove c'è il perché per esteso.
        S.SettingRow {
            width: parent.width
            label: page.it ? "Trasparenza della dock" : "Dock transparency"
            description: Core.Vetro.filtroChiesto
                ? (page.it
                   ? "Con l'acquerello o il blur dietro si può scendere molto di più"
                   : "With watercolour or blur behind you can go much lower")
                : ""
            controlWidth: 220
            control: S.ValueSlider {
                width: 220
                from: 0.4
                to: 1.0
                value: Core.Vetro.filtroChiesto
                       ? Core.Ipc.get("dock.opacityBlur", 0.68)
                       : Core.Ipc.get("dock.opacity", 0.90)
                onReleased: function(v) {
                    Core.Ipc.setSetting(Core.Vetro.filtroChiesto
                                        ? "dock.opacityBlur" : "dock.opacity",
                                        Math.round(v * 100) / 100);
                }
            }
        }

        S.SettingRow {
            width: parent.width
            label: page.it ? "Nome al passaggio" : "Name on hover"
            description: page.it
                ? "L'etichetta col nome del programma sopra l'icona puntata"
                : "The label with the program name above the pointed icon"
            control: S.ToggleSwitch {
                checked: Core.Ipc.get("dock.showLabels", true)
                onToggled: function(v) {
                    Core.Ipc.setSetting("dock.showLabels", v);
                }
            }
        }
    }
}

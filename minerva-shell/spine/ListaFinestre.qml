import QtQuick
import "../theme" as Theme
import "../core" as Core
import "../ui" as Ui

// ListaFinestre — Le finestre aperte, in fila nella barra.
//
// ── A che cosa serve ─────────────────────────────────────────────────────
//
// Giacomo, 4 settembre 2026: «posso avere la barra come windows con le app
// aperte e meteo e tutto simile a windows eccetera». È il pezzo che manca allo
// stile «Windows»: senza dock, le finestre aperte devono stare da qualche
// parte, e quella parte è la barra.
//
// Nella barra c'era solo `WindowChip`, che mostra la finestra **attiva** — una
// sola — e i suoi tre pulsanti. Utile con la dock accesa, insufficiente senza.
//
// ── Una voce per FINESTRA, non per applicazione ──────────────────────────
//
// È la differenza con la dock, ed è voluta. La dock ragiona per applicazioni:
// tre finestre di Chrome sono un'icona con un contatore, perché la dock serve
// ad AVVIARE. Questa serve a TORNARE, e per tornare bisogna scegliere: quindi
// una voce per finestra, col suo titolo, che è l'unica cosa che le distingue.
//
// È anche quello che fa la barra di Windows, e chi sceglie quello stile lo
// sceglie perché lo conosce.
Row {
    id: lista

    /// Larghezza massima che può occupare: oltre, le voci si stringono.
    property real spazio: 600

    // ── L'ordine NON è quello di sovrapposizione ─────────────────────────
    //
    // `Core.Windows.all` è ordinato per pila: la finestra davanti è la prima.
    // Prendendolo così com'è, ogni clic riordinava la fila — e il secondo clic
    // sullo stesso pulsante finiva su un'altra finestra.
    //
    // Misurato il 5 settembre 2026: primo clic su «Minerva · File», la porta
    // davanti; secondo clic nello stesso punto, e lì c'era ormai il terminale.
    //
    // È la stessa cosa che la dock si è scritta in testa al file: «la dock
    // deve stare ferma. Se le icone si spostano ogni volta che si apre un
    // programma, la memoria muscolare non si forma mai e ogni clic diventa
    // una ricerca».
    //
    // Quindi l'ordine è quello di COMPARSA: chi c'era resta dov'era, chi
    // arriva va in fondo, chi se ne va lascia il posto agli altri.
    property var _ordine: []

    /// Spenta (è di serie: la accende lo stile «Windows») non guarda le
    /// finestre per niente. `visible: false` da fuori non bastava: i legami
    /// qui sotto lavoravano lo stesso a ogni aggiornamento dell'elenco.
    property bool accesa: true

    readonly property var finestre: {
        if (!lista.accesa)
            return [];
        var tutte = Core.Windows.all || [];
        var perIndirizzo = ({});
        var i;
        for (i = 0; i < tutte.length; i++)
            perIndirizzo[tutte[i].address] = tutte[i];

        // Prima quelle che conoscevamo, nell'ordine di prima.
        var out = [];
        var visti = ({});
        for (i = 0; i < lista._ordine.length; i++) {
            var a = lista._ordine[i];
            if (perIndirizzo[a] !== undefined) {
                out.push(perIndirizzo[a]);
                visti[a] = true;
            }
        }
        // Poi le nuove, in fondo.
        for (i = 0; i < tutte.length; i++) {
            if (!visti[tutte[i].address])
                out.push(tutte[i]);
        }
        return out;
    }

    // L'ordine si aggiorna DOPO aver disegnato, non dentro il calcolo: un
    // legame che scrive la cosa da cui dipende è un anello, e in QML un anello
    // non è un errore — è un valore che smette di aggiornarsi quando gli pare.
    onFinestreChanged: {
        lista.sincronizza();
        Qt.callLater(function () {
            var nuovo = [];
            for (var i = 0; i < lista.finestre.length; i++)
                nuovo.push(lista.finestre[i].address);
            if (nuovo.join("|") !== lista._ordine.join("|"))
                lista._ordine = nuovo;
        });
    }

    // ── Le voci si aggiornano SUL POSTO ──────────────────────────────────
    //
    // Era `model: lista.finestre`: un array nuovo a ogni aggiornamento, e il
    // Repeater distruggeva e rifaceva tutte le voci — anche solo perché un
    // titolo era cambiato. Misurato il 29 settembre 2026 con un terminale
    // che cambia titolo cinque volte al secondo: 126 ricostruzioni in 25
    // secondi. È la stessa lezione della dock (`dock/Dock.qml`, «Il modello
    // del Repeater si aggiorna SUL POSTO»): le righe restano finché la
    // finestra esiste, cambia solo il valore.
    ListModel {
        id: modello
        dynamicRoles: true
    }

    /// Quante voci sono nate: per le prove.
    property int vociNate: 0

    function sincronizza() {
        var volute = lista.finestre;
        var i, j;
        for (i = modello.count - 1; i >= 0; i--) {
            var viva = false;
            for (j = 0; j < volute.length; j++)
                if (volute[j].address === modello.get(i).chiave) { viva = true; break; }
            if (!viva)
                modello.remove(i);
        }
        for (i = 0; i < volute.length; i++) {
            var w = volute[i];
            var dove = -1;
            for (j = i; j < modello.count; j++)
                if (modello.get(j).chiave === w.address) { dove = j; break; }
            if (dove === -1) {
                modello.insert(i, { "chiave": w.address, "w": w });
                continue;
            }
            if (dove !== i)
                modello.move(dove, i, 1);
            modello.setProperty(i, "w", w);
        }
    }

    spacing: Theme.Effects.space1
    visible: lista.accesa && lista.finestre.length > 0

    /// Quanto è larga una voce: si dividono lo spazio, con un minimo e un
    /// massimo. Il minimo è quello sotto cui resta solo l'icona — e allora
    /// tanto vale mostrare solo quella, invece di un titolo tagliato a due
    /// lettere che non dice niente.
    readonly property real larghezzaVoce: {
        var n = Math.max(1, lista.finestre.length);
        var q = (lista.spazio - lista.spacing * (n - 1)) / n;
        return Math.max(44, Math.min(200, q));
    }

    readonly property bool soloIcone: lista.larghezzaVoce < 90

    Repeater {
        id: voci
        model: modello

        delegate: Rectangle {
            id: voce
            required property var w
            // Il resto della voce parla di `modelData`, com'era quando il
            // modello era l'array: un nome solo, senza riscrivere tutto.
            readonly property var modelData: w
            Component.onCompleted: lista.vociNate++

            readonly property bool attiva:
                modelData.address === Core.Windows.activeAddress
            readonly property var app: Core.Apps.forWindow(modelData)

            width: lista.larghezzaVoce
            height: Theme.Effects.barButton
            radius: Theme.Effects.radiusSM

            color: voce.attiva ? Theme.Colors.selected
                 : presa.containsMouse ? Theme.Colors.hover
                                       : "transparent"
            // La finestra attiva porta un filo d'accento sotto: è il segno che
            // regge anche quando la selezione e il passaggio del mouse hanno
            // colori vicini.
            Behavior on color { ColorAnimation { duration: Theme.Motion.instant } }

            Rectangle {
                anchors { left: parent.left; right: parent.right
                          bottom: parent.bottom
                          leftMargin: Theme.Effects.space2
                          rightMargin: Theme.Effects.space2 }
                height: 2
                radius: 1
                color: Theme.Colors.accent
                visible: voce.attiva
            }

            // L'icona vera del programma se c'è, il nostro segno se non c'è.
            // Sono due strade diverse — un file PNG/SVG del tema contro un
            // tracciato nostro — e non si possono mettere nella stessa cosa:
            // vedi `ui/Icon.qml`, che disegna i NOSTRI nomi.
            Item {
                id: segno
                anchors.left: parent.left
                anchors.leftMargin: lista.soloIcone
                                    ? (voce.width - width) / 2
                                    : Theme.Effects.space2
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                // Una finestra ridotta si vede che è ridotta: mezza spenta,
                // come nella dock.
                opacity: voce.modelData.minimized ? 0.45 : 1

                Image {
                    id: iconaApp
                    anchors.fill: parent
                    source: (voce.app && voce.app.icon)
                            ? "file://" + voce.app.icon : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    cache: true
                    sourceSize.width: 36   // il doppio, per gli schermi scalati
                    visible: status === Image.Ready
                }

                Ui.Icon {
                    anchors.fill: parent
                    name: "window"
                    color: voce.attiva ? Theme.Colors.text
                                       : Theme.Colors.textMuted
                    visible: !iconaApp.visible
                }
            }

            Text {
                textFormat: Text.PlainText
                anchors { left: segno.right; leftMargin: Theme.Effects.space2
                          right: parent.right; rightMargin: Theme.Effects.space2
                          verticalCenter: parent.verticalCenter }
                visible: !lista.soloIcone
                text: String(voce.modelData.title || "").trim() !== ""
                      ? voce.modelData.title
                      : (Core.Strings.lang === "it" ? "Senza titolo" : "Untitled")
                elide: Text.ElideRight
                color: voce.attiva ? Theme.Colors.text : Theme.Colors.textMuted
                opacity: voce.modelData.minimized ? 0.6 : 1
                font { family: Theme.Typography.fontDisplay
                       ; pixelSize: Theme.Typography.sizeSM }
            }

            Ui.ToolTipHint {
                text: voce.modelData.title || ""
                shown: presa.containsMouse && lista.soloIcone
            }

            MouseArea {
                id: presa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // ── Solo il tasto sinistro ───────────────────────────
                //
                // Qui il destro chiudeva la finestra. Sbagliato: un pulsante
                // largo quaranta pixel in una fila di pulsanti uguali, e il
                // gesto più distruttivo che ci sia, senza una domanda. Una
                // finestra chiusa per sbaglio è del lavoro perso, e la barra
                // di Windows — che è il modello — apre un menù, non chiude.
                //
                // Il menù si farà; chiudere per sbaglio no.
                acceptedButtons: Qt.LeftButton

                // Il gesto che tutti si aspettano: se è già davanti, il clic
                // la ripiega; se non lo è, la porta davanti. Senza la prima
                // metà il pulsante della finestra attiva non farebbe niente,
                // ed è il caso in cui lo si preme più spesso.
                onClicked: function (m) {
                    // Una ridotta si RIPRENDE, non si mette a fuoco: dare
                    // il fuoco a una finestra che sta in un'altra scrivania
                    // non la riporta indietro. Misurato il 5 settembre 2026 —
                    // il terzo clic non faceva niente e la finestra restava
                    // ridotta.
                    if (voce.modelData.minimized)
                        Core.Windows.restore(voce.modelData.address);
                    else if (voce.attiva)
                        Core.Windows.minimize(voce.modelData.address);
                    else
                        Core.Windows.focus(voce.modelData.address);
                }
            }
        }
    }
}

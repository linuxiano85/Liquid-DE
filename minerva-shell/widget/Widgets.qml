import QtQuick
import "../theme" as Theme
import "../core" as Core

// Widgets — L'elenco dei widget sulla scrivania, e dove stanno.
//
// ── L'elenco sta nelle impostazioni, e ha una forma sola ───────────────────
//
//     desktop.widgets = [
//       { "id": "w1", "tipo": "processore", "fx": 0.04, "fy": 0.12,
//         "fw": 0.14, "fh": 0.13 },
//       …
//     ]
//
// `fx`, `fy`, `fw`, `fh` sono FRAZIONI dello schermo e non pixel. Il perché
// sta in `Telaio.qml`, in due parole: un widget messo a 1600 pixel sparisce
// il giorno che colleghi un monitor più stretto.
//
// ── Perché non è «stato ricordato» ────────────────────────────────────────
//
// Le posizioni dei widget somigliano a `files.desktopPositions` — dove hai
// trascinato le icone — che il banco delle manopole tratta come stato e non
// come manopola. Anche questo è stato, e va dichiarato lì: girarlo a caso in
// una prova vorrebbe dire spostare i widget di chi la fa girare.
Item {
    id: elenco

    /// I widget di adesso, come li dice il file.
    readonly property var messi: Core.Ipc.get("desktop.widgets", [])

    property bool bloccati: true

    Repeater {
        model: elenco.messi

        delegate: Telaio {
            id: cella
            required property var modelData
            required property int index

            identificativo: String(modelData.id || ("w" + index))
            tipo: String(modelData.tipo || "processore")
            fx: modelData.fx !== undefined ? modelData.fx : 0.05
            fy: modelData.fy !== undefined ? modelData.fy : 0.1
            fw: modelData.fw !== undefined ? modelData.fw : 0.16
            fh: modelData.fh !== undefined ? modelData.fh : 0.13
            bloccato: elenco.bloccati
            // «vetro» di serie, «nudo» per chi lo sfondo se l'è scelto per
            // guardarlo. Sta sul singolo widget e non su tutta la scrivania:
            // una colonna nuda accanto a una carta di vetro è una scelta che
            // si può volere.
            nudo: String(modelData.aspetto || "vetro") === "nudo"

            // `cella.tipo` e non `parent.tipo`: il genitore di quello che si
            // mette dentro un `Telaio` non è il telaio, è il suo contenitore
            // — `default property alias contenuto: dentro.data`. Con
            // `parent.tipo` il widget non sapeva cosa mostrare e disegnava un
            // trattino, che è esattamente quello che fa quando il dato non
            // c'è: un difetto travestito da caso normale.
            Loader {
                anchors.fill: parent
                // Il riassunto è una colonna di valori dentro una casella
                // sola; i tabelloni (prestazioni, bluetooth) hanno una forma
                // loro; tutto il resto è un numero e una parola. La riga di
                // confine sta scritta in cima a `Contenuto.qml`.
                sourceComponent: cella.tipo === "riassunto" ? tantiValori
                               : cella.tipo === "prestazioni" ? prestazioni
                               : cella.tipo === "bluetooth" ? bluetooth
                               : unValore
            }

            Component {
                id: prestazioni
                Prestazioni { nudo: cella.nudo }
            }

            Component {
                id: bluetooth
                Bluetooth { nudo: cella.nudo }
            }

            Component {
                id: unValore
                Contenuto {
                    tipo: cella.tipo
                    nudo: cella.nudo
                    // Il grafico si può spegnere per widget: chi vuole solo il
                    // numero grande lo vuole grande, non su una texture.
                    grafico: cella.modelData.grafico !== false
                }
            }

            Component {
                id: tantiValori
                Riassunto {
                    nudo: cella.nudo
                    righe: (cella.modelData.righe
                            && cella.modelData.righe.length > 0)
                           ? cella.modelData.righe
                           : ["processore", "memoria", "gpu", "temperatura"]
                }
            }

            onSistemato: function (nfx, nfy, nfw, nfh) {
                elenco.sposta(index, nfx, nfy, nfw, nfh);
            }
            onTolto: elenco.togli(index)
            onGuida: function (gx, gy) {
                elenco.guidaX = gx;
                elenco.guidaY = gy;
            }
            onMenuChiesto: function (mx, my) {
                elenco.apriMenu(index, mx, my);
            }
        }
    }

    // ── Le righe d'aggancio ──────────────────────────────────────────────
    //
    // Attraversano tutto lo schermo, e devono: servono a dire «sei allineato
    // con quell'altro là in fondo», e una riga lunga quanto il widget non lo
    // direbbe. Compaiono solo mentre si trascina.
    //
    // `Rectangle` e non `Shape`: la shell disegna col processore, e lì una
    // forma lascia i propri pixel dove non c'è più niente
    // (`minerva-residui-software`).
    property real guidaX: -1
    property real guidaY: -1

    Rectangle {
        visible: elenco.guidaX >= 0
        x: Math.round(elenco.guidaX)
        y: 0
        width: 1
        height: elenco.height
        color: Theme.Colors.accent
        opacity: 0.7
    }

    Rectangle {
        visible: elenco.guidaY >= 0
        x: 0
        y: Math.round(elenco.guidaY)
        width: elenco.width
        height: 1
        color: Theme.Colors.accent
        opacity: 0.7
    }

    // ── Il cartello del modo «personalizza» ──────────────────────────────
    //
    // Da sbloccati, tutta la superficie dei widget prende i clic: sta sopra
    // le icone (vedi `shell.qml`) e da qui non si può dire «solo dove c'è un
    // widget» — una superficie Wayland ha una regione sensibile sola, e
    // farla seguire ai widget mentre si trascinano sarebbe un aggiornamento
    // per fotogramma. Quindi è un MODO, e un modo deve vedersi: senza questo
    // cartello uno sblocca i widget dalle Impostazioni, torna sulla
    // scrivania, non riesce a cliccare le icone e non capisce perché.
    //
    // «Fatto» riblocca da qui, che è dove uno sta guardando.
    Rectangle {
        visible: !elenco.bloccati
        anchors.horizontalCenter: parent.horizontalCenter
        // Sotto la barra, che sta in cima (o in fondo): questa superficie
        // copre tutto lo schermo, barra compresa, e a `y: 0` il cartello
        // finiva dietro l'orologio.
        y: Core.Ipc.get("bar.position", "alto") === "basso"
           ? Theme.Effects.space4 : 44 + Theme.Effects.space3
        width: cartello.implicitWidth + Theme.Effects.space4 * 2
        height: 34
        radius: 17
        color: Theme.Colors.panel
        border.width: 1
        border.color: Theme.Colors.accent

        Row {
            id: cartello
            anchors.centerIn: parent
            spacing: Theme.Effects.space3

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Core.Strings.lang === "it"
                      ? "Personalizzazione: trascina, tira i bordi per la misura, tasto destro per le opzioni"
                      : "Customising: drag, pull the edges to resize, right-click for options"
                color: Theme.Colors.text
                font.family: Theme.Typography.fontDisplay
                font.pixelSize: Theme.Typography.sizeSM
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: fattoTesto.implicitWidth + Theme.Effects.space3 * 2
                height: 24
                radius: 12
                color: fattoMouse.containsMouse ? Theme.Colors.accent
                                                : Qt.alpha(Theme.Colors.accent, 0.25)

                Text {
                    id: fattoTesto
                    anchors.centerIn: parent
                    text: Core.Strings.lang === "it" ? "Fatto" : "Done"
                    color: fattoMouse.containsMouse ? Theme.Colors.textOnAccent
                                                    : Theme.Colors.text
                    font.family: Theme.Typography.fontDisplay
                    font.pixelSize: Theme.Typography.sizeSM
                    font.weight: Theme.Typography.weightMedium
                }

                MouseArea {
                    id: fattoMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Core.Ipc.setSetting("desktop.widgetBloccati", true)
                }
            }
        }
    }

    // ── Il menù di un widget ─────────────────────────────────────────────
    //
    // Disegnato QUI dentro e non con `ContextMenu`: quello è una superficie a
    // schermo intero sul piano di sopra, e questa sta sul piano Bottom — un
    // menù del piano alto aperto da un widget della scrivania si prenderebbe
    // la tastiera e coprirebbe le finestre, per scegliere fra tre voci.
    //
    // Esiste solo da sbloccati, cioè quando tutta la superficie è già
    // sensibile al puntatore: da bloccati non c'è niente da cui aprirlo.
    property int menuQuale: -1
    property real menuX: 0
    property real menuY: 0

    function apriMenu(i, x, y) {
        elenco.menuQuale = i;
        elenco.menuX = x;
        elenco.menuY = y;
    }

    function chiudiMenu() { elenco.menuQuale = -1; }

    /// La voce del widget aperto, o `null`.
    readonly property var menuVoce:
        (elenco.menuQuale >= 0 && elenco.menuQuale < elenco.messi.length)
        ? elenco.messi[elenco.menuQuale] : null

    // Il velo che chiude il menù cliccando fuori. Sotto al menù nell'ordine
    // di dichiarazione, quindi il menù riceve i suoi clic per primo.
    MouseArea {
        anchors.fill: parent
        visible: elenco.menuQuale >= 0
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: elenco.chiudiMenu()
    }

    Rectangle {
        id: menu
        visible: elenco.menuQuale >= 0
        // Non esce dallo schermo: aperto vicino al bordo destro si apre verso
        // sinistra, e in basso verso l'alto.
        x: Math.max(4, Math.min(elenco.width - width - 4, elenco.menuX))
        y: Math.max(4, Math.min(elenco.height - height - 4, elenco.menuY))
        width: 220
        height: voci.implicitHeight + Theme.Effects.space2 * 2
        radius: Theme.Effects.radiusMD
        // Quasi opaco, e non la membrana: questo menù si apre SOPRA il
        // widget, e con la trasparenza della membrana il numero grosso del
        // widget si leggeva attraverso le voci — visto in fotografia il 14
        // settembre 2026, e non si capiva quale delle due cose si stesse
        // guardando. Il menù della scrivania può essere di vetro perché
        // sotto ha lo sfondo; questo ha un «22 %» in corpo 40.
        color: Qt.rgba(Theme.Colors.membrane.r, Theme.Colors.membrane.g,
                       Theme.Colors.membrane.b, 0.96)
        border.width: 1
        border.color: Theme.Colors.edge

        Column {
            id: voci
            anchors.fill: parent
            anchors.margins: Theme.Effects.space2

            Repeater {
                model: elenco.vociMenu

                delegate: Rectangle {
                    required property var modelData
                    width: voci.width
                    height: 30
                    radius: Theme.Effects.radiusSM
                    color: sopra.containsMouse
                           ? (modelData.pericolo
                              ? Qt.alpha(Theme.Colors.danger, 0.16)
                              : Theme.Colors.raised)
                           : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.Effects.space2
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.testo
                        color: modelData.pericolo ? Theme.Colors.danger
                                                  : Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeSM
                    }

                    MouseArea {
                        id: sopra
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var i = elenco.menuQuale;
                            elenco.chiudiMenu();
                            elenco.eseguiMenu(i, String(modelData.azione));
                        }
                    }
                }
            }
        }
    }

    /// Le voci del menù, ricostruite a ogni apertura: dicono cosa c'è ADESSO
    /// («Togli il vetro» oppure «Rimetti il vetro»), che è l'unico modo di
    /// non avere una spunta da disegnare.
    readonly property var vociMenu: {
        var v = elenco.menuVoce;
        if (!v)
            return [];
        var it = Core.Strings.lang === "it";
        var nudo = String(v.aspetto || "vetro") === "nudo";
        var l = [];
        l.push({ "testo": nudo ? (it ? "Rimetti il vetro" : "Put the glass back")
                               : (it ? "Togli il vetro" : "Remove the glass"),
                 "azione": "aspetto", "pericolo": false });
        if (Core.Macchina.haStoria(String(v.tipo || ""))) {
            l.push({ "testo": v.grafico === false
                     ? (it ? "Mostra la storia" : "Show the history")
                     : (it ? "Nascondi la storia" : "Hide the history"),
                     "azione": "grafico", "pericolo": false });
        }
        l.push({ "testo": it ? "Portalo davanti" : "Bring to front",
                 "azione": "davanti", "pericolo": false });
        l.push({ "testo": it ? "Togli il widget" : "Remove the widget",
                 "azione": "togli", "pericolo": true });
        return l;
    }

    function eseguiMenu(i, azione) {
        if (i < 0 || i >= elenco.messi.length)
            return;
        var v = elenco.messi[i];
        switch (azione) {
        case "aspetto":
            elenco.cambia(i, "aspetto",
                String(v.aspetto || "vetro") === "nudo" ? "vetro" : "nudo");
            break;
        case "grafico":
            elenco.cambia(i, "grafico", v.grafico === false);
            break;
        // L'ordine dell'elenco È l'ordine di sovrapposizione: l'ultimo si
        // disegna sopra. Quindi «portalo davanti» è spostarlo in fondo — e
        // per due widget che si accavallano è l'unico modo di scegliere
        // quale si vede.
        case "davanti":
            elenco.davanti(i);
            break;
        case "togli":
            elenco.togli(i);
            break;
        }
    }

    function cambia(i, campo, valore) {
        var l = [];
        for (var k = 0; k < elenco.messi.length; k++)
            l.push(elenco.copia(elenco.messi[k]));
        if (i < 0 || i >= l.length)
            return;
        l[i][campo] = valore;
        Core.Ipc.setSetting("desktop.widgets", l);
    }

    function davanti(i) {
        var l = [];
        for (var k = 0; k < elenco.messi.length; k++)
            if (k !== i)
                l.push(elenco.copia(elenco.messi[k]));
        l.push(elenco.copia(elenco.messi[i]));
        Core.Ipc.setSetting("desktop.widgets", l);
    }

    // ── Si riscrive l'elenco intero, e non la voce ───────────────────────
    //
    // `Core.Ipc.get` restituisce la mappa VERA, non una copia: cambiarla sul
    // posto e riscriverla vorrebbe dire che il legame non si accorge di
    // niente, perché l'oggetto è lo stesso di prima. È la trappola presa
    // l'8 settembre con le spunte di Manutenzione, e costa una copia.
    function sposta(i, fx, fy, fw, fh) {
        var l = [];
        var vecchi = elenco.messi;
        for (var k = 0; k < vecchi.length; k++) {
            var v = vecchi[k];
            l.push(k === i
                ? { "id": v.id, "tipo": v.tipo, "aspetto": v.aspetto,
                    "righe": v.righe, "grafico": v.grafico,
                    "fx": Math.round(fx * 10000) / 10000,
                    "fy": Math.round(fy * 10000) / 10000,
                    "fw": Math.round(fw * 10000) / 10000,
                    "fh": Math.round(fh * 10000) / 10000 }
                : elenco.copia(v));
        }
        Core.Ipc.setSetting("desktop.widgets", l);
    }

    /// Una copia di una voce. Serve perché `Core.Ipc.get` restituisce
    /// l'oggetto VERO: cambiarlo sul posto vorrebbe dire che il legame non si
    /// accorge di niente, perché l'oggetto è lo stesso di prima. È la
    /// trappola presa l'8 settembre 2026 con le spunte di Manutenzione.
    function copia(v) {
        return { "id": v.id, "tipo": v.tipo, "aspetto": v.aspetto,
                 "righe": v.righe, "grafico": v.grafico,
                 "fx": v.fx, "fy": v.fy, "fw": v.fw, "fh": v.fh };
    }

    function togli(i) {
        var l = [];
        var vecchi = elenco.messi;
        for (var k = 0; k < vecchi.length; k++) {
            if (k === i)
                continue;
            l.push(elenco.copia(vecchi[k]));
        }
        Core.Ipc.setSetting("desktop.widgets", l);
    }

    /// Aggiunge un widget dove c'è posto. Non al centro dello schermo: due
    /// widget aggiunti di fila si coprirebbero, e il secondo sembrerebbe non
    /// essere comparso.
    function aggiungi(tipo) {
        var l = [];
        var vecchi = elenco.messi;
        for (var k = 0; k < vecchi.length; k++)
            l.push(elenco.copia(vecchi[k]));
        var n = l.length;
        // I tabelloni nascono grandi: sono cinque righe più un grafico, e a
        // misura di widget singolo mostrerebbero l'intestazione e basta.
        var grande = tipo === "prestazioni" || tipo === "bluetooth";
        l.push({ "id": "w" + Date.now(), "tipo": String(tipo),
                 "aspetto": "vetro", "grafico": true,
                 "fx": 0.04 + (n % 4) * 0.17,
                 "fy": 0.12 + Math.floor(n / 4) * 0.17,
                 "fw": grande ? 0.24 : 0.15, "fh": grande ? 0.62 : 0.14 });
        Core.Ipc.setSetting("desktop.widgets", l);
    }
}

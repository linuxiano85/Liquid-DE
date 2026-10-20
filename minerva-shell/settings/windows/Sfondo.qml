import QtQuick
import Quickshell
import "../../core" as Core
import "../../ui" as Ui
import "../../windows11" as W
import ".." as S
import "Dati.js" as Dati

// Personalizzazione › Sfondo, come in Windows 11 (macchina di riferimento,
// 12 ottobre 2026; struttura in `docs/impostazioni-windows-specifica.md`).
//
// Le scelte sono quelle di Liquid, per tutti i preset:
//   · Immagine       → `desktop.wallpaperMode` "image" (o gli sfondi di
//                       Liquid), le «Immagini recenti» (`wallpaperRecenti`);
//   · Tinta unita    → "color" e `desktop.wallpaperColor`;
//   · Presentazione  → "folder", `wallpaperFolder`, `rotateMinutes`,
//                       `rotateRandom`;
//   · Contenuti in evidenza di Windows: Liquid non lo ha ancora, grigia;
//   · l'adattamento  → `desktop.wallpaperFit`.
// Nel preset Windows lo sfondo di serie è Bloom che segue il tema
// (`windows11.wallpaper` "auto"): scegliere qualunque cosa qui lo fissa
// («current»), e l'opzione di Liquid in fondo lo rimette.
PaginaWindows {
    id: pagina

    readonly property string lingua: Core.Strings.lang
    function tt(k) { return Dati.t(pagina.lingua, k); }

    briciole: [{ "testo": tt("personalizzazione"), "pagina": "w-personalizzazione" }, { "testo": tt("sfondo") }]

    readonly property bool presetWindows: Core.Ipc.get("bar.stile", "isola") === "windows11"
    readonly property bool bloom: pagina.presetWindows && Core.Ipc.get("windows11.wallpaper", "auto") !== "current"
    readonly property string modo: Core.Ipc.get("desktop.wallpaperMode", "minerva")
    readonly property string tipo: pagina.bloom ? "immagine"
        : pagina.modo === "folder" ? "presentazione"
        : pagina.modo === "color" ? "tinta" : "immagine"

    function fissa() {
        if (pagina.presetWindows)
            Core.Ipc.setSetting("windows11.wallpaper", "current");
    }
    function scegliTipo(v) {
        if (v === "tinta") {
            pagina.fissa();
            Core.Ipc.setSetting("desktop.wallpaperMode", "color");
        } else if (v === "presentazione") {
            pagina.fissa();
            Core.Ipc.setSetting("desktop.wallpaperMode", "folder");
        } else if (v === "immagine") {
            var attuale = Core.Wallpaper.current;
            pagina.fissa();
            Core.Ipc.setSetting("desktop.wallpaperMode", "image");
            if (Core.Ipc.get("desktop.wallpaper", "") === "" && attuale !== "")
                Core.Ipc.setSetting("desktop.wallpaper", attuale);
        }
    }

    /// Le immagini recenti: quelle usate, poi gli sfondi che viaggiano con
    /// Liquid (Bloom se c'è, quelli di Liquid), fino a cinque, come Windows
    /// che di serie mostra i suoi.
    readonly property var recenti: {
        var lista = [];
        var usate = Core.Wallpaper.recenti || [];
        for (var i = 0; i < usate.length && lista.length < 5; i++)
            if (lista.indexOf(usate[i]) < 0)
                lista.push(usate[i]);
        var proprie = [];
        if (Core.Wallpaper.bloomPresente) {
            var base = decodeURIComponent(Qt.resolvedUrl("../../windows11/wallpapers/").toString().replace(/^file:\/\//, ""));
            proprie.push(base + "bloom-light.jpg", base + "bloom-dark.jpg");
        }
        for (var j = 0; j < Core.Wallpaper.own.length; j++)
            proprie.push(Core.Wallpaper.ownPath(Core.Wallpaper.own[j].file));
        for (var k = 0; k < proprie.length && lista.length < 5; k++)
            if (lista.indexOf(proprie[k]) < 0)
                lista.push(proprie[k]);
        return lista;
    }

    property string focusRecente: ""
    function ripristinaFocusRecente() {
        if (focusRecente === "" || String(recenti[0]) !== focusRecente)
            return;
        for (var i = 0; i < miniature.count; i++) {
            var item = miniature.itemAt(i);
            if (item && String(item.modelData) === focusRecente) {
                item.forceActiveFocus(Qt.OtherFocusReason);
                focusRecente = "";
                break;
            }
        }
    }
    onRecentiChanged: Qt.callLater(pagina.ripristinaFocusRecente)
    function scegliRecente(percorso) {
        focusRecente = String(percorso);
        Core.Wallpaper.scegli(percorso);
        // Si aspetta l'ordine aggiornato del demone: un richiamo prima della
        // risposta riporterebbe il fuoco su un delegato che viene distrutto.
        Qt.callLater(pagina.ripristinaFocusRecente);
    }
    function spostaRecente(indice, passo) {
        var prossimo = Math.max(0, Math.min(miniature.count - 1, indice + passo));
        var item = miniature.itemAt(prossimo);
        if (item)
            item.forceActiveFocus(Qt.TabFocusReason);
    }

    readonly property var adattamenti: [
        { "valore": "riempi", "testo": tt("riempi") }, { "valore": "adatta", "testo": tt("adatta") },
        { "valore": "allunga", "testo": tt("allunga") }, { "valore": "affianca", "testo": tt("affianca") },
        { "valore": "centra", "testo": tt("centra") }, { "valore": "estendi", "testo": tt("estendi") }
    ]

    ScegliFileWindows {
        id: sceltaFoto
        proprietario: pagina.Window.window
        onScelto: function(percorso) { Core.Wallpaper.scegli(percorso); }
    }
    ScegliFileWindows {
        id: sceltaCartella
        proprietario: pagina.Window.window
        soloCartelle: true
        onScelto: function(percorso) {
            pagina.fissa();
            Core.Ipc.setSettings({"desktop.wallpaperFolder": percorso, "desktop.wallpaperMode": "folder"});
        }
    }

    AnteprimaDesktop {
        objectName: "anteprimaDesktop"
        width: Math.min(336, pagina.larghezza)
        height: Math.round(width * 188 / 336)
        tinta: pagina.tipo === "tinta" ? Core.Wallpaper.colore : "transparent"
    }
    Item { width: 1; height: 11 }

    EspansoreImpostazione {
        objectName: "personalizzaSfondo"
        icona: "immagine"
        titolo: pagina.tt("personalizzaSfondo")
        descrizione: pagina.tt("personalizzaSfondoDescr")
        aperto: true
        comando: TendinaWindows {
            objectName: "tendinaTipoSfondo"
            valore: pagina.tipo
            voci: [
                { "valore": "immagine", "testo": pagina.tt("immagine") },
                { "valore": "tinta", "testo": pagina.tt("tintaUnita") },
                { "valore": "presentazione", "testo": pagina.tt("presentazione") },
                { "valore": "inEvidenza", "testo": pagina.tt("inEvidenza"), "disponibile": false }
            ]
            onScelto: function (v) { pagina.scegliTipo(v); }
        }

        // ── Immagine ──
        Item {
            visible: pagina.tipo === "immagine"
            width: parent.width
            height: visible ? immaginiRecenti.y + immaginiRecenti.implicitHeight + 6 : 0
            Rectangle { width: parent.width; height: 1; color: W.Style.divider }
            Text {
                x: 59; y: 13
                text: pagina.tt("immaginiRecenti")
                color: W.Style.text
                font.family: W.Style.font
                font.pixelSize: 14
            }
            // A 940 px cinque miniature da 100 non entrano sempre: il
            // ritorno a capo mantiene la misura e non invade la scrollbar.
            Flow {
                id: immaginiRecenti
                objectName: "recentiSfondo"
                x: 59
                y: 38
                width: Math.max(0, parent.width - x - 16)
                spacing: 4
                Repeater {
                    id: miniature
                    model: pagina.recenti
                    delegate: Rectangle {
                        id: miniatura
                        required property var modelData
                        required property int index
                        objectName: "recente-" + index
                        readonly property bool attuale: Core.Wallpaper.current === String(modelData)
                        width: Math.min(100, immaginiRecenti.width)
                        height: width
                        radius: 4
                        color: W.Style.field
                        clip: true
                        border.width: activeFocus || attuale || presaMin.containsMouse ? 2 : 0
                        border.color: activeFocus ? W.Style.accent : W.Style.text
                        activeFocusOnTab: true
                        Keys.onReturnPressed: pagina.scegliRecente(modelData)
                        Keys.onSpacePressed: pagina.scegliRecente(modelData)
                        Keys.onLeftPressed: pagina.spostaRecente(index, -1)
                        Keys.onRightPressed: pagina.spostaRecente(index, 1)
                        Keys.onUpPressed: pagina.spostaRecente(index, -Math.max(1, Math.floor((immaginiRecenti.width + 4) / (width + 4))))
                        Keys.onDownPressed: pagina.spostaRecente(index, Math.max(1, Math.floor((immaginiRecenti.width + 4) / (width + 4))))
                        Image {
                            anchors.fill: parent
                            anchors.margins: miniatura.border.width
                            source: Core.Wallpaper.urlFile(miniatura.modelData)
                            sourceSize: Qt.size(200, 200)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: String(modelData).substring(String(modelData).lastIndexOf("/") + 1)
                        Accessible.description: String(modelData)
                        Accessible.checkable: true
                        Accessible.checked: attuale
                        Accessible.onPressAction: pagina.scegliRecente(modelData)
                        Accessible.onToggleAction: pagina.scegliRecente(modelData)
                        MouseArea {
                            id: presaMin
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pagina.scegliRecente(miniatura.modelData)
                        }
                    }
                }
            }
        }
        SchedaImpostazione {
            visible: pagina.tipo === "immagine"
            interna: true
            titolo: pagina.tt("scegliFoto")
            PulsanteWindows {
                objectName: "sfogliaFoto"
                testo: pagina.tt("sfogliaFoto")
                onPremuto: sceltaFoto.apri("")
            }
        }

        // ── Tinta unita ──
        Item {
            visible: pagina.tipo === "tinta"
            width: parent.width
            height: visible ? coloreSfondo.y + coloreSfondo.height + 24 : 0
            Rectangle { width: parent.width; height: 1; color: W.Style.divider }
            Text {
                x: 59; y: 13
                text: pagina.tt("coloreSfondo")
                color: W.Style.text
                font.family: W.Style.font
                font.pixelSize: 14
            }
            GrigliaColori {
                id: coloreSfondo
                objectName: "coloriSfondo"
                x: 59; y: 38
                width: Math.min(parent.width - 59 - 44, 9 * 53)
                colori: Dati.coloriSfondo
                scelto: Core.Wallpaper.colore.toString()
                onPreso: function (c) {
                    pagina.fissa();
                    Core.Ipc.setSettings({ "desktop.wallpaperColor": c.toUpperCase(), "desktop.wallpaperMode": "color" });
                }
            }
        }
        SchedaImpostazione {
            visible: pagina.tipo === "tinta"
            interna: true
            titolo: pagina.tt("coloriPersonalizzati")
            PulsanteWindows {
                testo: pagina.tt("visualizzaColori")
                objectName: "visualizzaColoriSfondo"
                onPremuto: sceltaColore.apri(Core.Wallpaper.colore)
            }
        }

        // ── Presentazione ──
        SchedaImpostazione {
            visible: pagina.tipo === "presentazione"
            interna: true
            titolo: pagina.tt("album")
            PulsanteWindows {
                objectName: "sfogliaAlbum"
                testo: pagina.tt("sfoglia")
                onPremuto: sceltaCartella.apri(Core.Ipc.get("desktop.wallpaperFolder", ""))
            }
        }
        SchedaImpostazione {
            visible: pagina.tipo === "presentazione" && Core.Ipc.get("desktop.wallpaperFolder", "") !== ""
            interna: true
            icona: "cartella"
            rientro: 42
            titolo: {
                var c = String(Core.Ipc.get("desktop.wallpaperFolder", ""));
                return c.substring(c.lastIndexOf("/") + 1);
            }
        }
        SchedaImpostazione {
            visible: pagina.tipo === "presentazione"
            interna: true
            titolo: pagina.tt("cambiaOgni")
            TendinaWindows {
                valore: String(Core.Ipc.get("desktop.rotateMinutes", 30) || 30)
                voci: Dati.intervalli.map(function (v) { return { "valore": String(v[0]), "testo": v[1] }; })
                onScelto: function (v) { Core.Ipc.setSetting("desktop.rotateMinutes", parseInt(v)); }
            }
        }
        SchedaImpostazione {
            visible: pagina.tipo === "presentazione"
            interna: true
            titolo: pagina.tt("casuale")
            S.ToggleSwitch {
                checked: Core.Ipc.get("desktop.rotateRandom", false)
                onToggled: function (v) { Core.Ipc.setSetting("desktop.rotateRandom", v); }
            }
        }
        SchedaImpostazione {
            visible: pagina.tipo !== "tinta"
            interna: true
            titolo: pagina.tt("adattamento")
            TendinaWindows {
                objectName: "tendinaAdattamento"
                valore: Core.Wallpaper.adattamento
                voci: pagina.adattamenti
                onScelto: function (v) { Core.Ipc.setSetting("desktop.wallpaperFit", v); }
            }
        }
    }

    GruppoImpostazioni { testo: pagina.tt("correlate") }
    SchedaImpostazione {
        icona: "contrasto"
        titolo: pagina.tt("contrasto")
        descrizione: pagina.tt("contrastoDescr")
        porta: true
        disponibile: false
    }

    // Le opzioni che Windows non ha (decisione del manutentore: in coda, in una
    // scheda sola che si apre).
    GruppoImpostazioni { testo: "Liquid" }
    EspansoreImpostazione {
        objectName: "opzioniLiquid"
        icona: "settings"
        titolo: pagina.tt("opzioniLiquid")
        descrizione: pagina.tt("opzioniLiquidDescr")
        SchedaImpostazione {
            interna: true
            visible: pagina.presetWindows
            titolo: pagina.lingua === "it" ? "Sfondo Bloom che segue il tema chiaro o scuro" : "Bloom background that follows the light or dark theme"
            S.ToggleSwitch {
                checked: pagina.bloom
                onToggled: function (v) { Core.Ipc.setSetting("windows11.wallpaper", v ? "auto" : "current"); }
            }
        }
    }

    // Il selettore del colore personalizzato, sopra la pagina.
    ScegliColoreWindows {
        id: sceltaColore
        parent: pagina
        onConfermato: function (c) {
            pagina.fissa();
            Core.Ipc.setSettings({ "desktop.wallpaperColor": c.toString().toUpperCase(), "desktop.wallpaperMode": "color" });
        }
    }
}

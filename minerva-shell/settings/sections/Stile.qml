import QtQuick
import "../../theme" as Theme
import "../../core" as Core
import ".." as S

// Stile — Quattro scrivanie in un clic.
//
// ── Perché esiste ─────────────────────────────────────────────────────────
//
// Giacomo, 4 settembre 2026: «poi creerei dei preset come ad esempio stile
// mac, stile windows, stile minerva, stile libero che ad esempio posso avere
// la barra come windows con le app aperte e meteo e tutto simile a windows
// eccetera».
//
// Tutte le manopole che servono esistevano già e stavano in tre pagine
// diverse: dove sta la barra, dove sta la dock, se la dock c'è, come si
// nasconde, quanto ingrandisce, da che parte stanno i pulsanti delle finestre.
// Uno stile non aggiunge niente: **le scrive insieme**.
//
// ── Un messaggio solo, non venti ─────────────────────────────────────────
//
// `Core.Ipc.setSettings()` manda tutta la mappa in una volta, e il demone fa
// una scrittura su disco e un annuncio. Con venti `setSetting` di fila
// sarebbero venti giri, venti scritture e venti ricostruzioni del tema — e per
// un istante la scrivania sarebbe mezza Mac e mezza Windows.
//
// ── «Libero» non è vuoto: è il tuo ───────────────────────────────────────
//
// Scegliere uno stile salva prima com'era. Un preset che cancella una
// scrivania costruita in due mesi senza modo di tornare indietro è un difetto,
// non una funzione.
Page {
    id: page

    title: page.it ? "Stile della scrivania" : "Desktop style"
    subtitle: page.it
        ? "Dove stanno la barra, la dock e i comandi delle finestre"
        : "Where the bar, the dock and the window controls sit"

    readonly property bool it: Core.Strings.lang === "it"

    /// Le chiavi che uno stile tocca. Sono anche quelle che «Libero» si
    /// ricorda: l'elenco è uno solo apposta, o le due cose divergono e
    /// tornando a «Libero» si riprende metà scrivania.
    readonly property var _chiavi: [
        "bar.position", "bar.listaFinestre", "bar.stile",
        "dock.enabled", "dock.position", "dock.modo",
        "dock.iconSize", "dock.magnification",
        "windows.buttonsSide"
    ]

    readonly property var _stili: ({
        // La Riva: al posto della barra l'Isola, una capsula che galleggia in
        // mezzo con l'ora, il tempo, i segni di stato e le notifiche.
        "liquid": {
            "bar.position": "alto",
            "bar.stile": "isola",
            "bar.listaFinestre": false,
            "dock.enabled": true,
            "dock.position": "basso",
            "dock.modo": "sempre",
            "dock.iconSize": 48,
            "dock.magnification": 1.5,
            "windows.buttonsSide": "destra"
        },
        "minerva": {
            "bar.position": "alto",
            "bar.stile": "classica",
            "bar.listaFinestre": false,
            "dock.enabled": true,
            "dock.position": "basso",
            "dock.modo": "sempre",
            "dock.iconSize": 48,
            "dock.magnification": 1.5,
            "windows.buttonsSide": "destra"
        },
        "mac": {
            "bar.position": "alto",
            "bar.stile": "classica",
            "bar.listaFinestre": false,
            "dock.enabled": true,
            "dock.position": "basso",
            // «Elude» e non «sempre»: sul Mac la dock si toglie di mezzo
            // quando una finestra le arriva addosso.
            "dock.modo": "elude",
            "dock.iconSize": 52,
            "dock.magnification": 1.9,
            // Il semaforo sta a sinistra. È la cosa che si nota per prima, e
            // l'unica che nessun altro stile fa.
            "windows.buttonsSide": "sinistra"
        },
        "windows": {
            // Una barra sola, in basso, con dentro le finestre aperte. La
            // dock non c'è: sarebbe la stessa cosa detta due volte.
            "bar.position": "basso",
            "bar.stile": "classica",
            "bar.listaFinestre": true,
            "dock.enabled": false,
            "dock.position": "alto",
            "dock.modo": "sempre",
            "dock.iconSize": 48,
            "dock.magnification": 1.0,
            "windows.buttonsSide": "destra"
        }
    })

    readonly property string attuale: Core.Ipc.get("stile.attuale", "libero")

    /// Fotografa com'è adesso, per poterci tornare.
    function _fotografa() {
        var f = ({});
        for (var i = 0; i < page._chiavi.length; i++) {
            var k = page._chiavi[i];
            f[k] = Core.Ipc.get(k, null);
        }
        return f;
    }

    function applica(nome) {
        if (nome === page.attuale)
            return;

        var mappa = ({});

        // ── Si salva PRIMA di cambiare, e solo la prima volta ────────────
        //
        // Se si è già dentro uno stile, la fotografia da tenere è quella che
        // c'era prima di entrarci: risalvare adesso vorrebbe dire che
        // «Libero» riporta a Mac, cioè che il tuo l'hai perso.
        //
        // La fotografia viaggia come TESTO e non come mappa annidata: le
        // chiavi hanno il punto dentro (`bar.position`), e il demone il punto
        // lo legge come «scendi di un livello». Una riga di JSON non ha
        // questo problema e non chiede di inventarsi un carattere al posto
        // del punto.
        if (page.attuale === "libero")
            mappa["stile.libero"] = JSON.stringify(page._fotografa());

        if (nome === "libero") {
            // Si rimette quello che c'era. Chi non ha mai salvato niente
            // resta com'è: meglio non fare niente che riportare a valori
            // inventati.
            var salvato = null;
            try {
                var testo = String(Core.Ipc.get("stile.libero", ""));
                if (testo !== "")
                    salvato = JSON.parse(testo);
            } catch (e) {
                // Una fotografia illeggibile non deve impedire di cambiare
                // stile: si torna a «libero» senza spostare niente, che è
                // meglio che restare bloccati dentro Windows.
                console.warn("[MINERVA][Stile] fotografia illeggibile:", e);
            }
            if (salvato) {
                for (var chiave in salvato) {
                    if (salvato[chiave] !== null && salvato[chiave] !== undefined)
                        mappa[chiave] = salvato[chiave];
                }
            }
        } else {
            var s = page._stili[nome];
            if (!s)
                return;
            for (var kk in s)
                mappa[kk] = s[kk];
        }

        mappa["stile.attuale"] = nome;
        Core.Ipc.setSettings(mappa);
    }

    Card {
        heading: page.it ? "Scegli uno stile" : "Pick a style"
        note: page.it
              ? "Scegliendo uno stile, la scrivania che hai adesso viene messa da parte: «Libero» la riprende."
              : "Picking a style puts your current desktop aside: “Free” brings it back."

        S.SettingRow {
            width: parent.width
            label: page.it ? "Stile" : "Style"
            description: page.it
                ? "Cambia dove stanno barra, dock e comandi delle finestre"
                : "Changes where the bar, dock and window controls sit"
            controlWidth: 460
            control: S.ChoicePicker {
                value: page.attuale
                options: [
                    { "value": "liquid",  "label": "Liquid" },
                    { "value": "minerva", "label": "Minerva" },
                    { "value": "mac",     "label": "Mac" },
                    { "value": "windows", "label": "Windows" },
                    { "value": "libero",  "label": page.it ? "Libero" : "Free" }
                ]
                onPicked: function (v) { page.applica(v); }
            }
        }
    }

    Card {
        heading: page.it ? "Che cosa cambia" : "What changes"

        Column {
            width: parent.width
            spacing: Theme.Effects.space3

            Repeater {
                model: [
                    { "n": "Liquid",
                      "d": page.it
                           ? "Al posto della barra l'Isola: una capsula che galleggia in mezzo con l'ora, il tempo, i segni di stato e le notifiche. Si trascina in alto o in basso."
                           : "Instead of the bar, the Island: a capsule floating in the middle with the time, the weather, the status and the notifications. Drag it up or down." },
                    { "n": "Minerva",
                      "d": page.it
                           ? "Barra in alto, dock in fondo sempre visibile, comandi delle finestre a destra."
                           : "Bar on top, dock always visible at the bottom, window controls on the right." },
                    { "n": "Mac",
                      "d": page.it
                           ? "Come Minerva, ma la dock ingrandisce di più e si toglie di mezzo quando una finestra le arriva addosso — e i comandi delle finestre stanno a SINISTRA."
                           : "Like Minerva, but the dock magnifies more and gets out of the way — and the window controls sit on the LEFT." },
                    { "n": "Windows",
                      "d": page.it
                           ? "Una barra sola in fondo, con dentro le finestre aperte. Niente dock: sarebbe la stessa cosa detta due volte."
                           : "A single bar at the bottom holding the open windows. No dock: it would say the same thing twice." },
                    { "n": page.it ? "Libero" : "Free",
                      "d": page.it
                           ? "Quello che avevi messo tu, ripreso com'era."
                           : "Whatever you had set up, brought back as it was." }
                ]

                delegate: Column {
                    required property var modelData
                    width: parent.width
                    spacing: 2

                    Text {
                        text: modelData.n
                        color: Theme.Colors.text
                        font { family: Theme.Typography.fontDisplay
                               ; pixelSize: Theme.Typography.sizeMD
                               ; weight: Theme.Typography.weightMedium }
                    }
                    Text {
                        width: parent.width
                        text: modelData.d
                        wrapMode: Text.WordWrap
                        color: Theme.Colors.textMuted
                        font { family: Theme.Typography.fontDisplay
                               ; pixelSize: Theme.Typography.sizeSM }
                    }
                }
            }
        }
    }
}

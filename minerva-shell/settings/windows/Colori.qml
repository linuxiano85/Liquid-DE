import QtQuick
import "../../core" as Core
import "../../windows11" as W
import ".." as S
import "Dati.js" as Dati

// Personalizzazione › Colori, come in Windows 11 (macchina di riferimento,
// 12 ottobre 2026).
//
//   · Scegli la modalità: Chiara / Scura / Personalizzata. «Personalizzata»
//     separa la modalità di Windows (barra, Start, pannelli:
//     `windows11.theme`) da quella delle app (`windows11.themeApp`); le due
//     righe compaiono sotto, come in Windows.
//   · Effetti di trasparenza → `windows11.acrylic`.
//   · Colore principale: Manuale (i 48 colori di Windows, i recenti,
//     «Visualizza colori») → `windows11.accent`, `windows11.coloriRecenti`.
//     Automatico (dallo sfondo) non c'è ancora: grigio.
//   · Accento su Start e barra (solo in modalità scura, come Windows) →
//     `windows11.accentOnStart`. Sulle barre del titolo: non ancora, grigio.
PaginaWindows {
    id: pagina

    readonly property string lingua: Core.Strings.lang
    function tt(k) { return Dati.t(pagina.lingua, k); }

    briciole: [{ "testo": tt("personalizzazione"), "pagina": "w-personalizzazione" }, { "testo": tt("colori") }]

    readonly property string tema: Core.Ipc.get("windows11.theme", "light")
    readonly property string temaApp: Core.Ipc.get("windows11.themeApp", "")
    readonly property string modo: pagina.temaApp !== "" ? "personalizzata"
                                  : (pagina.tema === "dark" ? "scura" : "chiara")
    readonly property string accento: {
        var a = String(Core.Ipc.get("windows11.accent", "auto"));
        return a === "auto" ? W.Style.accentBase.toUpperCase() : a.toUpperCase();
    }
    readonly property var recenti: {
        var r = Core.Ipc.get("windows11.coloriRecenti", []) || [];
        return r.map(function (c) { return [c, Dati.nomeColore(c)]; });
    }

    function scegliAccento(c) {
        var h = String(c).toUpperCase();
        var lista = [h];
        var vecchi = Core.Ipc.get("windows11.coloriRecenti", []) || [];
        for (var i = 0; i < vecchi.length && lista.length < 5; i++)
            if (String(vecchi[i]).toUpperCase() !== h)
                lista.push(String(vecchi[i]).toUpperCase());
        Core.Ipc.setSettings({ "windows11.accent": h, "windows11.coloriRecenti": lista, "windows11.temaCorrente": "personalizzato" });
    }
    function scegliModo(v) {
        if (v === "chiara")
            Core.Ipc.setSettings({ "windows11.theme": "light", "windows11.themeApp": "" });
        else if (v === "scura")
            Core.Ipc.setSettings({ "windows11.theme": "dark", "windows11.themeApp": "" });
        else
            Core.Ipc.setSetting("windows11.themeApp", pagina.tema);
    }

    AnteprimaDesktop {
        width: 336
        height: 188
    }
    Item { width: 1; height: 11 }

    // Scegli la modalità: una scheda semplice, oppure un Expander con le
    // due righe quando è «Personalizzata».
    EspansoreImpostazione {
        objectName: "sceltaModalita"
        icona: "pennello"
        titolo: pagina.tt("modalita")
        descrizione: pagina.tt("modalitaDescr")
        aperto: pagina.modo === "personalizzata"
        espandibile: pagina.modo === "personalizzata"
        comando: TendinaWindows {
            objectName: "tendinaModalita"
            valore: pagina.modo
            voci: [{ "valore": "chiara", "testo": pagina.tt("chiara") },
                   { "valore": "scura", "testo": pagina.tt("scura") },
                   { "valore": "personalizzata", "testo": pagina.tt("personalizzata") }]
            onScelto: function (v) { pagina.scegliModo(v); }
        }
        SchedaImpostazione {
            interna: true
            titolo: pagina.tt("modalitaWindows")
            TendinaWindows {
                valore: pagina.tema
                voci: [{ "valore": "light", "testo": pagina.tt("chiara") }, { "valore": "dark", "testo": pagina.tt("scura") }]
                onScelto: function (v) { Core.Ipc.setSetting("windows11.theme", v); }
            }
        }
        SchedaImpostazione {
            interna: true
            titolo: pagina.tt("modalitaApp")
            TendinaWindows {
                valore: pagina.temaApp !== "" ? pagina.temaApp : pagina.tema
                voci: [{ "valore": "light", "testo": pagina.tt("chiara") }, { "valore": "dark", "testo": pagina.tt("scura") }]
                onScelto: function (v) { Core.Ipc.setSetting("windows11.themeApp", v); }
            }
        }
    }

    SchedaImpostazione {
        objectName: "effettiTrasparenza"
        icona: "trasparenza"
        titolo: pagina.tt("trasparenza")
        descrizione: pagina.tt("trasparenzaDescr")
        S.ToggleSwitch {
            checked: Core.Ipc.get("windows11.acrylic", true)
            onToggled: function (v) { Core.Ipc.setSetting("windows11.acrylic", v); }
        }
    }

    EspansoreImpostazione {
        objectName: "colorePrincipale"
        icona: "tavolozza"
        titolo: pagina.tt("colorePrincipale")
        aperto: true
        comando: TendinaWindows {
            valore: "manuale"
            voci: [{ "valore": "automatico", "testo": pagina.tt("automatico"), "disponibile": false },
                   { "valore": "manuale", "testo": pagina.tt("manuale") }]
        }
        Item {
            width: parent.width
            height: recentiGriglia.visible ? recentiGriglia.y + recentiGriglia.height + 18 : 0
            visible: pagina.recenti.length > 0
            Rectangle { width: parent.width; height: 1; color: W.Style.divider }
            Text { x: 59; y: 13; text: pagina.tt("coloriRecenti"); color: W.Style.text; font.family: W.Style.font; font.pixelSize: 14 }
            GrigliaColori {
                id: recentiGriglia
                x: 59; y: 38
                width: 9 * 53
                colori: pagina.recenti
                scelto: pagina.accento
                onPreso: function (c) { pagina.scegliAccento(c); }
            }
        }
        Item {
            width: parent.width
            height: windowsGriglia.y + windowsGriglia.height + 24
            Rectangle { visible: pagina.recenti.length === 0; width: parent.width; height: 1; color: W.Style.divider }
            Text { x: 59; y: 13; text: pagina.tt("coloriWindows"); color: W.Style.text; font.family: W.Style.font; font.pixelSize: 14 }
            GrigliaColori {
                id: windowsGriglia
                objectName: "coloriWindows"
                x: 59; y: 38
                width: 9 * 53
                colori: Dati.coloriWindows
                scelto: pagina.accento
                onPreso: function (c) { pagina.scegliAccento(c); }
            }
        }
        SchedaImpostazione {
            interna: true
            titolo: pagina.tt("coloriPersonalizzati")
            PulsanteWindows {
                objectName: "visualizzaColoriAccento"
                testo: pagina.tt("visualizzaColori")
                onPremuto: sceltaColore.apri(pagina.accento)
            }
        }
        SchedaImpostazione {
            interna: true
            objectName: "accentoStart"
            titolo: pagina.tt("accentoStart")
            descrizione: pagina.tema === "dark" ? "" : pagina.tt("soloScura")
            disponibileComando: pagina.tema === "dark"
            S.ToggleSwitch {
                checked: pagina.tema === "dark" && Core.Ipc.get("windows11.accentOnStart", false)
                onToggled: function (v) { Core.Ipc.setSetting("windows11.accentOnStart", v); }
            }
        }
        SchedaImpostazione {
            interna: true
            titolo: pagina.tt("accentoBarre")
            disponibile: false
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

    ScegliColoreWindows {
        id: sceltaColore
        parent: pagina
        onConfermato: function (c) { pagina.scegliAccento(c.toString()); }
    }
}

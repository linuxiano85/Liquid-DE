import QtQuick
import "../../core" as Core
import "../../windows11" as W
import ".." as S

PaginaWindows {
    id: pagina
    objectName: "impostazioniSchermoWindows"
    briciole: [{testo: W.Style.label("Sistema", "System"), pagina: "w-sistema"},
               {testo: W.Style.label("Schermo", "Display")}]
    S.DisplayController { id: configurazione }
    readonly property var monitor: configurazione.monitorScelto || ({})
    readonly property string modo: Number(monitor.hz) > 0
        ? monitor.modoLarghezza + "x" + monitor.modoAltezza + "@" + Number(monitor.hz).toFixed(3) : "preferito"
    readonly property bool occupato: configurazione.multiPending || configurazione.changeGuard.armed || configurazione.multiChangeGuard.armed
    readonly property var risoluzioni: {
        var unique = {};
        var current = monitor.modoLarghezza + "x" + monitor.modoAltezza;
        for (var entry of (monitor.modi || [])) {
            var parts = String(entry).split("@");
            var hz = Number(parts[1]);
            if (parts.length !== 2 || !isFinite(hz) || hz <= 0)
                continue;
            if (!unique[parts[0]])
                unique[parts[0]] = [];
            if (unique[parts[0]].indexOf(hz) < 0)
                unique[parts[0]].push(hz);
        }
        if (monitor.nome && Number(monitor.hz) > 0 && !unique[current])
            unique[current] = [Number(monitor.hz)];
        return Object.keys(unique).sort(function(a, b) {
            var left = a.split("x"), right = b.split("x");
            return Number(right[0]) * Number(right[1]) - Number(left[0]) * Number(left[1]);
        }).map(function(key) {
            return {valore: key, testo: key.replace("x", " × "),
                frequenze: unique[key].sort(function(a, b) { return b - a; })};
        });
    }
    readonly property var frequenze: {
        var current = monitor.modoLarghezza + "x" + monitor.modoAltezza;
        for (var resolution of risoluzioni) {
            if (resolution.valore === current)
                return resolution.frequenze.map(function(hz) {
                    return {valore: Number(hz).toFixed(3), testo: Number(hz).toLocaleString(Qt.locale(), 'f', 2) + " Hz"};
                });
        }
        return [];
    }
    function applica(mode, scale, rotation, description) {
        if (!monitor.nome || occupato)
            return;
        configurazione.apply(monitor.nome, mode, scale, rotation, description);
    }
    function risoluzione(value) {
        for (var item of risoluzioni) {
            if (item.valore !== value)
                continue;
            var rate = item.frequenze.indexOf(Number(monitor.hz)) >= 0 ? Number(monitor.hz) : item.frequenze[0];
            applica(value + "@" + Number(rate).toFixed(3), monitor.scala, monitor.gradi, item.testo);
        }
    }
    readonly property var schermiAccesi: configurazione.monitors.filter(function(item) { return item.acceso !== false; })
    readonly property string disposizione: schermiAccesi.length === 1 && configurazione.monitors.length > 1
        ? "solo:" + schermiAccesi[0].nome : configurazione.duplicati ? "duplica" : "estendi"
    property string esitoTrasmissione: ""
    Connections {
        target: Core.Ipc
        function onTrasmettiPermesso(result) {
            pagina.esitoTrasmissione = result.ok ? W.Style.label("Fatto", "Done")
                : String(result.error || W.Style.label("Operazione non riuscita", "Operation failed"));
        }
    }
    // La mappa comprende anche le coordinate negative: un monitor a sinistra
    // dell'origine non deve sparire o essere sovrapposto a quello principale.
    readonly property var bounds: {
        var x = 0, y = 0, right = 1, bottom = 1;
        for (var display of configurazione.monitors) {
            x = Math.min(x, display.x || 0);
            y = Math.min(y, display.y || 0);
            right = Math.max(right, (display.x || 0) + (display.larghezza || display.modoLarghezza || 1));
            bottom = Math.max(bottom, (display.y || 0) + (display.altezza || display.modoAltezza || 1));
        }
        return {x:x, y:y, width:right-x, height:bottom-y};
    }
    Rectangle {
        id: mappa
        objectName: "schermoMappa"
        width: parent.width
        height: 216
        radius: 8
        color: W.Style.card
        border.width: 1
        border.color: W.Style.cardStroke
        readonly property real factor: Math.min((width - 48) / pagina.bounds.width, 168 / pagina.bounds.height)
        Repeater {
            model: configurazione.monitors
            delegate: Rectangle {
                required property var modelData
                required property int index
                objectName: "schermoMonitor-" + index
                readonly property bool scelto: configurazione.scelto === modelData.nome || configurazione.duplicati
                visible: !configurazione.duplicati || modelData.acceso === false || modelData.nome === pagina.schermiAccesi[0].nome
                x: (mappa.width - pagina.bounds.width * mappa.factor) / 2 + (modelData.x - pagina.bounds.x) * mappa.factor
                y: (mappa.height - pagina.bounds.height * mappa.factor) / 2 + (modelData.y - pagina.bounds.y) * mappa.factor
                width: Math.max(1, (modelData.larghezza || modelData.modoLarghezza) * mappa.factor)
                height: Math.max(1, (modelData.altezza || modelData.modoAltezza) * mappa.factor)
                radius: 4
                color: scelto ? W.Style.accent : W.Style.field
                opacity: modelData.acceso === false ? 0.45 : 1
                border.width: activeFocus ? 3 : 1
                border.color: W.Style.text
                activeFocusOnTab: true
                Accessible.role: Accessible.RadioButton
                Accessible.name: (index + 1) + ": " + configurazione.nomeParlante(modelData)
                Accessible.checked: scelto
                Accessible.checkable: true
                Accessible.onPressAction: configurazione.scelto = modelData.nome
                Keys.onReturnPressed: configurazione.scelto = modelData.nome
                Keys.onSpacePressed: configurazione.scelto = modelData.nome
                Text {
                    anchors.centerIn: parent
                    text: configurazione.duplicati && modelData.acceso !== false
                        ? configurazione.monitors.map(function(item, number) { return item.acceso !== false ? String(number + 1) : ""; }).filter(function(value) { return value !== ""; }).join(" | ")
                        : index + 1
                    color: parent.scelto ? W.Style.accentForeground : W.Style.text
                    font.family: W.Style.font
                    font.pixelSize: Math.min(32, parent.height / 3)
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: configurazione.scelto = modelData.nome
                }
            }
        }
    }
    SchedaImpostazione {
        visible: monitor.nome !== undefined
        titolo: monitor.nome ? configurazione.nomeParlante(monitor) : ""
        descrizione: W.Style.label("Scegli uno schermo per modificarne le impostazioni", "Select a display to change its settings")
        TendinaWindows {
            visible: configurazione.monitors.length > 1
            valore: configurazione.scelto
            voci: configurazione.monitors.map(function(item, index) {
                return {valore:item.nome,testo:(index + 1) + ": " + configurazione.nomeParlante(item)};
            })
            onScelto: function(value) { configurazione.scelto = value; }
        }
    }
    SchedaImpostazione {
        visible: configurazione.displayError !== "" || configurazione.monitors.length === 0
        titolo: W.Style.label("Stato dello schermo", "Display status")
        descrizione: configurazione.displayError || W.Style.label("Nessuno schermo rilevato", "No displays detected")
        PulsanteWindows {
            testo: W.Style.label("Rileva", "Detect")
            onPremuto: configurazione.reload()
        }
    }
    SchedaImpostazione {
        visible: configurazione.monitors.length > 1
        titolo: W.Style.label("Più schermi", "Multiple displays")
        TendinaWindows {
            objectName: "schermoDisposizione"
            enabled: !pagina.occupato
            valore: pagina.disposizione
            voci: [
                {valore:"estendi", testo:W.Style.label("Estendi questi schermi", "Extend these displays")},
                {valore:"duplica", testo:W.Style.label("Duplica questi schermi", "Duplicate these displays")}
            ].concat(configurazione.monitors.map(function(item, index) {
                return {valore:"solo:" + item.nome, testo:W.Style.label("Mostra solo su ", "Show only on ") + (index + 1)};
            }))
            onScelto: function(value) {
                if (value.indexOf("solo:") === 0)
                    configurazione.multi("solo", value.substring(5));
                else
                    configurazione.multi(value, "");
            }
        }
    }
    GruppoImpostazioni { testo: W.Style.label("Luminosità e colore", "Brightness & color") }
    SchedaImpostazione {
        visible: Core.SystemState.hasBrightness
        titolo: W.Style.label("Luminosità", "Brightness")
        W.VolumeSlider {
            width: 250
            from: 1
            to: 100
            value: Core.SystemState.brightness
            Accessible.name: W.Style.label("Luminosità", "Brightness")
            changeVolume: function(value) { Core.SystemState.setBrightness(value); }
        }
    }
    SchedaImpostazione {
        titolo: W.Style.label("Luce notturna", "Night light")
        descrizione: configurazione._tintaSenzaStrada
            ? W.Style.label("Il compositore non dispone di un percorso colore per questo schermo", "The compositor has no color adjustment path for this display") : ""
        S.ToggleSwitch {
            objectName: "schermoLuceNotturna"
            checked: Core.Ipc.get("display.nightLight", false)
            onToggled: function(value) {
                Core.Ipc.setSetting("display.nightLight", value);
                Qt.callLater(Core.Compositore.chiediStato);
            }
        }
    }
    EspansoreImpostazione {
        titolo: W.Style.label("Impostazioni della luce notturna", "Night light settings")
        SchedaImpostazione {
            interna: true
            titolo: W.Style.label("Temperatura colore", "Color temperature")
            TendinaWindows {
                valore: String(Core.Ipc.get("display.nightLightTemp",3800))
                voci: [2000,2700,3800,4500,5500,6500,Core.Ipc.get("display.nightLightTemp",3800)].filter(function(value,index,list) {
                    return list.indexOf(value) === index;
                }).sort(function(a,b) { return a-b; }).map(function(value) {
                    return {valore:String(value),testo:value + " K"};
                })
                onScelto: function(value) { Core.Ipc.setSetting("display.nightLightTemp",Number(value)); }
            }
        }
        SchedaImpostazione {
            interna: true
            titolo: W.Style.label("Pianifica luce notturna", "Schedule night light")
            S.ToggleSwitch {
                checked: Core.Ipc.get("display.nightLightAuto",false)
                onToggled: function(value) { Core.Ipc.setSetting("display.nightLightAuto",value); }
            }
        }
        Repeater {
            model: [{key:"From",it:"Attiva",en:"Turn on"},{key:"To",it:"Disattiva",en:"Turn off"}]
            delegate: SchedaImpostazione {
                required property var modelData
                interna: true
                visible: Core.Ipc.get("display.nightLightAuto",false)
                titolo: W.Style.it ? modelData.it : modelData.en
                TendinaWindows {
                    valore: String(Core.Ipc.get("display.nightLight" + modelData.key, modelData.key === "From" ? 21 : 7))
                    voci: Array.from({length:24},function(_,index) { return {valore:String(index),testo:String(index).padStart(2,"0")+":00"}; })
                    onScelto: function(value) { Core.Ipc.setSetting("display.nightLight" + modelData.key,Number(value)); }
                }
            }
        }
    }
    SchedaImpostazione {
        titolo: "HDR"
        descrizione: W.Style.label("La gestione HDR non è ancora implementata nel compositore", "HDR management is not yet implemented in the compositor")
        disponibile: false
    }
    GruppoImpostazioni { testo: W.Style.label("Ridimensionamento e layout", "Scale & layout") }
    SchedaImpostazione {
        titolo: W.Style.label("Ridimensionamento", "Scale")
        TendinaWindows {
            objectName: "schermoScala"
            enabled: !!pagina.monitor.nome && !pagina.occupato
            valore: String(pagina.monitor.scala || 1)
            voci: [1,1.25,1.5,1.75,2].map(function(scale) { return {valore:String(scale),testo:Math.round(scale*100)+"%"}; })
            onScelto: function(value) { pagina.applica(pagina.modo, value, pagina.monitor.gradi, Math.round(Number(value)*100)+"%"); }
        }
    }
    SchedaImpostazione {
        titolo: W.Style.label("Risoluzione dello schermo", "Display resolution")
        TendinaWindows {
            objectName: "schermoRisoluzione"
            enabled: !!pagina.monitor.nome && pagina.risoluzioni.length > 0 && !pagina.occupato
            valore: pagina.monitor.modoLarghezza + "x" + pagina.monitor.modoAltezza
            voci: pagina.risoluzioni
            onScelto: function(value) { pagina.risoluzione(value); }
        }
    }
    SchedaImpostazione {
        titolo: W.Style.label("Orientamento dello schermo", "Display orientation")
        TendinaWindows {
            objectName: "schermoOrientamento"
            enabled: !!pagina.monitor.nome && !pagina.occupato
            valore: String(pagina.monitor.gradi || 0)
            voci: [
                {valore:"0",testo:W.Style.label("Orizzontale", "Landscape")},
                {valore:"90",testo:W.Style.label("Verticale", "Portrait")},
                {valore:"180",testo:W.Style.label("Orizzontale capovolto", "Landscape (flipped)")},
                {valore:"270",testo:W.Style.label("Verticale capovolto", "Portrait (flipped)")}
            ]
            onScelto: function(value) { pagina.applica(pagina.modo,pagina.monitor.scala,value,W.Style.label("Orientamento", "Orientation")); }
        }
    }
    GruppoImpostazioni { testo: W.Style.label("Impostazioni correlate", "Related settings") }
    SchedaImpostazione {
        titolo: W.Style.label("Frequenza di aggiornamento", "Refresh rate")
        TendinaWindows {
            objectName: "schermoFrequenza"
            enabled: !!pagina.monitor.nome && pagina.frequenze.length > 0 && !pagina.occupato
            valore: Number(pagina.monitor.hz).toFixed(3)
            voci: pagina.frequenze
            onScelto: function(value) { pagina.applica(pagina.monitor.modoLarghezza+"x"+pagina.monitor.modoAltezza+"@"+value,pagina.monitor.scala,pagina.monitor.gradi,value+" Hz"); }
        }
    }
    SchedaImpostazione {
        visible: configurazione.monitors.length > 1
        titolo: W.Style.label("Disconnetti questo schermo", "Disconnect this display")
        PulsanteWindows {
            testo: W.Style.label("Disconnetti", "Disconnect")
            enabled: !!pagina.monitor.nome && !pagina.occupato && configurazione.monitors.filter(function(item) { return item.acceso !== false; }).length > 1
            onPremuto: configurazione.disable(pagina.monitor.nome)
        }
    }
    SchedaImpostazione {
        visible: pagina.monitor.acceso === false
        titolo: W.Style.label("Attiva questo schermo", "Enable this display")
        PulsanteWindows {
            testo: W.Style.label("Attiva", "Enable")
            enabled: !pagina.occupato
            onPremuto: pagina.applica(pagina.modo,pagina.monitor.scala,pagina.monitor.gradi,W.Style.label("Attiva schermo", "Enable display"))
        }
    }
    GruppoImpostazioni { testo: "Liquid" }
    EspansoreImpostazione {
        titolo: W.Style.label("Trasmissione dello schermo", "Screen casting")
        SchedaImpostazione {
            interna: true
            titolo: W.Style.label("Autorizzazioni di rete", "Network permissions")
            descrizione: pagina.esitoTrasmissione
            Row {
                spacing: 8
                PulsanteWindows {
                    testo: W.Style.label("Permetti", "Allow")
                    onPremuto: Core.Ipc.trasmettiApri()
                }
                PulsanteWindows {
                    testo: W.Style.label("Rimuovi", "Remove")
                    onPremuto: Core.Ipc.trasmettiChiudi()
                }
            }
        }
    }

}

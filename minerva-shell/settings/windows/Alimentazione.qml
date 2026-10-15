import QtQuick
import "../../core" as Core
import "../../windows11" as W
import ".." as S

PaginaWindows {
    id: pagina
    objectName: "impostazioniAlimentazioneWindows"
    briciole: [{testo: W.Style.label("Sistema", "System"), pagina: "w-sistema"},
        {testo: Core.SystemState.hasBattery ? W.Style.label("Alimentazione e batteria", "Power & battery")
                                          : W.Style.label("Alimentazione", "Power")}]
    S.PowerController { id: alimentazione }
    readonly property var risparmio: Core.Compositore.risparmio || ({})
    Component.onCompleted: Core.Compositore.chiediRisparmio()
    Connections {
        target: Core.Ipc
        function onSettingsChanged() { aggiornaRisparmio.restart(); }
    }
    Timer {
        id: aggiornaRisparmio
        interval: 400
        onTriggered: Core.Compositore.chiediRisparmio()
    }
    function minuti(key, maximum) {
        var current = Number(Core.Ipc.get("power." + key, 0));
        return [0,1,2,3,5,10,15,20,30,45,60,90,120,current].filter(function(value,index,list) {
            return list.indexOf(value) === index && (value <= maximum || value === current);
        }).sort(function(a,b) { return a-b; }).map(function(value) {
            return {valore:String(value),testo:value === 0 ? W.Style.label("Mai", "Never")
                : value + W.Style.label(value === 1 ? " minuto" : " minuti", value === 1 ? " minute" : " minutes")};
        });
    }
    SchedaImpostazione {
        objectName: "alimentazioneBatteria"
        visible: Core.SystemState.hasBattery
        titolo: Core.SystemState.batteryPercent + "%"
        descrizione: (Core.SystemState.batteryCharging ? W.Style.label("Collegato alla rete elettrica", "Plugged in")
                                                      : W.Style.label("Alimentazione a batteria", "On battery"))
            + (alimentazione.batteryTime ? " · " + alimentazione.batteryTime : "")
            + (alimentazione.batteryHealth ? " · " + W.Style.label("Capacità ", "Capacity ") + alimentazione.batteryHealth : "")
        Rectangle {
            width: 120
            height: 12
            radius: 3
            color: W.Style.edge
            Rectangle {
                height: parent.height
                width: parent.width * Math.max(0,Math.min(100,Core.SystemState.batteryPercent)) / 100
                radius: 3
                color: Core.SystemState.batteryPercent < 15 ? W.Style.critical : W.Style.accent
            }
        }
    }
    SchedaImpostazione {
        visible: alimentazione.profileError !== ""
        titolo: W.Style.label("Modalità risparmio energia non disponibile", "Power mode unavailable")
        descrizione: alimentazione.profileError
        PulsanteWindows {
            objectName: "alimentazioneRiprova"
            testo: W.Style.label("Riprova", "Retry")
            enabled: !alimentazione.busy
            onPremuto: alimentazione.refresh()
        }
    }
    SchedaImpostazione {
        titolo: W.Style.label("Modalità risparmio energia", "Power mode")
        descrizione: W.Style.label("Scegli l'equilibrio tra consumo energetico e prestazioni", "Choose the balance between energy use and performance")
        TendinaWindows {
            objectName: "alimentazioneProfilo"
            enabled: !alimentazione.busy && alimentazione.profiles.length > 0
            valore: alimentazione.profile
            width: Math.min(implicitWidth, Math.max(120,pagina.larghezza-90))
            voci: alimentazione.profiles.map(function(name) {
                var labels = {"power-saver":W.Style.label("Migliore efficienza energetica", "Best power efficiency"),
                    "balanced":W.Style.label("Bilanciato", "Balanced"),
                    "performance":W.Style.label("Massime prestazioni", "Best performance")};
                return {valore:name,testo:labels[name] || name};
            })
            onScelto: function(value) { alimentazione.setProfile(value); }
        }
    }
    EspansoreImpostazione {
        objectName: "alimentazioneTimeout"
        titolo: W.Style.label("Timeout schermo e sospensione", "Screen and sleep timeouts")
        descrizione: W.Style.label("I tempi valgono sia a batteria sia con alimentazione esterna", "These timeouts apply both on battery and when plugged in")
        aperto: true
        Repeater {
            model: [
                {key:"screenOffAfter",it:"Disattiva lo schermo dopo",en:"Turn my screen off after",max:120},
                {key:"suspendAfter",it:"Sospendi il dispositivo dopo",en:"Make my device sleep after",max:120}
            ]
            delegate: Timeout { required property var modelData; dato: modelData }
        }
    }
    SchedaImpostazione {
        visible: Core.SystemState.hasBattery
        titolo: W.Style.label("Controlli del coperchio", "Lid controls")
        TendinaWindows {
            objectName: "alimentazioneCoperchio"
            valore: Core.Ipc.get("power.lidAction","suspend")
            voci: [
                {valore:"suspend",testo:W.Style.label("Sospendi", "Sleep")},
                {valore:"lock",testo:W.Style.label("Blocca", "Lock")},
                {valore:"none",testo:W.Style.label("Non intervenire", "Do nothing")}
            ]
            onScelto: function(value) { Core.Ipc.setSetting("power.lidAction",value); }
        }
    }
    GruppoImpostazioni { testo: "Liquid" }
    EspansoreImpostazione {
        objectName: "alimentazioneLiquid"
        titolo: W.Style.label("Opzioni aggiuntive di Liquid", "Additional Liquid options")
        Repeater {
            model: [
                {key:"dimAfter",it:"Riduci la luminosità dopo",en:"Dim the screen after",max:30},
                {key:"lockAfter",it:"Blocca lo schermo dopo",en:"Lock the screen after",max:60}
            ].filter(function(item) { return item.key !== "dimAfter" || Core.SystemState.hasBrightness; })
            delegate: Timeout { required property var modelData; dato: modelData }
        }
        SchedaImpostazione {
            interna: true
            titolo: W.Style.label("Compressione delle app inattive", "Compress inactive apps")
            descrizione: W.Style.label("Riduce la memoria occupata dalle app Liquid nascoste", "Reduces memory used by hidden Liquid apps")
            S.ToggleSwitch {
                objectName: "alimentazioneMemoria"
                checked: Core.Ipc.get("memoria.respiro","delicata") === "delicata"
                onToggled: function(value) { Core.Ipc.setSetting("memoria.respiro",value ? "delicata" : "spenta"); }
            }
        }
        SchedaImpostazione {
            interna: true
            titolo: W.Style.label("Riduci gli effetti", "Reduce visual effects")
            descrizione: pagina.risparmio.attivo === undefined ? ""
                : pagina.risparmio.attivo ? W.Style.label("Effetti ridotti", "Effects reduced") : W.Style.label("Effetti completi", "Full effects")
            TendinaWindows {
                objectName: "alimentazioneEffetti"
                valore: Core.Ipc.get("power.risparmioEffetti","auto")
                voci: [
                    {valore:"auto",testo:W.Style.label("A batteria bassa", "On low battery")},
                    {valore:"sempre",testo:W.Style.label("Sempre", "Always")},
                    {valore:"mai",testo:W.Style.label("Mai", "Never")}
                ]
                onScelto: function(value) { Core.Ipc.setSetting("power.risparmioEffetti",value); }
            }
        }
        SchedaImpostazione {
            interna: true
            visible: Core.Ipc.get("power.risparmioEffetti","auto") === "auto"
            titolo: W.Style.label("Soglia di batteria per gli effetti ridotti", "Battery threshold for reduced effects")
            TendinaWindows {
                objectName: "alimentazioneSoglia"
                valore: String(Core.Ipc.get("power.risparmioSoglia",20))
                voci: [5,10,15,20,25,30,40,50,60,80,Core.Ipc.get("power.risparmioSoglia",20)].filter(function(value,index,list) {
                    return list.indexOf(value) === index;
                }).sort(function(a,b) { return a-b; }).map(function(value) { return {valore:String(value),testo:value+"%"}; })
                onScelto: function(value) { Core.Ipc.setSetting("power.risparmioSoglia",Number(value)); }
            }
        }
    }
    component Timeout: SchedaImpostazione {
        id: timeout
        property var dato: ({})
        objectName: "alimentazioneVoce-" + dato.key
        interna: true
        titolo: W.Style.it ? dato.it : dato.en
        TendinaWindows {
            objectName: "alimentazioneTempo-" + timeout.dato.key
            valore: String(Core.Ipc.get("power." + timeout.dato.key,0))
            voci: pagina.minuti(timeout.dato.key,timeout.dato.max)
            onScelto: function(value) { Core.Ipc.setSetting("power." + timeout.dato.key,Number(value)); }
        }
    }
}

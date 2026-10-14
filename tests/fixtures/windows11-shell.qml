import QtQuick
import Quickshell
import Quickshell.Io
import "@CORE@" as Core
import Quickshell.Wayland
ShellRoot {
    id:host
    property var realShell:null
    Component.onCompleted: {
        var component=Qt.createComponent("@SHELL@");
        if(component.status!==Component.Ready)throw new Error(component.errorString());
        realShell=component.createObject(host);
    }
    IpcHandler {
        target:"windows-runtime"
        function preset(name:string):void {Core.DesktopStyle.applica(name);}
        function panel(name:string):void {host.realShell.pannello(name);}
        function close():void {host.realShell.chiudiPannelli();}
        function menu(name:string):void {Core.Ipc.setSetting("windows11.menu",name);}
        function theme(name:string):void {Core.Ipc.setSetting("windows11.theme",name);}
        function audioState():string {
            function find(item, name) {
                if (item.objectName === name)
                    return item;
                for (var child of (item.children || [])) {
                    var found = find(child, name);
                    if (found)
                        return found;
                }
                return null;
            }
            var s = host.realShell ? host.realShell.scrivaniaAttiva() : null;
            var quick = s && s.windows ? find(s.windows.contentItem, "windowsQuickSettings") : null;
            return JSON.stringify({page: quick ? quick.page : "closed",
                audio: s && s.windows ? !!find(s.windows.contentItem, "windowsAudioPage") : false});
        }
        // Gli stimoli restano nella fixture; nessun comando nuovo nella sessione.
        function riva(kind:string, value:string):void {
            var s = host.realShell.scrivaniaAttiva();
            if (!s)
                return;
            var screenName = s.isola.screen.name;
            if (kind === "bordo")
                Core.Compositore.bordo(value, screenName);
            else if (kind === "angolo")
                Core.Compositore.angolo(value, screenName);
            else if (kind === "panoramica")
                Core.Compositore.panoramicaChiesta(screenName);
            else if (kind === "guida")
                host.realShell.mostraTasti(value === "apri");
            else if (kind === "diretta") {
                if (value === "barra")
                    s.isolaBarra.svela();
                else if (value === "notifiche")
                    s.isola.apriNotifiche(null);
                else if (s[value])
                    s[value].apri();
            }
        }
        function preference(name:string, value:string):void {
            Core.Ipc.setSetting(name, JSON.parse(value));
        }
        function status():string {
            var s=host.realShell ? host.realShell.scrivaniaAttiva():null;
            var islands = [];
            if (host.realShell) {
                for (var name in host.realShell.scrivanie) {
                    var desktop = host.realShell.scrivanie[name];
                    var panels = {};
                    for (var panel of ["centro", "cassetto", "isola", "stanze", "attivita"])
                        panels[panel] = {open: desktop[panel].aperto, visible: desktop[panel].visible};
                    islands.push({screen: name, panels: panels,
                        peek: desktop.stanze.sbirciata,
                        barVisible: desktop.isolaBarra.visible,
                        barRevealed: desktop.isolaBarra.svelata});
                }
            }
            return JSON.stringify({ready:Core.Ipc.impostazioniArrivate && s!==null,
                windowsMode:host.realShell ? host.realShell.barraWindows:false,
                screenName:s && s.windows && s.windows.screen ? s.windows.screen.name:"",
                bar:s && s.windows!==null && s.windows!==undefined,
                panel:s && s.windows ? s.windows.activePanel:"",
                wallpaper:Core.Wallpaper.current,
                liquid:s && s.sottomarino ? s.sottomarino.aperto:false,
                island:s && s.isola ? s.isola.aperto:false,
                rivaEnabled:Core.Riva.attiva,
                islands:islands,
                guide:host.realShell ? host.realShell.tastiAperti:false,
                consent:host.realShell ? host.realShell.consenso:false,
                rivaPrefs:Core.Ipc.get("riva",{}),
                islandPrefs:Core.Ipc.get("isola",{}),
                outputs:host.realShell ? Object.keys(host.realShell.scrivanie):[]});
        }
    }
}

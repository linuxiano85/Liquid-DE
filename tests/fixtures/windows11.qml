import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import "@W@" as W
import "@CORE@" as Core
import "@MENU@" as Menu
import "@SETTINGS@" as Settings
import "@THEME@" as Theme
ShellRoot {
    id:root
    Theme.LegaTema {}
    Core.WindowRules { effetto:Core.Vetro.effettoChiesto;effettoOpacita:Core.Ipc.get("windows.effettoOpacita",0.88) }
    property var volumeRequests: []
    property var wheelRequests: []
    TestCase {
        id: wheelInput
        name: "WindowsVolumeInput"
        when: false
    }
    property bool tracingMotion:false
    // L'ultima azione chiesta dalla barra (alimentazione, account): la shell
    // vera la esegue, qui si annota e basta.
    property string ultimaAzione:""
    // Quanto ci mette il menu Liquid aperto dallo Start: dalla richiesta a
    // quando è fermo al suo posto (salita finita), con l'orologio di Qt.
    property double liquidChiesto:0
    property double liquidPronto:0
    Connections {target:liquid;function onApertoChanged(){if(liquid.aperto){root.liquidChiesto=Date.now();root.liquidPronto=0;}}function onSalitaChanged(){if(liquid.aperto && liquid.emerso && liquid.salita>=1 && root.liquidPronto===0)root.liquidPronto=Date.now();}}
    property string ultimaSezione:""
    property var motionFrames:[]
    SystemClock { id: fixtureClock; precision: SystemClock.Minutes }
    property bool tracingViews: false
    property var viewFrames: []
    property string viewInterruption: ""
    Timer {
        id: viewInterruptTimer
        interval: 40
        onTriggered: {
            var start = root.find(bar.contentItem, "windowsStart");
            if (root.viewInterruption === "back" && start) start.showApps(false);
            if (root.viewInterruption === "disable") Core.Ipc.setSetting("desktop.animations", false);
            if (root.viewInterruption === "close") bar.close();
            root.recordViews();
        }
    }
    function viewState() {
        var start = find(bar.contentItem, "windowsStart");
        if (!start) return {available: false, animating: false};
        var navigation = find(start, "windowsStartNavigation");
        var pinned = find(start, "windowsPinnedArea");
        var list = find(start, "windowsListArea");
        var grid = find(start, "windowsPinnedGrid");
        var appList = find(start, "windowsAllApps");
        var input = find(start, "windowsSearchInput");
        return {
            time: Date.now(),
            available: true,
            layout: start.layout,
            rows: start.pinnedRows,
            page: start.page,
            pageSize: start.pageSize,
            recommendedY: start.recommendedY,
            pinnedBottom: grid.y + grid.height,
            allApps: start.allApps,
            listMode: start.listMode,
            query: start.query,
            progress: navigation.progress,
            animating: navigation.animating,
            pinnedVisible: pinned.visible,
            listVisible: list.visible,
            pinnedEnabled: pinned.enabled,
            listEnabled: list.enabled,
            pinnedOpacity: pinned.opacity,
            listOpacity: list.opacity,
            pinnedX: pinned.mapToItem(start, 0, 0).x,
            listX: list.mapToItem(start, 0, 0).x,
            tileIds: grid.children.filter(function(item) {
                return item.modelData && item.modelData.appId;
            }).map(function(item) {
                return item.modelData.appId;
            }),
            listCount: appList.count,
            listY: appList.contentY,
            selected: start.selectedIndex,
            gridFocus: grid.activeFocus,
            pinnedScrollY: pinned.contentY,
            selectedTiles: grid.children.filter(function(item) {
                return item.modelData && item.border && item.border.width > 0;
            }).map(function(item) { return item.modelData.appId; }),
            inputFocus: input.activeFocus,
            footerOpacity: find(start, "windowsStartFooter").opacity
        };
    }
    function recordViews() {
        if (tracingViews && viewFrames.length < 240)
            viewFrames = viewFrames.concat([viewState()]);
    }
    function motionState() {
        var area=find(bar.contentItem,"windowsPanelArea"),loader=find(bar.contentItem,"windowsPanelLoader");
        return {time:Date.now(),panel:bar.activePanel,rendered:bar.renderedPanel,progress:area.progress,presented:area.presented,animating:area.animating,enabled:area.enabled,loaded:!!loader.item,keyboard:bar.WlrLayershell.keyboardFocus===WlrKeyboardFocus.Exclusive,opacity:area.opacity};
    }
    function recordMotion() {if(tracingMotion && motionFrames.length<240)motionFrames=motionFrames.concat([motionState()]);}
    Connections {
        target: bar.contentItem.Window.window
        function onFrameSwapped() {
            root.recordMotion();
            root.recordViews();
        }
    }
    readonly property var testScreen:Quickshell.screens.find(function(screen){return screen.name==="HEADLESS-1";})
    Component.onCompleted: {
        Core.Strings.requestedLanguage="it";
        var names=["File","Browser","Editor","Terminale","Impostazioni","Calcolatrice","Foto","Musica","Video","Monitor","Custodia","Fucina"];
        var icons=["files","terminale","editor","terminale","settings","calcolatrice","viewer","media","media","monitor","custodia","fucina"];
        Core.Ipc.allApps=names.map(function(name,index) {return {appId:index===0 ? "test-files.desktop":"test-"+index+".desktop",name:name,exec:"true",icon:"@ROOT@/assets/icons/minerva-"+icons[index]+".svg",wmClass:index===0 ? "test-files":"test-"+index,categories:index===1 ? ["Network"]:["Utility","FileManager"]};});
        Core.Meteo.adesso={temperatura:22,codice:0,giorno:true,umidita:62,vento:8};
        Core.Meteo.giorni=[{data:"2026-10-10",codice:0,max:24,min:16},{data:"2026-10-11",codice:2,max:23,min:15},{data:"2026-10-12",codice:3,max:21,min:14},{data:"2026-10-13",codice:61,max:20,min:13},{data:"2026-10-14",codice:0,max:22,min:14}];
        Core.SystemState.networkName="Rete demo";
        Core.SystemState.networkStrength=85;
        Core.SystemState.wifiPresent=true;Core.SystemState.wifiOn=true;
    }
    Binding {target:Core.Notifications;property:"doNotDisturb";value:Core.Ipc.get("notifications.doNotDisturb",false)}
    W.Taskbar {id:bar;screen:root.testScreen;onLiquidMenuRequested:function(centro){liquid.commutaSopra(centro);}onActionRequested:function(a){root.ultimaAzione=a;}onSettingsRequested:function(s){root.ultimaSezione=s;}}
    W.Toasts {id:toasts;screen:root.testScreen}
    Menu.Sottomarino {id:liquid;screen:root.testScreen;margineBasso:60;conAlimentazione:true;onAlimentazione:function(a){root.ultimaAzione=a;}}
    Menu.WallpaperLayer {screen:root.testScreen}
    FloatingWindow {id:settings;visible:false;implicitWidth:1000;implicitHeight:700;color:Theme.Colors.window;title:"Aspetto di prova";Settings.Preset {id:appearance;anchors.fill:parent}}
    function find(item,name) {
        if(item.objectName===name)return item;
        for(var c of (item.children || [])){var r=find(c,name);if(r)return r;}
        return null;
    }
    function glyphColor(item,name) {
        if(!item)return "";
        if(item.name===name && item.color!==undefined)return String(item.color);
        for(var c of (item.children || [])){var color=glyphColor(c,name);if(color)return color;}
        return "";
    }
    function labelColor(item,label) {
        if(!item)return "";
        if(item.text===label && item.color!==undefined)return String(item.color);
        for(var c of (item.children || [])){var color=labelColor(c,label);if(color)return color;}
        return "";
    }
    function collect(item,result,base) {
        if(item.objectName && item.visible && item.width>0 && item.height>0) {
            var p=item.mapToItem(base,item.width/2,item.height/2);
            result[item.objectName]={x:p.x,y:p.y,width:item.width,height:item.height,text:typeof item.text==="string" ? item.text:""};
        }
        if(item.visible && item.modelData && item.modelData.value!==undefined && item.parent && item.parent.objectName) {
            var chip=item.mapToItem(base,item.width/2,item.height/2);
            result[item.parent.objectName+"-"+item.modelData.value]={x:chip.x,y:chip.y,width:item.width,height:item.height};
        }
        for(var c of (item.children || []))collect(c,result,base);
    }
    IpcHandler {
        target:"windows-test"
        function wifiFocus(ssid:string): void {
            var page = root.find(bar.contentItem, "windowsWifiPage");
            page.focusNetwork(page.entries.findIndex(function(n) { return n.ssid === ssid; }));
        }
        function wifiType(secret:string): void {
            var input = root.find(bar.contentItem, "windowsWifiPassword");
            input.text = secret;
            input.textEdited();
        }
        function wifiState(): string {
            var page = root.find(bar.contentItem, "windowsWifiPage");
            if (!page)
                return JSON.stringify({available: false});
            var controller = root.find(page, "wifiController");
            var input = root.find(page, "windowsWifiPassword");
            var focus = bar.contentItem.Window.window.activeFocusItem;
            var selectedRow = root.find(page, "windowsWifiNetwork-Rete salvata");
            return JSON.stringify({available: true, count: page.networkCount, plainTooltip: selectedRow ? selectedRow.tooltipTextFormat === Text.PlainText : false, ssids: page.entries.map(function(n) { return n.ssid; }), active: page.entries.filter(function(n) { return n.active; }).map(function(n) { return n.ssid; }), connecting: page.connecting, passwordSsid: page.passwordSsid, inputEmpty: page.passwordText === "", secretEmpty: controller._wifiSecret === "", error: page.error, masked: input ? input.echoMode === TextInput.Password : false, focus: focus ? focus.objectName : ""});
        }
        function bluetoothFocus(identity:string): void {
            var page = root.find(bar.contentItem, "windowsBluetoothPage");
            page.focusDevice(page.entries.findIndex(function(entry) { return entry.identity === identity; }));
        }
        function bluetoothMockPower(): void {
            var page = root.find(bar.contentItem, "windowsBluetoothPage");
            page.changePower = function(on) {
                page.adapters.forEach(function(adapter) { adapter.enabled = on; });
            };
        }
        function bluetoothState(): string {
            var page = root.find(bar.contentItem, "windowsBluetoothPage");
            if (!page)
                return JSON.stringify({available: false});
            var connected = {};
            var batteries = {};
            page.entries.forEach(function(entry) {
                connected[entry.identity] = entry.connected;
                batteries[entry.identity] = entry.battery;
            });
            return JSON.stringify({available: true, count: page.deviceCount, powered: page.powered, pending: page.pendingPath, notice: page.notice, connected: connected, batteries: batteries, focus: bar.contentItem.Window.window.activeFocusItem ? bar.contentItem.Window.window.activeFocusItem.objectName : ""});
        }
        function quickTileState(wifi:bool, bluetooth:bool): void {
            Core.SystemState.wifiOn = wifi;
            Core.SystemState.bluetoothOn = bluetooth;
        }
        function quickRadios(): string {
            return JSON.stringify({wifi: Core.SystemState.wifiOn, bluetooth: Core.SystemState.bluetoothOn});
        }
        function volumeSetup(level:int, ceiling:int): void {
            var slider = root.find(bar.contentItem, "windowsVolumeSlider");
            slider.to = ceiling;
            slider.value = level;
            root.volumeRequests = [];
            slider.changeVolume = function(percent) {
                root.volumeRequests = root.volumeRequests.concat([percent]);
            };
        }
        function volumePress(position:real): void {
            var slider = root.find(bar.contentItem, "windowsVolumeSlider");
            wheelInput.mouseClick(slider, slider.leftPadding + slider.availableWidth * position, slider.height / 2);
        }
        function volumeState(): string {
            var slider = root.find(bar.contentItem, "windowsVolumeSlider");
            var fill = root.find(slider, "windowsVolumeExtraFill");
            var range = root.find(slider, "windowsVolumeExtraRange");
            var ink = root.find(slider, "windowsVolumeHandleInk");
            var percent = root.find(slider, "windowsVolumePercent");
            return JSON.stringify({
                value: slider.value, maximum: slider.to,
                amplified: slider.amplified, normalFraction: slider.normalFraction,
                extraWidth: fill.width, extraVisible: fill.visible,
                rangeWidth: range.width, rangeVisible: range.visible,
                handleColor: String(ink.color), extraColor: String(fill.color),
                text: percent.text, textColor: String(percent.color),
                requests: root.volumeRequests,
                accessible: slider.Accessible.name
            });
        }
        function wheelSetup(volume:int, muted:bool): void {
            var status = root.find(bar.contentItem, "windowsStatusButton");
            status.volume = volume;
            status.muted = muted;
            root.wheelRequests = [];
            // Si sostituisce solo l'uscita verso PipeWire. L'evento attraversa
            // i MouseArea veri, senza scrivere sul dispositivo dell'utente.
            status.changeVolume = function(delta) {
                root.wheelRequests = root.wheelRequests.concat([delta]);
                var decision = Core.SystemState.decidiVolume(status.volume + delta, status.muted, 100);
                status.volume = decision.volume;
                if (decision.smuta)
                    status.muted = false;
            };
        }
        function wheelInputAt(name:string, deltaX:int, deltaY:int): void {
            var target = root.find(bar.contentItem, name);
            wheelInput.mouseMove(target, target.width / 2, target.height / 2);
            wheelInput.mouseWheel(target, target.width / 2, target.height / 2, deltaX, deltaY, Qt.NoButton);
        }
        function wheelState(): string {
            var status = root.find(bar.contentItem, "windowsStatusButton");
            return JSON.stringify({volume: status.volume, muted: status.muted, requests: root.wheelRequests});
        }
        function systemState(snapshot:string):void {
            var status = root.find(bar.contentItem, "windowsStatusButton");
            var values = JSON.parse(snapshot);
            var names = ["batteryPercent", "batteryCharging", "volume", "muted", "strength", "networkName"];
            if (Object.keys(values).length === 0) {
                for (var key of names) {
                    (function(name) {
                        status[name] = Qt.binding(function() { return Core.SystemState[name === "strength" ? "networkStrength" : name]; });
                    })(key);
                }
                status.wired = Qt.binding(function() { return Core.SystemState.networkWired; });
                status.connected = Qt.binding(function() { return Core.SystemState.networkConnected; });
                status.energySaving = Qt.binding(function() { return Core.Compositore.risparmio.profiloRisparmio === true; });
                return;
            }
            for (var name in values)
                status[name] = values[name];
        }
        function clockState(snapshot:string):void {
            var clock = root.find(bar.contentItem, "windowsClockButton");
            var values = JSON.parse(snapshot);
            if (Object.keys(values).length === 0) {
                clock.date = Qt.binding(function() { return fixtureClock.date; });
                clock.format24 = Qt.binding(function() { return Core.Ipc.get("clock.format24", true); });
                clock.unread = Qt.binding(function() { return Core.Notifications.unread; });
                clock.quiet = Qt.binding(function() { return Core.Notifications.inSilenzio; });
                clock.locale = Qt.binding(function() { return Qt.locale(W.Style.it ? "it_IT" : "en_GB"); });
                return;
            }
            for (var name in values)
                clock[name] = name === "locale" ? Qt.locale(values[name])
                    : name === "date" ? new Date(values[name]) : values[name];
        }
        function statusIndicators():string {
            var status = root.find(bar.contentItem, "windowsStatusButton");
            var clock = root.find(bar.contentItem, "windowsClockButton");
            return JSON.stringify({volume: status.volumeIcon, network: status.networkIcon,
                battery: status.batteryState, fraction: status.batteryFraction,
                batteryColor: String(status.batteryColor), hasBattery: status.hasBattery,
                statusWidth: status.width, statusTooltip: status.tooltip,
                time: clock.timeText, date: clock.dateText, notification: clock.notificationIcon,
                notificationColor: String(clock.notificationColor), unread: clock.unread,
                quiet: clock.quiet, clockWidth: clock.width, clockTooltip: clock.tooltip,
                rawBattery: Core.SystemState.batteryPercent, rawVolume: Core.SystemState.volume,
                rawMuted: Core.SystemState.muted});
        }
        function open(name:string):void {bar.toggle(name);}
        function catalog():string {return JSON.stringify(Core.Apps.all);}
        function liquidOpen():void {bar.close();liquid.apri("");}
        function liquidClose():void {liquid.chiudi();}
        function close():void {bar.close();}
        function motionBegin(name:string):void {root.motionFrames=[];root.tracingMotion=true;bar.toggle(name);root.recordMotion();}
        function motionClose():void {bar.close();root.recordMotion();}
        function motionBurst(name:string):void {for(var i=0;i<8;i++){bar.toggle(name);bar.close();}bar.toggle(name);root.recordMotion();}
        function motionImmediateClose():void {bar.closeImmediately();root.recordMotion();}
        function motionStop():string {root.tracingMotion=false;return JSON.stringify({state:root.motionState(),frames:root.motionFrames});}
        function viewTraceBegin():void {
            root.viewFrames = [];
            root.tracingViews = true;
            root.recordViews();
        }
        function viewTraceStop():string {
            root.tracingViews = false;
            return JSON.stringify({state: root.viewState(), frames: root.viewFrames});
        }
        function viewStatus():string { return JSON.stringify(root.viewState()); }
        function viewInterrupt(action:string):void {
            root.viewFrames = [];
            root.tracingViews = true;
            root.viewInterruption = action;
            root.find(bar.contentItem, "windowsStart").showApps(true);
            root.recordViews();
            viewInterruptTimer.restart();
        }
        function theme(name:string):void {Core.Ipc.setSetting("windows11.theme",name);}
        function menu(name:string):void {Core.Ipc.setSetting("windows11.menu",name);}
        function preset(name:string):void {liquid.chiudi();Core.DesktopStyle.applica(name);}
        function preference(path:string,value:string):string {
            var parsed = JSON.parse(value).value;
            var before = Core.Ipc.get(path, null);
            var sent = Core.Ipc.setSetting(path, parsed);
            return JSON.stringify({path: path, requested: parsed, before: before, after: Core.Ipc.get(path, null), sent: sent});
        }
        function settingsOpen(open:bool):void {bar.close();liquid.chiudi();settings.visible=open;}
        function settingsReveal(query:string):void {appearance.revealSetting(query);}
        function toast():void {Core.Notifications.daMinerva("Progetto salvato","I documenti sono aggiornati.");}
        function aggiungiApp(count: int): void {
            var original = Core.Ipc.allApps.slice();
            var more = [];
            for (var i = original.length; i < count; i++) {
                var app = Object.assign({}, original[0]);
                app.appId = "extra-" + i + ".desktop";
                app.name = "Applicazione " + i;
                more.push(app);
            }
            Core.Ipc.allApps = original.concat(more);
            Core.Ipc.setSetting("launcher.fixedApps", Core.Ipc.allApps.map(function(a) { return a.appId; }));
        }
        function prepare():void {
            Core.Ipc.setSettings({"launcher.fixedApps":Core.Ipc.allApps.map(function(a){return a.appId;}),"dock.pinned":["test-files.desktop"],"desktop.animations":false,"windows.tilingMode":"colonne","windows.tilingLayout":"uguale","weather.name":"Città demo","weather.enabled":true});
        }
        function effectState():string {
            return JSON.stringify({requested:Core.Vetro.effettoChiesto,effective:Core.Vetro.effetto,
                alpha:Theme.Colors.window.a,acrylic:W.Style.acrylic,
                barAlpha:W.Style.barra.a,widgetsAlpha:W.Style.widgetsSurface.a});
        }
        function scrollState(name:string):string {
            var item=root.find(bar.contentItem,name);
            return JSON.stringify(item && item.bersaglio ? {visible:item.visible,
                x:item.bersaglio.contentX,y:item.bersaglio.contentY,
                maxX:item.bersaglio.contentWidth-item.bersaglio.width,
                maxY:item.bersaglio.contentHeight-item.bersaglio.height}:{});
        }
        function scrollTo(name:string,control:string):void {
            var barItem=root.find(bar.contentItem,name);
            var target=root.find(bar.contentItem,control);
            if(!barItem || !target)return;
            var flick=barItem.bersaglio;
            var point=target.mapToItem(flick,0,0);
            flick.contentY=Math.max(flick.originY,Math.min(flick.originY+flick.contentHeight-flick.height,
                flick.contentY+point.y-flick.height/2));
        }
        function newsImages():string {
            var result=[];
            function visit(item) {
                if(item.source!==undefined && String(item.source).indexOf("notizia.png")>=0)
                    result.push({source:String(item.source),status:item.status});
                for(var child of item.children || [])visit(child);
            }
            visit(bar.contentItem);
            return JSON.stringify(result);
        }
        function scrollTop(name:string):void {
            var item=root.find(bar.contentItem,name);
            if(item && item.bersaglio)item.bersaglio.contentY=item.bersaglio.originY;
        }
        function quickState(): string {
            var quick = root.find(bar.contentItem, "windowsQuickSettings");
            var audio = root.find(bar.contentItem, "windowsAudioPage");
            var focus = bar.contentItem.Window.window.activeFocusItem;
            return JSON.stringify({
                page: quick ? quick.page : "closed",
                focus: focus ? focus.objectName : "",
                defaultSink: audio ? audio.defaultSink : "",
                count: audio ? audio.deviceCount : 0,
                scrollY: audio ? audio.scrollY : 0,
                scrollMaximum: audio ? audio.scrollMaximum : 0,
                loading: audio ? audio.loading : false,
                selecting: audio ? audio.selecting : false,
                error: audio ? audio.audioError : ""
            });
        }
        // Il menu di Win+X (clic destro su Start) e la scelta di una voce,
        // anche dentro «Arresta o disconnetti» (12 ottobre 2026).
        function startContext(): string {
            bar.startContext();
            return "ok";
        }
        // Le voci arrivano quando il compositore ha detto dov'è il puntatore.
        function menuX(): string {
            for (var object of bar.data) {
                if (object.objectName === "windowsTaskbarContextMenu")
                    return JSON.stringify({visible: object.visible, items: object.items.map(function(item) {
                        return {label: item.label || "", action: item.action || "",
                                children: (item.children || []).map(function(c) { return {label: c.label, action: c.action}; })};
                    })});
            }
            return JSON.stringify({visible: false, items: []});
        }
        function sceltaMenu(action: string): string {
            for (var object of bar.data) {
                if (object.objectName === "windowsTaskbarContextMenu") {
                    // Come un clic vero: si sceglie e il menu si chiude.
                    object.triggered(action);
                    object.close();
                    return "ok";
                }
            }
            return "assente";
        }
        function startAccount(): string {
            var b = root.find(bar.contentItem, "windowsStartAccount");
            return JSON.stringify(b ? {testo: b.text, avatar: b.avatar} : null);
        }
        function statusContext(): string {
            for (var object of bar.data) {
                if (object.objectName === "windowsTaskbarContextMenu")
                    return JSON.stringify({visible: object.visible, above: object.growUp, bottom: object.menuY, actions: object.items.map(function(item) { return item.action; })});
            }
            return JSON.stringify({visible: false, actions: []});
        }
        function mixerState(): string {
            var audio = root.find(bar.contentItem, "windowsAudioPage");
            var mixer = root.find(bar.contentItem, "windowsAudioMixer");
            return JSON.stringify({available: !!mixer, count: mixer ? mixer.streamCount : 0,
                boundStreams: Pipewire.nodes.values.filter(function(node) { return node.isStream && node.ready; }).length,
                streams: audio ? audio.playbackStreams.map(function(node) {
                    return {id: node.id, ready: node.ready, name: node.name,
                        label: node.ready ? String(node.properties["application.name"] || "") : "",
                        volume: node.ready ? node.audio.volume : -1,
                        muted: node.ready ? node.audio.muted : false};
                }) : []});
        }
        function mixerReveal(): void {
            var list = root.find(bar.contentItem, "windowsAudioOutputList");
            list.positionViewAtEnd();
        }
        function mixerFocus(identity:string): void {
            var slider = root.find(bar.contentItem, "windowsAudioStreamVolume-" + identity);
            slider.forceActiveFocus(Qt.TabFocusReason);
        }
        function status():string {
            var controls={};collect(bar.contentItem,controls,bar.contentItem);
            var settingsControls={};collect(appearance,settingsControls,settings.contentItem);
            var start=find(bar.contentItem,"windowsStart") || find(bar.contentItem,"windowsSearchPanel"),overview=find(bar.contentItem,"windowsTaskView"),tray=find(bar.contentItem,"windowsTray");
            var style={chosen:String(W.Style.accentBase),accent:String(W.Style.accent),onAccent:String(W.Style.accentForeground),ink:String(W.Style.accentInk),field:String(W.Style.field),text:String(W.Style.text),muted:String(W.Style.startMuted),surface:String(W.Style.surface),base:String(W.Style.base),start:String(W.Style.startSurface),footer:String(W.Style.startFooter),taskbar:String(W.Style.taskbarSurface),indicator:String(W.Style.accentIndicator),tinted:W.Style.accentOnStart,wifiGlyph:glyphColor(find(bar.contentItem,"windowsQuick-wifi"),"wifi"),customLabel:labelColor(find(appearance,"windowsAccentCustom"),"Personalizzato"),settingsBase:String(Theme.Colors.raised),customOpen:appearance.coloreAperto==="windowsAccent",actualStart:find(bar.contentItem,"windowsStartSurface") ? String(find(bar.contentItem,"windowsStartSurface").color):""};
            return JSON.stringify({focoBarra:(function(){var r={};["windowsStartButton","windowsSearchButton","windowsOverviewButton"].forEach(function(n){var b=find(bar.contentItem,n);r[n]=b?{fuoco:b.activeFocus,contorno:b._focoVisibile}:null;});return r;})(),liquidMenu:(function(){var s=find(liquid.contentItem,"liquidMenuScafo");var p=find(liquid.contentItem,"liquidMenuPower");var b=find(bar.contentItem,"windowsStartButton");var q=find(liquid.contentItem,"liquidMenuPeriscopio");return s&&b?{centro:s.x+s.width/2,start:b.mapToItem(null,b.width/2,0).x,alimentazione:!!p&&p.visible,larghezza:s.width,emerso:liquid.emerso,salita:liquid.salita,periscopio:!!q&&q.visible&&q.scale>0,ms:root.liquidPronto>0 ? root.liquidPronto-root.liquidChiesto:-1}:null;})(),ultimaAzione:root.ultimaAzione,ultimaSezione:root.ultimaSezione,ready:Core.Ipc.impostazioniArrivate,colors:style,accentSwitch:{enabled:find(appearance,"windowsAccentOnStart").enabled,checked:find(appearance,"windowsAccentOnStart").checked},screenName:bar.screen ? bar.screen.name:"",screenX:bar.screen ? bar.screen.x:0,screenY:bar.screen ? bar.screen.y:0,screenWidth:bar.width,screenHeight:bar.height,hoverPreview:bar.hoverPreview,panel:bar.activePanel,theme:W.Style.dark,liquid:liquid.aperto,windows:Core.Windows.all,groups:bar.taskGroups,controls:controls,style:Core.DesktopStyle.attuale,settings:Core.Ipc.settings,settingsControls:settingsControls,openMs:bar.lastOpenMs,cacheActive:Core.Anteprime.active,selected:start ? start.selectedIndex:-1,apps:start ? start.apps.map(function(a){return a.appId;}):[],fileResults:start ? start.files:[],recent:start ? start.recent:[],desktops:overview ? overview.desktops:[],desktopsFocus:overview ? overview.desktopsFocus:false,selectedDesktop:overview ? overview.selectedDesktop:-1,selectedWindow:overview ? overview.selectedWindow:-1,dragging:overview ? overview.draggingHandler!==null:false,toastCount:toasts.items.length,trayCount:tray ? tray.entries.length:0,trayMenuOpen:tray ? tray.menuOpen:false,trayMenuCount:tray ? tray.menuEntries.length:0,wallpaper:Core.Wallpaper.current});
        }
    }
}

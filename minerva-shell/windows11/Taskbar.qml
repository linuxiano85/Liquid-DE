import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core" as Core
import "../ui" as Ui
import "../spine" as Spine
import "../menu" as Menu
PanelWindow {
    id: bar
    objectName:"windowsTaskbar"
    anchors {bottom:true;left:true;right:true}
    implicitHeight:screen ? screen.height:1080
    exclusiveZone:48
    color:"transparent"
    WlrLayershell.namespace:"liquid-windows11"
    WlrLayershell.layer:activePanel!=="" ? WlrLayer.Overlay:WlrLayer.Top
    WlrLayershell.keyboardFocus:activePanel!=="" && !hoverPreview ? WlrKeyboardFocus.Exclusive:WlrKeyboardFocus.None
    mask:Region {item:bar.activePanel!=="" && !bar.hoverPreview ? backdrop:strip;Region {item:bar.activePanel!=="" ? panelArea:null;intersection:Intersection.Combine}}
    readonly property string searchPresentation: Core.Ipc.get("windows11.taskbarSearch", "icon")
    readonly property bool leftAligned: Core.Ipc.get("windows11.taskbarAlignment", "center") === "left"
    readonly property var taskGroups:tasks.entries
    property string activePanel:""
    property string quickPage: "main"
    property string renderedPanel:""
    property var renderedGroup:null
    WindowModel {id:previewModel}
    onRenderedGroupChanged:previewModel.update(renderedGroup ? renderedGroup.windows:[])
    property real renderedCenter:0
    property var selectedGroup:null
    property real groupCenter:0
    readonly property var registry:({start:true,search:true,control:true,calendar:true,notifications:true,power:true,weather:true,schermata:true,screenshot:true,minimized:true,overview:true})
    readonly property var panelSpec: {
        var size={start:[640,726,"center"],search:[640,726,"center"],calendar:[360,640,"right"],control:[360,380+(Core.Media.cQualcosa ? 124 : 0),"right"],windows:[Math.min(760,(renderedGroup ? renderedGroup.windows.length:1)*220),204,"group"],appmenu:[360,160,"group"],power:[320,276,"right"],weather:[760,height-72,"left"],screenshot:[360,200,"right"],tray:[176,Math.ceil(trayIcons.entries.length/4)*40+24,"group"],overview:[width-48,height-104,"center"]};
        if (Core.Ipc.get("windows11.startExperience", "modern") === "modern")
            size.start = [768, 780, "center"];
        return size[renderedPanel] || size.control;
    }
    property double _paintStarted:-1
    property int lastOpenMs:-1
    onActivePanelChanged: {
        _paintStarted=activePanel!=="" ? Date.now():-1;
        if(activePanel!=="") {
            var replacing=renderedPanel!=="" && renderedPanel!==activePanel;
            renderedGroup=selectedGroup;renderedCenter=groupCenter;renderedPanel=activePanel;
            if(replacing)panelArea.replay();
        }
    }
    onSelectedGroupChanged:if(activePanel!=="")renderedGroup=selectedGroup
    onGroupCenterChanged:if(activePanel!=="")renderedCenter=groupCenter
    property bool hoverPreview:false
    property var hoverGroup:null
    property real hoverCenter:0
    Timer {id:previewTimer;interval:550;onTriggered:if((bar.activePanel==="" || (bar.hoverPreview && bar.activePanel==="windows")) && bar.hoverGroup && bar.hoverGroup.windows.length>0){bar.hoverPreview=true;bar.selectedGroup=bar.hoverGroup;bar.groupCenter=bar.hoverCenter;bar.activePanel="windows";}}
    readonly property rect screenRect:Qt.rect(0,height-48,width,48)
    readonly property int barHeight:48
    /// Il menu «Liquid» al posto dello Start: `centro` è il centro del
    /// pulsante Start, per aprirlo lì sopra.
    signal liquidMenuRequested(real centro)
    signal overviewRequested()
    signal commandRequested(string command)
    signal settingsRequested(string section)
    signal actionRequested(string action)
    signal screenshotRequested()
    Menu.ContextMenu {
        id: taskbarMenu
        objectName: "windowsTaskbarContextMenu"
        screen: bar.screen
        windowsAppearance: true
        onTriggered: function(action) {
            if (action === "audio-mixer")
                bar.openAudio();
            else if (action === "audio-settings")
                bar.settingsRequested("audio");
            else if (action === "taskbar-settings")
                bar.settingsRequested("w-barra");
            else if (action === "terminal")
                bar.commandRequested("terminal");
            else if (action === "monitor")
                bar.commandRequested("monitor");
            // «Arresta o disconnetti»: un clic esegue, come nello Start e
            // in Windows. Prima queste voci aprivano un terzo pannello con la
            // conferma «Premi ancora» (il manutentore, 12 ottobre 2026: «ci sono
            // problemi con il tasto per spegnimento riavvio»), e «Sospendi»
            // passava da un'altra strada.
            else if (["esci", "sospendi", "spegni", "riavvia"].indexOf(action) >= 0)
                bar.actionRequested(action);
            else
                bar.commandRequested(action);
        }
    }
    function startContext() {
        close();taskbarMenu.openAtCursor([
            {label:Style.label("Gestione attività","Task Manager"),icon:"monitor",action:"monitor"},
            {label:Style.label("Impostazioni","Settings"),icon:"settings",action:"settings"},
            {label:Style.label("Esplora file","File Explorer"),icon:"folder",action:"files"},
            {label:Style.label("Terminale","Terminal"),action:"terminal"},
            {separator:true},
            {label:Style.label("Arresta o disconnetti","Shut down or sign out"),icon:"power",children:[
                {label:Style.label("Disconnetti","Sign out"),action:"esci"},
                {label:Style.label("Sospendi","Sleep"),action:"sospendi"},
                {label:Style.label("Arresta il sistema","Shut down"),action:"spegni"},
                {label:Style.label("Riavvia il sistema","Restart"),action:"riavvia"}
            ]},
            {label:Style.label("Desktop","Desktop"),action:"windows-desktop"}
        ]);
    }
    function close() {hoverPreview=false;previewTimer.stop();activePanel="";selectedGroup=null;}
    function closeImmediately() {close();panelArea.hideImmediately();}
    function applyQuickPage() {
        if (activePanel === "control" && renderedPanel === "control" && panelLoader.item)
            panelLoader.item.page = quickPage;
    }
    function openAudio() {
        // Anche con un altro popup già aperto si deve arrivare alla pagina
        // audio: toggle("control") la chiuderebbe alla seconda pressione.
        quickPage = "audio";
        hoverPreview = false;
        previewTimer.stop();
        selectedGroup = null;
        activePanel = "control";
        applyQuickPage();
    }
    function toggle(name) {
        hoverPreview = false;
        previewTimer.stop();
        name = ({apps: "start", notifications: "calendar", minimized: "tasks", schermata: "screenshot"})[name] || name;
        if (name === "start" && Core.Ipc.get("windows11.menu", "windows11") === "liquid") {
            close();
            liquidMenuRequested(startButton.mapToItem(null, startButton.width / 2, 0).x);
            return;
        }
        if (name === "tasks")
            name = "overview";
        if (name === "control")
            quickPage = "main";
        activePanel = activePanel === name ? "" : name;
        applyQuickPage();
        if (activePanel !== "windows")
            selectedGroup = null;
    }
    function selectWindow(w) {
        var live=Core.Windows.all.find(function(l){return l.address===w.address && l.birth===w.birth;});
        if (live) {
            Core.Windows.focus(live.address);
        } else {
            console.warn("[MINERVA][ANTEPRIME] Finestra non più disponibile: " + w.address + ":" + w.birth);
        }
        close();
    }
    function activate(g,where) {
        hoverPreview=false;previewTimer.stop();
        if(g.windows.length===0) {tasks.launch(g,false);close();}
        else if(g.windows.length===1) {
            var w=g.windows[0];
            if(Core.Windows.activeAddress===w.address && !w.minimized) Core.Windows.minimize(w.address);
            else Core.Windows.focus(w.address);
            close();
        } else {selectedGroup=g;groupCenter=where;activePanel="windows";}
    }
    function showContext(g,where) {hoverPreview=false;previewTimer.stop();selectedGroup=g;groupCenter=where;activePanel="appmenu";}
    onVisibleChanged:if(!visible)closeImmediately()
    readonly property string menuPreference:Core.Ipc.get("windows11.menu","windows11")
    onMenuPreferenceChanged:close()
    readonly property var watched:selectedGroup && activePanel==="windows" ? selectedGroup.windows.map(function(w){return w.address;}):[]
    onWatchedChanged:Core.Anteprime.watch("windows11-"+(screen ? screen.name:""),watched)
    Component.onDestruction:Core.Anteprime.watch("windows11-"+(screen ? screen.name:""),null)
    Connections {target:Core.Windows;function onAllChanged() {
        if(!bar.selectedGroup)return;
        Qt.callLater(function(){if(!bar.selectedGroup)return;var updated=tasks.entries.find(function(g){return g.id===bar.selectedGroup.id;});if(updated)bar.selectedGroup=updated;else bar.close();});
    }}
    HoverHandler {id:wholeHover}
    Timer {interval:400;running:bar.hoverPreview && !wholeHover.hovered;onTriggered:bar.close()}
    Connections {target:Core.Compositore;function onBloccoCambiato(locked){if(locked)bar.closeImmediately();}}
    TaskModel {id:tasks;output:bar.screen ? bar.screen.name:""}
    SystemClock {id:clock;precision:SystemClock.Minutes}
    Item {id:backdrop;anchors.fill:parent
        MouseArea {anchors.fill:parent;visible:bar.activePanel!=="";onClicked:bar.close()}
    }
    Flyout {
        id:panelArea
        HoverHandler {id:panelHover}
        objectName:"windowsPanelArea"
        opened:bar.activePanel!==""
        onDismissed:{if(bar.activePanel===""){bar.renderedPanel="";bar.renderedGroup=null;}}
        x:bar.renderedPanel === "overview" ? 0
            : bar.leftAligned && (bar.renderedPanel === "start" || bar.renderedPanel === "search") ? 12
            : bar.panelSpec[2]==="center" ? Math.max(12,(bar.width-width)/2)
            : (bar.panelSpec[2]==="group" ? Math.max(12,Math.min(bar.width-width-12,bar.renderedCenter-width/2)):(bar.panelSpec[2]==="left" ? 12:bar.width-width-12))
        y:bar.renderedPanel === "overview" ? 0 : bar.height-48-12-height
        width:bar.renderedPanel === "overview" ? bar.width : Math.min(bar.width-24,bar.panelSpec[0])
        height:bar.renderedPanel === "overview" ? bar.height-48 : Math.min(bar.height-72,bar.panelSpec[1])
        Keys.onEscapePressed: {
            if (bar.renderedPanel === "control" && panelLoader.item && panelLoader.item.goBack())
                return;
            bar.close();
        }
        // I vuoti tra i controlli appartengono al pannello, non allo sfondo
        // della barra che chiude i popup. La panoramica gestisce il suo fondo.
        MouseArea {
            objectName: "windowsFlyoutSurface"
            anchors.fill: parent
            enabled: bar.renderedPanel !== "overview"
            acceptedButtons: Qt.AllButtons
        }
        Shadow {objectName:"windowsPanelShadow"}
        Loader {
            id:panelLoader;objectName:"windowsPanelLoader";anchors.fill:parent;active:panelArea.presented
            sourceComponent:({start:startPanel,search:searchPanel,control:quickPanel,calendar:calendarPanel,windows:windowsPanel,appmenu:appMenuPanel,weather:weatherPanel,screenshot:screenshotPanel,tray:trayIcons.panel,overview:overviewPanel})[bar.renderedPanel] || quickPanel
            onLoaded: {
                if (!bar.hoverPreview)
                    panelArea.forceActiveFocus();
                if (item.begin)
                    item.begin("");
                bar.applyQuickPage();
            }
        }
    }
    // Le azioni del piede dello Start (`StartMenu.piccolo`): alimentazione e
    // account eseguono subito, come in Windows 11; «accesso» e «utente»
    // aprono le Impostazioni.
    function azioneStart(a) {
        bar.close();
        if (["sospendi","spegni","riavvia","blocca","esci"].indexOf(a) >= 0) bar.actionRequested(a);
        else bar.settingsRequested(a === "w-home" ? "w-home" : a === "accesso" ? "accesso" : "utente");
    }
    // Il percorso passa come dato IPC, mai come comando interpolato nella shell.
    Component {
        id: startPanel
        StartMenu {
            onCloseRequested: bar.close()
            onActionRequested: function(a) { bar.azioneStart(a); }
            onFolderRequested: function(path) {
                Core.Ipc.apriOChiedi(path);
                bar.close();
            }
        }
    }
    // Cerca ha il suo pannello, come l'ultima Windows 11 (`SearchPanel.qml`):
    // l'ingranaggio apre le impostazioni della ricerca (pagina Preset).
    Component {
        id: searchPanel
        SearchPanel {
            onCloseRequested: bar.close()
            onActionRequested: function(a) {
                bar.close();
                bar.settingsRequested(a);
            }
        }
    }
    Component {id:quickPanel;QuickSettings {onSettingsRequested:function(s){bar.close();bar.settingsRequested(s);}}}
    Component {id:calendarPanel;Calendar {}}
    Component {id:windowsPanel;Rectangle {
        color:Style.pannello;radius:8;border.color:Style.edge
        Flickable {id:previewScroll;anchors.fill:parent;anchors.margins:12;clip:true;contentWidth:previews.width;contentHeight:height;flickableDirection:Flickable.HorizontalFlick
            Row {id:previews;spacing:8
                Repeater {model:previewModel;delegate:Button {
                    id:preview;required property string rowJson
                    readonly property var modelData:JSON.parse(rowJson)
                    objectName:"windowsPreview-"+modelData.address
                    width:200;height:178;tooltip:modelData.title
                    onClicked:bar.selectWindow(modelData)
                    Text {x:10;y:4;width:parent.width-40;text:preview.modelData.title;textFormat:Text.PlainText;elide:Text.ElideRight;color:Style.text;font.family:Style.font;font.pixelSize:12}
                    Ui.WindowPreview {x:8;y:30;width:184;height:138;path:Core.Anteprime.images[preview.modelData.address] || ""}
                    AppIcon {anchors.centerIn:parent;width:40;height:40;visible:!Core.Anteprime.images[preview.modelData.address];path:bar.renderedGroup ? bar.renderedGroup.icon:""}
                    Button {anchors.right:parent.right;width:28;height:26;icon:"close";tooltip:Style.label("Chiudi finestra","Close window");onClicked:{var w=Core.Windows.find("address:"+preview.modelData.address);if(w && w.birth===preview.modelData.birth)Core.Windows.close(w.address);}}
                }}
            }
        }
        Ui.Scorrimento {
            objectName:"windowsPreviewScrollBar"
            tinta:Style.muted
            bersaglio:previewScroll
            orizzontale:true
            anchors.left:previewScroll.left
            anchors.right:previewScroll.right
            anchors.bottom:parent.bottom
            height:14
        }
    }}
    Component {id:appMenuPanel;Rectangle {
        color:Style.pannello;radius:8;border.color:Style.edge
        Column {anchors.fill:parent;anchors.margins:8;spacing:4
            Button {objectName:"windowsNewWindow";width:parent.width;height:44;icon:"plus";text:Style.label("Apri nuova finestra","Open new window");enabled:bar.selectedGroup && !!bar.selectedGroup.app;onClicked:{tasks.launch(bar.selectedGroup,true);bar.close();}}
            Button {width:parent.width;height:44;text:bar.selectedGroup && bar.selectedGroup.pinned ? Style.label("Rimuovi dalla barra","Unpin from taskbar"):Style.label("Aggiungi alla barra","Pin to taskbar");enabled:bar.selectedGroup && !!bar.selectedGroup.app;onClicked:{tasks.pin(bar.selectedGroup);bar.close();}}
            Button {width:parent.width;height:44;icon:"close";text:Style.label("Chiudi finestre","Close windows");enabled:bar.selectedGroup && bar.selectedGroup.windows.length>0;onClicked:{bar.selectedGroup.windows.forEach(function(w){var live=Core.Windows.find("address:"+w.address);if(live && live.birth===w.birth)Core.Windows.close(w.address);});bar.close();}}
        }
    }}
    Component {id:overviewPanel;TaskView {output:bar.screen ? bar.screen.name:"";onCloseRequested:bar.close()}}
    Component {id:weatherPanel;Widgets {onSearchRequested:function(query){bar.activePanel="search";Qt.callLater(function(){if(panelLoader.item && panelLoader.item.begin)panelLoader.item.begin(query);});}onSettingsRequested:function(section){bar.close();bar.settingsRequested(section);}onOverviewRequested:bar.toggle("overview");onCalendarRequested:bar.toggle("calendar")}}
    Component {id:screenshotPanel;Rectangle {
        color:Style.pannello;radius:8;border.color:Style.edge
        Button {anchors.centerIn:parent;text:Style.label("Acquisisci schermata","Take screenshot");icon:"camera";onClicked:{bar.close();bar.screenshotRequested();}}
    }}
    Rectangle {
        id:strip;objectName:"windowsTaskbarStrip";x:0;y:bar.height-48;width:bar.width;height:48;color:Style.barra
        Image {anchors.fill:parent;source:Core.Vetro.percorso!=="" ? "file://"+Core.Vetro.percorso:"";asynchronous:true;fillMode:Image.PreserveAspectCrop;opacity:Style.dark ? .08:.12;sourceSize.width:Math.ceil(width);sourceSize.height:48}
        Rectangle {height:1;width:parent.width;color:Style.dark ? "#35ffffff":"#aaFFFFFF"}
        Connections {target:strip.Window.window;ignoreUnknownSignals:true;function onFrameSwapped(){if(bar._paintStarted>=0){bar.lastOpenMs=Date.now()-bar._paintStarted;bar._paintStarted=-1;}}}
        MouseArea {anchors.fill:parent;acceptedButtons:Qt.RightButton;onClicked:{bar.close();taskbarMenu.openAtCursor([{label:Style.label("Gestione attività","Task Manager"),icon:"monitor",action:"monitor"},{separator:true},{label:Style.label("Impostazioni della barra delle applicazioni","Taskbar settings"),icon:"settings",action:"taskbar-settings"}]);}}
        Button {
            id:weather;objectName:"windowsWeatherButton";x:12;y:4;width:Math.min(140,Math.max(40,bar.width/10));height:40;visible:bar.width>=1000 && Core.Ipc.get("windows11.taskbarWidgets", true)
            tooltip:Style.label("Meteo","Weather");onClicked:bar.toggle("weather")
            Row {anchors.centerIn:parent;spacing:8
                WeatherIcon {width:28;height:28;visible:Core.Meteo.attivo && Core.Meteo.pronto;code:Core.Meteo.pronto ? Core.Meteo.adesso.codice:3;day:!Core.Meteo.pronto || Core.Meteo.adesso.giorno!==false}
                Glyph {width:24;height:24;visible:!Core.Meteo.attivo || !Core.Meteo.pronto;name:"apps";color:Style.accentIndicator}
                Column {visible:bar.width>=1200
                    Text {text:Core.Meteo.attivo && Core.Meteo.pronto ? Core.Meteo.gradi(Core.Meteo.adesso.temperatura):Style.label("Widget","Widgets");color:Style.barraTesto;font.family:Style.font;font.pixelSize:12}
                    Text {text:Core.Meteo.pronto ? Core.Meteo.descrizione(Core.Meteo.adesso.codice):Style.label("Meteo","Weather");textFormat:Text.PlainText;color:Style.barraTenue;font.family:Style.font;font.pixelSize:11}
                }
            }
        }
        Flickable {
            id:appBand;objectName:"windowsAppBand";y:4;height:40
            readonly property real leftLimit:weather.visible ? weather.x+weather.width+12:8
            readonly property real rightLimit:tray.x-12
            width:Math.min(appRow.width,Math.max(40,rightLimit-leftLimit))
            x:bar.leftAligned ? leftLimit : Math.max(leftLimit,Math.min((strip.width-width)/2,rightLimit-width))
            contentWidth:appRow.width;contentHeight:40;clip:true;flickableDirection:Flickable.HorizontalFlick
            Row {id:appRow;height:40;spacing:4
                Button {id:startButton;objectName:"windowsStartButton";width:40;height:40;selected:bar.activePanel==="start";tooltip:Style.label("Start","Start");onClicked:bar.toggle("start");onRightClicked:bar.startContext();LiquidMark {anchors.centerIn:parent;width:24;height:24}}
                Button {
                    objectName: "windowsSearchButton"
                    visible: bar.searchPresentation !== "hidden"
                    width: bar.searchPresentation === "box" ? 220 : bar.searchPresentation === "label" ? 90 : 40
                    height: 40
                    tooltip: Style.label("Cerca", "Search")
                    onClicked: bar.toggle("search")
                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: 4
                        anchors.bottomMargin: 4
                        radius: 16
                        visible: bar.searchPresentation === "box"
                        color: Style.dark ? "#50333333" : "#90FFFFFF"
                        border.color: Style.edge
                        border.width: 1
                    }
                    Row {
                        x: bar.searchPresentation === "icon" ? 8 : 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        TaskGlyph {
                            width: 24
                            height: 24
                            kind: "search"
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: bar.searchPresentation !== "icon"
                            text: Style.label("Cerca", "Search")
                            color: Style.barraTesto
                            font.family: Style.font
                            font.pixelSize: 12
                        }
                    }
                }
                Button {objectName:"windowsOverviewButton";visible:Core.Ipc.get("windows11.taskbarTaskView",true);width:40;height:40;tooltip:Style.label("Visualizzazione attività","Task view");onClicked:bar.toggle("overview");TaskGlyph {anchors.centerIn:parent;width:24;height:24;kind:"overview"}}
                Repeater {model:tasks.model;delegate:Button {
                    id:task;required property string key;required property string rowJson
                    readonly property var group:JSON.parse(rowJson)
                    readonly property bool current:group.windows.some(function(w){return w.address===Core.Windows.activeAddress && !w.minimized;})
                    objectName:"windowsTask-"+key;width:40;height:40;selected:current;tooltip:group.name
                    onClicked:bar.activate(group,mapToItem(strip,width/2,0).x)
                    onRightClicked:bar.showContext(group,mapToItem(strip,width/2,0).x)
                    onMiddleClicked:tasks.launch(group,true)
                    onHoveredChanged:{if(hovered && group.windows.length>0){bar.hoverGroup=group;bar.hoverCenter=mapToItem(strip,width/2,0).x;previewTimer.restart();}else previewTimer.stop();}
                    AppIcon {anchors.centerIn:parent;width:24;height:24;path:task.group.icon}
                    Rectangle {anchors.bottom:parent.bottom;anchors.bottomMargin:1;anchors.horizontalCenter:parent.horizontalCenter;height:3;width:task.current ? 16:6;radius:2;visible:task.group.windows.length>0;color:task.current ? Style.accentIndicator:Style.muted}
                }}
            }
        }
        Ui.Scorrimento {
            objectName:"windowsAppBandScrollBar"
            tinta:Style.barraTenue
            bersaglio:appBand
            orizzontale:true
            anchors.left:appBand.left
            anchors.right:appBand.right
            anchors.bottom:parent.bottom
            height:12
        }
        Row {
            id:tray;anchors.right:parent.right;anchors.rightMargin:12;anchors.verticalCenter:parent.verticalCenter;height:40;spacing:4
            Tray {id:trayIcons;screen:bar.screen;expanded:bar.activePanel==="tray";onCloseRequested:bar.close();onToggleRequested:{bar.groupCenter=mapToItem(strip,width/2,0).x;bar.toggle("tray");}anchors.verticalCenter:parent.verticalCenter}
            Button {objectName:"windowsTilingButton";width:32;height:40;visible:Core.Compositore.nostro && Core.Tiling.showButton && Core.Ipc.get("windows11.showTilingButton",false);icon:Core.Tiling.active ? "grid":"window";tooltip:Style.label("Tiling / classico","Tiling / classic");selected:Core.Tiling.active;onClicked:Core.Tiling.toggle();onRightClicked:{bar.close();bar.settingsRequested("finestre");}}
            SystemStatus {
                id: systemStatus
                selected: bar.activePanel === "control"
                onClicked: bar.toggle("control")
                onAudioContextRequested: function(centre) {
                    bar.close();
                    // Il menu nasce sopra la barra, non sotto il mouse:
                    // il limite dello schermo lo farebbe coprire l'icona.
                    var point = systemStatus.mapToItem(null, centre, 0);
                    taskbarMenu.openAbove(point.x, bar.screenRect.y - 4, [
                        {label: Style.label("Apri mixer volume", "Open volume mixer"), icon: "volume", action: "audio-mixer"},
                        {label: Style.label("Impostazioni audio", "Sound settings"), icon: "settings", action: "audio-settings"}
                    ]);
                }
            }
            ClockButton {
                date: clock.date
                selected: bar.activePanel === "calendar"
                onClicked: bar.toggle("calendar")
            }
        }
        Button {objectName:"windowsShowDesktop";visible:Core.Ipc.get("windows11.taskbarShowDesktop",true);anchors.right:parent.right;width:8;height:48;tooltip:Style.label("Mostra desktop","Show desktop");onClicked:Core.Windows.mostraScrivania();Rectangle {width:1;height:24;anchors.centerIn:parent;color:Style.edge}}
    }
}

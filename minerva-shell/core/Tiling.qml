pragma Singleton
import QtQuick

QtObject {
    id: tiling
    readonly property bool active: Compositore.tilingState.modalita === "colonne"
    readonly property bool showButton: Ipc.get("windows.tilingTray", true) === true
    readonly property string order: String(Ipc.get("windows.tilingOrder", "recenti"))
    readonly property bool focusFirst: Ipc.get("windows.tilingFocusFirst",true)===true
    readonly property bool adaptiveMaster: Ipc.get("windows.tilingMasterAdaptive",true)===true
    readonly property string defaultMode: String(Ipc.get("windows.tilingMode", "classico"))
    readonly property string mode: active ? "colonne":"classico"
    readonly property var workspaceLayouts: Ipc.get("windows.workspaceLayouts", ["eredita","eredita","eredita","eredita","eredita","eredita","eredita","eredita","eredita","eredita"])
    readonly property var workspaceNames: Ipc.get("windows.workspaceNames", ["","","","","","","","","",""])
    readonly property bool recentWorkspacesFirst: Ipc.get("windows.workspaceRecentFirst",true)===true
    // ── L'ordine delle scrivanie usate: in memoria, salvato con calma ─────
    //
    // Fino al 19 ottobre 2026 ogni cambio di scrivania lo scriveva nelle
    // impostazioni: per il demone una transazione con fsync, e 59 KB di
    // impostazioni rimandati a ogni processo di Minerva, a ogni cambio. Ora la
    // shell lo tiene qui e lo salva dopo 30 s di calma (o alla chiusura): la
    // Panoramica lo vede subito, e il disco e gli altri processi una volta.
    readonly property var _recentiSalvate: Ipc.get("windows.workspaceRecentOrder",[1,2,3,4,5,6,7,8,9,10])
    property var _recentiQui: null
    readonly property var recentWorkspaces: _recentiQui !== null ? _recentiQui : _recentiSalvate
    function rememberWorkspace() {
        if(!Compositore.scrivania || !Ipc.impostazioniArrivate) return;
        var number=Compositore.scrivaniaAttiva;
        if(number<1 || number>10 || recentWorkspaces[0]===number) return;
        var list=[number];
        for(var n of recentWorkspaces) if(n!==number && list.indexOf(n)<0 && n>=1 && n<=10) list.push(n);
        for(var i=1;i<=10;i++) if(list.indexOf(i)<0) list.push(i);
        _recentiQui=list;
        salvaRecenti.restart();
    }
    function _salvaRecenti() {
        if(_recentiQui !== null && JSON.stringify(_recentiQui) !== JSON.stringify(_recentiSalvate))
            Ipc.setSetting("windows.workspaceRecentOrder",_recentiQui);
    }
    property Timer salvaRecenti: Timer { interval: 30000; onTriggered: tiling._salvaRecenti() }
    Component.onDestruction: _salvaRecenti()
    readonly property var previousLayouts: Ipc.get("windows.workspaceLastLayouts", ["uguale","uguale","uguale","uguale","uguale","uguale","uguale","uguale","uguale","uguale"])
    readonly property string defaultLayout: String(Ipc.get("windows.tilingLayout", "uguale"))
    readonly property string layout: {
        var value=workspaceLayouts[Compositore.scrivaniaAttiva-1];
        return ["uguale","maestro","griglia","nuovo"].indexOf(value)>=0 ? value:defaultLayout;
    }
    readonly property int widthPercent: Number(Ipc.get("windows.tilingWidth", 50))
    readonly property int gap: Number(Ipc.get("windows.tilingGap", 8))
    readonly property var rules: Ipc.get("windows.tilingRules", [])
    readonly property string signature: JSON.stringify([defaultMode,order,defaultLayout,widthPercent,gap,rules,workspaceLayouts,focusFirst,adaptiveMaster])
    property string applied: ""
    onSignatureChanged: applySoon.restart()
    function setWorkspace(number,value) {
        var layouts=["uguale","maestro","griglia","nuovo"];
        var remember=layouts.indexOf(value)>=0 ? value:workspaceLayouts[number-1];
        if(layouts.indexOf(remember)>=0 && previousLayouts[number-1]!==remember) {
            var previous=previousLayouts.slice();previous[number-1]=remember;
            Ipc.setSetting("windows.workspaceLastLayouts",previous);
        }
        var list=workspaceLayouts.slice();list[number-1]=value;Ipc.setSetting("windows.workspaceLayouts",list);
    }
    function nameWorkspace(number,value) {
        var list=workspaceNames.slice(),name=value.trim().substring(0,40);
        if(list[number-1]===name) return;
        list[number-1]=name;Ipc.setSetting("windows.workspaceNames",list);
    }
    function setMode(value) {
        if(workspaceLayouts[Compositore.scrivaniaAttiva-1]!=="eredita")
            setWorkspace(Compositore.scrivaniaAttiva,value==="classico" ? "classico":previousLayouts[Compositore.scrivaniaAttiva-1]);
        else Ipc.setSetting("windows.tilingMode", value);
    }
    function toggle() { setMode(active ? "classico":"colonne"); }
    function setOrder(value) { Ipc.setSetting("windows.tilingOrder",value); }
    function setLayout(value) {
        var selected=workspaceLayouts[Compositore.scrivaniaAttiva-1];
        if(selected!=="eredita" && selected!=="classico") setWorkspace(Compositore.scrivaniaAttiva,value);
        else Ipc.setSetting("windows.tilingLayout",value);
    }
    function recall(address) {
        if(Compositore.nostro) Compositore._nostro("richiama",[Compositore._selettore(address)]);
        else { Compositore.fuoco(address); Compositore.davanti(address); }
    }
    function apply() {
        if(!Compositore.scrivania || !Compositore.canaleAperto || !Ipc.impostazioniArrivate || applied===signature) return;
        applied=signature;
        Compositore._nostro("tiling",["config",order,String(widthPercent),String(gap)]);
        Compositore._nostro("tiling",["focus-prima",focusFirst ? "si":"no"]);
        Compositore._nostro("tiling",["maestro-adattivo",adaptiveMaster ? "si":"no"]);
        Compositore._nostro("tiling",["layout",defaultLayout]);
        Compositore._nostro("tiling",["regole-reset"]);
        for(var i=0;i<rules.length;i++) {
            var r=rules[i];
            if(!r || !/^[A-Za-z0-9_.@+-]{1,127}$/.test(String(r.app || ""))) continue;
            Compositore._nostro("tiling",["regola",r.app,r.enabled===false ? "no":"si",
                String(r.width || 50),String(r.position===undefined ? -1:r.position),String(r.workspace || 0)]);
        }
        for(var d=0;d<10;d++) Compositore._nostro("tiling",["scrivania",String(d+1),String(workspaceLayouts[d] || "eredita")]);
        Compositore._nostro("tiling",[defaultMode]);
    }
    property Timer applySoon: Timer { interval: 80; onTriggered: tiling.apply() }
    property Connections connection: Connections {
        target: Compositore
        function onCanaleApertoChanged() { tiling.applied=""; tiling.applySoon.restart(); }
        function onScrivaniaAttivaChanged() { tiling.rememberWorkspace(); }
    }
    property Connections settings: Connections {
        target: Ipc
        function onImpostazioniArrivateChanged() { tiling.applySoon.restart(); tiling.rememberWorkspace(); }
    }
    Component.onCompleted: applySoon.restart()
}

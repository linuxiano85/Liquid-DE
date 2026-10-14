import QtQuick
import "../../core" as Core
import "../../theme" as Theme
import "../../ui" as Ui
import ".." as S

Card {
    id: panel
    readonly property bool it: Core.Strings.lang === "it"
    heading: it ? "Disposizione delle finestre":"Window layout"
    note: it ? "La modalità predefinita vale per le stanze senza una scelta personale nella panoramica. Super + frecce seleziona una finestra. Tieni Super premuto per attraversare i riquadri senza ripartire dopo ogni riordino. Ctrl + ↑ ingrandisce, Ctrl + ↓ ripristina. Super + Maiusc + numero invia a un’altra scrivania. Super + Ctrl + Maiusc + frecce scambia le posizioni."
             : "Default for workspaces without their own choice in the overview. Super + arrows focuses a window. Keep Super held to traverse tiles without restarting after each reorder. Ctrl + ↑ maximizes, Ctrl + ↓ restores. Super + Shift + number sends to another workspace. Super + Ctrl + Shift + arrows swaps positions."
    function updateRule(index,key,value) {
        var list=Core.Tiling.rules.slice();
        var r=Object.assign({},list[index]); r[key]=value; list[index]=r;
        Core.Ipc.setSetting("windows.tilingRules",list);
    }
    function addRule() {
        var app=appName.text.trim();
        if(!/^[A-Za-z0-9_.@+-]{1,127}$/.test(app)) return;
        var list=Core.Tiling.rules.slice();
        for(var i=0;i<list.length;i++) if(list[i].app===app) return;
        if(list.length>=64) return;
        list.push({app:app,enabled:true,width:50,position:-1,workspace:0});
        Core.Ipc.setSetting("windows.tilingRules",list); appName.text="";
    }
    Repeater {
        model:[
            {key:"workspacePhotographs",it:"Fotografie nella panoramica",en:"Photos in overview",fallback:true},
            {key:"focusBorder",it:"Bordo colorato sulla finestra attiva",en:"Colored active window border",fallback:true},
            {key:"inactiveGray",it:"Finestre inattive in bianco e nero",en:"Inactive windows in grayscale",fallback:false},
            {key:"dockLocalWindows",it:"Dock: finestre del desktop corrente",en:"Dock: current workspace windows",fallback:true}
        ]
        S.SettingRow {
            required property var modelData
            width:parent.width;label:panel.it ? modelData.it:modelData.en
            control:S.ToggleSwitch {
                enabled:modelData.key!=="inactiveGray" || Core.Compositore.focusCapabilities.desaturation===true
                checked:Core.Ipc.get("windows."+modelData.key,modelData.fallback)===true
                onToggled:function(v) {Core.Ipc.setSetting("windows."+modelData.key,v);}
            }
        }
    }
    S.SettingRow {
        width: parent.width
        label: panel.it ? "Mostra l’icona tiling nella barra":"Show tiling icon in the bar"
        description: panel.it ? "Accanto alla tray, anche nell’isola. Puoi cambiare modalità da questa pagina quando l’icona è nascosta."
                              : "Next to the tray, including in the island. You can change mode here when the icon is hidden."
        control: S.ToggleSwitch {
            objectName: "tilingTray"
            checked: Core.Tiling.showButton
            onToggled: function(value) { Core.Ipc.setSetting("windows.tilingTray", value); }
        }
    }
    S.SettingRow {
        width:parent.width
        label:panel.it ? "Stanze recenti per prime":"Recent workspaces first"
        description:panel.it ? "Nella panoramica, l’ultima stanza usata viene prima. I numeri e Super + numero restano fissi. Disattiva per l’ordine numerico.":"The last workspace used appears first in the overview. Numbers and Super + number stay fixed. Disable for numerical order."
        control:S.ToggleSwitch {
            objectName:"workspaceRecentFirst"
            checked:Core.Tiling.recentWorkspacesFirst
            onToggled:function(value) {Core.Ipc.setSetting("windows.workspaceRecentFirst",value);}
        }
    }
    S.SettingRow {
        width: parent.width
        label: panel.it ? "Modalità":"Mode"
        description: Core.Tiling.active ? (panel.it ? "Tiling attivo":"Tiling active"):(panel.it ? "Modalità classica attiva":"Classic mode active")
        control: S.ChoicePicker {
            objectName: "tilingMode"
            value: Core.Tiling.mode
            options: [{value:"classico",label:panel.it ? "Classico":"Classic"},{value:"colonne",label:"Tiling"}]
            onPicked: function(value) { Core.Tiling.setMode(value); }
        }
    }
    S.SettingRow {
        width: parent.width; label: panel.it ? "Ordine":"Order"; controlWidth: 300
        description: panel.it ? "In Recenti, puoi portare al primo posto ogni finestra che prende il focus. Manuale mantiene le posizioni scelte con mouse e tastiera.":"In Recent mode, you can move every focused window to the first position. Manual keeps the positions chosen with mouse and keyboard."
        control: S.ChoicePicker {
            objectName: "tilingOrder"
            value: Core.Tiling.order
            options: [{value:"recenti",label:panel.it ? "Recenti a sinistra":"Recent on left"},{value:"manuale",label:panel.it ? "Manuale":"Manual"}]
            onPicked: function(value) { Core.Tiling.setOrder(value); }
        }
    }
    S.SettingRow {
        width:parent.width
        label:panel.it ? "Finestra attiva per prima":"Focused window first"
        description:panel.it ? "In tutti i layout, il focus porta la finestra a sinistra. In Maestro diventa il riquadro principale; le altre seguono l’ultimo utilizzo dall’alto in basso. Disattiva per cambiare focus senza spostare i riquadri.":"In every layout, focus moves the window to the left. In Master it becomes the main pane; the others follow last-use order from top to bottom. Disable to change focus without moving tiles."
        control:S.ToggleSwitch {
            objectName:"tilingFocusFirst"
            enabled:Core.Tiling.order==="recenti"
            checked:Core.Tiling.focusFirst && Core.Tiling.order==="recenti"
            onToggled:function(value) {Core.Ipc.setSetting("windows.tilingFocusFirst",value);}
        }
    }
    S.SettingRow {
        width: parent.width; label: panel.it ? "Disposizione":"Arrangement"; controlWidth: 340
        description: panel.it ? "Come si dispongono tre o più finestre sulla scrivania. «Uguale» le divide in parti uguali; «Maestro» tiene la più recente grande a sinistra e impila le altre; «Nuovo desktop» ne tiene al massimo due e apre una scrivania nuova."
                              : "How three or more windows arrange on the desktop. “Equal” splits them evenly; “Master” keeps the most recent large on the left and stacks the rest; “New desktop” keeps at most two and opens a new desktop."
        control: S.ChoicePicker {
            objectName: "tilingLayout"
            value: Core.Tiling.layout
            options: [
                {value:"uguale",  label:panel.it ? "Parti uguali":"Equal split"},
                {value:"maestro", label:panel.it ? "Maestro + pila":"Master + stack"},
                {value:"griglia", label:panel.it ? "Griglia adattiva":"Adaptive grid"},
                {value:"nuovo",   label:panel.it ? "Nuovo desktop":"New desktop"}
            ]
            onPicked: function(value) { Core.Tiling.setLayout(value); }
        }
    }
    S.SettingRow {
        width:parent.width
        label:panel.it ? "Proporzioni automatiche del Maestro":"Automatic Master proportions"
        description:panel.it ? "Una finestra usa tutto lo spazio. Con due: metà ciascuna; con tre: 60% al Maestro; con quattro o più: 65%. Rispetta i minimi delle app, le regole personali e il ridimensionamento con il mouse.":"One window uses all the space. With two: half each; with three: 60% for Master; with four or more: 65%. Respects app minimum sizes, personal rules and mouse resizing."
        control:S.ToggleSwitch {
            objectName:"tilingMasterAdaptive"
            checked:Core.Tiling.adaptiveMaster
            onToggled:function(value) {Core.Ipc.setSetting("windows.tilingMasterAdaptive",value);}
        }
    }
    S.SettingRow {
        width: parent.width; label: panel.it ? "Larghezza del maestro":"Master width"
        description:panel.it ? "Percentuale usata quando le proporzioni automatiche sono disattivate. Puoi sempre ridimensionare con Super e il tasto destro del mouse.":"Percentage used when automatic proportions are disabled. You can always resize with Super and the right mouse button."
        control: S.ValueSlider { objectName:"tilingMasterWidth"; enabled:!Core.Tiling.adaptiveMaster; width: 200; from: 20; to: 100; unit:"intero"; suffix:"%"; value: Core.Tiling.widthPercent
            onReleased: function(v) { Core.Ipc.setSetting("windows.tilingWidth",Math.round(v)); } }
    }
    S.SettingRow {
        width: parent.width; label: panel.it ? "Spazio fra finestre":"Window gap"
        control: S.ValueSlider { width: 200; from: 0; to: 40; unit:"pixel"; value: Core.Tiling.gap
            onReleased: function(v) { Core.Ipc.setSetting("windows.tilingGap",Math.round(v)); } }
    }
    Text {
        width: parent.width; wrapMode: Text.WordWrap; color: Theme.Colors.textMuted
        text: panel.it ? "Regole per applicazione · usa l’identificatore della finestra. Posizione 1 = prima colonna; Auto segue l’ordine scelto. La larghezza si aggiorna subito; la posizione vale per le nuove finestre in ordine Manuale, dove il focus non riordina."
                       : "Application rules · use the window app ID. Position 1 = first column; Auto follows the selected order. Width updates immediately; position applies to new windows in Manual order, where focus does not reorder."
    }
    Flow {
        width: parent.width; spacing: 8
        Ui.Campo { id: appName; width: Math.min(280,panel.width-80); segnaposto: panel.it ? "ID applicazione, es. firefox":"Application ID, e.g. firefox"; onAccettato: panel.addRule() }
        Ui.SpineButton { solido:true; tooltip:panel.it ? "Aggiungi regola":"Add rule"; onClicked:panel.addRule()
            content: Text { text:"+"; color:Theme.Colors.text; font.pixelSize:20 } }
    }
    Flow {
        width:parent.width; spacing:6
        Repeater {
            model: {
                var ids=[];
                for(var i=0;i<Core.Windows.all.length;i++) {
                    var a=Core.Windows.all[i].appClass;
                    if(a && ids.indexOf(a)<0) ids.push(a);
                }
                return ids;
            }
            Ui.RigaScelta { required property string modelData; width:Math.min(220,panel.width-40); piccola:true; testo:modelData
                onScelto:appName.text=modelData }
        }
    }
    Repeater {
        model: Core.Tiling.rules
        Column {
            id: rule; required property var modelData; required property int index
            width: parent.width; spacing: 6
            S.SettingRow {
                width:parent.width; label:rule.modelData.app
                description:panel.it ? "Partecipa al tiling":"Participates in tiling"
                control:S.ToggleSwitch { checked:rule.modelData.enabled; onToggled:function(v) {panel.updateRule(rule.index,"enabled",v);} }
            }
            S.SettingRow {
                width:parent.width; label:panel.it ? "Larghezza":"Width"
                control:S.ValueSlider { width:200; from:20; to:100; unit:"intero"; suffix:"%"; value:rule.modelData.width
                    onReleased:function(v) {panel.updateRule(rule.index,"width",Math.round(v));} }
            }
            S.SettingRow {
                width:parent.width;label:panel.it ? "Apri nella stanza":"Open in workspace"
                description:panel.it ? "Vale per le nuove finestre, senza cambiare la stanza attuale.":"Applies to new windows, without switching your current workspace."
                control:S.ValueSlider {width:200;from:0;to:10;unit:"intero";value:rule.modelData.workspace || 0
                    onReleased:function(v){panel.updateRule(rule.index,"workspace",Math.round(v));}}
            }
            Row {
                spacing:8
                Text { anchors.verticalCenter:parent.verticalCenter; color:Theme.Colors.textMuted
                    text:rule.modelData.position<0 ? "Auto":String(rule.modelData.position+1) }
                Ui.SpineButton { solido:true; tooltip:panel.it ? "Posizione precedente":"Previous position"; onClicked:panel.updateRule(rule.index,"position",Math.max(-1,rule.modelData.position-1))
                    content:Text {text:"−";color:Theme.Colors.text} }
                Ui.SpineButton { solido:true; tooltip:panel.it ? "Posizione successiva":"Next position"; onClicked:panel.updateRule(rule.index,"position",Math.min(63,rule.modelData.position+1))
                    content:Text {text:"+";color:Theme.Colors.text} }
                Ui.SpineButton { solido:true; tooltip:panel.it ? "Rimuovi regola":"Remove rule"; onClicked:{var l=Core.Tiling.rules.slice();l.splice(rule.index,1);Core.Ipc.setSetting("windows.tilingRules",l);}
                    content:Text {text:"×";color:Theme.Colors.danger} }
            }
        }
    }
}

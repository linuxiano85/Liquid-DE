import QtQuick
import QtQuick.Controls as Controls
import "../core" as Core
import "../theme" as Theme
import "../ui" as Ui

Item {
    id: picker
    objectName: "mediaPlaylistPicker"
    property var info: ({})
    property bool busy: false
    property string errorText: ""
    property var selection: ({})
    property string identity: ""
    readonly property bool it: Core.Strings.lang === "it"
    readonly property var entries: info.voci || []
    readonly property int selectedCount: Object.keys(selection).length
    signal moreRequested()
    signal downloadRequested(var indices)
    /// Torna ai risultati della ricerca (se ce n'è una da cui si è venuti).
    property bool canGoBack: false
    signal backRequested()
    /// Ascolta senza scaricare, dal brano `i` di `voci` in poi.
    signal listenRequested(var voci, int i)
    /// Tutta la playlist, nel formato scelto sopra.
    signal downloadAllRequested()

    onInfoChanged: {
        var key=info.request || "";
        // A new first page resets selection even when reopening the same URL.
        if((info.inizio === 1 || info.tipo!=="playlist") && key !== identity) selection=({});
        identity=key;
    }
    function selectAll(selected) {
        var values=({});
        if(selected) for(var i=0;i<entries.length;i++) {
            if(entries[i].indice>0 && entries[i].tipo==="video") values[entries[i].indice]=true;
        }
        selection=values;
    }
    function toggle(index) {
        var values=Object.assign({},selection);
        if(values[index]) delete values[index]; else values[index]=true;
        selection=values;
    }
    function download() {
        var indices=Object.keys(selection).map(Number).sort(function(a,b){return a-b;});
        if(indices.length && !busy) downloadRequested(indices);
    }
    Column {
        id: header
        width:parent.width
        spacing:6
        Text {
            width:parent.width
            text:picker.info.titolo || "Playlist"
            textFormat:Text.PlainText
            elide:Text.ElideRight
            color:Theme.Colors.text
            font {pixelSize:Theme.Typography.sizeMD;weight:Font.DemiBold}
        }
        Text {
            width:parent.width
            text:picker.it ? picker.entries.length+" elementi caricati · "+picker.selectedCount+" selezionati"
                           : picker.entries.length+" items loaded · "+picker.selectedCount+" selected"
            color:Theme.Colors.textMuted
            font.pixelSize:Theme.Typography.sizeSM
        }
        Text {
            width:parent.width
            visible:picker.errorText!==""
            height:visible?implicitHeight:0
            text:picker.errorText
            textFormat:Text.PlainText
            color:Theme.Colors.danger
            wrapMode:Text.Wrap
            font.pixelSize:Theme.Typography.sizeSM
        }
        Flow {
            width:parent.width
            spacing:8
            Action {
                objectName:"playlistBack"
                visible:picker.canGoBack
                text:picker.it?"← Risultati":"← Results"
                onClicked:picker.backRequested()
            }
            Action {
                objectName:"listenPlaylist"
                text:picker.it?"Ascolta tutta":"Listen to all"
                enabled:picker.entries.length>0
                onClicked:picker.listenRequested(picker.entries,0)
            }
            Action {
                objectName:"downloadWholePlaylist"
                text:picker.it?"Scarica tutta la playlist":"Download whole playlist"
                enabled:!picker.busy && (picker.info.url||"")!==""
                onClicked:picker.downloadAllRequested()
            }
            Action {
                objectName:"selectAllPlaylistItems"
                text:picker.it?"Seleziona tutti i caricati":"Select all loaded"
                enabled:!picker.busy
                onClicked:picker.selectAll(true)
            }
            Action {
                objectName:"clearPlaylistSelection"
                text:picker.it?"Deseleziona tutto":"Deselect all"
                onClicked:picker.selectAll(false)
            }
            Action {
                objectName:"downloadPlaylistSelection"
                text:picker.it?"Scarica selezionati":"Download selected"
                enabled:picker.selectedCount>0 && !picker.busy
                onClicked:picker.download()
            }
            Action {
                text:picker.busy ? (picker.it?"Caricamento…":"Loading…") : (picker.it?"Carica altri":"Load more")
                visible:picker.info.paginaPiena===true
                enabled:!picker.busy
                onClicked:picker.moreRequested()
            }
        }
    }
    ListView {
        id:list
        anchors {left:parent.left;right:parent.right;top:header.bottom;topMargin:8;bottom:parent.bottom;rightMargin:14}
        clip:true
        spacing:4
        model:picker.entries
        delegate:Controls.CheckBox {
            required property var modelData
            required property int index
            objectName:"playlistItem_"+modelData.indice
            width:list.width
            height:52
            rightPadding:48
            enabled:modelData.indice>0 && modelData.tipo==="video" && !picker.busy
            checked:picker.selection[modelData.indice]===true
            text:modelData.indice+". "+modelData.titolo
            Accessible.name:text
            onClicked:picker.toggle(modelData.indice)
            contentItem:Text {
                leftPadding:34
                text:parent.text
                textFormat:Text.PlainText
                elide:Text.ElideRight
                verticalAlignment:Text.AlignVCenter
                color:Theme.Colors.text
                font.pixelSize:Theme.Typography.sizeSM
            }
            background:Rectangle {radius:6;color:parent.hovered?Theme.Colors.hover:Theme.Colors.raised}
            // Ascolta da qui senza scaricare.
            Rectangle {
                objectName:"listenPlaylistItem_"+parent.modelData.indice
                anchors {right:parent.right;rightMargin:8;verticalCenter:parent.verticalCenter}
                width:34;height:34;radius:17
                visible:parent.modelData.tipo==="video"
                color:ascoltaQui.containsMouse?Theme.Colors.hover:"transparent"
                // Un carattere, non `Ui.Icon`: Icon legge Core.Ipc, e questo
                // componente resta senza dipendenze dal demone (la sua prova
                // QuickTest lo carica da solo).
                Text {anchors.centerIn:parent;text:"\u25B6";color:Theme.Colors.text;font.pixelSize:13}
                MouseArea {id:ascoltaQui;anchors.fill:parent;hoverEnabled:true;onClicked:picker.listenRequested(picker.entries,parent.parent.index)}
            }
        }
    }
    Ui.Scorrimento {bersaglio:list;anchors {right:parent.right;top:list.top;bottom:list.bottom}}
    component Action: Controls.Button {
        implicitHeight:32
        implicitWidth:label.implicitWidth+24
        opacity:enabled?1:0.45
        contentItem:Text {id:label;text:parent.text;color:Theme.Colors.text;font.pixelSize:Theme.Typography.sizeSM;verticalAlignment:Text.AlignVCenter}
        background:Rectangle {radius:6;color:parent.hovered?Theme.Colors.hover:Theme.Colors.raised;border.color:Theme.Colors.accent;border.width:1}
    }
}

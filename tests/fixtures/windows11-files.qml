//@ pragma AppId test-files
import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    id:root
    property var windows:[]
    function add() {var w=client.createObject(root);windows=windows.concat([w]);}
    Component.onCompleted:add()
    Component {id:client;FloatingWindow {
        visible:true;implicitWidth:440;implicitHeight:300;minimumSize:Qt.size(180,120);title:"File";color:"#f9fafb"
        Rectangle {x:0;y:0;width:parent.width;height:44;color:"#edf2f8";Text {x:20;y:14;text:"Documenti";font.pixelSize:16;color:"#243754"}}
        Text {x:24;y:84;text:"Progetto.txt\n\nAppunti.txt\n\nImmagini";font.pixelSize:15;color:"#253955"}
    }}
    IpcHandler {target:"windows-files-test";function add():void {root.add();}
        function renameAll():void {root.windows.forEach(function(w,i){w.title="Titolo aggiornato "+i;});}}
}

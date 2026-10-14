import QtQuick
import "../core" as Core
import "../ui" as Ui
FocusScope {
    id: panel
    objectName:"windowsCalendar"
    property date today:new Date()
    property date shown:new Date()
    property date selected:new Date()
    readonly property var locale:Style.it ? Qt.locale("it_IT"):Qt.locale("en_GB")
    readonly property int leading:(new Date(shown.getFullYear(),shown.getMonth(),1).getDay()+6)%7
    readonly property int days:new Date(shown.getFullYear(),shown.getMonth()+1,0).getDate()
    function step(delta) {var d=new Date(shown);d.setDate(1);d.setMonth(d.getMonth()+delta);shown=d;}
    Component.onCompleted:Core.Notifications.markAllRead()
    Rectangle {anchors.fill:parent;radius:8;color:Style.pannello;border.color:Style.edge}
    Item {id:notes;x:16;y:16;width:parent.width-32;height:Math.max(80,parent.height-390)
        Text {text:Style.label("Notifiche","Notifications");color:Style.text;font.family:Style.font;font.pixelSize:14;font.weight:Font.DemiBold}
        Button {anchors.right:parent.right;height:26;text:Style.label("Cancella tutto","Clear all");enabled:Core.Notifications.items.length>0;onClicked:Core.Notifications.clear()}
        ListView {id:noteList;y:38;width:parent.width;height:parent.height-38;clip:true;spacing:8;model:Core.Notifications.items.slice().reverse()
            delegate:Rectangle {
                required property var modelData;required property int index;width:noteList.width;height:86;radius:4;color:Style.card;border.color:Style.cardStroke
                Column {x:12;y:10;width:parent.width-50;spacing:4
                    Text {width:parent.width;text:parent.parent.modelData.appName || "";textFormat:Text.PlainText;elide:Text.ElideRight;color:Style.muted;font.family:Style.font;font.pixelSize:11}
                    Text {width:parent.width;text:parent.parent.modelData.summary || "";textFormat:Text.PlainText;elide:Text.ElideRight;color:Style.text;font.family:Style.font;font.pixelSize:13;font.weight:Font.DemiBold}
                    Text {width:parent.width;text:parent.parent.modelData.body || "";textFormat:Text.PlainText;elide:Text.ElideRight;color:Style.muted;font.family:Style.font;font.pixelSize:12}
                }
                MouseArea {anchors.fill:parent;onClicked:Core.Notifications.apri(parent.modelData)}
                Button {anchors.right:parent.right;anchors.top:parent.top;width:30;height:30;icon:"close";tooltip:Style.label("Rimuovi notifica","Dismiss notification");onClicked:Core.Notifications.remove(Core.Notifications.items.length-1-parent.index)}
            }
        }
        Ui.Scorrimento {
            objectName:"windowsNotificationsScrollBar"
            tinta:Style.muted
            bersaglio:noteList
            anchors.right:noteList.right
            anchors.top:noteList.top
            anchors.bottom:noteList.bottom
        }
        Text {y:55;visible:noteList.count===0;width:parent.width;text:Style.label("Nessuna nuova notifica","No new notifications");horizontalAlignment:Text.AlignHCenter;color:Style.muted;font.family:Style.font;font.pixelSize:13}
    }
    Rectangle {x:0;y:notes.y+notes.height+12;width:parent.width;height:1;color:Style.edge}
    Item {
        x:24;anchors.bottom:parent.bottom;anchors.bottomMargin:24;width:parent.width-48;height:330
        Button {y:0;text:panel.today.toLocaleDateString(panel.locale,"dddd d MMMM");tooltip:Style.label("Torna a oggi","Back to today");onClicked:{panel.shown=new Date();panel.selected=new Date();}}
        Text {y:55;text:panel.shown.toLocaleDateString(panel.locale,"MMMM yyyy");color:Style.text;font.family:Style.font;font.pixelSize:14;font.weight:Font.DemiBold}
        Row {anchors.right:parent.right;y:46;spacing:4
            Button {text:"‹";tooltip:Style.label("Mese precedente","Previous month");onClicked:panel.step(-1)}
            Button {text:"›";tooltip:Style.label("Mese successivo","Next month");onClicked:panel.step(1)}
        }
        Row {id:week;y:94;width:parent.width
            Repeater {model:Style.it ? ["L","M","M","G","V","S","D"]:["M","T","W","T","F","S","S"];delegate:Text {required property string modelData;width:week.width/7;text:modelData;horizontalAlignment:Text.AlignHCenter;color:Style.muted;font.family:Style.font;font.pixelSize:12}}
        }
        Grid {id:grid;objectName:"windowsCalendarDays";y:124;width:parent.width;columns:7
            Repeater {model:42;delegate:Button {
                required property int index
                readonly property int day:index-panel.leading+1
                readonly property date cellDate:new Date(panel.shown.getFullYear(),panel.shown.getMonth(),day)
                readonly property bool isToday:day===panel.today.getDate() && panel.shown.getMonth()===panel.today.getMonth() && panel.shown.getFullYear()===panel.today.getFullYear()
                readonly property bool isSelected:cellDate.toDateString()===panel.selected.toDateString()
                width:grid.width/7;height:32;text:String(cellDate.getDate());filled:isToday;selected:isSelected;opacity:day>0 && day<=panel.days ? 1:0.45
                tooltip:cellDate.toLocaleDateString(panel.locale,"dddd d MMMM yyyy");onClicked:{panel.selected=cellDate;if(day<=0 || day>panel.days)panel.shown=cellDate;}
            }}
        }
    }
}

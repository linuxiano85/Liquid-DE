import QtQuick
import QtQuick.Window
import Quickshell
import Minerva.WindowIdentity 1.0 as Native
import "../core" as Core
import "../theme" as Theme
import "../windows11" as W
import "../settings" as S
import "../settings/windows" as Win
import "../ui" as Ui

Window {
    id: dialog
    objectName:"liquidPrintDialog"
    readonly property bool windows:Core.DesktopStyle.attuale === "windows"
    readonly property bool it:Core.Strings.lang === "it"
    readonly property color ink:windows ? W.Style.text : Theme.Colors.text
    readonly property color muted:windows ? W.Style.muted : Theme.Colors.textMuted
    readonly property color paperSurface:windows ? W.Style.card : Theme.Colors.raised
    property var document: null
    property string sourcePath:""
    property string printerName:""
    readonly property var printer:Core.Printing.printers.find(function(row){return row.name===dialog.printerName;}) || null
    property string media:""
    property string sides:"one-sided"
    property string colorMode:""
    property string orientation:"portrait"
    property int page:1
    property string previewUrl:""
    property string problem:""
    property bool submitting:false
    property bool submitted:false
    property bool preparing:false
    property int generation:0
    property int jobId:0
    property bool standalone:false
    property string mode:"print"
    property string confirmAction:""
    property string afterSaveAction:""
    readonly property var scanPane:scanLoader.item
    readonly property int modeBarHeight:standalone ? 52 : 0
    readonly property bool backgroundBusy:worker.busy || !!scanPane && scanPane.busy || Core.Printing.busy
    signal dismissed()
    readonly property string helper:(Quickshell.env("LIQUID_DE") || Quickshell.shellDir+"/..")+"/scripts/liquid_print_document.py"
    readonly property bool rangesValid: {
        if(!document)return false;
        var expression=ranges.text.trim();
        if(!expression)return true;
        if(expression.length>1024)return false;
        if(!/^[1-9][0-9]*(?:-[1-9][0-9]*)?(?:,[1-9][0-9]*(?:-[1-9][0-9]*)?)*$/.test(expression))return false;
        for(var part of expression.split(",")) {
            var limits=part.split("-").map(Number);
            if(limits[0] > limits[limits.length-1] || limits[limits.length-1] > document.pageCount)return false;
        }
        return true;
    }
    readonly property bool canSubmit:!!document && !!printer && printer.accepting===true && !preparing && !submitting && !submitted && !Core.Printing.busy && copies.acceptableInput && rangesValid && (!standalone || !!scanPane && !scanPane.dirty && !scanPane.scanning && !scanPane.building)
    readonly property bool documentBusy:worker.busy
    Native.WindowIdentity {item:root}
    title:standalone ? label("Stampa e scansione · Liquid", "Print and Scan · Liquid") : label("Stampa", "Print")
    width:1000
    height:720
    minimumWidth:780
    minimumHeight:540
    flags:(standalone ? Qt.Window : Qt.Dialog) | Qt.FramelessWindowHint
    modality:standalone ? Qt.NonModal : Qt.WindowModal
    color:windows ? W.Style.base : Theme.Colors.window
    visible:false
    onActiveChanged:if(active && visible && !submitting && !submitted)Core.Printing.refresh()
    onClosing:function(event){event.accepted=false;dialog.dismiss();}
    function label(italian,english){return it ? italian : english;}
    function openUtility(path) {
        standalone=true;
        if(path){mode="print";open(path,null);}
        else {mode="scan";visible=true;Core.Printing.refresh();requestActivate();}
    }
    function adoptScans(info) {
        if(document && document.token!==info.token)send({action:"release",token:document.token});
        generation++;
        document=info;sourcePath="";page=1;previewUrl="";preparing=false;submitted=false;jobId=0;problem="";
        schedulePreview.restart();
    }
    function prepareScans() {
        if(!scanPane || sourcePath!=="")return;
        if(scanPane.scanning){preparing=true;return;}
        if(!scanPane.pages.length){
            if(document)send({action:"release",token:document.token});
            document=null;previewUrl="";preparing=false;return;
        }
        if(scanPane.dirty || !document){preparing=true;scanPane.buildPdf();}
    }
    function setMode(value){mode=value;if(value==="print")prepareScans();}
    function openDocument() {
        if(submitting || scanPane && scanPane.pages.length)return;
        filePicker.proprietario=dialog;filePicker.apri(sourcePath ? sourcePath.substring(0,sourcePath.lastIndexOf("/")) : "");
    }
    function newDocument() {
        if(submitting)return;
        if(scanPane && scanPane.scanning){scanPane.cancel();return;}
        if(scanPane && scanPane.unsaved){confirmAction="new";return;}
        clearDocument();
    }
    function clearDocument() {
        if(scanPane && !scanPane.clear())return false;
        if(document)send({action:"release",token:document.token});
        generation++;document=null;sourcePath="";previewUrl="";problem="";preparing=false;submitted=false;jobId=0;confirmAction="";
        return true;
    }
    function open(path,owner) {
        if(submitting)return;
        if(document)send({action:"release",token:document.token});
        generation++;
        sourcePath=path;document=null;page=1;previewUrl="";problem="";submitted=false;jobId=0;preparing=true;
        ranges.text="";copies.text="1";orientation="portrait";
        transientParent=owner || null;
        visible=true;
        requestActivate();
        Core.Printing.refresh();
        send({action:"prepare",file:path});
    }
    function send(request) {
        request.generation=generation;
        worker.start(["python3","-I",helper,JSON.stringify(request)]);
    }
    function dismiss() {
        if(submitting)return;
        if(standalone && scanPane && scanPane.scanning){scanPane.cancel();return;}
        if(standalone && scanPane && scanPane.unsaved){confirmAction="close";return;}
        closeNow();
    }
    function closeNow(){if(clearDocument()){visible=false;dismissed();}}
    function choosePrinter(name) {
        printerName=name;
        if(!printer)return;
        media=printer.paperDefault || (printer.media || [])[0] || "";
        sides=(printer.sides || []).indexOf("one-sided")>=0 ? "one-sided" : (printer.sides || [])[0] || "";
        colorMode=(printer.colors || []).indexOf("monochrome")>=0 ? "monochrome" : (printer.colors || [])[0] || "";
        schedulePreview.restart();
    }
    function preview() {
        if(!visible || !document)return;
        if(worker.busy){schedulePreview.restart();return;}
        send({action:"preview",token:document.token,page:page,monochrome:colorMode==="monochrome"});
    }
    function submitPrint() {
        if(!canSubmit)return;
        var options={copies:Number(copies.text),orientation:orientation};
        if(media)options.media=media;
        if(sides)options.sides=sides;
        if(colorMode)options.color=colorMode;
        if(ranges.text.trim())options.pages=ranges.text.trim();
        problem="";submitting=true;
        if(!Core.Printing.request({action:"print-document",printer:printerName,token:document.token,options:options}))submitting=false;
    }
    onPageChanged:schedulePreview.restart()
    onColorModeChanged:schedulePreview.restart()
    Timer {id:schedulePreview;interval:120;onTriggered:dialog.preview()}
    Core.Exec {
        id:worker
        timeoutMs:60000
        onCompleted:function(code,out,stderr) {
            try {
                if(code!==0)throw new Error(stderr || dialog.label("Preparazione non riuscita", "Preparation failed"));
                var result=JSON.parse(out);
                if(result.generation!==dialog.generation) {
                    if(result.action==="prepare" && result.ok)dialog.send({action:"release",token:result.token});
                    return;
                }
                if(!result.ok)throw new Error(Core.Printing.operationError(result.message));
                if(result.action==="prepare") {
                    dialog.document=result;dialog.preparing=false;schedulePreview.restart();
                } else if(result.action==="preview" && result.page===dialog.page && result.monochrome===(dialog.colorMode==="monochrome"))dialog.previewUrl=result.url;
            } catch(error) {dialog.preparing=false;dialog.problem=String(error.message || error);}
        }
    }
    Connections {
        target:dialog
        function onActiveFocusItemChanged() {
            var item=dialog.activeFocusItem;
            var ancestor=item;
            while(ancestor && ancestor!==settingsColumn)ancestor=ancestor.parent;
            if(!item || ancestor!==settingsColumn)return;
            var position=item.mapToItem(settingsScroll,0,0);
            var next=settingsScroll.contentY;
            if(position.y<8)next+=position.y-8;
            else if(position.y+item.height>settingsScroll.height-8)next+=position.y+item.height-settingsScroll.height+8;
            settingsScroll.contentY=Math.max(0,Math.min(next,Math.max(0,settingsScroll.contentHeight-settingsScroll.height)));
        }
    }
    Win.ScegliFileWindows {
        id:filePicker
        purpose:"file"
        allowedExtensions:[".pdf",".png",".jpg",".jpeg",".tif",".tiff",".webp",".bmp",".txt"]
        onScelto:function(path){dialog.mode="print";dialog.open(path,null);}
    }
    Component {
        id:scanComponent
        ScanPane {
            acquiringAllowed:dialog.sourcePath==="" || !dialog.document && !dialog.preparing
            onDocumentReady:function(info){dialog.adoptScans(info);}
            onChanged:{dialog.submitted=false;if(dialog.mode==="print")dialog.prepareScans();}
            onAcquisitionFinished:if(dialog.mode==="print")dialog.prepareScans()
            onProcessingFailed:function(message){dialog.preparing=false;dialog.problem=message;if(overwritePath==="")dialog.afterSaveAction="";}
            onSaveCancelled:dialog.afterSaveAction=""
            onSaved:function(path){
                var action=dialog.afterSaveAction;dialog.afterSaveAction="";
                if(action==="close")dialog.closeNow();else if(action==="new")dialog.clearDocument();
            }
        }
    }
    Connections {
        target:Core.Printing
        function onRefreshed() {
            if(!dialog.visible)return;
            if(dialog.submitting && Core.Printing.lastAction==="print-document") {
                dialog.submitting=false;
                if(Core.Printing.error)dialog.problem=Core.Printing.error;
                else {dialog.submitted=true;dialog.jobId=Core.Printing.lastSubmittedJob;}
            }
            if(!dialog.printer && Core.Printing.printers.length) {
                var preferred=Core.Printing.printers.find(function(row){return row.default;}) || Core.Printing.printers[0];
                dialog.choosePrinter(preferred.name);
            }
        }
    }
    component Label:Text {
        width:parent.width
        color:dialog.ink
        font.family:dialog.windows ? W.Style.font : Theme.Typography.fontDisplay
        font.pixelSize:14
        textFormat:Text.PlainText
        wrapMode:Text.Wrap
    }
    Item {
        id:root
        anchors.fill:parent
        Keys.onEscapePressed:function(event){if(!event.isAutoRepeat)dialog.dismiss();}
        Rectangle {
            id:titleBar
            width:parent.width;height:38;color:dialog.color
            Label {x:16;width:parent.width-(dialog.standalone ? 160 : 70);anchors.verticalCenter:parent.verticalCenter;text:dialog.title;font.pixelSize:13}
            DragHandler {target:null;onActiveChanged:if(active)dialog.startSystemMove()}
            Row {
                visible:dialog.standalone
                anchors.right:parent.right;anchors.rightMargin:44
                S.PrintingAction {objectName:"documentMinimize";width:44;implicitWidth:44;height:38;text:"−";onClicked:dialog.showMinimized()}
                S.PrintingAction {objectName:"documentMaximize";width:44;implicitWidth:44;height:38;text:dialog.visibility===Window.Maximized ? "❐" : "□";onClicked:dialog.visibility===Window.Maximized ? dialog.showNormal() : dialog.showMaximized()}
            }
            S.PrintingAction {objectName:"printClose";anchors.right:parent.right;width:44;implicitWidth:44;height:38;text:"×";enabled:!dialog.submitting;onClicked:dialog.dismiss()}
        }
        Item {
            id:modeBar
            y:titleBar.height;width:parent.width;height:dialog.modeBarHeight;visible:dialog.standalone
            Rectangle {
                x:20;y:6;width:260;height:36;radius:6;color:dialog.paperSurface;border.width:1;border.color:Qt.alpha(dialog.ink,0.15)
                Row {
                    Repeater {
                        model:[{value:"print",text:dialog.label("Stampa","Print")},{value:"scan",text:dialog.label("Scansione","Scan")}]
                        delegate:Rectangle {
                            required property var modelData
                            objectName:"documentMode-"+modelData.value
                            width:130;height:36;radius:6;color:dialog.mode===modelData.value ? Qt.alpha(dialog.ink,0.06) : "transparent"
                            activeFocusOnTab:true
                            Accessible.role:Accessible.PageTab
                            Accessible.name:modelData.text
                            Accessible.selected:dialog.mode===modelData.value
                            Keys.onReturnPressed:dialog.setMode(modelData.value)
                            Label {anchors.centerIn:parent;width:parent.width;text:parent.modelData.text;horizontalAlignment:Text.AlignHCenter;font.weight:dialog.mode===parent.modelData.value ? Font.DemiBold : Font.Normal}
                            Rectangle {anchors.bottom:parent.bottom;anchors.bottomMargin:2;anchors.horizontalCenter:parent.horizontalCenter;width:36;height:3;radius:1;color:dialog.windows ? W.Style.accent : Theme.Colors.accent;visible:dialog.mode===parent.modelData.value}
                            MouseArea {anchors.fill:parent;onClicked:dialog.setMode(parent.modelData.value)}
                        }
                    }
                }
            }
            Row {
                anchors.right:parent.right;anchors.rightMargin:20;y:8;spacing:8
                S.PrintingAction {objectName:"documentNew";text:dialog.label("Nuovo documento","New document");enabled:!dialog.submitting && (!dialog.scanPane || !dialog.scanPane.building);onClicked:dialog.newDocument()}
                S.PrintingAction {objectName:"documentOpen";text:dialog.label("Apri documento…","Open document…");enabled:!dialog.submitting && (!dialog.scanPane || !dialog.scanPane.pages.length);onClicked:dialog.openDocument()}
            }
        }
        Loader {
            id:scanLoader
            active:dialog.standalone
            sourceComponent:scanComponent
            x:0;y:titleBar.height+dialog.modeBarHeight;width:parent.width;height:parent.height-y
            visible:active && dialog.mode==="scan"
        }
        Rectangle {
            id:settings
            visible:dialog.mode==="print"
            x:0;y:titleBar.height+dialog.modeBarHeight
            width:320;height:parent.height-y-74
            color:dialog.paperSurface
            Flickable {
                id:settingsScroll
                anchors.fill:parent;anchors.margins:20
                contentHeight:settingsColumn.height
                clip:true
                boundsBehavior:Flickable.StopAtBounds
                Column {
                    id:settingsColumn
                    width:settingsScroll.width-settingsBar.width-8;spacing:12
                    Label {text:dialog.label("Stampante", "Printer");font.weight:Font.DemiBold}
                    Choice {
                        objectName:"printPrinter";width:parent.width
                        options:Core.Printing.printers.map(function(row){return {value:row.name,label:row.description};})
                        value:dialog.printerName;enabled:!dialog.submitting && !dialog.submitted
                        onPicked:function(value){dialog.choosePrinter(value);}
                    }
                    Label {text:dialog.printer ? Core.Printing.stateLabel(dialog.printer) : Core.Printing.error || dialog.label("Nessuna stampante installata", "No installed printer");color:dialog.muted;font.pixelSize:12}
                    S.PrintingAction {text:dialog.label("Gestisci stampanti", "Manage printers");onClicked:Quickshell.execDetached(["minerva-settings","stampanti"])}
                    Label {text:dialog.label("Copie", "Copies")}
                    Field {id:copies;objectName:"printCopies";width:parent.width;text:"1";validator:IntValidator {bottom:1;top:Math.min(999,dialog.printer && dialog.printer.copies ? dialog.printer.copies[1] : 1)} enabled:!dialog.submitting && !dialog.submitted}
                    Label {text:dialog.label("Pagine", "Pages")}
                    Field {id:ranges;objectName:"printPageRanges";width:parent.width;enabled:!dialog.submitting && !dialog.submitted}
                    Label {text:dialog.label("Vuoto = tutte · esempio: 1,3-5", "Empty = all · example: 1,3-5");font.pixelSize:12;color:dialog.rangesValid || !dialog.document ? dialog.muted : "#D13438"}
                    Label {text:dialog.label("Formato carta", "Paper size")}
                    Choice {
                        objectName:"printMedia";width:parent.width;value:dialog.media
                        options:((dialog.printer && dialog.printer.media) || []).filter(function(s){return !/^custom_(min|max)_/.test(s);}).map(function(s){var p=s.split("_");return {value:s,label:p.length>=3 ? p[1].toUpperCase()+" · "+p[2] : s};})
                        enabled:!!dialog.printer && !dialog.submitting && !dialog.submitted
                        onPicked:function(value){dialog.media=value;}
                    }
                    Label {text:dialog.label("Orientamento", "Orientation")}
                    Choice {objectName:"printOrientation";width:parent.width;value:dialog.orientation;options:[{value:"portrait",label:dialog.label("Verticale", "Portrait")},{value:"landscape",label:dialog.label("Orizzontale", "Landscape")}];enabled:!dialog.submitting && !dialog.submitted;onPicked:function(value){dialog.orientation=value;}}
                    Label {text:dialog.label("Colore", "Color")}
                    Choice {
                        objectName:"printColor";width:parent.width;value:dialog.colorMode
                        options:((dialog.printer && dialog.printer.colors) || []).map(function(s){return {value:s,label:s==="monochrome" ? dialog.label("Bianco e nero", "Black and white") : s==="color" ? dialog.label("Colore", "Color") : s};})
                        enabled:!!dialog.printer && !dialog.submitting && !dialog.submitted
                        onPicked:function(value){dialog.colorMode=value;}
                    }
                    Label {text:dialog.label("Fronte-retro", "Two-sided printing")}
                    Choice {
                        objectName:"printSides";width:parent.width;value:dialog.sides
                        options:((dialog.printer && dialog.printer.sides) || []).map(function(s){return {value:s,label:s==="one-sided" ? dialog.label("Solo fronte", "One-sided") : s==="two-sided-long-edge" ? dialog.label("Lato lungo", "Long edge") : s==="two-sided-short-edge" ? dialog.label("Lato corto", "Short edge") : s};})
                        enabled:!!dialog.printer && !dialog.submitting && !dialog.submitted
                        onPicked:function(value){dialog.sides=value;}
                    }
                }
            }
            Ui.Scorrimento {id:settingsBar;bersaglio:settingsScroll;anchors.right:settingsScroll.right;anchors.top:settingsScroll.top;anchors.bottom:settingsScroll.bottom}
        }
        Item {
            visible:dialog.mode==="print"
            x:settings.width+24;y:titleBar.height+dialog.modeBarHeight+20
            width:parent.width-x-24;height:parent.height-y-90
            Label {id:documentTitle;text:dialog.document ? dialog.document.name : dialog.preparing ? dialog.label("Preparazione del documento…", "Preparing document…") : dialog.label("Nessun documento selezionato","No document selected");font.pixelSize:20;font.weight:Font.DemiBold}
            Rectangle {
                anchors.top:documentTitle.bottom;anchors.topMargin:18
                anchors.bottom:pageNavigation.top;anchors.bottomMargin:18
                width:parent.width
                color:Qt.alpha(dialog.ink,0.06);radius:6
                Image {objectName:"printPreviewImage";anchors.fill:parent;anchors.margins:16;source:dialog.previewUrl;asynchronous:true;fillMode:Image.PreserveAspectFit;cache:false}
                Label {anchors.centerIn:parent;text:dialog.preparing ? dialog.label("Preparazione…", "Preparing…") : dialog.problem;visible:dialog.previewUrl==="";horizontalAlignment:Text.AlignHCenter}
                S.PrintingAction {anchors.centerIn:parent;visible:dialog.standalone && !dialog.document && !dialog.preparing;text:dialog.label("Apri documento…","Open document…");onClicked:dialog.openDocument()}
            }
            Row {
                id:pageNavigation
                anchors.bottom:note.top;anchors.bottomMargin:12
                anchors.horizontalCenter:parent.horizontalCenter
                spacing:14
                S.PrintingAction {objectName:"printPreviousPage";text:"‹";implicitWidth:42;width:42;enabled:dialog.page>1;onClicked:dialog.page--}
                Text {anchors.verticalCenter:parent.verticalCenter;color:dialog.ink;text:dialog.document ? dialog.page+" / "+dialog.document.pageCount : "—";font.pixelSize:14}
                S.PrintingAction {objectName:"printNextPage";text:"›";implicitWidth:42;width:42;enabled:!!dialog.document && dialog.page<dialog.document.pageCount;onClicked:dialog.page++}
            }
            Label {id:note;anchors.bottom:parent.bottom;text:dialog.label("Anteprima del documento. L’adattamento al foglio e i margini dipendono dal driver.", "Document preview. Paper fitting and margins depend on the driver.");color:dialog.muted;font.pixelSize:12}
        }
        Rectangle {
            visible:dialog.mode==="print"
            anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:parent.bottom;height:74;color:dialog.paperSurface
            Label {x:20;anchors.verticalCenter:parent.verticalCenter;width:parent.width-340;text:dialog.submitted ? dialog.label("Lavoro inviato · #", "Job submitted · #")+dialog.jobId : dialog.problem || (dialog.submitting ? dialog.label("Invio alla stampante…", "Sending to printer…") : "");font.pixelSize:13}
            Row {
                anchors.right:parent.right;anchors.rightMargin:20;anchors.verticalCenter:parent.verticalCenter;spacing:10
                S.PrintingAction {objectName:"printCancel";text:dialog.submitted ? dialog.label("Chiudi", "Close") : dialog.label("Annulla", "Cancel");enabled:!dialog.submitting;onClicked:dialog.dismiss()}
                Win.PulsanteWindows {objectName:"printSubmitWindows";visible:dialog.windows;testo:dialog.label("Stampa", "Print");accento:true;enabled:dialog.canSubmit;onPremuto:dialog.submitPrint()}
                S.PrintingAction {objectName:"printSubmitLiquid";visible:!dialog.windows;text:dialog.label("Stampa", "Print");enabled:dialog.canSubmit;onClicked:dialog.submitPrint()}
            }
        }
        Rectangle {
            visible:dialog.confirmAction!=="";anchors.fill:parent;color:"#66000000";z:100
            MouseArea {anchors.fill:parent}
            Rectangle {
                anchors.centerIn:parent;width:480;height:190;radius:dialog.windows ? 8 : 16;color:dialog.paperSurface;border.width:1;border.color:Qt.alpha(dialog.ink,0.2)
                Label {x:24;y:24;width:parent.width-48;text:dialog.label("Il documento contiene pagine non salvate. Puoi salvarle in PDF oppure scartare questa sessione.","The document contains unsaved pages. Save them as PDF or discard this session.");font.pixelSize:16}
                Row {
                    x:24;y:126;spacing:8
                    S.PrintingAction {objectName:"documentKeepEditing";text:dialog.label("Annulla","Cancel");onClicked:dialog.confirmAction=""}
                    S.PrintingAction {objectName:"documentSaveBeforeClose";text:dialog.label("Salva PDF…","Save PDF…");onClicked:{dialog.afterSaveAction=dialog.confirmAction;dialog.confirmAction="";dialog.mode="scan";if(dialog.scanPane)dialog.scanPane.savePdf();}}
                    S.PrintingAction {objectName:"documentDiscard";text:dialog.label("Scarta","Discard");onClicked:{var action=dialog.confirmAction;dialog.confirmAction="";if(action==="close")dialog.closeNow();else dialog.clearDocument();}}
                }
            }
        }
    }
}

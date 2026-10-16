import QtQuick
import QtQuick.Window
import Quickshell
import "../core" as Core
import "../theme" as Theme
import "../windows11" as W
import "../settings" as S
import "../settings/windows" as Win
import "../ui" as Ui

Item {
    id:scan
    objectName:"liquidScanPane"
    readonly property bool windows:Core.DesktopStyle.attuale === "windows"
    readonly property bool it:Core.Strings.lang === "it"
    readonly property color ink:windows ? W.Style.text : Theme.Colors.text
    readonly property color muted:windows ? W.Style.muted : Theme.Colors.textMuted
    readonly property color surface:windows ? W.Style.card : Theme.Colors.raised
    readonly property color accent:windows ? W.Style.accent : Theme.Colors.accent
    readonly property string scanHelper:(Quickshell.env("LIQUID_DE") || Quickshell.shellDir+"/..")+"/scripts/liquid-scan.py"
    readonly property string documentHelper:(Quickshell.env("LIQUID_DE") || Quickshell.shellDir+"/..")+"/scripts/liquid_print_document.py"
    property var devices:[]
    property string device:""
    property var capabilities:[]
    property string source:""
    property string scanMode:""
    property string resolution:""
    property string area:"auto"
    property bool batch:false
    property var pages:[]
    property int current:0
    readonly property var currentPage:pages[current] || null
    property var jobs:[]
    property var removed:[]
    property string activeJob:""
    property bool scanning:false
    property bool building:false
    property bool dirty:false
    property string savedPath:""
    readonly property bool unsaved:pages.length>0 && savedPath===""
    readonly property bool busy:scanner.busy || documentWorker.busy || cancellation.busy
    property int generation:0
    property int revision:0
    property string status:""
    property string tool:"move"
    property string annotationColor:"#E81123"
    property bool filled:false
    property var prepared:null
    property var previewData:null
    property string previewToken:""
    property var captureOptions:({})
    property string preferredMode:"Gray"
    property string preferredResolution:""
    property string savePath:""
    property bool saveOverwrite:false
    property string overwritePath:""
    property bool acquiringAllowed:true
    signal documentReady(var document)
    signal changed()
    signal saved(string path)
    signal saveCancelled()
    signal processingFailed(string message)
    signal acquisitionFinished()
    function label(a,b){return it ? a : b;}
    function option(name){return capabilities.find(function(row){return row.name===name && row.active;}) || null;}
    function sourceLabel(value) {
        var labels={"Flatbed":["Vetro","Flatbed"],"ADF":["Alimentatore","Document feeder"],"Automatic Document Feeder":["Alimentatore","Document feeder"],"ADF Front":["Alimentatore · fronte","Feeder · front"],"ADF Duplex":["Alimentatore · fronte-retro","Feeder · duplex"]};
        return labels[value] ? labels[value][it ? 0 : 1] : value;
    }
    function modeLabel(value){return value==="Gray" ? label("Scala di grigi","Grayscale") : value==="Color" ? label("Colore","Color") : value==="Lineart" ? label("Bianco e nero","Black and white") : value;}
    readonly property bool feeder:/^(ADF\b|Automatic Document Feeder\b|Document Feeder\b)/i.test(source)
    readonly property var resolutionChoices: {
        var row=option("resolution");if(!row)return [];
        var values=(row.choices || []).slice();
        if(!values.length && row.range)values=[row.range.min,50,75,100,150,200,300,400,600,1200,2400,4800,9600,row.range.max].filter(function(value){return value>=row.range.min && value<=row.range.max && (!row.range.quant || Math.abs((value-row.range.min)/row.range.quant-Math.round((value-row.range.min)/row.range.quant))<0.001);});
        if(typeof row.value==="number" && isFinite(row.value) && row.value>0)values.push(row.value);
        return values.filter(function(value,index,all){return all.indexOf(value)===index;}).sort(function(a,b){return a-b;}).map(function(value){return {value:String(value),label:value+" dpi"};});
    }
    readonly property var areas: {
        var out=[{value:"auto",label:label("Area predefinita","Default area")}];
        var x=option("br-x"),y=option("br-y");
        if(!x || !y || x.unit!==3 || y.unit!==3 || !x.range || !y.range)return out;
        function supports(row,value){return value>=row.range.min && value<=row.range.max+0.00001 && (!row.range.quant || Math.abs((value-row.range.min)/row.range.quant-Math.round((value-row.range.min)/row.range.quant))<0.001);}
        var left=option("tl-x"),top=option("tl-y");
        if(!left || !top || !left.range || !top.range || !supports(left,0) || !supports(top,0))return out;
        for(var page of [{value:"A4",w:210,h:297},{value:"Letter",w:215.9,h:279.4},{value:"A5",w:148,h:210}])
            if(supports(x,page.w) && supports(y,page.h))out.push({value:page.value,label:page.value});
        return out;
    }
    function message(value) {
        var messages={"no-documents":["Nessun foglio rilevato nell’alimentatore.","No paper detected in the feeder."],"cancelled":["Acquisizione interrotta. Le pagine complete sono state conservate.","Acquisition cancelled. Complete pages have been kept."],"timeout":["Tempo di acquisizione superato. Le pagine complete sono state conservate.","Acquisition timed out. Complete pages have been kept."],"sane-status-3":["Scanner occupato. Chiudi le altre acquisizioni e riprova.","Scanner busy. Close other scanning tasks and retry."],"sane-status-6":["Foglio inceppato nell’alimentatore.","Paper jam in the feeder."],"sane-status-8":["Il coperchio dello scanner è aperto.","The scanner cover is open."],"sane-status-9":["Comunicazione con lo scanner interrotta.","Scanner communication interrupted."],"sane-status-11":["Accesso allo scanner negato. Verifica permessi e driver.","Scanner access denied. Check permissions and drivers."],"scanner-no-longer-discovered":["Scanner non più rilevato. Accendilo e premi Cerca.","Scanner no longer detected. Turn it on and press Search."],"invalid-page-edit":["Annotazione o ritaglio non valido.","Invalid annotation or crop."],"output-file-exists":["Il PDF esiste già. Usa Sostituisci file per confermare.","The PDF already exists. Use Replace file to confirm."]};
        Object.assign(messages,{
            "unsupported-scan-value":["Lo scanner non supporta questa impostazione. Scegli uno dei valori disponibili.","The scanner does not support this setting. Choose an available value."],
            "scanner-open-timeout":["Lo scanner non risponde. Verifica che sia acceso e raggiungibile.","The scanner is not responding. Check power and connection."],
            "sane-support-missing":["Manca il supporto scanner SANE. Installa il pacchetto sane.","SANE scanner support is missing. Install the sane package."],
            "scan-job-active":["Acquisizione ancora attiva: interrompila prima di chiudere il documento.","Acquisition still active: cancel it before closing the document."]
        });
        return messages[value] ? messages[value][it ? 0 : 1] : Core.Printing.operationError(value);
    }
    function request(data) {data.generation=generation;scanner.timeoutMs=data.action==="capture" ? 650000 : 35000;scanner.start(["python3","-I",scanHelper,JSON.stringify(data)]);}
    function documentRequest(data){data.generation=generation;documentWorker.start(["python3","-I",documentHelper,JSON.stringify(data)]);}
    function discover(){if(busy || scanning)return;status=label("Ricerca degli scanner…","Searching for scanners…");request({action:"discover"});}
    function chooseDevice(value) {
        if(busy || scanning)return;device=value;capabilities=[];preferredMode="Gray";preferredResolution="";
        request({action:"capabilities",device:device});
    }
    function setSource(value) {
        preferredMode=scanMode;preferredResolution=resolution;
        request({action:"capabilities",device:device,options:{source:value}});
    }
    function setMode(value) {
        preferredMode=value;preferredResolution=resolution;
        var selections={mode:value};if(source)selections.source=source;
        request({action:"capabilities",device:device,options:selections});
    }
    function acquire() {
        if(!acquiringAllowed || busy || scanning || !device || !capabilities.length)return;
        var selected={};if(source)selected.source=source;if(scanMode)selected.mode=scanMode;if(resolution)selected.resolution=Number(resolution);
        var size=area==="A4" ? [210,297] : area==="Letter" ? [215.9,279.4] : area==="A5" ? [148,210] : null;
        if(size){selected["tl-x"]=0;selected["tl-y"]=0;selected["br-x"]=size[0];selected["br-y"]=size[1];}
        captureOptions=selected;scanning=true;status=label("Preparazione dello scanner…","Preparing scanner…");request({action:"create-job"});
    }
    function cancel() {
        if(!scanning || !activeJob)return;
        status=label("Annullamento in corso…","Cancelling…");
        cancellation.start(["python3","-I",scanHelper,JSON.stringify({action:"cancel",token:activeJob})]);
    }
    function touch() {dirty=true;savedPath="";overwritePath="";revision++;changed();previewTimer.restart();}
    function edit(changes) {
        if(!currentPage || scanning || building)return;
        var items=pages.slice(),entry=Object.assign({},currentPage);
        entry.history=(entry.history || []).concat([JSON.parse(JSON.stringify({rotation:entry.rotation,crop:entry.crop,annotations:entry.annotations}))]).slice(-50);
        items[current]=Object.assign(entry,changes);pages=items;touch();
    }
    function undo() {
        if(!currentPage || !currentPage.history || !currentPage.history.length)return;
        var items=pages.slice(),entry=Object.assign({},currentPage),history=entry.history.slice(),old=history.pop();
        items[current]=Object.assign(entry,old,{history:history});pages=items;touch();
    }
    function turnPoint(x,y){return [1-y,x];}
    function rotate() {
        if(!currentPage)return;
        var annotations=(currentPage.annotations || []).map(function(item){
            var out=Object.assign({},item);
            if(item.kind==="line" || item.kind==="arrow"){
                var a=turnPoint(item.x,item.y),b=turnPoint(item.x2,item.y2);out.x=a[0];out.y=a[1];out.x2=b[0];out.y2=b[1];
            }else {out.x=1-item.y-item.h;out.y=item.x;out.w=item.h;out.h=item.w;if(item.kind==="text" || item.kind==="note")out.rotation=((item.rotation || 0)+90)%360;}
            return out;
        });
        var old=currentPage.crop,crop=old ? [1-old[1]-old[3],old[0],old[3],old[2]] : null;
        edit({rotation:(currentPage.rotation+90)%360,crop:crop,annotations:annotations});
    }
    function movePage(delta) {
        var target=current+delta;if(target<0 || target>=pages.length || scanning || building)return;
        var items=pages.slice(),entry=items.splice(current,1)[0];items.splice(target,0,entry);pages=items;current=target;touch();
    }
    function removePage() {
        if(!currentPage || scanning || building)return;
        var items=pages.slice();removed=removed.concat([{index:current,page:items.splice(current,1)[0]}]);pages=items;current=Math.max(0,Math.min(current,pages.length-1));touch();
    }
    function restorePage(){if(!removed.length)return;var undo=removed.slice(),entry=undo.pop(),items=pages.slice();items.splice(entry.index,0,entry.page);removed=undo;pages=items;current=entry.index;touch();}
    function buildPdf() {
        if(!pages.length || scanning || building)return;
        if(!dirty && prepared){documentReady(prepared);return;}
        building=true;status=label("Preparazione del PDF…","Preparing PDF…");
        documentRequest({action:"compose",pages:pages.map(function(page){return {path:page.path,dpi:page.dpi,rotation:page.rotation,crop:page.crop,annotations:page.annotations};}),title:label("Documento scansionato.pdf","Scanned document.pdf")});
    }
    function savePdf() {
        if(!pages.length || scanning || building)return;
        picker.proprietario=scan.Window.window;picker.apri(savedPath ? savedPath.substring(0,savedPath.lastIndexOf("/")) : "");
    }
    function saveTo(path,overwrite) {
        savePath=path;saveOverwrite=overwrite;
        if(dirty || !prepared)buildPdf();
        else {building=true;documentRequest({action:"save",token:prepared.token,path:path,overwrite:overwrite});}
    }
    function clear() {
        if(scanning){cancel();return false;}
        if(building)return false;
        generation++;
        for(var token of jobs)request({action:"release",token:token});
        if(previewToken)documentRequest({action:"release",token:previewToken});
        jobs=[];pages=[];removed=[];current=0;dirty=false;savedPath="";previewToken="";previewData=null;prepared=null;savePath="";overwritePath="";status="";
        return true;
    }
    function makePreview() {
        if(!visible || !currentPage)return;
        if(documentWorker.busy || building){previewTimer.restart();return;}
        documentRequest({action:"scan-preview",page:currentPage,revision:revision});
    }
    onCurrentChanged:{revision++;previewData=null;previewTimer.restart();}
    onVisibleChanged:if(visible)previewTimer.restart()
    Timer {id:previewTimer;interval:150;onTriggered:scan.makePreview()}
    Core.Exec {id:cancellation;timeoutMs:10000}
    Core.Exec {
        id:scanner
        onCompleted:function(code,out,stderr){
            try {
                if(code!==0)throw new Error(stderr || scan.label("Servizio scanner non disponibile","Scanner service unavailable"));
                var result=JSON.parse(out);
                if(result.generation!==scan.generation)return;
                if(!result.ok)throw new Error(scan.message(result.message));
                if(result.action==="discover") {
                    scan.devices=result.devices;scan.status=result.devices.length ? "" : scan.label("Nessuno scanner rilevato. Verifica cavo o rete.","No scanner detected. Check cable or network.");
                    if(result.devices.length){scan.device=result.devices[0].id;scan.preferredMode="Gray";scan.request({action:"capabilities",device:scan.device});}
                }else if(result.action==="capabilities") {
                    scan.capabilities=result.options;
                    var source=scan.option("source"),mode=scan.option("mode"),resolution=scan.option("resolution");
                    scan.source=source ? String(source.value || "") : "";
                    scan.scanMode=mode ? String(mode.value || "") : "";
                    if(mode && scan.preferredMode && mode.choices.indexOf(scan.preferredMode)>=0 && scan.preferredMode!==scan.scanMode){
                        var wanted=scan.preferredMode;scan.preferredMode="";
                        var selections={mode:wanted};if(scan.source)selections.source=scan.source;
                        scan.request({action:"capabilities",device:scan.device,options:selections});return;
                    }
                    scan.resolution=scan.resolutionChoices.some(function(row){return row.value===scan.preferredResolution;}) ? scan.preferredResolution : resolution ? String(resolution.value) : "";
                    if(!scan.areas.some(function(row){return row.value===scan.area;}))scan.area="auto";
                    if(scan.area==="auto" && scan.areas.some(function(row){return row.value==="A4";}))scan.area="A4";
                    scan.status="";
                }else if(result.action==="create-job"){
                    scan.activeJob=result.token;scan.jobs=scan.jobs.concat([result.token]);
                    scan.request({action:"capture",token:result.token,device:scan.device,options:scan.captureOptions,batch:scan.batch && scan.feeder});
                    scan.status=scan.label("Acquisizione in corso…","Scanning…");
                }else if(result.action==="capture"){
                    scan.scanning=false;scan.activeJob="";
                    var dpi=result.applied && result.applied.resolution ? result.applied.resolution : 300;
                    var first=scan.pages.length;
                    scan.pages=scan.pages.concat((result.pages || []).map(function(page){return {path:page.path,url:page.url,dpi:dpi,rotation:0,crop:null,annotations:[],history:[]};}));
                    if(scan.pages.length>first){scan.current=first;scan.touch();}
                    scan.status=result.status==="complete" ? scan.label("Acquisizione completata · ","Acquisition complete · ")+(result.pages || []).length+scan.label(" pagine"," pages") : scan.message(result.status);
                    if(result.pageLimitReached)scan.status+=scan.label(" · Raggiunto il limite di 100 fogli: premi Prossimo foglio per continuare."," · 100-sheet limit reached: press Next sheet to continue.");
                    scan.acquisitionFinished();
                }
            }catch(error){scan.scanning=false;scan.activeJob="";scan.status=String(error.message || error);scan.acquisitionFinished();}
        }
    }
    Core.Exec {
        id:documentWorker
        timeoutMs:120000
        onCompleted:function(code,out,stderr){
            try {
                if(code!==0)throw new Error(stderr || scan.label("Elaborazione non riuscita","Processing failed"));
                var result=JSON.parse(out);
                if(result.generation!==scan.generation || result.action==="scan-preview" && result.revision!==scan.revision){
                    if(result.ok && result.kind)scan.documentRequest({action:"release",token:result.token});
                    return;
                }
                if(!result.ok) {
                    if(result.message==="output-file-exists"){scan.overwritePath=scan.savePath;scan.savePath="";}
                    throw new Error(scan.message(result.message));
                }
                if(result.action==="scan-preview"){
                    var previous=scan.previewToken;scan.previewToken=result.token;scan.previewData=result;
                    if(previous)scan.documentRequest({action:"release",token:previous});
                }else if(result.action==="compose"){
                    scan.building=false;scan.dirty=false;scan.prepared=result;scan.documentReady(result);scan.status="";
                    if(scan.savePath){scan.building=true;scan.documentRequest({action:"save",token:result.token,path:scan.savePath,overwrite:scan.saveOverwrite});}
                }else if(result.action==="save"){
                    scan.building=false;scan.savedPath=result.path;scan.savePath="";scan.overwritePath="";scan.status=scan.label("PDF salvato: ","PDF saved: ")+result.path;scan.saved(result.path);
                }
            }catch(error){scan.building=false;scan.savePath="";scan.saveOverwrite=false;scan.status=String(error.message || error);scan.processingFailed(scan.status);}
        }
    }
    Win.ScegliFileWindows {id:picker;purpose:"save";initialName:scan.label("Scansione.pdf","Scan.pdf");allowedExtensions:[".pdf"];onScelto:function(path){scan.saveTo(path,false);}onAnnullato:scan.saveCancelled()}
    Component.onCompleted:discover()
    component Label:Text {width:parent.width;wrapMode:Text.Wrap;textFormat:Text.PlainText;color:scan.ink;font.family:scan.windows ? W.Style.font : Theme.Typography.fontDisplay;font.pixelSize:14}
    Rectangle {
        id:left
        width:300;height:parent.height;color:scan.surface
        Flickable {
            id:optionsScroll;x:16;y:16;width:parent.width-32;height:Math.min(optionsColumn.height,parent.height*0.7)
            clip:true;contentHeight:optionsColumn.height;boundsBehavior:Flickable.StopAtBounds
            Column {
                id:optionsColumn;width:optionsScroll.width-26;spacing:8
                Label {text:scan.label("Scanner","Scanner");font.weight:Font.DemiBold}
                Choice {objectName:"scanDevice";width:parent.width;options:scan.devices.map(function(row){return {value:row.id,label:row.name};});value:scan.device;enabled:!scan.busy && !scan.scanning;onPicked:function(value){scan.chooseDevice(value);}}
                S.PrintingAction {objectName:"scanDiscover";text:scan.label("Cerca USB e rete","Find USB and network");enabled:!scan.busy && !scan.scanning;onClicked:scan.discover()}
                Label {text:scan.label("Origine","Source")}
                Choice {objectName:"scanSource";width:parent.width;value:scan.source;options:scan.option("source") ? scan.option("source").choices.map(function(value){return {value:value,label:scan.sourceLabel(value)};}) : [];enabled:!scan.busy && !scan.scanning;onPicked:function(value){scan.setSource(value);}}
                Label {text:scan.label("Colore","Color")}
                Choice {objectName:"scanMode";width:parent.width;value:scan.scanMode;options:scan.option("mode") ? scan.option("mode").choices.map(function(value){return {value:value,label:scan.modeLabel(value)};}) : [];enabled:!scan.busy && !scan.scanning;onPicked:function(value){scan.setMode(value);}}
                Label {text:scan.label("Risoluzione","Resolution")}
                Choice {objectName:"scanResolution";width:parent.width;options:scan.resolutionChoices;value:scan.resolution;enabled:!scan.busy && !scan.scanning;onPicked:function(value){scan.resolution=value;}}
                Label {text:scan.label("Area del foglio","Paper area")}
                Choice {objectName:"scanArea";width:parent.width;options:scan.areas;value:scan.area;enabled:!scan.busy && !scan.scanning;onPicked:function(value){scan.area=value;}}
                Choice {objectName:"scanBatch";visible:scan.feeder;width:parent.width;options:[{value:"one",label:scan.label("Un foglio","One sheet")},{value:"all",label:scan.label("Tutto l’alimentatore","Entire feeder")}];value:scan.batch ? "all" : "one";enabled:!scan.busy && !scan.scanning;onPicked:function(value){scan.batch=value==="all";}}
                S.PrintingAction {objectName:"scanAcquire";text:scan.pages.length ? scan.label("Prossimo foglio","Next sheet") : scan.label("Scansiona","Scan");enabled:scan.acquiringAllowed && !scan.busy && !scan.scanning && scan.capabilities.length>0;onClicked:scan.acquire()}
                S.PrintingAction {objectName:"scanCancel";visible:scan.scanning;text:scan.label("Interrompi","Cancel");enabled:scan.activeJob!=="" && !cancellation.busy;onClicked:scan.cancel()}
            }
        }
        Ui.Scorrimento {bersaglio:optionsScroll;anchors.right:optionsScroll.right;anchors.top:optionsScroll.top;anchors.bottom:optionsScroll.bottom}
        Label {id:pagesLabel;x:16;y:optionsScroll.y+optionsScroll.height+14;width:parent.width-32;text:scan.label("Pagine · ","Pages · ")+scan.pages.length;font.weight:Font.DemiBold}
        ListView {
            id:pageList;x:16;y:pagesLabel.y+pagesLabel.height+8;width:parent.width-32;height:parent.height-y-16
            clip:true;model:scan.pages;spacing:6
            delegate:Rectangle {
                required property var modelData
                required property int index
                width:pageList.width-26;height:76;radius:4
                color:index===scan.current ? Qt.alpha(scan.accent,0.16) : "transparent"
                border.width:index===scan.current ? 1 : 0;border.color:scan.accent
                Image {x:6;y:6;width:48;height:64;source:parent.modelData.url;sourceSize:Qt.size(72,96);fillMode:Image.PreserveAspectFit;asynchronous:true;rotation:parent.modelData.rotation}
                Label {x:66;y:18;width:parent.width-74;text:scan.label("Pagina ","Page ")+(parent.index+1);font.weight:Font.DemiBold}
                Label {x:66;y:40;width:parent.width-74;text:(parent.modelData.annotations || []).length+scan.label(" annotazioni"," annotations");font.pixelSize:12;color:scan.muted}
                MouseArea {anchors.fill:parent;onClicked:scan.current=parent.index}
            }
        }
        Ui.Scorrimento {bersaglio:pageList;anchors.right:pageList.right;anchors.top:pageList.top;anchors.bottom:pageList.bottom}
    }
    Column {
        id:tools;x:left.width+18;y:16;width:parent.width-x-18;spacing:8
        Label {text:scan.label("Documento multipagina","Multipage document");font.pixelSize:20;font.weight:Font.DemiBold}
        Flow {
            width:parent.width;spacing:6
            S.PrintingAction {objectName:"scanRotate";text:scan.label("Ruota 90°","Rotate 90°");enabled:!!scan.currentPage && !scan.scanning && !scan.building;onClicked:scan.rotate()}
            S.PrintingAction {objectName:"scanMoveBefore";text:scan.label("Sposta prima","Move earlier");enabled:scan.current>0 && !scan.scanning && !scan.building;onClicked:scan.movePage(-1)}
            S.PrintingAction {objectName:"scanMoveAfter";text:scan.label("Sposta dopo","Move later");enabled:scan.current+1<scan.pages.length && !scan.scanning && !scan.building;onClicked:scan.movePage(1)}
            S.PrintingAction {objectName:"scanRemove";text:scan.label("Rimuovi pagina","Remove page");enabled:!!scan.currentPage && !scan.scanning && !scan.building;onClicked:scan.removePage()}
            S.PrintingAction {objectName:"scanUndo";text:scan.label("Annulla modifica","Undo edit");enabled:!!scan.currentPage && !!scan.currentPage.history && scan.currentPage.history.length>0 && !scan.scanning && !scan.building;onClicked:scan.undo()}
            S.PrintingAction {objectName:"scanRestore";text:scan.label("Ripristina pagina","Restore page");visible:scan.removed.length>0;enabled:!scan.scanning && !scan.building;onClicked:scan.restorePage()}
        }
        Flow {
            width:parent.width;spacing:6
            Choice {objectName:"scanTool";width:180;value:scan.tool;options:[{value:"move",label:scan.label("Visualizza","View")},{value:"crop",label:scan.label("Ritaglia","Crop")},{value:"rectangle",label:scan.label("Rettangolo","Rectangle")},{value:"ellipse",label:scan.label("Ellisse","Ellipse")},{value:"line",label:scan.label("Linea","Line")},{value:"arrow",label:scan.label("Freccia","Arrow")},{value:"highlight",label:scan.label("Evidenzia","Highlight")},{value:"text",label:scan.label("Testo","Text")},{value:"note",label:scan.label("Nota","Note")}];onPicked:function(value){scan.tool=value;}}
            Choice {objectName:"scanColor";width:120;value:scan.annotationColor;options:[{value:"#E81123",label:scan.label("Rosso","Red")},{value:"#0078D4",label:scan.label("Blu","Blue")},{value:"#107C10",label:scan.label("Verde","Green")},{value:"#FFB900",label:scan.label("Giallo","Yellow")},{value:"#000000",label:scan.label("Nero","Black")}];onPicked:function(value){scan.annotationColor=value;}}
            Choice {width:150;visible:scan.tool==="rectangle" || scan.tool==="ellipse";value:scan.filled ? "filled" : "outline";options:[{value:"outline",label:scan.label("Contorno","Outline")},{value:"filled",label:scan.label("Pieno","Filled")}];onPicked:function(value){scan.filled=value==="filled";}}
            Field {id:annotationText;objectName:"scanAnnotationText";width:180;visible:scan.tool==="text" || scan.tool==="note";text:scan.label("Nota","Note")}
        }
    }
    Rectangle {
        id:stage;x:left.width+18;y:tools.y+tools.height+12;width:parent.width-x-18;height:Math.max(80,footer.y-y-12)
        color:Qt.alpha(scan.ink,0.06);radius:6;clip:true
        Image {id:pageImage;anchors.fill:parent;anchors.margins:12;source:scan.currentPage && scan.previewData ? scan.previewData.url : "";asynchronous:true;cache:false;fillMode:Image.PreserveAspectFit}
        Label {anchors.centerIn:parent;width:parent.width-40;horizontalAlignment:Text.AlignHCenter;visible:!scan.currentPage;text:scan.label("Acquisisci il primo foglio dal vetro o dall’alimentatore.","Acquire the first sheet from the flatbed or feeder.");color:scan.muted}
        Item {
            id:editing;anchors.centerIn:pageImage;width:pageImage.paintedWidth;height:pageImage.paintedHeight
            property point from:Qt.point(0,0)
            property point to:Qt.point(0,0)
            Canvas {
                id:gesture;anchors.fill:parent
                onPaint:{var ctx=getContext("2d");ctx.reset();if(!drawing.pressed)return;ctx.strokeStyle=scan.annotationColor;ctx.lineWidth=2;ctx.setLineDash([5,4]);if(scan.tool==="line" || scan.tool==="arrow"){ctx.beginPath();ctx.moveTo(editing.from.x*width,editing.from.y*height);ctx.lineTo(editing.to.x*width,editing.to.y*height);ctx.stroke();}else ctx.strokeRect(editing.from.x*width,editing.from.y*height,(editing.to.x-editing.from.x)*width,(editing.to.y-editing.from.y)*height);}
            }
            MouseArea {
                id:drawing;objectName:"scanAnnotationArea";anchors.fill:parent;enabled:!!scan.currentPage && !!scan.previewData && scan.previewData.revision===scan.revision && scan.tool!=="move" && !scan.scanning && !scan.building && !documentWorker.busy
                cursorShape:Qt.CrossCursor
                function point(x,y){return Qt.point(Math.max(0,Math.min(1,x/width)),Math.max(0,Math.min(1,y/height)));}
                onPressed:function(event){editing.from=point(event.x,event.y);editing.to=editing.from;gesture.requestPaint();}
                onPositionChanged:function(event){if(pressed){editing.to=point(event.x,event.y);gesture.requestPaint();}}
                onReleased:function(event){
                    editing.to=point(event.x,event.y);gesture.requestPaint();
                    var x=Math.min(editing.from.x,editing.to.x),y=Math.min(editing.from.y,editing.to.y),w=Math.abs(editing.from.x-editing.to.x),h=Math.abs(editing.from.y-editing.to.y);
                    if(scan.tool==="line" || scan.tool==="arrow"){if(Math.sqrt(w*w+h*h)<0.01)return;}
                    else if(w<0.01 || h<0.01){if(scan.tool!=="text" && scan.tool!=="note")return;x=Math.min(x,0.95);y=Math.min(y,0.95);w=Math.min(0.4,1-x);h=Math.min(0.15,1-y);}
                    var crop=scan.currentPage.crop || [0,0,1,1];
                    var full=[crop[0]+x*crop[2],crop[1]+y*crop[3],w*crop[2],h*crop[3]];
                    if(scan.tool==="crop"){scan.edit({crop:full});return;}
                    var item={kind:scan.tool,color:scan.annotationColor,width:2,filled:scan.filled,opacity:0.25};
                    if(scan.tool==="line" || scan.tool==="arrow"){
                        item.x=crop[0]+editing.from.x*crop[2];item.y=crop[1]+editing.from.y*crop[3];item.x2=crop[0]+editing.to.x*crop[2];item.y2=crop[1]+editing.to.y*crop[3];
                    }else {item.x=full[0];item.y=full[1];item.w=full[2];item.h=full[3];}
                    if(scan.tool==="text" || scan.tool==="note"){item.text=annotationText.text;item.size=14;item.rotation=0;}
                    scan.edit({annotations:(scan.currentPage.annotations || []).concat([item])});
                }
                onCanceled:gesture.requestPaint()
            }
        }
    }
    Item {
        id:footer;x:left.width+18;anchors.bottom:parent.bottom;anchors.bottomMargin:16;width:parent.width-x-18;height:80
        Label {text:!scan.acquiringAllowed ? scan.label("Chiudi il documento con Nuovo documento per iniziare una scansione.","Use New document before starting a scan.") : scan.status || (scan.unsaved ? scan.label("Modifiche non salvate","Unsaved changes") : "");font.pixelSize:12;color:scan.muted}
        Flow {
            y:40;width:parent.width;spacing:8
            S.PrintingAction {objectName:"scanSavePdf";text:scan.label("Salva PDF…","Save PDF…");enabled:scan.pages.length>0 && !scan.busy && !scan.scanning;onClicked:scan.savePdf()}
            S.PrintingAction {objectName:"scanReplacePdf";text:scan.label("Sostituisci file","Replace file");visible:scan.overwritePath!=="";enabled:!scan.busy;onClicked:scan.saveTo(scan.overwritePath,true)}
        }
    }
}

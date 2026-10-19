import QtQuick
import QtQuick.Window
import Quickshell
import "../../core" as Core
import "../../windows11" as W
import ".." as S

PaginaWindows {
    id: pagina
    objectName: "impostazioniAvvioWindows"
    briciole: [{testo:W.Style.label("App","Apps"),categoria:"app"},{testo:W.Style.label("Avvio","Startup")}]
    property var voci: []
    property bool caricato: false
    property bool attesa: false
    property string operazione: ""
    property string errore: ""
    property string confermaRimozione: ""
    property string ordine: "nome"
    readonly property var mostrate: voci.slice().sort(function(a,b){
        if(ordine==="stato" && a.acceso!==b.acceso)return a.acceso ? -1 : 1;
        return String(a.nome).localeCompare(String(b.nome));
    })
    function tr(it,en){return W.Style.label(it,en);}
    function richiedi(){
        if(attesa)return;
        errore="";attesa=Core.Ipc.autostartList();
        if(attesa)scadenza.restart();else errore=tr("Servizio non collegato. Riprova quando la connessione è ripristinata.","Service disconnected. Retry when connected.");
    }
    function modifica(file,enabled){
        if(attesa)return;
        errore="";operazione="set";confermaRimozione="";
        attesa=Core.Ipc.autostartSet(file,enabled);if(attesa)scadenza.restart();else operazione="";
    }
    function rimuovi(file){
        if(attesa)return;
        if(confermaRimozione!==file){confermaRimozione=file;disarma.restart();return;}
        confermaRimozione="";errore="";operazione="remove";
        attesa=Core.Ipc.autostartRemove(file);if(attesa)scadenza.restart();else operazione="";
    }
    function aggiungi(){
        if(attesa)return;
        var nome=nuovoNome.testo.trim(),comando=nuovoComando.testo.trim();
        if(!nome || !comando)return;
        if(/[\r\n\x00]/.test(nome+comando)){errore=tr("Nome e comando devono occupare una sola riga.","Name and command must each fit on one line.");return;}
        errore="";operazione="add";attesa=Core.Ipc.autostartAdd(nome,comando);if(attesa)scadenza.restart();else operazione="";
    }
    function motivo(voce){
        if(voce.acceso)return tr("Attivato","On");
        if(voce.motivo==="il programma non è installato")return tr("Il programma non è installato.","The program is not installed.");
        if(voce.motivo==="è di un altro ambiente")return tr("Questa voce è destinata a un altro ambiente desktop.","This entry is intended for another desktop environment.");
        if(!voce.utente)return tr("Voce di sistema: attivala per usarla in Liquid.","System entry: enable it to use it in Liquid.");
        if(voce.motivo==="spenta" || !voce.motivo)return tr("Disattivato","Off");
        return voce.motivo;
    }
    Timer {id:scadenza;interval:15000;onTriggered:{pagina.attesa=false;pagina.operazione="";pagina.errore=pagina.tr("Il servizio non ha risposto. Aggiorna l’elenco prima di riprovare.","The service did not respond. Refresh the list before retrying.");}}
    Timer {id:disarma;interval:4000;onTriggered:pagina.confermaRimozione=""}
    Component.onCompleted:richiedi()
    Connections {
        target:Core.Ipc
        function onConnectedChanged(){
            if(Core.Ipc.connected)pagina.richiedi();
            else {pagina.attesa=false;pagina.operazione="";scadenza.stop();pagina.errore=pagina.tr("Servizio non collegato.","Service disconnected.");}
        }
        function onFileResultReceived(result){
            if(!pagina.operazione)return;
            if(result.ok===false)pagina.errore=result.error || pagina.tr("Modifica non riuscita.","Change failed.");
            else if(result.ok===true && pagina.operazione==="add"){nuovoNome.testo="";nuovoComando.testo="";}
        }
        function onAutostartReceived(rows){
            pagina.voci=(rows || []).filter(function(row){return row && typeof row.file==="string" && typeof row.nome==="string";});
            pagina.caricato=true;pagina.attesa=false;pagina.operazione="";scadenza.stop();
        }
    }
    Item {
        width:parent.width
        readonly property bool affiancati:width>=800
        implicitHeight:affiancati ? Math.max(introduzione.implicitHeight,ordinamento.height) : introduzione.implicitHeight+ordinamento.height+8
        height:implicitHeight
        Text {
            id:introduzione;width:parent.width-(parent.affiancati ? ordinamento.width+24 : 0)
            wrapMode:Text.Wrap;color:W.Style.muted;font.family:W.Style.font;font.pixelSize:14*W.Style.textScale
            text:pagina.tr("Le app possono essere configurate per l’avvio al momento dell’accesso. Possono avviarsi ridotte a icona o solo in background.","Apps can be configured to start when you sign in. They may start minimized or only run in the background.")
        }
        Row {
            id:ordinamento;x:parent.affiancati ? parent.width-width : 0;y:parent.affiancati ? 0 : introduzione.implicitHeight+8;spacing:12
            Text {anchors.verticalCenter:parent.verticalCenter;text:pagina.tr("Ordina per:","Sort by:");color:W.Style.text;font.family:W.Style.font;font.pixelSize:14}
            TendinaWindows {objectName:"avvioOrdine";valore:pagina.ordine;voci:[{valore:"nome",testo:pagina.tr("Nome","Name")},{valore:"stato",testo:pagina.tr("Stato","Status")}];onScelto:function(value){pagina.ordine=value;}}
        }
    }
    Text {
        objectName:"avvioStato";width:parent.width;visible:pagina.errore!=="" || !pagina.caricato || pagina.attesa || !pagina.voci.length
        text:pagina.errore || (pagina.attesa ? pagina.tr("Caricamento…","Loading…") : pagina.caricato ? pagina.tr("Nessuna app configurata per l’avvio.","No startup apps configured.") : pagina.tr("In attesa del servizio…","Waiting for service…"))
        wrapMode:Text.Wrap;color:pagina.errore ? W.Style.text : W.Style.muted;font.family:W.Style.font;font.pixelSize:14
    }
    Repeater {
        model:pagina.mostrate
        delegate:EspansoreImpostazione {
            id:riga
            required property var modelData
            objectName:"avvioVoce-"+modelData.file
            titolo:modelData.nome
            descrizione:(modelData.utente ? pagina.tr("Utente","User") : pagina.tr("Sistema","System"))+"  |  "+pagina.tr("Impatto non misurato","Impact not measured")
            icona:"apps"
            readonly property var applicazione:Core.Apps.byId(modelData.file)
            immagine:applicazione && applicazione.icon ? "file://"+applicazione.icon : ""
            comando:S.ToggleSwitch {objectName:"avvioToggle-"+riga.modelData.file;checked:riga.modelData.acceso===true;enabled:Core.Ipc.connected && !pagina.attesa && (riga.modelData.acceso || !riga.modelData.motivo || riga.modelData.motivo==="spenta");Accessible.name:riga.modelData.nome;onToggled:function(value){pagina.modifica(riga.modelData.file,value);}}
            SchedaImpostazione {interna:true;titolo:pagina.tr("Comando","Command");descrizione:riga.modelData.exec || ""}
            SchedaImpostazione {interna:true;titolo:pagina.tr("Percorso","Location");descrizione:riga.modelData.percorso || ""}
            SchedaImpostazione {interna:true;titolo:pagina.tr("Stato","Status");descrizione:pagina.motivo(riga.modelData)}
            SchedaImpostazione {
                interna:true;visible:riga.modelData.utente===true
                titolo:pagina.tr("Rimuovi dall’avvio","Remove from startup")
                descrizione:pagina.tr("Rimuove solo questa voce di avvio, senza disinstallare l’app.","Removes only this startup entry, without uninstalling the app.")
                PulsanteWindows {objectName:"avvioRimuovi-"+riga.modelData.file;enabled:Core.Ipc.connected && !pagina.attesa;testo:pagina.confermaRimozione===riga.modelData.file ? pagina.tr("Conferma rimozione","Confirm removal") : pagina.tr("Rimuovi","Remove");onPremuto:pagina.rimuovi(riga.modelData.file)}
            }
        }
    }
    Item {width:1;height:20}
    EspansoreImpostazione {
        objectName:"avvioAggiungi"
        titolo:pagina.tr("Aggiungi un’app all’avvio","Add a startup app")
        descrizione:pagina.tr("Scegli un programma e le sue opzioni. Verrà avviato al prossimo accesso.","Choose a program and its options. It will start on the next sign-in.")
        icona:"add"
        SchedaImpostazione {interna:true;titolo:pagina.tr("Rileggi programmi configurati","Reload configured apps");PulsanteWindows {objectName:"avvioAggiorna";testo:pagina.tr("Aggiorna","Refresh");enabled:Core.Ipc.connected && !pagina.attesa;onPremuto:pagina.richiedi()}}
        SchedaImpostazione {interna:true;titolo:pagina.tr("Nome","Name");Campo {id:nuovoNome;objectName:"avvioNuovoNome";label:pagina.tr("Nome","Name");width:Math.min(240,pagina.larghezza*0.4)}}
        SchedaImpostazione {interna:true;titolo:pagina.tr("Comando","Command");Campo {id:nuovoComando;objectName:"avvioNuovoComando";label:pagina.tr("Comando","Command");width:Math.min(340,pagina.larghezza*0.45)}}
        SchedaImpostazione {
            interna:true;titolo:pagina.tr("Scegli programma","Choose program")
            PulsanteWindows {objectName:"avvioSfoglia";testo:pagina.tr("Sfoglia…","Browse…");enabled:Core.Ipc.connected && !pagina.attesa;onPremuto:selettore.apri("/usr/bin")}
        }
        SchedaImpostazione {
            interna:true;titolo:""
            PulsanteWindows {objectName:"avvioConfermaAggiunta";testo:pagina.tr("Aggiungi","Add");accento:true;enabled:Core.Ipc.connected && !pagina.attesa && nuovoNome.testo.trim()!=="" && nuovoComando.testo.trim()!=="";onPremuto:pagina.aggiungi()}
        }
    }
    EspansoreImpostazione {
        objectName:"avvioAppPronte"
        titolo:pagina.tr("App Liquid pronte all’uso","Keep Liquid apps ready")
        descrizione:pagina.tr("Riapertura più rapida mantenendo i processi in memoria.","Faster reopening by keeping app processes in memory.")
        icona:"window"
        Repeater {
            model:[{key:"files.tieniAcceso",name:pagina.tr("File","Files"),value:true},{key:"preload.impostazioni",name:pagina.tr("Impostazioni","Settings")},{key:"preload.editor",name:"Editor"},{key:"preload.attivita",name:pagina.tr("Attività","Activity")},{key:"preload.anteprima",name:pagina.tr("Anteprima","Preview")},{key:"preload.calcolatrice",name:pagina.tr("Calcolatrice","Calculator")},{key:"preload.terminale",name:pagina.tr("Terminale","Terminal")}]
            delegate:SchedaImpostazione {
                required property var modelData
                interna:true;titolo:modelData.name
                S.ToggleSwitch {objectName:"avvioPreload-"+modelData.key;checked:Core.Ipc.get(modelData.key,modelData.value===true);Accessible.name:modelData.name;onToggled:function(value){Core.Ipc.setSetting(modelData.key,value);}}
            }
        }
    }
    ScegliFileWindows {
        id:selettore;purpose:"file";proprietario:pagina.Window.window
        onScelto:function(path){nuovoComando.testo='"'+path.replace(/\\/g,'\\\\').replace(/"/g,'\\"')+'"';}
    }
    component Campo:Rectangle {
        property alias testo:campo.text
        property string label:""
        implicitWidth:240;implicitHeight:32;height:32;radius:4;color:W.Style.field;border.width:1;border.color:campo.activeFocus ? W.Style.accent : W.Style.gettoni.controlStroke
        TextInput {id:campo;Accessible.role:Accessible.EditableText;Accessible.name:parent.label;anchors.fill:parent;anchors.leftMargin:10;anchors.rightMargin:10;verticalAlignment:Text.AlignVCenter;color:W.Style.text;font.family:W.Style.font;font.pixelSize:14;selectByMouse:true;clip:true;activeFocusOnTab:true;selectionColor:W.Style.accent;selectedTextColor:W.Style.accentForeground}
    }
}

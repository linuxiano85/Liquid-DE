import QtQuick
import "../../core" as Core
import "../../windows11" as W

// Impaginazione dalla VM: testata, verifica a destra, schede da 69 px.
// La fonte è il progetto Liquid, non Windows né il gestore pacchetti Linux.
PaginaWindows {
    id: pagina
    readonly property var stato: Core.Ipc.liquidUpdateState
    readonly property var ultimo: stato.latest || ({})
    readonly property var installato: stato.installed || ({})
    readonly property bool occupato: stato.phase === "checking" || stato.phase === "downloading"
    property string vista: ""
    readonly property var confronto: stato.comparison || ({})
    readonly property var fileConfronto: confronto.files || []
    function componente(nome) {
        var nomi = {compositor: tr("Compositore", "Compositor"), daemon: tr("Demone", "Daemon"), shell: "Shell", native: tr("Modulo nativo", "Native module"), fucina: "Fucina", integration: tr("Risorse e integrazione", "Resources and integration"), repository: tr("Documentazione e sviluppo", "Documentation and development"), unclassified: tr("Da classificare", "Needs classification")};
        return nomi[nome] || nome;
    }
    briciole: vista === "" ? [{testo: "Liquid Update"}] : [
        {testo: "Liquid Update", pagina: "w-update"},
        {testo: vista === "history" ? tr("Cronologia dei download", "Download history") : vista === "changes" ? tr("Cosa cambia", "What changes") : tr("Opzioni avanzate", "Advanced options")}
    ]
    function tr(it, en) { return W.Style.label(it, en); }
    function tipoModifica(nome) {
        var nomi = {added: tr("Aggiunto", "Added"), removed: tr("Rimosso", "Removed"), modified: tr("Modificato", "Modified"), renamed: tr("Rinominato", "Renamed"), copied: tr("Copiato", "Copied"), changed: tr("Modificato", "Changed"), unchanged: tr("Invariato", "Unchanged")};
        return nomi[nome] || nome;
    }
    function quantiFile(numero) {
        return numero + (numero === 1 ? tr(" file interessato", " affected file") : tr(" file interessati", " affected files"));
    }
    function apriVista(destinazione) {
        if (finestra)
            finestra.registraVistaInterna(destinazione);
        vista = destinazione;
        posizioneScorrimento = 0;
    }
    function invia(azione, dati) {
        if (!Core.Ipc.connected)
            return;
        Core.Ipc.send(Object.assign({action: "liquid_update_" + azione}, dati || {}));
    }
    function data(testo) {
        var valore = new Date(testo);
        return testo && !isNaN(valore.getTime()) ? valore.toLocaleString(Qt.locale(Core.Strings.lang)) : "";
    }
    function breve(revisione) { return String(revisione || "").slice(0, 10); }
    function errore(codice) {
        if (codice === "network") return tr("Connessione non disponibile. Riprova quando sei online.", "Connection unavailable. Try again when online.");
        if (codice === "http_403" || codice === "http_429") return tr("GitHub ha temporaneamente limitato le richieste. Riprova più tardi.", "GitHub has temporarily limited requests. Try again later.");
        if (codice === "storage") return tr("Impossibile salvare il download o la cronologia. Controlla spazio e permessi.", "Unable to save the download or history. Check disk space and permissions.");
        if (codice === "http_404") return tr("Questa revisione non è più disponibile nel repository.", "This revision is no longer available in the repository.");
        if (codice === "invalid_response") return tr("La risposta o l’archivio non sono validi. Il download non è stato accettato.", "The response or archive is invalid. The download was not accepted.");
        if (codice) return tr("L’operazione non è riuscita. Puoi riprovare.", "The operation failed. You can try again.");
        return "";
    }
    readonly property string titoloStato: {
        if (!Core.Ipc.connected) return tr("Servizio aggiornamenti non disponibile", "Update service unavailable");
        if (stato.phase === "checking") return tr("Verifica degli aggiornamenti in corso", "Checking for updates");
        if (stato.phase === "downloading") return tr("Download in corso", "Downloading");
        if (stato.phase === "error") return tr("Impossibile completare l’operazione", "Unable to complete the operation");
        if (stato.phase === "cancelled") return tr("Download annullato", "Download cancelled");
        if (stato.downloaded) return tr("Archivio sorgenti pronto", "Source archive ready");
        if (confronto.complete && confronto.status === "ahead" && !confronto.runtimeChanged) return tr("Novità nel repository, desktop invariato", "Repository changes, desktop unchanged");
        if (stato.updateAvailable) return tr("Aggiornamenti disponibili", "Updates available");
        if (ultimo.revision && installato.dirty) return tr("Installazione locale personalizzata", "Customized local installation");
        if (ultimo.revision && installato.revision === ultimo.revision) return tr("Sei aggiornato", "You're up to date");
        return tr("Verifica disponibilità aggiornamenti", "Check for updates");
    }
    onBriciolaChiesta: function(destinazione) {
        if (destinazione === "w-update")
            vista = "";
    }
    Component.onCompleted: invia("subscribe")
    Component.onDestruction: invia("unsubscribe")
    Connections {
        target: Core.Ipc
        function onConnectedChanged() { if (Core.Ipc.connected) pagina.invia("subscribe"); }
    }

    Item {
        visible: pagina.vista === ""
        width: parent.width
        readonly property bool stretto: width < 760
        height: visible ? Math.max(120, descrizioni.implicitHeight + (stretto ? 90 : 48)) : 0
        Image {
            x: 12
            y: 24
            width: 72
            height: 72
            source: "icone/update.svg"
            sourceSize: Qt.size(144, 144)
        }
        Column {
            id: descrizioni
            x: 114
            y: 24
            width: parent.width - x - (parent.stretto ? 16 : verifica.width + 28)
            spacing: 4
            Text {
                objectName: "liquidUpdateStatus"
                width: parent.width
                text: pagina.titoloStato
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: W.Style.text
                font.family: W.Style.font
                font.pixelSize: 20
                font.weight: Font.DemiBold
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
            Text {
                width: parent.width
                text: pagina.stato.checkedAt ? pagina.tr("Ultima verifica: ", "Last checked: ") + pagina.data(pagina.stato.checkedAt)
                    : pagina.tr("Gli aggiornamenti del progetto arrivano da GitHub.", "Project updates come from GitHub.")
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: W.Style.muted
                font.family: W.Style.font
                font.pixelSize: 12
            }
        }
        PulsanteWindows {
            id: verifica
            objectName: "liquidUpdateCheck"
            x: parent.stretto ? 114 : parent.width - width
            y: parent.stretto ? descrizioni.y + descrizioni.implicitHeight + 16 : 38
            accento: true
            enabled: Core.Ipc.connected && !pagina.occupato
            testo: pagina.tr("Verifica disponibilità aggiornamenti", "Check for updates")
            onPremuto: pagina.invia("check")
        }
    }
    Text {
        visible: pagina.vista === "" && !!pagina.stato.error
        width: parent.width
        text: pagina.errore(pagina.stato.error) + (pagina.stato.retryAt ? " " + pagina.tr("Riprova dopo: ", "Retry after: ") + pagina.data(pagina.stato.retryAt) : "")
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: W.Style.critical
        font.family: W.Style.font
        font.pixelSize: 14
    }
    SchedaImpostazione {
        objectName: "liquidUpdateAvailable"
        visible: pagina.vista === "" && !!pagina.ultimo.revision
        icona: "download"
        titolo: "Liquid DE · " + pagina.breve(pagina.ultimo.revision)
        descrizione: pagina.ultimo.message || ""
        PulsanteWindows {
            objectName: "liquidUpdateDownload"
            enabled: Core.Ipc.connected && !pagina.occupato
            testo: pagina.stato.downloaded ? pagina.tr("Apri cartella", "Open folder") : pagina.tr("Scarica", "Download")
            onPremuto: {
                if (pagina.stato.downloaded)
                    Core.Ipc.apriOChiedi(pagina.stato.downloadFolder);
                else
                    pagina.invia("download", {revision: pagina.ultimo.revision});
            }
        }
    }
    Item {
        visible: pagina.vista === "" && pagina.stato.phase === "downloading"
        width: parent.width
        height: visible ? 60 : 0
        Rectangle {
            x: 0
            y: 12
            width: parent.width - annulla.width - 16
            height: 4
            radius: 2
            color: W.Style.edge
            Rectangle {
                height: parent.height
                width: parent.width * (pagina.stato.total > 0 ? Math.min(1, pagina.stato.received / pagina.stato.total) : 0)
                radius: 2
                color: W.Style.accent
            }
        }
        Text {
            x: 0
            y: 24
            text: (pagina.stato.received / 1048576).toFixed(1) + " MB" + (pagina.stato.total > 0 ? " / " + (pagina.stato.total / 1048576).toFixed(1) + " MB" : "")
            color: W.Style.muted
            font.family: W.Style.font
            font.pixelSize: 12
        }
        PulsanteWindows {
            id: annulla
            objectName: "liquidUpdateCancel"
            anchors.right: parent.right
            testo: pagina.tr("Annulla", "Cancel")
            onPremuto: pagina.invia("cancel")
        }
    }
    Text {
        objectName: "liquidUpdateDownloadNotice"
        visible: pagina.vista === "" && !!pagina.ultimo.revision
        width: parent.width
        text: pagina.tr("Canale principale: ", "Main channel: ") + pagina.ultimo.branch + " · " + pagina.tr("Archivio sorgenti del progetto", "Project source archive")
            + "\n" + pagina.tr("Scarica salva i sorgenti: non installa né sostituisce il desktop.", "Download saves the source code: it does not install or replace the desktop.")
            + (pagina.installato.dirty ? "\n" + pagina.tr("Questa installazione contiene modifiche locali.", "This installation contains local changes.") : "")
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: W.Style.muted
        font.family: W.Style.font
        font.pixelSize: 12
        bottomPadding: 16
    }
    // Il riepilogo deve essere leggibile prima di scaricare, senza aprire
    // una sottopagina. Un confronto parziale non diventa un elenco completo.
    Column {
        visible: pagina.vista === "" && !!pagina.ultimo.revision
        width: parent.width
        spacing: 8
        Text {
            objectName: "liquidUpdateChangesSummary"
            width: parent.width
            text: pagina.stato.comparisonError ? pagina.tr("Dettaglio delle modifiche non disponibile. Ripeti la verifica.", "Change details unavailable. Check again.")
                : !pagina.confronto.base ? pagina.tr("Esegui una verifica per caricare i file cambiati.", "Check for updates to load changed files.")
                : pagina.quantiFile(pagina.fileConfronto.length)
                    + (pagina.confronto.complete ? "" : pagina.tr(" · elenco parziale restituito da GitHub", " · partial list returned by GitHub"))
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: W.Style.text
            font.family: W.Style.font
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
        Text {
            objectName: "liquidUpdateComponentsSummary"
            visible: !!pagina.confronto.base
            width: parent.width
            text: Object.keys(pagina.confronto.components || {}).map(function(nome) {
                return pagina.componente(nome) + ": " + pagina.confronto.components[nome];
            }).join(" · ")
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: W.Style.muted
            font.family: W.Style.font
            font.pixelSize: 12
        }
        Repeater {
            model: pagina.fileConfronto.slice(0, 5)
            delegate: SchedaImpostazione {
                required property var modelData
                objectName: "liquidUpdateFilePreview-" + modelData.path
                titolo: modelData.path
                descrizione: pagina.tipoModifica(modelData.status) + " · +" + modelData.additions + " / −" + modelData.deletions
                porta: true
                onAttivata: pagina.apriVista("changes")
            }
        }
        PulsanteWindows {
            objectName: "liquidUpdateAllChanges"
            visible: !!pagina.confronto.base
            testo: pagina.tr("Vedi tutte le modifiche", "View all changes")
            onPremuto: pagina.apriVista("changes")
        }
        Item { width: 1; height: 8 }
    }
    Text {
        visible: pagina.vista === ""
        text: pagina.tr("Altre opzioni", "More options")
        color: W.Style.text
        font.family: W.Style.font
        font.pixelSize: 14
        font.weight: Font.DemiBold
        bottomPadding: 8
    }
    SchedaImpostazione {
        visible: pagina.vista === ""
        titolo: pagina.tr("Sospendi aggiornamenti", "Pause updates")
        descrizione: pagina.stato.paused ? pagina.tr("Sospesi fino al ", "Paused until ") + pagina.data(pagina.stato.pauseUntil) : ""
        PulsanteWindows {
            objectName: "liquidUpdatePause"
            enabled: Core.Ipc.connected
            testo: pagina.stato.paused ? pagina.tr("Riprendi aggiornamenti", "Resume updates") : pagina.tr("Sospendi per 1 settimana", "Pause for 1 week")
            onPremuto: pagina.invia("pause", {days: pagina.stato.paused ? 0 : 7})
        }
    }
    SchedaImpostazione {
        objectName: "liquidUpdateChanges"
        visible: pagina.vista === "" && !!pagina.ultimo.revision
        titolo: pagina.tr("Cosa cambia", "What changes")
        descrizione: pagina.confronto.base ? (pagina.confronto.files || []).length + pagina.tr(" file nel confronto disponibile", " files in the available comparison") : pagina.tr("Esegui una verifica per caricare il dettaglio", "Check for updates to load the details")
        porta: true
        onAttivata: pagina.apriVista("changes")
    }
    Text {
        visible: pagina.vista === "changes"
        width: parent.width
        text: pagina.stato.comparisonError ? pagina.tr("Impossibile caricare il dettaglio delle modifiche. Ripeti la verifica.", "Unable to load change details. Check again.")
            : !pagina.confronto.base ? (pagina.installato.revision ? pagina.tr("Esegui una verifica per caricare il confronto delle modifiche.", "Check for updates to load the change comparison.") : pagina.tr("La revisione installata non è registrata: il confronto non è disponibile.", "The installed revision is not recorded: comparison unavailable."))
            : pagina.tr("Confronto Git: ", "Git comparison: ") + pagina.breve(pagina.confronto.base) + " → " + pagina.breve(pagina.confronto.revision)
                + (pagina.confronto.complete ? "" : "\n" + pagina.tr("GitHub ha restituito un elenco parziale. Non usarlo come piano di installazione.", "GitHub returned a partial list. Do not use it as an installation plan."))
                + (pagina.installato.dirty ? "\n" + pagina.tr("Il confronto riguarda i commit pubblicati e non include le modifiche locali di questa installazione.", "This comparison covers published commits and excludes this installation’s local changes.") : "")
                + (pagina.confronto.status === "diverged" ? "\n" + pagina.tr("La cronologia locale e quella remota sono divergenti: serve una verifica prima di aggiornare.", "Local and remote histories have diverged: review required before updating.") : "")
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: W.Style.muted
        font.family: W.Style.font
        font.pixelSize: 13
    }
    Repeater {
        model: pagina.vista === "changes" ? Object.keys(pagina.confronto.components || {}) : []
        delegate: SchedaImpostazione {
            required property string modelData
            titolo: pagina.componente(modelData)
            descrizione: pagina.quantiFile(pagina.confronto.components[modelData])
        }
    }
    Repeater {
        model: pagina.vista === "changes" ? (pagina.confronto.commits || []) : []
        delegate: SchedaImpostazione {
            required property var modelData
            titolo: pagina.breve(modelData.revision)
            descrizione: modelData.message
        }
    }
    Repeater {
        model: pagina.vista === "changes" ? (pagina.confronto.files || []) : []
        delegate: Column {
            id: modifica
            objectName: "liquidUpdateFile"
            required property var modelData
            property bool aperta: false
            width: parent.width
            spacing: 8
            SchedaImpostazione {
                width: parent.width
                titolo: modifica.modelData.path
                descrizione: pagina.tipoModifica(modifica.modelData.status) + " · +" + modifica.modelData.additions + " / −" + modifica.modelData.deletions
                    + (modifica.modelData.previous ? "\n" + modifica.modelData.previous + " → " + modifica.modelData.path : "")
                porta: true
                onAttivata: modifica.aperta = !modifica.aperta
            }
            TextEdit {
                objectName: "liquidUpdatePatch"
                visible: modifica.aperta
                width: parent.width
                height: visible ? implicitHeight : 0
                text: modifica.modelData.patchAvailable ? modifica.modelData.patch : pagina.tr("Differenza non restituita da GitHub o troppo grande per questa vista. Non significa che il file sia invariato.", "Diff not returned by GitHub or too large for this view. This does not mean the file is unchanged.")
                textFormat: TextEdit.PlainText
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                color: W.Style.text
                font.family: "monospace"
                font.pixelSize: 12
                leftPadding: 12
                rightPadding: 12
                bottomPadding: 16
            }
        }
    }
    SchedaImpostazione {
        objectName: "liquidUpdateHistory"
        visible: pagina.vista === ""
        titolo: pagina.tr("Cronologia dei download", "Download history")
        porta: true
        onAttivata: pagina.apriVista("history")
    }
    SchedaImpostazione {
        objectName: "liquidUpdateAdvanced"
        visible: pagina.vista === ""
        titolo: pagina.tr("Opzioni avanzate", "Advanced options")
        descrizione: pagina.tr("Repository, canale, versione installata", "Repository, channel, installed version")
        porta: true
        onAttivata: pagina.apriVista("advanced")
    }
    SchedaImpostazione {
        visible: pagina.vista === "advanced"
        titolo: "GitHub"
        descrizione: "https://github.com/linuxiano85/Liquid-DE"
    }
    SchedaImpostazione {
        visible: pagina.vista === "advanced"
        titolo: pagina.tr("Versione installata", "Installed version")
        descrizione: (pagina.installato.version || pagina.tr("Non registrata", "Not recorded")) + " · " + pagina.breve(pagina.installato.revision)
    }
    SchedaImpostazione {
        visible: pagina.vista === "advanced"
        titolo: pagina.tr("Verifica automatica", "Automatic check")
        descrizione: pagina.tr("Ogni 6 ore, quando gli aggiornamenti non sono sospesi. Il download parte quando premi Scarica.", "Every 6 hours when updates are not paused. Download starts when you press Download.")
    }
    Text {
        visible: pagina.vista === "history" && !(pagina.stato.history || []).length
        text: pagina.tr("Nessun archivio scaricato.", "No archives downloaded.")
        color: W.Style.muted
        font.family: W.Style.font
        font.pixelSize: 14
    }
    Repeater {
        model: pagina.vista === "history" ? (pagina.stato.history || []) : []
        delegate: SchedaImpostazione {
            required property var modelData
            titolo: "Liquid DE · " + pagina.breve(modelData.revision)
            descrizione: pagina.data(modelData.date) + " · " + (modelData.bytes / 1048576).toFixed(1) + " MB\nSHA-256: " + modelData.sha256
        }
    }
}

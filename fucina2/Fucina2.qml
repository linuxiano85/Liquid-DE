import QtQuick
import Quickshell
import "theme" as Theme
import "core" as Core
import "ui" as Ui

FloatingWindow {
    id: win
    signal chiusa()
    property bool dormiente: false
    visible: Core.Ipc.prontoADipingere && !dormiente
    title: "Minerva · Fucina 2"
    implicitWidth: 1080
    implicitHeight: 740
    minimumSize: Qt.size(780, 560)
    color: Theme.Colors.window

    onClosed: chiusa()

    property var rilievo: null
    property var targetCompilatori: []
    property var elencoKernel: []
    property var amministrazioneKernel: null
    property var statoCache: ({})
    readonly property var recuperoCache: statoCache.recupero || ({})
    property bool staRiaprendoCache: false
    property string messaggioRecuperoCache: ""
    property var esitoRecuperoCache: null
    property var elencoVersioni: []
    property var ricettaPreview: null
    property var ricettaCompilazione: null
    property bool mostraUltimaBuild: false
    readonly property var pianoCompilazione: mostraUltimaBuild ? ricettaCompilazione : ricettaPreview
    property string kernelInUso: ""
    property string versioneKernel: ""
    property string erroreRicetta: ""
    property string erroreVersioni: ""
    property string richiestaRicetta: ""
    property int contatoreRichiesteRicetta: 0
    property bool staRilevando: false
    property bool staLeggendoKernel: false
    property bool staCalcolandoRicetta: false
    property bool staSalvandoReport: false
    property string reportPath: ""
    property string erroreReport: ""
    property string pagina: "panoramica"
    property bool targetNativo: false
    property bool prioritaScelta: false
    property bool provaAvvioKernel: false
    property bool prioritaProvaAvvio: false
    property string compilatore: "gcc"
    property int lavoriCompilazione: 0
    readonly property var parallelismoPreview: ricettaPreview && ricettaPreview.parallelismo
                                              ? ricettaPreview.parallelismo : null
    readonly property int threadCompilazione: Math.max(1, Math.min(512,
        Number(win.rilievo && win.rilievo.macchina ? win.rilievo.macchina.nuclei : 1)))
    readonly property int lavoriAuto: parallelismoPreview ? Number(parallelismoPreview.consigliati || 1) : 1
    property bool thinLto: false
    property bool autoFdo: false
    property string baseConfig: "in-uso"
    property string sorgente: "vanilla"
    property var presetUso: []
    property var moduliAggiunti: []
    property var scorteUso: null
    property var regoleModuli: ({ "mantieni": [], "escludi": [] })
    property string filtroModuli: ""
    property string messaggioRegolaModulo: ""
    property var profiliSalvati: []
    property string nomeProfilo: "Profilo personale"
    property string messaggioProfilo: ""
    property bool confermaDimentica: false
    property string messaggioStorico: ""
    property bool moduliEspansi: false
    property bool compilando: false
    property string erroreCompilazione: ""
    property string erroreKernel: ""
    property var verificaKernel: null
    property bool staVerificandoKernel: false
    property string kernelInLavorazione: ""
    property string azioneKernel: ""
    property string kernelAzione: ""
    property string kernelImpegnato: ""
    property bool confermaKernel: false
    property bool popupKernelPronto: false
    property bool confermaCompilazione: false
    property var esitoCompilazione: null
    property string logCompilazione: ""
    property var passiCompilazione: ({})
    property var righeCompilazione: []
    property string passoCompilazione: ""
    property string faseCompilazione: ""
    property int secondiCompilazione: 0
    property int revisioniStato: 0
    property int fileFatti: 0
    property int fileAttesi: 0

    Timer {
        id: timerRicetta
        interval: 350
        onTriggered: win.calcolaAnteprima()
    }

    Timer {
        interval: 1000
        repeat: true
        running: win.compilando
        onTriggered: win.secondiCompilazione++
    }

    Component.onCompleted: {
        staLeggendoKernel = true;
        Core.Ipc.fucinaChiediKernel();
        Core.Ipc.fucinaChiediVersioni();
        Core.Ipc.fucinaElencaProfili();
        Core.Ipc.fucinaChiediStato();
        verificaKernelInUso();
        staRilevando = true;
        Core.Ipc.fucinaRileva();
    }

    Connections {
        target: Core.Ipc
        function onConnectedChanged() {
            if (!Core.Ipc.connected) { win.amministrazioneKernel = null; return; }
            // Una nuova connessione non eredita l'ascolto della precedente.
            // Rileggere lo stato risottoscrive anche gli eventi dell'officina.
            Core.Ipc.fucinaChiediStato();
            Core.Ipc.fucinaChiediKernel();
        }
        function onFucinaGuardo(info) { win.staRilevando = true; }
        function onFucinaKernel(info) {
            win.elencoKernel = info && Array.isArray(info.kernel) ? info.kernel : [];
            win.statoCache = info && info.cache ? info.cache : ({});
            win.amministrazioneKernel = info && info.amministrazione ? info.amministrazione : null;
            win.kernelInUso = info ? String(info.inUso || "") : "";
            win.staLeggendoKernel = false;
        }
        function onFucinaCacheRecuperata(info) {
            win.staRiaprendoCache = false;
            win.esitoRecuperoCache = info && info.ok === true;
            win.messaggioRecuperoCache = String(info && (info.messaggio || info.errore) || "Recupero non riuscito.");
            if (info && info.ok === true)
                win.statoCache = Object.assign({}, win.statoCache, {recupero: {stato: "libero", recuperabile: false}});
            Core.Ipc.fucinaChiediKernel();
        }
        function onFucinaVerifica(info) {
            win.verificaKernel = info;
            win.staVerificandoKernel = false;
        }
        function onFucinaFatto(info) {
            if (info) {
                win.compilando = false;
                win.esitoCompilazione = info;
                win.ricettaCompilazione = info.ricetta || win.ricettaCompilazione;
                win.mostraUltimaBuild = true;
                win.logCompilazione = String(info.log || "");
                win.secondiCompilazione = Number(info.secondi) || 0;
                win.passoCompilazione = "";
                win.faseCompilazione = "";
                win.erroreCompilazione = info.ok === true
                        ? "" : String(info.errore || "La compilazione non è riuscita.");
                win.popupKernelPronto = info.ok === true;
                win.pagina = "compila";
            }
            win.staLeggendoKernel = true;
            Core.Ipc.fucinaChiediKernel();
        }
        function onFucinaTolto(info) {
            win.kernelImpegnato = "";
            win.erroreKernel = info && info.ok === true
                    ? "Kernel rimosso. Aggiorno l’elenco."
                    : String(info && info.errore || "Rimozione non riuscita.");
            win.staLeggendoKernel = true;
            Core.Ipc.fucinaChiediKernel();
        }
        function onFucinaInstallato(info) {
            win.kernelImpegnato = "";
            win.erroreKernel = info && info.ok === true
                    ? "Kernel installato. Resta disponibile quello della distribuzione per il recupero."
                    : String(info && info.errore || "Installazione non riuscita.");
            win.staLeggendoKernel = true;
            Core.Ipc.fucinaChiediKernel();
        }
        function onFucinaAvviata(info) {
            if (!info || info.ok !== true) {
                win.compilando = false;
                win.mostraUltimaBuild = false;
                win.ricettaCompilazione = null;
                win.erroreCompilazione = String(info && info.errore || "Non riesco ad avviare la compilazione.");
                return;
            }
            win.compilando = true;
            win.ricettaCompilazione = info.ricetta || win.ricettaCompilazione;
            win.mostraUltimaBuild = true;
            win.erroreCompilazione = "";
        }
        function onFucinaPasso(info) {
            if (!info) return;
            if (info.log) win.logCompilazione = String(info.log);
            // Una build può partire da un'altra finestra o da una prova IPC.
            // La risposta «avviata» va al richiedente; i passi arrivano a
            // tutti. Anche questa finestra deve attivare timer e comandi.
            if (info.stato === "via" && !win.compilando) {
                win.compilando = true;
                win.ricettaCompilazione = null;
                win.mostraUltimaBuild = true;
                win.esitoCompilazione = null;
                win.erroreCompilazione = "";
                win.pagina = "compila";
                Core.Ipc.fucinaChiediStato();
            }
            var passi = Object.assign({}, win.passiCompilazione);
            passi[String(info.id)] = String(info.stato || "");
            win.passiCompilazione = passi;
            if (info.stato === "via") {
                win.passoCompilazione = String(info.titolo || info.id || "");
                win.faseCompilazione = String(info.id || "");
                win.fileFatti = 0;
                win.fileAttesi = 0;
            }
        }
        function onFucinaRighe(info) {
            if (!info || !Array.isArray(info.righe)) return;
            var righe = win.righeCompilazione.slice();
            info.righe.forEach(function (riga) { righe.push(String(riga)); });
            if (righe.length > 300) righe = righe.slice(righe.length - 300);
            win.righeCompilazione = righe;
        }
        function onFucinaAvanzamento(info) {
            if (!info) return;
            win.faseCompilazione = String(info.fase || win.faseCompilazione);
            win.fileFatti = Number(info.fatti) || 0;
            win.fileAttesi = Number(info.attesi) || 0;
        }
        function onFucinaFermata(info) {
            if (info && info.eraInCorso !== true)
                win.erroreCompilazione = "Non c’era una compilazione da fermare.";
        }
        function onFucinaStato(info) {
            if (!info) return;
            win.revisioniStato++;
            win.logCompilazione = String(info.log || "");
            win.secondiCompilazione = Number(info.secondi) || 0;
            win.righeCompilazione = Array.isArray(info.righe) ? info.righe.slice(-300) : [];
            win.passiCompilazione = info.passi || ({});
            if (info.inCorso === true) {
                win.ricettaCompilazione = info.ricetta || null;
                win.mostraUltimaBuild = true;
                win.compilando = true;
                win.secondiCompilazione = Number(info.secondi) || 0;
                win.passoCompilazione = String(info.passo || "");
                win.passiCompilazione = info.passi || ({});
                var avanzamento = info.avanzamento || ({});
                win.faseCompilazione = String(avanzamento.fase || "");
                win.fileFatti = Number(avanzamento.fatti) || 0;
                win.fileAttesi = Number(avanzamento.attesi) || 0;
                win.righeCompilazione = Array.isArray(info.righe) ? info.righe.slice(-300) : [];
                win.pagina = "compila";
            } else if (info.esito) {
                win.ricettaCompilazione = info.ricetta || info.esito.ricetta || null;
                win.mostraUltimaBuild = true;
                win.compilando = false;
                win.esitoCompilazione = info.esito;
                win.erroreCompilazione = info.esito.ok === true
                        ? "" : String(info.esito.errore || "La compilazione non è riuscita.");
            }
        }
        function onAzioneFallita(azione, perche) {
            if (String(azione).indexOf("fucina_") !== 0) return;
            win.kernelImpegnato = "";
            win.erroreKernel = String(perche || "Il daemon non è riuscito a completare l’azione.");
            if (azione === "fucina_avvia") win.erroreCompilazione = win.erroreKernel;
            if (azione === "fucina_verifica") win.staVerificandoKernel = false;
            if (azione === "fucina_cache_recupera") win.staRiaprendoCache = false;
        }
        function onFucinaRilievo(info) {
            win.rilievo = info;
            win.targetCompilatori = info && Array.isArray(info.targetCompilatori) ? info.targetCompilatori : [];
            if (!win.prioritaProvaAvvio) {
                var attrezzi = info && info.macchina && Array.isArray(info.macchina.attrezzi)
                               ? info.macchina.attrezzi : [];
                win.provaAvvioKernel = attrezzi.some(function (attrezzo) {
                    return attrezzo.nome === "qemu-system-x86" && attrezzo.presente === true;
                });
            }
            if (info && info.regoleModuli)
                win.regoleModuli = info.regoleModuli;
            if (win.scorteUso === null) {
                var predefinite = [];
                var scorte = info && Array.isArray(info.scorte) ? info.scorte : [];
                for (var i = 0; i < scorte.length; i++)
                    if (scorte[i].predefinita === true) predefinite.push(String(scorte[i].id));
                win.scorteUso = predefinite;
            }
            if (!win.prioritaScelta)
                win.targetNativo = win.supportoNativo;
            win.staRilevando = false;
            win.scegliVersioneConsigliata();
        }
        function onFucinaVersioni(info) {
            win.elencoVersioni = info && info.ok === true && Array.isArray(info.versioni)
                                ? info.versioni : [];
            win.erroreVersioni = info && info.ok !== true
                                 ? String(info.errore || "Elenco versioni non disponibile.") : "";
            win.scegliVersioneConsigliata();
        }
        function onFucinaRicetta(info) {
            if (!info || String(info.richiesta || "") !== win.richiestaRicetta) return;
            if (info.ok === true) {
                win.ricettaPreview = info;
                win.erroreRicetta = "";
                win.staCalcolandoRicetta = false;
            } else {
                win.erroreRicetta = String(info.errore || "Non riesco a verificare la ricetta.");
                win.staCalcolandoRicetta = false;
            }
        }
        function onFucinaStorico(info) {
            win.confermaDimentica = false;
            if (info && info.ok === true) {
                win.messaggioStorico = "Storico cancellato; aggiorno i dispositivi collegati adesso.";
                Core.Ipc.fucinaRileva();
            } else {
                win.messaggioStorico = info && info.errore
                                       ? String(info.errore) : "Non riesco a cancellare lo storico.";
            }
        }
        function onFucinaReportEsportato(info) {
            win.staSalvandoReport = false;
            if (info && info.ok === true) {
                win.reportPath = String(info.percorso || "");
                win.erroreReport = "";
            } else {
                win.erroreReport = info && info.errore
                                   ? String(info.errore) : "Non riesco a salvare il report.";
            }
        }
        function onFucinaProfili(info) {
            win.profiliSalvati = info && info.ok === true && Array.isArray(info.profili)
                                 ? info.profili : [];
        }
        function onFucinaProfiloSalvato(info) {
            if (info && info.ok === true) {
                win.profiliSalvati = Array.isArray(info.profili) ? info.profili : win.profiliSalvati;
                win.messaggioProfilo = "Profilo salvato su questo computer.";
            } else {
                win.messaggioProfilo = info && info.errore
                                       ? String(info.errore) : "Non riesco a salvare il profilo.";
            }
        }
        function onFucinaProfiloEliminato(info) {
            if (info && info.ok === true) {
                win.profiliSalvati = Array.isArray(info.profili) ? info.profili : [];
                win.messaggioProfilo = "Profilo eliminato.";
            } else {
                win.messaggioProfilo = info && info.errore
                                       ? String(info.errore) : "Non riesco a eliminare il profilo.";
            }
        }
        function onFucinaProfiloCaricato(info) {
            if (!info || info.ok !== true || !info.scelte) {
                win.messaggioProfilo = info && info.errore
                                       ? String(info.errore) : "Non riesco ad applicare il profilo.";
                return;
            }
            var scelte = info.scelte;
            var presetSalvato = Array.isArray(scelte.preset) ? scelte.preset : [];
            win.presetUso = presetSalvato.length > 0 ? [String(presetSalvato[0])] : [];
            win.scorteUso = Array.isArray(scelte.scorte) ? scelte.scorte.slice() : [];
            win.moduliAggiunti = Array.isArray(scelte.aggiunti) ? scelte.aggiunti.slice() : [];
            win.sorgente = scelte.sorgente === "cachyos" ? "cachyos" : "vanilla";
            win.baseConfig = scelte.base === "defconfig" ? "defconfig" : "in-uso";
            win.compilatore = scelte.compilatore === "clang" ? "clang" : "gcc";
            win.lavoriCompilazione = Number.isInteger(scelte.lavori) ? scelte.lavori : 0;
            win.thinLto = scelte.lto === true && win.compilatore === "clang";
            win.autoFdo = scelte.autofdo === true && win.compilatore === "clang";
            win.provaAvvioKernel = scelte.provaAvvio === true;
            win.prioritaProvaAvvio = true;
            win.prioritaScelta = true;
            win.targetNativo = scelte.nativo === true && info.nativoCompatibile === true;
            win.messaggioProfilo = String(info.avvisoHardware || "Preferenze del profilo applicate.");
            win.scegliVersioneConsigliata();
        }
        function onFucinaRegolaModulo(info) {
            if (info && info.ok === true) {
                win.regoleModuli = info.regole || { "mantieni": [], "escludi": [] };
                win.messaggioRegolaModulo = "Regola salvata e applicata alla ricetta.";
                win.programmaAnteprima();
            } else {
                win.messaggioRegolaModulo = info && info.errore
                                             ? String(info.errore) : "Non riesco a salvare la regola.";
            }
        }
    }

    function scegliVersioneConsigliata() {
        var candidate = "";
        for (var i = 0; i < elencoVersioni.length; i++) {
            var v = elencoVersioni[i];
            if (v.tipo === "stable" && v.finita !== true
                    && (sorgente !== "cachyos" || v.cachyos === true)) {
                candidate = String(v.versione || "");
                break;
            }
        }
        if (candidate === "" && sorgente === "vanilla") {
            for (var j = 0; j < elencoVersioni.length; j++) {
                var fallback = elencoVersioni[j];
                if (fallback.tipo === "longterm" && fallback.finita !== true) {
                    candidate = String(fallback.versione || "");
                    break;
                }
            }
        }
        if (candidate === "" && sorgente === "vanilla" && rilievo) {
            var release = String(rilievo.rilascio || "").match(/^([1-9][0-9]?\.[0-9]{1,3}(\.[0-9]{1,4})?)/);
            if (release) candidate = release[1];
        }
        versioneKernel = candidate;
        // Rilievo e catalogo arrivano in parallelo. Ricalcola la scelta
        // iniziale dopo aver risolto la versione, altrimenti il target
        // restava generico se il rilievo arrivava per primo.
        // Un profilo salvato non deve chiedere un'opzione che la versione
        // scelta non può offrire.
        targetNativo = prioritaScelta
                ? targetNativo && supportoNativo
                : supportoNativo;
        if (candidate === "") {
            ricettaPreview = null;
            staCalcolandoRicetta = false;
            erroreRicetta = "";
        }
        programmaAnteprima();
    }

    function scelteAnteprima() {
        var scorte = Array.isArray(scorteUso) ? scorteUso.slice() : [];
        var disponibili = rilievo && Array.isArray(rilievo.scorte) ? rilievo.scorte : [];
        if (scorteUso === null)
            for (var i = 0; i < disponibili.length; i++)
                if (disponibili[i].predefinita === true) scorte.push(String(disponibili[i].id));
        scorte.sort();
        var preset = Array.isArray(presetUso) ? presetUso.slice() : [];
        preset.sort();
        return {
            "tolti": [],
            "aggiunti": moduliAggiunti.slice().sort(),
            "scorte": scorte,
            "preset": preset,
            "sorgente": sorgente,
            "versione": versioneKernel,
            "base": baseConfig,
            "compilatore": compilatore,
            "lavori": lavoriCompilazione > 0 ? lavoriCompilazione : null,
            "lto": thinLto && compilatore === "clang",
            "provaVeloce": false,
            "nativo": targetNativo,
            "nome": "anteprima",
            "autofdo": autoFdo && compilatore === "clang",
            "profilo": "",
            "misura": true,
            "provaAvvio": provaAvvioKernel
        };
    }

    function alternaPreset(id) {
        if (id === "") {
            presetUso = [];
            return;
        }
        var attivi = Array.isArray(presetUso) ? presetUso : [];
        presetUso = attivi.length === 1 && attivi[0] === id ? [] : [id];
    }

    function commutaScorta(id) {
        var scelte = Array.isArray(scorteUso) ? scorteUso.slice() : [];
        var indice = scelte.indexOf(id);
        if (indice >= 0) scelte.splice(indice, 1);
        else scelte.push(id);
        scorteUso = scelte;
        programmaAnteprima();
    }

    function statoRegolaModulo(nome) {
        var mantenuti = Array.isArray(regoleModuli.mantieni) ? regoleModuli.mantieni : [];
        var esclusi = Array.isArray(regoleModuli.escludi) ? regoleModuli.escludi : [];
        if (mantenuti.indexOf(nome) >= 0) return "mantieni";
        if (esclusi.indexOf(nome) >= 0) return "escludi";
        return "automatico";
    }

    function moduliFiltrati() {
        var tutti = rilievo && Array.isArray(rilievo.moduli) ? rilievo.moduli : [];
        var cerca = filtroModuli.trim().toLowerCase();
        var trovati = [];
        for (var i = 0; i < tutti.length; i++) {
            var m = tutti[i];
            if (cerca === "" || String(m.nome || "").toLowerCase().indexOf(cerca) >= 0
                    || String(m.famiglia || "").toLowerCase().indexOf(cerca) >= 0)
                trovati.push(m);
        }
        return trovati;
    }

    function impostaRegolaModulo(nome, scelta) {
        messaggioRegolaModulo = "Salvo la regola…";
        Core.Ipc.fucinaImpostaRegolaModulo(nome, scelta);
    }

    function salvaProfilo() {
        Core.Ipc.fucinaSalvaProfilo(nomeProfilo, scelteAnteprima());
    }

    function applicaProfilo(id) {
        Core.Ipc.fucinaCaricaProfilo(String(id));
    }

    function nomiPresetScelti() {
        var nomi = [];
        var disponibili = rilievo && rilievo.presets ? rilievo.presets : [];
        for (var i = 0; i < disponibili.length; i++)
            if (presetUso.indexOf(disponibili[i].id) >= 0)
                nomi.push(String(disponibili[i].nome || disponibili[i].id));
        return nomi.length ? nomi.join(" + ") : "Mantieni le impostazioni attuali";
    }

    function nomePrelazione(valore) {
        switch (String(valore || "")) {
        case "none": return "senza prelazione";
        case "voluntary": return "prelazione volontaria";
        case "full": return "prelazione completa";
        case "lazy": return "prelazione adattiva";
        default: return "prelazione non indicata";
        }
    }

    function descrizioneTargetCpu() {
        if (!rilievo || !rilievo.macchina) return "Da rilevare";
        var livello = String(rilievo.macchina.livelloX86 || "");
        return /^v[1-4]$/.test(livello) ? "x86-64 " + livello : "Generico";
    }

    function descrizioneModprobed() {
        var diario = rilievo && rilievo.modprobed ? rilievo.modprobed : null;
        if (!diario) return "Lettura automatica durante il rilievo";
        var percorso = String(diario.percorso || "percorso non disponibile");
        var voci = Number(diario.voci) || 0;
        if (diario.leggibile === true && voci > 0)
            return "Letto automaticamente · " + voci + " voci nel diario · " + percorso
                    + ". La ricetta unisce anche moduli attivi, driver rilevati, essenziali e scorte: il totale può essere maggiore.";
        if (diario.leggibile === true)
            return "File trovato e leggibile, ma vuoto · " + percorso;
        if (diario.fileTrovato === true)
            return "File trovato ma non leggibile · " + percorso;
        return "File non trovato · percorso controllato: " + percorso;
    }

    function versioneSupportaNativo() {
        var parti = String(versioneKernel).match(/^(\d+)\.(\d+)(?:\.|$)/);
        if (!parti) return false;
        var maggiore = Number(parti[1]);
        var minore = Number(parti[2]);
        return maggiore > 6 || (maggiore === 6 && minore >= 16);
    }

    function motivoTargetGenerico() {
        var livello = rilievo && rilievo.macchina
                ? String(rilievo.macchina.livelloX86 || "") : "";
        if (!/^v[1-4]$/.test(livello))
            return "Non è stato rilevato un livello x86-64 v1–v4 utilizzabile. Fucina mantiene il target generico per questa piattaforma.";
        if (rilievo.macchina.flagsCpuUniformi === false || rilievo.macchina.flagsCpuCompleti === false)
            return "I flag delle CPU descritte non sono uniformi o completi. Fucina propone il target generico: native non è verificabile per tutte queste CPU.";
        return "Il kernel " + (versioneKernel || "scelto") + " non offre l'opzione nativa: CONFIG_X86_NATIVE_CPU è disponibile dal kernel 6.16. Fucina mantiene il target generico.";
    }

    function durataPreparazione(secondi) {
        var n = Math.max(0, Math.floor(Number(secondi) || 0));
        var minuti = Math.floor(n / 60);
        var resto = n % 60;
        if (minuti === 0) return n + " s";
        if (resto === 0) return minuti + " min";
        return minuti + " min " + resto + " s";
    }

    function requisitiMancanti() {
        if (!ricettaPreview || !Array.isArray(ricettaPreview.requisitiMancanti)) return [];
        return ricettaPreview.requisitiMancanti;
    }

    function avviaCompilazione() {
        if (compilando || staCalcolandoRicetta || !ricettaPreview) return;
        confermaCompilazione = false;
        erroreCompilazione = "";
        esitoCompilazione = null;
        ricettaCompilazione = ricettaPreview;
        mostraUltimaBuild = true;
        logCompilazione = "";
        passiCompilazione = ({});
        righeCompilazione = ["Richiedo al daemon la ricetta verificata…"];
        passoCompilazione = "Preparazione";
        faseCompilazione = "";
        secondiCompilazione = 0;
        fileFatti = 0;
        fileAttesi = 0;
        pagina = "compila";
        Core.Ipc.fucinaAvvia(scelteAnteprima());
    }

    function fermaCompilazione() {
        righeCompilazione = righeCompilazione.concat(["Richiesta di arresto inviata…"]);
        Core.Ipc.fucinaFerma();
    }

    function apriLog(percorso) {
        var p = String(percorso || "");
        if (p.charAt(0) !== "/") return;
        Qt.openUrlExternally("file://" + p.split("/").map(encodeURIComponent).join("/"));
    }

    function verificaKernelInUso() {
        staVerificandoKernel = true;
        Core.Ipc.fucinaVerificaOra();
    }

    function chiediAzioneKernel(azione, rilascio) {
        var impedimento = motivoBloccoKernel(azione, rilascio);
        if (impedimento) { erroreKernel = impedimento; pagina = "kernel"; return; }
        azioneKernel = String(azione);
        kernelAzione = String(rilascio);
        confermaKernel = true;
    }

    function eseguiAzioneKernel() {
        var azione = azioneKernel;
        var rilascio = kernelAzione;
        confermaKernel = false;
        if (!rilascio) return;
        var impedimento = motivoBloccoKernel(azione, rilascio);
        if (impedimento) { erroreKernel = impedimento; pagina = "kernel"; return; }
        kernelImpegnato = rilascio;
        erroreKernel = "";
        if (azione === "installa") Core.Ipc.fucinaInstalla(rilascio);
        else if (azione === "rimuovi") Core.Ipc.fucinaTogli(rilascio);
    }

    function motivoBloccoKernel(azione, rilascio) {
        if (compilando || kernelImpegnato !== "") return "Attendi la fine del lavoro in corso.";
        if (staLeggendoKernel || !amministrazioneKernel)
            return "I prerequisiti amministrativi non sono ancora verificati. Aggiorna l’elenco.";
        var campo = azione === "installa" ? "installazionePossibile" : "rimozionePossibile";
        if (amministrazioneKernel[campo] !== true) return "Completa i prerequisiti amministrativi indicati prima di procedere.";
        if (azione === "installa" && String(recuperoCache.stato || "libero") !== "libero")
            return "Verifica il recupero della cache prima di installare.";
        var k = elencoKernel.find(function (v) { return String(v.rilascio) === String(rilascio); });
        if (!k) return "Aggiorna l’elenco: questo kernel non è disponibile.";
        if (k.inUso === true) return "È il kernel in uso. Riavvia su un altro prima di modificarlo.";
        if (azione === "installa" && (k.pronto !== true || (k.provaAvvio && k.provaAvvio.ok === false)))
            return "Questo kernel non è pronto: consulta i controlli nella sua scheda.";
        if (azione === "rimuovi" && k.installato !== true) return "Questo kernel non risulta installato.";
        return "";
    }

    function spiegazionePresetScelti() {
        var righe = [];
        var disponibili = rilievo && rilievo.presets ? rilievo.presets : [];
        for (var i = 0; i < disponibili.length; i++) {
            var p = disponibili[i];
            if (presetUso.indexOf(p.id) >= 0 && p.spiega)
                righe.push(String(p.spiega));
        }
        return righe.join(" ");
    }

    function conteggioFonte(fonte) {
        var moduli = rilievo && Array.isArray(rilievo.moduli) ? rilievo.moduli : [];
        var quanti = 0;
        for (var i = 0; i < moduli.length; i++)
            if (Array.isArray(moduli[i].fonti) && moduli[i].fonti.indexOf(fonte) >= 0)
                quanti++;
        return quanti;
    }

    function conteggioConfigKernel(tipo) {
        var config = rilievo && rilievo.configKernel ? rilievo.configKernel : null;
        var gruppi = config && Array.isArray(config.famiglie) ? config.famiglie : [];
        var totale = 0;
        for (var i = 0; i < gruppi.length; i++) {
            var voci = gruppi[i][tipo];
            if (Array.isArray(voci)) totale += voci.length;
        }
        return totale;
    }

    function notaConfigKernel() {
        var config = rilievo && rilievo.configKernel ? rilievo.configKernel : null;
        var gruppi = config && Array.isArray(config.famiglie) ? config.famiglie : [];
        var righe = [];
        for (var i = 0; i < gruppi.length; i++) {
            var g = gruppi[i];
            var quanti = (Array.isArray(g.integrate) ? g.integrate.length : 0)
                       + (Array.isArray(g.modulari) ? g.modulari.length : 0);
            if (quanti > 0) righe.push(String(g.nome) + ": " + quanti);
        }
        var stato = config && config.statoLive ? config.statoLive : {};
        var registrati = Array.isArray(stato.filesystemRegistrati) ? stato.filesystemRegistrati : [];
        var montati = Array.isArray(stato.filesystemMontati) ? stato.filesystemMontati : [];
        var lsm = Array.isArray(stato.lsmAttivi) ? stato.lsmAttivi : [];
        var nota = righe.slice(0, 3);
        if (registrati.length) nota.push("Filesystem registrati: " + registrati.length);
        if (montati.length) nota.push("Montati: " + montati.length);
        if (lsm.length) nota.push("LSM attivi: " + lsm.join(", "));
        return nota.length ? nota.join(" · ") : "Configurazione e stato live non disponibili";
    }

    function alternaModulo(nome) {
        var scelti = moduliAggiunti.slice();
        var posizione = scelti.indexOf(nome);
        if (posizione >= 0) scelti.splice(posizione, 1);
        else scelti.push(nome);
        moduliAggiunti = scelti;
    }

    function programmaAnteprima() {
        contatoreRichiesteRicetta++;
        richiestaRicetta = "";
        if (!rilievo || versioneKernel === "") return;
        ricettaPreview = null;
        erroreRicetta = "";
        staCalcolandoRicetta = true;
        timerRicetta.restart();
    }

    function calcolaAnteprima() {
        if (!rilievo || versioneKernel === "") return;
        var scelte = scelteAnteprima();
        contatoreRichiesteRicetta++;
        richiestaRicetta = "fucina2-" + contatoreRichiesteRicetta;
        staCalcolandoRicetta = true;
        erroreRicetta = "";
        Core.Ipc.fucinaCalcola(scelte, richiestaRicetta);
    }

    onTargetNativoChanged: programmaAnteprima()
    onCompilatoreChanged: programmaAnteprima()
    onLavoriCompilazioneChanged: programmaAnteprima()
    onThinLtoChanged: programmaAnteprima()
    onAutoFdoChanged: programmaAnteprima()
    onProvaAvvioKernelChanged: programmaAnteprima()
    onBaseConfigChanged: programmaAnteprima()
    onPresetUsoChanged: programmaAnteprima()
    onModuliAggiuntiChanged: programmaAnteprima()
    onSorgenteChanged: scegliVersioneConsigliata()

    Rectangle {
        anchors.fill: parent
        color: Theme.Colors.window
    }

    Ui.WindowTitleBar {
        id: barraTitolo
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        label: win.title
        onCloseRequested: win.chiusa()
    }

    Row {
        anchors.top: barraTitolo.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 0

        Rectangle {
            width: 220
            height: parent.height
            color: Theme.Colors.raised

            Column {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 22

                Column {
                    spacing: 5
                    Text {
                        text: "FUCINA"
                        color: Theme.Colors.accent
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeXS
                        font.bold: true
                        font.letterSpacing: 2.2
                    }
                    Text {
                        text: "Kernel su misura"
                        color: Theme.Colors.text
                        font.family: Theme.Typography.fontDisplay
                        font.pixelSize: Theme.Typography.sizeLG
                        font.bold: true
                    }
                    Text {
                        text: "GUIDATA · 2.0"
                        color: Theme.Colors.textMuted
                        font.pixelSize: Theme.Typography.sizeXS
                    }
                }

                Column {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: [
                            { id: "panoramica", label: "Panoramica", icon: "01" },
                            { id: "configura", label: "Configurazione", icon: "02" },
                            { id: "compila", label: "Compilazione", icon: "03" },
                            { id: "kernel", label: "Kernel installati", icon: "04" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width
                            height: 44
                            radius: 12
                            color: win.pagina === modelData.id
                                   ? Theme.Colors.edgeAccent : "transparent"
                            border.width: win.pagina === modelData.id ? 1 : 0
                            border.color: Theme.Colors.edgeAccent
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                spacing: 12
                                Text {
                                    width: 25
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.icon
                                    color: win.pagina === modelData.id
                                           ? Theme.Colors.accent : Theme.Colors.textMuted
                                    font.family: Theme.Typography.fontMono
                                    font.pixelSize: Theme.Typography.sizeXS
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: win.pagina === modelData.id
                                           ? Theme.Colors.text : Theme.Colors.textMuted
                                    font.family: Theme.Typography.fontDisplay
                                    font.pixelSize: Theme.Typography.sizeSM
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    win.pagina = modelData.id;
                                    if (modelData.id === "compila" && !win.ricettaPreview)
                                        win.programmaAnteprima();
                                    if (modelData.id === "kernel") {
                                        win.staLeggendoKernel = true;
                                        Core.Ipc.fucinaChiediKernel();
                                    }
                                }
                            }
                        }
                    }
                }

                Item { width: 1; height: Math.max(0, parent.height - 240) }
                Rectangle {
                    width: parent.width
                    height: 78
                    radius: 14
                    color: Theme.Colors.window
                    border.width: 1
                    border.color: Theme.Colors.edge
                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 5
                        Text {
                            text: "Modalità sicura"
                            color: Theme.Colors.text
                            font.pixelSize: Theme.Typography.sizeSM
                            font.bold: true
                        }
                        Text {
                            text: "Le azioni privilegiate restano nel daemon Fucina."
                            color: Theme.Colors.textMuted
                            wrapMode: Text.WordWrap
                            width: parent.width
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                    }
                }
            }
        }

        Item {
            id: areaContenuto
            width: parent.width - 220
            height: parent.height

        Flickable {
            id: scroll
            objectName: "scorrimentoFucina2"
            anchors.fill: parent
            contentWidth: width
            contentHeight: body.implicitHeight + 64
            clip: true
            interactive: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: body
                objectName: "contenutoFucina2"
                x: 38
                y: 32
                width: scroll.width - 76
                spacing: 24

                Row {
                    width: parent.width
                    spacing: 20
                    Column {
                        width: parent.width - refresh.width - 20
                        spacing: 8
                        Text {
                            text: win.pagina === "panoramica" ? "Il tuo sistema, sotto controllo"
                                  : win.pagina === "configura" ? "Progetta il prossimo kernel"
                                  : win.pagina === "compila" ? "Rivedi e compila"
                                  : "Kernel disponibili"
                            color: Theme.Colors.text
                            font.family: Theme.Typography.fontDisplay
                            font.pixelSize: Theme.Typography.sizeXL
                            font.bold: true
                            width: parent.width
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            text: win.pagina === "compila"
                                  ? "Controlla la ricetta, segui i passaggi e installa il kernel quando è pronto."
                                  : "Fucina analizza l’hardware e costruisce una proposta verificabile prima di ogni modifica."
                            color: Theme.Colors.textMuted
                            font.pixelSize: Theme.Typography.sizeSM
                            width: parent.width
                            wrapMode: Text.WordWrap
                        }
                    }
                    Rectangle {
                        id: refresh
                        width: 44; height: 44; radius: 13
                        color: Theme.Colors.raised
                        border.width: 1; border.color: Theme.Colors.edge
                        Text {
                            anchors.centerIn: parent
                            text: "↻"
                            color: Theme.Colors.text
                            font.pixelSize: 23
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                win.staRilevando = true;
                                Core.Ipc.fucinaRileva();
                                win.staLeggendoKernel = true;
                                Core.Ipc.fucinaChiediKernel();
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 156
                    radius: 20
                    color: Theme.Colors.raised
                    border.width: 1
                    border.color: Theme.Colors.edge
                    Row {
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 18
                        Rectangle {
                            width: 58; height: 58; radius: 18
                            color: Theme.Colors.edgeAccent
                            Text {
                                anchors.centerIn: parent
                                text: "✦"
                                color: Theme.Colors.accent
                                font.pixelSize: 28
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 76
                            spacing: 8
                            Text {
                                text: win.rilievo ? "Rilievo completato" : (win.staRilevando ? "Analisi del sistema in corso…" : "In attesa del daemon Fucina")
                                color: Theme.Colors.text
                                font.pixelSize: Theme.Typography.sizeLG
                                font.bold: true
                            }
                            Text {
                                text: win.rilievo
                                      ? "La panoramica usa i dati del daemon Fucina; puoi impostare il profilo d'uso e la priorità tra prestazioni locali e portabilità."
                                      : "Avvia Minerva con il servizio Fucina attivo, quindi aggiorna il rilievo."
                                color: Theme.Colors.textMuted
                                width: parent.width
                                wrapMode: Text.WordWrap
                                font.pixelSize: Theme.Typography.sizeSM
                            }
                        }
                    }
                }

                Text {
                    visible: win.pagina === "panoramica"
                    text: "HARDWARE RILEVATO"
                    color: Theme.Colors.textMuted
                    font.pixelSize: Theme.Typography.sizeXS
                    font.bold: true
                    font.letterSpacing: 1.5
                }

                Grid {
                    visible: win.pagina === "panoramica"
                    width: parent.width
                    columns: width >= 690 ? 2 : 1
                    spacing: 14
                    Repeater {
                        model: [
                            { label: "PROCESSORE", value: win.rilievo && win.rilievo.macchina ? String(win.rilievo.macchina.cpu || "—") : "In rilevamento", note: win.rilievo && win.rilievo.macchina ? String(win.rilievo.macchina.nuclei || "?") + " thread · " + String(win.rilievo.macchina.fornitore || "vendor non rilevato") : "Modello e produttore" },
                            { label: "TARGET CPU", value: win.descrizioneTargetCpu(), note: win.supportoNativo ? "Livello ISA x86-64 rilevato" : "Target generico · ottimizzazione nativa non disponibile" },
                            { label: "MEMORIA", value: win.rilievo && win.rilievo.macchina ? String(win.rilievo.macchina.ramGB || "?") + " GB" : "In rilevamento", note: win.rilievo && win.rilievo.macchina ? (Number(win.rilievo.macchina.nodiNuma) > 0 ? win.rilievo.macchina.nodiNuma + " nodo/i NUMA rilevati" : "Topologia NUMA non rilevata") : "Capacità installata" },
                            { label: "KERNEL ATTUALE", value: win.rilievo ? String(win.rilievo.rilascio || "—") : "In rilevamento", note: win.rilievo && win.rilievo.macchina ? (win.rilievo.macchina.uefi ? "Avvio UEFI" : "Avvio BIOS/Legacy") : "Rilascio in esecuzione" },
                            { label: "DISPOSITIVI ANALIZZATI", value: win.rilievo && Array.isArray(win.rilievo.dispositivi) ? String(win.rilievo.dispositivi.length) : "In rilevamento", note: "sysfs: PCI, USB, ACPI, I²C e altri bus esposti dal kernel" },
                            { label: "MODULI DRIVER ATTIVI", value: win.rilievo ? String(win.conteggioFonte("legato")) : "In rilevamento", note: "Abbinati ai dispositivi attivi tramite gli alias Kbuild" },
                            { label: "CONFIGURAZIONE E STATO LIVE", value: win.rilievo && win.rilievo.configKernel && win.rilievo.configKernel.disponibile === true ? win.conteggioConfigKernel("integrate") + " integrate · " + win.conteggioConfigKernel("modulari") + " modulari" : "Configurazione non disponibile", note: win.rilievo ? win.notaConfigKernel() + " · le opzioni compilate non provano l'attivazione" : "Leggo configurazione e stato del kernel in uso" },
                            { label: "MODPROBED-DB", value: win.rilievo && win.rilievo.modprobed ? String(win.rilievo.modprobed.voci || 0) + " moduli" : "In rilevamento", note: win.descrizioneModprobed() },
                            { label: "PERIFERICHE RICORDATE", value: win.rilievo ? String(win.rilievo.dispositiviStorici || 0) : "In rilevamento", note: "Modalias dello storico locale, anche se scollegati" },
                            { label: "SENZA DRIVER", value: win.rilievo && Array.isArray(win.rilievo.senzaDriver) ? String(win.rilievo.senzaDriver.length) : "In rilevamento", note: "Dispositivi con possibili moduli candidati da verificare" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: parent.columns === 1 ? parent.width : (parent.width - 14) / 2
                            height: 122
                            radius: 16
                            color: Theme.Colors.raised
                            border.width: 1
                            border.color: Theme.Colors.edge
                            Column {
                                anchors.fill: parent
                                anchors.margins: 18
                                spacing: 8
                                Text { text: modelData.label; color: Theme.Colors.textMuted; font.pixelSize: Theme.Typography.sizeXS; font.bold: true; font.letterSpacing: 1 }
                                Text { text: modelData.value; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeMD; font.bold: true; width: parent.width; elide: Text.ElideRight }
                                Text { text: modelData.note; color: Theme.Colors.textMuted; font.pixelSize: Theme.Typography.sizeXS; width: parent.width; elide: Text.ElideRight }
                            }
                        }
                    }
                }

                Rectangle {
                    visible: win.pagina === "panoramica" && win.rilievo !== null
                    width: parent.width
                    height: reportInfo.implicitHeight + 28
                    radius: 16
                    color: Theme.Colors.raised
                    border.width: 1
                    border.color: Theme.Colors.edge
                    Row {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 14
                        Column {
                            id: reportInfo
                            width: parent.width - 174
                            spacing: 5
                            Text {
                                text: "REPORT DIAGNOSTICO LOCALE"
                                color: Theme.Colors.text
                                font.pixelSize: Theme.Typography.sizeXS
                                font.bold: true
                                font.letterSpacing: 1
                            }
                            Text {
                                text: win.reportPath !== ""
                                      ? "Salvato: " + win.reportPath
                                      : "Report JSON locale con inventario, alias driver e fonti del rilievo. Non include seriali né percorsi personali e resta sul computer."
                                width: parent.width
                                wrapMode: Text.WordWrap
                                color: Theme.Colors.textMuted
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                            Text {
                                visible: win.erroreReport !== ""
                                text: win.erroreReport
                                width: parent.width
                                wrapMode: Text.WordWrap
                                color: Theme.Colors.warning
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 144
                            height: 38
                            radius: 10
                            color: win.staSalvandoReport ? Theme.Colors.edge : Theme.Colors.accent
                            opacity: win.staSalvandoReport ? 0.7 : 1
                            Text {
                                anchors.centerIn: parent
                                text: win.staSalvandoReport ? "Salvataggio…" : (win.reportPath !== "" ? "Salva un altro" : "Salva report")
                                color: Theme.Colors.textOnAccent
                                font.pixelSize: Theme.Typography.sizeXS
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: !win.staSalvandoReport
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    win.staSalvandoReport = true;
                                    win.erroreReport = "";
                                    Core.Ipc.fucinaEsportaRilievo();
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    visible: win.pagina === "panoramica" && win.rilievo !== null
                    width: parent.width
                    height: targetCpuInfo.implicitHeight + 36
                    radius: 16
                    color: Theme.Colors.raised
                    border.width: 1; border.color: Theme.Colors.edge
                    Column {
                        id: targetCpuInfo
                        anchors.fill: parent; anchors.margins: 18; spacing: 10
                        Text {
                            objectName: "titoloTargetCompilatori"
                            text: "Il target scelto dai tuoi compilatori"
                            color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeMD; font.bold: true
                        }
                        Text {
                            width: parent.width; wrapMode: Text.WordWrap
                            text: "Il livello x86-64 descrive un insieme di istruzioni. Il nome qui sotto è invece il target native dichiarato dal compilatore su questo PC. Non è una misura delle prestazioni."
                            color: Theme.Colors.textMuted; font.pixelSize: Theme.Typography.sizeXS
                        }
                        Repeater {
                            model: win.targetCompilatori
                            delegate: Text {
                                required property var modelData
                                objectName: "target-compilatore-" + String(modelData.compilatore)
                                width: targetCpuInfo.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
                                text: String(modelData.compilatore || "Compilatore").toUpperCase() + ": "
                                      + (modelData.rilevato ? String(modelData.cpu) + (modelData.tuning ? " · tuning " + String(modelData.tuning) : "") : String(modelData.messaggio || "Target non verificato"))
                                color: modelData.rilevato ? Theme.Colors.text : Theme.Colors.textMuted
                                font.pixelSize: Theme.Typography.sizeSM
                            }
                        }
                        Text {
                            visible: win.targetCompilatori.length === 0
                            text: "Target dei compilatori non verificato per questa piattaforma o sessione."
                            width: parent.width; wrapMode: Text.WordWrap
                            color: Theme.Colors.textMuted; font.pixelSize: Theme.Typography.sizeXS
                        }
                        Text {
                            objectName: "consiglioTargetCpu"
                            width: parent.width; wrapMode: Text.WordWrap
                            text: win.supportoNativo
                                  ? "Per un kernel dedicato a questo PC puoi provare native; per usarlo su altri PC scegli il target generico. Fucina verifica l’opzione in Kconfig prima della build. Confronta i risultati prima di adottarlo."
                                  : win.motivoTargetGenerico()
                            color: win.supportoNativo ? Theme.Colors.textMuted : Theme.Colors.warning
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                        Rectangle {
                            width: 170; height: 34; radius: 9; color: Theme.Colors.window
                            border.width: 1; border.color: Theme.Colors.edge
                            Text { anchors.centerIn: parent; text: "Rivedi il target CPU"; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeXS }
                            MouseArea { objectName: "rivediTargetCpu"; anchors.fill: parent; onClicked: win.pagina = "configura" }
                        }
                    }
                }

                Rectangle {
                    visible: win.pagina === "panoramica" && win.rilievo !== null
                    width: parent.width
                    height: prioritaInfo.implicitHeight + 36
                    radius: 16
                    color: Theme.Colors.raised
                    border.width: 1
                    border.color: Theme.Colors.edgeAccent
                    Column {
                        id: prioritaInfo
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 9
                        Text {
                            text: "Qual è la tua priorità?"
                            color: Theme.Colors.text
                            font.pixelSize: Theme.Typography.sizeMD
                            font.bold: true
                        }
                        Text {
                            text: win.supportoNativo
                                  ? "La CPU supporta x86-64 " + win.rilievo.macchina.livelloX86 + ". Per un kernel dedicato a questo PC puoi provare l'ottimizzazione nativa; per spostarlo su hardware diverso, scegli un target più portabile. Il vantaggio va verificato con misure sul tuo carico."
                                  : win.motivoTargetGenerico()
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: Theme.Colors.textMuted
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                        Row {
                            width: parent.width
                            spacing: 10
                            Repeater {
                                model: win.supportoNativo
                                       ? [
                                           { nativo: true, titolo: "Ottimizza questo PC", dettaglio: "Kernel 6.16+ · meno portabile" },
                                           { nativo: false, titolo: "Compatibilità più ampia", dettaglio: "Target generico · più riutilizzabile" }
                                         ]
                                       : [
                                           { nativo: false, titolo: "Target generico", dettaglio: "Consigliato per questa piattaforma" }
                                         ]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: win.supportoNativo ? (parent.width - 10) / 2 : parent.width
                                    height: 55
                                    radius: 12
                                    color: win.targetNativo === modelData.nativo
                                           ? Theme.Colors.edgeAccent : Theme.Colors.window
                                    border.width: 1
                                    border.color: win.targetNativo === modelData.nativo
                                                  ? Theme.Colors.accent : Theme.Colors.edge
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 3
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.titolo
                                            color: Theme.Colors.text
                                            font.pixelSize: Theme.Typography.sizeXS
                                            font.bold: true
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.dettaglio
                                            color: Theme.Colors.textMuted
                                            font.pixelSize: Theme.Typography.sizeXS
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            win.targetNativo = modelData.nativo;
                                            win.prioritaScelta = true;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    visible: win.pagina === "kernel"
                    width: parent.width
                    height: elencoKernelBox.implicitHeight + 44
                    radius: 20
                    color: Theme.Colors.raised
                    border.width: 1
                    border.color: Theme.Colors.edge
                    Column {
                        id: elencoKernelBox
                        anchors.fill: parent
                        anchors.margins: 22
                        spacing: 14
                        Text {
                            text: "Kernel creati con Fucina"
                            color: Theme.Colors.text
                            font.pixelSize: Theme.Typography.sizeLG
                            font.bold: true
                        }
                        Text {
                            text: win.kernelInUso !== "" ? "Kernel attivo: " + win.kernelInUso : "Il kernel della distribuzione resta fuori da questo elenco come opzione di recupero."
                            color: Theme.Colors.textMuted
                            font.pixelSize: Theme.Typography.sizeSM
                            width: parent.width
                            wrapMode: Text.WordWrap
                        }
                        Rectangle {
                            width: parent.width
                            height: prerequisitiKernel.implicitHeight + 24
                            radius: 14
                            color: Theme.Colors.window
                            border.width: 1; border.color: Theme.Colors.edge
                            Column {
                                id: prerequisitiKernel
                                anchors.fill: parent; anchors.margins: 12
                                spacing: 8
                                Text {
                                    objectName: "statoPrerequisitiKernel"
                                    width: parent.width; wrapMode: Text.WordWrap
                                    text: !win.amministrazioneKernel ? "Prerequisiti amministrativi: in attesa del daemon"
                                          : win.amministrazioneKernel.installazionePossibile === true ? "Prerequisiti amministrativi disponibili"
                                          : "Prima di installare: completa i prerequisiti"
                                    color: win.amministrazioneKernel && win.amministrazioneKernel.installazionePossibile === true ? Theme.Colors.positive : Theme.Colors.warning
                                    font.pixelSize: Theme.Typography.sizeSM; font.bold: true
                                }
                                Repeater {
                                    model: win.amministrazioneKernel && Array.isArray(win.amministrazioneKernel.controlli)
                                           ? win.amministrazioneKernel.controlli.filter(function (c) { return c.ok !== true; }) : []
                                    delegate: Text {
                                        required property var modelData
                                        width: prerequisitiKernel.width; wrapMode: Text.WordWrap
                                        text: "• " + String(modelData.messaggio || modelData.titolo || "Controllo non disponibile")
                                        textFormat: Text.PlainText
                                        color: Theme.Colors.warning; font.pixelSize: Theme.Typography.sizeXS
                                    }
                                }
                                Text {
                                    width: parent.width; wrapMode: Text.WordWrap
                                    text: "Il controllo non richiede password. Il kernel della distribuzione resta il recupero. "
                                          + "La presenza degli strumenti non certifica spazio libero, initramfs, Secure Boot o avviabilità sull’hardware."
                                    color: Theme.Colors.textMuted; font.pixelSize: Theme.Typography.sizeXS
                                }
                                Rectangle {
                                    width: 160; height: 34; radius: 9; color: Theme.Colors.raised
                                    border.width: 1; border.color: Theme.Colors.edge
                                    Text { anchors.centerIn: parent; text: "Aggiorna controlli"; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeXS }
                                    MouseArea {
                                        objectName: "aggiornaPrerequisitiKernel"
                                        anchors.fill: parent
                                        enabled: !win.staLeggendoKernel && win.kernelImpegnato === ""
                                        onClicked: { win.staLeggendoKernel = true; Core.Ipc.fucinaChiediKernel(); }
                                    }
                                }
                            }
                        }
                        Text {
                            objectName: "verificaDispositivi"
                            visible: win.staVerificandoKernel || win.verificaKernel !== null
                            width: parent.width
                            text: {
                                if (win.staVerificandoKernel) return "Confronto i dispositivi con quelli registrati prima della compilazione…";
                                var v = win.verificaKernel;
                                if (!v || !v.applicabile) return String(v && (v.spiega || v.errore) || "Verifica non disponibile.");
                                var orfani = Array.isArray(v.orfani) ? v.orfani : [];
                                var assenti = Array.isArray(v.assenti) ? v.assenti : [];
                                var ricollocati = Array.isArray(v.ricollocati) ? v.ricollocati : [];
                                var ambigui = Array.isArray(v.ambigui) ? v.ambigui : [];
                                return "Verifica dopo l'avvio: " + Number(v.aPosto || 0) + " dispositivi hanno un driver, "
                                        + orfani.length + " presenti senza driver, " + assenti.length + " non ritrovati nel percorso registrato."
                                        + (ricollocati.length > 0 ? "\n" + ricollocati.length + " ritrovati in un percorso diverso tramite identificativo del modello." : "")
                                        + (ambigui.length > 0 ? "\n" + ambigui.length + " corrispondenze ambigue: non vengono considerate verificate." : "")
                                        + (orfani.length > 0 ? "\nDriver attesi da controllare: " + orfani.map(function (d) { return String(d.modulo || d.driver || "non identificato"); }).join(", ") : "")
                                        + (assenti.length > 0 ? "\nI dispositivi non ritrovati possono essere scollegati o enumerati in un altro percorso." : "")
                                        + "\nIl controllo del driver non misura prestazioni né verifica tutte le funzioni del dispositivo.";
                            }
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            color: win.verificaKernel && Array.isArray(win.verificaKernel.orfani) && win.verificaKernel.orfani.length > 0
                                   ? Theme.Colors.warning : Theme.Colors.textMuted
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                        Text {
                            visible: win.staLeggendoKernel
                            text: "Aggiorno l'elenco…"
                            color: Theme.Colors.textMuted
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                        Text {
                            visible: !win.staLeggendoKernel && win.elencoKernel.length === 0
                            text: "Nessun kernel Fucina pronto o installato. Dopo la prima compilazione appariranno qui lo stato dell'installazione e l'esito della prova d'avvio."
                            color: Theme.Colors.textMuted
                            font.pixelSize: Theme.Typography.sizeSM
                            width: parent.width
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            visible: win.erroreKernel !== ""
                            text: win.erroreKernel
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: win.erroreKernel.indexOf("non riusc") >= 0 || win.erroreKernel.indexOf("Non ") === 0
                                   ? Theme.Colors.warning : Theme.Colors.textMuted
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                        Repeater {
                            model: win.elencoKernel
                            delegate: Rectangle {
                                required property var modelData
                                width: elencoKernelBox.width
                                height: scheda.implicitHeight + 24
                                radius: 14
                                color: Theme.Colors.window
                                border.width: 1
                                border.color: modelData.inUso ? Theme.Colors.edgeAccent : Theme.Colors.edge
                                Column {
                                    id: scheda
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 7
                                    Text {
                                        text: String(modelData.rilascio || "Kernel senza nome")
                                        color: Theme.Colors.text
                                        font.family: Theme.Typography.fontMono
                                        font.pixelSize: Theme.Typography.sizeMD
                                        font.bold: true
                                    }
                                    Text {
                                        text: (modelData.inUso ? "In uso" : (modelData.installato ? (modelData.immagine ? "Installato" : "Installato, immagine mancante") : (modelData.pronto ? "Preparato per l’installazione" : "Controlli da risolvere")))
                                              + (modelData.provaAvvio ? (modelData.provaAvvio.ok === true ? " · prova QEMU superata" : " · prova QEMU non superata") : " · prova QEMU non registrata")
                                              + (modelData.moduli ? " · " + modelData.moduli + " moduli richiesti" : "")
                                              + (modelData.prontoAlProfilo ? (modelData.profilo ? " · profilo AutoFDO registrato" : " · pronto per AutoFDO") : "")
                                        color: modelData.provaAvvio && modelData.provaAvvio.ok !== true ? Theme.Colors.warning : Theme.Colors.textMuted
                                        font.pixelSize: Theme.Typography.sizeXS
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                    }
                                    Text {
                                        objectName: "preparazione-" + String(modelData.rilascio)
                                        visible: !!modelData.preparazione
                                        width: parent.width; wrapMode: Text.WordWrap
                                        text: modelData.preparazione ? (modelData.preparazione.blocchi || []).concat(modelData.preparazione.avvisi || []).join("\n") : ""
                                        color: modelData.preparazione && modelData.preparazione.ok === false ? Theme.Colors.warning : Theme.Colors.textMuted
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                                    Text {
                                        visible: String(modelData.quando || "") !== ""
                                        text: "Compilato il " + String(modelData.quando).substring(0, 19).replace("T", " alle ")
                                        color: Theme.Colors.textFaint
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                                    Text {
                                        visible: Number.isInteger(modelData.secondiPreparazione)
                                        text: "Preparazione misurata: " + win.durataPreparazione(modelData.secondiPreparazione) + " · esclusa la prova QEMU"
                                        color: Theme.Colors.textFaint
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                                    Text {
                                        visible: String(modelData.log || "") !== ""
                                        text: "Apri log completo"
                                        color: Theme.Colors.accent
                                        font.pixelSize: Theme.Typography.sizeXS
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: win.apriLog(modelData.log)
                                        }
                                    }
                                    Row {
                                        visible: (modelData.pronto === true && modelData.installato !== true)
                                                 || (modelData.installato === true && modelData.inUso !== true)
                                        spacing: 8
                                        Rectangle {
                                            visible: modelData.pronto === true && modelData.installato !== true
                                            width: 132
                                            height: 34
                                            radius: 9
                                            color: Theme.Colors.accent
                                            opacity: win.motivoBloccoKernel("installa", modelData.rilascio) === "" ? 1 : 0.45
                                            Text { anchors.centerIn: parent; text: win.kernelImpegnato === modelData.rilascio ? "Attendi…" : "Installa kernel"; color: Theme.Colors.textOnAccent; font.pixelSize: Theme.Typography.sizeXS; font.bold: true }
                                            MouseArea {
                                                objectName: "installa-" + String(modelData.rilascio)
                                                anchors.fill: parent
                                                enabled: win.motivoBloccoKernel("installa", modelData.rilascio) === ""
                                                onClicked: win.chiediAzioneKernel("installa", String(modelData.rilascio))
                                            }
                                        }
                                        Rectangle {
                                            visible: modelData.installato === true && modelData.inUso !== true
                                            width: 132
                                            height: 34
                                            radius: 9
                                            color: Theme.Colors.window
                                            border.width: 1
                                            border.color: Theme.Colors.warning
                                            Text { anchors.centerIn: parent; text: win.kernelImpegnato === modelData.rilascio ? "Attendi…" : "Rimuovi kernel"; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeXS; font.bold: true }
                                            MouseArea {
                                                objectName: "rimuovi-" + String(modelData.rilascio)
                                                anchors.fill: parent
                                                enabled: win.motivoBloccoKernel("rimuovi", modelData.rilascio) === ""
                                                onClicked: win.chiediAzioneKernel("rimuovi", String(modelData.rilascio))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: archivioCache.implicitHeight + 24
                            radius: 14
                            color: Theme.Colors.window
                            border.width: 1
                            border.color: Theme.Colors.edge
                            Column {
                                id: archivioCache
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 7
                                Text {
                                    text: "Sorgenti e archivi conservati"
                                    color: Theme.Colors.text
                                    font.pixelSize: Theme.Typography.sizeSM
                                    font.bold: true
                                }
                                Column {
                                    width: parent.width
                                    spacing: 8
                                    visible: String(win.recuperoCache.stato || "libero") !== "libero"
                                             || win.messaggioRecuperoCache !== ""
                                    Text {
                                        objectName: "statoRecuperoCache"
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        text: win.messaggioRecuperoCache || String(win.recuperoCache.messaggio || "")
                                        color: win.esitoRecuperoCache === true ? Theme.Colors.positive
                                             : (win.esitoRecuperoCache === false ? Theme.Colors.danger
                                                : (win.recuperoCache.stato === "occupato" ? Theme.Colors.textMuted : Theme.Colors.warning))
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                                    Text {
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        text: "Il recupero riapre l’accesso alla cache e conserva sorgenti, kernel e log. Non completa una compilazione o un’installazione interrotta."
                                        color: Theme.Colors.textMuted
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                                    Row {
                                        spacing: 8
                                        Rectangle {
                                            width: 150; height: 34; radius: 9
                                            color: Theme.Colors.raised
                                            border.width: 1; border.color: Theme.Colors.edge
                                            Text { anchors.centerIn: parent; text: "Verifica di nuovo"; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeXS }
                                            MouseArea {
                                                objectName: "verificaRecuperoCache"
                                                anchors.fill: parent
                                                enabled: !win.staRiaprendoCache
                                                onClicked: { win.messaggioRecuperoCache = ""; win.esitoRecuperoCache = null; Core.Ipc.fucinaChiediKernel(); }
                                            }
                                        }
                                        Rectangle {
                                            width: 140; height: 34; radius: 9
                                            opacity: win.recuperoCache.recuperabile === true && !win.staRiaprendoCache ? 1 : 0.45
                                            color: Theme.Colors.accent
                                            Text { anchors.centerIn: parent; text: win.staRiaprendoCache ? "Attendi…" : "Riapri cache"; color: Theme.Colors.textOnAccent; font.pixelSize: Theme.Typography.sizeXS; font.bold: true }
                                            MouseArea {
                                                objectName: "riapriCache"
                                                anchors.fill: parent
                                                enabled: win.recuperoCache.recuperabile === true && !win.staRiaprendoCache
                                                onClicked: { win.staRiaprendoCache = true; win.messaggioRecuperoCache = ""; win.esitoRecuperoCache = null; Core.Ipc.fucinaRecuperaCache(win.recuperoCache.token); }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    text: "La Fucina riusa gli archivi verificati e gli alberi pronti della stessa versione. I sorgenti restano nella cache locale; le compilazioni successive ripartono dall’albero esistente."
                                    color: Theme.Colors.textMuted
                                    font.pixelSize: Theme.Typography.sizeXS
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    text: "Cache: " + String(win.statoCache.percorso || "in attesa del daemon")
                                    color: Theme.Colors.textMuted
                                    font.family: Theme.Typography.fontMono
                                    font.pixelSize: Theme.Typography.sizeXS
                                    width: parent.width
                                    wrapMode: Text.WrapAnywhere
                                }
                                Text {
                                    text: "Archivi: " + String(win.statoCache.percorsoArchivi || "—") + " · " + (Array.isArray(win.statoCache.archivi) ? win.statoCache.archivi.length : 0) + " kernel scaricati"
                                    color: Theme.Colors.textMuted
                                    font.family: Theme.Typography.fontMono
                                    font.pixelSize: Theme.Typography.sizeXS
                                    width: parent.width
                                    wrapMode: Text.WrapAnywhere
                                }
                                Repeater {
                                    model: Array.isArray(win.statoCache.archivi) ? win.statoCache.archivi : []
                                    delegate: Text {
                                        required property var modelData
                                        text: "• " + String(modelData.nome) + " · " + (modelData.verificato ? "firma verificata" : "da verificare")
                                        color: Theme.Colors.textFaint
                                        font.pixelSize: Theme.Typography.sizeXS
                                        width: archivioCache.width
                                        elide: Text.ElideMiddle
                                    }
                                }
                                Text {
                                    text: "Sorgenti estratti: " + (Array.isArray(win.statoCache.alberi) ? win.statoCache.alberi.length : 0) + " · " + String(win.statoCache.percorsoAlberi || "—")
                                    color: Theme.Colors.textMuted
                                    font.family: Theme.Typography.fontMono
                                    font.pixelSize: Theme.Typography.sizeXS
                                    width: parent.width
                                    wrapMode: Text.WrapAnywhere
                                }
                                Repeater {
                                    model: Array.isArray(win.statoCache.alberi) ? win.statoCache.alberi : []
                                    delegate: Text {
                                        required property var modelData
                                        text: "• " + String(modelData.nome) + " · " + (modelData.pronto ? "pronto, riutilizzabile" : (modelData.sorgentiPresenti ? "sorgenti presenti" : "estrazione incompleta"))
                                        color: Theme.Colors.textFaint
                                        font.pixelSize: Theme.Typography.sizeXS
                                        width: archivioCache.width
                                        elide: Text.ElideMiddle
                                    }
                                }
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: 42
                            radius: 12
                            color: Theme.Colors.accent
                            Text {
                                anchors.centerIn: parent
                                text: win.staVerificandoKernel ? "Verifica in corso…" : "Verifica il kernel in uso"
                                color: Theme.Colors.textOnAccent
                                font.pixelSize: Theme.Typography.sizeXS
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: !win.staVerificandoKernel
                                onClicked: win.verificaKernelInUso()
                            }
                        }
                    }
                }

                Rectangle {
                    visible: win.pagina === "configura"
                    width: parent.width
                    height: configurazioneContenuto.implicitHeight + 48
                    radius: 20
                    color: Theme.Colors.raised
                    border.width: 1
                    border.color: Theme.Colors.edge
                    Column {
                        id: configurazioneContenuto
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 12
                        Text {
                            visible: win.pagina === "configura"
                            text: "Imposta un profilo, poi rivedi la ricetta"
                            color: Theme.Colors.text
                            font.pixelSize: Theme.Typography.sizeLG
                            font.bold: true
                        }
                        Column {
                            id: configForm
                            visible: win.pagina === "configura"
                            width: parent.width
                            spacing: 12
                            Text { text: "SORGENTE DEL KERNEL"; color: Theme.Colors.textMuted; font.pixelSize: Theme.Typography.sizeXS; font.bold: true; font.letterSpacing: 1 }
                            Row {
                                width: parent.width; spacing: 10
                                Repeater {
                                    model: [
                                        { id: "vanilla", name: "Kernel.org · Vanilla", note: "Base ufficiale" },
                                        { id: "cachyos", name: "CachyOS", note: "Sorgenti e patch CachyOS" }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: (parent.width - 10) / 2; height: 58; radius: 12
                                        color: win.sorgente === modelData.id ? Theme.Colors.edgeAccent : Theme.Colors.window
                                        border.width: 1; border.color: win.sorgente === modelData.id ? Theme.Colors.accent : Theme.Colors.edge
                                        Column {
                                            anchors.centerIn: parent; spacing: 3
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeXS; font.bold: true }
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.note; color: Theme.Colors.textMuted; font.pixelSize: Theme.Typography.sizeXS }
                                        }
                                        MouseArea { objectName: "sorgente-" + modelData.id; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.sorgente = modelData.id }
                                    }
                                }
                            }
                            Text {
                                text: "COMPILATORE"
                                color: Theme.Colors.textMuted
                                font.pixelSize: Theme.Typography.sizeXS
                                font.bold: true
                                font.letterSpacing: 1
                            }
                            Row {
                                width: parent.width; spacing: 10
                                Repeater {
                                    model: [
                                        { id: "gcc", name: "GCC", note: "Scelta equilibrata" },
                                        { id: "clang", name: "Clang", note: "ThinLTO opzionale" }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: (parent.width - 10) / 2; height: 58; radius: 12
                                        color: win.compilatore === modelData.id ? Theme.Colors.edgeAccent : Theme.Colors.window
                                        border.width: 1; border.color: win.compilatore === modelData.id ? Theme.Colors.accent : Theme.Colors.edge
                                        Column {
                                            anchors.centerIn: parent; spacing: 3
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeXS; font.bold: true }
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.note; color: Theme.Colors.textMuted; font.pixelSize: Theme.Typography.sizeXS }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            objectName: "compilatore-" + modelData.id
                                            onClicked: {
                                                win.compilatore = modelData.id;
                                                if (modelData.id !== "clang") {
                                                    win.thinLto = false;
                                                    win.autoFdo = false;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            Row {
                                width: parent.width
                                spacing: 10
                                Text {
                                    text: "LAVORI PARALLELI"
                                    color: Theme.Colors.textMuted
                                    font.pixelSize: Theme.Typography.sizeXS
                                    font.bold: true
                                    font.letterSpacing: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Item { width: 1; height: 1 }
                                Rectangle {
                                    width: 74; height: 34; radius: 9
                                    color: win.lavoriCompilazione === 0 ? Theme.Colors.edgeAccent : Theme.Colors.window
                                    border.width: 1
                                    border.color: win.lavoriCompilazione === 0 ? Theme.Colors.accent : Theme.Colors.edge
                                    Text { anchors.centerIn: parent; text: "Auto"; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeXS; font.bold: true }
                                    MouseArea { objectName: "lavori-auto"; anchors.fill: parent; onClicked: win.lavoriCompilazione = 0 }
                                }
                                Rectangle {
                                    width: 38; height: 34; radius: 9
                                    color: Theme.Colors.window; border.width: 1; border.color: Theme.Colors.edge
                                    opacity: (win.lavoriCompilazione === 0 ? win.lavoriAuto : win.lavoriCompilazione) <= 1 ? 0.5 : 1
                                    Text { anchors.centerIn: parent; text: "−"; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeSM }
                                    MouseArea {
                                        objectName: "lavori-meno"
                                        anchors.fill: parent
                                        enabled: win.lavoriCompilazione === 0
                                                 ? win.parallelismoPreview !== null && win.lavoriAuto > 1
                                                 : win.lavoriCompilazione > 1
                                        onClicked: {
                                            win.lavoriCompilazione = win.lavoriCompilazione === 0 ? win.lavoriAuto - 1 : win.lavoriCompilazione - 1;
                                        }
                                    }
                                }
                                Text {
                                    objectName: "lavori-effettivi"
                                    text: win.lavoriCompilazione === 0
                                          ? (win.parallelismoPreview ? "Auto · " + win.lavoriAuto + " lavori" : "Auto · verifica…")
                                          : win.lavoriCompilazione + " lavori"
                                    color: Theme.Colors.text
                                    font.pixelSize: Theme.Typography.sizeXS
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    width: 100
                                }
                                Rectangle {
                                    width: 38; height: 34; radius: 9
                                    color: Theme.Colors.window; border.width: 1; border.color: Theme.Colors.edge
                                    opacity: (win.lavoriCompilazione === 0 ? win.lavoriAuto : win.lavoriCompilazione) >= win.threadCompilazione ? 0.5 : 1
                                    Text { anchors.centerIn: parent; text: "+"; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeSM }
                                    MouseArea {
                                        objectName: "lavori-piu"
                                        anchors.fill: parent
                                        enabled: win.lavoriCompilazione === 0
                                                 ? win.parallelismoPreview !== null && win.lavoriAuto < win.threadCompilazione
                                                 : win.lavoriCompilazione < win.threadCompilazione
                                        onClicked: {
                                            win.lavoriCompilazione = Math.min(win.threadCompilazione,
                                                (win.lavoriCompilazione === 0 ? win.lavoriAuto : win.lavoriCompilazione) + 1);
                                        }
                                    }
                                }
                            }
                            Text {
                                objectName: "consiglio-parallelismo"
                                text: win.parallelismoPreview
                                      ? String(win.parallelismoPreview.motivo) + "\n"
                                        + (win.parallelismoPreview.manualeOltreConsiglio ? "Il limite manuale supera il consiglio: aumenta la pressione sulla memoria.\n" : "")
                                        + String(win.parallelismoPreview.limite)
                                      : "Auto valuta i thread e la memoria disponibile. Il daemon sta verificando la ricetta."
                                width: parent.width
                                wrapMode: Text.WordWrap
                                color: win.parallelismoPreview && win.parallelismoPreview.manualeOltreConsiglio ? Theme.Colors.warning : Theme.Colors.textMuted
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                            Text { text: "PROFILI SALVATI SU QUESTO COMPUTER"; color: Theme.Colors.textMuted; font.pixelSize: Theme.Typography.sizeXS; font.bold: true; font.letterSpacing: 1 }
                            Row {
                                width: parent.width
                                spacing: 8
                                Rectangle {
                                    width: parent.width - 112
                                    height: 38
                                    radius: 9
                                    color: Theme.Colors.window
                                    border.width: 1
                                    border.color: Theme.Colors.edge
                                    TextInput {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        verticalAlignment: TextInput.AlignVCenter
                                        text: win.nomeProfilo
                                        color: Theme.Colors.text
                                        selectionColor: Theme.Colors.accent
                                        selectedTextColor: Theme.Colors.textOnAccent
                                        font.pixelSize: Theme.Typography.sizeXS
                                        maximumLength: 48
                                        onTextEdited: win.nomeProfilo = text
                                    }
                                }
                                Rectangle {
                                    width: 104
                                    height: 38
                                    radius: 9
                                    color: Theme.Colors.accent
                                    Text { anchors.centerIn: parent; text: "Salva"; color: Theme.Colors.textOnAccent; font.pixelSize: Theme.Typography.sizeXS; font.bold: true }
                                    MouseArea { anchors.fill: parent; onClicked: win.salvaProfilo() }
                                }
                            }
                            Text {
                                visible: win.messaggioProfilo !== ""
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: win.messaggioProfilo
                                color: win.messaggioProfilo.indexOf("diversa") >= 0 ? Theme.Colors.warning : Theme.Colors.textMuted
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                            Repeater {
                                model: win.profiliSalvati
                                delegate: Rectangle {
                                    required property var modelData
                                    width: configForm.width
                                    height: 54
                                    radius: 10
                                    color: Theme.Colors.window
                                    border.width: 1
                                    border.color: Theme.Colors.edge
                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 8
                                        spacing: 8
                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 150
                                            spacing: 3
                                            Text { width: parent.width; text: String(modelData.nome || "Profilo"); color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeXS; font.bold: true; elide: Text.ElideRight }
                                            Text {
                                                width: parent.width
                                                text: modelData.hardware && modelData.hardware.cpu ? String(modelData.hardware.cpu) : "Hardware non indicato"
                                                color: Theme.Colors.textMuted
                                                font.pixelSize: Theme.Typography.sizeXS
                                                elide: Text.ElideMiddle
                                            }
                                        }
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 74; height: 30; radius: 8
                                            color: Theme.Colors.edgeAccent
                                            Text { anchors.centerIn: parent; text: "Applica"; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeXS }
                                            MouseArea { anchors.fill: parent; onClicked: win.applicaProfilo(modelData.id) }
                                        }
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 50; height: 30; radius: 8
                                            color: Theme.Colors.raised
                                            Text { anchors.centerIn: parent; text: "Elimina"; color: Theme.Colors.warning; font.pixelSize: Theme.Typography.sizeXS }
                                            MouseArea { anchors.fill: parent; onClicked: Core.Ipc.fucinaEliminaProfilo(String(modelData.id)) }
                                        }
                                    }
                                }
                            }
                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: "Un profilo conserva le preferenze, non la versione del kernel. Se la CPU è diversa, l’ottimizzazione nativa viene disattivata quando lo applichi."
                                color: Theme.Colors.textMuted
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                            Text { text: "DA TENERE ANCHE SE OGGI NON SONO COLLEGATI"; color: Theme.Colors.textMuted; font.pixelSize: Theme.Typography.sizeXS; font.bold: true; font.letterSpacing: 1 }
                            Repeater {
                                model: win.rilievo && Array.isArray(win.rilievo.scorte) ? win.rilievo.scorte : []
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool selezionata: Array.isArray(win.scorteUso)
                                        ? win.scorteUso.indexOf(String(modelData.id)) >= 0
                                        : modelData.predefinita === true
                                    width: configForm.width
                                    height: 54
                                    radius: 10
                                    color: selezionata ? Theme.Colors.edgeAccent : Theme.Colors.window
                                    border.width: 1
                                    border.color: selezionata ? Theme.Colors.accent : Theme.Colors.edge
                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 10
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.selezionata ? "✓" : "＋"; color: Theme.Colors.accent; font.pixelSize: Theme.Typography.sizeSM; font.bold: true }
                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 32
                                            spacing: 2
                                            Text { width: parent.width; text: modelData.nome; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeXS; font.bold: true; elide: Text.ElideRight }
                                            Text { width: parent.width; text: modelData.spiega; color: Theme.Colors.textMuted; font.pixelSize: Theme.Typography.sizeXS; elide: Text.ElideRight }
                                        }
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.commutaScorta(String(modelData.id)) }
                                }
                            }
                            Rectangle {
                                width: parent.width
                                height: 52
                                radius: 11
                                color: Theme.Colors.window
                                border.width: 1
                                border.color: win.moduliEspansi ? Theme.Colors.accent : Theme.Colors.edge
                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 10
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 38
                                        spacing: 3
                                        Text {
                                            text: "Decisioni per singolo modulo"
                                            color: Theme.Colors.text
                                            font.pixelSize: Theme.Typography.sizeSM
                                            font.bold: true
                                        }
                                        Text {
                                            text: win.moduliEspansi
                                                  ? win.moduliFiltrati().length + " moduli visibili"
                                                  : "Elenco compresso · " + (win.rilievo && Array.isArray(win.rilievo.moduli) ? win.rilievo.moduli.length : 0) + " moduli"
                                            color: Theme.Colors.textMuted
                                            font.pixelSize: Theme.Typography.sizeXS
                                        }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: win.moduliEspansi ? "⌃" : "⌄"
                                        color: Theme.Colors.accent
                                        font.pixelSize: Theme.Typography.sizeLG
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    objectName: "comprimereModuli"
                                    onClicked: win.moduliEspansi = !win.moduliEspansi
                                }
                            }
                            Item {
                                objectName: "contenitoreDecisioniModuli"
                                width: parent.width
                                height: win.moduliEspansi ? decisioniModuliContent.implicitHeight : 0
                                clip: true
                                Column {
                                    id: decisioniModuliContent
                                    width: parent.width
                                    spacing: 8
                                    Text {
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        text: "Le regole valgono anche per le prossime versioni. Mantieni aggiunge il modulo alla proposta; Escludi lo rimuove. Automatico lascia decidere a hardware, modprobed-db e scorte. I componenti necessari all’avvio restano protetti."
                                        color: Theme.Colors.textMuted
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                            Rectangle {
                                width: parent.width
                                height: 38
                                radius: 9
                                color: Theme.Colors.window
                                border.width: 1
                                border.color: Theme.Colors.edge
                                TextInput {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: win.filtroModuli
                                    color: Theme.Colors.text
                                    selectionColor: Theme.Colors.accent
                                    selectedTextColor: Theme.Colors.textOnAccent
                                    font.pixelSize: Theme.Typography.sizeXS
                                    onTextEdited: win.filtroModuli = text
                                }
                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    verticalAlignment: Text.AlignVCenter
                                    visible: win.filtroModuli === ""
                                    text: "Filtra per nome o famiglia…"
                                    color: Theme.Colors.textFaint
                                    font.pixelSize: Theme.Typography.sizeXS
                                }
                            }
                            Text {
                                width: parent.width
                                text: win.moduliFiltrati().length + " moduli trovati · le decisioni sono locali a questo computer"
                                color: Theme.Colors.textMuted
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                            Text {
                                visible: win.messaggioRegolaModulo !== ""
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: win.messaggioRegolaModulo
                                color: win.messaggioRegolaModulo.indexOf("protett") >= 0 ? Theme.Colors.warning : Theme.Colors.textMuted
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                            Repeater {
                                model: win.moduliFiltrati()
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property string nomeModulo: String(modelData.nome)
                                    width: configForm.width
                                    height: 56
                                    radius: 10
                                    color: Theme.Colors.window
                                    border.width: 1
                                    border.color: Theme.Colors.edge
                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 7
                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 200
                                            spacing: 3
                                            Text { width: parent.width; text: String(modelData.nome); color: Theme.Colors.text; font.family: Theme.Typography.fontMono; font.pixelSize: Theme.Typography.sizeXS; elide: Text.ElideRight }
                                            Text {
                                                width: parent.width
                                                text: String(modelData.famiglia || "altro")
                                                      + (modelData.essenziale === true ? " · necessario all’avvio" : " · " + (Array.isArray(modelData.fonti) ? modelData.fonti.join(", ") : ""))
                                                color: modelData.essenziale === true ? Theme.Colors.warning : Theme.Colors.textMuted
                                                font.pixelSize: Theme.Typography.sizeXS
                                                elide: Text.ElideRight
                                            }
                                        }
                                        Repeater {
                                            model: [
                                                { id: "automatico", label: "Auto" },
                                                { id: "mantieni", label: "Tieni" },
                                                { id: "escludi", label: "Escludi" }
                                            ]
                                            delegate: Rectangle {
                                                required property var modelData
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 58
                                                height: 30
                                                radius: 8
                                                readonly property bool selezionata: win.statoRegolaModulo(modelloRiga.nomeModulo) === modelData.id
                                                color: selezionata ? Theme.Colors.edgeAccent : Theme.Colors.raised
                                                border.width: 1
                                                border.color: selezionata ? Theme.Colors.accent : Theme.Colors.edge
                                                opacity: modelData.id === "escludi" && modelloRiga.modelData.essenziale === true ? 0.45 : 1
                                                Text { anchors.centerIn: parent; text: modelData.label; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeXS }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    enabled: !(modelData.id === "escludi" && modelloRiga.modelData.essenziale === true)
                                                    onClicked: win.impostaRegolaModulo(modelloRiga.nomeModulo, modelData.id)
                                                }
                                            }
                                            id: selezioniRegola
                                        }
                                    }
                                    id: modelloRiga
                                }
                            }
                                }
                            }
                            Text { text: "PROFILO D'USO"; color: Theme.Colors.textMuted; font.pixelSize: Theme.Typography.sizeXS; font.bold: true; font.letterSpacing: 1 }
                            Grid {
                                id: profiliUso
                                width: parent.width
                                columns: 2
                                spacing: 10
                                Repeater {
                                    model: [{ id: "", nome: "Mantieni", hz: 0, prelazione: "" }].concat(
                                        win.rilievo && win.rilievo.presets ? win.rilievo.presets : [])
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: (profiliUso.width - 10) / 2
                                        height: 64
                                        radius: 12
                                        color: (modelData.id === "" ? win.presetUso.length === 0 : win.presetUso.indexOf(modelData.id) >= 0) ? Theme.Colors.edgeAccent : Theme.Colors.window
                                        border.width: 1
                                        border.color: (modelData.id === "" ? win.presetUso.length === 0 : win.presetUso.indexOf(modelData.id) >= 0) ? Theme.Colors.accent : Theme.Colors.edge
                                        Text {
                                            visible: modelData.id === "" ? win.presetUso.length === 0 : win.presetUso.indexOf(modelData.id) >= 0
                                            anchors.top: parent.top
                                            anchors.right: parent.right
                                            anchors.topMargin: 6
                                            anchors.rightMargin: 8
                                            text: "✓"
                                            color: Theme.Colors.accent
                                            font.pixelSize: Theme.Typography.sizeXS
                                            font.bold: true
                                        }
                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 3
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: modelData.nome
                                                color: Theme.Colors.text
                                                font.pixelSize: Theme.Typography.sizeXS
                                                font.bold: true
                                            }
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: modelData.hz ? modelData.hz + " Hz · " + win.nomePrelazione(modelData.prelazione) : "Nessun preset applicato"
                                                color: Theme.Colors.textMuted
                                                font.pixelSize: Theme.Typography.sizeXS
                                            }
                                        }
                                        MouseArea {
                                            objectName: "preset-" + modelData.id
                                            anchors.fill: parent
                                            onClicked: win.alternaPreset(modelData.id)
                                        }
                                    }
                                }
                            }
                            Text {
                                visible: win.presetUso.length > 0
                                text: win.spiegazionePresetScelti() + " È attivo un solo profilo alla volta; tocca di nuovo quello selezionato per tornare a Mantieni."
                                width: parent.width
                                wrapMode: Text.WordWrap
                                color: Theme.Colors.textMuted
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                            Text { text: "CONFIGURAZIONE DI PARTENZA"; color: Theme.Colors.textMuted; font.pixelSize: Theme.Typography.sizeXS; font.bold: true; font.letterSpacing: 1 }
                            Row {
                                width: parent.width; spacing: 10
                                Repeater {
                                    model: [
                                        { id: "in-uso", name: "Kernel in uso", note: "Mantiene le opzioni attuali" },
                                        { id: "defconfig", name: "Defconfig", note: "Impostazioni generiche" }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: (parent.width - 10) / 2; height: 54; radius: 12
                                        color: win.baseConfig === modelData.id ? Theme.Colors.edgeAccent : Theme.Colors.window
                                        border.width: 1; border.color: win.baseConfig === modelData.id ? Theme.Colors.accent : Theme.Colors.edge
                                        Column {
                                            anchors.centerIn: parent; spacing: 3
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeXS; font.bold: true }
                                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.note; color: Theme.Colors.textMuted; font.pixelSize: Theme.Typography.sizeXS }
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: win.baseConfig = modelData.id }
                                    }
                                }
                            }
                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: {
                                    var diario = win.rilievo && win.rilievo.modprobed ? win.rilievo.modprobed : null;
                                    if (!diario) return "modprobed-db viene controllato durante il rilievo. Questa scelta, invece, decide da quale configurazione Kconfig partire."
                                    if (diario.presente === true)
                                        return "Base Kconfig indipendente dal diario: modprobed-db è stato letto automaticamente (" + Number(diario.voci || 0) + " voci) da " + String(diario.percorso || "percorso non disponibile") + ". I moduli riconosciuti vengono conservati anche se ora sono scollegati."
                                    return "Base Kconfig indipendente dal diario. modprobed-db non è stato trovato o non contiene moduli; percorso controllato: " + String(diario.percorso || "non disponibile") + "."
                                }
                                color: Theme.Colors.textMuted
                                font.pixelSize: Theme.Typography.sizeXS
                            }
                            Rectangle {
                                width: parent.width; height: 52; radius: 12
                                color: win.compilatore === "clang" ? Theme.Colors.window : Theme.Colors.raised
                                border.width: 1; border.color: win.compilatore === "clang" ? Theme.Colors.edge : Theme.Colors.edge
                                opacity: win.compilatore === "clang" ? 1 : 0.55
                                Row {
                                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter; width: parent.width - 48; spacing: 2
                                        Text { text: "ThinLTO"; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeXS; font.bold: true }
                                        Text { text: "Ottimizzazione al collegamento · build più lunga · solo Clang"; color: Theme.Colors.textMuted; font.pixelSize: Theme.Typography.sizeXS; width: parent.width; elide: Text.ElideRight }
                                    }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter; width: 38; height: 22; radius: 11
                                        color: win.thinLto ? Theme.Colors.accent : Theme.Colors.edge
                                        Rectangle { x: win.thinLto ? 19 : 3; y: 3; width: 16; height: 16; radius: 8; color: Theme.Colors.textOnAccent }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: win.compilatore === "clang"
                                    onClicked: win.thinLto = !win.thinLto
                                }
                            }
                            Rectangle {
                                width: parent.width
                                height: 82
                                radius: 12
                                color: win.profiloAutoFdoPossibile ? Theme.Colors.window : Theme.Colors.raised
                                border.width: 1
                                border.color: win.autoFdo ? Theme.Colors.accent : Theme.Colors.edge
                                opacity: win.profiloAutoFdoPossibile ? 1 : 0.68
                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 12
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 50
                                        spacing: 4
                                        Text {
                                            text: "AutoFDO · profilo sul tuo uso reale"
                                            color: Theme.Colors.text
                                            font.pixelSize: Theme.Typography.sizeXS
                                            font.bold: true
                                        }
                                        Text {
                                            text: win.profiloAutoFdoPossibile
                                                  ? "Richiede installare questo kernel, usarlo, registrare il profilo e ricompilare. Non promette un miglioramento senza misure."
                                                  : (win.profiloHardware ? win.profiloHardware.perche : "In attesa del rilievo hardware.")
                                            width: parent.width
                                            wrapMode: Text.WordWrap
                                            color: Theme.Colors.textMuted
                                            font.pixelSize: Theme.Typography.sizeXS
                                        }
                                    }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 38; height: 22; radius: 11
                                        color: win.autoFdo ? Theme.Colors.accent : Theme.Colors.edge
                                        Rectangle {
                                            x: win.autoFdo ? 19 : 3; y: 3
                                            width: 16; height: 16; radius: 8
                                            color: Theme.Colors.textOnAccent
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: win.profiloAutoFdoPossibile
                                    onClicked: {
                                        win.autoFdo = !win.autoFdo;
                                        if (win.autoFdo) {
                                            win.compilatore = "clang";
                                            win.thinLto = true;
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                width: parent.width
                                height: 84
                                radius: 12
                                color: win.provaAvvioKernel ? Theme.Colors.window : Theme.Colors.raised
                                border.width: 1
                                border.color: win.provaAvvioKernel ? Theme.Colors.accent : Theme.Colors.edge
                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 12
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 50
                                        spacing: 4
                                        Text {
                                            text: "Prova d’avvio in QEMU"
                                            color: Theme.Colors.text
                                            font.pixelSize: Theme.Typography.sizeXS
                                            font.bold: true
                                        }
                                        Text {
                                            text: win.provaAvvioKernel
                                                  ? "Avvia una macchina virtuale prima di dichiarare il kernel pronto. Se non parte, Fucina blocca l’installazione; i dischi reali non vengono provati."
                                                  : "Consigliata prima dell’installazione. QEMU " + (win.qemuDisponibile ? "è disponibile." : "non è rilevato: sudo pacman -S --needed qemu-system-x86.")
                                            width: parent.width
                                            wrapMode: Text.WordWrap
                                            color: Theme.Colors.textMuted
                                            font.pixelSize: Theme.Typography.sizeXS
                                        }
                                    }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 38; height: 22; radius: 11
                                        color: win.provaAvvioKernel ? Theme.Colors.accent : Theme.Colors.edge
                                        Rectangle {
                                            x: win.provaAvvioKernel ? 19 : 3; y: 3
                                            width: 16; height: 16; radius: 8
                                            color: Theme.Colors.textOnAccent
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        win.prioritaProvaAvvio = true;
                                        win.provaAvvioKernel = !win.provaAvvioKernel;
                                    }
                                }
                            }
                            Rectangle {
                                width: parent.width
                                height: 112
                                radius: 12
                                color: Theme.Colors.window
                                border.width: 1
                                border.color: Theme.Colors.edge
                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 6
                                    Text {
                                        text: "Storico periferiche"
                                        color: Theme.Colors.text
                                        font.pixelSize: Theme.Typography.sizeXS
                                        font.bold: true
                                    }
                                    Text {
                                        text: "Salva solo i modalias (non i numeri seriali) per mantenere i driver di periferiche già viste."
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        color: Theme.Colors.textMuted
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                                    Row {
                                        spacing: 8
                                        Rectangle {
                                            width: win.confermaDimentica ? 142 : 182
                                            height: 30
                                            radius: 9
                                            color: win.confermaDimentica ? Theme.Colors.warning : Theme.Colors.raised
                                            border.width: 1
                                            border.color: Theme.Colors.edge
                                            Text {
                                                anchors.centerIn: parent
                                                text: win.confermaDimentica ? "Conferma cancellazione" : "Dimentica periferiche passate"
                                                color: Theme.Colors.text
                                                font.pixelSize: Theme.Typography.sizeXS
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: {
                                                    if (win.confermaDimentica)
                                                        Core.Ipc.fucinaDimenticaDispositivi();
                                                    else
                                                        win.confermaDimentica = true;
                                                }
                                            }
                                        }
                                        Rectangle {
                                            visible: win.confermaDimentica
                                            width: 78; height: 30; radius: 9
                                            color: Theme.Colors.raised
                                            border.width: 1; border.color: Theme.Colors.edge
                                            Text { anchors.centerIn: parent; text: "Annulla"; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeXS }
                                            MouseArea { anchors.fill: parent; onClicked: win.confermaDimentica = false }
                                        }
                                    }
                                    Text {
                                        visible: win.messaggioStorico !== ""
                                        text: win.messaggioStorico
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        color: Theme.Colors.textMuted
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                                }
                            }
                            Rectangle {
                                visible: win.rilievo && Array.isArray(win.rilievo.senzaDriver) && win.rilievo.senzaDriver.length > 0
                                width: parent.width
                                height: candidatiHardware.implicitHeight + 28
                                radius: 12
                                color: Theme.Colors.window
                                border.width: 1
                                border.color: Theme.Colors.warning
                                Column {
                                    id: candidatiHardware
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 8
                                    Text {
                                        text: "DISPOSITIVI SENZA DRIVER ASSOCIATO"
                                        color: Theme.Colors.warning
                                        font.pixelSize: Theme.Typography.sizeXS
                                        font.bold: true
                                        font.letterSpacing: 1
                                    }
                                    Text {
                                        text: "Fucina ha trovato moduli candidati tramite gli alias del kernel. Se riconosci una periferica che usi, seleziona il suo driver per includerlo nella proposta."
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        color: Theme.Colors.textMuted
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                                    Repeater {
                                        model: win.rilievo && Array.isArray(win.rilievo.senzaDriver) ? win.rilievo.senzaDriver : []
                                        delegate: Rectangle {
                                            id: dispositivoCandidato
                                            required property var modelData
                                            width: candidatiHardware.width
                                            height: dettagliDispositivo.implicitHeight + 16
                                            radius: 9
                                            color: Theme.Colors.raised
                                            border.width: 1
                                            border.color: Theme.Colors.edge
                                            Column {
                                                id: dettagliDispositivo
                                                anchors.fill: parent
                                                anchors.margins: 9
                                                spacing: 6
                                                Text {
                                                    text: String(dispositivoCandidato.modelData.bus || "bus").toUpperCase() + " · " + String(dispositivoCandidato.modelData.modalias || "identificativo non disponibile")
                                                    width: parent.width
                                                    elide: Text.ElideMiddle
                                                    color: Theme.Colors.text
                                                    font.family: Theme.Typography.fontMono
                                                    font.pixelSize: Theme.Typography.sizeXS
                                                }
                                                Text {
                                                    text: String(dispositivoCandidato.modelData.percorso || "")
                                                    width: parent.width
                                                    elide: Text.ElideMiddle
                                                    color: Theme.Colors.textMuted
                                                    font.pixelSize: Theme.Typography.sizeXS
                                                }
                                                Repeater {
                                                    model: Array.isArray(dispositivoCandidato.modelData.candidati) ? dispositivoCandidato.modelData.candidati : []
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        width: dettagliDispositivo.width
                                                        height: 32
                                                        radius: 8
                                                        color: win.moduliAggiunti.indexOf(String(modelData)) >= 0 ? Theme.Colors.edgeAccent : Theme.Colors.window
                                                        border.width: 1
                                                        border.color: win.moduliAggiunti.indexOf(String(modelData)) >= 0 ? Theme.Colors.accent : Theme.Colors.edge
                                                        Row {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 10
                                                            anchors.rightMargin: 10
                                                            spacing: 8
                                                            Text {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: win.moduliAggiunti.indexOf(String(modelData)) >= 0 ? "✓" : "+"
                                                                color: Theme.Colors.accent
                                                                font.bold: true
                                                            }
                                                            Text {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: String(modelData)
                                                                color: Theme.Colors.text
                                                                font.family: Theme.Typography.fontMono
                                                                font.pixelSize: Theme.Typography.sizeXS
                                                            }
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: win.alternaModulo(String(modelData))
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                width: parent.width
                                height: riepilogo.implicitHeight + 28
                                radius: 12
                                color: Theme.Colors.window
                                border.width: 1
                                border.color: Theme.Colors.edgeAccent
                                Column {
                                    id: riepilogo
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 8
                                    Text {
                                        text: "LA TUA RICETTA, IN CHIARO"
                                        color: Theme.Colors.accent
                                        font.pixelSize: Theme.Typography.sizeXS
                                        font.bold: true
                                        font.letterSpacing: 1
                                    }
                                    Text {
                                        text: win.riepilogoRicetta
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        color: Theme.Colors.text
                                        font.pixelSize: Theme.Typography.sizeSM
                                    }
                                    Text {
                                        visible: win.baseConfig === "defconfig"
                                        text: "Attenzione: defconfig parte da opzioni generiche. Lo storico e le scorte aiutano a conservare driver, ma rivedi la ricetta e verifica l’avvio prima di installare."
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        color: Theme.Colors.warning
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                                    Text {
                                        visible: win.sorgente === "cachyos"
                                        text: "La sorgente CachyOS aggiunge patch e configurazioni specifiche: verifica che siano adatte al tuo sistema e confronta i risultati con la base kernel.org."
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        color: Theme.Colors.textMuted
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                                }
                            }
                            Rectangle {
                                width: parent.width
                                height: piano.implicitHeight + 28
                                radius: 12
                                color: Theme.Colors.window
                                border.width: 1
                                border.color: Theme.Colors.edge
                                Column {
                                    id: piano
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 8
                                    Text {
                                        text: "CONTROLLO DEL DAEMON"
                                        color: Theme.Colors.accent
                                        font.pixelSize: Theme.Typography.sizeXS
                                        font.bold: true
                                        font.letterSpacing: 1
                                    }
                                    Text {
                                        visible: win.staCalcolandoRicetta
                                        text: "Verifico versione, toolchain e impostazioni della ricetta…"
                                        color: Theme.Colors.textMuted
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                                    Text {
                                        visible: !win.staCalcolandoRicetta && win.versioneKernel === ""
                                        text: win.sorgente === "cachyos"
                                              ? "Non trovo una versione stabile con patch CachyOS disponibile. " + win.erroreVersioni
                                              : "Non riesco a scegliere una versione stabile. " + win.erroreVersioni
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        color: Theme.Colors.warning
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                                    Text {
                                        visible: !win.staCalcolandoRicetta && win.erroreRicetta !== ""
                                        text: win.erroreRicetta
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        color: Theme.Colors.warning
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                                    Text {
                                        visible: !win.staCalcolandoRicetta && win.ricettaPreview !== null && win.erroreRicetta === ""
                                        text: win.ricettaPreview
                                              ? "Il daemon propone " + String(win.ricettaPreview.rilascio || "il kernel") + ": " + String(win.ricettaPreview.quanti || 0) + " moduli, " + String((win.ricettaPreview.passi || []).length) + " passaggi. Versione stabile più recente compatibile selezionata automaticamente; puoi cambiarla nell'officina."
                                              : ""
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        color: Theme.Colors.text
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                                    Text {
                                        visible: !win.staCalcolandoRicetta && win.ricettaPreview !== null && (win.ricettaPreview.avvisi || []).length === 0
                                        text: "Nessun avviso aggiuntivo dal controllo della ricetta. Verifica comunque l'esito della compilazione e la prova d'avvio prima di installare."
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        color: Theme.Colors.textMuted
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                                    Text {
                                        visible: !win.staCalcolandoRicetta && win.requisitiMancanti().length > 0
                                        text: "Compilazione bloccata: installa prima questi pacchetti con sudo pacman -S --needed " + win.requisitiMancanti().join(" ")
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        color: Theme.Colors.warning
                                        font.pixelSize: Theme.Typography.sizeSM
                                        font.bold: true
                                    }
                                    Repeater {
                                        model: !win.staCalcolandoRicetta && win.ricettaPreview ? (win.ricettaPreview.avvisi || []) : []
                                        delegate: Text {
                                            required property var modelData
                                            text: "• " + String(modelData)
                                            width: piano.width
                                            wrapMode: Text.WordWrap
                                            color: Theme.Colors.warning
                                            font.pixelSize: Theme.Typography.sizeXS
                                        }
                                    }
                                    Text {
                                        visible: !win.staCalcolandoRicetta && win.ricettaPreview === null && win.versioneKernel !== "" && win.erroreRicetta === ""
                                        text: "Attendo il rilievo hardware per calcolare il piano preciso."
                                        color: Theme.Colors.textMuted
                                        font.pixelSize: Theme.Typography.sizeXS
                                    }
                                }
                            }
                        }
                        Rectangle {
                            width: 260
                            height: 42
                            radius: 12
                            color: Theme.Colors.accent
                            Text {
                                anchors.centerIn: parent
                                text: win.pagina === "configura"
                                      ? "Rivedi la compilazione  →"
                                      : "Apri gestione kernel  →"
                                color: Theme.Colors.textOnAccent
                                font.pixelSize: Theme.Typography.sizeXS
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                objectName: "rivediCompilazione"
                                onClicked: win.pagina = win.pagina === "configura" ? "compila" : "kernel"
                            }
                        }
                    }
                }

                Rectangle {
                    visible: win.pagina === "compila"
                    width: parent.width
                    height: compilazioneBox.implicitHeight + 44
                    radius: 20
                    color: Theme.Colors.raised
                    border.width: 1
                    border.color: Theme.Colors.edge
                    Column {
                        id: compilazioneBox
                        anchors.fill: parent
                        anchors.margins: 22
                        spacing: 14
                        Text {
                            text: win.mostraUltimaBuild ? (win.compilando ? "Compilazione in corso" : "Ultima compilazione") : "Ricetta controllata dal daemon"
                            color: Theme.Colors.text
                            font.pixelSize: Theme.Typography.sizeLG
                            font.bold: true
                        }
                        Text {
                            objectName: "nomeRicettaCompilazione"
                            text: win.pianoCompilazione
                                  ? String(win.pianoCompilazione.rilascio || "Kernel") + " · " + String(win.pianoCompilazione.quanti || 0) + " moduli richiesti · " + String((win.pianoCompilazione.passi || []).length) + " passaggi"
                                  : win.mostraUltimaBuild ? "Ricetta non salvata per questo tentativo; consulta il log disponibile."
                                  : "Calcolo della ricetta in corso…"
                            color: Theme.Colors.textMuted
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                        Text {
                            visible: win.erroreCompilazione !== ""
                            text: win.erroreCompilazione
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: Theme.Colors.warning
                            font.pixelSize: Theme.Typography.sizeSM
                        }
                        Text {
                            objectName: "riepilogoCompilazione"
                            visible: win.pianoCompilazione !== null
                            text: win.mostraUltimaBuild ? win.riepilogoEsecuzione : win.riepilogoRicetta
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: Theme.Colors.textMuted
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                        Repeater {
                            model: win.pianoCompilazione && Array.isArray(win.pianoCompilazione.passi)
                                   ? win.pianoCompilazione.passi : []
                            delegate: Rectangle {
                                required property var modelData
                                width: compilazioneBox.width
                                height: 48
                                radius: 9
                                color: Theme.Colors.window
                                border.width: 1
                                border.color: win.passiCompilazione[String(modelData.id)] === "fallito"
                                              ? Theme.Colors.warning : Theme.Colors.edge
                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 10
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 22
                                        text: win.passiCompilazione[String(modelData.id)] === "fatto" ? "✓"
                                              : win.passiCompilazione[String(modelData.id)] === "via" ? "…"
                                              : win.passiCompilazione[String(modelData.id)] === "fallito" ? "!" : "·"
                                        color: win.passiCompilazione[String(modelData.id)] === "fallito"
                                               ? Theme.Colors.warning : Theme.Colors.accent
                                        font.bold: true
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 42
                                        spacing: 3
                                        Text {
                                            width: parent.width
                                            text: String(modelData.titolo || modelData.id)
                                            color: Theme.Colors.text
                                            font.pixelSize: Theme.Typography.sizeXS
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: parent.width
                                            text: String(modelData.spiega || "")
                                            color: Theme.Colors.textMuted
                                            font.pixelSize: Theme.Typography.sizeXS
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                        Rectangle {
                            visible: win.compilando && win.fileAttesi > 0
                            width: parent.width
                            height: 8
                            radius: 4
                            color: Theme.Colors.edge
                            Rectangle {
                                width: parent.width * Math.min(1, win.fileFatti / Math.max(1, win.fileAttesi))
                                height: parent.height
                                radius: 4
                                color: Theme.Colors.accent
                            }
                        }
                        Text {
                            objectName: "statoCompilazione"
                            visible: win.compilando || (win.mostraUltimaBuild && win.esitoCompilazione !== null)
                            text: (win.compilando
                                  ? (win.passoCompilazione || "Preparazione")
                                  : win.esitoCompilazione && win.esitoCompilazione.ok === true
                                    ? "Completato"
                                    : win.esitoCompilazione && win.esitoCompilazione.annullato === true
                                      ? "Interrotta"
                                      : "Non riuscita")
                                  + " · " + win.durataPreparazione(win.secondiCompilazione)
                                  + (win.faseCompilazione === "compila" && win.fileFatti > 0
                                     ? " · " + win.fileFatti + (win.fileAttesi > 0 ? " / " + win.fileAttesi + " file" : " file") : "")
                            color: Theme.Colors.textMuted
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                        Rectangle {
                            width: parent.width
                            height: win.righeCompilazione.length > 0 ? 220 : 56
                            radius: 12
                            color: Theme.Colors.window
                            border.width: 1
                            border.color: Theme.Colors.edge
                            Flickable {
                                anchors.fill: parent
                                anchors.margins: 12
                                clip: true
                                contentWidth: width
                                contentHeight: diarioCompilazione.implicitHeight
                                Text {
                                    id: diarioCompilazione
                                    width: parent.width
                                    text: win.righeCompilazione.length > 0
                                          ? win.righeCompilazione.join("\n")
                                          : "Il diario della compilazione apparirà qui."
                                    textFormat: Text.PlainText
                                    color: Theme.Colors.textMuted
                                    font.family: Theme.Typography.fontMono
                                    font.pixelSize: Theme.Typography.sizeXS
                                    wrapMode: Text.WrapAnywhere
                                }
                            }
                        }
                        Text {
                            objectName: "avvisiCompilazione"
                            visible: win.esitoCompilazione !== null
                                     && Array.isArray(win.esitoCompilazione.avvisi)
                                     && win.esitoCompilazione.avvisi.length > 0
                            width: parent.width
                            text: visible ? "Da controllare:\n• " + win.esitoCompilazione.avvisi.join("\n• ") : ""
                            textFormat: Text.PlainText
                            wrapMode: Text.WrapAnywhere
                            color: Theme.Colors.warning
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                        Rectangle {
                            objectName: "apriLogCompleto"
                            visible: win.logCompilazione !== ""
                            width: 180
                            height: 36
                            radius: 9
                            color: Theme.Colors.raised
                            border.width: 1
                            border.color: Theme.Colors.edge
                            Text { anchors.centerIn: parent; text: "Apri log completo"; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeXS }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.apriLog(win.logCompilazione)
                            }
                        }
                        Row {
                            spacing: 10
                            Rectangle {
                                width: 190
                                height: 42
                                radius: 11
                                color: win.compilando ? Theme.Colors.warning : Theme.Colors.accent
                                opacity: win.compilando || win.mostraUltimaBuild || (win.ricettaPreview && !win.staCalcolandoRicetta && win.requisitiMancanti().length === 0) ? 1 : 0.65
                                Text {
                                    anchors.centerIn: parent
                                    text: win.compilando ? "Ferma compilazione" : win.mostraUltimaBuild ? "Rivedi prossima ricetta" : (win.requisitiMancanti().length > 0 ? "Prerequisiti mancanti" : "Compila questo kernel")
                                    color: Theme.Colors.textOnAccent
                                    font.pixelSize: Theme.Typography.sizeXS
                                    font.bold: true
                                }
                                MouseArea {
                                    objectName: "azioneCompilazione"
                                    anchors.fill: parent
                                    enabled: win.compilando || win.mostraUltimaBuild || (win.ricettaPreview !== null && !win.staCalcolandoRicetta && win.requisitiMancanti().length === 0)
                                    onClicked: {
                                        if (win.compilando) win.fermaCompilazione();
                                        else if (win.mostraUltimaBuild) {
                                            win.mostraUltimaBuild = false;
                                            win.passiCompilazione = ({});
                                        }
                                        else win.confermaCompilazione = true;
                                    }
                                }
                            }
                            Rectangle {
                                visible: win.esitoCompilazione && win.esitoCompilazione.ok === true
                                width: 170
                                height: 42
                                radius: 11
                                color: Theme.Colors.raised
                                border.width: 1
                                border.color: Theme.Colors.accent
                                Text { anchors.centerIn: parent; text: "Kernel disponibili  →"; color: Theme.Colors.text; font.pixelSize: Theme.Typography.sizeXS; font.bold: true }
                                MouseArea { anchors.fill: parent; onClicked: win.pagina = "kernel" }
                            }
                        }
                    }
                }
            }
        }
            Ui.Scorrimento {
                bersaglio: scroll
                sempreVisibile: true
                anchors {
                    right: scroll.right
                    rightMargin: 3
                    top: scroll.top
                    bottom: scroll.bottom
                }
            }
        }
    }

    Rectangle {
        objectName: "confermaOperazioneFucina"
        anchors.fill: parent
        z: 100
        visible: win.popupKernelPronto || win.confermaCompilazione || win.confermaKernel
        color: Theme.Colors.scrim
        MouseArea { anchors.fill: parent }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 470)
            height: popupBox.implicitHeight + 44
            radius: 20
            color: Theme.Colors.lettura
            border.width: 1
            border.color: Theme.Colors.edgeAccent
            Column {
                id: popupBox
                anchors.fill: parent
                anchors.margins: 22
                spacing: 12
                Text {
                    text: win.popupKernelPronto ? "Compilazione completata"
                          : win.confermaCompilazione ? "Avviare la compilazione?"
                          : (win.azioneKernel === "installa" ? "Installare questo kernel?" : "Rimuovere questo kernel?")
                    color: Theme.Colors.text
                    font.pixelSize: Theme.Typography.sizeLG
                    font.bold: true
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: win.popupKernelPronto
                          ? String(win.esitoCompilazione.rilascio || "Il kernel") + " è compilato. "
                            + (win.motivoBloccoKernel("installa", String(win.esitoCompilazione.rilascio || "")) === ""
                               ? "Puoi installarlo ora o ritrovarlo più tardi in Kernel installati. La distribuzione chiederà la password."
                               : "Apri Kernel installati per controllare i prerequisiti e le verifiche prima dell’installazione.")
                          : win.confermaCompilazione
                          ? (win.requisitiMancanti().length > 0
                             ? "Mancano i prerequisiti: " + win.requisitiMancanti().join(", ") + ". Installali prima di avviare la compilazione."
                             : "Fucina userà la ricetta appena verificata. La prima compilazione scarica ed estrae i sorgenti; quelle successive riutilizzano la cache.")
                          : win.azioneKernel === "installa"
                          ? "Fucina installerà " + win.kernelAzione + " con i moduli e aggiornerà il menu di avvio. Il kernel della distribuzione resterà disponibile."
                          : "Fucina rimuoverà " + win.kernelAzione + ". Non è possibile rimuovere il kernel attualmente in uso."
                    color: Theme.Colors.textMuted
                    font.pixelSize: Theme.Typography.sizeSM
                }
                Row {
                    spacing: 10
                    Rectangle {
                        width: 150
                        height: 40
                        radius: 10
                        color: Theme.Colors.raised
                        border.width: 1
                        border.color: Theme.Colors.edge
                        Text {
                            anchors.centerIn: parent
                            text: win.popupKernelPronto ? "Più tardi" : "Annulla"
                            color: Theme.Colors.text
                            font.pixelSize: Theme.Typography.sizeXS
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (win.popupKernelPronto) {
                                    win.popupKernelPronto = false;
                                    win.pagina = "kernel";
                                } else {
                                    win.confermaCompilazione = false;
                                    win.confermaKernel = false;
                                }
                            }
                        }
                    }
                    Rectangle {
                        width: 190
                        height: 40
                        radius: 10
                        color: Theme.Colors.accent
                        Text {
                            anchors.centerIn: parent
                            text: win.popupKernelPronto ? (win.motivoBloccoKernel("installa", String(win.esitoCompilazione.rilascio || "")) === "" ? "Installa adesso" : "Vedi controlli")
                                  : win.confermaCompilazione ? "Avvia compilazione" : "Conferma"
                            color: Theme.Colors.textOnAccent
                            font.pixelSize: Theme.Typography.sizeXS
                            font.bold: true
                        }
                        MouseArea {
                            objectName: "confermaAzioneKernel"
                            anchors.fill: parent
                            enabled: win.popupKernelPronto || (win.confermaCompilazione ? win.requisitiMancanti().length === 0 : win.motivoBloccoKernel(win.azioneKernel, win.kernelAzione) === "")
                            onClicked: {
                                if (win.popupKernelPronto) {
                                    var rilascio = String(win.esitoCompilazione.rilascio || "");
                                    win.popupKernelPronto = false;
                                    if (win.motivoBloccoKernel("installa", rilascio) === "") win.chiediAzioneKernel("installa", rilascio);
                                    else win.pagina = "kernel";
                                } else if (win.confermaCompilazione) {
                                    win.avviaCompilazione();
                                } else {
                                    win.eseguiAzioneKernel();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    readonly property var profiloHardware: win.rilievo && win.rilievo.macchina
                                         ? (win.rilievo.macchina.profilo || null) : null
    readonly property bool profiloAutoFdoPossibile:
        win.profiloHardware !== null && win.profiloHardware.possibile === true
    readonly property bool qemuDisponibile: {
        var attrezzi = win.rilievo && win.rilievo.macchina
                && Array.isArray(win.rilievo.macchina.attrezzi)
                ? win.rilievo.macchina.attrezzi : [];
        return attrezzi.some(function (attrezzo) {
            return attrezzo.nome === "qemu-system-x86" && attrezzo.presente === true;
        });
    }
    readonly property bool supportoNativo:
        win.rilievo !== null && win.rilievo.macchina !== undefined
        && /^v[1-4]$/.test(String(win.rilievo.macchina.livelloX86 || ""))
        && win.rilievo.macchina.flagsCpuUniformi !== false
        && win.rilievo.macchina.flagsCpuCompleti !== false
        && win.versioneSupportaNativo()
    readonly property string riepilogoEsecuzione: {
        var s = win.ricettaCompilazione && win.ricettaCompilazione.scelte ? win.ricettaCompilazione.scelte : {};
        return [
            "Sorgente: " + (s.sorgente === "cachyos" ? "CachyOS" : "kernel.org") + ".",
            "Compilazione: " + (s.compilatore === "clang" ? "Clang" : "GCC") + (s.lto && s.compilatore === "clang" ? " con ThinLTO" : " senza LTO") + ".",
            "AutoFDO: " + (s.profilo ? "profilo di " + s.profilo : s.autofdo ? "preparazione per la raccolta del profilo" : "spento") + ".",
            "Parallelismo: " + (win.ricettaCompilazione && win.ricettaCompilazione.parallelismo ? win.ricettaCompilazione.parallelismo.effettivi + " lavori" : "non registrato nella ricetta precedente") + ".",
            "CPU: " + (s.nativo ? "native" : "target generico") + "; base: " + (s.base === "in-uso" ? "configurazione del kernel in uso alla partenza" : "defconfig") + ".",
            "Scorte: " + (Array.isArray(s.scorte) && s.scorte.length ? s.scorte.join(", ") : "nessuna") + "; prova QEMU " + (s.provaAvvio ? "richiesta" : "non richiesta") + "."
        ].join("\n");
    }

    readonly property string riepilogoRicetta: {
        var cpu = win.rilievo && win.rilievo.macchina
                  ? String(win.rilievo.macchina.livelloX86 || "architettura generica") : "in rilevamento";
        var profilo = win.nomiPresetScelti();
        var lines = [
            "CPU: " + (win.targetNativo ? "ottimizzazione nativa per questo PC" : "target generico") + " (livello rilevato " + cpu + ").",
            "Base: " + (win.baseConfig === "in-uso" ? "configurazione del kernel attuale" : "defconfig generico") + "; uso: " + profilo + ".",
            "Driver candidati scelti: " + (win.moduliAggiunti.length ? win.moduliAggiunti.slice().sort().join(", ") : "nessuno") + ".",
            "Compilazione: " + (win.compilatore === "clang" ? "Clang" : "GCC") + (win.thinLto && win.compilatore === "clang" ? " con ThinLTO" : " senza ThinLTO") + "; AutoFDO " + (win.autoFdo && win.compilatore === "clang" ? "preparazione per raccogliere un profilo dopo l'avvio" : "spento") + ".",
            "Parallelismo: " + (win.parallelismoPreview ? win.parallelismoPreview.effettivi + " lavori, " + (win.parallelismoPreview.automatico ? "automatici" : "limite manuale") : "in verifica") + ".",
            "Sorgente: " + (win.sorgente === "cachyos" ? "CachyOS" : "kernel.org") + "; " + (win.rilievo ? String(win.rilievo.dispositiviStorici || 0) : "0") + " identificatori hardware nello storico."
        ];
        return lines.join("\n");
    }
}

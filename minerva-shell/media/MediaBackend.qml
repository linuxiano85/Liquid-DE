import QtQuick
import Quickshell.Io
import "../core" as Core

// MediaBackend — I comandi di Minerva Media.
//
// Tutte le operazioni pesanti (ricerca, download, onde, tagli) sono comandi
// esterni lanciati come processi: `yt-dlp` per la rete, `ffmpeg` e `ffprobe`
// per l'audio. Il QML non tocca file né reti: ordina e ascolta.
//
// I valori che arrivano da fuori — un titolo di ricerca, un indirizzo, un
// percorso — passano SEMPRE come argomenti (`sh -c RIGA sh $1 $2 …`) e mai
// incollati nella riga: un percorso con un apice o un backtick non deve poter
// diventare un pezzo di comando. È la regola di `core/Exec.qml`, e qui vale
// doppia perché un titolo di YouTube è testo di chiunque.
Item {
    id: backend
    visible: false

    // ── Segnali ───────────────────────────────────────────────────────────

    /// I risultati di una ricerca: un elenco di { id, titolo, durata,
    /// canale, url, miniatura }.
    signal resultsReady(var risultati)
    /// Un messaggio di stato durante un download.
    signal downloadStatus(string messaggio)
    signal downloadFinished(string percorso, string titolo)
    /// Gli altri file di un lavoro con più brani (una playlist): `quanti` è il totale.
    signal altriScaricati(var percorsi, string titolo, int quanti)
    signal downloadError(string messaggio)
    /// `percorso` è il PNG dell'onda, `durata` i secondi del file.
    signal waveformReady(string percorso, real durata)
    signal waveformError(string messaggio)
    signal trimFinished(string percorso)
    signal trimError(string messaggio)
    /// `playlist` dice se l'elenco era quello della cartella dei download.
    signal elencoPronto(var file, bool playlist)
    signal elencoError(string messaggio)

    /// La cartella dove finiscono i download.
    readonly property string cartella: "$HOME/Musica/Minerva_YT"

    /// L'ultimo errore di stderr, per i messaggi da mostrare.
    property string ultimoErrore: ""

    property bool cercando: false
    readonly property bool scaricando: lavori.some(function(l) { return l.stato === "in_coda" || l.stato === "in_corso"; })
    readonly property bool lavorando: ondaProc.running
                                      || tagliaProc.running
                                      || backend._leggendoPlaylist
                                      || listaProc.running

    property var lavori: []
    property var elencoMedia: ({})
    property bool _aggiungiPagina: false
    function altriElementi() {
        if(cercando || !elencoMedia.paginaPiena || !elencoMedia.url) return;
        _aggiungiPagina=true;
        _ricercaId=Core.Ipc.mediaRichiesta("media_cerca",{"testo":elencoMedia.url,"inizio":elencoMedia.prossimo});
        cercando=_ricercaId!=="";
    }
    function scaricaSelezione(indici, video, formato, altezza) {
        if(!indici.length || elencoMedia.tipo!=="playlist") return;
        _scarica(elencoMedia.url,!video,true,formato,altezza,indici);
    }
    property string _ricercaId: ""
    property string _libreriaId: ""
    property bool _playlistPending: false
    property bool _leggendoPlaylist: false
    property var _richiesteDownload: ({})
    property var _annunciati: ({})
    readonly property bool _italiano: Core.Strings.lang === "it"

    function _errore(code) {
        var pairs = {
            "missing-ytdlp":["Installa yt-dlp per cercare e scaricare.","Install yt-dlp to search and download."],
            "search-busy":["Ci sono già due ricerche in corso.","Two searches are already running."],
            "search-timeout":["La ricerca ha impiegato troppo tempo.","The search took too long."],
            "search-output-limit":["La risposta della ricerca è troppo grande.","The search response is too large."],
            "invalid-request":["Richiesta non valida.","Invalid request."],
            "media-storage-error":["La cartella di destinazione non è disponibile.","The destination folder is unavailable."]
        };
        var text = pairs[code];
        return text ? text[backend._italiano ? 0:1] :
            (backend._italiano ? "Operazione Media non riuscita. Riprova." : "Media operation failed. Try again.");
    }
    function cerca(testo, quante, playlist) {
        if (!String(testo || "").trim()) return;
        backend._aggiungiPagina=false;
        backend._ricercaId = Core.Ipc.mediaRichiesta("media_cerca",{"testo":String(testo),"quanti":Math.max(1,Math.min(50,Math.round(quante)||20)),"playlist":playlist===true});
        backend.cercando = backend._ricercaId !== "";
        if (!backend.cercando) backend.resultsReady([]);
    }
    function scaricaAudio(url, playlist, formato) {
        backend._scarica(url,true,playlist === true,formato || "mp3",0);
    }
    function scaricaVideo(url, playlist, altezza) {
        backend._scarica(url,false,playlist === true,"mp3",altezza || 0);
    }
    function _scarica(url,audio,playlist,formato,altezza,selezione) {
        var id = Core.Ipc.mediaRichiesta("media_scarica",{
            "url":String(url || "").trim(),"audio":audio,"playlist":playlist,
            "formato":formato,"altezza":altezza,"selezione":selezione===undefined ? null : selezione
        });
        if (!id) { backend.downloadError(backend._italiano ? "Demone non connesso." : "Daemon disconnected."); return; }
        var pending = Object.assign({},backend._richiesteDownload); pending[id]=true;
        backend._richiesteDownload=pending;
        backend.downloadStatus(backend._italiano ? "Download in coda…" : "Download queued…");
    }
    function annulla(id) { Core.Ipc.mediaRichiesta("media_annulla",{"job":id}); }
    function pulisciLavori() { Core.Ipc.mediaRichiesta("media_pulisci",{}); }
    function aggiornaLavori() { Core.Ipc.mediaRichiesta("media_lavori",{}); }
    function _lavoro(job, announce) {
        var items=backend.lavori.slice(), found=false;
        for(var i=0;i<items.length;i++) if(items[i].id===job.id) { items[i]=job;found=true;break; }
        if(!found) items.push(job);
        backend.lavori=items;
        if (!announce || backend._annunciati[job.id]) return;
        if(job.stato === "fatto" || job.stato === "parziale" || job.stato === "errore" || job.stato === "annullato") {
            var done=Object.assign({},backend._annunciati);done[job.id]=true;backend._annunciati=done;
            if(job.stato === "errore") backend.downloadError(job.errore || backend._errore("download-failed"));
            else if(job.fatti && job.fatti.length) {
                // Una playlist finisce con tanti file: arrivava solo il primo,
                // e nella scaletta del Player compariva un brano su otto
                // (19 ottobre). Gli altri arrivano dopo, tutti insieme.
                backend.downloadFinished(job.fatti[0],job.titolo || job.corrente);
                if(job.fatti.length>1) backend.altriScaricati(job.fatti.slice(1),job.titolo || "",job.fatti.length);
            }
        } else if(job.stato === "in_corso") {
            var progress=job.totale>0 ? Math.min(100,Math.round(100*job.scaricati/job.totale))+"%" : "…";
            backend.downloadStatus((job.corrente || job.titolo || (backend._italiano?"Scaricamento":"Downloading"))+" · "+progress);
        }
    }
    Connections {
        target:Core.Ipc
        function onMediaRisposta(payload) {
            if(payload.azione === "media_libreria" && payload.request===backend._libreriaId) {
                backend._leggendoPlaylist=false;
                if(payload.error) backend.elencoError(backend._errore(payload.error));
                else backend.elencoPronto(payload.files || [],true);
            }
            if(payload.azione === "media_cerca" && payload.request===backend._ricercaId) {
                backend.cercando=false;
                backend.ultimoErrore=payload.error ? backend._errore(payload.error):"";
                if(payload.error && backend._aggiungiPagina) return;
                var previous=backend._aggiungiPagina ? (backend.elencoMedia.voci || []) : [];
                var merged=previous.slice(), seen=({});
                for(var j=0;j<merged.length;j++) seen[merged[j].indice]=true;
                var incoming=payload.voci || [];
                for(var k=0;k<incoming.length;k++) {
                    if(!backend._aggiungiPagina || !seen[incoming[k].indice]) merged.push(incoming[k]);
                }
                // A watch URL with list=... must keep its playlist identity.
                var info=Object.assign({},payload,{"voci":merged});
                if(info.tipo==="playlist" && !info.url) info.url=backend.elencoMedia.url || "";
                backend.elencoMedia=info;
                backend.resultsReady(merged);
            }
            if(backend._richiesteDownload[payload.request]) {
                var pending=Object.assign({},backend._richiesteDownload);delete pending[payload.request];backend._richiesteDownload=pending;
                if(payload.error) backend.downloadError(backend._errore(payload.error));
            }
            if(payload.lavori) {
                for(var i=0;i<payload.lavori.length;i++) backend._lavoro(payload.lavori[i],false);
            }
        }
        function onMediaLavoro(payload) {
            if(payload.tipo==="elenco") backend.lavori=payload.lavori || [];
            else if(payload.lavoro) backend._lavoro(payload.lavoro,true);
        }
        function onConnectedChanged() {
            if(Core.Ipc.connected) {
                backend.aggiornaLavori();
                if(backend._playlistPending)backend.elencoPlaylist();
                return;
            }
            backend.cercando=false;
            backend._playlistPending = backend._playlistPending || backend._leggendoPlaylist;
            backend._leggendoPlaylist=false;
            backend._ricercaId="";
            var jobs=backend.lavori.map(function(job){return Object.assign({},job,{"stale":true});});
            backend.lavori=jobs;
            if(Object.keys(backend._richiesteDownload).length) {
                backend._richiesteDownload=({});
                backend.downloadError(backend._italiano ? "Connessione interrotta: verifica la coda dopo la riconnessione." : "Connection lost: check the queue after reconnecting.");
            }
        }
    }
    Component.onCompleted: if(Core.Ipc.connected)backend.aggiornaLavori()

    // ── L'onda e la durata ────────────────────────────────────────────────

    /// Genera il PNG dell'onda con `showwavespic` e in più legge la durata
    /// con `ffprobe`: servono tutte e due al trimmer, e girano in un comando
    /// solo. Il PNG finisce nella cache di Liquid DE, sotto `media/`.
    function ondaDi(percorso, larghezza, altezza, colore) {
        var p = String(percorso || "");
        if (p === "")
            return;
        var w = Math.max(320, Math.round(larghezza || 960));
        var h = Math.max(120, Math.round(altezza || 240));
        // La cartella arriva come argomento ($2) e non dentro la riga: un
        // percorso con uno spazio non deve poterla spezzare.
        var cartella = Core.Ipc.cartellaCache + "/media";
        var tmp = "$2/onda-" + String(Date.now()) + ".png";
        ondaProc.command = ["sh", "-c",
            'mkdir -p "$2" '
            + '&& d=$(ffprobe -v error -show_entries format=duration '
            + '-of default=noprint_wrappers=1:nokey=1 -- "$1" 2>/dev/null) '
            + '&& ffmpeg -y -v error -i "$1" -filter_complex '
            + '"[0:a]showwavespic=s='
            + w + "x" + h + ':colors=0x' + backend._hex(colore) + '" '
            + '-frames:v 1 -f image2 "' + tmp + '" >/dev/null 2>&1 '
            + '&& printf "%s\\n%s\\n" "${d:-0}" "' + tmp + '"',
            "sh", p, cartella];
        ondaProc.running = true;
    }

    /// Un colore Qt in `RRGGBB`, che è quello che vuole `showwavespic`.
    function _hex(colore) {
        // Solo cifre esadecimali: questo valore finisce dentro la riga di
        // `-filter_complex`, cioè dentro una riga di shell.
        var s = String(colore.toString()).replace(/[^0-9a-fA-F]/g, "");
        s = s.slice(-6).toUpperCase();
        return s.length === 6 ? s : "FFFFFF";
    }

    function _ondaFinito(uscita) {
        var righe = String(uscita || "").split("\n");
        var durata = parseFloat(righe[0] || "0") || 0;
        var percorso = (righe[righe.length - 1] || "").trim();
        if (!percorso) {
            backend.waveformError("Non riesco a disegnare l'onda.");
            return;
        }
        backend.waveformReady(percorso, durata);
    }

    Process {
        id: ondaProc
        stdout: StdioCollector {
            onStreamFinished: backend._ondaFinito(text)
        }
        stderr: StdioCollector {
            onStreamFinished: backend.ultimoErrore = text.trim()
        }
        onExited: function (code) {
            if (code !== 0)
                backend.waveformError(
                    backend.ultimoErrore || "Non riesco a disegnare l'onda.");
        }
    }

    // ── Il taglio ─────────────────────────────────────────────────────────

    /// Taglia `inizio`–`fine` (secondi) di `percorso` e salva un mp3 in
    /// `~/Musica/Minerva_YT/tagli`, con dissolvenze all'inizio e alla fine.
    ///
    /// `-ss` prima di `-i` cerca alla svelta e `-t` conta da lì in poi:
    /// funziona allo stesso modo su qualunque ffmpeg, senza dipendere da
    /// come ogni versione intende `-to`.
    function taglia(percorso, inizio, fine, fadeIn, fadeOut) {
        var p = String(percorso || "");
        if (p === "") {
            backend.trimError("Nessun file da tagliare.");
            return;
        }
        if (!(inizio >= 0) || !(fine > inizio)) {
            backend.trimError("Selezione non valida.");
            return;
        }
        var durata = fine - inizio;
        var fi = Math.max(0, Math.min(fadeIn || 0, durata / 2));
        var fo = Math.max(0, Math.min(fadeOut || 0, durata / 2));
        var st = Math.max(0, durata - fo);
        // ── Solo il NOME, non il percorso ────────────────────────────────
        //
        // Qui si passava `"$HOME/Musica/…/nome.mp3"` come argomento, e un
        // argomento **non viene espanso**: la shell lo consegna a `ffmpeg`
        // così com'è, con le cinque lettere «$HOME» dentro. La cartella
        // letterale non esiste, `ffmpeg` non scrive niente, il `printf` non si
        // raggiunge — e il taglio falliva sempre, in silenzio.
        //
        // Il percorso si compone dentro lo script, dove `$HOME` è una
        // variabile per davvero; il nome del file, che viene dal titolo di un
        // brano e quindi da fuori, resta un argomento e non entra mai nella
        // riga di shell.
        var nome = backend._nomeTagliato(p, inizio, fine);
        tagliaProc.command = ["sh", "-c",
            'c="$HOME/Musica/Minerva_YT/tagli" && mkdir -p "$c" '
            + '&& ffmpeg -y -v error -ss "$2" -i "$1" -t "$3" '
            + '-af "afade=t=in:st=0:d=$4,afade=t=out:st=$5:d=$6" '
            + '-c:a libmp3lame -q:a 2 "$c/$7" >/dev/null 2>&1 '
            + '&& printf "%s\\n" "$c/$7"',
            "sh", p, String(inizio), String(durata),
            String(fi), String(st), String(fo), nome];
        tagliaProc.running = true;
    }

    function _nomeTagliato(percorso, inizio, fine) {
        var base = String(percorso).split("/").pop();
        base = base.replace(/\.[^.]+$/, "");
        // Il nome viene dal titolo di un brano, cioè da fuori. Nel percorso ci
        // entra come `"$c/$7"`, quindi una barra dentro sposterebbe il file in
        // un'altra cartella — e `..` lo porterebbe fuori da `Musica`.
        base = base.replace(/[\/\x00]/g, "_");
        if (base === "" || base === "." || base === "..")
            base = "taglio";
        function t(s) {
            s = Math.max(0, Math.round(s));
            return Math.floor(s / 60) + "-" + String(s % 60).padStart(2, "0");
        }
        return base + "__" + t(inizio) + "_" + t(fine) + ".mp3";
    }

    Process {
        id: tagliaProc
        stdout: StdioCollector {
            onStreamFinished: backend.trimFinished(text.trim())
        }
        stderr: StdioCollector {
            onStreamFinished: backend.ultimoErrore = text.trim()
        }
        onExited: function (code) {
            if (code !== 0)
                backend.trimError(
                    backend.ultimoErrore || "Il taglio è fallito.");
        }
    }

    // ── Gli elenchi ───────────────────────────────────────────────────────

    /// I file della cartella dei download, con il percorso intero.
    function elencoPlaylist() {
        backend._libreriaId=Core.Ipc.mediaRichiesta("media_libreria",{});
        backend._playlistPending=backend._libreriaId === "";
        backend._leggendoPlaylist=!backend._playlistPending;
    }

    /// I file di una cartella qualunque, per la pagina Esplora.
    function elencoCartella(dir) {
        var d = String(dir || "").trim();
        if (d === "")
            return;
        backend._perLaPlaylist = false;
        listaProc.command = ["sh", "-c",
            'for f in "$1"/*; do [ -f "$f" ] || continue; '
            + 'case "$f" in "$1"/.*) continue;; esac; '
            + 'printf "%s\\n" "$f"; done',
            "sh", d];
        listaProc.running = true;
    }

    property bool _perLaPlaylist: false

    function _elencoFinito(uscita) {
        var out = [];
        var righe = String(uscita || "").split("\n");
        for (var i = 0; i < righe.length; i++) {
            var r = righe[i].trim();
            if (r)
                out.push(r);
        }
        backend.elencoPronto(out, backend._perLaPlaylist);
    }


    Process {
        id: listaProc
        stdout: StdioCollector {
            onStreamFinished: backend._elencoFinito(text)
        }
        stderr: StdioCollector {
            onStreamFinished: backend.ultimoErrore = text.trim()
        }
        onExited: function (code) {
            if (code !== 0)
                backend.elencoError(backend.ultimoErrore || "");
        }
    }
}
import QtQuick
import Quickshell.Io

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
    signal downloadError(string messaggio)
    /// `percorso` è il PNG dell'onda, `durata` i secondi del file.
    signal waveformReady(string percorso, real durata)
    signal waveformError(string messaggio)
    signal trimFinished(string percorso)
    signal trimError(string messaggio)
    /// `playlist` dice se l'elenco era quello della cartella dei download.
    signal elencoPronto(var file, bool playlist)
    signal elencoError(string messaggio)
    signal durataPronta(real secondi)

    /// La cartella dove finiscono i download.
    readonly property string cartella: "$HOME/Musica/Minerva_YT"

    /// L'ultimo errore di stderr, per i messaggi da mostrare.
    property string ultimoErrore: ""

    readonly property bool cercando: ricercaProc.running
    readonly property bool scaricando: scaricaProc.running
    readonly property bool lavorando: ondaProc.running
                                      || tagliaProc.running
                                      || elencoProc.running
                                      || listaProc.running

    // ── Ricerca ───────────────────────────────────────────────────────────

    function cerca(testo, quante) {
        var q = String(testo || "").trim();
        if (q === "")
            return;
        // Un intero, non «quello che è arrivato»: `n` finisce DENTRO la riga
        // di shell (`ytsearchN:`), ed è l'unico valore di questo file che ci
        // finisce senza essere un argomento.
        var n = String(Math.max(1, Math.min(50, Math.round(quante) || 5)));
        ricercaProc.command = ["sh", "-c",
            'yt-dlp -q --no-warnings --flat-playlist --dump-json '
            + '-- "ytsearch' + n + ':$1"',
            "sh", q];
        ricercaProc.running = true;
    }

    function _risultatiDa(uscita) {
        var out = [];
        var righe = String(uscita || "").split("\n");
        for (var i = 0; i < righe.length; i++) {
            var riga = righe[i].trim();
            if (!riga)
                continue;
            var j;
            try {
                j = JSON.parse(riga);
            } catch (e) {
                continue;
            }
            if (!j || !j.title)
                continue;
            out.push({
                id: j.id || "",
                titolo: String(j.title),
                durata: Number(j.duration || 0),
                canale: String(j.channel || ""),
                url: String(j.url || j.webpage_url || ""),
                miniatura: j.id
                            ? "https://img.youtube.com/vi/" + j.id + "/mqdefault.jpg"
                            : ""
            });
        }
        backend.resultsReady(out);
    }

    Process {
        id: ricercaProc
        stdout: StdioCollector {
            onStreamFinished: backend._risultatiDa(text)
        }
        stderr: StdioCollector {
            onStreamFinished: backend.ultimoErrore = text.trim()
        }
        onExited: function (code) {
            if (code !== 0)
                backend.resultsReady([]);
        }
    }

    // ── Download ──────────────────────────────────────────────────────────

    /// Audio soltanto: mp3 a 192 kbps. È il formato dei telefoni.
    function scaricaAudio(url) {
        backend._scarica(
            'yt-dlp -q --no-progress -x --audio-format mp3 '
            + '--audio-quality 192 --no-playlist --no-warnings '
            + '--print "%(title)s" --print "after_move:filepath" '
            + '-o "$HOME/Musica/Minerva_YT/%(title)s.%(ext)s" -- "$1"',
            url, "Scarico l'audio…");
    }

    /// Il video migliore con audio, in mp4.
    function scaricaVideo(url) {
        backend._scarica(
            'yt-dlp -q --no-progress '
            + '-f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" '
            + '--merge-output-format mp4 --no-playlist --no-warnings '
            + '--print "%(title)s" --print "after_move:filepath" '
            + '-o "$HOME/Musica/Minerva_YT/%(title)s.%(ext)s" -- "$1"',
            url, "Scarico il video…");
    }

    function _scarica(riga, url, stato) {
        if (backend.scaricando)
            return;
        var u = String(url || "").trim();
        if (u === "") {
            backend.downloadError("Nessun indirizzo da scaricare.");
            return;
        }
        backend.ultimoErrore = "";
        backend._downloadOk = false;
        backend.downloadStatus(stato);
        scaricaProc.command = ["sh", "-c", riga, "sh", u];
        scaricaProc.running = true;
    }

    property bool _downloadOk: false

    function _downloadFinito(uscita) {
        var righe = String(uscita || "").split("\n");
        var titolo = (righe[0] || "").trim();
        var percorso = (righe[righe.length - 1] || "").trim();
        if (!percorso)
            return;
        backend._downloadOk = true;
        backend.downloadFinished(percorso, titolo);
    }

    Process {
        id: scaricaProc
        stdout: StdioCollector {
            onStreamFinished: backend._downloadFinito(text)
        }
        stderr: StdioCollector {
            onStreamFinished: backend.ultimoErrore = text.trim()
        }
        onExited: function (code) {
            if (code !== 0)
                backend.downloadError(
                    backend.ultimoErrore || "Il download è fallito.");
            else if (!backend._downloadOk)
                backend.downloadError("Il download è fallito.");
        }
    }

    // ── L'onda e la durata ────────────────────────────────────────────────

    /// Genera il PNG dell'onda con `showwavespic` e in più legge la durata
    /// con `ffprobe`: servono tutte e due al trimmer, e girano in un comando
    /// solo. Il PNG finisce in `~/.cache/minerva-media`.
    function ondaDi(percorso, larghezza, altezza, colore) {
        var p = String(percorso || "");
        if (p === "")
            return;
        var w = Math.max(320, Math.round(larghezza || 960));
        var h = Math.max(120, Math.round(altezza || 240));
        var tmp = "$HOME/.cache/minerva-media/onda-"
                  + String(Date.now()) + ".png";
        ondaProc.command = ["sh", "-c",
            'mkdir -p "$HOME/.cache/minerva-media" '
            + '&& d=$(ffprobe -v error -show_entries format=duration '
            + '-of default=noprint_wrappers=1:nokey=1 -- "$1" 2>/dev/null) '
            + '&& ffmpeg -y -v error -i "$1" -filter_complex '
            + '"[0:a]showwavespic=s='
            + w + "x" + h + ':colors=0x' + backend._hex(colore) + '" '
            + '-frames:v 1 -f image2 "' + tmp + '" >/dev/null 2>&1 '
            + '&& printf "%s\\n%s\\n" "${d:-0}" "' + tmp + '"',
            "sh", p];
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

    /// La durata di un file, in secondi. Per i file locali che non hanno
    /// ancora un'onda.
    function durataDi(percorso) {
        durataProc.command = ["sh", "-c",
            'ffprobe -v error -show_entries format=duration '
            + '-of default=noprint_wrappers=1:nokey=1 -- "$1" 2>/dev/null',
            "sh", String(percorso || "")];
        durataProc.running = true;
    }

    Process {
        id: durataProc
        stdout: StdioCollector {
            onStreamFinished: backend.durataPronta(parseFloat(text.trim()) || 0)
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
        backend._perLaPlaylist = true;
        elencoProc.command = ["sh", "-c",
            'mkdir -p "$HOME/Musica/Minerva_YT" '
            + '&& for f in "$HOME/Musica/Minerva_YT"/*; do '
            + '[ -f "$f" ] || continue; '
            + 'case "$f" in "$HOME/Musica/Minerva_YT"/.*) continue;; esac; '
            + 'printf "%s\\n" "$f"; done',
            "sh"];
        elencoProc.running = true;
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
        id: elencoProc
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
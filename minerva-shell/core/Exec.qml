import QtQuick
import Quickshell.Io

// Exec — Un comando da lanciare e una risposta da aspettare.
//
// Le impostazioni di sistema non hanno un'API: si parlano con `hyprctl`,
// `pactl`, `nmcli`, `powerprofilesctl`. Ognuno va lanciato, aspettato e letto,
// e farlo a mano ogni volta significa ripetere lo stesso `Process` con lo
// stesso `StdioCollector` in venti punti diversi.
//
//     Exec { id: monitors; onDone: function(out) { ... } }
//     ...
//     monitors.start(["hyprctl", "-j", "monitors"])
//
// `done` arriva SEMPRE, anche quando il comando fallisce: chi chiama deve
// poter distinguere «ha risposto vuoto» da «non ha risposto», e un segnale che
// a volte non arriva lascia l'interfaccia in attesa per sempre.
Item {
    id: exec

    // Non è roba da vedere: dichiarato dentro una colonna occuperebbe comunque
    // il proprio posto in fila, e la pagina si ritroverebbe buchi larghi
    // quanto la spaziatura per ogni comando che sa lanciare.
    visible: false

    /// Uscita del comando, senza spazi ai bordi.
    signal done(string output)
    signal completed(int exitCode, string output, string error)
    property int timeoutMs: 30000
    property int exitCode: 0
    property string error: ""
    property bool _active: false
    property int _generation: 0
    property var _queue: []
    property string _output: ""
    property string _stderr: ""
    /// Vero mentre il comando è in corso.
    readonly property bool busy: _active || _queue.length > 0

    /// Ultimo comando lanciato, utile nei log quando qualcosa non torna.
    property var lastCommand: []

    function start(argv) {
        exec._accoda(argv, null);
    }

    /// Come `start`, ma `testo` va sullo STDIN del comando e non fra gli
    /// argomenti.
    ///
    /// ── Perché serve ─────────────────────────────────────────────────────
    ///
    /// Gli argomenti di un processo si leggono in `/proc/<pid>/cmdline`, da
    /// chiunque sul computer e per tutto il tempo in cui il comando gira. La
    /// password del Wi-Fi passava così a `nmcli --wait 45`: fino a
    /// quarantacinque secondi in vista. Trovato in revisione il 30 settembre
    /// 2026. Qui il testo non tocca mai la riga di comando: lo scrive il
    /// `Process` appena il comando è partito, e poi chiude il canale.
    function startConIngresso(argv, testo) {
        exec._accoda(argv, String(testo));
    }

    function _accoda(argv, ingresso) {
        if (!argv || argv.length === 0)
            return;
        exec._queue = exec._queue.concat([{ "argv": exec._stringhe(argv),
                                            "ingresso": ingresso }]);
        exec._next();
    }

    /// Quel che va scritto sullo stdin del comando in corso, fino a quando
    /// non è partito.
    property var _ingresso: null

    function _next() {
        if (exec._active || proc.running || exec._queue.length === 0) return;
        var queue = exec._queue.slice();
        var voce = queue.shift();
        var argv = voce.argv;
        exec._queue = queue;
        exec._ingresso = voce.ingresso;
        proc.stdinEnabled = voce.ingresso !== null;
        exec._active = true;
        exec._generation++;
        exec._output = "";
        exec._stderr = "";
        exec.error = "";
        exec.exitCode = -1;
        exec.lastCommand = argv;
        proc.command = argv;
        proc.running = true;
        deadline.restart();
        failedStart.restart();
    }

    function _finish(generation) {
        if (!exec._active || generation !== exec._generation) return;
        deadline.stop();
        failedStart.stop();
        exec._active = false;
        exec._ingresso = null;
        if (exec.exitCode !== 0 && exec.error === "") exec.error = exec._stderr;
        exec.completed(exec.exitCode, exec._output, exec.error);
        exec.done(exec._output);
        Qt.callLater(exec._next);
    }

    /// Comodo per le righe di shell con pipe e simili.
    ///
    /// La riga la scrive il programma: NON ci si infila mai dentro un valore
    /// che arriva da fuori — un nome di file, un SSID, un indirizzo. Per
    /// quelli c'è `shArgs`, e il perché è scritto lì.
    function sh(line) {
        exec.start(["sh", "-c", line]);
    }

    /// Come `sh`, ma i valori che vengono da fuori si passano A PARTE.
    ///
    ///     shArgs('printf %s "$1" | wl-copy', [percorso])
    ///
    /// `sh -c RIGA nome arg1 arg2 …` mette `arg1` in `$1`, e la shell non lo
    /// rilegge MAI come codice: dentro le virgolette `"$1"` non c'è più niente
    /// da espandere. Incollarlo nella riga invece — anche fra virgolette
    /// doppie, anche passando per `JSON.stringify` — lascia vivi `` ` `` e
    /// `$( )`: un file chiamato ``foto`comando`.png`` ESEGUE quel comando
    /// appena qualcuno ne copia il percorso. Provato, non temuto.
    ///
    /// Il primo argomento in più è il nome del processo (`$0`), che `sh`
    /// pretende: senza, il primo valore vero finirebbe lì e `$1` sarebbe
    /// vuoto.
    function shArgs(line, args) {
        exec.start(["sh", "-c", line, "sh"].concat(exec._stringhe(args)));
    }

    function fireShArgs(line, args) {
        exec.fire(["sh", "-c", line, "sh"].concat(exec._stringhe(args)));
    }

    /// `Process.command` vuole stringhe: un numero passato così com'è fa
    /// fallire il comando in silenzio.
    function _stringhe(args) {
        var out = [];
        for (var i = 0; i < (args || []).length; i++)
            out.push(String(args[i]));
        return out;
    }

    /// Lancia e basta, senza aspettare risposta: per i comandi che cambiano
    /// qualcosa e non hanno niente da dire.
    ///
    /// ── Uno alla volta, ma nessuno perso ─────────────────────────────────
    ///
    /// Il `Process` qui sotto è uno solo, e dargli `running = true` mentre
    /// gira non fa niente: il comando nuovo restava in `command` e non partiva
    /// mai. Scegliere «Risparmio» e subito dopo «Prestazioni» (lo script di
    /// `powerprofilesctl` ci mette un paio di decimi) lasciava la macchina in
    /// risparmio con l'interfaccia che diceva prestazioni. Trovato in
    /// revisione il 30 settembre 2026: adesso chi arriva mentre il precedente
    /// gira aspetta il suo turno.
    property var _daLanciare: []

    function fire(argv) {
        if (!argv || argv.length === 0)
            return;
        exec._daLanciare = exec._daLanciare.concat([exec._stringhe(argv)]);
        exec._lanciaProssimo();
    }

    function _lanciaProssimo() {
        if (fireProc.running || exec._daLanciare.length === 0)
            return;
        var fila = exec._daLanciare.slice();
        fireProc.command = fila.shift();
        exec._daLanciare = fila;
        fireProc.running = true;
    }

    function fireSh(line) {
        exec.fire(["sh", "-c", line]);
    }

    Process {
        id: proc
        onStarted: {
            if (exec._ingresso === null)
                return;
            proc.write(exec._ingresso);
            exec._ingresso = null;
            // Chiuso dopo la scrittura (Qt spedisce prima quel che aspetta):
            // chi legge fino alla fine del file non resta appeso.
            proc.stdinEnabled = false;
        }
        stdout: StdioCollector {
            onStreamFinished: exec._output = text.trim()
        }
        stderr: StdioCollector { onStreamFinished: exec._stderr = text.trim() }
        onExited: function(code) {
            exec.exitCode = code;
            var generation = exec._generation;
            Qt.callLater(function() { exec._finish(generation); });
        }
    }

    Timer {
        id: failedStart
        interval: 25
        onTriggered: {
            if (exec._active && !proc.running) {
                exec.error = "Avvio del comando fallito";
                exec._finish(exec._generation);
            }
        }
    }
    Timer {
        id: deadline
        interval: Math.max(1, exec.timeoutMs)
        onTriggered: {
            exec.error = "Tempo massimo del comando superato";
            proc.signal(9);
            if (!proc.running) exec._finish(exec._generation);
        }
    }

    Process {
        id: fireProc
        // Su `running` e non su `exited`: un comando che non riesce nemmeno a
        // partire non «esce», e la fila resterebbe ferma dietro di lui.
        onRunningChanged: if (!fireProc.running) Qt.callLater(exec._lanciaProssimo)
    }
}

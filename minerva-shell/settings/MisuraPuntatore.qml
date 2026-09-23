import QtQuick
import "../core" as Core
import "." as S

// MisuraPuntatore — Quanto è grande il puntatore.
//
// ── Perché è un pezzo a sé ───────────────────────────────────────────────
//
// Sta in DUE pagine, e apposta:
//
//  · in «Accessibilità», perché un puntatore grande è una delle prime cose
//    che si cerca quando non lo si trova sullo schermo;
//  · in «Tastiera e mouse › Puntatore», perché è lì che ci si aspetta ogni
//    cosa che riguardi il mouse.
//
// Giacomo, 5 settembre 2026: «voglio anche un'impostazione per selezionare la
// grandezza del puntatore». C'era già — in «Accessibilità» — e nessuno la
// cercava lì. È lo stesso ragionamento che questa stessa pagina si è già
// scritta per le animazioni: «non è un doppione: là è una comodità fra le
// altre, qui è il posto dove la cerca chi ha bisogno di spegnerla».
//
// Doppia sì, copiata no: se le due copie divergono, una delle due mente. Qui
// la scelta è una sola, e il pezzo delicato — il nome del tema — sta scritto
// in un posto solo.
Item {
    id: misura

    readonly property bool it: Core.Strings.lang === "it"
    readonly property int valore: Core.Ipc.get("accessibility.cursorSize", 24)

    // La larghezza la dà il riquadro che ci contiene — `controlWidth` di
    // `SettingRow`. Legarla a `picker.implicitWidth` era un anello: il Flow
    // decide dove andare a capo guardando la propria larghezza, e la propria
    // larghezza veniva da quanto era largo lui. Risultato, le tre voci una
    // sotto l'altra.
    width: parent ? parent.width : picker.implicitWidth
    implicitHeight: picker.implicitHeight

    /// Serve a una cosa sola: trovare il nome del tema di puntatori. Ad
    /// applicarlo poi ci pensa `Core.Compositore.cursore`, che vuole tema e
    /// misura INSIEME — il gestore dei cursori si crea con tutti e due, e non
    /// c'è modo di cambiarne uno lasciando l'altro.
    Core.Exec {
        id: comando
        property int misura: 24
        onDone: function (tema) {
            var t = String(tema).trim();
            if (t !== "")
                Core.Compositore.cursore(t, comando.misura);
        }
    }

    S.ChoicePicker {
        id: picker
        width: misura.width
        value: String(misura.valore)
        options: [
            { "value": "24", "label": misura.it ? "Normale" : "Normal" },
            { "value": "32", "label": misura.it ? "Grande" : "Large" },
            { "value": "48", "label": misura.it ? "Molto grande" : "Very large" }
        ]
        onPicked: function (v) {
            Core.Ipc.setSetting("accessibility.cursorSize", parseInt(v));
            comando.misura = parseInt(v);
            // ── Il TEMA si cerca, non si indovina ────────────────────────
            //
            // Il nome si legge dalle impostazioni di GTK, ma prima di usarlo
            // si controlla che quella cartella di puntatori esista davvero:
            // un tema che non c'è fa SPARIRE il puntatore, e sparito quello
            // non si riesce più a rimetterlo a posto col mouse.
            // ── `sh`, non `fireSh` ───────────────────────────────────────
            //
            // `fireSh` vuol dire «lancia e basta»: usa un `Process` senza
            // raccoglitore di stdout e senza segnale, e `onDone` **non arriva
            // mai**. Qui il risultato del comando È la risposta — il nome del
            // tema — quindi serve `sh`, che aspetta.
            //
            // Giacomo, 7 settembre 2026: «nemmeno ingrandire il puntatore».
            // Non era una questione di quando si applicava: non si applicava
            // proprio, né all'accesso né premendo il pulsante. Il comando
            // partiva, trovava il tema, e la risposta la buttava via un
            // `Process` che non ascoltava nessuno.
            comando.sh(
                "t=$(sed -n 's/^gtk-cursor-theme-name=//p' " +
                "\"$HOME/.config/gtk-3.0/settings.ini\" 2>/dev/null " +
                "| tr -d '\"' | head -1); " +
                "[ -d \"/usr/share/icons/$t/cursors\" ] || " +
                "[ -d \"$HOME/.icons/$t/cursors\" ] || t=Adwaita; " +
                "printf '%s' \"$t\"");
        }
    }
}

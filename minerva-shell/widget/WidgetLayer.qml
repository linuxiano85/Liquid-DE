import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core" as Core

// WidgetLayer — I widget della scrivania, su una superficie loro.
//
// ── Perché una superficie a parte e non quella delle icone ─────────────────
//
// Per il VETRO. Dal 9 settembre 2026 il compositore sa mettere un fondo
// sfocato dietro una superficie appoggiata, e lo fa **solo dove quella
// superficie dipinge davvero** (`wlr_scene_blur_set_transparency_mask_source`).
// Se i widget stessero sulla stessa superficie delle icone, la sfocatura
// finirebbe anche dietro i nomi dei file — che è un'altra cosa, e non è
// questa.
//
// Su Linux i widget della scrivania sono disegni piatti sopra lo sfondo:
// Conky, Rainmeter, i plasmoidi. Nessuno ha il vetro vero dietro, perché
// nessuno di loro possiede il compositore. Noi sì.
//
// ── Il blocco è vero, non finto ────────────────────────────────────────────
//
// Giacomo: «possono anche essere bloccati e diventare parte dello sfondo e non
// modificabili cliccabili o rimovibili».
//
// «Non cliccabili» non si fa con `enabled: false`: un oggetto disabilitato è
// ancora lì per il puntatore, si mangia il tasto destro della scrivania e chi
// clicca non capisce perché non succede niente. Si fa con `mask: Region {}`,
// che dice al compositore che questa superficie non ha NESSUNA zona sensibile:
// il clic la attraversa e arriva alla scrivania sotto.
//
// È la stessa riga che impedisce allo sfondo di mangiarsi il tasto destro,
// scritta in `menu/WallpaperLayer.qml` con il suo perché.
PanelWindow {
    id: livello

    anchors { top: true; bottom: true; left: true; right: true }

    WlrLayershell.namespace: "minerva-widget"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    color: "transparent"

    /// Bloccati: parte dello sfondo. Si sblocca dal tasto destro sulla barra
    /// («Personalizza scrivania») o dalle Impostazioni.
    readonly property bool bloccati: Core.Ipc.get("desktop.widgetBloccati", true)

    /// Nascosti del tutto: la modalità «pulita», per una schermata o per
    /// mostrare la scrivania a qualcuno.
    readonly property bool nascosti: Core.Ipc.get("desktop.puliti", false)

    /// ── Uno schermo solo ────────────────────────────────────────────────
    ///
    /// Come le icone della scrivania. Duplicare i widget su tutti gli schermi
    /// vorrebbe dire due copie dello stesso processore, e spostarne una non
    /// muoverebbe l'altra.
    ///
    /// La scelta sta QUI e non nel contenuto, e la differenza è grossa: un
    /// contenuto invisibile dentro una superficie che c'è lascia in piedi la
    /// superficie — e da sbloccati quella superficie non ha maschera, cioè si
    /// mangerebbe ogni clic del secondo schermo senza disegnare niente.
    readonly property bool principale: livello.screen
                                       && livello.screen.x === 0
                                       && livello.screen.y === 0

    visible: livello.principale && !livello.nascosti
             && Core.Ipc.get("desktop.widgetAccesi", true)
             && livello.quanti > 0

    readonly property var messi: Core.Ipc.get("desktop.widgets", [])
    readonly property int quanti: livello.messi.length

    // Bloccati, il puntatore non li vede affatto. Sbloccati, la zona sensibile
    // è tutta la superficie: si trascina, si ridimensiona, si toglie.
    mask: livello.bloccati ? livello.nessunaZona : null

    /// Una regione vuota: «questa superficie non ha nessuna zona sensibile».
    /// Dichiarata come proprietà e non appesa fra i figli — un `Region` in
    /// mezzo ai figli di una finestra è un oggetto che non disegna niente e
    /// che il prossimo che legge deve fermarsi a capire.
    property Region nessunaZona: Region {}

    // ── Chi guarda i numeri ──────────────────────────────────────────────
    //
    // Un conteggio solo per tutta la superficie: il demone legge `/proc`
    // mentre almeno un widget c'è, e smette quando non ce n'è più nessuno.
    // Il perché sta in `core/Macchina.qml`.
    //
    // ── E si spegne quando è COPERTA ────────────────────────────────────
    //
    // Un widget dietro una finestra non lo vede nessuno, e aggiornarlo è
    // tutto costo e nessun beneficio. Su un portatile è la maggior parte
    // della giornata: una finestra ingrandita e via.
    //
    // Possediamo il compositore, quindi lo sappiamo davvero — `Core.Windows`
    // ha la geometria di ognuna. È la regola che il piano della scrivania
    // chiamava «quella che vale di più tutti i giorni».
    readonly property bool serveIlDato:
        livello.visible && !Core.Gioco.aSchermoIntero && !livello.coperti

    /// ── «Coperti» vuol dire TUTTI, e coperti DAVVERO ────────────────────
    ///
    /// Due avvertenze, e sono le due che rendono facile scrivere questa
    /// regola sbagliata:
    ///
    /// 1. **Basta un widget scoperto** perché il dato serva. Se ne bastasse
    ///    la maggioranza, quello scoperto mostrerebbe un numero vecchio di
    ///    minuti senza dirlo — che è peggio di non mostrarlo.
    /// 2. **Col vetro acceso non copre niente.** Se l'effetto è acceso le
    ///    finestre sono trasparenti o sfocate, e in tutti e due i casi quello
    ///    che c'è sotto contribuisce a quello che si vede. Fermarsi lì
    ///    vorrebbe dire disegnare un numero fermo dentro una sfocatura viva.
    readonly property bool coperti: {
        if (Core.Vetro.effettoAcceso)
            return false;
        var f = livello._copritrici;
        if (f.length === 0)
            return false;
        var l = livello.messi;
        for (var i = 0; i < l.length; i++) {
            if (!livello._copertoUno(l[i], f))
                return false;
        }
        return l.length > 0;
    }

    /// Le finestre che possono coprire: aperte, non ridotte a icona, e sulla
    /// scrivania che si sta guardando. Una finestra su un'altra scrivania non
    /// copre niente, per quanto grande sia.
    readonly property var _copritrici: {
        var a = Core.Windows.active;
        if (!a)
            return [];
        var qui = a.workspace;
        var out = [];
        var tutte = Core.Windows.all;
        for (var i = 0; i < tutte.length; i++) {
            var w = tutte[i];
            if (w.minimized || w.workspace !== qui || w.w <= 0 || w.h <= 0)
                continue;
            out.push(w);
        }
        return out;
    }

    /// Un widget è coperto se sta tutto dentro UNA finestra. Non la somma di
    /// più finestre: due finestre affiancate coprono insieme, ma metterle
    /// insieme vuol dire un conto di aree che sbaglia appena si sovrappongono
    /// — e sbagliando ferma dei numeri che si vedono.
    function _copertoUno(v, f) {
        var sx = livello.screen ? livello.screen.x : 0;
        var sy = livello.screen ? livello.screen.y : 0;
        var x = sx + (v.fx !== undefined ? v.fx : 0) * livello.width;
        var y = sy + (v.fy !== undefined ? v.fy : 0) * livello.height;
        var w = (v.fw !== undefined ? v.fw : 0.16) * livello.width;
        var h = (v.fh !== undefined ? v.fh : 0.13) * livello.height;
        for (var i = 0; i < f.length; i++) {
            var q = f[i];
            if (q.x <= x && q.y <= y && q.x + q.w >= x + w && q.y + q.h >= y + h)
                return true;
        }
        return false;
    }

    onServeIlDatoChanged: {
        if (livello.serveIlDato)
            Core.Macchina.guarda();
        else
            Core.Macchina.nonGuardo();
    }

    Component.onCompleted: if (livello.serveIlDato) Core.Macchina.guarda()
    Component.onDestruction: if (livello.serveIlDato) Core.Macchina.nonGuardo()
}

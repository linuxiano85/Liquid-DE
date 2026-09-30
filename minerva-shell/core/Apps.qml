pragma Singleton
import QtQuick
// La propria cartella, dichiarata: dentro `core` gli altri singleton si
// vedrebbero anche senza, ma scriverlo risparmia a chi legge il dubbio da
// dove salti fuori `Ipc`.
import "." as Core

// Apps — I programmi installati, e come si risale da una finestra al suo.
//
// L'elenco lo scandisce il demone leggendo i file `.desktop`; qui si tiene il
// pezzo difficile, che è l'ABBINAMENTO. Una finestra dice solo la propria
// classe, e nessuno si è mai messo d'accordo su cosa ci debba stare dentro:
// Chrome dichiara `google-chrome`, Alacritty apre finestre di classe
// `Alacritty` con un file `Alacritty.desktop`, Konsole ha un file che si chiama
// `org.kde.konsole.desktop`, e un mucchio di programmi non dichiara niente.
//
// Sta qui e non nella dock perché servono le stesse tre prove anche alle barre
// del titolo, che vogliono mostrare l'icona del programma. Due copie della
// stessa euristica finiscono sempre per divergere, e il giorno che divergono
// la stessa finestra ha due icone diverse in due punti dello schermo.
QtObject {
    id: apps

    /// Ci si LEGA alla proprietà del canale invece di ascoltarne il segnale:
    /// la shell parte prima del demone, e chi si è iscritto tardi non riceve
    /// niente e resta con l'elenco vuoto per sempre.
    readonly property var all: Core.Ipc.allApps || []

    /// Qualcuno deve pur chiederlo, e insistere finché non arriva: il demone
    /// può metterci qualche secondo a scandire i `.desktop`.
    property Timer _ask: Timer {
        interval: 2500
        running: apps.all.length === 0
        repeat: true
        triggeredOnStart: true
        onTriggered: if (Core.Ipc.connected) Core.Ipc.rescanApps()
    }

    // ── Le applicazioni di Minerva ───────────────────────────────────────
    //
    // Il gestore file e le Impostazioni sono applicazioni a tutti gli effetti:
    // stanno nel menu, si cercano, si fissano nella dock, si lanciano da un
    // terminale. Hanno il loro file `.desktop` come chiunque altro.
    //
    // Per un lungo tratto non avevano un nome proprio: giravano dentro la
    // shell e al compositore dichiaravano tutte la stessa classe,
    // `org.quickshell`. Abbinarle per classe dava lo stesso programma per due
    // finestre diverse, quindi si abbinavano per TITOLO — l'unica cosa che le
    // distingueva.
    //
    // Poi ognuna ha avuto un nome proprio (`//@ pragma AppId minerva-…`), che
    // coincide col nome del suo `.desktop` e con quello della sua icona, e la
    // strada buona è tornata a essere la classe.
    //
    // ── E poi quattro sono tornate a chiamarsi tutte uguali ──────────────
    //
    // Calcolatrice, Editor, Anteprima e Attività vivono nello stesso processo
    // (`minerva-shell/app.qml`) per non pagare quattro volte il pavimento di
    // Qt. Ma `AppId` è del PROCESSO, non della finestra: Wayland ha un
    // `set_app_id` per ogni superficie, Quickshell lo imposta una volta sola
    // all'avvio. Quindi tutte e quattro dichiarano `minerva-app`, e nessun
    // `.desktop` si chiama così.
    //
    // Si vedeva nella dock e nell'Alt+Tab: Attività l'icona ce l'aveva —
    // perché il suo titolo era in questa tabella — mentre Editor e
    // Calcolatrice comparivano senza. Non era la dock: era che il ripiego per
    // titolo era rimasto fermo a prima del trasloco.
    //
    // Finché la classe è del processo, questa tabella non è un ripiego: è
    // l'unica cosa che distingue le quattro. Va tenuta viva.
    readonly property var ownApps: [
        { "appId": "minerva-files.desktop",
          "titles": ["Minerva · File", "Minerva · Files"] },
        { "appId": "minerva-settings.desktop",
          "titles": ["Minerva · Impostazioni", "Minerva · Settings"] },
        { "appId": "minerva-monitor.desktop",
          "titles": ["Minerva · Attività", "Minerva · Activity"] },
        { "appId": "minerva-calcolatrice.desktop",
          "titles": ["Minerva · Calcolatrice", "Minerva · Calculator"] },
        { "appId": "minerva-custodia.desktop",
          "titles": ["Minerva · Custodia", "Minerva · Custody"] },
        { "appId": "minerva-media.desktop",
          "titles": ["Minerva · Media"] },
        { "appId": "minerva-manutenzione.desktop",
          "titles": ["Minerva · Manutenzione", "Minerva · Maintenance"] },
        { "appId": "minerva-fucina.desktop",
          "titles": ["Minerva · Fucina", "Minerva · Forge"] },
        // Il Terminale porta nel titolo quello che la shell dice (la
        // cartella, il programma in corso): si abbina per inizio, come
        // l'editor.
        { "appId": "minerva-terminale.desktop",
          "titles": [], "prefissi": ["Minerva · Terminale", "Minerva · Terminal"] },
        // ── Le due che nel titolo portano il documento ───────────────────
        //
        // L'editor scrive «Minerva · conti.txt ●» e Anteprima «Minerva ·
        // foto.png»: è quello che serve a chi ha venti schede o venti
        // fotografie, e vuol dire che per titolo intero non si riconoscono
        // mai. Si abbinano per INIZIO.
        //
        // Il pallino dello sporco sta in fondo apposta: se stesse davanti
        // spezzerebbe anche questo.
        { "appId": "minerva-editor.desktop",
          "titles": [], "prefissi": ["Minerva · "] },
        // Anteprima ha una classe sua (`minerva-viewer`) perché è ancora un
        // processo a sé, quindi qui basta il nome proprio della finestra
        // quando non ha nessun file aperto.
        { "appId": "minerva-viewer.desktop",
          "titles": ["Minerva · Anteprima", "Minerva · Preview"] }
    ]

    /// Il programma di una finestra della shell, riconosciuto dal titolo.
    ///
    /// I titoli interi si provano TUTTI prima dei prefissi: «Minerva · » è il
    /// prefisso dell'editor ed è anche l'inizio del titolo di ogni altra
    /// nostra finestra. Cercando in un giro solo, la prima app con un prefisso
    /// si prenderebbe le finestre di tutte le altre.
    function forOwnWindow(title) {
        var t = String(title || "");
        var i, j;
        for (i = 0; i < apps.ownApps.length; i++)
            for (j = 0; j < (apps.ownApps[i].titles || []).length; j++)
                if (t === apps.ownApps[i].titles[j])
                    return apps.byId(apps.ownApps[i].appId);
        for (i = 0; i < apps.ownApps.length; i++)
            for (j = 0; j < (apps.ownApps[i].prefissi || []).length; j++)
                if (t.indexOf(apps.ownApps[i].prefissi[j]) === 0)
                    return apps.byId(apps.ownApps[i].appId);
        return null;
    }

    /// I nomi che le nostre finestre si danno quando NON hanno un documento
    /// aperto: «Custodia», «Attività», «Calcolatrice»…
    ///
    /// ── Perché esiste questa lista ─────────────────────────────────────
    ///
    /// Il prefisso dell'editor è «Minerva · », che è anche l'inizio del titolo
    /// di OGNI nostra finestra. Finché ogni finestra aveva la sua riga qui
    /// sopra la cosa reggeva, perché i titoli interi si provano tutti prima;
    /// ma la prima finestra nuova che si dimentica di aggiungere cade nel
    /// prefisso e diventa l'editor.
    ///
    /// È successo davvero: la Custodia, aperta, nella dock e nell'Alt+Tab si
    /// chiamava «Editor di testi» e ne prendeva l'icona. Il difetto non si
    /// vede leggendo il codice — si vede guardando lo schermo — e non è un
    /// caso limite: capita a ogni applicazione nuova.
    ///
    /// La prova `prove.sh` controlla che ogni `//@ pragma AppId minerva-app`
    /// abbia la sua riga in `ownApps`, così la prossima volta si rompe una
    /// prova invece di rompersi un nome.
    function nomeConosciuto(titolo) {
        var t = String(titolo || "");
        for (var i = 0; i < apps.ownApps.length; i++)
            for (var j = 0; j < (apps.ownApps[i].titles || []).length; j++)
                if (t === apps.ownApps[i].titles[j])
                    return true;
        return false;
    }

    /// Il programma di una finestra qualunque. È questa che va usata: sa già
    /// distinguere le finestre della shell da quelle di tutti gli altri.
    function forWindow(w) {
        if (!w)
            return null;
        // Prima la classe, anche per le nostre: da quando ogni applicazione di
        // Minerva ha un nome proprio (`//@ pragma AppId`) la classe è la strada
        // buona anche qui, ed è quella che porta all'icona giusta. Il titolo
        // resta come ripiego per le finestre che si presentano ancora come
        // `org.quickshell`.
        const A = apps.forClass(w.appClass);
        if (A)
            return A;
        if (w.own === true)
            return apps.forOwnWindow(w.title);
        return null;
    }

    /// Il programma a cui appartiene una finestra, o `null`.
    function forClass(cls) {
        if (!cls || cls === "")
            return null;
        var low = String(cls).toLowerCase();
        var list = apps.all;
        var i, a;

        // 1. `StartupWMClass`, che è il campo fatto apposta per questo.
        for (i = 0; i < list.length; i++) {
            a = list[i];
            if (a.wmClass && String(a.wmClass).toLowerCase() === low)
                return a;
        }
        // 2. L'identificatore senza `.desktop`.
        for (i = 0; i < list.length; i++) {
            a = list[i];
            if (String(a.appId).replace(/\.desktop$/, "").toLowerCase() === low)
                return a;
        }
        // 3. Il primo pezzo del comando, contro la classe intera o contro il
        //    suo ultimo segmento: `org.kde.konsole` e `konsole` sono lo stesso
        //    programma.
        var tail = low.split(".").pop();
        for (i = 0; i < list.length; i++) {
            a = list[i];
            var first = String(list[i].exec || "").trim().split(/\s+/)[0] || "";
            var base = first.split("/").pop().toLowerCase();
            if (base !== "" && (base === low || base === tail))
                return list[i];
        }
        return null;
    }

    function byId(id) {
        for (var i = 0; i < apps.all.length; i++)
            if (apps.all[i].appId === id)
                return apps.all[i];
        return null;
    }

    /// Percorso dell'icona di una finestra, "" se non si sa.
    function iconForClass(cls) {
        var a = apps.forClass(cls);
        return a && a.icon ? a.icon : "";
    }
}

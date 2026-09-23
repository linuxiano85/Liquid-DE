pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland

import "." as Core

// Gioco — La modalità gioco, che si accende da sola.
//
// ── Perché esiste, e perché nessuno ce l'ha ────────────────────────────────
//
// Chi gioca su Windows non pensa a niente: lancia il gioco e il computer si
// comporta di conseguenza. Su Linux invece si scopre col tempo che bisogna
// dirlo a mano, un pezzo per volta — spegnere le notifiche, impedire il blocco
// schermo, mettere il profilo su prestazioni — e ogni volta ci si ricorda solo
// DOPO che è successo qualcosa:
//
//  · la notifica dell'aggiornamento che compare in mezzo a una partita;
//  · lo schermo che si spegne perché per venti minuti non hai toccato il mouse
//    (stavi guardando un filmato, o giocavi col pad);
//  · il processore che resta in modalità risparmio perché il portatile non sa
//    che quello che sta girando è un gioco.
//
// Sono tre fastidi piccoli che messi insieme fanno «su Linux non si gioca».
//
// ── Due livelli, perché a schermo intero non c'è solo il gioco ─────────────
//
// A schermo intero ci va anche un film, e anche lì le notifiche danno fastidio
// e lo schermo non deve spegnersi. Ma un film NON deve far salire il
// processore a prestazioni: sarebbe batteria buttata per guardare qualcosa che
// va bene comunque.
//
// Quindi:
//
//   schermo intero            → notifiche zitte, niente blocco né spegnimento
//   schermo intero + gioco    → in più, profilo su prestazioni
//
// ── E si rimette tutto com'era ─────────────────────────────────────────────
//
// Un pezzo di ambiente che cambia le impostazioni e non le rimette a posto è
// peggio di uno che non le cambia. Il profilo di energia si LEGGE prima di
// toccarlo e si riscrive quello di prima, e il silenzio delle notifiche è una
// proprietà a runtime che non passa dal demone: se la shell muore in mezzo a
// una partita, al riavvio è già tutto normale.
QtObject {
    id: gioco

    /// Vero quando qualcosa occupa tutto lo schermo.
    readonly property bool aSchermoIntero: {
        var w = Core.Windows.all || [];
        for (var i = 0; i < w.length; i++)
            if (w[i].modoSchermo === 2 && !w[i].minimized)
                return true;
        return false;
    }

    /// La finestra a schermo intero, se c'è.
    readonly property var finestra: {
        var w = Core.Windows.all || [];
        for (var i = 0; i < w.length; i++)
            if (w[i].modoSchermo === 2 && !w[i].minimized)
                return w[i];
        return null;
    }

    // ── È un gioco? ──────────────────────────────────────────────────────
    //
    // Non c'è un modo pulito di saperlo: Wayland non dice «questo è un gioco».
    // Si guarda la classe della finestra, ed è affidabile più di quanto
    // sembri, perché chi fa girare i giochi su Linux ci mette il proprio nome:
    //
    //   steam_app_1091500   un gioco lanciato da Steam
    //   gamescope           il compositore che Steam usa per i giochi
    //   lutris / heroic     i due lanciatori più diffusi
    //   *.exe               un gioco Windows sotto Wine o Proton
    //
    // Quello che NON c'è in questo elenco conta quanto quello che c'è: un
    // browser a schermo intero è un film, e non deve far salire il processore.
    readonly property var segniDiGioco: [
        /^steam_app_/i, /^gamescope$/i, /^lutris/i, /^heroic/i, /^bottles/i,
        /\.exe$/i, /^wine/i, /^proton/i, /^minecraft/i, /^retroarch/i,
        /^dolphin-emu/i, /^pcsx2/i, /^rpcs3/i, /^yuzu/i, /^ryujinx/i
    ]

    readonly property bool eUnGioco: {
        if (!gioco.finestra)
            return false;
        var c = String(gioco.finestra.appClass || "");
        for (var i = 0; i < gioco.segniDiGioco.length; i++)
            if (gioco.segniDiGioco[i].test(c))
                return true;
        return false;
    }

    /// Acceso dall'utente a mano, dal pannello di controllo. Vale come se ci
    /// fosse un gioco: chi lo accende sa quello che vuole.
    property bool forzato: false

    readonly property bool attiva: gioco.forzato || gioco.aSchermoIntero
    readonly property bool prestazioni: gioco.forzato || gioco.eUnGioco

    /// Come si chiama quello che sta girando, per il cartello.
    readonly property string nome: {
        if (!gioco.finestra)
            return "";
        var a = Core.Apps.forClass(gioco.finestra.appClass || "");
        if (a && a.name)
            return a.name;
        return gioco.finestra.appClass || gioco.finestra.title || "";
    }

    // ── Le tre cose che cambia ───────────────────────────────────────────

    onAttivaChanged: {
        Core.Notifications.zittitoDalGioco = gioco.attiva;
        if (!gioco.attiva)
            gioco.rimettiProfilo();
    }

    onPrestazioniChanged: {
        if (gioco.prestazioni)
            gioco.alzaProfilo();
        else
            gioco.rimettiProfilo();
    }

    // ── Il blocco schermo e lo spegnimento ───────────────────────────────
    //
    // `IdleInhibitor` è il modo previsto da Wayland: si dichiara al
    // compositore che una superficie non vuole che il computer si consideri
    // fermo, e chi sorveglia l'inattività lo rispetta senza che ci si debba
    // parlare.
    //
    // Chi sorveglia, dal 1º settembre 2026, è il compositore stesso: conta gli
    // inibitori vivi e finché ce n'è uno non annuncia niente (vedi
    // `inibitore_nuovo` in `compositore/src/main.c`). Prima il protocollo era
    // acceso e non lo onorava nessuno — cioè questo blocco c'era e non faceva
    // niente, che è peggio di non averlo: chi legge il codice lo dà per fatto.
    //
    // Molti giochi lo fanno già da soli; molti no, e i lanciatori quasi mai.
    // Chi guarda un film col pad in mano non tocca né mouse né tastiera per
    // due ore: senza questo, lo schermo si spegne in mezzo.
    //
    // Dal 23 settembre 2026, sotto il NOSTRO compositore, lo schermo intero
    // frena da solo (`schermo_intero_visibile` in `compositore/src/main.c`).
    // Il freno appeso qui voleva una superficie mappata per tutto il film,
    // e una superficie della shell sopra la finestra a schermo intero basta
    // a impedire lo scanout diretto: la scheda video ricompone ogni
    // fotogramma per una striscia trasparente. Qui resta il freno acceso a
    // mano (`forzato`), e quello sotto Hyprland, che non frena da sé.
    readonly property bool frenoServe: gioco.attiva
        && (gioco.forzato || !Core.Compositore.nostro)

    property var freno: IdleInhibitor {
        window: gioco.finestraFreno
        enabled: gioco.frenoServe
    }

    /// La finestra a cui appendere il freno. La mette la shell: qui non
    /// abbiamo superfici nostre, e `IdleInhibitor` ne vuole una.
    property var finestraFreno: null

    // ── Il profilo di energia ────────────────────────────────────────────

    property string _profiloPrima: ""

    property var _leggi: Core.Exec {
        onDone: function (out) {
            var p = String(out).trim();
            if (p !== "")
                gioco._profiloPrima = p;
            gioco._scrivi.fireSh("powerprofilesctl set performance");
        }
    }

    property var _scrivi: Core.Exec {}

    function alzaProfilo() {
        // Si legge prima di scrivere, sempre: rimettere «bilanciato» a chi
        // aveva scelto «risparmio energetico» è cambiargli le impostazioni
        // senza dirglielo.
        if (gioco._profiloPrima === "")
            gioco._leggi.sh("powerprofilesctl get 2>/dev/null");
        else
            gioco._scrivi.fireSh("powerprofilesctl set performance");
    }

    function rimettiProfilo() {
        if (gioco._profiloPrima === "")
            return;
        gioco._scrivi.fireShArgs("powerprofilesctl set \"$1\"", [gioco._profiloPrima]);
        gioco._profiloPrima = "";
    }
}

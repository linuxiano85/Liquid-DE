pragma Singleton
import QtQuick
import "." as Core

// DesktopStyle — I preset della scrivania: quali sono, come si chiamano, e il
// cambio dall'uno all'altro.
//
// Ogni preset ricorda le proprie scelte (effetti, angoli, colori, sfondo,
// icone, tiling, scorciatoie): il demone salva quelle del preset che si lascia
// e rimette quelle del preset in cui si entra, con una scrittura sola
// (`minervad/lib/core/desktop_profiles.dart`). Qui non si riapplica niente di
// fabbrica: si coprirebbero le scelte di chi usa il preset.
//
// L'elenco sta qui e non nelle Impostazioni perché lo leggono in due: la
// pagina Aspetto e il selettore rapido (Super+P, `menu/SelettorePreset.qml`).
// Due copie sarebbero due descrizioni che un giorno dicono cose diverse.
QtObject {
    id: preset

    readonly property string attuale: Core.Ipc.get("stile.attuale", "libero")
    readonly property bool it: Core.Strings.lang === "it"

    /// I preset, nell'ordine in cui si mostrano. `breve` va sotto il nome nel
    /// selettore; `descrizione` è la frase intera delle Impostazioni.
    readonly property var elenco: [
        {
            "id": "liquid",
            "nome": "Liquid",
            "breve": preset.it ? "L'Isola al posto della barra" : "The Island instead of a bar",
            "descrizione": preset.it
                ? "Al posto della barra l'Isola: una capsula che galleggia in mezzo con l'ora, il tempo, i segni di stato e le notifiche. Si trascina in alto o in basso."
                : "Instead of the bar, the Island: a capsule floating in the middle with the time, the weather, the status and the notifications. Drag it up or down."
        },
        {
            "id": "minerva",
            "nome": "Minerva",
            "breve": preset.it ? "Barra in alto, dock in fondo" : "Top bar, dock at the bottom",
            "descrizione": preset.it
                ? "Barra in alto, dock in fondo sempre visibile, comandi delle finestre a destra."
                : "Bar on top, dock always visible at the bottom, window controls on the right."
        },
        {
            "id": "mac",
            "nome": "Mac",
            "breve": preset.it ? "Dock che si scansa, comandi a sinistra" : "Dock that steps aside, controls on the left",
            "descrizione": preset.it
                ? "Come Minerva, ma la dock ingrandisce di più e si toglie di mezzo quando una finestra le arriva addosso, e i comandi delle finestre stanno a sinistra."
                : "Like Minerva, but the dock magnifies more and gets out of the way, and the window controls sit on the left."
        },
        {
            "id": "windows",
            "nome": "Windows 11",
            "breve": preset.it ? "Barra centrata e Start" : "Centred taskbar and Start",
            "descrizione": preset.it
                ? "Windows 11 classico: barra centrata, Start, ricerca, notifiche e impostazioni rapide. Le preferenze sono salvate solo in questo stile."
                : "Classic Windows 11: centred taskbar, Start, search, notifications and quick settings. Preferences are saved for this style."
        },
        {
            "id": "libero",
            "nome": preset.it ? "Libero" : "Free",
            "breve": preset.it ? "Come l'avevi messo tu" : "The way you set it up",
            "descrizione": preset.it
                ? "Quello che avevi messo tu, ripreso com'era."
                : "Whatever you had set up, brought back as it was."
        }
    ]

    /// La voce di un preset, o `null` se il nome non esiste.
    function voce(nome) {
        for (var i = 0; i < preset.elenco.length; i++) {
            if (preset.elenco[i].id === nome)
                return preset.elenco[i];
        }
        return null;
    }

    /// Passa al preset `nome`. Un nome che non esiste, o quello già attivo, non
    /// fa niente: rientrare nello stesso preset rimetterebbe di fabbrica
    /// quello che c'è.
    function applica(nome) {
        if (preset.voce(nome) === null || nome === preset.attuale)
            return;
        Core.Ipc.setSetting("stile.attuale", nome);
    }
}

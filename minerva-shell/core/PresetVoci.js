// PresetVoci — In quali preset vale una scheda delle Impostazioni.
//
// Una tabella sola, così la regola si legge in un posto: le pagine scrivono
// `preset: PresetVoci.barraLiquid` e non un elenco di nomi ripetuto (che un
// giorno, in una delle copie, perderebbe un preset). Vuoto vuol dire «tutti»;
// il preset «libero» vede comunque tutto (`settings/sections/Card.qml`).
//
// il manutentore, 11 ottobre 2026: «impostazioni per ogni preset grafica come
// Windows». Col preset Windows la pagina «Barra e dock» mostrava la dock,
// l'Isola, la Riva e la molla di Liquid, che lì non esistono.
.pragma library

/// La barra di Liquid con la sua dock, l'Isola, la Riva e gli angoli: tutti
/// i preset tranne Windows, che ha la sua barra (`windows11/Taskbar.qml`).
var barraLiquid = ["liquid", "minerva", "mac"];

/// Solo il preset Windows 11.
var windows = ["windows"];

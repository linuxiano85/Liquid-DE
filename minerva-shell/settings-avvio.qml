//@ pragma AppId minerva-settings
// settings-avvio.qml — l'ingresso con cui si lancia `settings.qml`.
//
// Carica `settings.qml` con un indirizzo file:// perché Qt ne tenga in cache la
// compilazione: quello che Quickshell carica come `qs:@` non entra mai nella
// cache. Il perché e le misure stanno in `filemanager-avvio.qml` (19 ottobre
// 2026). `settings.qml` non cambia e si può ancora avviare da solo.
// I pragma devono stare QUI, nel file che Quickshell legge per primo.
import QtQuick
import Quickshell

ShellRoot {
    LazyLoader {
        active: true
        source: "file://" + Quickshell.shellDir + "/settings.qml"
    }
}

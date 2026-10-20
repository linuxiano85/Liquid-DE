//@ pragma AppId minerva-app
// app-avvio.qml — l'ingresso con cui si lancia `app.qml`.
//
// Carica `app.qml` con un indirizzo file:// perché Qt ne tenga in cache la
// compilazione: quello che Quickshell carica come `qs:@` non entra mai nella
// cache. Il perché e le misure stanno in `filemanager-avvio.qml` (19 ottobre
// 2026). `app.qml` non cambia e si può ancora avviare da solo.
// I pragma devono stare QUI, nel file che Quickshell legge per primo.
import QtQuick
import Quickshell

ShellRoot {
    LazyLoader {
        active: true
        source: "file://" + Quickshell.shellDir + "/app.qml"
    }
}

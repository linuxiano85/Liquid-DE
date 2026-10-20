// shell-avvio.qml — l'ingresso con cui il guardiano (`minerva-interfaccia`)
// lancia la scrivania.
//
// Carica `shell.qml` con un indirizzo file:// perché Qt ne tenga in cache la
// compilazione: quello che Quickshell carica come `qs:@` non entra mai nella
// cache (registro `qt.qml.diskcache`: «File has to be a local file»). Il
// perché e le misure stanno in `filemanager-avvio.qml` (19 ottobre 2026).
// `shell.qml` non cambia e si può ancora avviare da solo (`qs -p`).
import QtQuick
import Quickshell

ShellRoot {
    LazyLoader {
        active: true
        source: "file://" + Quickshell.shellDir + "/shell.qml"
    }
}

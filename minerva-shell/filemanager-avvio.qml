//@ pragma AppId minerva-files
// filemanager-avvio.qml — l'ingresso con cui si lancia il gestore file.
//
// Non fa niente se non caricare `filemanager.qml` con un indirizzo file://.
//
// ── Perché un ingresso in più ─────────────────────────────────────────────
//
// Quickshell carica il file che gli si passa con `qs -p`, e tutto quello che
// quel file importa con indirizzi relativi, come `qs:@/qs/…`: un finto
// indirizzo di rete. Per Qt sono file remoti, e i file remoti non entrano
// nella cache della compilazione («File has to be a local file», registro
// `qt.qml.diskcache`). Così ogni apertura ricompilava da capo tutto il
// gestore file: il profilo del 19 ottobre 2026 dava ~459 ms solo
// di compilazione, su ~750 di avvio.
//
// Caricato da qui con `file://`, `filemanager.qml` e tutto ciò che importa
// restano file locali: dalla seconda apertura Qt usa la cache. Misurato il 19
// ottobre (Liquid_test `prova_filemanager_riapertura.py`, banco privato):
// primo dato disegnato a 720–800 ms prima, 342–404 ms dopo (la prima apertura
// in assoluto, a cache vuota, resta ~745 ms).
//
// `filemanager.qml` non cambia e si può ancora lanciare da solo (`qs -p`):
// le prove che lo leggono o lo avviano direttamente funzionano come prima.
// Il pragma `AppId` deve stare QUI, nel file che Quickshell legge per primo.
import QtQuick
import Quickshell

ShellRoot {
    LazyLoader {
        active: true
        source: "file://" + Quickshell.shellDir + "/filemanager.qml"
    }
}

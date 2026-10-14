pragma Singleton
import QtQuick
import Quickshell
import "." as Core

// Utente — Chi usa il computer: il nome da mostrare e la foto.
//
// Li sa il demone (AccountsService, `greeter_info`); qui si chiedono una
// volta per processo e si tengono aggiornati a ogni risposta, anche quando
// è la pagina Utente delle Impostazioni a chiederli dopo averli cambiati.
// Servono al piede dello Start di Windows e alla navigazione delle
// Impostazioni in Windows (12 ottobre 2026): prima ognuno faceva la sua
// richiesta, e lo Start scriveva «Account locale» al posto del nome.
QtObject {
    id: utente

    property var io: null
    readonly property string login: Quickshell.env("USER") || ""
    readonly property string nome: utente.io ? (utente.io.nomeCompleto || utente.io.nome || utente.login)
                                             : utente.login
    readonly property string ritratto: utente.io && utente.io.ritratto ? utente.io.ritratto : ""

    function aggiorna() {
        if (Core.Ipc.connected)
            Core.Ipc.greeterInfo();
    }

    property Connections _demone: Connections {
        target: Core.Ipc
        function onConnectedChanged() { utente.aggiorna(); }
        function onGreeterInfoReceived(info) {
            var utenti = info.utenti || [];
            for (var i = 0; i < utenti.length; i++) {
                if (utenti[i].nome === utente.login) {
                    utente.io = utenti[i];
                    return;
                }
            }
        }
    }

    Component.onCompleted: utente.aggiorna()
}

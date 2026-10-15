import QtQuick
import "../../core" as Core
import "../../windows11" as W

PaginaWindows {
    id: pagina
    objectName:"impostazioniRipristinoWindows"
    briciole:[{testo:W.Style.label("Sistema", "System"),pagina:"w-sistema"},
        {testo:W.Style.label("Ripristino", "Recovery")}]
    property bool conferma:false
    Timer { id:scadenza; interval:4000; onTriggered:pagina.conferma=false }
    SchedaImpostazione {
        titolo:W.Style.label("Ripristina le preferenze di Liquid DE", "Reset Liquid DE preferences")
        descrizione:W.Style.label("Riporta le preferenze del desktop ai valori iniziali. Non reinstalla Linux e non cancella file personali.",
            "Restore desktop preferences to their defaults. This does not reinstall Linux or delete personal files.")
        icona:"restore"
        PulsanteWindows {
            objectName:"ripristinaPreferenze"
            enabled:Core.Ipc.connected
            testo:pagina.conferma ? W.Style.label("Conferma ripristino", "Confirm reset") : W.Style.label("Ripristina", "Reset")
            onPremuto: {
                if (pagina.conferma) {
                    pagina.conferma=false;
                    scadenza.stop();
                    Core.Ipc.resetSettings();
                } else {
                    pagina.conferma=true;
                    scadenza.restart();
                }
            }
        }
    }
    Text {
        visible:pagina.conferma
        width:parent.width
        wrapMode:Text.Wrap
        text:W.Style.label("Premi di nuovo entro quattro secondi per confermare. Verrà ripristinato anche il preset iniziale.",
            "Press again within four seconds to confirm. The default preset will also be restored.")
        font.family:W.Style.font
        font.pixelSize:14*W.Style.textScale
        color:W.Style.muted
    }
}

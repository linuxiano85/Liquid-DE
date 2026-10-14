import QtQuick
import "../core" as Core
import "windows" as W

// Le categorie condividono la stessa impalcatura delle pagine dedicate:
// il vecchio ripiego usava margini e schede Liquid e spezzava la navigazione.
W.PaginaWindows {
    id: categoria

    readonly property bool it: Core.Strings.lang === "it"
    readonly property var dati: finestra
        ? finestra.categoriaPer(finestra.paginaCategoria) : null
    briciole: [{ testo: dati ? (it ? dati.it : dati.en) : "" }]

    Repeater {
        model: categoria.dati ? categoria.dati.voci : []
        delegate: W.SchedaImpostazione {
            required property string modelData
            readonly property var pagina: categoria.finestra.paginaPer(modelData)
            readonly property var dettagli: categoria.finestra.descrizioniWindows[modelData] || ["", ""]
            objectName: "categoriaVoce-" + modelData
            icona: pagina ? pagina.icon : "settings"
            titolo: pagina ? (categoria.it ? pagina.it : pagina.en) : ""
            descrizione: categoria.it ? dettagli[0] : dettagli[1]
            porta: true
            onAttivata: categoria.finestra.apriSezione(modelData)
        }
    }
}

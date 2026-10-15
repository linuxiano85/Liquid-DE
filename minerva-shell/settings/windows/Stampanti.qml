import QtQuick
import ".." as S
import "../../windows11" as W
PaginaWindows {
    id: page
    objectName: "impostazioniStampantiWindows"
    property alias vista: content.selectedPrinter
    briciole: {
        var rows=[{testo:W.Style.label("Bluetooth e dispositivi", "Bluetooth & devices"), categoria:"dispositivi"},
            {testo:W.Style.label("Stampanti e scanner", "Printers & scanners"),pagina:"stampanti"}];
        if (content.selectedPrinter) rows.push({testo:content.selectedPrinter});
        return rows;
    }
    function apriStampante(name) {
        if (page.finestra) page.finestra.registraVistaInterna(name);
        content.selectedPrinter=name;
        page.posizioneScorrimento=0;
    }
    S.PrintingContent {
        id: content
        width: parent.width
        onPrinterRequested: function(name) {page.apriStampante(name);}
    }
}

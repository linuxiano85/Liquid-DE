import QtQuick
import ".." as S
import "../../windows11" as W
PaginaWindows {
    objectName: "impostazioniStampantiWindows"
    briciole: [{testo: W.Style.label("Bluetooth e dispositivi", "Bluetooth & devices"), categoria:"dispositivi"},
        {testo: W.Style.label("Stampanti e scanner", "Printers & scanners")}]
    S.PrintingContent { width: parent.width }
}

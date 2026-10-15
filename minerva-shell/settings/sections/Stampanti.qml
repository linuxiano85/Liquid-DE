import QtQuick
import "../../core" as Core
import ".." as S
Page {
    title: Core.Strings.lang === "it" ? "Stampanti e scanner" : "Printers & scanners"
    subtitle: Core.Strings.lang === "it" ? "Code, consumabili e manutenzione" : "Queues, supplies and maintenance"
    S.PrintingContent { width: parent.width }
}

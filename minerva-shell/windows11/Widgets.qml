import "../core" as Core
import "../ui" as Ui
import QtQuick
import Quickshell

FocusScope {
    id: widgets

    readonly property var now: Core.Meteo.adesso || ({
    })
    readonly property var days: Core.Meteo.giorni.slice(0, 5)
    readonly property bool weatherReady: Core.Meteo.attivo && Core.Meteo.pronto
    readonly property var locale: Qt.locale(Style.it ? "it_IT" : "en_US")
    readonly property bool twoColumns: width >= 620
    property bool forecastExpanded: false

    signal settingsRequested(string section)
    signal overviewRequested()
    signal calendarRequested()
    signal searchRequested(string query)

    objectName: "windowsWidgets"

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    // Il riferimento fornito dall'utente usa una bacheca Acrylic con schede
    // chiare e compatte: il meteo non è un rettangolo azzurro pieno.
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Style.widgetsSurface
        border.color: Style.dark ? "#40ffffff" : "#70ffffff"
    }

    Text {
        y: 26
        anchors.horizontalCenter: parent.horizontalCenter
        text: clock.date.toLocaleTimeString(widgets.locale, Core.Ipc.get("clock.format24", true) ? "HH:mm" : "h:mm AP")
        color: Style.text
        font.family: Style.font
        font.pixelSize: 26
    }

    Button {
        x: 22
        y: 24
        icon: "settings"
        tooltip: Style.label("Personalizza widget", "Customise widgets")
        onClicked: widgets.settingsRequested("preset")
    }

    Button {
        anchors.right: parent.right
        anchors.rightMargin: 22
        y: 24
        icon: "user"
        tooltip: Style.label("Account", "Account")
        onClicked: widgets.settingsRequested("utente")
    }

    Rectangle {
        x: 56
        y: 76
        width: parent.width - 112
        height: 36
        radius: 4
        color: Style.dark ? "#cc303030" : "#dfffffff"
        border.color: search.activeFocus ? Style.accent : Style.edge

        TaskGlyph {
            x: 12
            y: 9
            width: 18
            height: 18
        }

        TextInput {
            id: search

            objectName: "windowsWidgetsSearch"
            x: 40
            width: parent.width - 52
            height: parent.height
            clip: true
            verticalAlignment: TextInput.AlignVCenter
            color: Style.text
            font.family: Style.font
            font.pixelSize: 13
            selectByMouse: true
            Accessible.name: Style.label("Cerca app e documenti", "Search apps and documents")
            onAccepted: {
                if (text.trim() !== "") {
                    widgets.searchRequested(text.trim());
                }
            }

            Text {
                anchors.fill: parent
                visible: search.text === ""
                verticalAlignment: Text.AlignVCenter
                text: Style.label("Digita per cercare", "Type here to search")
                color: Style.muted
                font: search.font
            }

        }

    }

    Flickable {
        id: scroll

        objectName: "windowsWidgetsScroll"
        x: 56
        y: 142
        width: parent.width - 112
        height: parent.height - 162
        contentWidth: width
        contentHeight: content.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content

            width: scroll.width
            spacing: 24

            Row {
                width: parent.width
                spacing: 12

                Column {
                    width: widgets.twoColumns ? (parent.width - 12) / 2 : parent.width
                    spacing: 12

                    Rectangle {
                        id: weather

                        objectName: "windowsWeatherCard"
                        width: parent.width
                        height: widgets.forecastExpanded ? 342 : 220
                        radius: 8
                        border.color: Style.edge

                        Row {
                            x: 12
                            y: 12
                            spacing: 6

                            WeatherIcon {
                                width: 16
                                height: 16
                                code: 2
                            }

                            Text {
                                text: Style.label("Meteo", "Weather")
                                color: Style.text
                                font.family: Style.font
                                font.pixelSize: 12
                            }

                        }

                        Button {
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            y: 4
                            icon: "settings"
                            tooltip: Style.label("Località e meteo", "Location and weather")
                            onClicked: widgets.settingsRequested("dataora")
                        }

                        Text {
                            x: 92
                            y: 53
                            width: parent.width - 104
                            text: Core.Meteo.luogo || Style.label("Scegli una località", "Choose a location")
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Style.text
                            font.family: Style.font
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        WeatherIcon {
                            x: 20
                            y: 85
                            width: 60
                            height: 60
                            visible: widgets.weatherReady
                            code: widgets.now.codice === undefined ? 3 : widgets.now.codice
                            day: widgets.now.giorno !== false
                        }

                        Text {
                            x: 92
                            y: 79
                            text: widgets.weatherReady ? Core.Meteo.gradi(widgets.now.temperatura) : "—"
                            color: Style.text
                            font.family: Style.font
                            font.pixelSize: 40
                        }

                        Text {
                            x: 94
                            y: 131
                            width: parent.width - 108
                            text: widgets.weatherReady ? Core.Meteo.descrizione(widgets.now.codice) : Style.label("Configura il meteo", "Set up weather")
                            color: Style.text
                            font.family: Style.font
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Row {
                            x: 18
                            y: 174
                            spacing: 10
                            visible: widgets.weatherReady

                            Text {
                                text: widgets.now.umidita === undefined || widgets.now.umidita === null ? "" : Style.label("Umidità ", "Humidity ") + Math.round(widgets.now.umidita) + "%"
                                color: Style.muted
                                font.family: Style.font
                                font.pixelSize: 11
                            }

                            Text {
                                text: widgets.now.vento === undefined || widgets.now.vento === null ? "" : Math.round(widgets.now.vento) + " km/h"
                                color: Style.muted
                                font.family: Style.font
                                font.pixelSize: 11
                            }

                        }

                        Row {
                            x: 12
                            y: 213
                            width: parent.width - 24
                            visible: widgets.forecastExpanded && widgets.weatherReady

                            Repeater {
                                model: widgets.days

                                delegate: Column {
                                    required property var modelData

                                    width: (weather.width - 24) / Math.max(1, widgets.days.length)
                                    spacing: 8

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: new Date(parent.modelData.data).toLocaleDateString(widgets.locale, "ddd")
                                        color: Style.text
                                        font.family: Style.font
                                        font.pixelSize: 11
                                    }

                                    WeatherIcon {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 26
                                        height: 26
                                        code: parent.modelData.codice
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: Core.Meteo.gradi(parent.modelData.max)
                                        color: Style.text
                                        font.family: Style.font
                                        font.pixelSize: 12
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: Core.Meteo.gradi(parent.modelData.min)
                                        color: Style.muted
                                        font.family: Style.font
                                        font.pixelSize: 11
                                    }

                                }

                            }

                        }

                        Button {
                            objectName: "windowsWeatherForecast"
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            height: 28
                            text: !widgets.weatherReady ? Style.label("Configura località", "Set up location") : widgets.forecastExpanded ? Style.label("Riduci previsioni", "Hide forecast") : Style.label("Vedi tutte le previsioni", "See full forecast")
                            onClicked: {
                                if (!widgets.weatherReady)
                                    widgets.settingsRequested("dataora");
                                else
                                    widgets.forecastExpanded = !widgets.forecastExpanded;
                            }
                        }

                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: Style.dark ? "#303a43" : "#f6fafb"
                            }

                            GradientStop {
                                position: 1
                                color: Style.dark ? "#3b3828" : "#fff8d7"
                            }

                        }

                    }

                    Rectangle {
                        width: parent.width
                        height: 236
                        radius: 8
                        color: Style.card
                        border.color: Style.cardStroke

                        Text {
                            x: 16
                            y: 14
                            text: Style.label("Calendario", "Calendar")
                            color: Style.text
                            font.family: Style.font
                            font.pixelSize: 12
                        }

                        Text {
                            x: 16
                            y: 54
                            text: Qt.formatDateTime(clock.date, "d")
                            color: Style.accentInk
                            font.family: Style.font
                            font.pixelSize: 64
                        }

                        Text {
                            x: 16
                            y: 135
                            width: parent.width - 32
                            wrapMode: Text.WordWrap
                            text: clock.date.toLocaleDateString(widgets.locale, "dddd d MMMM yyyy")
                            color: Style.muted
                            font.family: Style.font
                            font.pixelSize: 13
                        }

                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 8
                            text: Style.label("Apri calendario", "Open calendar")
                            onClicked: widgets.calendarRequested()
                        }

                    }

                    Rectangle {
                        visible: !widgets.twoColumns
                        width: parent.width
                        height: 236
                        radius: 8
                        color: Style.card
                        border.color: Style.cardStroke

                        Text {
                            x: 16
                            y: 18
                            width: parent.width - 32
                            text: Style.label("Spazi di lavoro", "Workspaces")
                            color: Style.text
                            font.family: Style.font
                            font.pixelSize: 14
                        }

                        Button {
                            x: 16
                            y: 74
                            text: Style.label("Visualizza i desktop", "View desktops")
                            icon: "window"
                            onClicked: widgets.overviewRequested()
                        }

                    }

                }

                Column {
                    visible: widgets.twoColumns
                    width: (parent.width - 12) / 2
                    spacing: 12

                    Rectangle {
                        width: parent.width
                        height: 312
                        radius: 8
                        clip: true
                        color: Style.card
                        border.color: Style.cardStroke

                        Text {
                            x: 16
                            y: 14
                            text: Style.label("Foto", "Photos")
                            color: Style.text
                            font.family: Style.font
                            font.pixelSize: 12
                        }

                        Text {
                            x: 16
                            y: 51
                            text: Style.label("Il tuo sfondo", "Your wallpaper")
                            color: Style.text
                            font.family: Style.font
                            font.pixelSize: 18
                        }

                        Image {
                            x: 1
                            y: 86
                            width: parent.width - 2
                            height: 175
                            source: Core.Wallpaper.current ? "file://" + Core.Wallpaper.current : ""
                            asynchronous: true
                            sourceSize.width: 640
                            fillMode: Image.PreserveAspectCrop

                            Text {
                                anchors.centerIn: parent
                                visible: parent.status !== Image.Ready
                                text: Style.label("Nessuna foto scelta", "No photo selected")
                                color: Style.muted
                                font.family: Style.font
                                font.pixelSize: 12
                            }

                        }

                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6
                            text: Style.label("Personalizza sfondo", "Personalise wallpaper")
                            onClicked: widgets.settingsRequested("wallpaper")
                        }

                    }

                    Rectangle {
                        width: parent.width
                        height: 144
                        radius: 8
                        color: Style.card
                        border.color: Style.cardStroke

                        Text {
                            x: 16
                            y: 16
                            text: Style.label("Spazi di lavoro", "Workspaces")
                            color: Style.text
                            font.family: Style.font
                            font.pixelSize: 13
                        }

                        Text {
                            x: 16
                            y: 49
                            text: Style.label("Desktop attivo: ", "Active desktop: ") + Core.Compositore.scrivaniaAttiva
                            color: Style.muted
                            font.family: Style.font
                            font.pixelSize: 12
                        }

                        Button {
                            x: 10
                            y: 86
                            text: Style.label("Visualizza i desktop", "View desktops")
                            onClicked: widgets.overviewRequested()
                        }

                    }

                }

            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Style.label("Personalizza widget", "Customise widgets")
                onClicked: widgets.settingsRequested("preset")
            }

            Notizie {
                width: parent.width
                onPersonalizza: widgets.settingsRequested("preset")
            }

        }

    }

    Ui.Scorrimento {
        objectName: "windowsWidgetsScrollBar"
        tinta: Style.muted
        bersaglio: scroll
        anchors.right: parent.right
        anchors.rightMargin: 12
        y: scroll.y
        height: scroll.height
    }

}

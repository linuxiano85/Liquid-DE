import QtQuick
import "../core" as Core

Button {
    id: clock
    objectName: "windowsClockButton"
    property date date: new Date()
    property bool format24: Core.Ipc.get("clock.format24", true)
    property var locale: Qt.locale(Style.it ? "it_IT" : "en_GB")
    property int unread: Core.Notifications.unread
    property bool quiet: Core.Notifications.inSilenzio
    readonly property string timeText: Qt.formatTime(date, format24 ? "HH:mm" : "h:mm AP")
    // Qt abbrevia l'anno anche in italiano; la taskbar Windows lo mostra intero.
    // Conserviamo ordine e separatori della località, cambiando solo l'anno.
    readonly property string shortDateFormat: locale.dateFormat(Locale.ShortFormat).replace(/y+/g, "yyyy")
    readonly property string dateText: date.toLocaleDateString(locale, shortDateFormat)
    readonly property string notificationIcon: quiet ? "bellSnooze" : unread > 0 ? "bellFilled" : "bell"
    readonly property color notificationColor: !quiet && unread > 0 ? Style.accentIndicator : Style.barraTesto
    width: Math.max(100, labels.implicitWidth + 46)
    height: 40
    tooltip: {
        var description = Qt.formatDate(date, locale, Locale.LongFormat);
        if (quiet)
            description += "\n" + Style.label("Non disturbare attivo", "Do not disturb is on");
        if (unread > 0)
            description += "\n" + unread + (unread === 1
                ? Style.label(" notifica da leggere", " unread notification")
                : Style.label(" notifiche da leggere", " unread notifications"));
        return description;
    }
    Column {
        id: labels
        anchors.right: notification.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text {
            objectName: "windowsClockTime"
            anchors.right: parent.right
            text: clock.timeText
            color: Style.barraTesto
            font.family: Style.font
            font.pixelSize: 12
        }
        Text {
            objectName: "windowsClockDate"
            text: clock.dateText
            color: Style.barraTesto
            font.family: Style.font
            font.pixelSize: 12
        }
    }
    Glyph {
        id: notification
        objectName: "windowsNotificationIcon"
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        name: clock.notificationIcon
        color: clock.notificationColor
    }
}

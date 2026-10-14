import QtQuick

// Una sola posizione governa le due viste: invertire la navigazione riparte
// dal fotogramma corrente senza lasciare attiva la pagina precedente.
Item {
    id: navigation

    property bool active: false
    property bool allowed: true
    property bool ready: false
    property real progress: 0
    readonly property bool animating: motion.running

    function finish() {
        motion.stop();
        progress = active ? 1 : 0;
    }

    function navigate() {
        if (!ready)
            return ;

        motion.stop();
        if (!allowed || !Style.motionEnabled) {
            finish();
            return ;
        }
        motion.from = progress;
        motion.to = active ? 1 : 0;
        motion.duration = Math.max(1, Math.round(Style.flyoutDuration * Math.abs(motion.to - progress)));
        motion.start();
    }

    onActiveChanged: navigate()
    // Ricerca, chiusura e riapertura cambiano il contenuto subito: non devono
    // riavviare una navigazione rimasta sospesa o mostrare risultati obsoleti.
    onAllowedChanged: finish()
    Component.onCompleted: {
        finish();
        ready = true;
    }

    Connections {
        function onMotionEnabledChanged() {
            if (!Style.motionEnabled)
                navigation.finish();

        }

        target: Style
    }

    NumberAnimation {
        id: motion

        target: navigation
        property: "progress"
        easing.type: Easing.OutCubic
    }

}

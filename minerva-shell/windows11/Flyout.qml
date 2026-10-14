import QtQuick

// Keep the last rendered panel only until its exit frame. Input ownership is
// controlled separately by opened: closing never waits for the animation.
FocusScope {
    id: flyout
    property bool opened: false
    property bool presented: false
    property real progress: 0
    readonly property bool animating: motion.running
    property real travel: 24
    signal dismissed()
    visible: presented
    enabled: opened
    opacity: progress
    transform: Translate { y: flyout.travel * (1 - flyout.progress) }

    function finish() {
        progress = opened ? 1 : 0;
        if (!opened) {
            presented = false;
            dismissed();
        }
    }
    function animate() {
        motion.stop();
        if (opened) presented = true;
        if (!Style.motionEnabled || !presented) { finish(); return; }
        motion.from = progress;
        motion.to = opened ? 1 : 0;
        motion.duration = Math.max(1, Math.round(Style.flyoutDuration * Math.abs(motion.to - progress)));
        motion.start();
    }
    function replay() {
        if (!opened) return;
        motion.stop();
        progress = 0;
        animate();
    }
    function hideImmediately() {
        motion.stop();
        progress = 0;
        presented = false;
        dismissed();
    }
    onOpenedChanged: animate()
    Connections {
        target: Style
        function onMotionEnabledChanged() {
            if (!Style.motionEnabled) { motion.stop(); flyout.finish(); }
        }
    }
    NumberAnimation {
        id: motion; target: flyout; property: "progress"
        easing.type: Easing.OutCubic
        onFinished: flyout.finish()
    }
}

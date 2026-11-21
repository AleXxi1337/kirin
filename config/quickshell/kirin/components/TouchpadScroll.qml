import QtQuick

// Firefox-like touchpad scrolling for a Flickable (ListView, GridView, ...):
// follows the fingers, keeps gliding after they lift (momentum), and stretches
// past the ends with resistance, springing back. Qt on Wayland does none of
// this for touchpads; mouse wheels keep Qt's default behaviour.
//
// Put it inside the Flickable: TouchpadScroll { flickable: list }
WheelHandler {
    id: root

    required property Flickable flickable

    // Recent movement as [time ms, pixels], for the release velocity.
    property var samples: []

    acceptedDevices: PointerDevice.TouchPad
    target: null

    function finish(): void {
        endTimer.stop();
        const f = flickable;
        const now = Date.now();
        const recent = samples.filter(s => now - s[0] < 100);
        samples = [];

        if (f.contentY < f.originY || f.contentY > f.originY + Math.max(0, f.contentHeight - f.height)) {
            f.returnToBounds();
            return;
        }
        if (recent.length < 2)
            return;
        const span = Math.max(16, recent[recent.length - 1][0] - recent[0][0]);
        const distance = recent.reduce((sum, s) => sum + s[1], 0);
        const velocity = distance / span * 1000;
        if (Math.abs(velocity) > 150)
            f.flick(0, velocity);
    }

    onWheel: event => {
        const f = flickable;
        const dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 4;
        f.cancelFlick();

        const top = f.originY;
        const bottom = f.originY + Math.max(0, f.contentHeight - f.height);
        let y = f.contentY - dy;
        // Past an end the content follows the fingers less and less.
        if (y < top)
            y = f.contentY < top ? f.contentY - dy * Math.max(0.1, 1 - (top - f.contentY) / 150) * 0.5 : top - (top - y) * 0.5;
        else if (y > bottom)
            y = f.contentY > bottom ? f.contentY - dy * Math.max(0.1, 1 - (f.contentY - bottom) / 150) * 0.5 : bottom + (y - bottom) * 0.5;
        f.contentY = y;

        const now = Date.now();
        samples = samples.filter(s => now - s[0] < 150).concat([[now, dy]]);
        event.accepted = true;

        // Fingers lifted (Wayland sends ScrollEnd), or events just stopped.
        if (event.phase === Qt.ScrollEnd)
            finish();
        else
            endTimer.restart();
    }

    property Timer endTimer: Timer {
        interval: 80
        onTriggered: root.finish()
    }
}

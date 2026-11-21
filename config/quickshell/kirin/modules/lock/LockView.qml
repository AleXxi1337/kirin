pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.components
import qs.services

// What the lock screen shows on one monitor (Lock.qml has the session and
// the state). Kept apart from the session so a login screen can use it too.
//
// The lock screen is see-through: Hyprland draws the desktop under it
// (misc.session_lock_xray), an empty workspace by then, so the wallpaper
// (playing on, if it's a video) shows as it was.
//
// Clock stage, after a locked Pixel: the wallpaper itself (so locking looks
// like the windows going away), the date over a large stacked clock in the
// accent colour, and a hint at the bottom. A key or a
// click swipes it up to the password stage (Escape swipes back down).
// Password stage, after macOS: the wallpaper blurred and dimmed, the time
// small at the top, a round picture, the user's name and a pill-shaped
// field under it that shakes on a wrong password.
Item {
    id: root

    // Lock.qml's state: stage, buffer, checking, failures, message,
    // capsLock, layout, unlocking; wake(), submit(), handleKey(event).
    required property var ctx
    property ShellScreen screen: null
    // The primary monitor's view has the clock, the field and the status;
    // the others only the wallpaper, blurring and clearing along with it.
    property bool main: true

    // Played its way out after the password was right.
    signal unlocked

    readonly property bool password: ctx.stage === "password"
    readonly property bool unlocking: ctx.unlocking

    // --- Choreography ----------------------------------------------------------
    // Every element has a Stage: it comes in (0 → 1) when `on`, after its
    // delay, and goes (1 → 0) when not, after its own. Staggered delays make
    // the elements arrive and leave one after another, not all at once.

    component Stage: QtObject {
        id: st

        property bool on: false
        property int delayIn: 0
        property int delayOut: 0
        property real progress: on ? 1 : 0

        Behavior on progress {
            SequentialAnimation {
                PauseAnimation {
                    duration: st.on ? st.delayIn : st.delayOut
                }
                NumberAnimation {
                    duration: st.on ? 560 : 260
                    easing.type: st.on ? Easing.OutQuint : Easing.InCubic
                }
            }
        }
    }

    // Set a moment after the first frame is on screen (not after creation:
    // a new window takes a while to set up its graphics, which would eat
    // the start of the animations), so that frame shows the plain wallpaper
    // (as the desktop had it) and everything comes in over it.
    property bool appeared: false

    Connections {
        target: root.Window.window
        enabled: !root.appeared && !appear.running

        function onFrameSwapped(): void {
            appear.start();
        }
    }

    Timer {
        id: appear

        interval: 60
        onTriggered: root.appeared = true
    }

    // Both stages' elements are in while the lock screen is up; which one
    // is seen is the swipe between them (page).
    // Going to sleep, nothing comes in: it goes dark instead (below).
    readonly property bool asleep: ctx.asleep
    // Locked at logging in: black until the dark lifts, then as waking.
    readonly property bool booting: ctx.fromBoot
    readonly property bool clockOn: appeared && !unlocking && !asleep && !booting
    readonly property bool passwordOn: appeared && !unlocking && !asleep && !booting
    readonly property int handover: 80

    // The swipe: 0 the clock page, 1 the password page. The clock page goes
    // up and fades as the password page comes up from below, like swiping
    // a phone's lock screen; back down the other way. No overshoot: the
    // blur follows it, and a blur amount past 0 blurs again.
    property real page: password ? 1 : 0

    Behavior on page {
        // Turned while dark for sleep: at once, nothing to see.
        enabled: !root.asleep

        NumberAnimation {
            duration: 560
            easing.type: Easing.OutQuint
        }
    }

    // Blur and dim for the password stage, gone again while unlocking so the
    // desktop comes back as it was. An even curve: an overshoot past 0 made
    // the blur's amount negative, which blurs again.
    readonly property real fx: page * (1 - gone)
    // The blurred copy of the wallpaper is wanted (loaded only then: the
    // lock screen itself is see-through, the desktop shows under it).
    readonly property bool blurred: password || fx > 0

    // 0 … 1 as the blur and dim go while unlocking.
    property real gone: unlocking ? 1 : 0

    Behavior on gone {
        NumberAnimation {
            duration: 480
            easing.type: Easing.InOutCubic
        }
    }

    // The light dim for the text over the wallpaper.
    property real dim: appeared && !unlocking ? 1 : 0

    Behavior on dim {
        NumberAnimation {
            duration: 480
            easing.type: Easing.InOutCubic
        }
    }

    Connections {
        target: root.ctx

        function onUnlockingChanged(): void {
            if (root.ctx.unlocking)
                leave.start();
        }

        function onFailuresChanged(): void {
            shake.restart();
        }
    }

    // Everything has gone: the session can unlock.
    Timer {
        id: leave

        interval: 620
        onTriggered: root.unlocked()
    }

    SystemClock {
        id: clock

        precision: SystemClock.Seconds
    }

    // ~/.face: the user's picture, if there's one.
    Process {
        id: hasFace

        property bool exists: false

        running: true
        command: ["test", "-e", `${Quickshell.env("HOME")}/.face`]
        onExited: code => exists = code === 0
    }

    readonly property string clockFamily: Theme.clockFamily
    // Light text over the wallpaper, whatever the scheme's mode.
    readonly property color ink: "#f4f1f6"
    readonly property color inkDim: Qt.alpha(ink, 0.72)

    // --- Wallpaper -------------------------------------------------------------

    // For the password stage's blur: this monitor's part of the wallpaper,
    // cut as the desktop does (modules/background): spanning, one picture
    // over all the monitors as they're laid out, each showing its own
    // slice; else the whole picture on each. Drawn into a layer of this
    // monitor's size, so the blur only works on what's seen.
    Item {
        id: wallpaper

        anchors.fill: parent
        clip: true
        visible: false
        layer.enabled: true

        Image {
            id: picture

            readonly property bool span: Config.wallpaper.span && root.screen !== null
            readonly property real dpr: root.screen?.devicePixelRatio ?? 1

            x: span ? Wallpaper.desktop.x - root.screen.x : 0
            y: span ? Wallpaper.desktop.y - root.screen.y : 0
            width: span ? Wallpaper.desktop.width : root.width
            height: span ? Wallpaper.desktop.height : root.height
            source: root.blurred && Wallpaper.displayed ? `file://${Wallpaper.fileFor(Wallpaper.displayed)}` : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(width * dpr, height * dpr)
            asynchronous: true
        }

        // A video wallpaper plays under the blur too, over its first frame
        // (the picture): from the desktop's own player (Kirin.Video), the
        // same frames as the desktop under it; without the module, a player
        // of its own on the shared timeline. Paused like the desktop by the
        // power profile.
        Loader {
            anchors.fill: picture
            active: root.blurred && Wallpaper.isVideo(Wallpaper.displayed)
            source: Wallpaper.sharedPlayers ? "../background/SharedVideoLayer.qml" : "../background/VideoLayer.qml"
            onLoaded: {
                item.path = Qt.binding(() => Wallpaper.displayed);
                item.playing = Qt.binding(() => Wallpaper.videosAllowed);
            }
        }
    }

    // The wallpaper blurred and dimmed, faded in over the desktop for the
    // password stage, out again for the clock and while unlocking.
    MultiEffect {
        anchors.fill: parent
        visible: root.fx > 0
        opacity: root.fx
        source: wallpaper
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        blur: 1
        brightness: -0.12
    }

    // A little dim at the top and bottom for the text, more while typing.
    Rectangle {
        anchors.fill: parent
        opacity: root.dim
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha("black", 0.28 + 0.12 * root.fx)
            }
            GradientStop {
                position: 0.45
                color: Qt.alpha("black", 0.05 + 0.2 * root.fx)
            }
            GradientStop {
                position: 1
                color: Qt.alpha("black", 0.3 + 0.12 * root.fx)
            }
        }
    }

    // --- Input -------------------------------------------------------------------

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            root.ctx.handleKey(event);
            event.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.ctx.wake()
    }

    // --- Status: keyboard layout and battery, top right ------------------------

    Row {
        visible: root.main
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.sp(24)
        spacing: Theme.sp(14)
        opacity: status.progress

        readonly property Stage status: Stage {
            id: status

            on: root.appeared && !root.unlocking
            delayIn: 360
        }

        StyledText {
            visible: root.ctx.layout !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.ctx.layout
            font.pixelSize: Theme.size.labelLarge
            font.weight: Font.Bold
            color: root.inkDim
        }

        Row {
            readonly property var device: UPower.displayDevice
            readonly property real level: Math.max(0, Math.min(1, device?.percentage ?? 0))

            visible: device?.isLaptopBattery ?? false
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.sp(4)

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: UPower.onBattery ? `battery_${Math.round(parent.level * 6)}_bar` : "battery_charging_full"
                fill: true
                size: 18
                rotation: 90
                color: root.inkDim
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: `${Math.round(parent.level * 100)}%`
                font.pixelSize: Theme.size.labelLarge
                font.weight: Font.Medium
                color: root.inkDim
            }
        }
    }

    // --- Clock page --------------------------------------------------------------

    Item {
        id: clockPage

        width: root.width
        height: root.height
        y: -root.page * root.height * 0.45
        // Leaving, it's gone in the first third of the swipe, so it doesn't
        // linger under the page coming in.
        opacity: root.password ? Math.max(0, 1 - root.page * 3) : 1 - root.page
        visible: root.main && opacity > 0

        Column {
            id: bigClock

            anchors.horizontalCenter: parent.horizontalCenter
            // Upper part of the screen, like the phone's.
            y: root.height * 0.14
            spacing: Theme.sp(6)

            // Comes in from below.
            function lift(p: real): real {
                return (1 - p) * Theme.sp(28);
            }

            readonly property real digitSize: Math.round(Math.min(root.height * 0.2, root.width * 0.16))

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(clock.date, "dddd, d MMMM")
                font.family: root.clockFamily
                font.pixelSize: Theme.size.titleMedium
                font.weight: Font.Medium
                color: root.ink
                opacity: dateStage.progress
                visible: opacity > 0
                transform: Translate {
                    y: bigClock.lift(dateStage.progress)
                }

                readonly property Stage stage: Stage {
                    id: dateStage

                    on: root.clockOn
                    delayIn: root.handover
                    delayOut: 60
                }
            }

            // Hours over minutes, tight, rounded.
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: -Math.round(bigClock.digitSize * 0.36)

                Repeater {
                    model: [Qt.formatTime(clock.date, "HH"), Qt.formatTime(clock.date, "mm")]

                    Text {
                        id: digits

                        required property string modelData
                        required property int index

                        readonly property Stage stage: Stage {
                            id: digitStage

                            on: root.clockOn
                            delayIn: root.handover + 60 + digits.index * 70
                            delayOut: 30 - digits.index * 30
                        }

                        anchors.horizontalCenter: parent.horizontalCenter
                        opacity: digitStage.progress
                        visible: opacity > 0
                        scale: 0.92 + 0.08 * digitStage.progress
                        transform: Translate {
                            y: bigClock.lift(digitStage.progress) * (1 + digits.index * 0.4)
                        }
                        text: modelData
                        font.family: root.clockFamily
                        font.pixelSize: bigClock.digitSize
                        font.variableAxes: ({ ROND: 100, wght: 700, opsz: 144 })
                        font.features: {
                            "tnum": 1
                        }
                        color: Theme.m3primary
                        renderType: Text.QtRendering
                    }
                }
            }

            // What's playing (Media): the source's icon (Spotify, a
            // browser; a note for others), the artist — the title.
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: nowPlaying.width
                height: nowPlaying.height + Theme.sp(10)
                visible: Config.media.lockScreen && Media.hasTrack && opacity > 0
                opacity: musicStage.progress
                transform: Translate {
                    y: bigClock.lift(musicStage.progress)
                }

                readonly property Stage stage: Stage {
                    id: musicStage

                    on: root.clockOn && Config.media.lockScreen && Media.hasTrack
                    delayIn: root.handover + 220
                    delayOut: 0
                }

                Row {
                    id: nowPlaying

                    y: Theme.sp(10)
                    spacing: Theme.sp(8)

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.sp(22)
                        height: width

                        SymbolIcon {
                            visible: Media.source !== ""
                            anchors.centerIn: parent
                            // Symbols have a margin round the shape.
                            width: Math.round(parent.width * 1.2)
                            height: width
                            appId: Media.sourceApp
                            entry: {
                                DesktopEntries.applications.values;
                                return DesktopEntries.heuristicLookup(Media.sourceApp);
                            }
                            color: root.ink
                        }

                        MaterialIcon {
                            visible: Media.source === ""
                            anchors.centerIn: parent
                            text: "music_note"
                            fill: true
                            size: Theme.sp(20)
                            color: root.ink
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, root.width * 0.5)
                        text: Media.artist ? `${Media.artist} — ${Media.title}` : Media.title
                        font.family: root.clockFamily
                        font.pixelSize: Theme.size.titleMedium
                        font.weight: Font.Medium
                        color: root.ink
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // Lock and a hint, at the bottom.
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.sp(40)
            spacing: Theme.sp(10)
            opacity: hintStage.progress
            visible: opacity > 0
            transform: Translate {
                y: (1 - hintStage.progress) * Theme.sp(16)
            }

            readonly property Stage stage: Stage {
                id: hintStage

                on: root.clockOn
                delayIn: root.handover + 260
            }

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "lock"
                fill: true
                size: 24
                color: root.ink
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Press any key to unlock"
                font.pixelSize: Theme.size.labelLarge
                color: root.inkDim
            }
        }

    }

    // --- Password page -----------------------------------------------------------

    Item {
        id: passwordPage

        width: root.width
        height: root.height
        y: (1 - root.page) * root.height * 0.3
        opacity: root.password ? root.page : Math.max(0, 1 - (1 - root.page) * 3)
        visible: root.main && opacity > 0

        // The time, small, at the top.
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.sp(56)
            opacity: timeStage.progress
            visible: opacity > 0
            // Goes up, a little larger, when unlocking.
            scale: root.unlocking ? 1 + 0.06 * (1 - timeStage.progress) : 1
            transform: Translate {
                y: (1 - timeStage.progress) * (root.unlocking ? -Theme.sp(20) : 0)
            }

            readonly property Stage stage: Stage {
                id: timeStage

                on: root.passwordOn
                delayIn: root.handover
                delayOut: 90
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(clock.date, "dddd, d MMMM")
                font.family: root.clockFamily
                font.pixelSize: Theme.size.titleMedium
                font.weight: Font.Medium
                color: root.inkDim
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatTime(clock.date, "HH:mm")
                font.family: root.clockFamily
                font.pixelSize: Math.round(Theme.sp(88))
                font.variableAxes: ({ ROND: 100, wght: 600, opsz: 144 })
                font.features: {
                    "tnum": 1
                }
                color: root.ink
                renderType: Text.QtRendering
            }
        }

        Column {
            id: login

            anchors.horizontalCenter: parent.horizontalCenter
            y: root.height * 0.62 - height / 2
            spacing: Theme.sp(14)

            // Unlocking, its rows go up and a little larger, one by one.
            function lift(p: real): real {
                return (1 - p) * (root.unlocking ? -Theme.sp(16) : 0);
            }

            function grow(p: real): real {
                return root.unlocking ? 1 + 0.08 * (1 - p) : 1;
            }

            // The user's picture (~/.face), else their initial.
            Rectangle {
                readonly property Stage stage: Stage {
                    id: faceStage

                    on: root.passwordOn
                    delayIn: root.handover + 60
                    delayOut: 90
                }

                opacity: faceStage.progress
                scale: login.grow(faceStage.progress)
                transform: Translate {
                    y: login.lift(faceStage.progress)
                }
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.sp(88)
                height: width
                radius: width / 2
                color: Theme.m3primaryContainer
                border.width: 1
                border.color: Qt.alpha("white", 0.25)

                readonly property string user: Quickshell.env("USER") || "user"

                StyledText {
                    visible: face.status !== Image.Ready
                    anchors.centerIn: parent
                    text: parent.user.charAt(0).toUpperCase()
                    font.family: root.clockFamily
                    font.pixelSize: parent.width * 0.42
                    font.weight: Font.Medium
                    color: Theme.m3onPrimaryContainer
                }

                Image {
                    id: face

                    anchors.fill: parent
                    anchors.margins: 1
                    source: hasFace.exists ? `file://${Quickshell.env("HOME")}/.face` : ""
                    sourceSize: Qt.size(width * 2, height * 2)
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                }

                MultiEffect {
                    visible: face.status === Image.Ready
                    anchors.fill: face
                    source: face
                    maskEnabled: true
                    maskSource: faceMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }

                Item {
                    id: faceMask

                    anchors.fill: face
                    layer.enabled: true
                    visible: false

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                    }
                }
            }

            StyledText {
                readonly property Stage stage: Stage {
                    id: nameStage

                    on: root.passwordOn
                    delayIn: root.handover + 120
                    delayOut: 60
                }

                opacity: nameStage.progress
                scale: login.grow(nameStage.progress)
                transform: Translate {
                    y: login.lift(nameStage.progress)
                }
                anchors.horizontalCenter: parent.horizontalCenter
                text: Quickshell.env("USER") || "user"
                font.family: root.clockFamily
                font.pixelSize: Theme.size.titleMedium
                font.weight: Font.DemiBold
                color: root.ink
            }

            // The field: frosted pill, dots for what's typed.
            Rectangle {
                id: field

                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.sp(240)
                height: Theme.sp(36)
                radius: height / 2
                color: Qt.alpha("white", root.ctx.checking ? 0.12 : 0.18)
                border.width: 1
                border.color: Qt.alpha("white", root.ctx.message ? 0 : 0.22)

                Behavior on color {
                    CAnim {}
                }

                readonly property Stage stage: Stage {
                    id: fieldStage

                    on: root.passwordOn
                    delayIn: root.handover + 180
                    delayOut: 30
                }

                opacity: fieldStage.progress
                scale: login.grow(fieldStage.progress)
                // Shakes sideways on a wrong password.
                transform: [
                    Translate {
                        id: shift
                    },
                    Translate {
                        y: login.lift(fieldStage.progress)
                    }
                ]

                SequentialAnimation {
                    id: shake

                    loops: 1
                    NumberAnimation {
                        target: shift
                        property: "x"
                        to: -12
                        duration: 50
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: shift
                        property: "x"
                        to: 10
                        duration: 80
                        easing.type: Easing.InOutQuad
                    }
                    NumberAnimation {
                        target: shift
                        property: "x"
                        to: -7
                        duration: 70
                        easing.type: Easing.InOutQuad
                    }
                    NumberAnimation {
                        target: shift
                        property: "x"
                        to: 4
                        duration: 60
                        easing.type: Easing.InOutQuad
                    }
                    NumberAnimation {
                        target: shift
                        property: "x"
                        to: 0
                        duration: 50
                        easing.type: Easing.OutQuad
                    }
                }

                StyledText {
                    visible: root.ctx.buffer.length === 0 && !root.ctx.checking
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.sp(16)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Enter Password"
                    font.pixelSize: Theme.size.bodyMedium
                    color: Qt.alpha("white", 0.55)
                }

                // One dot per character, cut off at the field's end.
                Item {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.sp(16)
                    anchors.right: trailing.left
                    anchors.rightMargin: Theme.sp(6)
                    anchors.verticalCenter: parent.verticalCenter
                    height: 8
                    clip: true
                    opacity: root.ctx.checking ? 0.5 : 1

                    // A fixed set of dots, each shown while there's a character
                    // for it: typing adds one dot and leaves the others be (a
                    // model of the length recreated them all on every key).
                    Repeater {
                        model: 32

                        Rectangle {
                            required property int index
                            readonly property bool on: index < root.ctx.buffer.length

                            x: index * 13
                            width: 8
                            height: 8
                            radius: 4
                            color: root.ink
                            scale: on ? 1 : 0
                            opacity: on ? 1 : 0

                            Behavior on scale {
                                Anim {
                                    type: Anim.FastSpatial
                                }
                            }
                            Behavior on opacity {
                                Anim {
                                    type: Anim.FastEffects
                                }
                            }
                        }
                    }
                }

                // Caps Lock, then the go button / a spinner.
                Row {
                    id: trailing

                    anchors.right: parent.right
                    anchors.rightMargin: Theme.sp(4)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.sp(2)

                    MaterialIcon {
                        visible: root.ctx.capsLock
                        anchors.verticalCenter: parent.verticalCenter
                        text: "keyboard_capslock_badge"
                        size: 18
                        color: root.inkDim
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: field.height - Theme.sp(8)
                        height: width
                        radius: width / 2
                        color: Qt.alpha("white", 0.2)
                        opacity: root.ctx.buffer.length > 0 || root.ctx.checking ? 1 : 0

                        Behavior on opacity {
                            Anim {
                                type: Anim.FastEffects
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.ctx.submit()
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: root.ctx.checking ? "progress_activity" : "arrow_forward"
                            size: 18
                            color: root.ink

                            RotationAnimation on rotation {
                                running: root.ctx.checking
                                from: 0
                                to: 360
                                duration: 900
                                loops: Animation.Infinite
                            }
                        }
                    }
                }
            }

            // Wrong password and such; Caps Lock as a reminder under it.
            StyledText {
                readonly property Stage stage: Stage {
                    id: messageStage

                    on: root.passwordOn
                    delayIn: root.handover + 240
                }

                opacity: messageStage.progress
                transform: Translate {
                    y: login.lift(messageStage.progress)
                }
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.ctx.message || (root.ctx.capsLock ? "Caps Lock is on" : " ")
                font.pixelSize: Theme.size.labelLarge
                font.weight: root.ctx.message ? Font.Medium : Font.Normal
                color: root.ctx.message ? "#ffb4ab" : root.inkDim
            }
        }
    }

    // Going to sleep: dark over everything once the windows have gone;
    // lifted on waking, as the clock comes in.
    Rectangle {
        anchors.fill: parent
        color: "black"
        // From the first frame on (made asleep, it'd start black). At
        // logging in, black from the start: made with it on, no fade in.
        opacity: (root.asleep && root.appeared) || root.booting ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: 550
                easing.type: Easing.InOutCubic
            }
        }
    }
}

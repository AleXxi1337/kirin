pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

// Wi-Fi and Bluetooth come back on or off as they were: their state is kept
// in ~/.local/state/kirin/radios.json whenever it changes (from kirin or
// anything else), and put back when the session starts (a restart, a
// reboot), whatever NetworkManager and BlueZ start with (BlueZ powers the
// adapter on at boot).
// The state is kept only once it's been put back and things have settled
// (SETTLE): what the system starts with isn't the user's choice.
// Bluetooth's state is the adapter's power while there is one; blocked by
// rfkill, it has no adapter and nothing is kept.
Singleton {
    id: root

    readonly property string path: `${Wallpaper.stateDir}/radios.json`
    readonly property int settle: 8000

    // Saved: true / false, or undefined when not known yet.
    property var saved: ({})
    property bool restored: false

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    // Read by shell.qml to start the service at once.
    readonly property bool running: true

    FileView {
        id: file

        path: root.path
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                root.saved = JSON.parse(text()) ?? {};
            } catch (e) {
                root.saved = {};
            }
        }
        onLoadFailed: root.saved = {}
    }

    function save(key: string, value: bool): void {
        if (!restored || saved[key] === value)
            return;
        const next = Object.assign({}, saved);
        next[key] = value;
        saved = next;
        file.setText(JSON.stringify(next) + "\n");
    }

    // --- Putting it back ------------------------------------------------------

    function restoreWifi(): void {
        if (saved.wifi === undefined || !Network.loaded)
            return;
        if (Network.wifiEnabled !== saved.wifi)
            Network.setWifiEnabled(saved.wifi);
    }

    function restoreBluetooth(): void {
        if (saved.bluetooth === undefined)
            return;
        if (adapter) {
            if (adapter.enabled !== saved.bluetooth)
                adapter.enabled = saved.bluetooth;
        } else if (saved.bluetooth) {
            // Blocked (no adapter then): unblocked, and on when it's back.
            Quickshell.execDetached(["rfkill", "unblock", "bluetooth"]);
        }
    }

    Component.onCompleted: {
        restoreWifi();
        restoreBluetooth();
        settleTimer.start();
    }

    // NetworkManager read late, the adapter come late (bluetoothd starting):
    // put back then, while still settling.
    Connections {
        target: Network

        function onLoadedChanged(): void {
            if (!root.restored)
                root.restoreWifi();
        }

        function onWifiEnabledChanged(): void {
            root.save("wifi", Network.wifiEnabled);
        }
    }

    onAdapterChanged: {
        if (!restored)
            restoreBluetooth();
    }

    Connections {
        target: root.adapter
        ignoreUnknownSignals: true

        function onEnabledChanged(): void {
            if (!root.restored)
                // BlueZ powering it on at start: back as it was.
                root.restoreBluetooth();
            else
                root.save("bluetooth", root.adapter.enabled);
        }
    }

    // While settling, put back once a second (the adapter can be there and
    // not take a change yet); then keep the state from there on.
    Timer {
        id: settleTimer

        property int ticks: 0

        interval: 1000
        repeat: true
        onTriggered: {
            root.restoreWifi();
            root.restoreBluetooth();
            if (++ticks * interval < root.settle)
                return;
            stop();
            root.restored = true;
            // Nothing saved yet (first run): what it is now. (Only then: a
            // state just being put back may not have changed yet.)
            if (root.saved.wifi === undefined && Network.loaded)
                root.save("wifi", Network.wifiEnabled);
            if (root.saved.bluetooth === undefined && root.adapter)
                root.save("bluetooth", root.adapter.enabled);
        }
    }
}

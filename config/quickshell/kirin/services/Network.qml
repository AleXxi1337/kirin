pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// NetworkManager through nmcli. Quickshell's own Networking module (0.3.0)
// crashes the shell when an access point disappears during a scan, so this
// runs nmcli as separate processes instead, refreshing on `nmcli monitor`.
Singleton {
    id: root

    // Wi-Fi radio (Settings / airplane mode) and a Wi-Fi device present.
    property bool wifiEnabled: false
    // The state has been read from NetworkManager at least once.
    property bool loaded: false
    property bool wifiHardware: true
    property string wifiDevice: ""
    // A wired connection is up.
    property bool wired: false
    // NetworkManager's connectivity check: full | limited | portal | none | unknown
    property string connectivity: "unknown"

    // Networks around, one per SSID (the strongest access point):
    // [{ ssid, signal: 0–100, security, secured, active, known }]
    property var networks: []
    // The connected network (kept while the list is cleared for a rescan).
    property var active: null
    // Saved Wi-Fi connection names.
    property var known: []

    // SSID being connected to by us, and the last error for it.
    property string connecting: ""
    property string error: ""
    property string errorSsid: ""
    // Set when the last attempt failed for want of a (right) password.
    property bool needsPassword: false

    function refresh(): void {
        if (state.running)
            state.again = true;
        else
            state.running = true;
    }

    // A scan for networks; `scanning` while it runs, and a moment after for
    // the results to come in.
    property bool scanning: scanner.running || scanSettle.running
    // Cleared for a fresh scan: the list stays empty until it's done.
    property bool clearing: false

    // `clear`: empty the list first and show only what this scan finds.
    function rescan(clear: bool): void {
        if (!wifiEnabled || scanner.running)
            return;
        if (clear) {
            clearing = true;
            networks = [];
        }
        scanner.running = true;
    }

    function setWifiEnabled(on: bool): void {
        wifiEnabled = on;
        Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]);
    }

    // Saved or open networks connect directly; others need a password.
    function connect(ssid: string, password: string): void {
        error = "";
        errorSsid = "";
        needsPassword = false;
        connecting = ssid;
        const net = networks.find(n => n.ssid === ssid);
        if (known.includes(ssid) && !password) {
            connector.password = "";
            connector.command = ["nmcli", "--wait", "30", "connection", "up", "id", ssid];
        } else {
            // --ask reads the password from stdin, so it isn't on the command line.
            connector.password = password;
            connector.command = ["nmcli", "--wait", "30", ...(password ? ["--ask"] : []), "device", "wifi", "connect", ssid, ...(root.wifiDevice ? ["ifname", root.wifiDevice] : [])];
        }
        connector.running = true;
    }

    function disconnect(): void {
        if (active)
            Quickshell.execDetached(["nmcli", "connection", "down", "id", active.ssid]);
    }

    function forget(ssid: string): void {
        Quickshell.execDetached(["nmcli", "connection", "delete", "id", ssid]);
    }

    // nmcli -t -e yes: fields split by ':', with ':' and '\' escaped.
    function fields(line: string): var {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) {
                cur += line[++i];
            } else if (c === ":") {
                out.push(cur);
                cur = "";
            } else {
                cur += c;
            }
        }
        out.push(cur);
        return out;
    }

    Component.onCompleted: refresh()

    // Everything in one go: radio, devices, saved connections, networks.
    Process {
        id: state

        property bool again: false

        command: ["sh", "-c", "nmcli -t -e yes -f WIFI,WIFI-HW,CONNECTIVITY general; echo @devices; nmcli -t -e yes -f DEVICE,TYPE,STATE dev; echo @known; nmcli -t -e yes -f NAME,TYPE con show; echo @networks; nmcli -t -e yes -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list --rescan no"]
        onRunningChanged: {
            if (!running && again) {
                again = false;
                running = true;
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                let section = "general";
                const known = [];
                const bySsid = {};
                let wifiDevice = "", wired = false;
                for (const line of text.split("\n")) {
                    if (!line)
                        continue;
                    if (line.startsWith("@")) {
                        section = line.slice(1);
                        continue;
                    }
                    const f = root.fields(line);
                    if (section === "general") {
                        root.wifiEnabled = f[0] === "enabled";
                        root.loaded = true;
                        root.wifiHardware = f[1] === "enabled";
                        root.connectivity = f[2] || "unknown";
                    } else if (section === "devices") {
                        if (f[1] === "wifi" && !wifiDevice)
                            wifiDevice = f[0];
                        if (f[1] === "ethernet" && f[2] === "connected")
                            wired = true;
                    } else if (section === "known") {
                        if (f[1] === "802-11-wireless")
                            known.push(f[0]);
                    } else if (section === "networks") {
                        const ssid = f[1];
                        if (!ssid)
                            continue;
                        const n = {
                            ssid,
                            signal: parseInt(f[2]) || 0,
                            security: f[3] || "",
                            secured: !!f[3] && f[3] !== "--",
                            active: f[0] === "*"
                        };
                        const prev = bySsid[ssid];
                        if (!prev || n.active || (!prev.active && n.signal > prev.signal))
                            bySsid[ssid] = n;
                    }
                }
                root.wifiDevice = wifiDevice;
                root.wired = wired;
                root.known = known;
                const networks = Object.values(bySsid).map(n => Object.assign(n, {
                        known: known.includes(n.ssid)
                    }));
                root.active = networks.find(n => n.active) ?? null;
                if (!root.clearing)
                    root.networks = networks;
            }
        }
    }

    Process {
        id: scanner

        command: ["nmcli", "device", "wifi", "rescan"]
        onExited: scanSettle.restart()
    }

    Timer {
        id: scanSettle

        // Results trickle in after the scan request returns.
        interval: 2500
        onTriggered: {
            root.clearing = false;
            root.refresh();
        }
    }

    Process {
        id: connector

        property string password: ""
        property string ssid: ""

        stdinEnabled: true
        onStarted: {
            ssid = root.connecting;
            if (password) {
                write(password + "\n");
                password = "";
            }
        }
        onExited: code => {
            if (code !== 0) {
                const message = err.text.trim();
                root.errorSsid = ssid;
                root.needsPassword = /secret|password|802-1x|psk|Secrets were required/i.test(message);
                root.error = root.needsPassword ? "Wrong or missing password" : "Couldn't connect";
            }
            root.connecting = "";
            root.refresh();
        }

        stderr: StdioCollector {
            id: err
        }
    }

    // NetworkManager tells about every change; refresh shortly after.
    Process {
        id: monitor

        running: true
        // Goes when kirin does (--pdeathsig): killed rather than quit,
        // kirin left it running, and they piled up (68 by a reboot).
        command: ["setpriv", "--pdeathsig", "TERM", "nmcli", "monitor"]
        stdout: SplitParser {
            onRead: debounce.restart()
        }
        // Restarts if it ever exits.
        onExited: restartMonitor.start()
    }

    Timer {
        id: restartMonitor

        interval: 3000
        onTriggered: monitor.running = true
    }

    Timer {
        id: debounce

        interval: 300
        onTriggered: root.refresh()
    }

    // Signal strength changes aren't announced; poll gently.
    Timer {
        running: true
        repeat: true
        interval: 15000
        onTriggered: root.refresh()
    }
}

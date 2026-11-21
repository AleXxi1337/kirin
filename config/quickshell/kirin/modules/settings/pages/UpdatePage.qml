pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.services

// Updating kirin (services/Updates.qml): the versions, what's new, the
// update itself; on NixOS with kirin's module also the system's settings
// (auto update, committing flake.lock, cleaning up old systems), hidden
// elsewhere.
ColumnLayout {
    id: root

    readonly property var u: Updates
    readonly property string flake: u.system?.flake ?? "/etc/nixos"
    readonly property string host: u.system?.host ?? ""

    function ago(ms: real): string {
        if (!ms)
            return "never";
        const m = Math.round((Date.now() - ms) / 60000);
        if (m < 1)
            return "just now";
        if (m < 60)
            return `${m} min ago`;
        const h = Math.round(m / 60);
        return h < 24 ? `${h} h ago` : `${Math.round(h / 24)} d ago`;
    }

    spacing: Theme.sp(24)

    Component.onCompleted: u.check()

    SettingsSection {
        title: "Kirin"

        SettingsRow {
            icon: root.u.available ? "system_update" : "verified"
            title: root.u.checking ? "Checking…" : root.u.updating ? "Updating…" : !root.u.present ? "No checkout" : root.u.noHistory ? "Not connected to the repository" : root.u.available ? "Update available" : "Kirin is up to date"
            subtitle: {
                if (!root.u.present)
                    return `${root.u.dir} isn't a kirin checkout.`;
                if (root.u.noHistory)
                    return `${root.u.dir} was copied without git history (offline at the first login). Connect it to get updates; its files are the same.`;
                const parts = [`Shell ${root.u.shortRev(root.u.head)}`];
                if (root.u.managed)
                    parts.push(`system ${root.u.shortRev(root.u.system.rev)}`);
                if (root.u.remote)
                    parts.push(`latest ${root.u.shortRev(root.u.remote)} (${root.u.upstream})`);
                parts.push(`checked ${root.ago(root.u.lastCheck)}`);
                return parts.join(" · ") + (root.u.fetchFailed ? " · the repository couldn't be reached" : "");
            }
            trailing: [
                FilledButton {
                    visible: root.u.noHistory
                    icon: "link"
                    text: "Connect"
                    onClicked: root.u.connect()
                },
                FilledButton {
                    visible: !root.u.noHistory
                    icon: "refresh"
                    text: "Check"
                    onClicked: root.u.check()
                }
            ]
        }

        // Changes of the user's in the way: no update until they're dealt with.
        SettingsRow {
            visible: root.u.dirty > 0
            icon: "warning"
            title: `${root.u.dirty} changed ${root.u.dirty === 1 ? "file" : "files"} in ${root.u.dir}`
            subtitle: "Updating waits for them. Stash puts them aside (git stash; back with git stash pop), or commit them."
            trailing: FilledButton {
                icon: "inventory_2"
                text: "Stash"
                onClicked: root.u.stash()
            }
        }

        SettingsRow {
            visible: root.u.ahead > 0
            icon: "warning"
            title: `${root.u.ahead} ${root.u.ahead === 1 ? "commit" : "commits"} of your own`
            subtitle: `Not on ${root.u.upstream}: updating waits for them. Push them, or rebase them onto it (git pull --rebase) in ${root.u.dir}.`
        }

        SettingsRow {
            visible: root.u.error !== ""
            icon: "error"
            title: "Couldn't update"
            subtitle: root.u.error
        }

        SettingsRow {
            visible: root.u.needsRelogin
            icon: "logout"
            title: "Log out to finish"
            subtitle: "Hyprland or the titlebar plugin was updated: they're loaded when the session starts."
        }
    }

    // What's new and the update.
    SettingsSection {
        visible: root.u.available
        title: "What's new"

        Repeater {
            model: root.u.commits.slice(0, 15)

            SettingsRow {
                required property var modelData

                icon: "commit"
                title: modelData.subject
                subtitle: `${modelData.rev} · ${new Date(modelData.time).toLocaleDateString()}`
            }
        }

        SettingsRow {
            visible: root.u.commits.length > 15
            icon: "more_horiz"
            title: `${root.u.commits.length - 15} more`
        }

        // NixOS, auto update off: the commands.
        SettingsRow {
            visible: root.u.managed && !root.u.autoUpdate && root.u.systemBehind
            icon: "terminal"
            title: "Update the system"
            subtitle: "With Flake auto update off, in a terminal:"

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: commands.implicitHeight + Theme.sp(24)
                radius: Theme.rounding.small
                color: Theme.m3surfaceContainerHighest

                StyledText {
                    id: commands

                    anchors.fill: parent
                    anchors.margins: Theme.sp(12)
                    text: `sudo nix flake update kirin --flake ${root.flake}\nsudo nixos-rebuild switch --flake ${root.flake}#${root.host}\ngit -C ${root.u.dir} merge --ff-only $(jq -r .rev /etc/kirin/system.json)`
                    font.family: "monospace"
                    wrapMode: Text.WrapAnywhere
                }
            }

            FilledButton {
                icon: "content_copy"
                text: "Copy"
                onClicked: Quickshell.execDetached(["wl-copy", commands.text])
            }
        }

        SettingsRow {
            visible: !(root.u.managed && !root.u.autoUpdate && root.u.systemBehind)
            icon: "download"
            title: root.u.managed && root.u.systemBehind ? "Update the system and the shell" : "Update the shell"
            subtitle: root.u.managed && root.u.systemBehind ? (root.u.systemChanges ? "Rebuilds the system: a few minutes. The shell restarts after." : "Rebuilds the system (nothing of it changed: quick). The shell restarts after.") : "The shell restarts after."
            trailing: FilledButton {
                opacity: root.u.clean && !root.u.updating ? 1 : 0.4
                enabled: root.u.clean && !root.u.updating
                icon: "download"
                text: root.u.updating ? "Updating…" : "Update"
                onClicked: root.u.update()
            }
        }

        // The system update's output.
        SettingsRow {
            visible: root.u.updating && root.u.log !== ""
            icon: "receipt_long"
            title: "Progress"

            StyledText {
                Layout.fillWidth: true
                text: root.u.log.trim().split("\n").slice(-12).join("\n")
                font.family: "monospace"
                font.pixelSize: Theme.size.labelMedium
                color: Theme.m3onSurfaceVariant
                wrapMode: Text.WrapAnywhere
            }
        }
    }

    // NixOS with kirin's module only.
    SettingsSection {
        visible: root.u.managed
        title: "System"

        SettingsRow {
            icon: "autorenew"
            title: "Flake auto update"
            subtitle: "Update kirin and the system on their own, once a day, without asking (your password once, to switch this). It builds whatever the repository holds, as root."
            trailing: ToggleSwitch {
                checked: root.u.autoUpdate
                onToggled: checked => root.u.setAutoUpdate(checked)
            }
        }

        SettingsRow {
            visible: root.u.flakeInGit
            icon: "commit"
            title: "Commit flake.lock after updating"
            subtitle: `${root.flake} is a git repository: the updated flake.lock is committed there (only it, not pushed).`
            trailing: ToggleSwitch {
                checked: Config.update.autoCommit
                onToggled: checked => Config.update.autoCommit = checked
            }
        }

        SettingsRow {
            icon: "cleaning_services"
            title: "Clean up old systems"
            subtitle: "After updating, keep only the last ones (the boot menu's), and free the space the rest take."
            trailing: ToggleSwitch {
                checked: Config.update.cleanup
                onToggled: checked => Config.update.cleanup = checked
            }

            SegmentedButtons {
                visible: Config.update.cleanup
                current: Config.update.keep
                options: [3, 5, 10].map(n => ({
                            value: n,
                            label: `Keep ${n}`
                        }))
                onSelected: value => Config.update.keep = value
            }
        }

        SettingsRow {
            icon: "delete_sweep"
            title: "Clean up now"
            subtitle: root.u.cleaning ? "Cleaning up…" : root.u.cleanupResult || `Keep the last ${Config.update.keep} systems, free the rest.`
            trailing: FilledButton {
                enabled: !root.u.cleaning
                opacity: enabled ? 1 : 0.4
                icon: "delete_sweep"
                text: "Clean up"
                onClicked: root.u.cleanupNow()
            }
        }
    }
}

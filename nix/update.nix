# Updating kirin on NixOS, for Settings → Update (services/Updates.qml).
#
#   kirin-update.service   updates the kirin input of the system's flake
#                          (as its owner, when it's a user's), rebuilds and
#                          switches to the system, then cleans up old ones
#                          (if asked). Sleep is held off meanwhile.
#   kirin-cleanup.service  keeps the last N systems (the boot menu's), and
#                          collects the garbage in the store.
#
# With "One-click system update" on (Settings → Update; /var/lib/kirin/auto-update,
# set through `pkexec kirin-auto-update on|off`, so a password once), the
# user may start them without a password (polkit): the Update button does,
# nothing starts them on its own. Off, kirin shows the commands instead.
# Their settings (cleanup, how many systems to keep) are the
# user's, in ~/.config/kirin/config.json (update.*): a flag and a number,
# checked here.
#
# The update trusts the repository: whatever it holds is built and switched
# to as root.
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kirin;
  flag = "/var/lib/kirin/auto-update";

  # The user's update settings, checked.
  settings = ''
    home=$(getent passwd ${lib.escapeShellArg cfg.user} | cut -d: -f6)
    conf="$home/.config/kirin/config.json"
    read_setting() { jq -r "$1" "$conf" 2>/dev/null || true; }
    # (jq's // takes false for missing: compared instead.)
    cleanup=$(read_setting '.update.cleanup != false')
    keep=$(read_setting '.update.keep // 5')
    case "$keep" in "" | *[!0-9]*) keep=5 ;; esac
    [ "$keep" -lt 1 ] && keep=1
    [ "$keep" -gt 50 ] && keep=50
  '';

  cleanupScript = ''
    set -eo pipefail
    ${settings}
    echo "==> Keeping the last $keep systems"
    nix-env --profile /nix/var/nix/profiles/system --delete-generations "+$keep"
    echo "==> Collecting garbage"
    nix-collect-garbage
    echo "==> Updating the boot menu"
    /run/current-system/bin/switch-to-configuration boot
  '';

  updateScript = ''
    set -eo pipefail
    ${settings}
    flake=${lib.escapeShellArg cfg.update.flake}
    host=${lib.escapeShellArg cfg.update.host}
    owner=$(stat -c %U "$flake")
    owner_home=$(getent passwd "$owner" | cut -d: -f6)
    as_owner() { runuser -u "$owner" -- env HOME="$owner_home" "$@"; }

    echo "==> Updating kirin in $flake"
    if [ -d "$flake/.git" ] && [ "$owner" != root ]; then
      # The owner's repository: updated as them (flake.lock stays theirs;
      # committing it is theirs too).
      as_owner nix flake update kirin --flake "$flake"

      # Built as them too: git won't open a repository root doesn't own
      # ("not owned by current user"; sudo passes SUDO_UID, a service
      # can't). Then made the system and switched to as root, as
      # nixos-rebuild switch does.
      echo "==> Building the system ($flake#$host)"
      system=$(as_owner nix build --no-link --print-out-paths "$flake#nixosConfigurations.\"$host\".config.system.build.toplevel")
      echo "==> Switching to $system"
      nix-env --profile /nix/var/nix/profiles/system --set "$system"
      "$system/bin/switch-to-configuration" switch
    else
      nix flake update kirin --flake "$flake"
      echo "==> Building the system ($flake#$host)"
      nixos-rebuild switch --flake "$flake#$host"
    fi

    if [ "$cleanup" = true ]; then
      ${cleanupScript}
    fi
    echo "==> Done"
  '';

  path = with pkgs; [
    config.nix.package
    config.system.build.nixos-rebuild
    git
    jq
    coreutils
    util-linux
    getent
    systemd
    bash
  ];

  service = name: script: {
    description = "kirin: ${name}";
    inherit path;
    environment.HOME = "/root";
    serviceConfig.Type = "oneshot";
    script = ''
      exec systemd-inhibit --what=sleep:shutdown --who=kirin --why=${lib.escapeShellArg name} \
        bash -c ${lib.escapeShellArg script}
    '';
  };
in
{
  options.kirin.update = {
    flake = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos";
      description = "The system's flake, whose kirin input updates follow.";
    };
    host = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = "Its nixosConfigurations entry for this machine.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.kirin-update = service "updating the system" updateScript;
    systemd.services.kirin-cleanup = service "cleaning up old systems" cleanupScript;

    systemd.tmpfiles.rules = [ "d /var/lib/kirin 0755 root root -" ];

    # Switching auto update on or off: as root (a password once).
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "kirin-auto-update" ''
        case "$1" in
          on) mkdir -p /var/lib/kirin && touch ${flag} ;;
          off) rm -f ${flag} ;;
          *) [ -e ${flag} ] && echo on || echo off ;;
        esac
      '')
    ];

    # With auto update on, the user starts the update and the cleanup
    # without a password.
    security.polkit.extraConfig = ''
      polkit.addRule(function (action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" && subject.user == ${builtins.toJSON cfg.user}) {
          var unit = action.lookup("unit");
          if (unit == "kirin-update.service" || unit == "kirin-cleanup.service") {
            try {
              polkit.spawn(["${pkgs.coreutils}/bin/test", "-e", "${flag}"]);
              return polkit.Result.YES;
            } catch (e) {
              return polkit.Result.AUTH_ADMIN_KEEP;
            }
          }
        }
      });
    '';

    # What the system is built from, for kirin to compare with the latest.
    environment.etc."kirin/system.json".text = builtins.toJSON {
      rev = self.rev or self.dirtyRev or "unknown";
      flake = cfg.update.flake;
      host = cfg.update.host;
    };
  };
}

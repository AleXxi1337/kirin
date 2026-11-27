# A quiet boot, like macOS: no boot menu (it still shows while a key is
# held, systemd-boot's Space), no kernel or systemd text, a splash
# (Plymouth) from the firmware's logo to the lock screen; the disk's
# password (LUKS) is asked on it too.
#
# Everything is a default: the system's own config wins.
#   kirin.boot.splash = false;   # the usual boot, with its text
{ config, lib, pkgs, ... }:
let
  cfg = config.kirin.boot;
in
{
  options.kirin.boot.splash = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "A quiet boot with a splash screen (Plymouth) instead of the kernel's text.";
  };

  config = lib.mkIf (config.kirin.enable && cfg.splash) {
    boot.loader.timeout = lib.mkDefault 0;

    # Plymouth starts from the initrd and asks for the disk's password there.
    boot.initrd.systemd.enable = lib.mkDefault true;
    boot.plymouth = {
      enable = lib.mkDefault true;
      theme = lib.mkDefault "nixos-bgrt";
      themePackages = [ (pkgs.callPackage ./pkgs/plymouth-theme { }) ];
    };

    boot.kernelParams = [
      "quiet"
      "splash"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];
    boot.initrd.verbose = lib.mkDefault false;
    boot.consoleLogLevel = lib.mkDefault 0;
    systemd.settings.Manager.ShowStatus = lib.mkDefault "no";
  };
}

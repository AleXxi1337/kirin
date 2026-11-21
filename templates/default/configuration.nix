# The whole system: a user and kirin. hardware-configuration.nix comes from
# `nixos-generate-config` on the machine.
{ ... }:
{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "kirin";
  time.timeZone = "UTC";

  users.users.user = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    # Change it after the first login (passwd).
    initialPassword = "kirin";
  };

  kirin = {
    enable = true;
    user = "user";
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "26.05";
}

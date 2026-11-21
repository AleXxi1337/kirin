# Sleep, like macOS: the lid and the power button put the machine to sleep;
# a laptop sleeps, then hibernates once its battery runs low. When to dim,
# turn the screen off and sleep while idle is kirin's (Settings → Power):
# it also locks the screen, with its animation, before any sleep (it holds
# logind's sleep delay for that).
#
#   kirin.sleep.thenHibernate = true;   # a laptop with hibernation (hibernation.nix)
{ config, lib, ... }:
let
  cfg = config.kirin.sleep;
  # What "sleep" means here.
  action = if cfg.thenHibernate then "suspend-then-hibernate" else "suspend";
in
{
  options.kirin.sleep.thenHibernate = lib.mkEnableOption ''
    sleeping, then hibernating once the battery runs low (systemd checks it
    every hour while asleep): nothing is lost with the battery flat. Needs
    kirin.hibernation.enable'';

  config = lib.mkIf config.kirin.enable {
    assertions = [
      {
        assertion = cfg.thenHibernate -> config.kirin.hibernation.enable;
        message = "kirin.sleep.thenHibernate needs kirin.hibernation.enable";
      }
    ];

    services.logind.settings.Login = {
      # Lid closed: sleep. With another monitor connected (docked): keep
      # working there; Hyprland turns the built-in screen off
      # (config/hypr/modules/lid.lua).
      HandleLidSwitch = action;
      HandleLidSwitchExternalPower = action;
      HandleLidSwitchDocked = "ignore";
      # Power button: a press sleeps; holding it still powers off (the
      # firmware does that).
      HandlePowerKey = action;
      # Time kirin gets to lock the screen before sleeping (its animation
      # takes about a second).
      InhibitDelayMaxSec = 5;
    };

    # No battery estimate is needed on mains: hibernate only on battery.
    systemd.sleep.settings.Sleep = lib.mkIf cfg.thenHibernate {
      HibernateOnACPower = false;
    };
  };
}

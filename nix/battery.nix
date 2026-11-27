# The charge limit ("Preserve battery health" in Settings → Power) is
# UPower's (1.90.5+): it writes the laptop's own thresholds
# (charge_control_{start,end}_threshold) when switched on, to its udev
# CHARGE_LIMIT (75,80 unless set here).
#
#   kirin.battery.chargeLimit = [ 70 75 ];   # charge below 70%, stop at 75%
#
# kirin-charge-limit.service puts the thresholds right when UPower's didn't
# take: some firmware (ThinkPads) refuses an end below the start it holds
# (its own 95 after a reset), and UPower writes the end first, says the
# limit is on, and the battery still charges to 100%. It runs once UPower
# is up, and kirin starts it (no password) whenever it sees the two differ.
{ config, lib, pkgs, ... }:
let
  cfg = config.kirin;
  limit = cfg.battery.chargeLimit;

  script = ''
    set -u
    for dir in /sys/class/power_supply/*; do
      [ -w "$dir/charge_control_end_threshold" ] || continue
      name=$(basename "$dir")
      path=/org/freedesktop/UPower/devices/battery_$name
      enabled=$(busctl --system get-property org.freedesktop.UPower "$path" org.freedesktop.UPower.Device ChargeThresholdEnabled 2>/dev/null | cut -d' ' -f2)
      [ "$enabled" = true ] || continue

      # What it should be: udev's CHARGE_LIMIT ("start,end"; "_" skips one).
      want=$(udevadm info -q property -p "$dir" | sed -n 's/^CHARGE_LIMIT=//p')
      [ -n "$want" ] || continue
      start=''${want%,*}
      end=''${want#*,}
      cur_start=$(cat "$dir/charge_control_start_threshold" 2>/dev/null || echo _)
      cur_end=$(cat "$dir/charge_control_end_threshold")

      write() { [ "$2" = _ ] || [ ! -w "$dir/$1" ] || echo "$2" > "$dir/$1"; }
      if [ "$start" = "$cur_start" ] && [ "$end" = "$cur_end" ]; then
        echo "$name: $cur_start-$cur_end, as it should be"
        continue
      fi
      # In an order the firmware takes: never an end below the start it
      # holds, nor a start above the end.
      if [ "$start" != _ ] && [ "$start" -lt "$cur_end" ]; then
        write charge_control_start_threshold "$start"
        write charge_control_end_threshold "$end"
      else
        write charge_control_end_threshold "$end"
        write charge_control_start_threshold "$start"
      fi
      echo "$name: $cur_start-$cur_end -> $(cat "$dir/charge_control_start_threshold" 2>/dev/null || echo _)-$(cat "$dir/charge_control_end_threshold")"
    done
  '';
in
{
  options.kirin.battery.chargeLimit = lib.mkOption {
    type = lib.types.nullOr (lib.types.listOf (lib.types.ints.between 0 100));
    default = null;
    example = [ 70 75 ];
    description = ''
      The charge limit's thresholds, [ start end ]: the battery charges when
      below start, up to end. Null: UPower's (75, 80).
    '';
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = limit == null || (builtins.length limit == 2 && builtins.elemAt limit 0 < builtins.elemAt limit 1);
        message = "kirin.battery.chargeLimit is [ start end ], start below end";
      }
    ];

    # After UPower's hwdb (99-local.rules comes last): its thresholds.
    services.udev.extraRules = lib.mkIf (limit != null) ''
      SUBSYSTEM=="power_supply", ATTR{type}=="Battery", ENV{CHARGE_LIMIT}="${toString (builtins.elemAt limit 0)},${toString (builtins.elemAt limit 1)}"
    '';

    systemd.services.kirin-charge-limit = {
      description = "kirin: the battery's charge limit, as UPower has it";
      after = [ "upower.service" ];
      wants = [ "upower.service" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [ systemd coreutils gnused ];
      serviceConfig.Type = "oneshot";
      inherit script;
    };

    # kirin starts it when the thresholds and UPower differ: no password.
    security.polkit.extraConfig = ''
      polkit.addRule(function (action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" && subject.user == ${builtins.toJSON cfg.user}
            && action.lookup("unit") == "kirin-charge-limit.service" && action.lookup("verb") == "start") {
          return polkit.Result.YES;
        }
      });
    '';
  };
}

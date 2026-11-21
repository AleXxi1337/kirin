#!/bin/sh
# The charge limit UPower offers (1.90.5+), for the first device that has
# one: its D-Bus path, kernel name, whether it's on, the start and end
# thresholds, and the kernel's own end threshold ("-" if none) to check
# that it took. Exits 1 if no device has a limit (many laptops don't).
#
#   charge-limit.sh  ->  "<path> <name> <true|false> <start> <end> <kernel end>"
#
# Used by services/Power.qml.

for p in $(busctl --system call org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower EnumerateDevices | tr ' ' '\n' | grep '^"' | tr -d '"'); do
    get() { busctl --system get-property org.freedesktop.UPower "$p" org.freedesktop.UPower.Device "$1" 2>/dev/null | cut -d' ' -f2- | tr -d '"'; }
    [ "$(get ChargeThresholdSupported)" = true ] || continue
    name=$(get NativePath)
    kernel=$(cat "/sys/class/power_supply/$name/charge_control_end_threshold" 2>/dev/null || echo -)
    echo "$p $name $(get ChargeThresholdEnabled) $(get ChargeStartThreshold) $(get ChargeEndThreshold) $kernel"
    exit 0
done
exit 1

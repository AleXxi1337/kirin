#!/bin/sh
# The first battery's wear, from the kernel: how much it holds when full,
# how much it held new, and charge cycles (0: not reported), in Wh (energy)
# or Ah (charge, on some batteries).
#
#   battery-health.sh  ->  "<full> <design> <cycles> <Wh|Ah>"  (full, design in µWh/µAh)
#
# Used by services/Power.qml.

for d in /sys/class/power_supply/BAT*; do
    [ -e "$d" ] || exit 1
    cycles=$(cat "$d/cycle_count" 2>/dev/null || echo 0)
    if [ -e "$d/energy_full" ]; then
        echo "$(cat "$d/energy_full") $(cat "$d/energy_full_design") $cycles Wh"
    else
        echo "$(cat "$d/charge_full") $(cat "$d/charge_full_design") $cycles Ah"
    fi
    exit 0
done
exit 1

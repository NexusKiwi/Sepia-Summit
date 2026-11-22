#!/usr/bin/env bash
# temps.sh cpu        -> CPU temp (AMD k10temp Tctl, or Intel coretemp package)
# temps.sh nvme       -> all NVMe drive temps, e.g. "41° 38°"
# Finds sensors by name so it survives hwmon numbering changes between boots.
mode="$1"
read_c() { [ -r "$1" ] && echo $(( $(cat "$1") / 1000 )); }

case "$mode" in
  cpu)
    for h in /sys/class/hwmon/hwmon*; do
      case "$(cat "$h/name" 2>/dev/null)" in
        k10temp|zenpower) read_c "$h/temp1_input"; exit ;;
        coretemp)         read_c "$h/temp1_input"; exit ;;
      esac
    done
    echo "--" ;;
  nvme)
    out=""
    for h in /sys/class/hwmon/hwmon*; do
      [ "$(cat "$h/name" 2>/dev/null)" = "nvme" ] && out="$out$(read_c "$h/temp1_input")° "
    done
    echo "${out:---}" ;;
  *) echo "usage: $0 cpu|nvme" >&2; exit 1 ;;
esac

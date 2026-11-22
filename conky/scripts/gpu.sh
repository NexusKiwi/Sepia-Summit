#!/usr/bin/env bash
# gpu.sh <field>  — NVIDIA stats via nvidia-smi, cached so conky only calls it
# once every ~2 s no matter how many fields it asks for.
# fields: name util temp fan vram vramperc power clock
cache="${XDG_RUNTIME_DIR:-/tmp}/conky-sepia-gpu"
if [ ! -s "$cache" ] || [ $(( $(date +%s) - $(stat -c %Y "$cache") )) -ge 2 ]; then
  if command -v nvidia-smi >/dev/null; then
    nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu,fan.speed,memory.used,memory.total,power.draw,clocks.gr \
      --format=csv,noheader,nounits 2>/dev/null | head -n1 > "$cache.tmp" && mv "$cache.tmp" "$cache"
  else
    echo "no nvidia-smi,0,0,0,0,1,0,0" > "$cache"
  fi
fi
IFS=',' read -r name util temp fan used total power clock < "$cache"
trim() { echo "$1" | sed 's/^ *//; s/ *$//'; }
case "$1" in
  name)     trim "$name" | sed 's/NVIDIA GeForce //' ;;
  util)     trim "$util" ;;
  temp)     trim "$temp" ;;
  fan)      trim "$fan" | sed 's/\[N\/A\]/--/' ;;
  vram)     u=$(trim "$used"); t=$(trim "$total"); awk -v u="$u" -v t="$t" 'BEGIN{printf "%.1f / %.0f GiB\n", u/1024, t/1024}' ;;
  vramperc) u=$(trim "$used"); t=$(trim "$total"); awk -v u="$u" -v t="$t" 'BEGIN{printf "%d\n", (t>0)?u*100/t:0}' ;;
  power)    printf "%.0f\n" "$(trim "$power")" 2>/dev/null || echo "--" ;;
  clock)    trim "$clock" ;;
  *) echo "?" ;;
esac

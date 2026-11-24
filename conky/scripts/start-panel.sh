#!/usr/bin/env bash
# Starts the panel on the chosen monitor (0 = leftmost).
# conky's Wayland surface opens on KWin's active monitor and ignores xinerama_head,
# so make the target monitor active while it starts, then switch back.
# Usage: start-panel.sh <conky binary> <config> <monitor index>
BIN="$1" CONF="$2" INDEX="${3:-0}"

QDBUS="$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus || true)"

start() { setsid "$BIN" -c "$CONF" >/dev/null 2>&1 < /dev/null & }

active() { "$QDBUS" org.kde.KWin /KWin org.kde.KWin.activeOutputName 2>/dev/null; }

switch_to() {
  local i
  for ((i = 0; i < count; i++)); do
    [ "$(active)" = "$1" ] && return 0
    "$QDBUS" org.kde.kglobalaccel /component/kwin \
      org.kde.kglobalaccel.Component.invokeShortcut "Switch to Next Screen" >/dev/null 2>&1
    sleep 0.2
  done
}

# Enabled monitors, left to right
mapfile -t outputs < <(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '
  /^Output:/ { name = $3; on = 0 }
  /^[[:space:]]*enabled$/ { on = 1 }
  /Geometry:/ && on { split($2, xy, ","); print xy[1], name }' | sort -n | awk '{print $2}')
count=${#outputs[@]}

if [ -z "$QDBUS" ] || [ "$count" -lt 2 ]; then
  start
  exit 0
fi

[ "$INDEX" -ge "$count" ] && INDEX=$((count - 1))
target="${outputs[$INDEX]}"
previous="$(active)"

switch_to "$target"
start
sleep 5   # the AppImage can take a few seconds to open its surface when the desktop is busy
[ -n "$previous" ] && switch_to "$previous"
exit 0

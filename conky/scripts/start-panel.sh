#!/usr/bin/env bash
# Starts the panel on the chosen monitor (0 = leftmost) and keeps it running.
# conky's Wayland surface opens on KWin's active monitor and ignores xinerama_head,
# so make the target monitor active while it starts, then switch back.
# conky exits when its monitor disappears (monitors in deep sleep disconnect), so this
# script stays running, waits for the monitors to come back and starts conky again.
# Usage: start-panel.sh <conky binary> <config> <monitor index>
BIN="$1" CONF="$2" INDEX="${3:-0}"

# Only one supervisor per config: replace any older one (and its conky).
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/sepia-panel.pid"
if [ -r "$PIDFILE" ]; then
  old="$(cat "$PIDFILE" 2>/dev/null)"
  if [ -n "$old" ] && [ "$old" != "$$" ] && grep -qs start-panel "/proc/$old/cmdline"; then
    kill "$old" 2>/dev/null
  fi
fi
echo $$ > "$PIDFILE"
pkill -f -- "conky -c $CONF" 2>/dev/null
trap 'pkill -f -- "conky -c $CONF"; exit 0' TERM INT
running() { pgrep -f -- "conky -c $CONF" >/dev/null; }

QDBUS="$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus || true)"

active() { "$QDBUS" org.kde.KWin /KWin org.kde.KWin.activeOutputName 2>/dev/null; }

# Enabled monitors, left to right
list_outputs() {
  mapfile -t outputs < <(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '
    /^Output:/ { name = $3; on = 0 }
    /^[[:space:]]*enabled$/ { on = 1 }
    /Geometry:/ && on { split($2, xy, ","); print xy[1], name }' | sort -n | awk '{print $2}')
  count=${#outputs[@]}
}

switch_to() {
  local i
  for ((i = 0; i < count; i++)); do
    [ "$(active)" = "$1" ] && return 0
    "$QDBUS" org.kde.kglobalaccel /component/kwin \
      org.kde.kglobalaccel.Component.invokeShortcut "Switch to Next Screen" >/dev/null 2>&1
    sleep 0.2
  done
}

start_on_target() {
  local target previous i=$INDEX
  [ "$i" -ge "$count" ] && i=$((count - 1))
  if [ -n "$QDBUS" ] && [ "$count" -ge 2 ]; then
    target="${outputs[$i]}"
    previous="$(active)"
    switch_to "$target"
  fi
  setsid "$BIN" -c "$CONF" >/dev/null 2>&1 < /dev/null &
  if [ -n "$target" ]; then
    sleep 5   # the AppImage can take a few seconds to open its surface when the desktop is busy
    [ -n "$previous" ] && switch_to "$previous"
  fi
}

backoff=3
while :; do
  # Wait for the monitors. Give the target one up to 30 s to join the others.
  list_outputs
  waited=0
  while [ "$count" -eq 0 ] || { [ "$count" -le "$INDEX" ] && [ "$waited" -lt 30 ]; }; do
    sleep 2; waited=$((waited + 2)); list_outputs
  done
  [ "$waited" -gt 0 ] && sleep 3   # let the desktop settle after the monitors return

  started=$SECONDS
  start_on_target
  # The AppImage forks, so watch for conky by its command line rather than a PID.
  sleep 2
  while running; do sleep 5; done

  # Back off if conky keeps dying straight away (a broken config, say).
  if [ $((SECONDS - started)) -lt 20 ]; then
    backoff=$((backoff * 2)); [ "$backoff" -gt 60 ] && backoff=60
  else
    backoff=3
  fi
  sleep "$backoff"
done

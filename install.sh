#!/usr/bin/env bash
# Sepia desktop kit installer — Bazzite / Fedora Atomic, KDE Plasma 6.
# Safe to re-run. Override detection with env vars, e.g.:
#   HEAD=0 IFACE=enp5s0 DISK=nvme0n1 ./install.sh
#   LIVE=0 ./install.sh      # plain static wallpaper, no visualiser behind the ridges
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
CONF="$HOME/.config/conky/sepia"
WPDIR="$HOME/Pictures/Wallpapers/sepia-mountains"
LIVE="${LIVE:-1}"
c() { printf '\033[38;2;196;160;116m%s\033[0m\n' "$*"; }

c "── Sepia desktop kit ──"

# 1. packages ---------------------------------------------------------------
missing=()
command -v cava  >/dev/null || missing+=(cava)
if [ ${#missing[@]} -gt 0 ]; then
  c "Missing: ${missing[*]}"
  if command -v rpm-ostree >/dev/null; then
    read -rp "Layer them with rpm-ostree now? (needs a reboot afterwards) [y/N] " a
    if [[ "$a" =~ ^[Yy]$ ]]; then
      rpm-ostree install --idempotent --allow-inactive "${missing[@]}"
      c "Done. Reboot, then run ./install.sh again."
      exit 0
    fi
  else
    c "Install them with your package manager, then re-run."
  fi
  c "Continuing without them (configs will still be copied)."
fi

# 2. detect hardware bits ---------------------------------------------------
IFACE="${IFACE:-$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' || true)}"
IFACE="${IFACE:-eth0}"

if [ -z "${DISK:-}" ]; then
  src="$(findmnt -no SOURCE /var/home 2>/dev/null || findmnt -no SOURCE / 2>/dev/null || true)"
  src="${src%%[*}"
  DISK="$(lsblk -sno NAME,TYPE "$src" 2>/dev/null | awk '$2=="disk"{gsub(/[^a-zA-Z0-9]/,"",$1); print $1; exit}' || true)"
  DISK="${DISK:-nvme0n1}"
fi

if [ -z "${HEAD:-}" ]; then
  n=1
  if command -v kscreen-doctor >/dev/null; then
    n="$(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -c '^Output:' || true)"
  fi
  [ "${n:-1}" -ge 2 ] && HEAD=1 || HEAD=0
fi

# extra mounted drives (game drives etc.)
EXTRA=""
while read -r tgt; do
  [[ "$tgt" == *'\x'* ]] && continue          # skip paths with spaces
  label="$(basename "$tgt" | cut -c1-10)"
  EXTRA+="\${color2}${label} \${color3}\${fs_used ${tgt}} / \${fs_size ${tgt}}\${alignr}\${fs_used_perc ${tgt}}%\n\${color2}\${fs_bar ${tgt}}\n"
done < <(findmnt -rno TARGET 2>/dev/null | grep -E '^/(run/media/[^/]+|var/mnt|mnt|media)/[^/]+$' | head -n 3 || true)

c "network: $IFACE   disk: $DISK   monitor index: $HEAD"
[ -n "$EXTRA" ] && c "extra drives: $(findmnt -rno TARGET | grep -E '^/(run/media/[^/]+|var/mnt|mnt|media)/[^/]+$' | head -n3 | tr '\n' ' ')"

# The panel needs conky 1.25+ to stay on the desktop layer under Wayland.
# Use the system conky if it's new enough, otherwise a pinned, verified AppImage.
CONKY_VER="1.26.2"
CONKY_SHA="1d1390b7ebd162d3ba55d6c29693b9aa410a7afd8e6f11b05509e4716038927d"
CONKY_URL="https://github.com/brndnmtthws/conky/releases/download/v$CONKY_VER/conky-ubuntu-24.04-x86_64-v$CONKY_VER-release.AppImage"
CONKY_APP="$HOME/.local/bin/sepia-conky"

conky_is_new_enough() {
  local v
  v="$("$1" --version 2>/dev/null | awk '/^conky /{print $2; exit}' | cut -d- -f1)"
  [ -n "$v" ] && [ "$(printf '%s\n1.25.0\n' "$v" | sort -V | head -n1)" = "1.25.0" ]
}

CONKY_BIN="$(command -v conky || true)"
if [ -z "$CONKY_BIN" ] || ! conky_is_new_enough "$CONKY_BIN"; then
  if ! { [ -x "$CONKY_APP" ] && echo "$CONKY_SHA  $CONKY_APP" | sha256sum -c --status; }; then
    c "Downloading conky $CONKY_VER…"
    mkdir -p "$HOME/.local/bin"
    tmp="$(mktemp "$HOME/.local/bin/.sepia-conky.XXXXXX")"
    if curl -fsSL --retry 2 "$CONKY_URL" -o "$tmp" && echo "$CONKY_SHA  $tmp" | sha256sum -c --status; then
      chmod 755 "$tmp"
      mv -f "$tmp" "$CONKY_APP"
    else
      rm -f "$tmp"
      c "Couldn't download conky $CONKY_VER. The panel may vanish on Show Desktop."
    fi
  fi
  [ -x "$CONKY_APP" ] && CONKY_BIN="$CONKY_APP"
fi

# 3. conky ------------------------------------------------------------------
mkdir -p "$CONF/scripts"
cp "$KIT"/conky/scripts/*.sh "$KIT"/conky/scripts/*.lua "$CONF/scripts/"
chmod +x "$CONF"/scripts/*.sh
EXTRA_ESC="$(printf '%s' "$EXTRA" | sed 's/[&|]/\\&/g')"
sed -e "s|@IFACE@|$IFACE|g" -e "s|@DISK@|$DISK|g" -e "s|@HEAD@|$HEAD|g" \
    -e "s|@EXTRA_DRIVES@|$EXTRA_ESC|" \
    "$KIT/conky/sepia.conf" > "$CONF/sepia.conf"

mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/conky-sepia.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Conky (Sepia)
Exec=sh -c "sleep 6 && $CONF/scripts/start-panel.sh ${CONKY_BIN:-conky} $CONF/sepia.conf $HEAD"
X-KDE-autostart-phase=2
Hidden=false
EOF

# 4. cava theme -------------------------------------------------------------
mkdir -p "$HOME/.config/cava"
[ -f "$HOME/.config/cava/config" ] && cp "$HOME/.config/cava/config" "$HOME/.config/cava/config.bak.$(date +%s)"
cp "$KIT/cava/config" "$HOME/.config/cava/config"

# 5. live wallpaper plugin + audio server -----------------------------------
if [ "$LIVE" = "1" ]; then
  PLUG="$HOME/.local/share/plasma/wallpapers/com.nexuskiwi.sepiasummit"
  rm -rf "$PLUG"; mkdir -p "$(dirname "$PLUG")"
  cp -r "$KIT/plasma/wallpaper/com.nexuskiwi.sepiasummit" "$PLUG"
  mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
  install -m 755 "$KIT/plasma/sepia-cava-server.py" "$HOME/.local/bin/sepia-cava-server"
  cp "$KIT/plasma/sepia-cava.service" "$HOME/.config/systemd/user/"
  if command -v systemctl >/dev/null && command -v cava >/dev/null; then
    systemctl --user daemon-reload
    systemctl --user enable --now sepia-cava.service && systemctl --user restart sepia-cava.service
    c "Audio server running (sepia-cava.service)."
  else
    c "cava not installed yet — the visualiser will stay still until it is."
  fi
fi

# 6. wallpaper --------------------------------------------------------------
mkdir -p "$WPDIR"
cp "$KIT"/wallpapers/*.png "$WPDIR/"
QDBUS="$(command -v qdbus6 || command -v qdbus || command -v qdbus-qt6 || true)"
if [ -n "$QDBUS" ]; then
  js="$(sed -e "s|@WPDIR@|$WPDIR|" -e "s|@LIVE@|$LIVE|" "$KIT/plasma/set-wallpaper.js")"
  "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$js" || c "Couldn't set wallpaper automatically — pick it in Desktop > Configure."
else
  c "qdbus not found — set the wallpaper by hand from $WPDIR"
fi

# Dock and app drawer -------------------------------------------------------
# Replaces the taskbars with one floating dock on the left monitor and hides
# desktop icons from view (the files stay). DOCK=0 skips this.
if [ "${DOCK:-1}" = "1" ] && [ -n "$QDBUS" ]; then
  restart_shell() {
    systemctl --user restart plasma-plasmashell
    for _ in $(seq 1 30); do
      "$QDBUS" org.kde.plasmashell /PlasmaShell org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1 && break
      sleep 0.5
    done
    sleep 3
  }
  DRAWER_SRC="$KIT/plasma/drawer/com.nexuskiwi.sepiadrawer"
  DRAWER="$HOME/.local/share/plasma/plasmoids/com.nexuskiwi.sepiadrawer"
  APPLETS="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
  drawer_changed=0
  diff -rq "$DRAWER_SRC" "$DRAWER" >/dev/null 2>&1 || drawer_changed=1
  rm -rf "$DRAWER"; mkdir -p "$(dirname "$DRAWER")"
  cp -r "$DRAWER_SRC" "$DRAWER"

  if grep -q '^plugin=com.nexuskiwi.sepiadrawer$' "$APPLETS" 2>/dev/null; then
    [ "$drawer_changed" = 1 ] && restart_shell
  else
    BACKUP="$HOME/.local/share/sepia-summit/backups/pre-dock-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
    for f in plasma-org.kde.plasma.desktop-appletsrc plasmashellrc; do
      [ -f "$HOME/.config/$f" ] && cp -p "$HOME/.config/$f" "$BACKUP/"
    done
    c "Previous panel layout saved to $BACKUP"
    restart_shell
    "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat "$KIT/plasma/apply-dock.js")" \
      || c "Couldn't set up the dock automatically."
    sleep 12   # let Plasma save the layout, the widget order applies on reload
    restart_shell
  fi
fi

# 7. start it ---------------------------------------------------------------
if [ -n "$CONKY_BIN" ]; then
  pkill -f -- "-c $CONF/sepia.conf" 2>/dev/null || true
  sleep 1
  "$CONF/scripts/start-panel.sh" "$CONKY_BIN" "$CONF/sepia.conf" "$HEAD"
fi

c "All done. If the wallpaper shows black, run: systemctl --user restart plasma-plasmashell"
if [ "$LIVE" = "1" ]; then c "Play some music — the bars rise from behind the mountains."; fi

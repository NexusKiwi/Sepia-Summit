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
command -v conky >/dev/null || missing+=(conky)
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
Exec=sh -c "sleep 6 && conky -c $CONF/sepia.conf"
X-KDE-autostart-phase=2
Hidden=false
EOF

# KWin script that keeps the panel above Plasma's desktop layer
KEEPER="$HOME/.local/share/kwin/scripts/sepia-panel-keeper"
mkdir -p "$KEEPER"
cp -r "$KIT/plasma/kwin/sepia-panel-keeper/." "$KEEPER/"
if command -v kwriteconfig6 >/dev/null; then
  kwriteconfig6 --file kwinrc --group Plugins --key sepia-panel-keeperEnabled true
  QDBUS_KWIN="$(command -v qdbus6 || command -v qdbus || command -v qdbus-qt6 || true)"
  if [ -n "$QDBUS_KWIN" ]; then
    "$QDBUS_KWIN" org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
    "$QDBUS_KWIN" org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1 || true
  fi
fi

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

# 7. start it ---------------------------------------------------------------
if command -v conky >/dev/null; then
  pkill -f "conky -c $CONF/sepia.conf" 2>/dev/null || true
  (conky -c "$CONF/sepia.conf" >/dev/null 2>&1 &)
fi

c "All done. If the wallpaper shows black, run: systemctl --user restart plasma-plasmashell"
if [ "$LIVE" = "1" ]; then c "Play some music — the bars rise from behind the mountains."; fi

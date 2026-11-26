#!/usr/bin/env bash
# Sepia desktop kit installer — Bazzite / Fedora Atomic, KDE Plasma 6.
# Safe to re-run. Override detection with env vars, e.g.:
#   HEAD=0 IFACE=enp5s0 DISK=nvme0n1 ./install.sh
#   LIVE=0 ./install.sh      # plain static wallpaper, no visualiser behind the ridges
#   PLACE="Lisbon" ./install.sh   # town for the weather (otherwise asked once)
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
    pm=""
    if   command -v dnf    >/dev/null; then pm="sudo dnf install -y"
    elif command -v pacman >/dev/null; then pm="sudo pacman -S --needed --noconfirm"
    elif command -v zypper >/dev/null; then pm="sudo zypper install -y"
    elif command -v apt    >/dev/null; then pm="sudo apt install -y"
    fi
    if [ -n "$pm" ]; then
      read -rp "Install them with \`$pm ${missing[*]}\` now? [y/N] " a
      [[ "$a" =~ ^[Yy]$ ]] && $pm "${missing[@]}" || true
    else
      c "Install them with your package manager, then re-run."
    fi
  fi
  command -v cava >/dev/null || c "Continuing without them (configs will still be copied)."
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

# 4b. weather (conky lines + live wallpaper sky) ------------------------------
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
install -m 755 "$KIT/plasma/sepia-weather.py" "$HOME/.local/bin/sepia-weather"
cp "$KIT/plasma/sepia-weather.service" "$KIT/plasma/sepia-weather.timer" "$HOME/.config/systemd/user/"
WCONF="${XDG_CONFIG_HOME:-$HOME/.config}/sepia-summit/weather.json"
PLACE="${PLACE:-}"
if [ -z "$PLACE" ] && [ ! -f "$WCONF" ] && [ -t 0 ]; then
  read -r -p "Town for the weather and day/night sky (Enter to skip): " PLACE || PLACE=""
fi
if [ -n "$PLACE" ]; then
  "$HOME/.local/bin/sepia-weather" setup "$PLACE" || c "Couldn't look up \"$PLACE\". Later, run: sepia-weather setup \"Your town\""
fi
if command -v systemctl >/dev/null; then
  systemctl --user daemon-reload
  systemctl --user enable --now sepia-weather.timer
fi
[ -f "$WCONF" ] || c "No weather location yet. Run: sepia-weather setup \"Your town\""

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

# Lock screen ---------------------------------------------------------------
# The lock screen gives every monitor the same wallpaper settings. With two
# monitors and the live plugin, its Span mode shows each monitor its own half of
# the dual image (bars on the right), so the lock screen matches the desktop.
# Otherwise use the single-screen (or ultrawide) picture for the tallest monitor.
# LOCK=0 skips this.
if [ "${LOCK:-1}" = "1" ] && command -v kwriteconfig6 >/dev/null; then
  read -r ln lw lh < <(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '
    /^Output:/ { on = 0 } /^[[:space:]]*enabled$/ { on = 1 }
    /Geometry:/ && on { n++; split($3, wh, "x"); if (wh[2] + 0 > h) { w = wh[1]; h = wh[2] } }
    END { print n + 0, w + 0, h + 0 }')
  tall=1080; [ "${lh:-0}" -gt 1150 ] && tall=1440
  LOCKRC="$HOME/.config/kscreenlockerrc"
  if [ -f "$LOCKRC" ] && ! grep -qs sepia-mountains "$LOCKRC"; then
    BACKUP="$HOME/.local/share/sepia-summit/backups/pre-lock-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
    cp -p "$LOCKRC" "$BACKUP/"
    c "Previous lock screen settings saved to $BACKUP"
  fi
  lockset() { kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group "$1" --group General --key "$2" "$3"; }
  if [ "$LIVE" = "1" ] && [ "${ln:-0}" -eq 2 ]; then
    LOCKIMG="sepia-mountains_$([ $tall = 1440 ] && echo dual-1440p_5120x1440 || echo dual-1080p_3840x1080).png"
    kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin com.nexuskiwi.sepiasummit
    lockset com.nexuskiwi.sepiasummit Background "file://$WPDIR/$LOCKIMG"
    lockset com.nexuskiwi.sepiasummit Foreground "file://$WPDIR/${LOCKIMG%.png}_front.png"
    lockset com.nexuskiwi.sepiasummit Span true
    lockset com.nexuskiwi.sepiasummit Visualiser true
  else
    kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image
  fi
  # The static picture, used without the live plugin (and kept ready if you switch back).
  if [ "${lh:-0}" -gt 0 ] && [ $((lw * 10 / lh)) -ge 22 ]; then
    STATICIMG="sepia-mountains_ultrawide_$([ $tall = 1440 ] && echo 3440x1440 || echo 2560x1080).png"
  else
    STATICIMG="sepia-mountains_single_$([ $tall = 1440 ] && echo 2560x1440 || echo 1920x1080).png"
  fi
  lockset org.kde.image Image "file://$WPDIR/$STATICIMG"
  lockset org.kde.image PreviewImage "file://$WPDIR/$STATICIMG"
  lockset org.kde.image FillMode 2
fi

# Dock and app drawer -------------------------------------------------------
# Replaces the taskbars with one floating glass dock down the left edge of the left monitor, with
# a few apps pinned, and hides desktop icons from view (the files stay). DOCK=0 skips this.
if [ "${DOCK:-1}" = "1" ] && [ -n "$QDBUS" ]; then
  have_app() {
    local d
    for d in "$HOME/.local/share/applications" /usr/share/applications /usr/local/share/applications \
             /var/lib/flatpak/exports/share/applications "$HOME/.local/share/flatpak/exports/share/applications"; do
      [ -f "$d/$1" ] && return 0
    done
    return 1
  }
  # Pinned: your default browser, files, terminal, then Steam, Discord and Claude if installed
  LAUNCHERS=""
  browser="$(xdg-settings get default-web-browser 2>/dev/null || true)"
  for app in "$browser" org.kde.dolphin.desktop org.kde.konsole.desktop steam.desktop discord.desktop \
             com.discordapp.Discord.desktop claude-desktop.desktop claude.desktop; do
    [ -n "$app" ] && have_app "$app" && case ",$LAUNCHERS" in *",applications:$app,"*) ;; *) LAUNCHERS+="applications:$app,";; esac
  done
  LAUNCHERS="${LAUNCHERS%,}"
  # Tray apps that get their own button under the tray arrow (the tray hides everything else)
  TRAY_BUTTONS=""
  if command -v gdbus >/dev/null && [ -n "$(python3 "$KIT/plasma/trayitem/com.nexuskiwi.sepiatrayitem/contents/code/sepia-trayitem.py" status OpenRGB 2>/dev/null | grep 1)" ]; then
    TRAY_BUTTONS="OpenRGB"
  fi
  dock_script() { sed -e "s|@TRAY_ITEMS@|$1|" -e "s|@LAUNCHERS@|$LAUNCHERS|g" -e "s|@TRAY_BUTTONS@|$TRAY_BUTTONS|g" "$KIT/plasma/apply-dock.js"; }
  TRAYBTN="$HOME/.local/share/plasma/plasmoids/com.nexuskiwi.sepiatrayitem"
  diff -rq "$KIT/plasma/trayitem/com.nexuskiwi.sepiatrayitem" "$TRAYBTN" >/dev/null 2>&1 || drawer_changed_btn=1
  rm -rf "$TRAYBTN"; mkdir -p "$(dirname "$TRAYBTN")"
  cp -r "$KIT/plasma/trayitem/com.nexuskiwi.sepiatrayitem" "$TRAYBTN"
  DOCK_MARK="$HOME/.local/share/sepia-summit/dock-version"
  restart_shell() {
    # Several restarts in a row would otherwise hit systemd's start limit
    systemctl --user reset-failed plasma-plasmashell 2>/dev/null || true
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
  [ "${drawer_changed_btn:-0}" = 1 ] && drawer_changed=1
  rm -rf "$DRAWER"; mkdir -p "$(dirname "$DRAWER")"
  cp -r "$DRAWER_SRC" "$DRAWER"

  if grep -q '^plugin=com.nexuskiwi.sepiadrawer$' "$APPLETS" 2>/dev/null; then
    # Docks set up while the tray arrow was scaled up to fill the dock: back to its usual size
    if grep -q '^scaleIconsToFit=true$' "$APPLETS"; then
      "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript 'panels().forEach(function (p) { p.widgets().forEach(function (w) { if (w.type === "org.kde.plasma.systemtray") { w.currentConfigGroup = ["General"]; w.writeConfig("scaleIconsToFit", false); } }); });' >/dev/null \
        || c "Couldn't update the tray arrow."
      sleep 12   # let Plasma save it before the restart
      drawer_changed=1
    fi
    # Docks from before the current layout (version 3: left edge, arrow above volume/network/buttons)
    if [ "$(cat "$DOCK_MARK" 2>/dev/null)" != 3 ]; then
      for _ in 1 2; do   # twice, as below: the new spacers' order only sticks on the second pass
        "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(dock_script "")" >/dev/null \
          || c "Couldn't update the dock."
        sleep 12
        restart_shell
      done
      drawer_changed=0
    fi
    [ "$drawer_changed" = 1 ] && restart_shell
    mkdir -p "$(dirname "$DOCK_MARK")"; echo 3 > "$DOCK_MARK"
  else
    BACKUP="$HOME/.local/share/sepia-summit/backups/pre-dock-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
    for f in plasma-org.kde.plasma.desktop-appletsrc plasmashellrc; do
      [ -f "$HOME/.config/$f" ] && cp -p "$HOME/.config/$f" "$BACKUP/"
    done
    c "Previous panel layout saved to $BACKUP"
    restart_shell
    TRAY_ITEMS=""
    for item in $("$QDBUS" org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.freedesktop.DBus.Properties.Get org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems 2>/dev/null || true); do
      id="$("$QDBUS" "${item%%/*}" "/${item#*/}" org.freedesktop.DBus.Properties.Get org.kde.StatusNotifierItem Id 2>/dev/null | tr -cd 'A-Za-z0-9_.-' || true)"
      [ -n "$id" ] && TRAY_ITEMS+="$id,"
    done
    # Twice: on the first pass Plasma saves its own order over ours while it
    # adds the new widgets. Once they exist, the second pass sticks.
    for _ in 1 2; do
      "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(dock_script "$TRAY_ITEMS")" >/dev/null \
        || c "Couldn't set up the dock automatically."
      sleep 12   # let Plasma save the layout, the widget order applies on reload
      restart_shell
    done
    mkdir -p "$(dirname "$DOCK_MARK")"; echo 3 > "$DOCK_MARK"
  fi
fi

# Icons ---------------------------------------------------------------------
# Cream line icons for the browser, files, terminal, Steam, Discord and Claude. The theme holds only
# those and inherits everything else from the icon theme you had. ICONS=0 skips this.
if [ "${ICONS:-1}" = "1" ] && [ -x /usr/libexec/plasma-changeicons ]; then
  ICONDIR="$HOME/.local/share/icons/sepia-summit"
  cur="$(kreadconfig6 --group Icons --key Theme 2>/dev/null || true)"
  if [ "$cur" = "sepia-summit" ]; then
    base="$(sed -n 's/^Inherits=\([^,]*\).*/\1/p' "$ICONDIR/index.theme" 2>/dev/null)"
  else
    base="${cur:-breeze}"
    c "Icon theme was ${cur:-breeze}; Sepia Summit builds on it (switch back in System Settings > Colours & Themes > Icons)"
  fi
  rm -rf "$ICONDIR"; mkdir -p "$ICONDIR"
  cp -r "$KIT/plasma/icons/sepia-summit/." "$ICONDIR/"
  sed -i "s|@INHERITS@|${base:-breeze}|" "$ICONDIR/index.theme"
  /usr/libexec/plasma-changeicons sepia-summit >/dev/null 2>&1 || c "Couldn't switch the icon theme automatically."
fi

# Plasma style --------------------------------------------------------------
# Sepia colours over Breeze's artwork, with more see-through panels and popups.
# THEME=0 skips this.
if [ "${THEME:-1}" = "1" ] && command -v plasma-apply-desktoptheme >/dev/null; then
  STYLE="$HOME/.local/share/plasma/desktoptheme/sepia-summit"
  if [ -f "$HOME/.config/plasmarc" ] && [ ! -d "$STYLE" ]; then
    BACKUP="$HOME/.local/share/sepia-summit/backups/pre-theme-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
    cp -p "$HOME/.config/plasmarc" "$BACKUP/"
    c "Previous Plasma style saved to $BACKUP"
  fi
  rm -rf "$STYLE"; mkdir -p "$STYLE"
  cp -r "$KIT/plasma/theme/sepia-summit/." "$STYLE/"
  # The panel, popup and task frames and the volume/network icons are our own (tools/make_plasma_style.py):
  # translucent/ is used when KWin can blur behind it (glass), the others are the fallback.
  # Everything else falls back to Breeze.
  rm -rf "$HOME/.cache/plasma_theme_sepia-summit"* 2>/dev/null || true
  plasma-apply-desktoptheme sepia-summit >/dev/null 2>&1 || c "Couldn't apply the Plasma style automatically."

  # Frosted glass: a bit more blur than KWin's default, with fine grain. GLASS=0 leaves KWin alone.
  if [ "${GLASS:-1}" = "1" ] && command -v kwriteconfig6 >/dev/null; then
    if [ -z "$(kreadconfig6 --file kwinrc --group Effect-blur --key SepiaPrevious)" ]; then
      prev="$(kreadconfig6 --file kwinrc --group Effect-blur --key BlurStrength),$(kreadconfig6 --file kwinrc --group Effect-blur --key NoiseStrength)"
      kwriteconfig6 --file kwinrc --group Effect-blur --key SepiaPrevious "$prev"     # empty = KWin defaults
    fi
    kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled true
    kwriteconfig6 --file kwinrc --group Effect-blur --key BlurStrength 11
    kwriteconfig6 --file kwinrc --group Effect-blur --key NoiseStrength 3
    [ -n "$QDBUS" ] && "$QDBUS" org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  fi

  # Matching colours for app windows, with a tan accent
  SCHEMES="$HOME/.local/share/color-schemes"
  if [ ! -f "$SCHEMES/SepiaSummit.colors" ] && [ -f "$HOME/.config/kdeglobals" ]; then
    BACKUP="$HOME/.local/share/sepia-summit/backups/pre-colours-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
    cp -p "$HOME/.config/kdeglobals" "$BACKUP/"
    c "Previous app colours saved to $BACKUP"
  fi
  mkdir -p "$SCHEMES"
  cp "$KIT/plasma/colors/SepiaSummit.colors" "$SCHEMES/"
  # The accent goes first: applying a scheme bakes the current accent into it
  if command -v kwriteconfig6 >/dev/null; then
    kwriteconfig6 --file kdeglobals --group General --key AccentColor "196,160,116"
    kwriteconfig6 --file kdeglobals --group General --key LastUsedCustomAccentColor "196,160,116"
  fi
  if command -v plasma-apply-colorscheme >/dev/null; then
    plasma-apply-colorscheme SepiaSummit >/dev/null 2>&1 || true
  fi
  dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0 2>/dev/null || true

  # Konsole profile, made the default for new windows
  KONSOLE="$HOME/.local/share/konsole"
  if [ ! -f "$KONSOLE/SepiaSummit.profile" ] && [ -f "$HOME/.config/konsolerc" ]; then
    BACKUP="$HOME/.local/share/sepia-summit/backups/pre-konsole-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
    cp -p "$HOME/.config/konsolerc" "$BACKUP/"
    c "Previous Konsole settings saved to $BACKUP"
  fi
  mkdir -p "$KONSOLE"
  cp "$KIT/konsole/SepiaSummit.profile" "$KIT/konsole/SepiaSummit.colorscheme" "$KONSOLE/"
  if command -v kwriteconfig6 >/dev/null; then
    kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile SepiaSummit.profile
  fi
fi

# 7. start it ---------------------------------------------------------------
if [ -n "$CONKY_BIN" ]; then
  # start-panel.sh replaces any running panel and keeps conky alive, so detach it.
  setsid -f "$CONF/scripts/start-panel.sh" "$CONKY_BIN" "$CONF/sepia.conf" "$HEAD" \
    >/dev/null 2>&1 < /dev/null
fi

c "All done. If the wallpaper shows black, run: systemctl --user restart plasma-plasmashell"
if [ "$LIVE" = "1" ]; then c "Play some music — the bars rise from behind the mountains."; fi

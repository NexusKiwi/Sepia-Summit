# CLAUDE.md — Sepia Summit

Context for Claude Code working in this repo. Read this first.

## What this is

Sepia Summit is a Rainmeter-style desktop "rice" for KDE Plasma 6 on Linux, built for the
owner's (NexusKiwi) PC and shared with friends. It has these parts:

1. **Wallpaper** — a procedural sepia mountain range (`tools/make_wallpaper.py`), rendered
   for dual, ultrawide and single screens from one shared "world", so every size shows the
   same mountains. Each image also has a `_front.png` cut-out of the nearer ridges.
2. **Conky panel** — a hardware stats panel on the right edge (`conky/sepia.conf` plus helper scripts).
3. **Live wallpaper** — a Plasma 6 wallpaper plugin (`plasma/wallpaper/com.nexuskiwi.sepiasummit`)
   that draws the wallpaper → full-width audio bars → the ridge cut-out, so the
   visualiser rises from the valley behind the mountains. A small local service
   (`plasma/sepia-cava-server.py`, run by `sepia-cava.service`) runs CAVA and serves
   its levels on `127.0.0.1:37421`. The QML polls that address about 30 times a second.
4. **Weather + day/night** — `plasma/sepia-weather.py` (stdlib, Open-Meteo, run every 10 min by
   `sepia-weather.timer`) writes `~/.cache/sepia-summit/weather.json`. Conky prints two lines from it
   under the date. It also writes `weather.qml` (a QtObject holding the same JSON) that the wallpaper
   loads with a Loader: the lock screen blocks **all** network access, even 127.0.0.1 (so the audio
   bars never move there), and XHR can't read files, but loading local QML works. The QML computes the sun's elevation itself from the cached
   lat/lon (so DST/seasons need nothing), draws clouds/overcast inside the `_sky.png` mask (exact,
   from the generator), and light/stars/fog/rain/snow above the ridges. The location lives only in
   `~/.config/sepia-summit/weather.json`, never in the repo (it's public).
5. **Seasons** — season from the date and hemisphere (`yearPhase` 0 = midsummer, mid-Jan south /
   mid-Jul north). Snow = the wallpaper brightened through `_snow.png` (alpha = how early a spot gets
   snow) with `maskThresholdMin = 1 - snowShown`. Trees (`contents/code/scene.js`, generated in world
   units by make_wallpaper.py from the same ridge lines) are drawn from the `trees.png` sprite sheet,
   cross-fading season columns and swaying with `drift`. Fireflies/leaves/pollen/spindrift are a
   second ParticleSystem; the moon is computed (low precision) and drawn on a Canvas.
6. **Sun, eclipses, meteors** — the images have no sun (`make_wallpaper.py --painted-sun` restores the
   old one); the QML places `sun.png`/`sunglow.png` and the moon by azimuth/altitude (`skyX`/`skyY`:
   facing the equator, ±90° = ±1.6 world units). `sepia-weather` embeds a Meeus-based sun/moon model
   (checked against the 2024-04-08 and 2025-03-14 eclipses) and caches `eclipses` (per-minute samples
   of the moon's offset from the sun in sun radii, or the shadow's offset from the moon in moon radii)
   and `meteors` (current shower: rate seen from here, radiant alt/az). The QML interpolates samples.
7. **Glass** — the dock and popups are frosted by KWin (the style's `translucent/` SVGs from
   `tools/make_plasma_style.py`: panel 0.42, dialogs 0.41 to match conky's 105/255, 1.5 px cream edge,
   KWin blur strength 11, noise 3). conky's desktop-layer window can't be blurred by KWin, so
   `panel.lua` writes its size/monitor to `~/.cache/sepia-summit/glass.qml` and the wallpaper draws a
   blurred copy of its `scene` item there. Desktop applets can do real glass themselves:
   `Plasmoid.containment.wallpaperGraphicsObject` + ShaderEffectSource + MultiEffect blur.
8. **Dock + icons** — vertical floating dock on the left edge (apply-dock.js, `@LAUNCHERS@` from
   install.sh: default browser, Dolphin, Konsole, Steam, Discord, Claude), then the tray (arrow only,
   `scaleIconsToFit=false` so it stays small), the volume and network applets, and one
   `com.nexuskiwi.sepiatrayitem` per running tray app in `@TRAY_BUTTONS@` (OpenRGB): it finds the SNI
   item by Id over D-Bus. Clicks go through the dock's own systemtray applet (found in
   `Plasmoid.containment.applets`; its `activate`/`openContextMenu(source, pos, item)` pass a Wayland
   activation token and draw the app's dbusmenu — a bare ContextMenu call does nothing for Qt apps).
   Left click first picks the `leftClick` menu entry by label (default "Show/Hide": OpenRGB ignores
   Activate), falling back to a plain tray click. `plasma/icons/sepia-summit` is an icon theme
   with only those apps, the drawer's `sepia-app-grid`, and audio/network status icons (plain and
   `-symbolic`, from make_plasma_style.py; the style's `icons/*.svg` hold the same drawings), inheriting
   the previous theme. Dock layout version lives in `~/.local/share/sepia-summit/dock-version` (3).

`install.sh` sets up everything and is safe to re-run. `README.md` is the user-facing doc.

## Owner's machine (primary target)

- **OS**: Bazzite (Fedora Atomic, immutable). KDE Plasma 6 on Wayland. Packages are added
  with `rpm-ostree install …` and need a reboot. Don't suggest `dnf install` on the host.
- **Hardware**: Ryzen 7 5800X (16 threads, `k10temp` sensor), RTX 3070 (nvidia-smi on the
  bazzite-nvidia image), 32 GB RAM, B550M board, NVMe storage, **two monitors**.
- The user's home data lives in `/var/home`, so the conky storage section uses that path.

## Status

Installed and working on the owner's machine (Plasma 6.8, Wayland, `plasmalogin`). A fresh install
from a clean clone was tested on 2026-11-24, starting from the original desktop.

- Not tested: other hardware, single or ultrawide monitors, or the Sleep button.
- **Known issue:** light rays occasionally fan out from a monitor's top-left corner, sometimes blue
  or green. Bars shorter than their width are now hidden as a possible fix, but the cause is
  unconfirmed because stress tests never reproduced it. If it returns, replace the bars with one shader.

### Things that bite on real Plasma
- `systemctl --user restart plasma-plasmashell` kills anything in the shell's cgroup, so the drawer
  launches apps in their own scope. It also has a limit of 3 starts a minute: run `reset-failed` first.
- On a new dock, Plasma overwrites `AppletOrder` while adding widgets, so apply-dock.js runs twice.
- Set the accent **before** `plasma-apply-colorscheme`, which bakes the current accent into the scheme.
- Monitors in deep sleep disconnect, and conky exits when its monitor goes away. start-panel.sh stays
  running as a supervisor that restarts it (matched by `conky -c <config>`, because the AppImage forks).
- The tray arrow is the `arrow-up-symbolic` icon, so editing the Plasma style's arrows does nothing.
- Editing the live conky config makes conky reload, and on Wayland the reloaded surface opens on
  the *active* monitor. Re-run start-panel.sh afterwards (via `systemd-run --user`) to put it back.
- Qt ImageParticle draws every particle as a square of `size`, so sprites must be square (a tall rain
  streak image became bright blobs). Weather effects must stay faint: the owner found bright,
  dense particles painful. Use `sepia-weather preview …` and screenshot, and keep previews short.
- In Span mode (lock screen) each monitor's wallpaper instance draws only its slice of a shared
  desktop. Anything spread across the sky (clouds, stars) must be laid out over `sliceX/sliceW`,
  not `width`, or each monitor shows a copy of the same sky.
- MultiEffect's mask spread is centred on the threshold: threshold 0 with spread 0.3 lets ~50% of
  the masked-out area through (clouds showed over the peaks). Use threshold 0.5 for binary masks.
  Brightness alone is fine on a masked MultiEffect; contrast/saturation left dark smudges.
- A Loader reloading a new URL that resolves Ready again doesn't emit statusChanged: use `onLoaded`.
- Weather/season effects are tuned to be faint (see above). Spindrift, fireflies and pollen use big,
  very low-alpha particles; small bright dots read as sparkles.
- There is no `qml` runner on the host; test QML by installing and restarting plasmashell.
- `console.log` from the wallpaper doesn't reach the journal; `console.warn` does.
- conky's monitor number counts screens from the left; `Qt.application.screens` is in another order,
  so the wallpaper sorts screens by `virtualX` before matching it.
- The weather timer runs `sepia-weather refresh`, which leaves a preview alone for 15 minutes (a
  plain `fetch` replaced previews mid-eclipse).
- `pkill -f` with a pattern that also appears in your own shell command kills that shell (exit 144).
- Never pause a ParticleSystem the moment its effect ends: `running: false` freezes particles in flight
  (rain hung in the air after a shower). Disable the emitters, keep running for the longest lifeSpan, then pause.
- Plasma style frames: lay the 9 pieces out edge to edge (Breeze-style, corners R, edges 32 long), use
  `hint-stretch-borders`, and draw the edge line as a *filled* band, not a stroke. Gaps between pieces,
  tiled translucent edges, or a stroke's half-width overhang all showed up as light seams in the dock.
- `Plasmoid.activated` fires twice per shortcut press (the drawer debounces it). To open the drawer for a
  screenshot, give it a temporary global shortcut, then `invokeShortcut "activate widget <id>"` on
  `/component/plasmashell` (kglobalaccel only knows widgets that have a shortcut).

## Repo layout

```
install.sh                    installer (bash, set -euo pipefail; env overrides HEAD IFACE DISK LIVE DOCK THEME LOCK PLACE)
conky/sepia.conf              conky Lua config; @HEAD@ @IFACE@ @DISK@ @EXTRA_DRIVES@ filled by install.sh,
                              @S@ replaced at runtime via gsub (scripts path)
conky/scripts/temps.sh        CPU/NVMe temps found by hwmon *name* (numbering changes between boots)
conky/scripts/gpu.sh          nvidia-smi, cached in $XDG_RUNTIME_DIR for 2 s
cava/config                   sepia colours for terminal cava
plasma/wallpaper/…/           Plasma 6 wallpaper package (metadata.json, contents/ui/main.qml,
                              contents/ui/config.qml, contents/config/main.xml)
plasma/sepia-cava-server.py   CAVA → localhost HTTP (stdlib only, 127.0.0.1 only)
plasma/sepia-cava.service     systemd --user unit (ExecStart=%h/.local/bin/sepia-cava-server)
plasma/set-wallpaper.js       plasmashell evaluateScript: picks images per screen (@WPDIR@ @LIVE@)
plasma/apply-dock.js          plasmashell evaluateScript: vertical glass dock on the left monitor, hides desktop icons
plasma/icons/sepia-summit/    icon theme (index.theme Inherits=@INHERITS@ filled by install.sh)
plasma/drawer/…/              app drawer plasmoid (contents/code/sepia-drawer.py lists and launches apps)
plasma/theme/sepia-summit/    Plasma style (generated SVGs; don't hand-edit, rerun make_plasma_style.py)
plasma/colors/                app colour scheme
konsole/                      Konsole profile and colour scheme
plasma/sepia-weather.py       weather fetcher + conky lines + `preview` (installed as ~/.local/bin/sepia-weather)
plasma/sepia-weather.{service,timer}  10-minute refresh
tools/make_wallpaper.py       generator (numpy + Pillow). --seed, --split, --only, --masks-only (_sky/_snow
                              masks + scene.js; the images themselves stay bit-identical)
tools/make_weather_assets.py  cloud/stratus/rain/snow/sun/sunglow/tree/leaf sprites → plasma/wallpaper/…/contents/images
tools/make_icons.py           cream line app icons → plasma/icons/sepia-summit (stdlib)
tools/make_plasma_style.py    glass frames, tasks highlights, audio/network icons → plasma/theme/sepia-summit
                              and plasma/icons/sepia-summit/scalable/status (stdlib)
plasma/trayitem/…/            dock button for a StatusNotifierItem tray app (code/sepia-trayitem.py via gdbus)
wallpapers/                   generated PNGs (+ _LEFT/_RIGHT halves for dual, + _front cut-outs,
                              + _sky masks: white with alpha = open sky, because MultiEffect masks by alpha,
                              + _snow masks: alpha = snow level)
docs/screenshots/             real README captures (hero, panel, gallery); IP + Hue light name blurred
```

## Design language (keep consistent)

| role | hex |
|---|---|
| darkest / panel background | `#1c120c` (conky at argb 150) |
| dark base | `#4a3221` |
| dim labels | `#b89b7c` |
| tan accent / headings | `#c4a074` |
| values | `#e4cca2` |
| cream text / bars | `#f5e8ca` (bars `#f5e6c8`) |
| warning | `#d9822b` |

- Fonts: Noto Serif for the clock and date (light / italic), Noto Sans Mono for stats, Noto Sans
  bold with letter spacing for section headings.
- Layout: apps and the dock on the **left** (left monitor), widgets on the **right** (right monitor).
- Wallpaper: tallest peak on the left, calmer sky on the right for the widgets. The sun is live.
  Valley line for the default `--split 3` is about 0.79 of the height, so the plugin baseline defaults to 80%.

## Roadmap (agreed with the owner, not built yet)

1. **Visualiser placement** — dual screens already use the right monitor only (per-screen
   `Visualiser` setting). Still to add: a choice of which monitor.
2. ~~**Lock screen**~~ — done. The greeter gives every monitor the same wallpaper config, so with two
   monitors and LIVE=1 it uses the plugin's `Span` mode (dual image, each monitor shows its slice from
   `Screen.virtualX`, bars on the rightmost only). Otherwise the single-screen image. Preview without
   locking: `/usr/libexec/kscreenlocker_greet --testing` (kill it afterwards).
3. **Login screen** — the owner's machine uses **Plasma Login Manager**: Breeze only, but set its
   wallpaper (maybe even the live plugin). If **SDDM**: a full custom `sepia-summit` SDDM theme.
   Bazzite is immutable, so themes go in a writable location; check the Bazzite docs.
4. ~~**Moving sun**~~ — done (with eclipses and meteor showers).
5. **Splash screen** — custom Plasma splash (the peak fading in on the sepia sky).
6. The friend's machine may have different hardware. Keep auto-detection robust: CPU
   thread count (the per-core bars are hard-coded to 16), non-NVIDIA GPUs (gpu.sh only knows
   nvidia-smi; AMD could use `/sys/class/drm/card*/device/gpu_busy_percent` + hwmon `amdgpu`).

## Conventions

- Keep install.sh idempotent and non-destructive. Back up user configs before overwriting
  (as done for cava). Never delete user files.
- Don't add heavy dependencies. Python stdlib only for anything installed on the host;
  numpy/Pillow are fine for the generator, which can run in a distrobox.
- Regenerating wallpapers changes about 90 MB of PNGs. Only commit them when the art actually changes.
- README images are real captures only (no mock-ups left). If a mock-up is ever needed, label it as one.
- README screenshots are real captures in `docs/screenshots/` (full native resolution, JPG q88). Shoot them with `sepia-weather preview …` and KWin Show Desktop (`qdbus-qt6 org.kde.KWin /KWin org.kde.KWin.showDesktop true`), blur the conky LAN IP and the Hue light name, never show the location, then `sepia-weather fetch`.
  Real screenshots from the owner's desktop are welcome.
- Remote: `github.com/NexusKiwi/Sepia-Summit` (branch `main`). The repo is public, so commit as
  `NexusKiwi <NexusKiwi@users.noreply.github.com>`.

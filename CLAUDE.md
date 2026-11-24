# CLAUDE.md — Sepia Summit

Context for Claude Code working in this repo. Read this first.

## What this is

Sepia Summit is a Rainmeter-style desktop "rice" for KDE Plasma 6 on Linux, built for the
owner's (NexusKiwi) PC and shared with friends. It has three parts:

1. **Wallpaper** — a procedural sepia mountain range (`tools/make_wallpaper.py`), rendered
   for dual, ultrawide and single screens from one shared "world", so every size shows the
   same mountains. Each image also has a `_front.png` cut-out of the nearer ridges.
2. **Conky panel** — a hardware stats panel on the right edge (`conky/sepia.conf` plus helper scripts).
3. **Live wallpaper** — a Plasma 6 wallpaper plugin (`plasma/wallpaper/com.nexuskiwi.sepiasummit`)
   that draws the wallpaper → full-width audio bars → the ridge cut-out, so the
   visualiser rises from the valley behind the mountains. A small local service
   (`plasma/sepia-cava-server.py`, run by `sepia-cava.service`) runs CAVA and serves
   its levels on `127.0.0.1:37421`. The QML polls that address about 30 times a second.

`install.sh` sets up everything and is safe to re-run. `README.md` is the user-facing doc.

## Owner's machine (primary target)

- **OS**: Bazzite (Fedora Atomic, immutable). KDE Plasma 6 on Wayland. Packages are added
  with `rpm-ostree install …` and need a reboot. Don't suggest `dnf install` on the host.
- **Hardware**: Ryzen 7 5800X (16 threads, `k10temp` sensor), RTX 3070 (nvidia-smi on the
  bazzite-nvidia image), 32 GB RAM, B550M board, NVMe storage, **two monitors**.
- The user's home data lives in `/var/home`, so the conky storage section uses that path.

## Status: IMPORTANT

Everything was written in a cloud sandbox **without KDE Plasma, Conky or a GPU**.

Verified there:
- the wallpaper generator
- the helper scripts (with simulated nvidia-smi output)
- the cava server (with a fake `cava`)
- an install.sh dry run
- set-wallpaper.js (with mocked Plasma APIs)

**Never run on real Plasma yet:**
- the conky config on Wayland
- the QML wallpaper plugin and its config page
- the evaluateScript wallpaper setter
- the systemd service

The first job on the real machine is to install and test, then fix what breaks.

### First-run test checklist
1. `systemctl status plasmalogin sddm` — note which login manager is active (needed for the roadmap).
2. Check `which conky cava`. If either is missing: `rpm-ostree install conky cava`, reboot.
3. `./install.sh` — read its output. Check the detected network adapter, disk and monitor index.
4. **Conky**: is it visible, on the right monitor and positioned well? If not, try the XWayland
   fallback lines in `sepia.conf`. Run `conky -c ~/.config/conky/sepia/sepia.conf` in the
   foreground to see errors. Check `conky --version`: `own_window_namespace` needs 1.25+.
5. **Live wallpaper**: if it's black or blank, run `systemctl --user restart plasma-plasmashell`, then
   `journalctl --user -b | grep -i -E "sepiasummit|qml"` for QML errors.
   Plasma 6 API points to check: the `WallpaperItem.configuration` keys, the
   `QtQuick.Effects` MultiEffect glow, XHR to localhost from the wallpaper, and the config.qml `cfg_` aliases.
6. **Audio**: `systemctl --user status sepia-cava` and `curl -s http://127.0.0.1:37421/`
   (it should print numbers while music plays).
7. Report what's off visually (spacing, font sizes, opacity) and tune.

## Repo layout

```
install.sh                    installer (bash, set -euo pipefail; env overrides HEAD IFACE DISK LIVE)
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
plasma/apply-dock.js          plasmashell evaluateScript: floating dock on the left monitor, hides desktop icons
plasma/drawer/…/              app drawer plasmoid (contents/code/sepia-drawer.py lists and launches apps)
plasma/theme/sepia-summit/    Plasma style (install.sh tints Breeze's panel and dialog artwork)
plasma/colors/                app colour scheme
konsole/                      Konsole profile and colour scheme
tools/make_wallpaper.py       generator (numpy + Pillow). --seed, --split, --only
wallpapers/                   generated PNGs (+ _LEFT/_RIGHT halves for dual, + _front cut-outs)
docs/                         README images (the panel close-up and live preview are MOCK-UPS)
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
- Wallpaper: sun and tallest peak on the left, calmer sky on the right for the widgets.
  Valley line for the default `--split 3` is about 0.79 of the height, so the plugin baseline defaults to 80%.

## Roadmap (agreed with the owner, not built yet)

1. **Visualiser placement modes** — dual screens: right monitor only (configurable which);
   ultrawide: full width; single: full width. Probably an `Enabled`/`Mode` option in
   main.xml, and set-wallpaper.js setting it per screen.
2. **Lock screen** — point the kscreenlocker image at the sepia wallpaper (add to install.sh).
3. **Login screen** — if **Plasma Login Manager**: Breeze only, but set its wallpaper (maybe
   even the live plugin). If **SDDM**: a full custom `sepia-summit` SDDM theme. Bazzite is
   immutable, so themes go in a writable location; check the Bazzite docs.
4. **Splash screen** — custom Plasma splash (the peak fading in on the sepia sky).
5. Optional: a matching Plasma colour scheme and Konsole profile.
6. The friend's machine may have different hardware. Keep auto-detection robust: CPU
   thread count (the per-core bars are hard-coded to 16), non-NVIDIA GPUs (gpu.sh only knows
   nvidia-smi; AMD could use `/sys/class/drm/card*/device/gpu_busy_percent` + hwmon `amdgpu`).

## Conventions

- Keep install.sh idempotent and non-destructive. Back up user configs before overwriting
  (as done for cava). Never delete user files.
- Don't add heavy dependencies. Python stdlib only for anything installed on the host;
  numpy/Pillow are fine for the generator, which can run in a distrobox.
- Regenerating wallpapers changes about 90 MB of PNGs. Only commit them when the art actually changes.
- Mock-up images in `docs/` must stay labelled as mock-ups until real screenshots replace them.
  Real screenshots from the owner's desktop are welcome.
- Remote: `github.com/NexusKiwi/Sepia-Summit` (branch `main`).

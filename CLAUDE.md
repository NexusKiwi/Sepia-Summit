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
- The tray arrow is the `arrow-up-symbolic` icon, so editing the Plasma style's arrows does nothing.

## Repo layout

```
install.sh                    installer (bash, set -euo pipefail; env overrides HEAD IFACE DISK LIVE DOCK THEME)
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

1. **Visualiser placement** — dual screens already use the right monitor only (per-screen
   `Visualiser` setting). Still to add: a choice of which monitor.
2. **Lock screen** — point the kscreenlocker image at the sepia wallpaper (add to install.sh).
3. **Login screen** — the owner's machine uses **Plasma Login Manager**: Breeze only, but set its
   wallpaper (maybe even the live plugin). If **SDDM**: a full custom `sepia-summit` SDDM theme.
   Bazzite is immutable, so themes go in a writable location; check the Bazzite docs.
4. **Splash screen** — custom Plasma splash (the peak fading in on the sepia sky).
5. The friend's machine may have different hardware. Keep auto-detection robust: CPU
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
- Remote: `github.com/NexusKiwi/Sepia-Summit` (branch `main`). The repo is public, so commit as
  `NexusKiwi <NexusKiwi@users.noreply.github.com>`.

# Sepia Summit

**A Rainmeter-style sepia desktop for Linux: KDE Plasma 6, Bazzite and Fedora Atomic.**

![Sepia Summit on dual monitors, with the visualiser rising behind the ridges](docs/preview-live.jpg)

<sub>Mock-up: the visualiser rises from the valley behind the nearer ridges.</sub>

<p align="center"><img src="docs/panel-closeup.png" width="360" alt="Conky stats panel close-up (mock-up)"></p>
<p align="center"><sub>Panel preview is a mock-up; real numbers come from your hardware.</sub></p>

What's included:

- **Wallpaper**: a sepia mountain range generated for this kit. It comes in sizes for dual 1440p, dual 1080p, ultrawide (3440 and 2560) and single screens. All sizes show the same mountains, so the scene carries across both monitors. The tall peaks sit on the left, with calmer sky on the right where the widgets go.
- **Conky stats panel** (right edge): clock, CPU load/temp/clock speed with 16 per-thread bars, RTX 3070 load/temp/VRAM/power/fan, RAM/swap, drive space, NVMe temps, disk read/write, network and top processes.
- **Live wallpaper with the visualiser behind the mountains**: a Plasma 6 wallpaper plugin draws the wallpaper, then audio bars across the full width of each screen, then a cut-out of the nearer ridges on top. The bars look like they're rising out of the valley behind the mountains. When nothing is playing it's just the normal wallpaper.
- **Left side**: a vertical app panel for your programs.

Conky and the live wallpaper draw natively, so they use far less than Rainmeter did. Expect well under 1% CPU.

```
install.sh                 one-shot installer (safe to re-run)
conky/sepia.conf           the stats panel
conky/scripts/temps.sh     CPU + NVMe temps (finds sensors by name)
conky/scripts/gpu.sh       NVIDIA stats (cached nvidia-smi)
cava/config                sepia colours for terminal CAVA
plasma/wallpaper/          the live wallpaper plugin (com.nexuskiwi.sepiasummit)
plasma/sepia-cava-server.py  runs CAVA and serves audio levels on 127.0.0.1:37421
plasma/sepia-cava.service  user service that keeps the server running
plasma/set-wallpaper.js    picks the right images for each monitor
wallpapers/                all the PNGs: dual images come pre-split _LEFT/_RIGHT,
                           and every image has a _front.png ridge cut-out
tools/make_wallpaper.py    the generator, if you want different mountains
```

---

## 1. Install

```bash
git clone https://github.com/NexusKiwi/sepia-summit.git
cd sepia-summit
```

Then:

```bash
./install.sh
```

The first run notices that `conky` and `cava` are missing and offers to layer them with `rpm-ostree`. Say **y**, **reboot**, then run `./install.sh` again. The second run:

- detects your network adapter, main drive, any extra drives mounted under `/run/media` or `/var/mnt` (game drives etc.), and how many monitors you have
- installs the conky panel and adds it to autostart
- installs the live wallpaper plugin and starts the audio service (`sepia-cava.service`)
- copies the wallpapers to `~/Pictures/Wallpapers/sepia-mountains` and sets them **per monitor**. With two screens, the left screen gets the left half and the right screen gets the right half. With an ultrawide, it gets the ultrawide image.

If it guesses something wrong, you can override it:
```bash
HEAD=0 ./install.sh            # put conky on the other monitor
IFACE=enp5s0 DISK=nvme1n1 ./install.sh
LIVE=0 ./install.sh            # plain static wallpaper, no visualiser
```

## 2. The left side: your apps

Plasma does this natively, with no extra installs:

1. Right-click your current panel → **Show Panel Configuration** → set **Position: Left**. Or add a new panel: right-click desktop → **Add Panel → Empty Panel**, then move it left.
2. Set the width to about 56–64 px. Turn on **Floating** for that detached look.
3. Add widgets to it: **Application Launcher** at the top, **Icons-only Task Manager** (pin your apps), a **Spacer**, then **System Tray** and **Digital Clock** at the bottom. Conky already shows the big clock, so you can drop the panel clock if you like.
4. If you have two monitors, put the panel only on the **left** monitor. That keeps the right one clean for the widgets.

## 3. The visualiser behind the mountains

This works once the installer has run. Play anything — Spotify, YouTube, a game — and bars rise from behind the middle ridge on every screen.

How it works: `sepia-cava.service` runs CAVA and serves the audio levels on `127.0.0.1` only. The wallpaper plugin reads them about 30 times a second and draws the bars between the wallpaper and the ridge cut-out.

To adjust it, right-click the desktop → **Desktop and Wallpaper**. With **Sepia Summit (live)** selected, you can change:

| setting | default | what it does |
|---|---|---|
| Bars per screen | 96 | more = thinner bars |
| Valley line | 80% | where the bars start, measured from the top. Keep it below the ridge so the bases stay hidden |
| Max bar height | 42% | how far up the sky they can reach |
| Opacity | 50% | lower = hazier, more like light than bars |
| Bar colour | `#f5e6c8` | try `#e4cca2` for warmer bars |
| Glow | on | soft bloom around the bars |

**Bars behind a different ridge:** regenerate with `--split`. 0 is the farthest range and 5 the nearest; the default is 3. Higher numbers put more mountains in front of the bars:
```bash
python3 tools/make_wallpaper.py wallpapers --split 2
```

You can still add the **Kurve** widget for a small visualiser somewhere else. Find it under Add Widgets → Get New Widgets and search "Kurve".

## 4. Make the rest of Plasma match

- **System Settings → Colours & Themes → Colours**: pick Breeze Dark. Click the accent colour picker and set a custom accent of `#c4a074`.
- **Window decorations**: Breeze with "No borders" gives a cleaner look for screenshots.
- **Konsole**: make a profile with background `#1c120c` at about 85% opacity, foreground `#f5e8ca`, and blur on.
- **Font**: for a vintage feel, set the window title font to *Noto Serif*.

## 5. Customising

- **Different CPU?** The panel shows 16 per-thread bars (a Ryzen 7 5800X). For a different thread count, add or remove `${cpubar cpuN 3,34}` entries in the PROCESSOR section. The GPU section needs an NVIDIA card (it uses `nvidia-smi`).
- **Panel layout/colours**: edit `~/.config/conky/sepia/sepia.conf`. Conky reloads by itself when you save. The colours are `color1`–`color4` near the top. `own_window_argb_value` sets panel opacity (0 = see-through, 255 = solid).
- **Different mountains**: change the seed. This needs numpy and pillow; on Bazzite, run it in a distrobox:
  ```bash
  python3 tools/make_wallpaper.py wallpapers --seed 7
  ```
  Then re-run `./install.sh`. Try a few seeds — each gives a different range. The sun position and sepia palette are at the top of the script.

## Troubleshooting

**Conky doesn't show up, or flickers.** Conky's Wayland support on KDE still varies between versions. Open `sepia.conf` and swap to the XWayland fallback. The lines are already in the file, commented out:
```lua
out_to_wayland = false, out_to_x = true,
own_window_type = 'desktop',
```
In XWayland mode, you can also pin it to a monitor with a KWin Window Rule: System Settings → Window Rules, match window class `Conky`.

**It's on the wrong monitor.** Run `HEAD=0 ./install.sh` (or `HEAD=1`). If Wayland ignores that, use the XWayland fallback above plus a Window Rule.

**It disappears when I press Meta+D.** You need conky 1.25 or newer, where `own_window_namespace = 'desktop'` keeps it visible. Older builds just hide it.

**Temps show `--`.** Run `~/.config/conky/sepia/scripts/temps.sh cpu`. AMD CPU temps come from the `k10temp` sensor, which loads by default on Bazzite.

**The wallpaper went black after install.** Plasma hasn't picked up the new plugin yet. Run `systemctl --user restart plasma-plasmashell`. If you'd rather not use it, run `LIVE=0 ./install.sh` to go back to the plain image.

**The bars don't move.** Check the audio service:
```bash
systemctl --user status sepia-cava
curl -s http://127.0.0.1:37421/ | head -c 80; echo   # should print numbers while music plays
```
If `cava` isn't found, layer it (`rpm-ostree install cava`) and reboot.

**GPU shows `no nvidia-smi`.** You need the `bazzite-nvidia` image. It ships `nvidia-smi`.

## Inspiration

The old /g/ desktop threads live on as **r/unixporn**: search "sepia", "conky" or "kde". If you ever try a tiling setup like Hyprland, look at **Eww** and **Quickshell**. They're the next step past conky: fully scriptable bars and widgets, the closest thing to "Rainmeter, but with no limits".

## License

MIT. The wallpapers are generated by `tools/make_wallpaper.py` and are free to use, share and remix.

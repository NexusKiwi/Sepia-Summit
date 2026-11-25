# Sepia Summit

**A Rainmeter-style sepia desktop for Linux: KDE Plasma 6, Bazzite and Fedora Atomic.**

![Sepia Summit on dual monitors, with the visualiser rising behind the ridges](docs/preview-live.jpg)

<sub>Mock-up: the visualiser rises from the valley behind the nearer ridges.</sub>

<p align="center"><img src="docs/panel-closeup.png" width="360" alt="Conky stats panel close-up (mock-up)"></p>
<p align="center"><sub>Panel preview is a mock-up; real numbers come from your hardware.</sub></p>

What's included:

- **Wallpaper**: a sepia mountain range generated for this kit. It comes in sizes for dual 1440p, dual 1080p, ultrawide (3440 and 2560) and single screens. All sizes show the same mountains, so the scene carries across both monitors. The tall peaks sit on the left, with calmer sky on the right where the widgets go.
- **Conky stats panel** (right edge): clock, today's weather, CPU load/temp/clock speed with 16 per-thread bars, RTX 3070 load/temp/VRAM/power/fan, RAM/swap, drive space, NVMe temps, disk read/write, network and top processes.
- **Live wallpaper with the visualiser behind the mountains**: a Plasma 6 wallpaper plugin draws the wallpaper, then full-width audio bars (on the right monitor with two screens), then a cut-out of the nearer ridges on top. The bars look like they're rising out of the valley behind the mountains. When nothing is playing it's just the normal wallpaper.
- **Live weather and day/night**: clouds drift behind the peaks on cloudy days, the sky greys over when it's overcast, and faint rain, snow or valley fog appear when the real weather does. The scene glows at sunrise and sunset and goes dark and starry at night, following the real sun where you live, so daylight saving and the seasons take care of themselves.
- **Floating dock and app drawer** (left monitor): the dock shows only your open apps. The drawer sorts everything into Games, Apps and System, with search and lock, log out, sleep, restart and shut down buttons.
- **Matching theme**: a sepia Plasma style, app colours and Konsole profile.

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
plasma/sepia-weather.py    fetches the weather (Open-Meteo, free, no account)
plasma/sepia-weather.timer refreshes it every 10 minutes
plasma/set-wallpaper.js    picks the right images for each monitor
plasma/apply-dock.js       sets up the floating dock
plasma/drawer/             the app drawer widget
plasma/theme/, plasma/colors/, konsole/   Plasma style, app colours, Konsole profile
wallpapers/                all the PNGs: dual images come pre-split _LEFT/_RIGHT,
                           and every image has a _front.png ridge cut-out and
                           a _sky.png mask (where clouds and stars may go)
tools/make_wallpaper.py    the generator, if you want different mountains
tools/make_weather_assets.py  draws the clouds, rain and snow sprites
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

If `cava` is missing, the first run offers to layer it with `rpm-ostree`. Say **y**, **reboot**, then run `./install.sh` again. The installer restarts Plasma a few times, so save your work first. It:

- detects your network adapter, main drive, any extra drives mounted under `/run/media` or `/var/mnt` (game drives etc.), and how many monitors you have
- installs the conky panel and adds it to autostart
- asks for your nearest town once, for the weather and the day/night sky (a town is enough; only its coordinates are sent to Open-Meteo)
- installs the live wallpaper plugin and starts the audio service (`sepia-cava.service`)
- copies the wallpapers to `~/Pictures/Wallpapers/sepia-mountains` and sets them **per monitor**. With two screens, the left screen gets the left half and the right screen gets the right half. With an ultrawide, it gets the ultrawide image.
- replaces your taskbars with the floating dock and app drawer, and hides desktop icons from view (the files stay in `~/Desktop`)
- sets the lock screen to the sepia mountains, matching the desktop across both monitors when there are two (your previous lock screen settings are backed up)
- applies the sepia Plasma style, app colours and Konsole profile

Your previous settings are saved in `~/.local/share/sepia-summit/backups/`.

If it guesses something wrong, you can override it:
```bash
HEAD=0 ./install.sh            # put conky on the other monitor
IFACE=enp5s0 DISK=nvme1n1 ./install.sh
LIVE=0 ./install.sh            # plain static wallpaper, no visualiser
DOCK=0 ./install.sh            # keep your own panels and desktop icons
THEME=0 ./install.sh           # keep your Plasma style, colours and Konsole profile
LOCK=0 ./install.sh            # keep your own lock screen picture
PLACE="Lisbon" ./install.sh    # set or change the weather town without being asked
```

## 2. The dock and app drawer

The dock floats at the bottom of the left monitor and holds the drawer button, your open apps and a tray arrow. It stays out of the way of your windows: it shows on a clear desktop and slips away when a window covers it, so maximised windows fill the whole screen. Push the mouse to the bottom edge under the dock and it floats up over them. The grid button or the Meta key opens the drawer. Type to search, and press Enter to launch the first result. The buttons beside the search bar lock, log out, sleep, restart and shut down. Hibernate also appears if your system supports it. Log out, restart and shut down always ask first.

## 3. The visualiser behind the mountains

This works once the installer has run. Play anything — Spotify, YouTube, a game — and bars rise from behind the middle ridge. With two monitors they appear on the right one only.

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

## 4. Weather and day/night

`sepia-weather` fetches the current weather every 10 minutes (`sepia-weather.timer`). Conky shows it under the date, and the live wallpaper turns it into the sky: clouds for cloud cover, a grey deck when it's overcast, faint rain, snow, valley fog, and a soft glow for thunderstorms. Day and night follow the sun's real position at your town.

```bash
sepia-weather setup "Your town"     # change the location
sepia-weather preview rain night    # try a look: clear partly cloudy overcast fog drizzle
                                    #   rain showers snow storm, at day / dusk / night
sepia-weather fetch                 # back to the real weather
```

Both parts can be switched off per screen in the wallpaper settings (Desktop → Configure → Sky).

## 5. Optional finishing touches

The installer already applies the Plasma style, app colours and Konsole profile. Two extras you can set by hand:

- **Window decorations**: Breeze with "No borders" gives a cleaner look for screenshots.
- **Font**: for a vintage feel, set the window title font to *Noto Serif*.

## 6. Customising

- **Different CPU?** The panel shows 16 per-thread bars (a Ryzen 7 5800X). For a different thread count, add or remove `${cpubar cpuN 3,34}` entries in the PROCESSOR section. The GPU section needs an NVIDIA card (it uses `nvidia-smi`).
- **Panel layout/colours**: edit `~/.config/conky/sepia/sepia.conf`. Conky reloads by itself when you save, but on Wayland the reloaded panel can open on the wrong monitor; log out and in (or re-run the autostart command) to put it back. The colours are `color1`–`color4` near the top. Panel opacity and corner radius are `ALPHA` and `RADIUS` at the top of `~/.config/conky/sepia/scripts/panel.lua`.
- **Different mountains**: change the seed. This needs numpy and pillow; on Bazzite, run it in a distrobox:
  ```bash
  python3 tools/make_wallpaper.py wallpapers --seed 7
  ```
  Then re-run `./install.sh`. Try a few seeds — each gives a different range. The sun position and sepia palette are at the top of the script.

## Troubleshooting

**Conky doesn't show up.** Run `~/.local/bin/sepia-conky -c ~/.config/conky/sepia/sepia.conf` in a terminal to see its errors. The panel needs conky 1.25 or newer on Wayland. `install.sh` downloads a verified copy to `~/.local/bin/sepia-conky` if your system version is older.

**It's on the wrong monitor.** Run `HEAD=0 ./install.sh` for the leftmost monitor, `HEAD=1` for the next one, and so on.

**Temps show `--`.** Run `~/.config/conky/sepia/scripts/temps.sh cpu`. AMD CPU temps come from the `k10temp` sensor, which loads by default on Bazzite.

**The wallpaper went black after install.** Plasma hasn't picked up the new plugin yet. Run `systemctl --user restart plasma-plasmashell`. If you'd rather not use it, run `LIVE=0 ./install.sh` to go back to the plain image.

**The bars don't move.** Check the audio service:
```bash
systemctl --user status sepia-cava
curl -s http://127.0.0.1:37421/ | head -c 80; echo   # should print numbers while music plays
```
If `cava` isn't found, layer it (`rpm-ostree install cava`) and reboot.

**No weather / "weather unavailable".** Check `sepia-weather fetch` prints no error and `systemctl --user list-timers sepia-weather.timer` shows a next run. The wallpaper reads `~/.cache/sepia-summit/weather.qml`, which should exist and be recent.

**GPU shows `no nvidia-smi`.** You need the `bazzite-nvidia` image. It ships `nvidia-smi`.

## Inspiration

The old /g/ desktop threads live on as **r/unixporn**: search "sepia", "conky" or "kde". If you ever try a tiling setup like Hyprland, look at **Eww** and **Quickshell**. They're the next step past conky: fully scriptable bars and widgets, the closest thing to "Rainmeter, but with no limits".

## License

MIT. The wallpapers are generated by `tools/make_wallpaper.py` and are free to use, share and remix.

#!/usr/bin/env python3
"""Cream line-art app icons for the Sepia Summit icon theme (plasma/icons/sepia-summit).

The theme only holds these few icons and inherits everything else from the icon theme that was in
use (install.sh fills in Inherits=). Each drawing is saved under every icon name its app uses, so a
browser gets its own icon whichever packaging (Flatpak or distro) is installed.

    python3 tools/make_icons.py          # stdlib only
"""
import math
import os

CREAM, TAN = "#f5e8ca", "#c4a074"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "plasma", "icons", "sepia-summit")


def svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">'
            f'<g fill="none" stroke="{CREAM}" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round">'
            f'{body}</g></svg>\n')


def chrome():
    lines = []
    for k in range(3):                       # three tangents off the centre disc to the rim
        a = math.radians(120 * k)
        p = lambda x, y: (32 + (x - 32) * math.cos(a) - (y - 32) * math.sin(a),
                          32 + (x - 32) * math.sin(a) + (y - 32) * math.cos(a))
        (x1, y1), (x2, y2) = p(32, 23), p(32 + math.sqrt(26 ** 2 - 9 ** 2), 23)
        lines.append(f'<line x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}"/>')
    return ('<circle cx="32" cy="32" r="26"/>' + "".join(lines) +
            f'<circle cx="32" cy="32" r="9" stroke="{TAN}"/>')


def claude():
    rays = []
    for k in range(12):
        a = math.radians(k * 30 + 8)
        r2 = 25 if k % 2 == 0 else 18
        rays.append(f'<line x1="{32 + 6 * math.cos(a):.2f}" y1="{32 + 6 * math.sin(a):.2f}" '
                    f'x2="{32 + r2 * math.cos(a):.2f}" y2="{32 + r2 * math.sin(a):.2f}"/>')
    return "".join(rays) + f'<circle cx="32" cy="32" r="2.6" fill="{TAN}" stroke="none"/>'


ICONS = {
    # wheel and piston
    ("steam",): '<circle cx="32" cy="32" r="26"/>'
                '<circle cx="40" cy="25" r="8.5"/>'
                f'<circle cx="40" cy="25" r="3" fill="{TAN}" stroke="none"/>'
                '<circle cx="22.5" cy="41.5" r="5"/>'
                '<path d="M26.5 38.5 L33 31.5"/><path d="M6.5 37 L17.8 40.2"/>',
    # a friendly controller face
    ("discord",): '<path d="M15 19 Q32 12 49 19 Q55 31 55 45 Q49 51 42 51 L39 46 Q32 48 25 46 L22 51 '
                  'Q15 51 9 45 Q9 31 15 19 Z"/>'
                  f'<ellipse cx="25" cy="34" rx="3.6" ry="4.2" fill="{CREAM}" stroke="none"/>'
                  f'<ellipse cx="39" cy="34" rx="3.6" ry="4.2" fill="{CREAM}" stroke="none"/>',
    # a spark
    ("claude", "claude-desktop", "io.github.aaddrick.claude-desktop-debian", "com.anthropic.claude"): claude(),
    # a prompt
    ("utilities-terminal", "org.kde.konsole", "terminal"): '<rect x="8" y="12" width="48" height="40" rx="7"/>'
                  '<path d="M18 26 L26 32 L18 38"/>'
                  f'<path d="M31 40 L44 40" stroke="{TAN}"/>',
    # a folder
    ("org.kde.dolphin", "system-file-manager"): '<path d="M8 18 Q8 14 12 14 L24 14 L29.5 19.5 L52 19.5 '
                  'Q56 19.5 56 23.5 L56 48 Q56 52 52 52 L12 52 Q8 52 8 48 Z"/>'
                  f'<path d="M8 27 L56 27" stroke="{TAN}"/>',
    # three overlapping lights
    ("OpenRGB", "openrgb", "org.openrgb.OpenRGB"): '<circle cx="32" cy="23" r="13"/>'
                  '<circle cx="22.5" cy="39.5" r="13"/>'
                  f'<circle cx="41.5" cy="39.5" r="13" stroke="{TAN}"/>',
    # the app drawer button: a 3 x 3 grid of rounded tiles, the centre one tan
    ("sepia-app-grid",): "".join(f'<rect x="{x}" y="{y}" width="11" height="11" rx="2"'
                                 + (f' stroke="{TAN}"' if (x, y) == (26.5, 26.5) else "") + "/>"
                                 for y in (11.5, 26.5, 41.5) for x in (11.5, 26.5, 41.5)),
    ("com.google.Chrome", "google-chrome", "chrome", "chromium", "org.chromium.Chromium"): chrome(),
    # a fox curled round a small globe
    ("org.mozilla.firefox", "firefox"): f'<circle cx="33" cy="34" r="12" stroke="{TAN}"/>'
                  '<path d="M15 21 C8 35 13 54 32 56.5 C49 58 59 45 56.5 30 C55 21 48 13.5 39 10.5 '
                  'C45 16 46 23 43.5 28 C40 21 33 18.5 26 20"/>',
    # a lion's head on a shield
    ("com.brave.Browser", "brave-browser", "brave"): '<path d="M21 9 L43 9 L49 15.5 L54 15 L56.5 21 L52.5 39 '
                  'Q48.5 49.5 32 56 Q15.5 49.5 11.5 39 L7.5 21 L10 15 L15 15.5 Z"/>'
                  f'<path d="M27 38 L37 38 L32 44 Z" stroke="{TAN}"/>'
                  '<path d="M20.5 27.5 L27 31"/><path d="M43.5 27.5 L37 31"/>',
}


def main():
    d = os.path.join(OUT, "scalable", "apps")
    os.makedirs(d, exist_ok=True)
    for names, body in ICONS.items():
        for n in names:
            with open(os.path.join(d, n + ".svg"), "w") as f:
                f.write(svg(body))
    print("wrote", sum(len(n) for n in ICONS), "icons to", os.path.normpath(d))


if __name__ == "__main__":
    main()

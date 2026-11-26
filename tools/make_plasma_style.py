#!/usr/bin/env python3
"""Artwork for the Sepia Summit Plasma style (plasma/theme/sepia-summit), matching the conky panel:
dark sepia glass with 16 px corners and a faint cream edge.

  translucent/widgets/panel-background.svg   the dock, over KWin blur
  widgets/panel-background.svg               the same without blur (more opaque)
  translucent/dialogs/background.svg         popups (tray, volume, network, the app drawer)
  dialogs/background.svg                     popups without blur
  widgets/tasks.svg                          the dock's running / active app highlights
  icons/audio.svg, icons/network.svg         cream line icons for the volume and network widgets

Plasma frames are 9-slice: elements named topleft, top, ... center (plus mask-* for the blur shape
and hint-*-margin for padding). Icons the style doesn't draw fall back to the icon theme.

    python3 tools/make_plasma_style.py      # stdlib only
"""
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "plasma", "theme", "sepia-summit")
DARK, CREAM, TAN, WARN = "#1c120c", "#f5e8ca", "#c4a074", "#d9822b"


def frame(prefix, ox, oy, R, fill, fill_op, edge_op=0.0, sw=1.0, mask=False, L=32):
    """One 9-slice frame laid out edge to edge from (ox, oy) like Breeze's: R x R corners, edges L
    long, an L x L centre. Absolute coordinates, no transforms. Returns SVG text."""
    p = (prefix + "-") if prefix else ""
    w, q = sw, R - sw     # the edge is a filled band, not a stroke: a stroke pads the element's
    x0, x1, x2, x3 = ox, ox + R, ox + R + L, ox + 2 * R + L      # bounds by half its width and
    y0, y1, y2, y3 = oy, oy + R, oy + R + L, oy + 2 * R + L      # Plasma stretches that gap
    rect = lambda a, b, c, d: f"M{a},{b} H{c} V{d} H{a} Z"
    pieces = {  # name: (box, fill path, edge path)
        "topleft": ((x0, y0, R, R), f"M{x1},{y0} A{R},{R} 0 0 0 {x0},{y1} L{x1},{y1} Z",
                    f"M{x1},{y0} A{R},{R} 0 0 0 {x0},{y1} H{x0 + w} A{q},{q} 0 0 1 {x1},{y0 + w} Z"),
        "top": ((x1, y0, L, R), rect(x1, y0, x2, y1), rect(x1, y0, x2, y0 + w)),
        "topright": ((x2, y0, R, R), f"M{x2},{y0} A{R},{R} 0 0 1 {x3},{y1} L{x2},{y1} Z",
                     f"M{x2},{y0} A{R},{R} 0 0 1 {x3},{y1} H{x3 - w} A{q},{q} 0 0 0 {x2},{y0 + w} Z"),
        "left": ((x0, y1, R, L), rect(x0, y1, x1, y2), rect(x0, y1, x0 + w, y2)),
        "center": ((x1, y1, L, L), rect(x1, y1, x2, y2), ""),
        "right": ((x2, y1, R, L), rect(x2, y1, x3, y2), rect(x3 - w, y1, x3, y2)),
        "bottomleft": ((x0, y2, R, R), f"M{x1},{y2} L{x1},{y3} A{R},{R} 0 0 1 {x0},{y2} Z",
                       f"M{x1},{y3} A{R},{R} 0 0 1 {x0},{y2} H{x0 + w} A{q},{q} 0 0 0 {x1},{y3 - w} Z"),
        "bottom": ((x1, y2, L, R), rect(x1, y2, x2, y3), rect(x1, y3 - w, x2, y3)),
        "bottomright": ((x2, y2, R, R), f"M{x2},{y2} L{x3},{y2} A{R},{R} 0 0 1 {x2},{y3} Z",
                        f"M{x3},{y2} A{R},{R} 0 0 1 {x2},{y3} V{y3 - w} A{q},{q} 0 0 0 {x3 - w},{y2} Z"),
    }
    out = []
    for name, ((bx, by, bw, bh), fp, ep) in pieces.items():
        g = [f'<g id="{p}{name}">',
             f'<rect x="{bx}" y="{by}" width="{bw}" height="{bh}" fill="#000" opacity="0.001"/>']   # the element's size
        if mask:
            g.append(f'<path d="{fp}" fill="#000"/>')
        else:
            g.append(f'<path d="{fp}" fill="{fill}" fill-opacity="{fill_op}"/>')
            if ep and edge_op:
                g.append(f'<path d="{ep}" fill="{CREAM}" fill-opacity="{edge_op}"/>')
        g.append("</g>")
        out.append("".join(g))
    return "\n".join(out)


def hints(prefix, ox, oy, margin):
    p = (prefix + "-") if prefix else ""
    return "\n".join([
        f'<rect id="{p}hint-top-margin" x="{ox}" y="{oy}" width="10" height="{margin}" fill="#000" opacity="0.001"/>',
        f'<rect id="{p}hint-bottom-margin" x="{ox + 12}" y="{oy}" width="10" height="{margin}" fill="#000" opacity="0.001"/>',
        f'<rect id="{p}hint-left-margin" x="{ox + 24}" y="{oy}" width="{margin}" height="10" fill="#000" opacity="0.001"/>',
        f'<rect id="{p}hint-right-margin" x="{ox + 36}" y="{oy}" width="{margin}" height="10" fill="#000" opacity="0.001"/>',
    ])


def doc(body, w=400, h=400):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">\n'
            f'{body}\n</svg>\n')


STRETCH = '<rect id="hint-stretch-borders" x="190" y="100" width="4" height="4" fill="#000" opacity="0.001"/>'


def glass(tint, edge, margin, R=16):
    # 1.5 px cream edge like the conky panel. Stretched, not tiled: tiling a translucent edge leaves a hairline at every tile boundary
    return doc(frame("", 0, 0, R, DARK, tint, edge, sw=1.5) + "\n" + frame("mask", 100, 0, R, DARK, 1, mask=True)
               + "\n" + hints("", 0, 100, margin) + "\n" + STRETCH)


def tasks():
    R, parts = 10, []
    looks = {  # prefix: (colour, fill opacity, edge opacity)
        "normal": (CREAM, 0.05, 0.0), "minimized": (CREAM, 0.025, 0.0), "hover": (CREAM, 0.10, 0.10),
        "focus": (CREAM, 0.14, 0.16), "attention": (WARN, 0.30, 0.0), "progress": (TAN, 0.28, 0.0),
    }
    for i, (name, (col, op, edge)) in enumerate(looks.items()):
        parts.append(frame(name, 0, i * 60, R, col, op, edge))
        parts.append(hints(name, 60, i * 60, 3))
    return doc("\n".join(parts) + "\n" + STRETCH, 200, 380)


# ---- icons: 22 x 22, cream lines --------------------------------------------------------
def icon(name, i, body):
    x, y = (i % 16) * 24, (i // 16) * 24
    return (f'<g id="{name}" transform="translate({x},{y})"><rect width="22" height="22" fill="#000" opacity="0.001"/>'
            f'<g fill="none" stroke="{CREAM}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">'
            f'{body}</g></g>')


SPEAKER = '<path d="M3.5 8.5 H7 L11.5 4.5 V17.5 L7 13.5 H3.5 Z"/>'
WAVES = ['<path d="M14.2 9 Q15.6 11 14.2 13"/>', '<path d="M16.4 6.8 Q19.2 11 16.4 15.2"/>',
         '<path d="M18.6 4.8 Q22.4 11 18.6 17.2"/>']


def audio():
    items = [
        ("audio-volume-muted", SPEAKER + '<path d="M15 8.5 L19.5 13.5 M19.5 8.5 L15 13.5" stroke-opacity="0.8"/>'),
        ("audio-volume-low", SPEAKER + WAVES[0] + "".join(w.replace("/>", ' stroke-opacity="0.3"/>') for w in WAVES[1:])),
        ("audio-volume-medium", SPEAKER + "".join(WAVES[:2]) + WAVES[2].replace("/>", ' stroke-opacity="0.3"/>')),
        ("audio-volume-high", SPEAKER + "".join(WAVES)),
        ("audio-volume-high-warning", SPEAKER + "".join(WAVES[:2]) + WAVES[2].replace("/>", f' stroke="{WARN}"/>')),
        ("audio-volume-high-danger", SPEAKER + WAVES[0] + "".join(w.replace("/>", f' stroke="{WARN}"/>') for w in WAVES[1:])),
    ]
    items += [("16-16-" + n, b) for n, b in items]
    return items


PLUG = '<rect x="6.5" y="8" width="9" height="7" rx="2"/><path d="M9 8 V4.5 M13 8 V4.5 M11 15 V19"/>'
WARN_DOT = f'<circle cx="18" cy="4.5" r="1.6" fill="{WARN}" stroke="none"/>'
SLASH = '<path d="M4 18 L18 4" stroke-opacity="0.85"/>'


def wifi(lit, extra=""):
    arcs = []
    for k, r in enumerate((4.5, 8.5, 12.5)):
        dx = r * 0.7071
        op = "" if k < lit else ' stroke-opacity="0.3"'
        arcs.append(f'<path d="M{11 - dx:.2f} {17 - dx:.2f} A{r} {r} 0 0 1 {11 + dx:.2f} {17 - dx:.2f}"{op}/>')
    return "".join(arcs) + f'<circle cx="11" cy="17" r="1.4" fill="{CREAM}" stroke="none"/>' + extra


def network():
    dim = lambda b: f'<g opacity="0.45">{b}</g>'
    items = [
        ("network-wired-activated", PLUG), ("network-wired-activated-locked", PLUG),
        ("network-wired-activated-limited", PLUG + WARN_DOT), ("network-wired-available", dim(PLUG)),
        ("network-wired", dim(PLUG)), ("network-unavailable", dim(PLUG) + SLASH),
        ("network-vpn", '<path d="M11 3.5 L17.5 6 V11 Q17.5 16 11 18.5 Q4.5 16 4.5 11 V6 Z"/><path d="M8.5 11 L10.5 13 L14 9"/>'),
        ("network-wireless-disconnected", wifi(0, SLASH)), ("network-wireless-off", wifi(0, SLASH)),
        ("network-wireless-available", wifi(3)), ("network-wireless-on", wifi(3)),
    ]
    for lvl, lit in (("00", 0), ("0", 0), ("20", 1), ("40", 1), ("60", 2), ("80", 3), ("100", 3)):
        if lvl != "0":
            items.append((f"network-wireless-connected-{lvl}", wifi(lit)))
        if lvl != "00":
            items += [(f"network-wireless-{lvl}", wifi(lit)), (f"network-wireless-{lvl}-locked", wifi(lit)),
                      (f"network-wireless-{lvl}-limited", wifi(lit, WARN_DOT))]
    return items


def icon_sheet(items, h):
    return doc("\n".join(icon(n, i, b) for i, (n, b) in enumerate(items)), 400, h)


ICON_THEME = os.path.join(OUT, "..", "..", "icons", "sepia-summit", "scalable", "status")


def icon_files(items):
    """The same drawings as standalone icons for the icon theme (plain and -symbolic names), for
    widgets that ask the icon theme rather than the Plasma style."""
    os.makedirs(ICON_THEME, exist_ok=True)
    for name, body in items:
        if name.startswith("16-16-"):
            continue
        text = (f'<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 22 22">'
                f'<g fill="none" stroke="{CREAM}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">'
                f'{body}</g></svg>\n')
        for n in (name, name + "-symbolic"):
            with open(os.path.join(ICON_THEME, n + ".svg"), "w") as f:
                f.write(text)


def main():
    files = {
        "translucent/widgets/panel-background.svg": glass(0.42, 0.12, 4),
        "widgets/panel-background.svg": glass(0.88, 0.12, 4),
        "translucent/dialogs/background.svg": glass(0.41, 0.12, 12),
        "dialogs/background.svg": glass(0.92, 0.12, 12),
        "widgets/tasks.svg": tasks(),
        "icons/audio.svg": icon_sheet(audio(), 60),
        "icons/network.svg": icon_sheet(network(), 100),
    }
    for path, text in files.items():
        full = os.path.join(OUT, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as f:
            f.write(text)
    icon_files(audio() + network())
    print("wrote", len(files), "files to", os.path.normpath(OUT), "and the status icons to", os.path.normpath(ICON_THEME))


if __name__ == "__main__":
    main()

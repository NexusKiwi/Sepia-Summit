#!/usr/bin/env python3
"""Find a tray (StatusNotifierItem) app by its Id and click it, like the system tray does.

    sepia-trayitem.py status ID      prints 1 if the app's tray icon is registered, else 0
    sepia-trayitem.py source ID      prints its tray source ("service/path", what the system tray
                                     widget calls DataEngineSource), or nothing
    sepia-trayitem.py activate ID    left click (usually shows or hides the app's window)
    sepia-trayitem.py menu ID X Y    right click: ask the app for its menu at X, Y
    sepia-trayitem.py trigger ID LABEL   click the entry LABEL in the app's tray menu; prints 1 if it
                                         was found, else 0
"""
import re
import subprocess
import sys


def gdbus(*args):
    """One D-Bus call; "" if it fails, so a hung tray app or a missing gdbus reads as "not there"."""
    try:
        return subprocess.run(["gdbus", "call", "--session", *args], capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def find(item_id):
    out = gdbus("--dest", "org.kde.StatusNotifierWatcher", "--object-path", "/StatusNotifierWatcher", "--method",
                "org.freedesktop.DBus.Properties.Get", "org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems")
    for item in re.findall(r"'([^']+)'", out):
        service, _, path = item.partition("/")
        got = gdbus("--dest", service, "--object-path", "/" + path, "--method",
                    "org.freedesktop.DBus.Properties.Get", "org.kde.StatusNotifierItem", "Id")
        if f"'{item_id}'" in got:
            return service, "/" + path, item
    return None


def trigger(found, label):
    """Click a top-level entry of the item's D-Bus menu (com.canonical.dbusmenu) by its label."""
    menu = re.search(r"objectpath '([^']+)'", gdbus("--dest", found[0], "--object-path", found[1], "--method",
                     "org.freedesktop.DBus.Properties.Get", "org.kde.StatusNotifierItem", "Menu"))
    if not menu:
        return False
    layout = gdbus("--dest", found[0], "--object-path", menu.group(1), "--method",
                   "com.canonical.dbusmenu.GetLayout", "0", "1", '["label"]')
    for entry_id, props in re.findall(r"\((\d+), \{([^}]*)\}", layout):
        got = re.search(r"'label': <'((?:[^'\\]|\\.)*)'>", props)
        if got and got.group(1).replace("&", "") == label.replace("&", ""):
            gdbus("--dest", found[0], "--object-path", menu.group(1), "--method", "com.canonical.dbusmenu.Event",
                  entry_id, "clicked", "<int32 0>", "0")
            return True
    return False


def main():
    cmd, item_id = sys.argv[1], sys.argv[2]
    found = find(item_id)
    if cmd == "status":
        print(1 if found else 0)
    elif cmd == "source":
        print(found[2] if found else "")
    elif cmd == "trigger":
        print(1 if found and trigger(found, sys.argv[3]) else 0)
    elif found and cmd == "activate":
        gdbus("--dest", found[0], "--object-path", found[1], "--method", "org.kde.StatusNotifierItem.Activate", "0", "0")
    elif found and cmd == "menu":
        gdbus("--dest", found[0], "--object-path", found[1], "--method", "org.kde.StatusNotifierItem.ContextMenu",
              sys.argv[3], sys.argv[4])


if __name__ == "__main__":
    main()

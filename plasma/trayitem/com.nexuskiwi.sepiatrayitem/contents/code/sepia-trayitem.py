#!/usr/bin/env python3
"""Find a tray (StatusNotifierItem) app by its Id and click it, like the system tray does.

    sepia-trayitem.py status ID      prints 1 if the app's tray icon is registered, else 0
    sepia-trayitem.py activate ID    left click (usually shows or hides the app's window)
    sepia-trayitem.py menu ID X Y    right click: ask the app for its menu at X, Y
"""
import re
import subprocess
import sys


def gdbus(*args):
    return subprocess.run(["gdbus", "call", "--session", *args], capture_output=True, text=True, timeout=3).stdout


def find(item_id):
    out = gdbus("--dest", "org.kde.StatusNotifierWatcher", "--object-path", "/StatusNotifierWatcher", "--method",
                "org.freedesktop.DBus.Properties.Get", "org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems")
    for item in re.findall(r"'([^']+)'", out):
        service, _, path = item.partition("/")
        got = gdbus("--dest", service, "--object-path", "/" + path, "--method",
                    "org.freedesktop.DBus.Properties.Get", "org.kde.StatusNotifierItem", "Id")
        if f"'{item_id}'" in got:
            return service, "/" + path
    return None


def main():
    cmd, item_id = sys.argv[1], sys.argv[2]
    found = find(item_id)
    if cmd == "status":
        print(1 if found else 0)
    elif found and cmd == "activate":
        gdbus("--dest", found[0], "--object-path", found[1], "--method", "org.kde.StatusNotifierItem.Activate", "0", "0")
    elif found and cmd == "menu":
        gdbus("--dest", found[0], "--object-path", found[1], "--method", "org.kde.StatusNotifierItem.ContextMenu",
              sys.argv[3], sys.argv[4])


if __name__ == "__main__":
    main()

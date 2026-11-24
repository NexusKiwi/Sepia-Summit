#!/usr/bin/env python3
"""sepia-drawer — app list and launcher for the Sepia Summit drawer.

  sepia-drawer list          print every app as JSON, sorted into tabs
  sepia-drawer launch FILE   start the app described by a .desktop file
"""
import json, os, re, shlex, shutil, subprocess, sys
from pathlib import Path

HOME = Path.home()
FIELD_CODE = re.compile(r"^%[fFuUdDnNickvm]$")
# Apps whose desktop categories put them on the wrong tab
TAB_OVERRIDES = {"CurseForge": "Games", "ProtonPlus": "System", "Protontricks": "System", "memtamer": "System"}


def desktop_dir():
    try:
        out = subprocess.run(["xdg-user-dir", "DESKTOP"], capture_output=True, text=True, timeout=2).stdout.strip()
        if out:
            return Path(out)
    except (OSError, subprocess.SubprocessError):
        pass
    return HOME / "Desktop"


def app_dirs():
    data_home = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))
    dirs = [data_home / "applications", data_home / "flatpak/exports/share/applications"]
    for d in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"):
        if d:
            dirs.append(Path(d) / "applications")
    dirs.append(Path("/var/lib/flatpak/exports/share/applications"))
    return list(dict.fromkeys(dirs))


def read_entry(path):
    entry = {}
    section = None
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("[") and line.endswith("]"):
                    section = line[1:-1]
                elif section == "Desktop Entry" and "=" in line:
                    key, value = line.split("=", 1)
                    entry.setdefault(key.strip(), value.strip())
    except OSError:
        return None
    return entry or None


def visible(entry):
    if entry.get("Type") != "Application" or not entry.get("Name") or not entry.get("Exec"):
        return False
    if entry.get("NoDisplay", "").lower() == "true" or entry.get("Hidden", "").lower() == "true":
        return False
    desktops = set(os.environ.get("XDG_CURRENT_DESKTOP", "KDE").split(":"))
    only = {d for d in entry.get("OnlyShowIn", "").split(";") if d}
    if only and not only & desktops:
        return False
    if {d for d in entry.get("NotShowIn", "").split(";") if d} & desktops:
        return False
    try_exec = entry.get("TryExec")
    return not try_exec or shutil.which(os.path.expanduser(try_exec)) is not None


def tab_for(entry):
    if entry["Name"] in TAB_OVERRIDES:
        return TAB_OVERRIDES[entry["Name"]]
    categories = {c for c in entry.get("Categories", "").split(";") if c}
    if "Game" in categories or "steam://rungameid/" in entry.get("Exec", ""):
        return "Games"
    if categories & {"Settings", "System", "Monitor", "PackageManager"}:
        return "System"
    return "Apps"


def list_apps():
    apps, seen = [], set()
    sources = [desktop_dir(), *app_dirs()]
    for directory in sources:
        if not directory.is_dir():
            continue
        for path in sorted(directory.glob("*.desktop")):
            entry = read_entry(path)
            if not entry or not visible(entry):
                continue
            key = entry["Name"].casefold()
            if key in seen:
                continue
            seen.add(key)
            apps.append({
                "name": entry["Name"],
                "icon": entry.get("Icon", "application-x-executable"),
                "path": str(path),
                "tab": tab_for(entry),
            })
    apps.sort(key=lambda a: a["name"].casefold())
    return apps


def launch(path):
    entry = read_entry(path)
    if not entry or not entry.get("Exec"):
        return 1
    exec_line = entry["Exec"].replace("%%", "\0")
    argv = [a.replace("\0", "%") for a in shlex.split(exec_line) if not FIELD_CODE.match(a)]
    if not argv:
        return 1
    if entry.get("Terminal", "").lower() == "true":
        argv = ["konsole", "-e", *argv]
    cwd = entry.get("Path") or str(HOME)
    if not os.path.isdir(cwd):
        cwd = str(HOME)
    # Give the app its own systemd scope, or it dies whenever plasmashell restarts
    if shutil.which("systemd-run"):
        argv = ["systemd-run", "--user", "--scope", "--quiet", "--collect", "--slice=app.slice", "--", *argv]
    subprocess.Popen(argv, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    return 0


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "list":
        print(json.dumps(list_apps(), ensure_ascii=False))
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "launch":
        return launch(sys.argv[2])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())

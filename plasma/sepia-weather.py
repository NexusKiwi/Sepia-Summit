#!/usr/bin/env python3
"""sepia-weather — weather for the Sepia Summit conky panel and live wallpaper.

  sepia-weather setup PLACE          look up a town and save it (e.g. "Lisbon")
  sepia-weather setup LAT LON NAME   save coordinates directly
  sepia-weather fetch                download current weather into the cache
  sepia-weather conky now|details    one line of text for the conky panel
  sepia-weather preview SKY [TIME] [SEASON] [wind=KMH] [temp=C] [snow=CM]
                                     pretend it's SKY (clear partly cloudy overcast fog drizzle
                                     rain showers snow storm) at TIME (day dusk night) in SEASON
                                     (summer autumn winter spring) until the next fetch; for
                                     trying out the wallpaper

Data from Open-Meteo (free, no key). Only the saved coordinates are sent.
Config: ~/.config/sepia-summit/weather.json   Cache: ~/.cache/sepia-summit/weather.json
The same data is also written as ~/.cache/sepia-summit/weather.qml for the live wallpaper:
the lock screen blocks all network access (even 127.0.0.1) but can still load local QML.
Python standard library only.
"""
import json, os, sys, time, urllib.parse, urllib.request
from pathlib import Path

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "sepia-summit/weather.json"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "sepia-summit/weather.json"
STALE = 3600            # seconds before conky shows the data as unavailable
UA = {"User-Agent": "sepia-summit-weather/1.0"}

# WMO weather code -> (label, sky, intensity 0-1). sky drives the wallpaper.
CODES = {
    0: ("Clear", "clear", 0), 1: ("Mostly clear", "partly", 0), 2: ("Partly cloudy", "partly", 0),
    3: ("Overcast", "overcast", 0), 45: ("Fog", "fog", 0), 48: ("Icy fog", "fog", 0),
    51: ("Light drizzle", "drizzle", 0.25), 53: ("Drizzle", "drizzle", 0.35), 55: ("Heavy drizzle", "drizzle", 0.45),
    56: ("Freezing drizzle", "drizzle", 0.3), 57: ("Freezing drizzle", "drizzle", 0.45),
    61: ("Light rain", "rain", 0.45), 63: ("Rain", "rain", 0.7), 65: ("Heavy rain", "rain", 1.0),
    66: ("Freezing rain", "rain", 0.5), 67: ("Freezing rain", "rain", 0.9),
    71: ("Light snow", "snow", 0.35), 73: ("Snow", "snow", 0.6), 75: ("Heavy snow", "snow", 0.9), 77: ("Snow grains", "snow", 0.3),
    80: ("Light showers", "showers", 0.5), 81: ("Showers", "showers", 0.75), 82: ("Heavy showers", "showers", 1.0),
    85: ("Snow showers", "snow", 0.5), 86: ("Heavy snow showers", "snow", 0.9),
    95: ("Thunderstorm", "storm", 1.0), 96: ("Thunderstorm, hail", "storm", 1.0), 99: ("Thunderstorm, hail", "storm", 1.0),
}
COMPASS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


def get_json(url, params):
    with urllib.request.urlopen(urllib.request.Request(url + "?" + urllib.parse.urlencode(params), headers=UA),
                                timeout=15) as r:
        return json.loads(r.read())


def write_atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=1))
    tmp.replace(path)


def save_cache(data):
    write_atomic(CACHE, data)
    # JSON is a valid JavaScript literal, and json.dumps escapes every string
    qml = CACHE.with_suffix(".qml")
    tmp = qml.with_suffix(".qml.tmp")
    tmp.write_text("import QtQml\nQtObject { readonly property var data: (" + json.dumps(data) + ") }\n")
    tmp.replace(qml)


def setup(args):
    if len(args) >= 3:
        lat, lon, name = float(args[0]), float(args[1]), " ".join(args[2:])
    elif args:
        res = get_json("https://geocoding-api.open-meteo.com/v1/search",
                       {"name": " ".join(args), "count": 1, "language": "en", "format": "json"}).get("results")
        if not res:
            sys.exit(f"Couldn't find a place called {' '.join(args)!r}. Try the nearest town, or LAT LON NAME.")
        r = res[0]
        lat, lon, name = r["latitude"], r["longitude"], r["name"]
        print(f"Found {name}, {r.get('admin1', '')} {r.get('country', '')} ({lat:.2f}, {lon:.2f})".replace(" ,", ","))
    else:
        sys.exit(__doc__)
    write_atomic(CONFIG, {"name": name, "latitude": round(lat, 2), "longitude": round(lon, 2)})
    print("Saved to", CONFIG)
    fetch()


def fetch():
    c = json.loads(CONFIG.read_text())
    d = get_json("https://api.open-meteo.com/v1/forecast", {
        "latitude": c["latitude"], "longitude": c["longitude"], "timezone": "auto", "forecast_days": 2,
        "current": "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,cloud_cover,"
                   "wind_speed_10m,wind_direction_10m,precipitation,is_day",
        "daily": "temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,snowfall_sum",
        "past_days": 3,
    })
    cur, day = d["current"], d["daily"]
    t = day["time"].index(cur["time"][:10]) if cur["time"][:10] in day["time"] else 0     # today
    # recent snow (cm), older days counting less: lowers the wallpaper's snowline, then melts back
    snow_cm = sum((day["snowfall_sum"][t - k] or 0) * w for k, w in enumerate((1, 0.7, 0.45, 0.25)) if t - k >= 0)
    label, sky, intensity = CODES.get(cur["weather_code"], ("—", "clear", 0))
    # The code says "partly cloudy" for anything from a few clouds to most of the sky
    if sky == "partly" and cur["cloud_cover"] >= 70:
        sky = "cloudy"
    save_cache({
        "updated": int(time.time()),
        "place": c["name"], "latitude": c["latitude"], "longitude": c["longitude"],
        "label": label, "sky": sky, "intensity": intensity, "code": cur["weather_code"],
        "temp": cur["temperature_2m"], "feels": cur["apparent_temperature"],
        "humidity": cur["relative_humidity_2m"], "cloud_cover": cur["cloud_cover"],
        "precip_mm": cur["precipitation"], "wind_kmh": cur["wind_speed_10m"], "wind_dir": cur["wind_direction_10m"],
        "is_day": cur["is_day"],
        "max": day["temperature_2m_max"][t], "min": day["temperature_2m_min"][t],
        "rain_chance": day["precipitation_probability_max"][t], "snow_cm": round(snow_cm, 1),
        "sunrise": day["sunrise"][t][-5:], "sunset": day["sunset"][t][-5:],
    })


def preview(args):
    sky = args[0] if args else "rain"
    when, season, extra = "day", None, {}
    for a in args[1:]:
        if a in ("day", "dusk", "night"):
            when = a
        elif a in ("summer", "autumn", "winter", "spring"):
            season = a
        elif "=" in a and a.split("=")[0] in ("wind", "temp", "snow"):
            k, v = a.split("=", 1)
            extra[{"wind": "wind_kmh", "temp": "temp", "snow": "snow_cm"}[k]] = float(v)
        else:
            sys.exit(__doc__)
    skies = {"clear": (0, 0), "partly": (2, 35), "cloudy": (2, 75), "overcast": (3, 95), "fog": (45, 100),
             "drizzle": (53, 90), "rain": (63, 95), "showers": (81, 80), "snow": (73, 95), "storm": (95, 100)}
    if sky not in skies:
        sys.exit(__doc__)
    code, cover = skies[sky]
    try:
        data = json.loads(CACHE.read_text())
    except (OSError, ValueError):
        data = {"place": "Preview", "latitude": 0, "longitude": 0, "temp": 15, "feels": 14, "humidity": 70,
                "wind_kmh": 15, "wind_dir": 270, "max": 18, "min": 9, "rain_chance": 50,
                "sunrise": "06:00", "sunset": "20:00"}
    label, _, intensity = CODES[code]
    data.update({"label": label + " (preview)", "sky": sky, "intensity": intensity, "code": code,
                 "cloud_cover": cover, "updated": int(time.time()), "preview": True,
                 "sun_elevation": {"day": 40, "dusk": -1, "night": -25}[when]})
    data.pop("season", None)
    if season:
        data["season"] = season
    data.update(extra)
    save_cache(data)
    print(f"Previewing {sky} at {when}{' in ' + season if season else ''}. Run `sepia-weather fetch` to go back to the real weather.")


def conky(what):
    try:
        w = json.loads(CACHE.read_text())
    except (OSError, ValueError):
        print("weather unavailable" if what == "now" else "")
        return
    if time.time() - w.get("updated", 0) > STALE:
        print("weather unavailable" if what == "now" else "")
        return
    if what == "now":
        print(f"{w['label']}, {round(w['temp'])}°  ·  feels {round(w['feels'])}°")
    elif what == "details":
        wind = f"{round(w['wind_kmh'])} km/h {COMPASS[round(w['wind_dir'] / 45) % 8]}"
        print(f"H {round(w['max'])}°  L {round(w['min'])}°  ·  {wind}  ·  rain {w['rain_chance']}%  ·  "
              f"↑{w['sunrise']} ↓{w['sunset']}")


def main(argv):
    cmd, args = (argv[1], argv[2:]) if len(argv) > 1 else ("", [])
    try:
        if cmd == "setup":
            setup(args)
        elif cmd == "fetch":
            fetch()
        elif cmd == "conky" and args:
            conky(args[0])
        elif cmd == "preview":
            preview(args)
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except FileNotFoundError:
        print("No location set. Run: sepia-weather setup \"Your town\"", file=sys.stderr)
        return 1
    except OSError as e:
        print("sepia-weather:", e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

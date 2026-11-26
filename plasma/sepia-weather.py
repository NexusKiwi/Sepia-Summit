#!/usr/bin/env python3
"""sepia-weather — weather for the Sepia Summit conky panel and live wallpaper.

  sepia-weather setup PLACE          look up a town and save it (e.g. "Lisbon")
  sepia-weather setup LAT LON NAME   save coordinates directly
  sepia-weather fetch                download current weather into the cache
  sepia-weather conky now|details    one line of text for the conky panel
  sepia-weather preview SKY [TIME] [SEASON] [wind=KMH] [temp=C] [snow=CM] [eclipse=solar|lunar] [meteors=N]
                                     pretend it's SKY (clear partly cloudy overcast fog drizzle
                                     rain showers snow storm) at TIME (day dusk night) in SEASON
                                     (summer autumn winter spring) until the next fetch; for
                                     trying out the wallpaper. eclipse= plays one over ~4 minutes,
                                     meteors= fakes a shower of N an hour
  sepia-weather refresh              fetch, unless a preview started in the last 15 min (the timer)
  sepia-weather events               eclipses visible from your town in the next 3 years

Data from Open-Meteo (free, no key). Only the saved coordinates are sent. Eclipses and meteor
showers are worked out locally (sun and moon positions, Meeus), nothing is downloaded for them.
Config: ~/.config/sepia-summit/weather.json   Cache: ~/.cache/sepia-summit/weather.json
The same data is also written as ~/.cache/sepia-summit/weather.qml for the live wallpaper:
the lock screen blocks all network access (even 127.0.0.1) but can still load local QML.
Python standard library only.
"""
import json, os, sys, time, urllib.parse, urllib.request

# --- astronomy (stdlib): sun, moon (Meeus ch. 47, main terms), eclipses, meteor showers -----------
from math import sin, cos, tan, asin, acos, atan2, sqrt, radians as rad, degrees as deg, pi, floor

DELTA_T = 69.0                                   # TT - UT seconds (good for the 2020s-2030s)

# Meeus table 47.A: D M M' F, sum l (1e-6 deg), sum r (1e-3 km)
_LR = [(0,0,1,0,6288774,-20905355),(2,0,-1,0,1274027,-3699111),(2,0,0,0,658314,-2955968),
       (0,0,2,0,213618,-569925),(0,1,0,0,-185116,48888),(0,0,0,2,-114332,-3149),
       (2,0,-2,0,58793,246158),(2,-1,-1,0,57066,-152138),(2,0,1,0,53322,-170733),
       (2,-1,0,0,45758,-204586),(0,1,-1,0,-40923,-129620),(1,0,0,0,-34720,108743),
       (0,1,1,0,-30383,104755),(2,0,0,-2,15327,10321),(0,0,1,2,-12528,0),(0,0,1,-2,10980,79661),
       (4,0,-1,0,10675,-34782),(0,0,3,0,10034,-23210),(4,0,-2,0,8548,-21636),(2,1,-1,0,-7888,24208),
       (2,1,0,0,-6766,30824),(1,0,-1,0,-5163,-8379),(1,1,0,0,4987,-16675),(2,-1,1,0,4036,-12831),
       (2,0,2,0,3994,-10445),(4,0,0,0,3861,-11650),(2,0,-3,0,3665,14403),(0,1,-2,0,-2689,-7003),
       (2,0,-1,2,-2602,0),(2,-1,-2,0,2390,10056),(1,0,1,0,-2348,6322),(2,-2,0,0,2236,-9884),
       (0,1,2,0,-2120,5751),(0,2,0,0,-2069,0),(2,-2,-1,0,2048,-4950),(2,0,1,-2,-1773,4130),
       (2,0,0,2,-1595,0),(4,-1,-1,0,1215,-3958),(0,0,2,2,-1110,0),(3,0,-1,0,-892,3258),
       (2,1,1,0,-810,2616),(4,-1,-2,0,759,-1897),(0,2,-1,0,-713,-2117),(2,2,-1,0,-700,2354),
       (2,1,-2,0,691,0),(2,-1,0,-2,596,0),(4,0,1,0,549,-1423),(0,0,4,0,537,-1117),
       (4,-1,0,0,520,-1571),(1,0,-2,0,-487,-1739),(2,1,0,-2,-399,0),(0,0,2,-2,-381,-4421),
       (1,1,1,0,351,0),(3,0,-2,0,-340,0),(4,0,-3,0,330,0),(2,-1,2,0,327,0),(0,2,1,0,-323,1165),
       (1,1,-1,0,299,0),(2,0,3,0,294,0),(2,0,-1,-2,0,8752)]
# table 47.B: D M M' F, sum b (1e-6 deg)
_B = [(0,0,0,1,5128122),(0,0,1,1,280602),(0,0,1,-1,277693),(2,0,0,-1,173237),(2,0,-1,1,55413),
      (2,0,-1,-1,46271),(2,0,0,1,32573),(0,0,2,1,17198),(2,0,1,-1,9266),(0,0,2,-1,8822),
      (2,-1,0,-1,8216),(2,0,-2,-1,4324),(2,0,1,1,4200),(2,1,0,-1,-3359),(2,-1,-1,1,2463),
      (2,-1,0,1,2211),(2,-1,-1,-1,2065),(0,1,-1,-1,-1870),(4,0,-1,-1,1828),(0,1,0,1,-1794),
      (0,0,0,3,-1749),(0,1,-1,1,-1565),(1,0,0,1,-1491),(0,1,1,1,-1475),(0,1,1,-1,-1410),
      (0,1,0,-1,-1344),(1,0,0,-1,-1335),(0,0,3,1,1107),(4,0,0,-1,1021),(4,0,-1,1,833)]


def _jd(unix):
    return unix / 86400 + 2440587.5


def _T(unix):
    return (_jd(unix + DELTA_T) - 2451545.0) / 36525


def _obliquity(T):
    return 23.4392911 - 0.0130042 * T


def sun_ecliptic(unix):
    """Apparent ecliptic longitude (deg) and distance (AU)."""
    T = _T(unix)
    L0 = 280.46646 + 36000.76983 * T
    M = rad(357.52911 + 35999.05029 * T)
    C = (1.914602 - 0.004817 * T) * sin(M) + 0.019993 * sin(2 * M) + 0.000289 * sin(3 * M)
    v = M + rad(C)
    e = 0.016708634 - 0.000042037 * T
    R = 1.000001018 * (1 - e * e) / (1 + e * cos(v))
    lam = L0 + C - 0.00569 - 0.00478 * sin(rad(125.04 - 1934.136 * T))
    return lam % 360, R


def moon_ecliptic(unix):
    """Geocentric ecliptic longitude, latitude (deg) and distance (km)."""
    T = _T(unix)
    Lp = 218.3164477 + 481267.88123421 * T - 0.0015786 * T * T
    D = 297.8501921 + 445267.1114034 * T - 0.0018819 * T * T
    M = 357.5291092 + 35999.0502909 * T - 0.0001536 * T * T
    Mp = 134.9633964 + 477198.8675055 * T + 0.0087414 * T * T
    F = 93.2720950 + 483202.0175233 * T - 0.0036539 * T * T
    E = 1 - 0.002516 * T - 0.0000074 * T * T
    sl = sr = sb = 0.0
    for d, m, mp, f, l, r in _LR:
        a = rad(d * D + m * M + mp * Mp + f * F)
        k = E ** abs(m)
        sl += l * k * sin(a)
        sr += r * k * cos(a)
    for d, m, mp, f, b in _B:
        sb += b * E ** abs(m) * sin(rad(d * D + m * M + mp * Mp + f * F))
    A1, A2, A3 = 119.75 + 131.849 * T, 53.09 + 479264.290 * T, 313.45 + 481266.484 * T
    sl += 3958 * sin(rad(A1)) + 1962 * sin(rad(Lp - F)) + 318 * sin(rad(A2))
    sb += (-2235 * sin(rad(Lp)) + 382 * sin(rad(A3)) + 175 * sin(rad(A1 - F)) + 175 * sin(rad(A1 + F))
           + 127 * sin(rad(Lp - Mp)) - 115 * sin(rad(Lp + Mp)))
    return (Lp + sl / 1e6) % 360, sb / 1e6, 385000.56 + sr / 1000


def _equatorial(lam, beta, T):
    e, l, b = rad(_obliquity(T)), rad(lam), rad(beta)
    ra = atan2(sin(l) * cos(e) - tan(b) * sin(e), cos(l))
    dec = asin(sin(b) * cos(e) + cos(b) * sin(e) * sin(l))
    return ra, dec


def _lst(unix, lon):
    jd = _jd(unix)
    t = (jd - 2451545.0) / 36525
    gmst = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * t * t
    return rad((gmst + lon) % 360)


def _horizontal(ra, dec, unix, lat, lon):
    H, phi = _lst(unix, lon) - ra, rad(lat)
    alt = asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(H))
    az = atan2(-sin(H) * cos(dec), cos(phi) * sin(dec) - sin(phi) * cos(dec) * cos(H))   # from north, east = 90
    return deg(alt), deg(az) % 360


def _topocentric(ra, dec, dist_er, unix, lat, lon):
    """Shift a body at dist_er Earth radii to where it appears from the observer (parallax)."""
    phi, lst = rad(lat), _lst(unix, lon)
    x, y, z = dist_er * cos(dec) * cos(ra), dist_er * cos(dec) * sin(ra), dist_er * sin(dec)
    x -= cos(phi) * cos(lst); y -= cos(phi) * sin(lst); z -= 0.99664719 * sin(phi)
    d = sqrt(x * x + y * y + z * z)
    return atan2(y, x), asin(z / d), d


def sun_moon(unix, lat, lon):
    """Topocentric alt/az (deg) and apparent radii (deg) of the sun and moon, plus moon phase."""
    T = _T(unix)
    ls, R = sun_ecliptic(unix)
    lm, bm, dm = moon_ecliptic(unix)
    sra, sdec = _equatorial(ls, 0, T)
    mra, mdec = _equatorial(lm, bm, T)
    mra, mdec, der = _topocentric(mra, mdec, dm / 6378.14, unix, lat, lon)
    s_alt, s_az = _horizontal(sra, sdec, unix, lat, lon)
    m_alt, m_az = _horizontal(mra, mdec, unix, lat, lon)
    elong = (lm - ls) % 360
    return {"sun": (s_alt, s_az, 0.2666 / R), "moon": (m_alt, m_az, deg(asin(1737.4 / (der * 6378.14)))),
            "phase": (1 - cos(rad(elong))) / 2, "waxing": elong < 180}


def _sky_offset(a_alt, a_az, b_alt, b_az):
    """Where b is relative to a on the sky (deg): x towards larger azimuth, y up."""
    da = (b_az - a_az + 180) % 360 - 180
    return da * cos(rad((a_alt + b_alt) / 2)), b_alt - a_alt


def lunar_shadow(unix):
    """Earth's shadow vs the moon, geocentric: (offset of shadow centre from the moon in deg as
    ecliptic dx, dy), umbra radius, penumbra radius, moon radius (deg)."""
    ls, R = sun_ecliptic(unix)
    lm, bm, dm = moon_ecliptic(unix)
    pm, ps, ss = deg(asin(6378.14 / dm)), 8.794 / 3600 / R, 0.2666 / R
    dx = ((ls + 180 - lm + 180) % 360 - 180) * cos(rad(bm))
    return dx, -bm, 1.02 * (pm + ps - ss), 1.02 * (pm + ps + ss), deg(asin(1737.4 / dm))


def eclipses(start, lat, lon, hours=36, step=300):
    """Eclipses visible from lat/lon in the next `hours`. Each: kind, start, end and samples every
    minute: solar [t, moon dx, dy] in sun radii; lunar [t, shadow dx, dy, umbra r, penumbra r]
    in moon radii (dx along increasing azimuth, dy up, so it draws the right way round)."""
    out = []
    for kind in ("solar", "lunar"):
        t, end = start - 3 * 3600, start + hours * 3600
        while t < end:
            hit = False
            if kind == "solar":
                p = sun_moon(t, lat, lon)
                (sa, sz, sr), (ma, mz, mr) = p["sun"], p["moon"]
                dx, dy = _sky_offset(sa, sz, ma, mz)
                hit = sqrt(dx * dx + dy * dy) < sr + mr + 0.3 and sa > -2
            else:
                dx, dy, ur, pr, mr = lunar_shadow(t)
                hit = sqrt(dx * dx + dy * dy) < pr + mr + 0.3 and sun_moon(t, lat, lon)["moon"][0] > -2
            if not hit:
                t += step
                continue
            # walk minute by minute through this window
            samples, u = [], t - step
            while True:
                p = sun_moon(u, lat, lon)
                (sa, sz, sr), (ma, mz, mr) = p["sun"], p["moon"]
                if kind == "solar":
                    dx, dy = _sky_offset(sa, sz, ma, mz)
                    on = sqrt(dx * dx + dy * dy) < sr + mr and sa > -1
                    row = [int(u), round(dx / sr, 4), round(dy / sr, 4), round(mr / sr, 4)]
                else:
                    ex, ey, ur, pr, mr2 = lunar_shadow(u)
                    on = sqrt(ex * ex + ey * ey) < pr + mr2 and ma > -1
                    # rotate ecliptic offsets roughly into the moon's local sky frame (good enough to draw)
                    row = [int(u), round(ex / mr2, 3), round(ey / mr2, 3), round(ur / mr2, 3), round(pr / mr2, 3)]
                if on:
                    samples.append(row)
                elif samples or u > t + 4 * step:
                    break
                u += 60
            if samples:
                out.append({"kind": kind, "start": samples[0][0], "end": samples[-1][0], "samples": samples})
            t = u + step
    return out


# Major showers: name, peak solar longitude (deg), ZHR, slope B (per deg each side), radiant RA, Dec
SHOWERS = [("Quadrantids", 283.15, 110, 0.75, 230, 49), ("Lyrids", 32.32, 18, 0.22, 271, 34),
           ("Eta Aquariids", 45.5, 50, 0.08, 338, -1), ("Southern Delta Aquariids", 125.0, 25, 0.09, 340, -16),
           ("Perseids", 140.0, 100, 0.2, 48, 58), ("Orionids", 208.0, 20, 0.12, 95, 16),
           ("Leonids", 235.27, 15, 0.3, 152, 22), ("Geminids", 262.2, 150, 0.39, 112, 33),
           ("Ursids", 270.7, 10, 0.6, 217, 76)]


def meteor_shower(unix, lat, lon):
    """The most active shower right now as seen from lat/lon, or None. rate = meteors/hour you'd
    actually see (radiant height, darkness and moonlight taken into account)."""
    ls, _ = sun_ecliptic(unix)
    p = sun_moon(unix, lat, lon)
    dark = min(1, max(0, (-p["sun"][0] - 6) / 6))                 # full dark from 12 deg below
    moonlight = 1 - 0.6 * p["phase"] * (p["moon"][0] > 0)
    best = None
    for name, peak, zhr, b, ra, dec in SHOWERS:
        dl = abs((ls - peak + 180) % 360 - 180)
        z = zhr * 10 ** (-b * dl)
        if z < 4:
            continue
        alt, az = _horizontal(rad(ra), rad(dec), unix, lat, lon)
        rate = z * max(0, sin(rad(alt))) * dark * moonlight
        cand = {"name": name, "zhr": round(z), "rate": round(rate, 1), "radiant_alt": round(alt, 1),
                "radiant_az": round(az, 1)}
        if best is None or rate > best["rate"] or (best["rate"] == 0 and z > best["zhr"]):
            best = cand
    return best

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
        **sky_events(c["latitude"], c["longitude"]),
    })


def sky_events(lat, lon):
    now = time.time()
    return {"eclipses": eclipses(now, lat, lon), "meteors": meteor_shower(now, lat, lon)}


def preview(args):
    sky = args[0] if args else "rain"
    when, season, extra = "day", None, {}
    for a in args[1:]:
        if a in ("day", "dusk", "night"):
            when = a
        elif a in ("summer", "autumn", "winter", "spring"):
            season = a
        elif a in ("eclipse=solar", "eclipse=lunar"):
            extra["eclipses"] = [fake_eclipse(a.split("=")[1])]
            when = "day" if a.endswith("solar") else "night"
        elif a.startswith("meteors="):
            extra["meteors"] = {"name": "Preview shower", "zhr": float(a[8:]), "rate": float(a[8:]),
                                "radiant_alt": 45, "radiant_az": 20}
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
                 "sun_elevation": {"day": 21, "dusk": -1, "night": -25}[when],
                 # put the sun where the old painted one was, and the full moon right of the big peak
                 "sun_az": -44 if data.get("latitude", 0) < 0 else 136,
                 "moon_alt": 35, "moon_az": -22 if data.get("latitude", 0) < 0 else 158, "moon_phase": 1.0,
                 "eclipses": [], "meteors": None})
    data.pop("season", None)
    if season:
        data["season"] = season
    data.update(extra)
    save_cache(data)
    print(f"Previewing {sky} at {when}{' in ' + season if season else ''}. Run `sepia-weather fetch` to go back to the real weather.")


def fake_eclipse(kind):
    """A total eclipse squeezed into four minutes, starting now."""
    now, rows = int(time.time()) + 20, []
    for i in range(241):
        f = i / 240 * 2 - 1                                            # -1 .. 1
        if kind == "solar":
            rows.append([now + i, round(2.1 * f, 4), round(0.08 * f, 4), 1.05])
        else:
            rows.append([now + i, round(-3.2 * f, 3), round(0.25, 3), 2.7, 4.6])
    return {"kind": kind, "start": now, "end": now + 240, "samples": rows}


def events():
    c = json.loads(CONFIG.read_text())
    t, end, seen = time.time(), time.time() + 3 * 365 * 86400, []
    while t < end:
        ph = sun_moon(t, c["latitude"], c["longitude"])["phase"]
        if ph < 0.02 or ph > 0.98:
            for e in eclipses(t, c["latitude"], c["longitude"], hours=30):
                if any(abs(e["start"] - s) < 86400 for s in seen):
                    continue
                seen.append(e["start"])
                s = e["samples"]
                if e["kind"] == "solar":
                    o = max(min(1, (r[3] + 1 - (r[1] ** 2 + r[2] ** 2) ** 0.5) / 2) for r in s)
                    what = "total solar eclipse" if o >= 1 else f"partial solar eclipse, {o:.0%} of the sun's width"
                else:
                    o = max((r[3] + 1 - (r[1] ** 2 + r[2] ** 2) ** 0.5) / 2 for r in s)
                    what = ("total lunar eclipse" if o >= 1 else f"partial lunar eclipse (magnitude {o:.2f})"
                            if o > 0 else "penumbral lunar eclipse (faint)")
                print(time.strftime("%a %d %b %Y, %H:%M", time.localtime(e["start"])), "-", what)
            t += 3 * 86400
        else:
            t += 6 * 3600
    if not seen:
        print("No eclipses visible from", c["name"], "in the next 3 years.")


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
        elif cmd == "refresh":                      # the timer: leaves a fresh preview running
            try:
                d = json.loads(CACHE.read_text())
                if d.get("preview") and time.time() - d.get("updated", 0) < 900:
                    sys.exit(0)
            except (OSError, ValueError):
                pass
            fetch()
        elif cmd == "conky" and args:
            conky(args[0])
        elif cmd == "preview":
            preview(args)
        elif cmd == "events":
            events()
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

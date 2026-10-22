#!/usr/bin/env python3
"""Apply published aircraft figures to the game's AircraftStats (.tres).

Every row of PUBLISHED is a rounded figure from commonly published specifications. Rows marked [src] were checked
against the named source; the rest are rounded from standard references and are approximate. Nothing here is read
from any game's files.

  * Wikipedia - Hawker Typhoon (Mk IB), Messerschmitt Bf 110, Dornier Do 17 (Z), Bristol Blenheim, Supermarine Spitfire
    (early Merlin-powered variants), Messerschmitt Bf 109, Junkers Ju 88, Heinkel He 111: https://en.wikipedia.org
  * battleofbritain1940.com - Bf 109E-3 (speed, span), Ju 88A-1 (speed, span), He 111H-3 (speed, span)

Derivation (arcade stays playable, numbers stay real):
  max_speed      = Vmax / 3.6                     (m/s, 1 unit = 1 m)
  stall_speed    = sqrt(2*mass*9.81/(1.225*S*1.4))  real lift equation, CLmax 1.4
  accel          = 2.2 + climb * 0.32             climb rate is a proxy for excess power
  decel          = accel * 0.85
  pitch_rate_deg = 28 + climb * 2.2
  roll_rate_deg  = 50 + climb*2.6 + (16 - span)*4.0
  yaw_rate_deg   = 9 + climb * 0.85
  bank_turn_rate = 0.45 + climb * 0.02
  rate_response  = 2.6 + climb * 0.17
  boost_bonus    = max_speed * 0.32
  max_health     = mass / 22
  radius         = span / 1.15
Weapons / ammo / gear_height / names are left as authored in the .tres.
"""
import math, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRES = os.path.join(ROOT, "data", "aircraft")

# id: vmax_kmh, climb_ms, span_m, empty_mass_kg, wing_m2, turn estimate (s, informational)
PUBLISHED = {
    "spitfire":  (583, 12.7, 11.23, 2182, 22.48, 24),   # Mk I: 362 mph at 18,500 ft, 2,490 ft/min [Wikipedia]
    "typhoon":   (679, 13.9, 12.67, 4010, 25.90, 28),   # Mk IB: 422 mph, 2,740 ft/min, 41 ft 7 in, 279 sq ft, 8,840 lb [Wikipedia]
    "bf109":     (560, 16.5,  9.87, 2000, 16.40, 22),   # E-3: 348 mph at 12,300 ft, 9.87 m [battleofbritain1940.com]
    "bf110":     (541, 11.0, 16.25, 4425, 38.40, 30),   # 541 km/h at 6,000 m, 11 m/s, 38.4 m2, 4,425 kg [Wikipedia]
    "he111":     (415,  4.5, 22.60, 7700, 87.60, 40),   # H-3: 415 km/h at 16,000 ft, 22.60 m [battleofbritain1940.com]; area from the F-series wing
    "do17":      (410,  6.0, 18.00, 5210, 55.00, 35),   # Z: 410 km/h at 5,000 m, 18 m, 55 m2, 5,210 kg [Wikipedia]
    "blenheim":  (428,  7.9, 17.17, 4441, 43.60, 33),   # 266 mph at 11,800 ft, 17.17 m, 469 sq ft, 9,790 lb; 2,000 m in 4 min 10 s [Wikipedia]
    "ju88":      (461,  5.5, 18.25, 7200, 52.50, 38),   # A-1: 461 km/h at 4,876 m, 18.25 m [battleofbritain1940.com]
    "ju87":      (383,  5.0, 13.80, 2750, 31.90, 30),   # B-2: approximate
    "hurricane": (520, 13.0, 12.19, 2260, 23.92, 22),
    "mosquito":  (610, 14.5, 16.51, 6440, 42.18, 26),
    "p51":       (703, 16.3, 11.28, 3465, 21.83, 22),
    "p47":       (690, 15.0, 12.42, 4535, 27.87, 26),
    "fw190":     (660, 16.0, 10.51, 3200, 18.30, 23),
    "me262":     (870, 20.0, 12.60, 3800, 21.70, 27),
    "lancaster": (450,  4.7, 31.09, 16738, 120.50, 45),
    "b26":       (455,  6.1, 21.64, 11500, 61.10, 38),
}

DERIVED = ["max_speed", "stall_speed", "boost_bonus", "accel", "decel", "pitch_rate_deg",
           "roll_rate_deg", "yaw_rate_deg", "bank_turn_rate", "rate_response",
           "max_health", "radius"]


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def derive(vmax_kmh, climb, span, mass, area, turn):
    ms = vmax_kmh / 3.6
    vs = math.sqrt(2.0 * mass * 9.81 / (1.225 * area * 1.4))
    accel = clamp(2.2 + climb * 0.32, 3.4, 8.8)
    return {
        "max_speed": round(ms, 1),
        "stall_speed": round(clamp(vs, 26.0, 62.0), 1),
        "boost_bonus": round(ms * 0.32, 1),
        "accel": round(accel, 1),
        "decel": round(accel * 0.85, 1),
        "pitch_rate_deg": round(clamp(28 + climb * 2.2, 30, 78), 0),
        "roll_rate_deg": round(clamp(50 + climb * 2.6 + (16 - span) * 4.0, 50, 180), 0),
        "yaw_rate_deg": round(clamp(9 + climb * 0.85, 9, 28), 0),
        "bank_turn_rate": round(clamp(0.45 + climb * 0.02, 0.45, 0.9), 2),
        "rate_response": round(clamp(2.6 + climb * 0.17, 2.8, 6.6), 1),
        "max_health": round(clamp(mass / 22.0, 100, 450), 0),
        "radius": round(clamp(span / 1.15, 6, 20), 0),
    }


def rewrite(path, vals):
    raw = open(path, "rb").read().decode("utf-8")
    nl = "\r\n" if "\r\n" in raw else "\n"
    txt = raw.replace("\r\n", "\n")
    # drop any existing assignment of a derived key, then append the new ones
    for k in DERIVED:
        txt = re.sub(r"^%s\s*=.*\n" % k, "", txt, flags=re.M)
    txt = txt.rstrip("\n") + "\n"
    for k in DERIVED:
        v = vals[k]
        txt += "%s = %s\n" % (k, ("%d" % v) if float(v) == int(v) else v)
    open(path, "wb").write(txt.replace("\n", nl).encode("utf-8"))


def main():
    print("%-11s %8s %8s %7s %7s %7s %7s %6s %6s" % (
        "aircraft", "Vmax", "stall", "accel", "pitch", "roll", "yaw", "health", "radius"))
    for aid in sorted(PUBLISHED.keys()):
        vals = derive(*PUBLISHED[aid])
        path = os.path.join(TRES, aid + ".tres")
        if not os.path.exists(path):
            print("  %s: no .tres" % aid)
            continue
        rewrite(path, vals)
        print("%-11s %8.0f %8.1f %7.1f %7.0f %7.0f %7.0f %6.0f %6.0f" % (
            aid, vals["max_speed"] * 3.6, vals["stall_speed"], vals["accel"],
            vals["pitch_rate_deg"], vals["roll_rate_deg"], vals["yaw_rate_deg"],
            vals["max_health"], vals["radius"]))


if __name__ == "__main__":
    main()

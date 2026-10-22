#!/usr/bin/env python3
"""Phase 0.4: populate the formerly-dead `cities[].landmark` strings and make sure every landmark
id handled by scripts/ground/landmarks.gd has a matching features[type=landmark] row.

IN-PLACE, NON-DESTRUCTIVE. Never regenerates the file (tools/build_locations.py would drop the
hand-added targets) - it reads data/locations.json, edits the landmark values / appends any missing
feature rows, and writes the file back with the SAME formatting (indent=1, CRLF, no trailing
newline) so the diff is limited to the intended changes. Existing keys and their order are kept;
existing non-empty landmark strings are left untouched except for the explicit FIXUPS below.

Idempotent: running twice changes nothing the second time.

Usage: python tools/upsert_cities_1940.py
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOC = os.path.join(ROOT, "data", "locations.json")
LM_GD = os.path.join(ROOT, "scripts", "ground", "landmarks.gd")
LAT_MIN, LAT_MAX, LON_MIN, LON_MAX = 48.9, 53.0, -4.6, 9.0

# 1-3 real 1940s landmarks per city, for every city whose landmark field was empty.
LANDMARKS = {
    "folkestone": "Leas Pavilion; Folkestone Harbour",
    "southampton": "Bargate; Ocean Dock; Civic Centre",
    "cherbourg": "Fort du Roule; Rade de Cherbourg",
    "ostend": "St Peter's Church; Kursaal",
    "ramsgate": "Royal Harbour; Ramsgate Maritime Museum",
    "chatham": "Chatham Dockyard; Royal Engineers' Barracks",
    "maidstone": "All Saints' Church; Maidstone Gaol",
    "hastings": "Hastings Castle ruins; Pelham Crescent",
    "eastbourne": "Eastbourne Pier; Wish Tower",
    "guildford": "Guildford Castle; Holy Trinity Church",
    "reading": "Reading Abbey ruins; Huntley & Palmers Works",
    "saint_omer_town": "Basilique Notre-Dame; Saint-Omer Cathedral",
    "le_treport": "Le Treport cliffs; Chateau d'Eu",
    "abbeville": "Collegiale Saint-Vulfran; Abbeville Belfry",
    "poole": "Poole Quay; Brownsea Island",
    "dunkirk_la_panne": "Dunkerque outer harbour; Saint-Eloi Church",
    "lisieux": "Lisieux Cathedral; Basilica of St Therese",
    "saint_lo": "Saint-Lo ramparts; Notre-Dame Church",
    "valognes": "Valognes town houses; Abbey of Valognes",
    "leicester": "Leicester Cathedral; Clock Tower",
    "leuven": "Leuven Town Hall; St Peter's Church",
    "charleroi": "Charleroi Town Hall; coal basin",
    "mons": "Mons Belfry; Collegiate Church of St Waltrude",
    "maastricht": "Basilica of Saint Servatius; Sint-Pietersberg caves",
    "the_hague": "Binnenhof; Peace Palace",
    "breda": "Grote Kerk; Breda Castle",
    "tilburg": "Heikese Kerk; Tilburg textile mills",
    "den_bosch": "St John's Cathedral; Sint-Jan",
    "venlo_city": "Saint Martin's Church; Maas bridges",
    "bonn": "Bonn Minster; Beethoven birthplace",
    "dusseldorf": "St Lambertus; Oberkassel Bridge",
    "dortmund": "Dortmund Hauptbahnhof; Westfalenhalle",
    "munster": "St Paulus Dom; Prince-Bishop's Palace",
    "osnabruck": "Osnabruck Cathedral; Bucksturm tower",
    "bielefeld": "Sparrenburg Castle; Bielefeld Town Hall",
    "paderborn": "Paderborn Cathedral; Kaiserpfalz",
    "wiesbaden": "Wiesbaden Kurhaus; Neroberg",
    "mainz": "Mainz Cathedral; Gutenberg Museum",
    "wolverhampton": "St Peter's Church; Goodyear Works",
    "nottingham": "Nottingham Castle; Council House",
    "stoke": "Stoke Victoria Hall; Etruria Potteries",
    "northampton": "Northampton Guildhall; All Saints' Church",
    "worcester": "Worcester Cathedral; Royal Worcester Works",
    "cardiff": "Cardiff Castle; City Hall",
}

# Existing values that were anachronistic or placeholders (the Atomium is a 1958 building).
FIXUPS = {
    "brussels": "Palais de Justice; Grand-Place",
}

# Every id handled by Landmarks.build(), with the coords used to (re)create a feature row if the
# features list ever loses one. Kept here so the file is self-healing without touching the .gd.
FEATURE_COORDS = {
    "mont_saint_michel": ("Mont Saint-Michel", 48.6361, -1.5115, 1000),
    "dover_castle": ("Dover Castle", 51.1295, 1.3217, 400),
    "tower_bridge": ("Tower Bridge", 51.5055, -0.0754, 200),
    "big_ben": ("Big Ben", 51.5007, -0.1246, 200),
    "st_pauls": ("St Paul's Cathedral", 51.5138, -0.0984, 250),
    "pegasus_bridge": ("Pegasus Bridge", 49.2447, -0.274, 200),
    "arromanches_mulberry": ("Mulberry Harbour (Arromanches)", 49.34, -0.619, 1500),
    "eddystone": ("Eddystone Lighthouse", 50.1818, -4.2688, 200),
    "needles": ("The Needles", 50.662, -1.592, 800),
    "beffroi_calais": ("Calais Belfry", 50.9525, 1.856, 200),
    "cologne_cathedral": ("Cologne Cathedral", 50.9413, 6.9583, 400),
    "antwerp_cathedral": ("Antwerp Cathedral", 51.2205, 4.4012, 400),
    "bruges_belfry": ("Belfry of Bruges", 51.2087, 3.225, 400),
    "utrecht_dom": ("Dom Tower, Utrecht", 52.0907, 5.1214, 400),
    "aachen_cathedral": ("Aachen Cathedral", 50.7753, 6.0839, 400),
    "frankfurt_cathedral": ("Frankfurt Cathedral", 50.1106, 8.6853, 400),
    "coventry_cathedral": ("Coventry Cathedral (ruins)", 52.4082, -1.5062, 400),
    "canterbury_cathedral": ("Canterbury Cathedral", 51.2802, 1.0829, 400),
    "salisbury_cathedral": ("Salisbury Cathedral", 51.0651, -1.797, 400),
    "rouen_cathedral": ("Rouen Cathedral", 49.4402, 1.0951, 400),
    "amiens_cathedral": ("Amiens Cathedral", 49.8946, 2.3023, 400),
    "caen_abbey": ("Abbaye aux Hommes, Caen", 49.186, -0.3495, 400),
    "bayeux_cathedral": ("Bayeux Cathedral", 49.2765, -0.7027, 400),
    "windsor_castle": ("Windsor Castle", 51.4839, -0.6044, 400),
    "stonehenge": ("Stonehenge", 51.1789, -1.8262, 400),
    "ludendorff_bridge": ("Ludendorff Bridge, Remagen", 50.568, 7.233, 400),
    "nijmegen_bridge": ("Nijmegen Waal Bridge", 51.847, 5.856, 400),
    "arnhem_bridge": ("Arnhem Rhine Bridge", 51.974, 5.907, 400),
}


def build_ids():
    """Landmark ids handled in landmarks.gd build() (parsed, not hard-coded)."""
    src = open(LM_GD, encoding="utf-8").read()
    m = re.search(r"static func build\(id: String\) -> Node3D:(.*?)\n\troot\.scale", src, re.S)
    return re.findall(r'^\t\t"([a-z_0-9]+)":', m.group(1), re.M)


def main():
    obj = json.load(open(LOC, encoding="utf-8"))
    filled = fixed = added = 0

    for c in obj["cities"]:
        if not c.get("landmark"):
            if c["id"] in LANDMARKS:
                c["landmark"] = LANDMARKS[c["id"]]
                filled += 1
            else:
                raise SystemExit(f"no landmark text for city {c['id']}")
        elif c["id"] in FIXUPS and c["landmark"] != FIXUPS[c["id"]]:
            c["landmark"] = FIXUPS[c["id"]]
            fixed += 1

    have = {f["id"] for f in obj["features"] if f.get("type") == "landmark"}
    for lid in build_ids():
        if lid in have:
            continue
        name, lat, lon, rad = FEATURE_COORDS[lid]
        obj["features"].append(dict(
            id=lid, name=name, type="landmark", lat=lat, lon=lon, radius_m=rad,
            in_bounds=bool(LAT_MIN <= lat <= LAT_MAX and LON_MIN <= lon <= LON_MAX)))
        added += 1

    text = json.dumps(obj, ensure_ascii=False, indent=1).replace("\n", "\r\n")
    with open(LOC, "w", encoding="utf-8", newline="") as f:
        f.write(text)

    print(f"cities landmark filled: {filled}")
    print(f"cities landmark fixed:  {fixed}")
    print(f"landmark features added: {added}")


if __name__ == "__main__":
    main()

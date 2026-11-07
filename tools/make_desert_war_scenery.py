#!/usr/bin/env python3
"""Author + validate data/desert/war_scenery.json (dated desert war scenery; same row style as data/war_damage.json and
data/buildup_1944.json: id, name, lat, lon, from, to / full, source).

The dataset lives in this file so every coordinate is checked against the coast mask and heightmap on each run:
  * land features must be on land;  * 'coast' line ends are moved to the shore (first sea cell northward + margin);
  * harbour wrecks must be within 1.5 km of sea in the mask. The Natural Earth coastline (10 m) does not resolve harbour
    inlets (Tobruk, Grand Harbour, Marsamxett), so those wrecks sit on mask-land by up to ~1 km: flagged "harbour_in_mask_land".
Positions are hand-placed from published geography to roughly +-3..10 km (see "confidence"); dates follow the cited
Wikipedia campaign articles. Not wired into the game.
Run:  python3 tools/make_desert_war_scenery.py"""
import json
import math
import os

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "data", "desert")
meta = json.load(open(os.path.join(D, "region_meta.json")))
W, H = 7000, 2770
LAT0, LAT1, LON0, LON1 = meta["lat_min"], meta["lat_max"], meta["lon_min"], meta["lon_max"]
land = np.asarray(Image.open(os.path.join(D, "region_coast.png")).convert("L")) > 127
elev = np.asarray(Image.open(os.path.join(D, "region_height.png")), np.float32) * (meta["max_elev_m"] / 65535.0)
loc = json.load(open(os.path.join(D, "locations.json")))
AF = {a["id"]: a for a in loc["airfields"]}
PXKM = 0.298


def rc(lat, lon):
    return int((LAT1 - lat) / (LAT1 - LAT0) * H), int((lon - LON0) / (LON1 - LON0) * W)


def ll(r, c):
    return LAT1 - (r + 0.5) / H * (LAT1 - LAT0), LON0 + (c + 0.5) / W * (LON1 - LON0)


def sea_km(lat, lon, rad=40):
    r, c = rc(lat, lon)
    win = land[max(0, r - rad):r + rad + 1, max(0, c - rad):c + rad + 1]
    ys, xs = np.nonzero(~win)
    if not len(ys):
        return 99.0
    cy, cx = min(r, rad), min(c, rad)
    return float(np.sqrt(((ys - cy) ** 2 + (xs - cx) ** 2).min())) * PXKM


def to_coast(lat, lon, margin_px=5):
    """Move a point north (or the first sea direction) to just inland of the shore."""
    r, c = rc(lat, lon)
    rr = r
    if land[rr, c]:
        while rr > 0 and land[rr, c]:
            rr -= 1
        return ll(rr + margin_px, c)
    while rr < H - 1 and not land[rr, c]:
        rr += 1
    return ll(rr + margin_px, c)


def nearest_land(lat, lon, rad=30):
    r, c = rc(lat, lon)
    if land[r, c]:
        return lat, lon
    best = None
    for dr in range(-rad, rad + 1):
        for dc in range(-rad, rad + 1):
            if land[min(H - 1, max(0, r + dr)), min(W - 1, max(0, c + dc))]:
                d = dr * dr + dc * dc
                if best is None or d < best[0]:
                    best = (d, r + dr, c + dc)
    return ll(best[1], best[2]) if best else (lat, lon)


problems = []


def chk_land(i, lat, lon):
    r, c = rc(lat, lon)
    ok = bool(land[r, c])
    if not ok:
        problems.append("%s: (%.4f,%.4f) is sea in the coast mask" % (i, lat, lon))
    return ok


def row(i, name, lat, lon, **kw):
    d = {"id": i, "name": name, "lat": round(lat, 4), "lon": round(lon, 4)}
    d.update(kw)
    return d


wrecks, lines, boxes, battle, airdmg, dmg, passes = [], [], [], [], [], [], []

# ------------------------------------------------------------ harbour wrecks (water features, harbour inlets unresolved)
for i, nm, la, lo, hull, ln, frm, to, src, conf in [
    ("wreck_tobruk_san_giorgio", "Italian armoured cruiser San Giorgio, scuttled and burnt out in Tobruk harbour", 32.0865, 23.9780, "cruiser", 140, "1941-01-22", "", "Wikipedia: Italian cruiser San Giorgio (scuttled at Tobruk 22 Jan 1941; the hulk stayed in the bay)", "medium"),
    ("wreck_tobruk_ladybird", "HMS Ladybird gunboat, sunk by Stukas in Tobruk harbour", 32.0830, 23.9700, "gunboat", 56, "1941-05-12", "", "Wikipedia: HMS Ladybird (T 1941 sunk at Tobruk 12 May 1941)", "medium"),
    ("wreck_tobruk_liguria", "Hulk of the liner Liguria, Tobruk harbour", 32.0900, 23.9830, "liner", 130, "1941-01-22", "", "Wikipedia: Siege of Tobruk / Capture of Tobruk (Jan 1941) - Italian shipping scuttled or bombed in the harbour; exact berth unverified", "low"),
    ("wreck_malta_maori", "HMS Maori (destroyer), bombed and sunk in Grand Harbour", 35.8905, 14.5230, "destroyer", 115, "1942-02-12", "1945-09-01", "Wikipedia: HMS Maori (F24) (bombed at Malta 12 Feb 1942, wreck raised and scuttled 1945)", "medium"),
    ("wreck_malta_breconshire", "SS Breconshire (supply ship), capsized in Marsaxlokk Bay", 35.8385, 14.5560, "cargo", 140, "1942-03-27", "1950-12-31", "Wikipedia: SS Breconshire (bombed in Marsaxlokk 27 Mar 1942, capsized; wreck left)", "medium"),
    ("wreck_malta_ohio", "SS Ohio, broken-backed tanker moored in Grand Harbour after Operation Pedestal", 35.8890, 14.5300, "tanker", 150, "1942-08-15", "1946-09-19", "Wikipedia: SS Ohio (arrived 15 Aug 1942; scuttled off Malta 19 Sep 1946)", "medium"),
]:
    d = sea_km(la, lo)
    in_mask_water = not bool(land[rc(la, lo)])
    if d > 1.5 and not in_mask_water:
        problems.append("%s: %.1f km from sea in the mask" % (i, d))
    wrecks.append(row(i, nm, la, lo, type="wreck", hull=hull, length_m=ln, heading=0 if "Ohio" not in nm else 80,
                      **{"from": frm, "to": to}, source=src, confidence=conf, mask_sea_km=round(d, 1),
                      coord_check="water" if in_mask_water else "harbour_in_mask_land"))

# ------------------------------------------------------------ defence lines (wire + mines), box garrisons
def line(i, nm, pts, frm, to, src, conf, coast_start=False, coast_end=False, belts=(), wire=True, mines=True, depth_m=1500, trench=True):
    pts = [list(p) for p in pts]
    if coast_start:
        pts[0] = list(to_coast(*pts[0]))
    if coast_end:
        pts[-1] = list(to_coast(*pts[-1]))
    for p in pts:
        chk_land(i, p[0], p[1])
    lines.append({"id": i, "name": nm, "type": "defence_line", "pts": [[round(p[0], 4), round(p[1], 4)] for p in pts],
                  "wire": wire, "mines": mines, "trench": trench, "belt_depth_m": depth_m, "from": frm, "to": to, "source": src,
                  "confidence": conf})


line("line_gazala", "Gazala Line: wire, mines and boxes from Ain el Gazala to Bir Hakeim",
     [(32.20, 23.05), (32.10, 23.12), (32.02, 23.20), (31.93, 23.27), (31.82, 23.33), (31.70, 23.40), (31.594, 23.480)],
     "1942-02-04", "1942-06-14", "Wikipedia: Battle of Gazala (the Gazala Line was built Feb-May 1942; broken 26 May - 14 Jun 1942)", "medium",
     coast_start=True, depth_m=2500)
line("line_alamein_axis", "El Alamein: Axis wire and Devil's Gardens, coast to Qaret el Himeimat",
     [(30.87, 28.86), (30.82, 28.84), (30.75, 28.82), (30.68, 28.82), (30.60, 28.85), (30.55, 28.88)],
     "1942-07-04", "1943-06-30", "Wikipedia: Second Battle of El Alamein (Axis mine belts ~5 km apart; Devil's Gardens); First Alamein 1-27 Jul 1942", "medium",
     coast_start=True, depth_m=5000)
line("line_alamein_allied", "El Alamein: British wire and minefields east of the Axis belts",
     [(30.84, 28.93), (30.79, 28.91), (30.72, 28.90), (30.66, 28.90), (30.60, 28.92)],
     "1942-07-04", "1942-11-04", "Wikipedia: First Battle of El Alamein / Second Battle (British defensive box line July - Oct 1942)", "low",
     coast_start=True, depth_m=3000)
line("line_mareth", "Mareth Line: French fortifications along Wadi Zigzaou, refurbished by the Axis",
     [(33.68, 10.40), (33.62, 10.29), (33.55, 10.17), (33.49, 10.06), (33.44, 9.98)],
     "1943-01-15", "1943-03-31", "Wikipedia: Mareth Line (~50 km from the Gulf of Gabes to Cheguimi / Djebel Matmata; Axis refurbished 1942-43; battle 16-31 Mar 1943)", "medium",
     coast_start=True, depth_m=1200)
line("line_tobruk_perimeter", "Tobruk fortress perimeter (Red Line): wire, anti-tank ditch and minefield ring",
     [(32.12, 23.80), (32.05, 23.66), (31.93, 23.72), (31.86, 23.90), (31.90, 24.15), (32.00, 24.28), (32.12, 24.22)],
     "1941-04-10", "1941-12-10", "Wikipedia: Siege of Tobruk (perimeter ~50 km long, held 10 Apr - 10 Dec 1941)", "medium", coast_start=True, coast_end=True, depth_m=1500)
line("line_halfaya_wire", "Halfaya Pass: Axis wire and dug-in 88 mm positions on the escarpment",
     [(31.540, 25.160), (31.515, 25.195), (31.490, 25.225)],
     "1941-05-27", "1942-01-17", "Wikipedia: Halfaya Pass (taken by Germans 27 May 1941; Battleaxe 15 Jun 1941; garrison surrendered 17 Jan 1942)", "medium",
     wire=True, mines=True, depth_m=800)
line("line_wadi_akarit", "Wadi Akarit - Gabes gap: Axis wire and ditch between Chott el Fejaj and the sea",
     [(34.02, 10.10), (33.99, 10.02), (33.96, 9.93)],
     "1943-03-30", "1943-04-07", "Wikipedia: Battle of Wadi Akarit (6-7 Apr 1943); position approximate", "low", coast_start=True, depth_m=900)

def box(i, nm, la, lo, rad, frm, to, src, conf, wire=True, mines=True, garrison=""):
    chk_land(i, la, lo)
    boxes.append(row(i, nm, la, lo, type="fortified_box", radius_m=rad, wire=wire, mines=mines, garrison=garrison,
                     **{"from": frm, "to": to}, source=src, confidence=conf, elev_m=round(float(elev[rc(la, lo)]))))


box("box_bir_hakeim", "Bir Hakeim (Free French brigade box)", 31.594, 23.480, 2200, "1942-02-14", "1942-06-11",
    "Wikipedia: Battle of Bir Hakeim (31 35N 23 28E; Free French garrison until the breakout 10-11 Jun 1942)", "high", garrison="Free French")
box("box_gazala", "Gazala box (1st South African Division)", 32.17, 23.05, 2500, "1942-02-04", "1942-06-14",
    "Wikipedia: Battle of Gazala (Gazala Line western box); position approximate", "low", garrison="1st South African Division")
box("box_got_el_ualeb", "Got el Ualeb / Sidi Muftah (150th Brigade box)", 32.02, 23.19, 2000, "1942-02-20", "1942-06-01",
    "Wikipedia: Battle of Gazala (150th Brigade box overrun 1 Jun 1942); position approximate", "low", garrison="150th Brigade")
box("box_knightsbridge", "Knightsbridge box (201st Guards Brigade)", 31.99, 23.62, 2200, "1942-05-20", "1942-06-13",
    "Wikipedia: Battle of Gazala (Knightsbridge box evacuated 13 Jun 1942); position approximate", "low", garrison="201st Guards Brigade")
box("box_el_adem", "El Adem box", 31.85, 23.93, 2200, "1942-05-20", "1942-06-17",
    "Wikipedia: Battle of Gazala (El Adem box evacuated 17 Jun 1942)", "medium", garrison="29th Indian Brigade")
box("box_sidi_rezegh", "Sidi Rezegh escarpment positions (Crusader battlefield)", 31.90, 24.39, 3500, "1941-11-19", "1941-12-01",
    "Wikipedia: Operation Crusader (Sidi Rezegh 19-23 Nov 1941); position approximate", "low", wire=False, mines=False, garrison="mixed")
box("box_bardia", "Bardia Italian fortified perimeter (fortress)", 31.76, 25.09, 6000, "1940-06-11", "1941-01-05",
    "Wikipedia: Battle of Bardia (Italian wire and anti-tank ditch; fell 5 Jan 1941)", "medium", garrison="Italian 23rd Corps")
box("box_el_alamein_station", "El Alamein railway station box (Alamein box)", 30.8330, 28.9510, 2500, "1942-07-01", "1942-11-04",
    "Wikipedia: First Battle of El Alamein (El Alamein 30 50N 28 56E; 1st South African Division box)", "high", garrison="1st South African Division")
box("box_alam_halfa_ridge", "Alam el Halfa ridge defences", 30.78, 29.02, 3500, "1942-08-25", "1942-09-06",
    "Wikipedia: Battle of Alam el Halfa (30 Aug - 5 Sep 1942); position approximate", "low", wire=False, mines=True, garrison="44th Division / 10th Armoured")
box("box_medenine", "Medenine anti-tank screen", 33.355, 10.505, 3500, "1943-03-04", "1943-03-07",
    "Wikipedia: Battle of Medenine (6 Mar 1943)", "medium", wire=False, mines=True, garrison="2nd NZ Division")
box("box_kasserine_pass", "Kasserine Pass defences", 35.18, 8.68, 3000, "1943-02-14", "1943-02-22",
    "Wikipedia: Battle of the Kasserine Pass (19-24 Feb 1943)", "medium", wire=False, mines=True, garrison="US 26th / 19th Engineers")

passes.append(row("pass_halfaya", "Halfaya Pass (Hellfire Pass): 88 mm guns, wire and wrecked tanks", 31.505, 25.205, type="pass_feature",
                  radius_m=2500, wrecks=14, **{"from": "1941-06-15", "to": "1942-01-17"},
                  source="Wikipedia: Halfaya Pass (Battleaxe 15 Jun 1941 - 88 mm guns destroyed the first British tank wave; garrison surrendered 17 Jan 1942); 7.5 km S of the Sollum pass",
                  confidence="medium"))
chk_land("pass_halfaya", 31.505, 25.205)
passes.append(row("pass_sollum", "Sollum Pass (coast road climb)", 31.5677, 25.1482, type="pass_feature", radius_m=1800, wrecks=6,
                  **{"from": "1941-04-14", "to": "1942-11-12"}, source="Wikipedia: Halfaya Pass (the more major pass 7.5 km north); steepest scarp cell on the heightmap", confidence="medium"))
passes.append(row("pass_kasserine", "Kasserine Pass: knocked-out US armour and halftracks", 35.18, 8.68, type="pass_feature", radius_m=3000, wrecks=22,
                  **{"from": "1943-02-19", "to": "1943-04-30"}, source="Wikipedia: Battle of the Kasserine Pass (19-24 Feb 1943)", confidence="medium"))

# ------------------------------------------------------------ battle wreck fields (burnt tanks, trucks, guns)
def bw(i, nm, la, lo, rad, tanks, trucks, frm, to, src, conf):
    chk_land(i, la, lo)
    battle.append(row(i, nm, la, lo, type="battle_wrecks", radius_m=rad, tanks=tanks, trucks=trucks, **{"from": frm, "to": to},
                      source=src, confidence=conf))


bw("wrecks_sidi_barrani", "Sidi Barrani: abandoned Italian vehicles and guns", 31.61, 25.92, 5000, 8, 60, "1940-12-10", "1941-03-31", "Wikipedia: Operation Compass (Sidi Barrani 9-11 Dec 1940)", "medium")
bw("wrecks_bardia", "Bardia: Italian guns and trucks", 31.76, 25.09, 4000, 6, 50, "1941-01-05", "1941-04-10", "Wikipedia: Battle of Bardia", "medium")
bw("wrecks_sidi_rezegh", "Sidi Rezegh: burnt tanks on the escarpment", 31.90, 24.39, 5000, 40, 30, "1941-11-23", "1942-05-30", "Wikipedia: Operation Crusader (Totensonntag 23 Nov 1941)", "low")
bw("wrecks_cauldron", "The Cauldron: tank graveyard south of Knightsbridge", 31.93, 23.55, 6000, 60, 40, "1942-06-05", "1942-12-31", "Wikipedia: Battle of Gazala (The Cauldron 30 May - 5 Jun 1942)", "low")
bw("wrecks_alam_halfa", "Alam el Halfa: Panzer wrecks", 30.76, 28.93, 4500, 25, 20, "1942-09-01", "1943-03-31", "Wikipedia: Battle of Alam el Halfa", "low")
bw("wrecks_kidney_ridge", "Kidney Ridge (Snipe): burnt tanks and guns", 30.80, 28.87, 4000, 45, 30, "1942-10-27", "1943-04-30", "Wikipedia: Second Battle of El Alamein (Operation Supercharge; Snipe 27 Oct 1942)", "low")
bw("wrecks_tel_el_eisa", "Tel el Eisa: wrecks along the coast road", 30.86, 28.90, 3000, 12, 40, "1942-07-10", "1942-12-31", "Wikipedia: First Battle of El Alamein (Tel el Eisa 10-11 Jul 1942)", "low")
bw("wrecks_via_balbia_el_daba", "Coast road retreat: burnt-out Axis transport, El Daba to Fuka", 30.97, 28.55, 8000, 10, 120, "1942-11-05", "1943-06-30", "Wikipedia: Second Battle of El Alamein (pursuit, Nov 1942)", "low")
bw("wrecks_sidi_bou_zid", "Sidi Bou Zid: destroyed US tanks", 35.04, 9.49, 6000, 50, 40, "1943-02-14", "1943-04-30", "Wikipedia: Battle of Sidi Bou Zid (14-17 Feb 1943)", "medium")
bw("wrecks_mareth", "Mareth / Wadi Zigzaou: abandoned tanks and guns", 33.58, 10.22, 5000, 20, 40, "1943-03-27", "1943-06-30", "Wikipedia: Battle of the Mareth Line (Operation Pugilist 19-23 Mar 1943)", "low")
bw("wrecks_medenine", "Medenine: knocked-out Panzers", 33.37, 10.46, 4000, 32, 6, "1943-03-06", "1943-06-30", "Wikipedia: Battle of Medenine (6 Mar 1943, 52 tanks lost)", "medium")
bw("wrecks_tunis_bizerte", "Tunis and Bizerte: scuttled equipment and abandoned vehicles", 36.88, 10.05, 9000, 30, 200, "1943-05-08", "1943-12-31", "Wikipedia: Tunisian campaign (Axis surrender 13 May 1943)", "low")

# ------------------------------------------------------------ bomb-damaged airfields (use locations.json positions)
def adm(aid, frm, peak, full, level, radius, craters, src, conf="medium"):
    a = AF[aid]
    chk_land("airfield_" + aid, a["lat"], a["lon"])
    airdmg.append(row("dmg_" + aid, a["name"] + ": craters, burnt hangars and wrecked aircraft", a["lat"], a["lon"], type="airfield_damage", airfield=aid,
                      radius_m=radius, level=level, craters=craters, **{"from": frm, "peak": peak, "full": full}, source=src, confidence=conf))


adm("luqa", "1940-06-11", "1942-04-20", "1942-05-10", 0.75, 1900, 140, "Wikipedia: Siege of Malta (1940-42) (Luqa the main Axis target, heaviest Mar-Apr 1942)")
adm("hal_far", "1940-06-11", "1942-04-20", "1942-05-10", 0.8, 1700, 120, "Wikipedia: Siege of Malta (1940-42) (Hal Far / Kalafrana raided from Jan 1941)")
adm("ta_kali", "1940-06-11", "1942-04-15", "1942-05-10", 0.8, 1800, 130, "Wikipedia: Siege of Malta (1940-42) (Ta Kali (Takali) hammered Mar-Apr 1942)")
adm("benina", "1941-04-10", "1942-12-01", "1943-01-23", 0.45, 2000, 60, "Wikipedia: Benina Airport / North African campaign air raids (RAF raids Benghazi area 1941-43)", "low")
adm("castel_benito", "1941-01-15", "1943-01-10", "1943-01-23", 0.5, 2200, 80, "Wikipedia: Tripoli / Western Desert air war (RAF raids until the fall of Tripoli 23 Jan 1943)", "low")
adm("el_adem", "1941-04-10", "1942-06-17", "1942-06-20", 0.55, 2000, 70, "Wikipedia: RAF Station El Adem (bombed during the Siege of Tobruk and Gazala)", "low")
adm("gambut", "1941-11-20", "1942-06-17", "1942-06-20", 0.4, 1800, 40, "Wikipedia: Battle of Gazala (LGs Gambut overrun 17 Jun 1942)", "low")
adm("martuba", "1941-12-20", "1942-11-15", "1942-11-20", 0.4, 1800, 40, "Wikipedia: Western Desert air war (Martuba airfields raided 1941-42)", "low")
adm("catania_fontanarossa", "1943-05-05", "1943-07-18", "1943-08-05", 0.6, 2400, 90, "Wikipedia: Allied invasion of Sicily (airfields around Catania bombed May-Aug 1943)", "low")
adm("comiso", "1943-05-10", "1943-07-09", "1943-07-12", 0.55, 2200, 70, "Wikipedia: Allied invasion of Sicily (Comiso bombed before the landings, taken 11 Jul 1943)", "low")
adm("el_aouina", "1943-02-01", "1943-04-20", "1943-05-10", 0.55, 2200, 80, "Wikipedia: Tunisian campaign (Allied air raids on the Tunis airfields Feb-May 1943)", "low")
adm("sfax_el_maou", "1943-02-20", "1943-03-30", "1943-04-10", 0.4, 1900, 40, "Wikipedia: Tunisian campaign (Sfax airfields raided before the 10 Apr 1943 fall)", "low")
adm("bizerte_sidi_ahmed", "1943-04-01", "1943-05-01", "1943-05-10", 0.5, 2000, 60, "Wikipedia: Tunisian campaign (Bizerte raided before 7 May 1943)", "low")
adm("thelepte", "1943-02-14", "1943-02-17", "1943-03-01", 0.5, 1700, 40, "Wikipedia: Battle of the Kasserine Pass (Thelepte evacuated and wrecked 17 Feb 1943)", "low")

# ------------------------------------------------------------ town and port damage (war_damage.json areas schema)
def da(i, nm, la, lo, rad, level, frm, full, src):
    la, lo = nearest_land(la, lo)       # city centres on a coarse coast can fall in the mask sea: move to the shore
    la, lo = round(la, 4), round(lo, 4)
    chk_land(i, la, lo)
    dmg.append({"id": i, "name": nm, "lat": la, "lon": lo, "radius_m": rad, "level": level, "from": frm, "full": full, "source": src})


da("dmg_valletta", "Valletta and Floriana", 35.8975, 14.5090, 1100, 0.40, "1940-06-11", "1942-05-10", "Wikipedia: Siege of Malta (1940-42)")
da("dmg_three_cities", "Senglea, Vittoriosa and Cospicua (dockyard)", 35.8870, 14.5220, 1200, 0.65, "1941-01-10", "1942-05-10", "Wikipedia: Siege of Malta (1940-42) (dockyard area worst hit)")
da("dmg_kalafrana_marsaxlokk", "Kalafrana and Birzebbuga", 35.8210, 14.5230, 900, 0.45, "1941-01-20", "1942-05-10", "Wikipedia: Siege of Malta (1940-42)")
da("dmg_tobruk", "Tobruk town and harbour", 32.0836, 23.9764, 1500, 0.70, "1941-04-10", "1942-06-21", "Wikipedia: Siege of Tobruk (nightly air raids 1941; fell 21 Jun 1942)")
da("dmg_benghazi", "Benghazi port and old town", 32.1167, 20.0667, 1700, 0.40, "1941-04-01", "1943-01-01", "Wikipedia: Benghazi (heavily bombed; changed hands five times 1941-42)")
da("dmg_tripoli_port", "Tripoli port and harbour", 32.9020, 13.1850, 1500, 0.35, "1941-01-15", "1943-01-21", "Wikipedia: Tripoli (RAF and Navy bombardment 1941-43)")
da("dmg_bardia", "Bardia town", 31.7592, 25.0853, 700, 0.55, "1941-01-02", "1941-01-05", "Wikipedia: Battle of Bardia (3-5 Jan 1941)")
da("dmg_sollum", "Sollum harbour village", 31.5528, 25.15, 600, 0.40, "1941-06-15", "1941-12-31", "Wikipedia: Battle of Sollum / Halfaya Pass")
da("dmg_mersa_matruh", "Mersa Matruh", 31.3525, 27.2453, 900, 0.30, "1940-09-10", "1942-07-01", "Wikipedia: Mersa Matruh (raids 1940-42)")
da("dmg_bizerte", "Bizerte port", 37.2746, 9.8739, 1400, 0.50, "1943-04-01", "1943-05-07", "Wikipedia: Tunisian campaign (Bizerte bombing, fell 7 May 1943)")
da("dmg_tunis_goulette", "La Goulette and Tunis port", 36.8165, 10.3050, 1300, 0.35, "1942-11-10", "1943-05-08", "Wikipedia: Tunisian campaign (Allied air raids on Tunis docks)")
da("dmg_sfax", "Sfax port", 34.7406, 10.7603, 1300, 0.30, "1943-02-20", "1943-04-10", "Wikipedia: Tunisian campaign (Sfax bombed, taken 10 Apr 1943)")
da("dmg_catania", "Catania port and railway", 37.5000, 15.0900, 1500, 0.30, "1943-05-05", "1943-08-05", "Wikipedia: Allied invasion of Sicily")

out = {
    "source_note": "Dated war scenery for the desert map (Libya, Egypt, Tunisia, Malta). Same row conventions as data/war_damage.json (areas: from, full, level, radius_m) and data/buildup_1944.json (from, to; empty 'to' = stays). Positions are hand-placed from published geography (+-3..10 km, see 'confidence') and checked against region_coast.png by tools/make_desert_war_scenery.py; dates follow the cited Wikipedia campaign articles. Harbour wrecks: the 10 m Natural Earth coast does not resolve harbour inlets (coord_check 'harbour_in_mask_land'), so a renderer must either carve harbour water or snap them to the shore. Not wired into the game.",
    "harbour_wrecks": wrecks,
    "defence_lines": lines,
    "fortified_boxes": boxes,
    "pass_features": passes,
    "battle_wrecks": battle,
    "airfield_damage": airdmg,
    "damage_areas": dmg,
}
json.dump(out, open(os.path.join(D, "war_scenery.json"), "w"), indent=1, ensure_ascii=False)
print("rows:", {k: len(v) for k, v in out.items() if isinstance(v, list)})
for ln in lines:
    e = [float(elev[rc(p[0], p[1])]) for p in ln["pts"]]
    print("  line %-22s elev along: %s" % (ln["id"], " ".join("%.0f" % x for x in e)))
print("PROBLEMS:", len(problems))
for p in problems:
    print("  ", p)

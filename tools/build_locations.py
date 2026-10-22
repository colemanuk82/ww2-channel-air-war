#!/usr/bin/env python3
"""Generates data/locations.json and data/missions_seed.json (hand-authored real-world data).

Run: python tools/build_locations.py
side_owner on targets is "Axis" or "Allies" (the side that owns / defends the target; the
opposing side attacks it). Airfields use side "RAF" / "Luftwaffe" per the data contract.
Every record gets in_bounds=false if it lies outside the playable bounds (lat 48.9..51.7,
lon -4.6..4.7) -- e.g. Duxford, Debden, Mont Saint-Michel.
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAT_MIN, LAT_MAX, LON_MIN, LON_MAX = 48.9, 53.0, -4.6, 9.0

# id, name, side, lat, lon, heading_deg (runway), runway_len_m
AIRFIELDS = [
    ("biggin_hill", "Biggin Hill", "RAF", 51.3308, 0.0325, 30, 1800),
    ("hawkinge", "Hawkinge", "RAF", 51.1150, 1.1494, 100, 900),
    ("manston", "Manston", "RAF", 51.3422, 1.3461, 100, 2700),
    ("tangmere", "Tangmere", "RAF", 50.8472, -0.7061, 100, 1400),
    ("kenley", "Kenley", "RAF", 51.3042, -0.0903, 70, 1000),
    ("northolt", "Northolt", "RAF", 51.5530, -0.4181, 70, 1600),
    ("duxford", "Duxford", "RAF", 52.0908, 0.1319, 60, 1300),
    ("debden", "Debden", "RAF", 51.9525, 0.2686, 90, 1100),
    ("westhampnett", "Westhampnett", "RAF", 50.8586, -0.7503, 60, 1000),
    ("lympne", "Lympne", "RAF", 51.0794, 1.0183, 110, 1000),
    ("hornchurch", "Hornchurch", "RAF", 51.5030, 0.2078, 70, 1100),
    ("calais_marck", "Calais-Marck", "Luftwaffe", 50.9622, 1.9540, 60, 1400),
    ("cap_gris_nez", "Cap Gris-Nez (Audembert)", "Luftwaffe", 50.8660, 1.6130, 90, 1000),
    ("abbeville_drucat", "Abbeville-Drucat", "Luftwaffe", 50.1420, 1.8320, 60, 1500),
    ("caen_carpiquet", "Caen-Carpiquet", "Luftwaffe", 49.1733, -0.4505, 130, 1800),
    ("cherbourg_maupertus", "Cherbourg-Maupertus", "Luftwaffe", 49.6500, -1.4700, 100, 1800),
    ("merville", "Merville", "Luftwaffe", 50.6150, 2.6420, 90, 1200),
    ("saint_omer", "Saint-Omer (Longuenesse)", "Luftwaffe", 50.7284, 2.2556, 90, 1200),
    ("lille_nord", "Lille-Nord (Vendeville)", "Luftwaffe", 50.6560, 3.1000, 90, 1500),
    ("brussels_evere", "Brussels-Evere", "Luftwaffe", 50.9019, 4.4950, 70, 1900),
    ("antwerp_deurne", "Antwerp-Deurne", "Luftwaffe", 51.1894, 4.4603, 110, 1500),
]

# id, name, lat, lon, size, landmark
CITIES = [
    ("london", "London", 51.5074, -0.1278, 5, "Big Ben; Tower Bridge"),
    ("dover", "Dover", 51.1279, 1.3134, 2, "Dover Castle"),
    ("folkestone", "Folkestone", 51.0814, 1.1695, 2, None),
    ("portsmouth", "Portsmouth", 50.8198, -1.0880, 4, "Spinnaker (harbour forts)"),
    ("southampton", "Southampton", 50.9097, -1.4044, 4, None),
    ("brighton", "Brighton", 50.8225, -0.1372, 3, "Palace Pier"),
    ("plymouth", "Plymouth", 50.3755, -4.1427, 4, "Smeaton's Tower"),
    ("canterbury", "Canterbury", 51.2802, 1.0789, 2, "Canterbury Cathedral"),
    ("calais", "Calais", 50.9513, 1.8587, 3, "Hotel de Ville belfry"),
    ("dunkirk", "Dunkirk", 51.0343, 2.3768, 3, "Belfry of Saint-Eloi"),
    ("boulogne", "Boulogne-sur-Mer", 50.7264, 1.6147, 3, "Notre-Dame basilica"),
    ("dieppe", "Dieppe", 49.9230, 1.0770, 3, "Chateau de Dieppe"),
    ("le_havre", "Le Havre", 49.4944, 0.1079, 4, "Saint Joseph's Church"),
    ("rouen", "Rouen", 49.4432, 1.0993, 4, "Rouen Cathedral"),
    ("caen", "Caen", 49.1829, -0.3707, 3, "Abbaye aux Hommes"),
    ("cherbourg", "Cherbourg", 49.6337, -1.6220, 3, None),
    ("bayeux", "Bayeux", 49.2764, -0.7024, 2, "Bayeux Cathedral"),
    ("amiens", "Amiens", 49.8941, 2.2958, 3, "Amiens Cathedral"),
    ("lille", "Lille", 50.6292, 3.0573, 4, "Beffroi"),
    ("arras", "Arras", 50.2910, 2.7775, 2, "Arras belfry"),
    ("ostend", "Ostend", 51.2154, 2.9286, 3, None),
    ("bruges", "Bruges", 51.2093, 3.2247, 3, "Belfry of Bruges"),
    ("ghent", "Ghent", 51.0543, 3.7174, 3, "Saint Bavo Cathedral"),
    ("brussels", "Brussels", 50.8503, 4.3517, 5, "Atomium (post-war)"),
    ("antwerp", "Antwerp", 51.2194, 4.4025, 4, "Cathedral of Our Lady"),
    # extra towns for density
    ("ramsgate", "Ramsgate", 51.3355, 1.4170, 1, None),
    ("chatham", "Chatham", 51.3811, 0.5272, 2, None),
    ("maidstone", "Maidstone", 51.2720, 0.5290, 2, None),
    ("hastings", "Hastings", 50.8543, 0.5735, 2, None),
    ("eastbourne", "Eastbourne", 50.7687, 0.2905, 2, None),
    ("chichester", "Chichester", 50.8365, -0.7792, 1, "Chichester Cathedral"),
    ("guildford", "Guildford", 51.2362, -0.5704, 1, None),
    ("reading", "Reading", 51.4543, -0.9781, 2, None),
    ("saint_omer_town", "Saint-Omer", 50.7483, 2.2519, 1, None),
    ("le_treport", "Le Treport", 50.0590, 1.3800, 1, None),
    ("abbeville", "Abbeville", 50.1058, 1.8366, 1, None),
    ("poole", "Poole", 50.7150, -1.9872, 2, None),
    ("dunkirk_la_panne", "De Panne", 51.0990, 2.5950, 1, None),
    ("lisieux", "Lisieux", 49.1452, 0.2272, 1, None),
    ("saint_lo", "Saint-Lo", 49.1160, -1.0910, 1, None),
    ("valognes", "Valognes", 49.5090, -1.4710, 1, None),
]

# id, name, type, lat, lon, radius_m
FEATURES = [
    ("white_cliffs_dover", "White Cliffs of Dover", "cliff", 51.1330, 1.3650, 4500),
    ("seven_sisters", "Seven Sisters", "cliff", 50.7450, 0.1550, 4000),
    ("beachy_head", "Beachy Head", "cliff", 50.7340, 0.2420, 1500),
    ("cap_blanc_nez", "Cap Blanc-Nez", "cliff", 50.9230, 1.7160, 2500),
    ("cap_gris_nez_cape", "Cap Gris-Nez", "cliff", 50.8700, 1.5833, 2500),
    ("utah_beach", "Utah Beach", "beach", 49.4160, -1.1750, 3500),
    ("omaha_beach", "Omaha Beach", "beach", 49.3700, -0.8700, 4500),
    ("gold_beach", "Gold Beach", "beach", 49.3400, -0.5500, 4500),
    ("juno_beach", "Juno Beach", "beach", 49.3350, -0.4550, 3500),
    ("sword_beach", "Sword Beach", "beach", 49.2900, -0.2650, 3500),
    ("dunkirk_beaches", "Dunkirk Beaches (Malo-les-Bains)", "beach", 51.0500, 2.3900, 3500),
    ("la_panne_beach", "La Panne Beach (Dunkirk evacuation)", "beach", 51.0950, 2.5900, 3000),
    ("longues_sur_mer", "Longues-sur-Mer Battery", "battery", 49.3400, -0.6930, 600),
    ("pointe_du_hoc", "Pointe du Hoc Battery", "battery", 49.3969, -0.9889, 500),
    ("merville_battery", "Merville Battery", "battery", 49.2800, -0.2000, 500),
    ("thames", "River Thames", "river", 51.4900, 0.2000, 25000),
    ("seine", "River Seine", "river", 49.4300, 1.0500, 25000),
    ("somme", "River Somme", "river", 50.1100, 1.8000, 25000),
    ("scheldt", "River Scheldt", "river", 51.2000, 4.3700, 20000),
    ("new_forest", "New Forest", "forest", 50.8500, -1.6000, 12000),
    ("ardennes", "Ardennes (western edge)", "forest", 49.9500, 4.6000, 30000),
    ("foret_de_mormal", "Foret de Mormal", "forest", 50.2000, 3.6500, 8000),
    ("mont_saint_michel", "Mont Saint-Michel", "landmark", 48.6361, -1.5115, 1000),
    ("dover_castle", "Dover Castle", "landmark", 51.1295, 1.3217, 400),
    ("tower_bridge", "Tower Bridge", "landmark", 51.5055, -0.0754, 200),
    ("big_ben", "Big Ben", "landmark", 51.5007, -0.1246, 200),
    ("st_pauls", "St Paul's Cathedral", "landmark", 51.5138, -0.0984, 250),
    ("pegasus_bridge", "Pegasus Bridge", "landmark", 49.2447, -0.2740, 200),
    ("arromanches_mulberry", "Mulberry Harbour (Arromanches)", "landmark", 49.3400, -0.6190, 1500),
    ("eddystone", "Eddystone Lighthouse", "landmark", 50.1818, -4.2688, 200),
    ("needles", "The Needles", "landmark", 50.6620, -1.5920, 800),
    ("beffroi_calais", "Calais Belfry", "landmark", 50.9525, 1.8560, 200),
]

# id, name, type, lat, lon, side_owner, extra
T = []
def t(id_, name, typ, lat, lon, owner, **extra):
    T.append(dict(id=id_, name=name, type=typ, lat=lat, lon=lon, side_owner=owner, **extra))

# --- Axis-owned (attacked by Allies) ---
t("wizernes_v2", "Wizernes V-2 Bunker (La Coupole)", "v1_site", 50.7143, 2.1055, "Axis")
t("mimoyecques", "Mimoyecques V-3 Supergun Site", "v1_site", 50.8183, 1.7117, "Axis")
t("watten_bunker", "Watten Blockhaus", "v1_site", 50.8261, 2.2128, "Axis")
t("eperlecques", "Eperlecques Blockhaus", "v1_site", 50.8208, 2.1989, "Axis")
t("siracourt", "Siracourt V-1 Bunker", "v1_site", 50.4617, 2.3333, "Axis")
t("rail_lille_fives", "Lille-Fives Rail Yard", "rail_yard", 50.6300, 3.0800, "Axis")
t("rail_amiens_longueau", "Amiens-Longueau Rail Yard", "rail_yard", 49.8750, 2.3600, "Axis")
t("rail_rouen_sotteville", "Rouen-Sotteville Rail Yard", "rail_yard", 49.4150, 1.0800, "Axis")
t("rail_caen", "Caen Rail Yard", "rail_yard", 49.1750, -0.3470, "Axis")
t("rail_hazebrouck", "Hazebrouck Rail Junction", "rail_yard", 50.7250, 2.5400, "Axis")
t("rail_arras", "Arras Rail Yard", "rail_yard", 50.2880, 2.7900, "Axis")
t("port_calais", "Calais Harbour", "port", 50.9680, 1.8550, "Axis")
t("port_boulogne", "Boulogne Harbour", "port", 50.7330, 1.5950, "Axis")
t("port_dunkirk", "Dunkirk Harbour", "port", 51.0480, 2.3550, "Axis")
t("port_le_havre", "Le Havre Docks", "port", 49.4800, 0.1200, "Axis")
t("port_cherbourg", "Cherbourg Naval Base", "port", 49.6500, -1.6300, "Axis")
t("port_antwerp", "Antwerp Docks", "port", 51.2700, 4.3500, "Axis")
t("port_ostend", "Ostend Harbour", "port", 51.2300, 2.9250, "Axis")
t("port_zeebrugge", "Zeebrugge Mole", "port", 51.3300, 3.2000, "Axis")
t("bridge_tancarville", "Tancarville Bridge (ferry/rail area)", "bridge", 49.4700, 0.4600, "Axis")
t("bridge_rouen", "Rouen Seine Bridges", "bridge", 49.4370, 1.0850, "Axis")
t("bridge_oissel", "Oissel Rail Bridge", "bridge", 49.3400, 1.1050, "Axis")
t("bridge_vernon", "Vernon Seine Bridge", "bridge", 49.0900, 1.4850, "Axis")
t("bridge_mantes", "Mantes-Gassicourt Seine Bridge", "bridge", 48.9900, 1.7100, "Axis")
t("bridge_abbeville", "Abbeville Somme Bridge", "bridge", 50.1050, 1.8350, "Axis")
t("factory_minerva_antwerp", "Minerva Works Antwerp", "factory", 51.1900, 4.4300, "Axis")
t("factory_fives_lille", "Fives-Lille Locomotive Works", "factory", 50.6310, 3.0870, "Axis")
t("factory_rouen_oil", "Petit-Couronne Oil Refinery", "factory", 49.3900, 1.0200, "Axis")
t("battery_lindemann", "Batterie Lindemann (Sangatte)", "battery", 50.9300, 1.7400, "Axis")
t("battery_todt", "Batterie Todt (Haringzelles)", "battery", 50.8130, 1.6100, "Axis")
t("battery_longues", "Longues-sur-Mer Battery", "battery", 49.3400, -0.6930, "Axis")
t("battery_pointe_du_hoc", "Pointe du Hoc Battery", "battery", 49.3969, -0.9889, "Axis")
t("battery_merville", "Merville Battery", "battery", 49.2800, -0.2000, "Axis")
t("radar_douvres", "Douvres-la-Delivrande Radar", "radar", 49.2900, -0.3800, "Axis")
t("radar_wissant", "Wissant Freya Radar", "radar", 50.8890, 1.6600, "Axis")
t("radar_antifer", "Cap d'Antifer Radar", "radar", 49.6850, 0.1600, "Axis")
t("radar_la_hague", "Cap de la Hague Radar", "radar", 49.7200, -1.9400, "Axis")
t("convoy_rouen_caen", "Axis Supply Convoy Route Rouen-Caen", "convoy_route", 49.4432, 1.0993, "Axis",
  path=[[49.4432, 1.0993], [49.3000, 0.7500], [49.2300, 0.3000], [49.1829, -0.3707]])
t("convoy_lille_calais", "Axis Supply Convoy Route Lille-Calais", "convoy_route", 50.6292, 3.0573, "Axis",
  path=[[50.6292, 3.0573], [50.7000, 2.5000], [50.8500, 2.1000], [50.9513, 1.8587]])
t("convoy_antwerp_ostend", "Axis Shipping Route Antwerp-Ostend", "convoy_route", 51.2194, 4.4025, "Axis",
  path=[[51.2194, 4.4025], [51.3800, 3.8000], [51.3300, 3.2000], [51.2154, 2.9286]])

# --- Allied-owned (attacked by Axis) ---
t("radar_dover_ch", "Chain Home Dover (Swingate)", "radar", 51.1320, 1.3330, "Allies")
t("radar_dunkirk_ch", "Chain Home Dunkirk (Kent)", "radar", 51.2800, 0.9700, "Allies")
t("radar_pevensey_ch", "Chain Home Pevensey", "radar", 50.8200, 0.3600, "Allies")
t("radar_poling_ch", "Chain Home Poling", "radar", 50.8300, -0.5200, "Allies")
t("radar_ventnor_ch", "Chain Home Ventnor", "radar", 50.5900, -1.2000, "Allies")
t("factory_short_rochester", "Short Brothers Rochester", "factory", 51.3830, 0.5030, "Allies")
t("factory_supermarine_woolston", "Supermarine Woolston Works", "factory", 50.8900, -1.3800, "Allies")
t("factory_hawker_kingston", "Hawker Aircraft Kingston", "factory", 51.4100, -0.3000, "Allies")
t("oil_thameshaven", "Thameshaven Oil Depot", "factory", 51.5100, 0.5200, "Allies")
t("port_royal_docks", "Royal Docks London", "port", 51.5100, 0.0300, "Allies")
t("port_portsmouth", "Portsmouth Dockyard", "port", 50.7990, -1.1060, "Allies")
t("port_southampton", "Southampton Docks", "port", 50.8970, -1.4060, "Allies")
t("port_dover", "Dover Harbour", "port", 51.1230, 1.3200, "Allies")
t("port_plymouth", "Plymouth Devonport Dockyard", "port", 50.3860, -4.1840, "Allies")
t("rail_ashford", "Ashford Rail Works", "rail_yard", 51.1470, 0.8750, "Allies")
t("rail_clapham", "Clapham Junction Rail Yard", "rail_yard", 51.4640, -0.1700, "Allies")
t("bridge_tower", "Tower Bridge", "bridge", 51.5055, -0.0754, "Allies")
t("convoy_thames_dover", "Allied Channel Convoy Route (Peewit)", "convoy_route", 51.4800, 0.7000, "Allies",
  path=[[51.4800, 0.7000], [51.4000, 1.4500], [51.2000, 1.6500], [51.0000, 1.4500]])
t("convoy_dunkirk_evac", "Operation Dynamo Evacuation Route", "convoy_route", 51.0480, 2.3550, "Allies",
  path=[[51.0480, 2.3550], [51.1000, 1.9000], [51.1500, 1.5000], [51.1230, 1.3200]])
t("convoy_neptune", "Operation Neptune Assault Convoy Route", "convoy_route", 50.7000, -1.0000, "Allies",
  path=[[50.7000, -1.0000], [50.2000, -0.8000], [49.7000, -0.6000], [49.3500, -0.5500]])

MISSIONS = [
    dict(id="bob_kent", name="Battle of Britain: Kent Skies", year=1940, date="1940-08-15",
         sides=[dict(side="Allies", start_airfield="biggin_hill", aircraft=["spitfire", "hurricane"]),
                dict(side="Axis", start_airfield="calais_marck", aircraft=["bf109", "ju87", "he111"])],
         objectives={"Allies": ["radar_dover_ch", "airfield_defence_manston", "factory_short_rochester"],
                     "Axis": ["radar_dover_ch", "radar_dunkirk_ch", "factory_short_rochester"]},
         time_of_day=14.0, weather="scattered",
         brief="Mid-August 1940. Waves of Stukas and Heinkels escorted by Bf 109s head across the Channel at Kent's radar stations and airfields. Scramble from Biggin Hill, break up the raid before it reaches the coast. (Axis: smash the Chain Home radar and Short Brothers works.)"),
    dict(id="dieppe_1942", name="Operation Jubilee: Dieppe", year=1942, date="1942-08-19",
         sides=[dict(side="Allies", start_airfield="tangmere", aircraft=["spitfire", "typhoon"]),
                dict(side="Axis", start_airfield="abbeville_drucat", aircraft=["fw190", "bf109"])],
         objectives={"Allies": ["radar_antifer", "battery_todt", "port_le_havre"],
                     "Axis": ["convoy_neptune"]},
         time_of_day=6.0, weather="overcast",
         brief="Dawn, 19 August 1942. Canadian troops land at Dieppe. Provide fighter cover and suppress shore batteries from Tangmere against the new Focke-Wulf 190s. (Axis: intercept the landing force and its fighter umbrella.)"),
    dict(id="dday_1944", name="D-Day: Operation Overlord", year=1944, date="1944-06-06",
         sides=[dict(side="Allies", start_airfield="tangmere", aircraft=["typhoon", "p51", "p47", "mosquito", "b26"]),
                dict(side="Axis", start_airfield="caen_carpiquet", aircraft=["fw190", "bf109"])],
         objectives={"Allies": ["battery_longues", "battery_pointe_du_hoc", "battery_merville", "radar_douvres", "bridge_vernon"],
                     "Axis": ["convoy_neptune"]},
         time_of_day=5.5, weather="overcast",
         brief="6 June 1944. The largest amphibious landing in history. Strike the Atlantic Wall batteries and radar at Utah, Omaha, Gold, Juno and Sword before the first boats hit the beach, then keep the Luftwaffe off the fleet. (Axis: a handful of Fw 190s against the sky full of Allied fighters.)"),
    dict(id="dunkirk_1940", name="Operation Dynamo: Dunkirk Cover", year=1940, date="1940-05-30",
         sides=[dict(side="Allies", start_airfield="manston", aircraft=["spitfire", "hurricane"]),
                dict(side="Axis", start_airfield="calais_marck", aircraft=["bf109", "ju87", "he111"])],
         objectives={"Allies": ["convoy_dunkirk_evac"],
                     "Axis": ["port_dunkirk", "convoy_dunkirk_evac"]},
         time_of_day=16.0, weather="fog",
         brief="Late May 1940. Over 300,000 men wait on the Dunkirk beaches. Patrol the patch of sky over the evacuation ships and keep the Stukas off them. (Axis: sink the little ships and bomb the Mole.)"),
    dict(id="antwerp_raid", name="Bomber Command: Antwerp Docks", year=1944, date="1944-10-12",
         sides=[dict(side="Allies", start_airfield="northolt", aircraft=["lancaster", "mosquito", "b26"]),
                dict(side="Axis", start_airfield="antwerp_deurne", aircraft=["me262", "fw190", "bf109"])],
         objectives={"Allies": ["port_antwerp", "factory_minerva_antwerp"], "Axis": ["port_dunkirk"]},
         time_of_day=15.0, weather="scattered",
         brief="Autumn 1944. Antwerp's port is vital for Allied supply but V-weapons rain on the city. Hit the docks and yards on a bombing run across the Channel, and watch for Me 262 jets. (Axis: defend the docks.)"),
    dict(id="lille_raid", name="Lille Rail Yards Strike", year=1943, date="1943-05-13",
         sides=[dict(side="Allies", start_airfield="hornchurch", aircraft=["b26", "typhoon", "spitfire"]),
                dict(side="Axis", start_airfield="lille_nord", aircraft=["fw190", "bf109"])],
         objectives={"Allies": ["rail_lille_fives", "factory_fives_lille"], "Axis": ["radar_dover_ch"]},
         time_of_day=11.0, weather="clear",
         brief="Medium bombers escorted by Spitfires hit the Fives-Lille locomotive works and rail yards. Stay with the formation; Fw 190s will rise from Lille-Nord and Vendeville. (Axis: stop the Marauders.)"),
    dict(id="lehavre_raid", name="Le Havre Port Raid", year=1944, date="1944-09-05",
         sides=[dict(side="Allies", start_airfield="tangmere", aircraft=["lancaster", "mosquito", "typhoon"]),
                dict(side="Axis", start_airfield="caen_carpiquet", aircraft=["fw190", "bf109", "ju88"])],
         objectives={"Allies": ["port_le_havre", "radar_antifer", "bridge_tancarville"], "Axis": ["port_portsmouth"]},
         time_of_day=17.5, weather="overcast",
         brief="September 1944. The Germans still hold Le Havre as a fortress port. Pound the docks, radar and flak positions with heavy bombers and rocket-firing Typhoons before the ground assault. (Axis: raid Portsmouth.)"),
    dict(id="v1_sites", name="Crossbow: V-Weapon Sites", year=1944, date="1944-07-20",
         sides=[dict(side="Allies", start_airfield="kenley", aircraft=["typhoon", "p47", "mosquito", "lancaster"]),
                dict(side="Axis", start_airfield="saint_omer", aircraft=["fw190", "bf109"])],
         objectives={"Allies": ["wizernes_v2", "mimoyecques", "watten_bunker", "eperlecques", "siracourt"],
                     "Axis": ["radar_dover_ch"]},
         time_of_day=9.0, weather="clear",
         brief="Summer 1944. Strike the concrete V-weapon bunkers around Saint-Omer and the Pas-de-Calais: Wizernes, Mimoyecques, Watten and Eperlecques. Heavy flak. (Axis: defend the sites.)"),
    dict(id="seine_bridges", name="Interdiction: Seine Bridges", year=1944, date="1944-05-10",
         sides=[dict(side="Allies", start_airfield="northolt", aircraft=["p47", "p51", "typhoon", "b26"]),
                dict(side="Axis", start_airfield="abbeville_drucat", aircraft=["fw190", "bf109"])],
         objectives={"Allies": ["bridge_rouen", "bridge_oissel", "bridge_vernon", "bridge_mantes", "rail_rouen_sotteville"],
                     "Axis": ["convoy_neptune"]},
         time_of_day=12.0, weather="scattered",
         brief="Spring 1944. Cut the Seine bridges and rail yards to isolate Normandy from the German reinforcements. Strafe trains and convoys along the valley. (Axis: keep the bridges open.)"),
]

def tag(rec):
    rec["in_bounds"] = (LAT_MIN <= rec["lat"] <= LAT_MAX) and (LON_MIN <= rec["lon"] <= LON_MAX)
    return rec

# --- Midlands (map extended north to 53.0N)
AIRFIELDS += [("castle_bromwich", "Castle Bromwich", "RAF", 52.5122, -1.7728, 50, 1300),
              ("hucknall", "Hucknall", "RAF", 53.0136, -1.2292, 80, 1200),
              ("bruntingthorpe", "Bruntingthorpe", "RAF", 52.4903, -1.1264, 60, 1900)]
CITIES += [("birmingham", "Birmingham", 52.4862, -1.8904, 5, "Bull Ring; Rotunda"),
           ("coventry", "Coventry", 52.4068, -1.5197, 4, "Cathedral"),
           ("leicester", "Leicester", 52.6369, -1.1398, 4, ""),
           ("derby", "Derby", 52.9225, -1.4746, 3, "Rolls-Royce works")]
t("factory_castle_bromwich_spitfire", "Castle Bromwich Spitfire Factory", "factory", 52.5110, -1.7790, "Allies")
t("factory_rolls_royce_derby", "Rolls-Royce Derby Works", "factory", 52.9060, -1.4560, "Allies")
t("factory_coventry_ordnance", "Coventry Ordnance Works", "factory", 52.4050, -1.5200, "Allies")
t("rail_birmingham_new_street", "Birmingham New Street Yards", "rail_yard", 52.4778, -1.8985, "Allies")


# --- Low Countries, Rhineland and Midlands: real airfields, cities and industry (approximate real coordinates)
AIRFIELDS += [
    ("brussels_melsbroek", "Brussels-Melsbroek", "Luftwaffe", 50.9014, 4.4842, 70, 2000),
    ("grimbergen", "Grimbergen", "Luftwaffe", 50.9400, 4.3800, 90, 1200),
    ("chievres", "Chievres", "Luftwaffe", 50.5758, 3.8311, 100, 2500),
    ("st_trond", "St. Trond (Sint-Truiden)", "Luftwaffe", 50.7919, 5.1931, 90, 2000),
    ("florennes", "Florennes", "Luftwaffe", 50.2433, 4.6458, 60, 2500),
    ("le_culot", "Le Culot (Beauvechain)", "Luftwaffe", 50.7586, 4.7683, 70, 1500),
    ("diest", "Diest-Schaffen", "Luftwaffe", 50.9967, 5.0750, 90, 1300),
    ("asch", "Asch (Genk)", "Luftwaffe", 50.9697, 5.5917, 90, 1300),
    ("woensdrecht", "Woensdrecht", "Luftwaffe", 51.4491, 4.3425, 70, 2200),
    ("gilze_rijen", "Gilze-Rijen", "Luftwaffe", 51.5678, 4.9319, 100, 2300),
    ("eindhoven", "Eindhoven", "Luftwaffe", 51.4501, 5.3745, 220, 2000),
    ("volkel", "Volkel", "Luftwaffe", 51.6564, 5.7075, 70, 2400),
    ("venlo", "Venlo", "Luftwaffe", 51.3500, 6.1200, 90, 1800),
    ("deelen", "Deelen", "Luftwaffe", 52.0603, 5.8738, 80, 2000),
    ("soesterberg", "Soesterberg", "Luftwaffe", 52.1269, 5.2761, 70, 1800),
    ("schiphol", "Schiphol", "Luftwaffe", 52.3081, 4.7642, 90, 2000),
    ("ypenburg", "Ypenburg", "Luftwaffe", 52.0425, 4.3578, 40, 1500),
    ("valkenburg", "Valkenburg", "Luftwaffe", 52.1664, 4.4203, 80, 1500),
    ("rotterdam_waalhaven", "Rotterdam-Waalhaven", "Luftwaffe", 51.8950, 4.4370, 60, 1300),
    ("twente", "Twente", "Luftwaffe", 52.2756, 6.8742, 70, 2400),
    ("hopsten", "Hopsten", "Luftwaffe", 52.3356, 7.5444, 90, 2000),
    ("rheine", "Rheine", "Luftwaffe", 52.2900, 7.3830, 100, 1800),
    ("essen_mulheim", "Essen-Mulheim", "Luftwaffe", 51.4025, 6.9372, 90, 1300),
    ("dusseldorf_lohausen", "Dusseldorf-Lohausen", "Luftwaffe", 51.2895, 6.7668, 50, 2200),
    ("koln_butzweilerhof", "Koln-Butzweilerhof", "Luftwaffe", 50.9867, 6.8997, 100, 1500),
    ("koln_wahn", "Koln-Wahn", "Luftwaffe", 50.8658, 7.1428, 70, 2400),
    ("bonn_hangelar", "Bonn-Hangelar", "Luftwaffe", 50.7683, 7.1631, 100, 1200),
    ("aachen_merzbruck", "Aachen-Merzbruck", "Luftwaffe", 50.8236, 6.1861, 100, 1300),
    ("frankfurt_rhein_main", "Frankfurt Rhein-Main", "Luftwaffe", 50.0333, 8.5706, 70, 2500),
    ("wiesbaden_erbenheim", "Wiesbaden-Erbenheim", "Luftwaffe", 50.0500, 8.3250, 80, 2000),
    ("gutersloh", "Gutersloh", "Luftwaffe", 51.9228, 8.3064, 90, 2000),
    ("wittering", "Wittering", "RAF", 52.6126, -0.4764, 70, 1800),
    ("cottesmore", "Cottesmore", "RAF", 52.7367, -0.6486, 40, 1700),
    ("cosford", "Cosford", "RAF", 52.6400, -2.3056, 60, 1300),
    ("gaydon", "Gaydon", "RAF", 52.1989, -1.4747, 20, 1700),
    ("silverstone", "Silverstone", "RAF", 52.0719, -1.0222, 70, 1500),
    ("bicester", "Bicester", "RAF", 51.9167, -1.1333, 70, 1200),
    ("benson", "Benson", "RAF", 51.6164, -1.0975, 70, 1700),
    ("abingdon", "Abingdon", "RAF", 51.6900, -1.3167, 80, 1500),
    ("brize_norton", "Brize Norton", "RAF", 51.7500, -1.5833, 90, 2000),
    ("lyneham", "Lyneham", "RAF", 51.5047, -1.9950, 70, 1700),
    ("cranfield", "Cranfield", "RAF", 52.0722, -0.6167, 80, 1400),
    ("tempsford", "Tempsford", "RAF", 52.1300, -0.2500, 80, 1700),
]
CITIES += [
    ("brussels", "Brussels", 50.8503, 4.3517, 5, "Atomium; Grand Place"),
    ("ghent", "Ghent", 51.0543, 3.7174, 3, "Gravensteen"),
    ("bruges", "Bruges", 51.2093, 3.2247, 3, "Belfry"),
    ("leuven", "Leuven", 50.8798, 4.7005, 2, None),
    ("liege", "Liege", 50.6326, 5.5797, 4, "Meuse bridges"),
    ("namur", "Namur", 50.4674, 4.8720, 3, "Citadel"),
    ("charleroi", "Charleroi", 50.4108, 4.4446, 3, None),
    ("mons", "Mons", 50.4542, 3.9523, 2, None),
    ("maastricht", "Maastricht", 50.8514, 5.6909, 3, None),
    ("eindhoven_city", "Eindhoven", 51.4416, 5.4697, 3, "Philips works"),
    ("rotterdam", "Rotterdam", 51.9244, 4.4777, 5, "Maas harbour"),
    ("the_hague", "The Hague", 52.0705, 4.3007, 4, None),
    ("amsterdam", "Amsterdam", 52.3676, 4.9041, 5, "Canal belt"),
    ("utrecht", "Utrecht", 52.0907, 5.1214, 3, "Dom Tower"),
    ("arnhem", "Arnhem", 51.9851, 5.8987, 3, "Rhine bridge"),
    ("nijmegen", "Nijmegen", 51.8126, 5.8372, 3, "Waal bridge"),
    ("breda", "Breda", 51.5719, 4.7683, 3, None),
    ("tilburg", "Tilburg", 51.5606, 5.0919, 3, None),
    ("den_bosch", "'s-Hertogenbosch", 51.6978, 5.3037, 3, None),
    ("venlo_city", "Venlo", 51.3704, 6.1724, 2, None),
    ("aachen", "Aachen", 50.7753, 6.0839, 4, "Cathedral"),
    ("cologne", "Cologne", 50.9375, 6.9603, 5, "Cathedral; Rhine bridges"),
    ("bonn", "Bonn", 50.7374, 7.0982, 3, None),
    ("dusseldorf", "Dusseldorf", 51.2277, 6.7735, 4, None),
    ("duisburg", "Duisburg", 51.4344, 6.7623, 4, "Inland port"),
    ("essen", "Essen", 51.4556, 7.0116, 4, "Krupp works"),
    ("dortmund", "Dortmund", 51.5136, 7.4653, 4, None),
    ("munster", "Munster", 51.9607, 7.6261, 3, None),
    ("osnabruck", "Osnabruck", 52.2799, 8.0472, 3, None),
    ("bielefeld", "Bielefeld", 52.0302, 8.5325, 3, None),
    ("paderborn", "Paderborn", 51.7189, 8.7575, 2, None),
    ("frankfurt", "Frankfurt", 50.1109, 8.6821, 5, "Main bridges"),
    ("wiesbaden", "Wiesbaden", 50.0782, 8.2397, 3, None),
    ("mainz", "Mainz", 49.9929, 8.2473, 3, None),
    ("koblenz", "Koblenz", 50.3569, 7.5890, 3, "Deutsches Eck"),
    ("wolverhampton", "Wolverhampton", 52.5870, -2.1288, 3, None),
    ("nottingham", "Nottingham", 52.9548, -1.1581, 4, None),
    ("stoke", "Stoke-on-Trent", 53.0027, -2.1794, 3, None),
    ("northampton", "Northampton", 52.2405, -0.9027, 2, None),
    ("gloucester", "Gloucester", 51.8642, -2.2380, 2, "Cathedral"),
    ("worcester", "Worcester", 52.1920, -2.2216, 2, None),
    ("bristol", "Bristol", 51.4545, -2.5879, 4, "Clifton Suspension Bridge"),
    ("cardiff", "Cardiff", 51.4816, -3.1791, 3, None),
]
# Axis-owned industry (targets for the Allies)
t("factory_ford_cologne", "Ford-Werke Koln-Niehl", "factory", 51.0030, 6.9750, "Axis")
t("factory_krupp_essen", "Krupp Works Essen", "factory", 51.4430, 7.0000, "Axis")
t("factory_rheinmetall_dusseldorf", "Rheinmetall Dusseldorf-Derendorf", "factory", 51.2400, 6.7900, "Axis")
t("factory_scholven_oil", "Scholven Hydrogenation Plant (synthetic oil)", "factory", 51.5970, 7.0400, "Axis")
t("factory_huls_marl", "Chemische Werke Huls, Marl", "factory", 51.6600, 7.1000, "Axis")
t("factory_hoesch_dortmund", "Hoesch Steelworks Dortmund", "factory", 51.5000, 7.4800, "Axis")
t("factory_bayer_leverkusen", "Bayer Leverkusen Chemical Works", "factory", 51.0300, 6.9800, "Axis")
t("factory_opel_russelsheim", "Opel Works Russelsheim", "factory", 49.9900, 8.4150, "Axis")
t("factory_philips_eindhoven", "Philips Works Eindhoven", "factory", 51.4400, 5.4700, "Axis")
t("factory_fokker_amsterdam", "Fokker Works Amsterdam-Noord", "factory", 52.4000, 4.8400, "Axis")
t("factory_cockerill_seraing", "Cockerill Steelworks Seraing", "factory", 50.5900, 5.5050, "Axis")
t("factory_fn_herstal", "FN Herstal Arms Works", "factory", 50.6700, 5.6300, "Axis")
t("rail_cologne_gremberg", "Cologne-Gremberg Marshalling Yard", "rail_yard", 50.9140, 7.0100, "Axis")
t("rail_hamm", "Hamm Marshalling Yard", "rail_yard", 51.6720, 7.8200, "Axis")
t("rail_hagen", "Hagen-Vorhalle Yard", "rail_yard", 51.3600, 7.4600, "Axis")
t("rail_munster", "Munster Rail Junction", "rail_yard", 51.9570, 7.6330, "Axis")
t("rail_osnabruck", "Osnabruck Rail Yards", "rail_yard", 52.2700, 8.0600, "Axis")
t("rail_koblenz_lutzel", "Koblenz-Lutzel Yard", "rail_yard", 50.3750, 7.5950, "Axis")
t("rail_liege_kinkempois", "Liege-Kinkempois Yard", "rail_yard", 50.6050, 5.5900, "Axis")
t("rail_monceau", "Monceau-sur-Sambre Yard", "rail_yard", 50.4100, 4.4000, "Axis")
t("rail_utrecht", "Utrecht Rail Junction", "rail_yard", 52.0890, 5.1100, "Axis")
t("bridge_nijmegen", "Nijmegen Waal Bridge", "bridge", 51.8470, 5.8560, "Axis")
t("bridge_arnhem", "Arnhem Rhine Bridge", "bridge", 51.9740, 5.9070, "Axis")
t("bridge_grave", "Grave Maas Bridge", "bridge", 51.7650, 5.7400, "Axis")
t("bridge_remagen", "Ludendorff Bridge, Remagen", "bridge", 50.5680, 7.2330, "Axis")
t("bridge_wesel", "Wesel Rhine Rail Bridge", "bridge", 51.6600, 6.6100, "Axis")
t("bridge_moerdijk", "Moerdijk Bridges", "bridge", 51.7000, 4.5900, "Axis")
t("bridge_hohenzollern", "Hohenzollern Bridge Cologne", "bridge", 50.9410, 6.9650, "Axis")
t("bridge_maastricht", "Maastricht Maas Bridges", "bridge", 50.8480, 5.6900, "Axis")
t("port_rotterdam", "Rotterdam Harbour", "port", 51.9500, 4.1400, "Axis")
t("port_amsterdam", "Amsterdam Harbour", "port", 52.3900, 4.8000, "Axis")
t("port_ghent", "Ghent Canal Docks", "port", 51.1000, 3.7900, "Axis")
t("port_duisburg", "Duisburg-Ruhrort Inland Port", "port", 51.4500, 6.7300, "Axis")
t("port_flushing", "Flushing (Vlissingen) Docks", "port", 51.4430, 3.5800, "Axis")
t("port_ijmuiden", "IJmuiden Harbour", "port", 52.4600, 4.6100, "Axis")
# Allied-owned industry (targets for the Axis)
t("factory_austin_longbridge", "Austin Longbridge Works", "factory", 52.3930, -1.9830, "Allies")
t("factory_dunlop_birmingham", "Fort Dunlop, Birmingham", "factory", 52.5250, -1.8200, "Allies")
t("factory_bsa_small_heath", "BSA Small Heath Works", "factory", 52.4600, -1.8500, "Allies")
t("factory_morris_cowley", "Morris Motors Cowley", "factory", 51.7300, -1.2000, "Allies")
t("factory_gloster_hucclecote", "Gloster Aircraft Hucclecote", "factory", 51.8400, -2.2000, "Allies")
t("factory_bristol_filton", "Bristol Aeroplane Co., Filton", "factory", 51.5200, -2.5900, "Allies")
t("port_bristol", "Bristol Avonmouth Docks", "port", 51.5000, -2.7000, "Allies")
t("port_cardiff", "Cardiff Docks", "port", 51.4600, -3.1600, "Allies")
t("port_newport", "Newport Docks", "port", 51.5500, -2.9800, "Allies")
t("port_swansea", "Swansea Docks", "port", 51.6150, -3.9300, "Allies")
t("rail_swindon", "Swindon Rail Works", "rail_yard", 51.5650, -1.7800, "Allies")
t("rail_derby_midland", "Derby Midland Railway Works", "rail_yard", 52.9160, -1.4630, "Allies")


# Sea convoy routes (the planner's "boat strike" scenario picks targets flagged naval)
t("convoy_boulogne_calais", "Axis Coastal Convoy Boulogne-Calais", "convoy_route", 50.7400, 1.5000, "Axis",
  path=[[50.7400, 1.5000], [50.9000, 1.6000], [51.0200, 1.9000]])
t("convoy_ijmuiden_scheldt", "Axis Coastal Convoy IJmuiden-Scheldt", "convoy_route", 52.5000, 4.4000, "Axis",
  path=[[52.5000, 4.4000], [52.1000, 3.9000], [51.8000, 3.5000], [51.4500, 3.3000]])
t("convoy_cherbourg_lehavre", "Axis Coastal Convoy Cherbourg-Le Havre", "convoy_route", 49.7800, -1.4000, "Axis",
  path=[[49.7800, -1.4000], [49.6200, -0.8000], [49.5500, -0.2000], [49.5800, 0.0000]])
t("convoy_solent_channel", "Allied Convoy Spithead-Lyme Bay", "convoy_route", 50.7000, -1.0500, "Allies",
  path=[[50.7000, -1.0500], [50.5500, -1.4000], [50.4000, -2.0000]])
t("convoy_east_coast", "Allied East Coast Convoy", "convoy_route", 51.6000, 1.7500, "Allies",
  path=[[51.6000, 1.7500], [51.3000, 2.0000], [51.1000, 1.9500]])
NAVAL_IDS = {"convoy_neptune", "convoy_dunkirk_evac", "convoy_antwerp_ostend", "convoy_thames_dover", "convoy_boulogne_calais",
             "convoy_ijmuiden_scheldt", "convoy_cherbourg_lehavre", "convoy_solent_channel", "convoy_east_coast"}


LIBERATED = {   # airfield id -> ISO date the Allies took it (used from that date on: Allied side, no Luftwaffe flak)
    "chievres": "1944-09-02", "merville": "1944-09-02", "abbeville_drucat": "1944-09-02", "lille_nord": "1944-09-03",
    "brussels_evere": "1944-09-03", "brussels_melsbroek": "1944-09-03", "grimbergen": "1944-09-03", "le_culot": "1944-09-03",
    "florennes": "1944-09-03", "antwerp_deurne": "1944-09-04", "diest": "1944-09-04", "saint_omer": "1944-09-04",
    "st_trond": "1944-09-08", "asch": "1944-09-10", "eindhoven": "1944-09-18", "volkel": "1944-09-18", "cap_gris_nez": "1944-09-29",
    "calais_marck": "1944-10-01", "gilze_rijen": "1944-10-28", "woensdrecht": "1944-11-02", "caen_carpiquet": "1944-07-09",
    "cherbourg_maupertus": "1944-06-27",
}


def _dedupe():
    for lst in (AIRFIELDS, CITIES):
        seen = set()
        lst[:] = [r for r in lst if not (r[0] in seen or seen.add(r[0]))]
    seen = set()
    T[:] = [r for r in T if not (r["id"] in seen or seen.add(r["id"]))]
    for r in T:
        if r["id"] in NAVAL_IDS:
            r["naval"] = True


def main():
    _dedupe()
    airfields = [tag(dict(id=a[0], name=a[1], side=a[2], lat=a[3], lon=a[4], heading_deg=a[5], runway_len_m=a[6]))
                 for a in AIRFIELDS]
    for a in airfields:
        if a["id"] in LIBERATED:
            a["liberated"] = LIBERATED[a["id"]]
    cities = []
    for c in CITIES:
        d = dict(id=c[0], name=c[1], lat=c[2], lon=c[3], size=c[4])
        if c[5]:
            d["landmark"] = c[5]
        cities.append(tag(d))
    features = [tag(dict(id=f[0], name=f[1], type=f[2], lat=f[3], lon=f[4], radius_m=f[5])) for f in FEATURES]
    targets = [tag(dict(x)) for x in T]
    out = dict(airfields=airfields, cities=cities, features=features, targets=targets)
    os.makedirs(os.path.join(ROOT, "data"), exist_ok=True)
    with open(os.path.join(ROOT, "data", "locations.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    # drop objective ids that are not real targets (e.g. placeholder), keep data consistent
    tids = {x["id"] for x in targets}
    for m in MISSIONS:
        for side, objs in m["objectives"].items():
            m["objectives"][side] = [o for o in objs if o in tids]
    with open(os.path.join(ROOT, "data", "missions_seed.json"), "w", encoding="utf-8") as f:
        json.dump(dict(missions=MISSIONS), f, indent=1, ensure_ascii=False)
    print("airfields", len(airfields), "cities", len(cities), "features", len(features),
          "targets", len(targets), "missions", len(MISSIONS))

if __name__ == "__main__":
    main()

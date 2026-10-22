"""Adds original (author-written) missions to data/missions.json. Idempotent."""
import json, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
P = ROOT / "data" / "missions.json"
raw = P.read_bytes().decode("utf-8")
data = json.loads(raw)

def amb(ac, n, lat, lon, alt, km=25, label="Interceptors"):
    return {"kind": "ambush", "hostile": True, "aircraft": ac, "count": n,
            "lat": lat, "lon": lon, "alt_m": alt, "trigger_km": km, "label": label}
def raid(ac, n, lat, lon, alt, km=20, label="Bomber stream"):
    return {"kind": "raid", "hostile": True, "aircraft": ac, "count": n,
            "lat": lat, "lon": lon, "alt_m": alt, "trigger_km": km, "label": label}

def M(id, name, year, date, tod, wx, side, af, ac, obj, role, mode, brief, tl, waves, diff, events, protect=None):
    other = "Axis" if side == "Allies" else "Allies"
    return {"id": id, "name": "◆ " + name, "year": year, "date": date,
            "sides": [{"side": side, "start_airfield": af, "aircraft": ac}],
            "objectives": {side: obj} if obj else {}, "time_of_day": tod, "weather": wx,
            "brief": brief, "roles": {side: role}, "protect": {side: protect} if protect else {},
            "time_limit": tl, "waves": waves, "difficulty_hint": diff,
            "modes": {side: mode}, "events": events}

new = [
 M("op_kent_dawn_patrol","Dawn Patrol over the Weald",1940,"1940-09-07",6.0,"fog","Allies","kenley",["hurricane","spitfire"],["radar_pevensey_ch"],"defend","defend",
   "Mist lies over the Weald as Pevensey reports plots building over the Channel. Climb out of Kenley and meet the first wave before it reaches the coast.",1500,3,0.45,[amb("bf109",6,50.95,0.9,4500,label="Fighter screen"),raid("he111",8,50.85,0.6,4200)],["radar_pevensey_ch"]),
 M("op_solent_watch","Solent Watch",1940,"1940-08-16",13.0,"clear","Allies","tangmere",["spitfire","hurricane"],["port_portsmouth"],"defend","defend",
   "Ju 87s are diving on the Portsmouth approaches. Get above them from Tangmere and keep the dockyard intact.",1400,3,0.5,[amb("ju87",8,50.70,-1.05,2800,label="Stuka formation"),amb("bf109",6,50.60,-1.00,4800,label="Escort")],["port_portsmouth"]),
 M("op_peewit_convoy","Convoy Peewit Cover",1940,"1940-07-25",11.0,"scattered","Allies","hawkinge",["spitfire","hurricane"],["convoy_thames_dover"],"defend","defend",
   "The Channel convoy is steaming past Dover with E-boats and Stukas in the area. Protect the ships from Hawkinge.",1500,3,0.55,[amb("ju87",8,51.15,1.55,2500,label="Stukas on the convoy"),amb("bf110",6,51.10,1.80,4200,label="Zerstorer escort")],["convoy_thames_dover"]),
 M("op_thames_night","Night Over the Estuary",1941,"1941-03-19",23.0,"clear","Allies","hornchurch",["hurricane"],["oil_thameshaven"],"defend","defend",
   "A night raid is heading up the Thames for the oil depots at Thameshaven. Find the bombers by their engine glow and break them up.",1400,3,0.6,[raid("he111",8,51.70,1.20,3500),raid("ju88",6,51.60,0.95,3800)],["oil_thameshaven"]),
 M("op_east_coast_sweep","East Coast Sweep",1941,"1941-06-12",10.0,"scattered","Allies","duxford",["spitfire"],[],"sweep","dogfight",
   "Fighter Command wants the sky cleared off the Suffolk coast. Sweep out from Duxford and engage whatever flies.",1300,3,0.5,[amb("bf109",8,52.00,1.90,5200,label="Fighter patrol"),amb("bf109",6,51.80,2.10,4500)]),
 M("op_ruhr_steel","Steel for the Ruhr",1944,"1944-10-14",11.0,"clear","Allies","rh_af_melsbroek",["b26"],["factory_krupp_essen"],"strike","bombing",
   "A medium-bomber raid on the Essen works, flown in daylight with fighter cover that may not stay with you the whole way.",4500,3,0.6,[amb("fw190",8,51.20,6.30,5500,label="Defending fighters"),amb("bf109",6,51.40,6.80,5500)]),
 M("op_marshalling_hamm","Hamm Marshalling Yard",1944,"1944-11-02",10.0,"overcast","Allies","rh_af_asch",["b25"],["rail_hamm"],"strike","bombing",
   "Break the main rail artery feeding the front. Cloud helps on the approach and hurts on the run-in.",4500,3,0.6,[amb("bf109",8,51.50,7.20,5200),raid("ju88",2,51.55,7.40,4500,label="Interceptor wave")]),
 M("op_oil_scholven","Scholven Oil",1944,"1944-12-11",12.0,"scattered","Allies","rh_af_florennes",["b26"],["factory_scholven_oil"],"strike","bombing",
   "Synthetic fuel keeps the Luftwaffe flying. Hit the Scholven plant and return before the fighters regroup.",5400,3,0.65,[amb("fw190",8,51.50,6.90,5000),amb("me262",2,51.60,7.10,6500,label="Jet interceptors")]),
 M("op_waal_crossing","Waal Crossing",1944,"1944-09-20",13.5,"clear","Allies","rh_af_helmond",["typhoon"],["bridge_nijmegen"],"strike","ground_attack",
   "Suppress the defenders on the approaches to the Waal bridge so the ground column can cross.",1700,3,0.55,[amb("fw190",6,51.85,5.80,2200),amb("bf109",4,51.90,5.90,3000)]),
 M("op_scheldt_barges","Scheldt Barges",1944,"1944-10-30",9.0,"overcast","Allies","rh_af_deurne",["typhoon","tempest"],["convoy_antwerp_ostend"],"strike","ground_attack",
   "The enemy still moves supplies by water around the Scheldt. Rocket and cannon the barge traffic at low level.",1600,3,0.55,[amb("bf109",6,51.40,3.80,1800,label="Fighter cover")]),
 M("op_venlo_flak","Venlo Flak Belt",1944,"1944-11-23",14.0,"scattered","Allies","rh_af_schijndel",["p47"],["rh_battery_objective_near_venlo"],"strike","ground_attack",
   "Dive-bomb the flak belt at Venlo and strafe the guns that survive.",1500,3,0.5,[amb("fw190",6,51.35,6.10,2500)]),
 M("op_lines_of_supply","Lines of Supply",1944,"1944-12-02",8.5,"fog","Allies","rh_af_evere",["p51","p47"],["rh_convoy_route_supply_train_near_spa"],"strike","ground_attack",
   "Dawn fog hides the supply trains. Find them on the rails near Spa before the haze lifts.",2400,3,0.5,[amb("bf109",6,50.50,5.90,2500)]),
 M("op_schiphol_sweep","Schiphol Sweep",1944,"1944-10-05",15.0,"clear","Allies","rh_af_grimbergen",["spitfire","tempest"],[],"sweep","dogfight",
   "A free-ranging sweep across Holland to pull the Luftwaffe up where you can fight it.",1400,3,0.55,[amb("fw190",8,52.20,4.80,4500),amb("bf109",6,52.00,5.20,5000)]),
 M("op_axis_coast_raid","Coastal Raid on Dover",1940,"1940-08-12",8.5,"clear","Axis","calais_marck",["ju87","bf109"],["radar_dover_ch","port_dover"],"strike","bombing",
   "Strike the radar at Dover and the harbour behind it. The RAF will rise to meet you.",1400,4,0.6,[amb("hurricane",8,51.12,1.45,4500),amb("spitfire",6,51.20,1.30,5000)]),
 M("op_axis_thames_dusk","Dusk on the Thames",1940,"1940-09-07",18.0,"scattered","Axis","cap_gris_nez",["he111","ju88"],["port_royal_docks"],"strike","bombing",
   "A long run up the estuary to the Royal Docks as the light fails. Fighters will be waiting.",3600,4,0.7,[amb("spitfire",8,51.40,0.60,5000),amb("hurricane",8,51.45,0.30,4200)]),
 M("op_axis_bridge_defence","Hold the Bridges",1944,"1944-09-21",10.0,"clear","Axis","rh_af_mill",["fw190","bf109"],["bridge_grave"],"defend","defend",
   "Allied fighter-bombers are working over the Maas crossings. Stop them.",1500,3,0.6,[amb("typhoon",8,51.75,5.80,2000,label="Fighter-bombers"),amb("spitfire",6,51.85,5.70,4500)],["bridge_grave"]),
 M("op_axis_jet_hunt","Jet Hunt",1945,"1945-03-03",12.0,"scattered","Axis","rh_af_hopsten",["me262"],[],"sweep","dogfight",
   "Use the speed advantage to slash through the escorts and pick off bombers.",1300,3,0.7,[raid("b26",8,52.10,6.20,5500,label="Medium bombers"),amb("p51",8,52.00,6.10,6000,label="Escort")]),
]

have = {m["id"] for m in data["missions"]}
for m in new:
    if m["id"] not in have:
        data["missions"].append(m)
out = json.dumps(data, indent=1, ensure_ascii=True).replace("\n", "\r\n")
P.write_bytes(out.encode("utf-8"))
print("missions:", len(data["missions"]))

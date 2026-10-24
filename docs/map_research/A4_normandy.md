# A4 Normandy after D-Day

## Survey
- `arromanches_mulberry` was a static landmark (8 boxes) shown at every date: replaced.
- Gooseberry blockship rows in sea_defences_1940.json were undated: now from 1944-06-07.
- Beach defences (BeachKit) exist; nothing for the landings themselves.

## Research
Wikipedia - Mulberry harbour (Phoenix caissons, 115 sunk for Mulberry B by 15 June; Whale roadways on beetles, 80 ft
spans; Spud pierheads; Bombardons outside; Mulberry A wrecked by the 19-22 June storm, 21 of 28 Phoenixes destroyed);
Operation Tonga / Mallard / Deadstick (LZ N north of Ranville east of the Orne, LZ W east of Saint-Aubin-d'Arquenay,
LZ X/Y at the bridges); Operations Chicago, Elmira, Keokuk, Galveston, Hackensack (LZ E Hiesville, LZ W south of
Sainte-Mere-Eglise); Battle of La Fiere and Battle of Carentan (Merderet and Douve inundations); the Dives valley
inundations; Utah / Omaha / Gold / Juno / Sword Beach; Operation Goodwood, Epsom, Jupiter, Windsor, Totalize; Battle of
Villers-Bocage. The well-known RAF oblique of Port Winston (the Phoenix arc and three roadways to the pierheads) was the
layout reference.

## Built
- MulberryKit: Mulberry B (Phoenix arc with Bofors platforms, blockships, three Whale roadways on beetles to Spud
  pierheads, Bombardons 6-19 June), Mulberry A (intact to 19 June, then storm-wrecked: broken caissons and roadway).
- GliderKit + data/airborne_landings.json: Horsa / Hamilcar / Waco in three states (intact, tail off for unloading,
  wrecked), with invasion stripes; parachutes on the dropping zones for two days.
- WarGround + data/war_ground.json: floods (terrain kind 5: water up to a level with the hedge lines showing),
  battlefields (crater fields, burnt-out tanks and lorries), invasion beaches (terrain kind 6 churn, wrecked LCTs at the
  waterline, drowned tanks, lorries).

## Cost
Floods and churn are shader zones (32 slots now, ordered by edge distance). Wreck sites: a few MultiMeshes each.

# A2 Bomb damage that builds up with the date

## Survey
- No damage of any kind on the map before this task. Coventry cathedral is modelled as a ruin (`coventry_cathedral`,
  landmarks.gd) at all dates. Towns come from two builders: `Scatter.make_town` (dense cores, `_build_city`, main
  thread) and the land-cover tiles (`Scatter.tile_landcover_data`, worker thread). Both produce per-variant lists of
  house transforms over a unit-box house mesh.

## Research
Sources (dates, extent): Wikipedia - The Blitz; Second Great Fire of London; Surrey Commercial Docks; Coventry Blitz;
Birmingham, Bristol, Southampton, Portsmouth, Plymouth Blitz; Baedeker Blitz; Rotterdam Blitz; Bombing of Cologne in
World War II; Battle of the Ruhr; Bombing of Wuppertal; Emmerich am Rhein (7 Oct 1944, ~91% destroyed, checked);
Juelich (16 Nov 1944, ~97%, checked, coords 50.922 N 6.358 E match); Dueren; Kleve; Wesel; Koblenz; Bonn; Mainz;
Bombing of Frankfurt am Main; Bombing of Darmstadt; Battle for Caen; Saint-Lo; Bombing of Le Havre in World War II;
Lisieux; Aunay-sur-Odon; Battle of Villers-Bocage; Rouen; Operation Wellhit; Siege of Calais; Battle of Arnhem;
Bombing of Nijmegen. Each data row carries its own source.

What the photographs show from the air (LCC bomb damage maps, the RAF/USAAF obliques of Cologne, Wesel, Caen):
- districts of roofless shells in otherwise intact street rows: the streets stay, the roofs go; walls stand to
  first-floor height with burnt-out window holes and blackened tops;
- cleared plots where the rubble was pushed up, pale grey-brown;
- crater fields, densest round docks, rail yards and bridges; scorch where whole blocks burned (London docks 7 Sep
  1940, Coventry 14 Nov 1940, Rotterdam 14 May 1940);
- the worst-hit towns of 1944-45 (Saint-Lo, Dueren, Juelich, Wesel, Emmerich) were almost entirely shells and rubble.

## Design and cost
- `data/war_damage.json`: 55 areas with centre, radius, peak level, first raid and the date the damage was complete.
- `WarDamage.refresh()` turns them into live areas for the EraClock date (main thread, at build).
- Houses: in damaged areas a share (level x 0.68) become a gutted shell, a further share (to level x 0.86) is cleared.
  Same instance transforms, two shared shell meshes (`ruin0`, `ruin1`, ~8 surfaces merged to 3 by material) per tile:
  +2 draw calls in a damaged tile, fewer houses overall. Zero cost outside damaged areas.
- Terrain: one zone of kind 4 per area (strength in the fractional part): rubble colour, scorch blotches, crater pits
  with pale spoil rims, one crater test per 30 m cell. Shader cost: a few ALU ops inside the existing zone loop.
- The church in a tile is skipped when the damage at its spot exceeds 0.6.

## Not modelled
- Individual famous ruins beyond Coventry cathedral; fire-watch smoke (left for C3's capped emitter pool).

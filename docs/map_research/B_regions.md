# B1-B6 Regional farming shapes and seasons

## B1 Region bake
`data/regions_1940.json` (14 hand-drawn polygons, lat/lon) is baked by `tools/bake_regions.py` into
`data/heightmap/region_types.png`: RGBA 1024 x 512 over the WorldCoords bounds (same rect as `region_color.png`), one
channel per farming landscape, blurred ~1.6 px (a 2-3 km blend between landscapes). `RegionMap` (scripts/ground/
region_map.gd) loads the same PNG for the CPU side so the hedges the scatter places agree with the lattice the shader
paints. Cost: one extra texture sample per terrain pixel.

## B2 Bocage
Wikipedia - Bocage; Battle for the bocage / Hedgerow fighting (Normandy 1944: small irregular fields, 1-2 ha, behind
banked hedges with trees, sunken lanes). Region channel R covers the Cotentin, the Bessin west of Bayeux, the Suisse
Normande and the Pays d'Auge. In it the field lattice cell shrinks and gets more irregular, the hedge line is wider and
darker, and the scatter's field-edge test reports "region" so hedgerow trees line every field.

## B3 Open fields
Wikipedia - Openfield; Pays de Caux; Picardy; Plaine de Caen; Salisbury Plain. Big hedgeless strip-farmed arable on the
chalk and loess plateaux: long narrow parcels, no hedges, isolated farmsteads behind tree screens (the Caux "clos
masures"). Channel G: Caux, Vexin, Picardy, Artois, the Caen-Falaise plain, Champagne edge, the Wiltshire and Hampshire
downs. Lattice stretched into strips, hedge lines suppressed, field colours more varied (strip by strip).

## B4 Polders
Wikipedia - Polder; Zuiderzee Works (Wieringermeer drained 1930, Noordoostpolder 1942); The Fens. Long rectangular
parcels divided by straight drainage ditches, few hedges, rows of poplars / willows along the dykes and roads. Channel B:
Holland, Zeeland, the Flemish polders behind Dunkirk-Nieuwpoort, the Fens and Romney Marsh. Lattice becomes long thin
rectangles aligned to the grid, ditch lines in place of hedges; poplar rows on the field edges.

## B5 Weald
Wikipedia - Weald; Shaw (woodland). Small irregular fields with many shaws (narrow woodland strips) and copses, oak
standards in the hedges. Channel A: the High and Low Weald of Kent, Sussex and Surrey. Smaller cells than the default
English lattice, darker hedges with more trees.

## B6 Seasons
Harvest calendar for southern England and northern France in the 1940s (Wikipedia - Stook; Haystack / rick; Harvest):
corn cut late July to August and stood in stooks in the fields for one to two weeks, carted and built into ricks by the
farmyard in late August to September, threshed through the winter. Grass green through summer, browning in a dry
August; ploughed brown ground from October; bare winter fields. Implementation: one season colour shift on the field
palette (`season_center` / `season_tint` from the sortie month), stooks only in August and September, ricks from July
to March.

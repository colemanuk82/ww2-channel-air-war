# C, D Low-level life, haze and the horizon

## C1 Barges
Wikipedia - Peniche (barge) / Freycinet gauge (38.5 x 5.05 m, the standard French-Belgian canal barge since 1879);
Rhine barge / push and tow trains (a tug towing several lighters, the normal Rhine traffic before pushing took over in
the 1950s). The Low Countries' waterways carried most of their freight in the war years and the barges were regular
Typhoon and Mustang targets in 1944-45. `BargeTraffic`: at most 12 barges within 9 km of the camera on the continental
canals (lon > 1.9) and rivers longer than 20 km, sliding along the real polylines at 2.4 m/s. One merged mesh per barge.

## C2 Trains
Steam locomotives trail white exhaust (FX trail, "smoke" kind, no darkening) while within 7 km of the camera; at most
6 at once.

## C3 Industry smoke
Covered by D2 (the haze areas); chimney smoke columns already existed (v2.x industry sites).

## C4 Searchlight belt
Wikipedia - Kammhuber Line ("Himmelbett" boxes, searchlight belt in front of the night-fighter boxes across the
Netherlands and Belgium, 1941-42; the searchlights were withdrawn to the cities in late 1942). Searchlight sites every
~9 km along the belt from Groningen to Maastricht, built only for sortie dates 1941-01-01 .. 1942-12-31.

## C5 Harbours (survey only)
The ports (Dover, Folkestone, Calais, Boulogne, Dunkirk, Ostend, Le Havre, Cherbourg, Antwerp, Rotterdam) already have
quay sites, cranes and shipping from v2.x. Gaps noted for a later pass: dated harbour wrecks (Dunkirk 1940, Le Havre and
Cherbourg demolitions 1944), blockships in Zeebrugge, and E-boat pens at IJmuiden.

## D2 Industrial haze
Wikipedia - Battle of the Ruhr ("industrial haze" over the Ruhr hid the targets; Oboe was used because of it); Great
Smog of London / London fog (coal smoke). `TimeOfDay.HAZE_AREAS`: the Ruhr, London, Liege, Charleroi, Lille, Rotterdam,
Antwerp, Birmingham. While the camera is over one, fog density is raised up to 2.3x and tinted brown in daylight.
Evaluated once a second; no per-pixel cost beyond the existing fog.

## D1 Horizon, D3 Landmarks, D4 Coast
D1: checked from 6 km - the far terrain LODs (48 km) and the fog meet without a visible edge. D3: the landmark set from
v2.x plus the dated bridges (A6, A7). D4: the shallow-water foam blotches seen from altitude came from the surf band in
water.gdshader triggering over any shallow sea floor; the band now needs the depth to rise towards the shore.

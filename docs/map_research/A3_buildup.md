# A3 The 1944 invasion build-up

## Survey
Nothing for 1943-44 in southern England before this: the coast defences, airfields and camps are 1940 data.
`RoadMesh.routes_in_rect` gives the real road polylines (the data holds the main network: primary / trunk / motorway).

## Research
- Wikipedia - Operation Overlord; Operation Neptune (assault forces assembled in the south-coast harbours: Force U
  Torbay/Dartmouth/Plymouth, Force O Portland/Weymouth, Forces G/J/S Solent, Spithead, Portsmouth, Newhaven, Shoreham);
  Exercise Tiger; Mulberry harbour (Phoenixes sunk off Dungeness and Pagham/Selsey to wait, refloated after D-Day);
  the surviving embarkation hards (Lepe, Stokes Bay, Hamble, Hardway, Torquay, Brixham, Turnchapel...).
- What the photographs show: vehicles parked nose to tail on the verges for miles, often under the trees; landing
  craft moored in tight trots; the hards as pale concrete aprons with "chocolate-block" mats running into the water.

## Built (data/buildup_1944.json, BuildupKit)
- 10 marshalling areas: vehicles on the verges of the real roads within the area (lorries / Shermans / half-tracks,
  convoy runs with gaps, none in built-up areas), capped per area; 1944-04-20 .. 1944-06-10.
- 11 anchorages: LCT / LCI(L) / LST moored in rows on water deeper than ~1.5 m; 1944-05-01 .. 1944-06-05.
- 2 Phoenix parks (Selsey/Pagham, Dungeness): caissons sunk in rows in the shallows; 1944-04-20 .. 1944-06-07.
- 11 embarkation hards (from 1943-06, still there after the war).

## Cost
Per site one MultiMesh per mesh; 4 km fades (caissons and hards 9 km). Lane vehicles capped (160-320 per area).
Measured: see the commit / phase board.

## Notes
- Areas whose roads all run through built-up land (Havant / Fareham round Portsmouth) get few or no roadside vehicles
  by design.

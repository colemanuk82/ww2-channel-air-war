# de Havilland Mosquito FB VI — dimensions & station tables

Two Rolls-Royce Merlin 25 (1,635 hp each) driving three-blade de Havilland Hydromatic props.

## Published dimensions (with sources)

| Dimension | Value used | Published | Source |
|---|---|---|---|
| Length | 12.55 m | 41 ft 2 in (12.55 m) over guns | https://en.wikipedia.org/wiki/De_Havilland_Mosquito |
| Wingspan | 16.51 m | 54 ft 2 in (16.51 m) | https://en.wikipedia.org/wiki/De_Havilland_Mosquito |
| Height | 4.65 m | 15 ft 3 in (4.65 m) | https://www.canada.ca/en/air-force/services/aircraft/de-havilland-mosquito.html |
| Wing area | 41.81 m² | 454 sq ft (42.18 m²) | https://en.wikipedia.org/wiki/De_Havilland_Mosquito |
| Propeller diameter | 3.81 m | 12 ft 6 in (3.81 m), 3-blade | https://www.britmodeller.com/forums/index.php?/topic/235097025-mosquito-propeller-question/ |
| Undercarriage track | ~3.05 m (estimate) | not published in the sources consulted | — |

Note: some references quote a generic Mosquito height of 5.30 m; the 15 ft 3 in (4.65 m) Canada/RCAF figure
is used here. Length varies by mark (B.IV 12.43 m, FB.VI 12.55 m over the guns); the FB VI value is used.

## Modelled configuration

* **Two Merlins, two nacelles** at x = ±3.30 m ⇒ `Propeller`, `Propeller2`.
* **Single fin**, one-piece blown canopy (no separate nose glazing).
* Smooth wooden fuselage; **no turret** — a fast unarmed-attack type with a 4×20 mm belly cannon pack.

## Fuselage stations (y, half-width, half-height, centre-z) — metres, nose +Y

y = +6.35 (nose) → −6.20 (tail).

| y | hw | hh | cz |
|---|---|---|---|
| 6.35 | 0.16 | 0.20 | 0.05 |
| 5.80 | 0.42 | 0.46 | 0.04 |
| 4.90 | 0.55 | 0.64 | 0.02 |
| 4.30 | 0.57 | 0.70 | 0.02 |
| 3.60 | 0.57 | 0.72 | 0.02 |
| 1.00 | 0.52 | 0.66 | 0.03 |
| −2.20 | 0.38 | 0.50 | 0.08 |
| −4.80 | 0.23 | 0.31 | 0.16 |
| −6.20 | 0.04 | 0.07 | 0.22 |

## Wing planform (half-span x, chord, LE-y, LE-z, t/c) — root→tip

Span 16.51 m, area 41.8 m² (mean chord 2.53 m), ~2° dihedral.

| x | chord | LE y | LE z | t/c |
|---|---|---|---|---|
| 0.00 | 3.37 | 0.05 | 0.00 | 0.150 |
| 1.50 | 3.26 | 0.00 | 0.05 | 0.145 |
| 3.00 | 3.01 | −0.10 | 0.14 | 0.140 |
| 4.50 | 2.60 | −0.25 | 0.24 | 0.135 |
| 6.00 | 2.09 | −0.45 | 0.36 | 0.125 |
| 7.20 | 1.58 | −0.62 | 0.46 | 0.120 |
| 8.255 | 0.73 | −0.84 | 0.57 | 0.105 |

## Accuracy gate result

```
ACCURACY mosquito length 12.650/12.550 m (+0.8%) OK span 16.510/16.510 m (+0.0%) OK height 4.650/4.650 m (-0.0%) OK -> PASS
```
Tris 42,612 (budget 40,000–50,000).

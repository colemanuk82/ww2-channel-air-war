# Avro Lancaster B.I — dimensions & station tables

Four Rolls-Royce Merlin XX (1,280 hp each) driving de Havilland Hydromatic three-blade props.

## Published dimensions (with sources)

| Dimension | Value used | Published | Source |
|---|---|---|---|
| Length | 21.18 m | 69 ft 6 in (21.18 m) | https://www.canada.ca/en/air-force/services/aircraft/lancaster.html ; https://www.flugzeuginfo.net/acdata_php/acdata_lancaster_en.php |
| Wingspan | 31.09 m | 102 ft 0 in (31.09 m) | same as above |
| Height | 6.10 m | 20 ft 0 in (6.10 m) | https://www.canada.ca/en/air-force/services/aircraft/lancaster.html |
| Wing area | 120.5 m² | 1,297 sq ft (120.5 m²) | https://www.flugzeuginfo.net/acdata_php/acdata_lancaster_en.php |
| Undercarriage track | 7.24 m | 23 ft 9 in | https://bombercommandmuseumarchives.ca/lancavrospecs.html |
| Propeller diameter | 3.96 m | 13 ft 0 in (4.0 m), 3-blade | https://en.wikipedia.org/wiki/Avro_Lancaster ; https://www.avroheritagemuseum.co.uk/posters/lancaster-propeller-blades |

Note: some sources quote height 6.25 m (20 ft 6 in, https://warintheskies.org/aircraft/lancaster.html) and
5.97 m (19 ft 7 in, flugzeuginfo). 6.10 m (20 ft 0 in) is the RAF/Canada figure used here.

## Modelled configuration

* **Four Merlins in four nacelles, two per wing** (inboard x = ±6.50 m, outboard x = ±11.30 m).
  Two props per side ⇒ four propellers, named `Propeller`, `Propeller2`, `Propeller3`, `Propeller4`.
* **Twin elliptical fins + rudders** on the tailplane tips (single `Fin` object holding both).
* Huge unobstructed bomb bay (7.2 m fairing under the centre fuselage).
* Dorsal (FN.50) turret, stepped bomb-aimer nose glazing + raised flight-deck canopy.

## Fuselage stations (y, half-width, half-height, centre-z) — metres, nose +Y

y = +10.00 (nose) → −11.16 (tail); oval section, max 1.52 m wide × 2.00 m deep.

| y | hw | hh | cz |
|---|---|---|---|
| 10.00 | 0.13 | 0.16 | 0.04 |
| 9.05 | 0.45 | 0.54 | 0.02 |
| 8.40 | 0.57 | 0.68 | 0.00 |
| 7.70 | 0.65 | 0.80 | 0.00 |
| 6.30 | 0.75 | 0.98 | 0.00 |
| 5.40 | 0.76 | 1.00 | 0.00 |
| 2.80 | 0.74 | 0.98 | 0.00 |
| −0.40 | 0.64 | 0.88 | 0.02 |
| −3.60 | 0.48 | 0.70 | 0.08 |
| −6.80 | 0.29 | 0.46 | 0.16 |
| −9.20 | 0.14 | 0.25 | 0.24 |
| −11.16 | 0.018 | 0.035 | 0.26 |

## Wing planform (half-span x, chord, LE-y, LE-z, t/c) — root→tip

Span 31.09 m, area 120.5 m² (mean chord 3.876 m), dihedral ≈ 5.5°, LE swept back outboard.

| x | chord | LE y | LE z | t/c |
|---|---|---|---|---|
| 0.00 | 5.90 | 0.60 | 0.00 | 0.180 |
| 2.00 | 5.80 | 0.55 | 0.06 | 0.170 |
| 4.50 | 5.25 | 0.30 | 0.24 | 0.160 |
| 7.00 | 4.30 | −0.10 | 0.50 | 0.150 |
| 9.50 | 3.35 | −0.60 | 0.80 | 0.140 |
| 12.00 | 2.40 | −1.20 | 1.10 | 0.130 |
| 14.00 | 1.55 | −1.70 | 1.34 | 0.120 |
| 15.55 | 0.70 | −2.15 | 1.53 | 0.100 |

## Accuracy gate result

```
ACCURACY lancaster length 21.160/21.180 m (-0.1%) OK span 31.100/31.090 m (+0.0%) OK height 6.120/6.100 m (+0.3%) OK -> PASS
```
Tris 46,860 (budget 45,000–60,000). Height is the airframe height (fin top to wheel bottom); the
3.96 m prop discs stay inside it.

# Bristol Blenheim Mk IV — dimensions & station tables

Two Bristol Mercury XV nine-cylinder radials (920 hp each).

## Published dimensions (with sources)

| Dimension | Value used | Published | Source |
|---|---|---|---|
| Length | 12.98 m | 42 ft 7 in (12.98 m) | https://en.wikipedia.org/wiki/Bristol_Blenheim |
| Wingspan | 17.17 m | 56 ft 4 in (17.17 m) | https://en.wikipedia.org/wiki/Bristol_Blenheim |
| Height | 3.00 m | 9 ft 10 in (3.00 m) | https://en.wikipedia.org/wiki/Bristol_Blenheim |
| Wing area | 43.6 m² | 469 sq ft (43.6 m²) | https://www.zap16.com/2021/03/22/bristol-blenheim |
| Propeller diameter | 3.20 m | 10 ft 6 in (3.20 m), 3-blade Hamilton Standard | https://en.wikipedia.org/wiki/Bristol_Blenheim |
| Undercarriage track | ~4.80 m (estimate) | not published in the sources consulted | — |
| Airfoil | RAF-28 (18%) | https://indy-amps.weebly.com/... |

Note: one source quotes height 3.91 m (12.8 ft — https://military.cz/british/air/war/bomber/blenheim/blenheim_en.htm).
The 3.00 m figure is the standard Britain/Canada value. The 3.20 m prop disc is taller than the 3.00 m
airframe height (the Blenheim's props dominated its height), so the gate compares the **airframe** height.

## Modelled configuration

* **Two Mercuries in two nacelles** at x = ±2.55 m ⇒ `Propeller`, `Propeller2`.
* **Single fin** (small, rounded), low-mounted wing.
* The Mk IV's signature **very long stepped glazed nose** (bomb-aimer) + raised cockpit canopy.
* Dorsal power-operated turret with two guns.

## Fuselage stations (y, half-width, half-height, centre-z) — metres, nose +Y

y = +6.90 (nose) → −6.08 (tail).

| y | hw | hh | cz |
|---|---|---|---|
| 6.90 | 0.10 | 0.13 | −0.06 |
| 6.25 | 0.36 | 0.34 | −0.10 |
| 5.80 | 0.46 | 0.44 | −0.06 |
| 5.30 | 0.55 | 0.56 | 0.00 |
| 4.00 | 0.64 | 0.68 | 0.04 |
| 3.10 | 0.65 | 0.70 | 0.04 |
| 0.80 | 0.58 | 0.64 | 0.05 |
| −2.00 | 0.44 | 0.50 | 0.08 |
| −4.50 | 0.28 | 0.34 | 0.12 |
| −6.08 | 0.05 | 0.07 | 0.15 |

## Wing planform (half-span x, chord, LE-y, LE-z, t/c) — root→tip

Span 17.17 m, area 43.7 m² (mean chord 2.54 m), low-mounted, slight dihedral.

| x | chord | LE y | LE z | t/c |
|---|---|---|---|---|
| 0.00 | 3.48 | 0.10 | 0.00 | 0.160 |
| 1.50 | 3.37 | 0.05 | 0.00 | 0.150 |
| 3.00 | 3.08 | −0.05 | 0.02 | 0.140 |
| 4.50 | 2.62 | −0.20 | 0.06 | 0.135 |
| 6.00 | 2.11 | −0.40 | 0.12 | 0.125 |
| 7.20 | 1.65 | −0.60 | 0.18 | 0.115 |
| 8.585 | 0.82 | −0.88 | 0.27 | 0.100 |

## Accuracy gate result

```
ACCURACY blenheim length 12.980/12.980 m (+0.0%) OK span 17.170/17.170 m (+0.0%) OK height 3.000/3.000 m (+0.0%) OK -> PASS
```
Tris 42,140 (budget 40,000–50,000).

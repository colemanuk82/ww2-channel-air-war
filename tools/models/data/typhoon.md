# Hawker Typhoon Mk IB — researched dimensions and station tables

Model id `typhoon` · source module `tools/models/data/typhoon.py` · built by
`blender --background --python tools/models/build_all.py -- typhoon`

All geometry is authored from the published figures below. Frame: metres, origin at the CG
station, **nose toward +Y**, up +Z, right +X (the glTF export maps that onto Godot's −Z forward).

## Headline dimensions (gated at 2 %)

| Quantity | Published | Source |
|---|---|---|
| Length | 9.73 m (31 ft 11 in) | https://en.wikipedia.org/wiki/Hawker_Typhoon · https://military.cz/british/air/war/fighter/typhoon/typhoon_en.htm |
| Wingspan | 12.67 m (41 ft 7 in) | https://en.wikipedia.org/wiki/Hawker_Typhoon · https://military.cz/british/air/war/fighter/typhoon/typhoon_en.htm |
| Height | 4.52 m (14 ft 10 in), level attitude | http://migman.com/sw/european-air-war/typhoon.php · https://de.zxc.wiki/wiki/Hawker_Typhoon |
| Wing area | 25.9 m² (279 sq ft) | https://en.wikipedia.org/wiki/Hawker_Typhoon |

Height is the one figure where the references genuinely split: military.cz quotes 15.3 ft
(4.66 m) — https://military.cz/british/air/war/fighter/typhoon/typhoon_en.htm — while migman and
zxc.wiki quote 14 ft 10 in (4.52 m). The model is gated against **4.52 m**, the figure for the
aircraft in its normal level stance with one propeller blade vertical; the 4.66 m value is a
tail-down measurement. Both are recorded here so the choice is visible.

## Secondary dimensions (recorded, not gated)

| Quantity | Value | Source |
|---|---|---|
| Wing root chord | 2.86 m | derived: 25.9 m² / 12.67 m = 2.04 m mean chord; taper 2.86 → 1.24 m |
| Wing tip chord | 1.24 m (rounded tip ~0.97 m) | derived as above |
| Wing section | 1° anhedral inboard of the gear, **5.5° dihedral** outboard (inverted gull) | https://en.wikipedia.org/wiki/Hawker_Typhoon · https://aircraft.fandom.com/wiki/Hawker_Typhoon |
| Propeller | 4-blade de Havilland or Rotol constant-speed, **~3.66 m (12 ft 0 in)** — **approximate** | https://en.wikipedia.org/wiki/Hawker_Typhoon (gives only "3 or 4-bladed de Havilland or Rotol"); sources do not state the Typhoon's diameter. The Tempest's 4-blade was 14 ft, and the Tempest's *longer* gear was introduced specifically to clear a bigger prop, so the Typhoon's is modelled smaller. |
| Main-wheel track | 4.13 m (13 ft 6 3/4 in) | https://aircraft.fandom.com/wiki/Hawker_Typhoon |
| Main wheel | 0.86 m (34 × 11 in, five-spoke) | https://olddogsplanes.com/tempest.html ("the Typhoon's larger 34 by 11 inch five-spoke wheels") |
| Armament | 4 × 20 mm Hispano Mk II cannon | https://en.wikipedia.org/wiki/Hawker_Typhoon |

## Station tables actually used

**Fuselage** — `kit.tube`, 16 stations, n = 32, power 2.7 (the Typhoon's slab-sided, deep Sabre
fuselage). `NOSE = +3.55`, `TAIL = −6.18`. `(y, half-width, half-height, cz)`:

```
( 3.53, 0.13, 0.15, 0.00) ( 3.13, 0.34, 0.38, 0.00) ( 2.60, 0.46, 0.52, 0.02)
( 2.05, 0.50, 0.60, 0.04) ( 1.50, 0.52, 0.66, 0.06) ( 0.95, 0.53, 0.70, 0.08)
( 0.30, 0.53, 0.72, 0.11) (-0.35, 0.50, 0.70, 0.14) (-1.05, 0.44, 0.64, 0.18)
(-1.80, 0.36, 0.55, 0.22) (-2.55, 0.28, 0.45, 0.26) (-3.30, 0.20, 0.35, 0.29)
(-4.05, 0.14, 0.26, 0.31) (-4.80, 0.09, 0.18, 0.33) (-5.50, 0.06, 0.12, 0.34)
(-6.18, 0.035, 0.06, 0.36)
```

**Wing** — `kit.surface` half-wing, mirrored. `WING_LE = +0.95`. `(half-span x, chord, z offset,
thickness ratio)` — the z offsets carry the inverted-gull bend (inboard droop, 5.5° outboard rise):

```
(0.34, 2.86, -0.28, 0.150) (1.10, 2.61, -0.30, 0.145) (2.00, 2.31, -0.32, 0.141)
(2.70, 2.11, -0.31, 0.137) (3.40, 1.89, -0.24, 0.133) (4.30, 1.60, -0.12, 0.129)
(5.20, 1.32, +0.02, 0.124) (5.90, 1.02, +0.14, 0.121) (6.335, 0.97, +0.20, 0.118)
```

**Tailplane** — half-span 2.00 m, root chord 1.52 m → tip 0.90 m, `y = TAIL + 1.60`
(the enlarged Tempest-pattern tailplane fitted to late Typhoons).

**Fin/rudder** — `kit.fin`, root LE `FIN_LE = TAIL + 2.26` (the long root chord of 2.25 m places
the rudder trailing edge exactly on `TAIL`):

```
(0.30, 2.25, FIN_LE        , 0.11) (0.80, 2.16, FIN_LE - 0.04, 0.10)
(1.22, 1.94, FIN_LE + 0.00 , 0.095) (1.58, 1.56, FIN_LE + 0.06, 0.09)
(1.82, 1.02, FIN_LE + 0.12 , 0.085) (1.94, 0.48, FIN_LE + 0.18, 0.08)
```

**Chin radiator** — `kit.radiator("ChinRadiator", 0, NOSE − 1.30, −0.72, w 0.96, h 0.74, length 1.35)`:
the Typhoon's defining deep chin intake under the Sabre nose. Four 20 mm Hispanos sit two per wing
at x = ±1.50 and ±2.62 with barrels through the leading edge.

**Gear** — track 4.13 m (x = ±2.065), pivot at `y = WING_LE − 0.45`, `z = −0.50`; tailwheel at
`y = TAIL + 1.05`. Undercarriage leg length is solved at build time so the bbox height matches the
published figure (see `_accuracy()` in the module).

## Verified output

```
ACCURACY typhoon    length 9.73/9.73m (-0.0%) span 12.67/12.67m (+0.0%) height 4.52/4.52m (+0.0%) PASS
[model] typhoon      tris= 26220 objects=89
```

(Note: tri count from the shared `tools/models/kit.py` revision current when written.)

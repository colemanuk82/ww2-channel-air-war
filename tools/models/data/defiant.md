# Boulton Paul Defiant Mk I — researched dimensions and station tables

Model id `defiant` · source module `tools/models/data/defiant.py` · built by
`blender --background --python tools/models/build_all.py -- defiant`

All geometry is authored from the published figures below. Frame: metres, origin at the CG
station, **nose toward +Y**, up +Z, right +X (the glTF export maps that onto Godot's −Z forward).

## Headline dimensions (gated at 2 %)

| Quantity | Published | Source |
|---|---|---|
| Length | 10.77 m (35 ft 4 in) | https://ww2db.com/aircraft_spec.php?aircraft_model_id=343 |
| Wingspan | 11.99 m (39 ft 4 in) | https://ww2db.com/aircraft_spec.php?aircraft_model_id=343 |
| Height | 3.45 m (11 ft 4 in) | http://wardrawings.be/WW2/Files/2-Airplanes/Allies/3-UK/01-Fighters/BoultonPaul-Defiant/Data/Defiant-Mk1.htm |
| Wing area | 23.23 m² (250 sq ft) | https://ww2db.com/aircraft_spec.php?aircraft_model_id=343 |

Some sources quote height 3.71 m (http://theworldwars.net/weapons/entry.php?b=air&m=defiant);
3.45 m is used as it is the figure carried by the two most consistent references above.

## Secondary dimensions (recorded, not gated)

| Quantity | Value | Source |
|---|---|---|
| Wing root chord | 2.66 m | derived: 23.23 m² / 11.99 m = 1.94 m mean chord; taper 2.66 → 1.22 m |
| Wing tip chord | 1.22 m (rounded tip ~0.88 m) | derived as above |
| Dihedral | 4.0° | the Defiant wing is the Hurricane-class Hawker/Boulton Paul layout |
| Propeller | 3-blade constant-speed, **3.35 m** dia — **approximate** | Merlin III installation, same class as the Hurricane's 3.43 m Rotol (https://migflug.com/aircraft/hawker-hurricane/); no Defiant-specific diameter was found |
| Main-wheel track | ~2.36 m — **approximate** | scaled from published 3-views |
| Main wheel | 0.80 m (Dunlop 31.5 × 9.5 in) | https://ww2aircraft.net/forum/threads/tyre-id-help-please.66422/page-2 |
| Armament | 4 × .303 in Browning in a hydraulically driven dorsal turret; **no fixed forward-firing guns** | https://ww2db.com/aircraft_spec.php?aircraft_model_id=343 |

Because the Defiant carried no fixed forward armament, the `MuzzleL`/`MuzzleR` contract markers
are placed on the dorsal turret's Brownings rather than in the wings.

## Station tables actually used

**Fuselage** — `kit.tube`, 18 stations, n = 32, power 2.45. `NOSE = +3.30`, `TAIL = −7.47`
(the deeper two-seat spine that carries the turret ring). `(y, half-width, half-height, cz)`:

```
( 3.28, 0.11, 0.13, 0.00) ( 2.90, 0.31, 0.34, 0.00) ( 2.40, 0.41, 0.46, 0.02)
( 1.90, 0.45, 0.52, 0.04) ( 1.40, 0.47, 0.57, 0.06) ( 0.90, 0.48, 0.60, 0.08)
( 0.30, 0.48, 0.62, 0.10) (-0.30, 0.47, 0.62, 0.12) (-0.90, 0.45, 0.60, 0.14)
(-1.55, 0.40, 0.55, 0.17) (-2.25, 0.34, 0.47, 0.20) (-2.95, 0.27, 0.39, 0.23)
(-3.65, 0.20, 0.31, 0.26) (-4.35, 0.14, 0.24, 0.28) (-5.05, 0.09, 0.17, 0.30)
(-5.75, 0.06, 0.12, 0.31) (-6.45, 0.04, 0.08, 0.32) (-7.47, 0.03, 0.05, 0.32)
```

**Wing** — `kit.surface` half-wing, mirrored. `WING_LE = +0.85`, `Z_ROOT = −0.26`,
`z(t) = Z_ROOT + 0.42·t` (4.0° dihedral). `(half-span x, chord, thickness ratio)`:

```
(0.34, 2.66, 0.150) (0.95, 2.56, 0.145) (1.65, 2.27, 0.141) (2.40, 2.07, 0.137)
(3.20, 1.85, 0.133) (4.00, 1.64, 0.129) (4.75, 1.45, 0.124) (5.35, 0.96, 0.121)
(5.75, 0.90, 0.119) (5.995, 0.88, 0.118)
```

**Tailplane** — half-span 1.74 m, root chord 1.38 m → tip 0.80 m, `y = TAIL + 1.50`.

**Fin/rudder** — `kit.fin`, root LE `FIN_LE = TAIL + 1.90`:

```
(0.26, 1.86, FIN_LE        , 0.11) (0.68, 1.80, FIN_LE - 0.02, 0.10)
(1.04, 1.62, FIN_LE + 0.02 , 0.095) (1.34, 1.30, FIN_LE + 0.06, 0.09)
(1.54, 0.84, FIN_LE + 0.10 , 0.085) (1.64, 0.42, FIN_LE + 0.14, 0.08)
```

**Dorsal turret** — `kit.turret("Turret", 0, TURRET_Y, 0.50, r = 0.72, barrels = 4, length = 0.92)`
with `TURRET_Y = NOSE − 4.95 = −1.65`, i.e. immediately behind the pilot and above the wing
trailing edge; a `Gunner` head sits in the crew ring beneath it.

**Gear** — track 2.36 m (x = ±1.18), pivot at `y = WING_LE − 0.35`, `z = −0.45`; tailwheel at
`y = TAIL + 0.95`. Undercarriage leg length is solved at build time so the bbox height matches the
published figure (see `_accuracy()` in the module).

## Verified output

```
ACCURACY defiant    length 10.77/10.77m (-0.0%) span 11.99/11.99m (-0.0%) height 3.45/3.45m (+0.0%) PASS
[model] defiant      tris= 26788 objects=90
```

(Note: tri count from the shared `tools/models/kit.py` revision current when written.)

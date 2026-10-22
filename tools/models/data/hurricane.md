# Hawker Hurricane Mk I — researched dimensions and station tables

Model id `hurricane` · source module `tools/models/data/hurricane.py` · built by
`blender --background --python tools/models/build_all.py -- hurricane`

All geometry is authored from the published figures below; nothing is converted from a
third-party mesh. Frame: metres, origin at the CG station, **nose toward +Y**, up +Z, right +X
(the glTF export maps that onto Godot's −Z forward).

## Headline dimensions (gated at 2 %)

| Quantity | Published | Source |
|---|---|---|
| Length (overall, spinner to rudder) | 9.84 m (32 ft 3 in) | https://www.globalair.com/aircraft-specifications/hawker-aircraft/hurricane-mk-specifications/1559 · https://migflug.com/aircraft/hawker-hurricane/ |
| Wingspan | 12.19 m (40 ft 0 in) | https://airpages.ru/eng/uk/hurr1.shtml |
| Height | 4.00 m (13 ft 1.5 in) | https://en.wikipedia.org/wiki/Hawker_Hurricane |
| Wing area | 23.92 m² (257.5 sq ft) | https://migflug.com/aircraft/hawker-hurricane/ · https://airpages.ru/eng/uk/hurr1.shtml (258 sq ft) |

Notes on the published figures (sources disagree, as they do for every Hurricane mark):

* Some sources give length 9.55 m / 9.58 m — those are **two-blade, early-Mk I** airframes.
  9.84 m is the standard Battle-of-Britain Mk I figure (metal wing, Rotol constant-speed prop).
* Height 4.00 m is quoted as the **overall height with one propeller blade vertical**. The model
  is built level (thrust line horizontal) with the prop tip as the highest point, so the bbox
  height equals the published figure directly. A tail-down stance would read ~4.04 m.

## Secondary dimensions (recorded, not gated)

| Quantity | Value | Source |
|---|---|---|
| Wing root chord (centre section) | 2.72 m | derived: 23.92 m² / 12.19 m mean chord = 1.96 m; taper 2.72 → 1.22 m |
| Wing tip chord | 1.22 m (rounded tip ~0.88 m) | derived as above |
| Dihedral | 4.0° (outer panels) | https://all-aero.com/2025/01/15/hawker-hurricane/ (notes outer-panel dihedral) |
| Propeller | 3-blade Rotol constant-speed, **3.43 m (11 ft 3 in)** dia | https://migflug.com/aircraft/hawker-hurricane/ |
| Main-wheel track | 2.39 m (7 ft 10 in) | https://all-aero.com/2025/01/15/hawker-hurricane/ |
| Main wheel diameter | 0.75 m (29.5 in) — **approximate**, not directly sourced | estimated from period 3-view |
| Armament | 8 × .303 in Browning (4 per wing) | https://en.wikipedia.org/wiki/Hawker_Hurricane |

The Rotol blade in the NASM collection is 3.28 m (129 in) across (https://airandspace.si.edu/collection-objects/rotol-hurricane-variable-pitch-propeller-blade/nasm_A19601434000),
and the 1941 Mk I manual quotes 10 ft 9 in — the 11 ft 3 in figure is used here because it is the
number carried in the standard reference tables.

## Station tables actually used

**Fuselage** — `kit.tube`, 17 stations, n = 30, superellipse power 2.45. `NOSE = +3.10`,
`TAIL = −6.74`. `(y, half-width, half-height, section-centre z)`:

```
( 3.08, 0.11, 0.13, 0.00) ( 2.72, 0.30, 0.33, 0.00) ( 2.25, 0.40, 0.44, 0.02)
( 1.75, 0.44, 0.50, 0.04) ( 1.25, 0.46, 0.55, 0.06) ( 0.75, 0.47, 0.58, 0.08)
( 0.15, 0.47, 0.60, 0.10) (-0.45, 0.45, 0.58, 0.13) (-1.15, 0.40, 0.53, 0.16)
(-1.85, 0.34, 0.47, 0.19) (-2.55, 0.28, 0.40, 0.22) (-3.25, 0.21, 0.33, 0.25)
(-3.95, 0.15, 0.26, 0.27) (-4.65, 0.10, 0.19, 0.29) (-5.35, 0.07, 0.14, 0.30)
(-6.05, 0.05, 0.09, 0.31) (-6.74, 0.03, 0.05, 0.32)
```

**Wing** — `kit.surface` half-wing, mirrored. `WING_LE = +0.75`, `Z_ROOT = −0.26`,
`z(t) = Z_ROOT + 0.43·t` (4.0° dihedral). `(half-span x, chord, thickness ratio)`:

```
(0.34, 2.72, 0.150) (0.95, 2.62, 0.145) (1.65, 2.31, 0.141) (2.45, 2.12, 0.137)
(3.30, 1.91, 0.133) (4.15, 1.70, 0.129) (4.90, 1.51, 0.124) (5.50, 0.99, 0.121)
(5.85, 0.92, 0.119) (6.095, 0.88, 0.118)     # last two stations round the tip
```

**Tailplane** — `kit.surface`, half-span 1.86 m, root chord 1.42 m → tip 0.80 m, `y = TAIL+1.55`.

**Fin/rudder** — `kit.fin`, `(z height, chord, leading-edge y, thickness ratio)`, root LE
`FIN_LE = TAIL + 1.95` so the rudder trailing edge lands exactly on `TAIL`:

```
(0.26, 1.95, FIN_LE        , 0.11) (0.72, 1.88, FIN_LE - 0.02, 0.10)
(1.10, 1.68, FIN_LE + 0.02 , 0.095) (1.42, 1.34, FIN_LE + 0.06, 0.09)
(1.62, 0.86, FIN_LE + 0.10 , 0.085) (1.72, 0.44, FIN_LE + 0.14, 0.08)
```

**Sizing rule that makes the gate exact.** The spinner cone tip is placed at `+NOSE` and the
radiator/rudder trailing edge at `TAIL`, so length self-checks; the wing tips sit on ±SPAN/2, so
span self-checks; the undercarriage leg length is *solved* at build time —
`z_ground = z_max − HEIGHT`, `leg = z_pivot − WHEEL_R − z_ground` — so the bbox height matches the
published figure by construction — see `_accuracy()` in the module.

**Gear** — track 2.39 m (x = ±1.195), pivot at `y = WING_LE − 0.35`, `z = −0.45`; tailwheel at
`y = TAIL + 0.95`.

## Verified output

```
ACCURACY hurricane  length 9.84/9.84m (-0.0%) span 12.19/12.19m (-0.0%) height 4.00/4.00m (-0.0%) PASS
[model] hurricane    tris= 25804 objects=95
```

(Note: this count is from the shared `tools/models/kit.py` revision current when written; the
authored geometry is fixed, only the kit's own detail level moves the total.)

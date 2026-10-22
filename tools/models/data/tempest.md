# Hawker Tempest Mk V — researched dimensions and station tables

Model id `tempest` · source module `tools/models/data/tempest.py` · built by
`blender --background --python tools/models/build_all.py -- tempest`

All geometry is authored from the published figures below. Frame: metres, origin at the CG
station, **nose toward +Y**, up +Z, right +X (the glTF export maps that onto Godot's −Z forward).

## Headline dimensions (gated at 2 %)

| Quantity | Published | Source |
|---|---|---|
| Length | 10.26 m (33 ft 8 in) | https://en.wikipedia.org/wiki/Hawker_Tempest |
| Wingspan | 12.49 m (41 ft 0 in) | https://aeropedia.com.au/content/hawker-tempest/ (12.49 m) · https://en.wikipedia.org/wiki/Hawker_Tempest (41 ft 0 in = 12.50 m) |
| Height | 4.52 m (14 ft 10 in), tail in the rigging/level position, one prop blade vertical | https://en.wikipedia.org/wiki/Hawker_Tempest |
| Wing area | 28.1 m² (302 sq ft) | https://en.wikipedia.org/wiki/Hawker_Tempest |

Height is stance-dependent and Wikipedia gives both: **4.52 m** (14 ft 10 in, tail in rigging
position with one propeller blade vertical) and **4.90 m** (16 ft 1 in, tail down with one
propeller blade vertical). The model is built level, so it is gated against **4.52 m**. Wing area
is also quoted as 303.7 ft² for the Mk II (https://www.warbirdsresourcegroup.org/BARC/tempest-specifications.html);
302 ft² is the Mk V figure.

## Secondary dimensions (recorded, not gated)

| Quantity | Value | Source |
|---|---|---|
| Wing root chord | 3.05 m | derived: 28.1 m² / 12.49 m = 2.25 m mean chord; taper 3.05 → 1.45 m |
| Wing tip chord | 1.45 m (rounded tip ~1.16 m) | derived as above |
| Wing section | Hawker H.14/14/37.5 root, H.14/10/37.5 tip (max thickness at 37.5 % chord) | https://en.wikipedia.org/wiki/Hawker_Tempest |
| Dihedral | flat inner section, dihedral picks up outboard of the (inward-retracting) main gear | https://hawkertempest.newchurchvillage.org/index.php/thetempest/2014-05-12-18-28-30/marki.html |
| Propeller | 4-blade de Havilland Hydromatic, **4.27 m (14 ft 0 in)** dia | https://en.wikipedia.org/wiki/Hawker_Tempest |
| Main-wheel track | 4.53 m (14 ft 11 in) | https://hawkertempest.newchurchvillage.org/index.php/thetempest/2014-05-12-18-28-30/marki.html |
| Main wheel | 0.86 m (34 × 11 in, Mk V Series 1) or 0.76 m (30 × 9 in, Series 2) | https://olddogsplanes.com/tempest.html |
| Armament | 4 × 20 mm Hispano Mk V cannon | https://en.wikipedia.org/wiki/Hawker_Tempest |

## Station tables actually used

**Fuselage** — `kit.tube`, 16 stations, n = 32, power 2.7. `NOSE = +3.90`, `TAIL = −6.36` (the
long Sabre nose). `(y, half-width, half-height, cz)`:

```
( 3.88, 0.13, 0.15, 0.00) ( 3.45, 0.35, 0.40, 0.00) ( 2.90, 0.47, 0.54, 0.02)
( 2.30, 0.51, 0.62, 0.04) ( 1.70, 0.53, 0.68, 0.06) ( 1.10, 0.54, 0.72, 0.09)
( 0.40, 0.54, 0.74, 0.12) (-0.30, 0.51, 0.72, 0.16) (-1.05, 0.45, 0.66, 0.20)
(-1.85, 0.37, 0.56, 0.24) (-2.65, 0.28, 0.46, 0.28) (-3.45, 0.20, 0.36, 0.31)
(-4.25, 0.14, 0.27, 0.33) (-5.05, 0.09, 0.19, 0.35) (-5.75, 0.06, 0.13, 0.36)
(-6.36, 0.035, 0.06, 0.38)
```

**Wing** — `kit.surface` half-wing, mirrored. `WING_LE = +1.00`. The Tempest's thinner laminar
wing keeps a flat centre section and takes its dihedral up outboard of the main gear.
`(half-span x, chord, z offset, thickness ratio)`:

```
(0.34, 3.05, -0.30, 0.145) (1.10, 2.78, -0.32, 0.140) (2.30, 2.39, -0.34, 0.135)
(3.10, 2.12, -0.30, 0.131) (3.90, 1.85, -0.18, 0.127) (4.80, 1.56, 0.00, 0.123)
(5.60, 1.31, +0.16, 0.119) (6.245, 1.16, +0.26, 0.117)
```

**Tailplane** — half-span 2.14 m, root chord 1.62 m → tip 0.96 m, `y = TAIL + 1.70`.

**Fin/rudder** — `kit.fin`, root LE `FIN_LE = TAIL + 2.41` (root chord 2.40 m ⇒ rudder trailing
edge exactly on `TAIL`):

```
(0.32, 2.40, FIN_LE        , 0.11) (0.86, 2.30, FIN_LE - 0.04, 0.10)
(1.32, 2.06, FIN_LE + 0.00 , 0.095) (1.70, 1.64, FIN_LE + 0.07, 0.09)
(1.94, 1.06, FIN_LE + 0.14 , 0.085) (2.06, 0.50, FIN_LE + 0.20, 0.08)
```

**Chin radiator** — `kit.radiator("ChinRadiator", 0, NOSE − 1.40, −0.78, w 1.00, h 0.78, length 1.45)`:
the Tempest's deep chin intake under the long Sabre nose. Four 20 mm Hispanos sit two per wing at
x = ±1.60 and ±2.80 with barrels through the leading edge.

**Gear** — track 4.53 m (x = ±2.265), pivot at `y = WING_LE − 0.50`, `z = −0.52`; tailwheel at
`y = TAIL + 1.10`. The main legs are longer than the Typhoon's (they were redesigned specifically
to clear the 14 ft propeller). Undercarriage leg length is solved at build time so the bbox height
matches the published figure (see `_accuracy()` in the module).

## Verified output

```
ACCURACY tempest    length 10.26/10.26m (+0.0%) span 12.49/12.49m (-0.0%) height 4.52/4.52m (-0.0%) PASS
[model] tempest      tris= 25516 objects=89
```

(Note: tri count from the shared `tools/models/kit.py` revision current when written.)

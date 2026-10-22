"""Douglas C-47 Skytrain / Dakota - 1:1 airframe from published DC-3/C-47 figures.

Headline dimensions (each with its source URL in tools/models/data/c47.md):
  length 19.66 m (64 ft 5 in)   span 28.96 m (95 ft 0 in)   height 5.16 m (16 ft 9 in, level attitude)
  wing area 91.7 m2 (988.9 sq ft)   aspect ratio 9.13   airfoil NACA 2215 (root) / NACA 2206 (tip)
  root chord 4.318 m (170 in)   tip chord 1.209 m (47.6 in, construction tip)   dihedral 5 deg
  outer-panel leading-edge sweep 15.5 deg   mean aerodynamic chord 3.508 m (138.1 in)
  powerplant 2 x Pratt & Whitney R-1830 Twin Wasp (cowl dia 1.566 m), 3-blade Hamilton Standard
  23E50 propeller 11 ft 6 in (3.505 m) dia   main-wheel track 18 ft 6 in (5.64 m), 17.00-16 tyres.

Authoritative geometry source: NACA TN 3088, *Determination of the flying qualities of the Douglas
DC-3 airplane* (1953), Table I - the official airplane specification sheet (see c47.md).

Frame: origin at the CG station (25% MAC), nose toward +Y, up +Z, right +X - the glTF export maps
(x, y, z) -> (x, z, -y) so the nose lands on Godot's -Z.  Everything below is authored here from the
published plan-form; nothing is converted from a third-party mesh.  Deterministic - no RNG.
"""
import math

import bpy
import bmesh
from mathutils import Vector

import kit

ID = "c47"
LEN = 19.66
SPAN = 28.96
HEIGHT = 5.16
AREA = 91.7

# ------------------------------------------------------------------ derived stations (metres)
NOSE_Y = 6.60                     # front of the rounded nose (front-most point of the airframe)
TAIL_Y = NOSE_Y - LEN             # -13.06  rudder trailing edge / tail cone
HALF = SPAN * 0.5                 # 14.48

WING_LE = 1.68                    # wing root leading edge, ahead of the CG (= 25% MAC station)
C_ROOT = 4.318                    # 170 in, NACA TN 3088 Table I
C_TIP = 1.209                     # 47.6 in, construction tip chord (linear-taper extension)
CS_END = 3.813                    # constant-chord centre section half-width (area+MAC solve)
TE_Y = WING_LE - C_ROOT           # -2.638  (straight trailing edge)
Z_ROOT = -0.55                    # wing chord-line height at the root (low wing)
DIH = 0.0875                      # tan(5 deg) dihedral, outboard of the centre section only

NACELLE_X = 3.20                  # engine / nacelle centreline (props just clear the fuselage)
NAC_FRONT = 3.10                  # nacelle front face
NAC_LEN = 3.30
ENG_R = 0.80                      # R-1830 cowl radius (~1.566 m dia)
ENG_Z = -0.10                     # engine axis height
PROP_R = 1.7525                   # 11 ft 6 in Hamilton Standard 23E50
PROP_Y = NAC_FRONT + 0.22
SPINNER_R = 0.36

TRACK = 5.64                      # 18 ft 6 in main-gear spread
WHEEL_R = 0.635                   # 17.00-16 tyre, ~1.27 m dia
WHEEL_X = TRACK * 0.5
Z_GEAR = -0.35                    # gear pivot (in the nacelle)

TAIL_TE_Y = -10.10                # tailplane trailing edge
TAILPLANE_HALF = 4.064            # 320 in span
Z_TAIL = 0.34
FIN_TE_Y = TAIL_Y                 # fin/rudder trailing edge lands on the tail
FIN_LE = -9.21
Z_FIN_ROOT = 0.25

TAILWHEEL_Y = -10.9
EYE = (0.0, 4.32, 1.33)     # above the deck (1.29), just inside the canopy top (1.365)

N_FUS = 40
N_WING = 26
N_TAIL = 18
N_FIN = 20
N_CAN = 26
N_NAC = 24
N_PROP = 10
CUTS = 1

EXPECT = (LEN, SPAN)
HEIGHT_INFO = HEIGHT


# ------------------------------------------------------------------ local helpers
def _surf(name, sections, mirror=True):
    """Loft equal-length rings of absolute (x, y, z) points, then mirror to -X."""
    verts, faces = [], []
    m = len(sections[0])
    for s in sections:
        verts.extend(s)
    for k in range(len(sections) - 1):
        a, b = k * m, (k + 1) * m
        for i in range(m):
            j = (i + 1) % m
            faces.append((a + i, a + j, b + j, b + i))
    faces.append(tuple(range(m - 1, -1, -1)))
    base = (len(sections) - 1) * m
    faces.append(tuple(range(base, base + m)))
    if mirror:
        off = len(verts)
        verts = verts + [(-x, y, z) for (x, y, z) in verts]
        for f in list(faces):
            faces.append(tuple(off + i for i in reversed(f)))
    return kit.new_mesh_object(name, verts, faces)


def _wing_chord(x):
    if x <= CS_END:
        return C_ROOT
    c = C_ROOT - (C_ROOT - C_TIP) * (x - CS_END) / (HALF - CS_END)
    # round the tip off over the outer 0.6 m (a semicircular DC-3 tip, not a square corner)
    if x > 13.9:
        t = (x - 13.9) / (HALF - 13.9)
        c *= 1.0 - 0.80 * t ** 2.0
    return max(c, 0.26)


def _wing_z(x):
    return Z_ROOT + (DIH * (x - CS_END) if x > CS_END else 0.0)


def _wing_sections():
    """Half wing: constant centre section + tapered, raked outer panel with washout, 5 deg dihedral."""
    xs = [0.0, 0.9, 1.9, 2.9, CS_END, 4.9, 6.1, 7.4, 8.7, 10.0, 11.2, 12.3, 13.2, 13.9, 14.15, 14.35, HALF]
    secs = []
    for x in xs:
        chord = _wing_chord(x)
        th = 0.150 - 0.085 * (x / HALF)            # NACA 2215 -> ~2209
        z = _wing_z(x)
        twist = math.radians(-2.2 * (x / HALF))    # a touch of washout
        ring = kit.airfoil_ring(th, 0.02, N_WING)
        ct, st = math.cos(twist), math.sin(twist)
        sec = []
        for (fx, fz) in ring:
            dx, dz = fx - 0.25, fz
            rxc = 0.25 + dx * ct - dz * st
            rzc = dx * st + dz * ct
            sec.append((x, TE_Y + chord * (1.0 - rxc), z + chord * rzc))
        secs.append(sec)
    return secs


def _nacelle(name, x, y_front, length, r0, r1, z_axis, n=N_NAC, stations=9, rz=0.94):
    """A wing engine nacelle: rounded cowl at the front, tapering back to a point aft."""
    secs = []
    for i in range(stations):
        t = i / float(stations - 1)
        r = r0 + (r1 - r0) * t ** 0.85
        bulge = 1.0 + 0.05 * math.sin(math.pi * min(t * 1.5, 1.0))
        yy = y_front - length * t
        ring = kit.superellipse(n, max(r * bulge, 0.02), max(r * bulge * rz, 0.02), 2.2)
        secs.append([(x + px, yy, z_axis + pz) for (px, pz) in ring])
    v, f = kit.loft(secs, True, True)
    return kit.new_mesh_object(name, v, f)


def _blade(name, r_hub, radius, chord, n=N_PROP, steps=6):
    """One prop blade: span along +Z, chord along X, thickness along Y, with real pitch twist."""
    secs = []
    for k in range(steps + 1):
        t = k / float(steps)
        r = r_hub + (radius - r_hub) * t
        c = chord * (1.0 - 0.30 * t)
        th = 0.11 - 0.03 * t
        pitch = math.radians(34.0 - 20.0 * t)
        cp, sp = math.cos(pitch), math.sin(pitch)
        ring = kit.airfoil_ring(th, 0.05, n)
        pts = []
        for (fx, fz) in ring:
            bx = (fx - 0.42) * c
            by = fz * c
            pts.append((bx * cp - by * sp, bx * sp + by * cp, r))
        secs.append(pts)
    return kit.new_mesh_object(name, *kit.loft(secs, True, True))


def _prop(name, suffix, x, y, z, radius, blades=3, spinner_r=0.36, blade_chord=0.34):
    """`name` > `Spinner{suffix}` + `Blades{suffix}` (Blade0..N + BladeTip0..N) + `PropDisc{suffix}`.

    The spinner points forward (kit.propeller's is blunt-forward); blades swing about the shaft (Y).
    """
    prop = kit.empty(name, (x, y, z))
    sp = kit.cylinder("Spinner" + suffix, 0.11, spinner_r, spinner_r * 1.55, loc=(0, 0, 0),
                      rot=(90, 0, 0), n=22)
    kit.parent_to(sp, prop)
    grp = kit.group("Blades" + suffix, (0.0, 0.0, 0.0), prop)
    dy = -0.34 * spinner_r
    for i in range(blades):
        a = kit.TAU * i / blades
        b = _blade("Blade%d%s" % (i, suffix), spinner_r * 0.52, radius, blade_chord)
        b.location = (0.0, dy, 0.0)
        b.rotation_euler = (0.0, a, 0.0)
        kit.parent_to(b, grp)
        tip = kit.box("BladeTip%d%s" % (i, suffix), (blade_chord * 0.70, 0.05, 0.12),
                      loc=(0.0, dy, radius - 0.07), rot=(0.0, math.degrees(a), 0.0))
        kit.parent_to(tip, grp)
    disc = kit.plate("PropDisc" + suffix, 0.0, radius, radius, n=28, thickness=0.02)
    disc.location = (0.0, dy, 0.0)
    kit.parent_to(disc, prop)
    return prop


def _min_z(exclude=()):
    bpy.context.view_layer.update()
    lo = 1e9
    for ob in bpy.data.objects:
        if ob.type != 'MESH' or ob.name in exclude:
            continue
        mw = ob.matrix_world
        for c in ob.bound_box:
            lo = min(lo, (mw @ Vector(c)).z)
    return lo


def _set_top(ob, z_top):
    bpy.context.view_layer.update()
    mw = ob.matrix_world
    zs = [(mw @ Vector(c)).z for c in ob.bound_box]
    ob.location.z += (z_top - max(zs))


def _accuracy():
    """Per-axis bbox vs the published figures; FAIL if length, span or height is beyond 2%."""
    _lo, _hi, size = kit.bounds()
    checks = (("length", size[1], LEN), ("span", size[0], SPAN), ("height", size[2], HEIGHT))
    ok = True
    parts = []
    for nm, got, want in checks:
        pc = (got - want) / want * 100.0
        if abs(pc) > 2.0:
            ok = False
        parts.append("%s %.2f/%.2fm (%+.1f%%)" % (nm, got, want, pc))
    print("ACCURACY %-10s %s %s" % (ID, " ".join(parts), "PASS" if ok else "FAIL"))
    return ok


# ---------------------------------------------------------------- station tables
# fuselage: (y, half-width, half-height, section centre z) nose -> tail
FUS = [
    (NOSE_Y, 0.32, 0.52, -0.42),      # rounded low nose
    (6.30, 0.60, 0.78, -0.30),
    (5.95, 0.85, 0.98, -0.18),
    (5.55, 1.02, 1.10, -0.10),
    (5.10, 1.14, 1.18, -0.05),
    (4.60, 1.22, 1.24, -0.01),
    (4.00, 1.28, 1.29, 0.00),          # windscreen / cockpit front
    (3.30, 1.31, 1.32, 0.00),
    (2.40, 1.32, 1.34, 0.00),
    (1.40, 1.33, 1.35, 0.00),
    (0.40, 1.33, 1.35, 0.01),
    (-0.60, 1.33, 1.35, 0.02),
    (-1.60, 1.32, 1.34, 0.03),
    (-2.60, 1.29, 1.31, 0.05),
    (-3.60, 1.24, 1.26, 0.07),
    (-4.60, 1.17, 1.19, 0.10),
    (-5.60, 1.08, 1.10, 0.13),
    (-6.60, 0.98, 1.01, 0.16),
    (-7.40, 0.89, 0.93, 0.19),
    (-8.40, 0.77, 0.81, 0.23),
    (-9.40, 0.63, 0.67, 0.27),
    (-10.40, 0.49, 0.53, 0.31),
    (-11.40, 0.35, 0.39, 0.35),
    (-12.30, 0.21, 0.24, 0.38),
    (TAIL_Y, 0.09, 0.11, 0.40),
]

# tailplane: (half-span x, chord, twist, z-offset, thickness-ratio, absolute leading-edge y)
TAIL_ST = [
    (0.20, 2.85, 0.0, 0.00, 0.105, TAIL_TE_Y + 2.85),
    (1.30, 2.65, 0.0, 0.03, 0.100, TAIL_TE_Y + 2.65),
    (2.40, 2.28, 0.0, 0.07, 0.095, TAIL_TE_Y + 2.28),
    (3.40, 1.85, 0.0, 0.11, 0.090, TAIL_TE_Y + 1.85),
    (TAILPLANE_HALF, 1.25, 0.0, 0.14, 0.085, TAIL_TE_Y + 1.25),
]

# fin/rudder: (z height, chord, absolute leading-edge y, thickness-ratio); straight rudder TE
FIN_ST = [
    (0.25, 3.85, FIN_TE_Y + 3.85, 0.110),
    (0.80, 3.74, FIN_TE_Y + 3.74, 0.105),
    (1.35, 3.55, FIN_TE_Y + 3.55, 0.100),
    (1.90, 3.28, FIN_TE_Y + 3.28, 0.095),
    (2.40, 2.94, FIN_TE_Y + 2.94, 0.090),
    (2.85, 2.50, FIN_TE_Y + 2.50, 0.085),
    (3.20, 1.98, FIN_TE_Y + 1.98, 0.082),
    (3.45, 1.36, FIN_TE_Y + 1.36, 0.080),
    (3.62, 0.74, FIN_TE_Y + 0.74, 0.080),
]


def build():
    parts = []

    # ---------------------------------------------------------------- fuselage
    fus = kit.tube("Fuselage", FUS, n=N_FUS, power=2.12)
    parts.append(fus)

    # ---------------------------------------------------------------- wing (single mirrored mesh)
    wing = _surf("Wing", _wing_sections())
    parts.append(wing)

    # ---------------------------------------------------------------- tailplane + fin
    tail = kit.surface("Tailplane", TAIL_ST, camber=0.0, n=N_TAIL)
    tail.location = (0.0, 0.0, Z_TAIL)
    parts.append(tail)

    fin = kit.fin("Fin", FIN_ST, camber=0.03, n=N_FIN)
    parts.append(fin)
    # dorsal fillet fairing: a low wedge on the tail-cone spine, rising aft into the fin root
    dorsal = kit.new_mesh_object("DorsalFin", *kit.loft([
        [(x, y, cz + z) for (x, z) in kit.superellipse(10, 0.20, hgt * 0.5, 2.2)]
        for (y, base, hgt) in ((-6.70, 1.02, 0.16), (-7.30, 1.00, 0.26), (-7.90, 0.95, 0.36),
                               (-8.50, 0.90, 0.46), (-9.10, 0.84, 0.56))
        for cz in (base + hgt * 0.5,)
    ], True, True))
    parts.append(dorsal)

    # ---------------------------------------------------------------- engine nacelles + cowls
    for sx, sfx in ((1.0, ""), (-1.0, "R")):
        nac = _nacelle("Nacelle" + sfx, sx * NACELLE_X, NAC_FRONT, NAC_LEN, ENG_R, 0.30, ENG_Z)
        parts.append(nac)
        cowl = kit.cylinder("Cowling" + sfx, ENG_R * 1.03, ENG_R * 0.97, 0.42,
                            loc=(sx * NACELLE_X, NAC_FRONT - 0.12, ENG_Z), rot=(90, 0, 0), n=N_NAC)
        parts.append(cowl)
        parts.append(kit.box("Exhaust" + sfx, (0.16, 1.15, 0.14),
                             loc=(sx * (NACELLE_X + 0.62), NAC_FRONT - 1.35, ENG_Z + 0.52)))
        parts.append(kit.box("Intake" + sfx, (0.22, 0.50, 0.34),
                             loc=(sx * (NACELLE_X + 0.10), NAC_FRONT - 0.35, ENG_Z - 0.86)))

    # ---------------------------------------------------------------- propellers (two)
    parts.append(_prop("Propeller", "", NACELLE_X, PROP_Y, ENG_Z, PROP_R, 3, SPINNER_R))
    parts.append(_prop("PropellerR", "R", -NACELLE_X, PROP_Y, ENG_Z, PROP_R, 3, SPINNER_R))

    # ---------------------------------------------------------------- cockpit glazing (flush with the nose)
    CAN = [
        (5.15, 0.62, 0.12, 0.86),
        (4.95, 0.72, 0.22, 0.94),
        (4.70, 0.80, 0.30, 1.00),
        (4.30, 0.83, 0.32, 1.02),
        (3.85, 0.80, 0.30, 1.00),
        (3.45, 0.70, 0.24, 0.96),
        (3.10, 0.55, 0.16, 0.92),
    ]
    canopy = kit.canopy("Canopy", CAN, n=N_CAN)
    parts.append(canopy)
    frames = []
    for i, (y, hw, hh, cz) in enumerate(CAN):
        frames.append(kit.box("CanopyFrameTop%d" % i, (hw * 2.0, 0.05, 0.05), loc=(0.0, y, cz + hh)))
        frames.append(kit.box("CanopyFrameL%d" % i, (0.05, 0.05, hh * 1.8), loc=(hw, y, cz - hh * 0.15)))
        frames.append(kit.box("CanopyFrameR%d" % i, (0.05, 0.05, hh * 1.8), loc=(-hw, y, cz - hh * 0.15)))
    frames.append(kit.box("WindscreenFrame", (0.66, 0.06, 0.34), loc=(0.0, 4.85, 0.92)))
    frames.append(kit.box("WindscreenCentre", (0.05, 0.06, 0.30), loc=(0.0, 4.80, 1.02)))

    # astrodome blister on the cabin roof behind the cockpit (a proper dome lofted in X-Y rings)
    astro = kit.new_mesh_object("Astrodome", *kit.loft([
        [(math.cos(kit.TAU * i / 12) * r, 2.55 + math.sin(kit.TAU * i / 12) * r * 0.9, z)
         for i in range(12)]
        for (z, r) in ((1.24, 0.22), (1.34, 0.21), (1.43, 0.16), (1.49, 0.09), (1.52, 0.03))
    ], True, True))
    parts.append(astro)

    # ---------------------------------------------------------------- doors (transport fittings)
    parts.append(kit.box("CargoDoor", (0.06, 1.85, 1.55), loc=(-1.28, -2.65, -0.05)))
    parts.append(kit.box("CrewDoor", (0.06, 0.80, 1.05), loc=(-1.30, 2.35, 0.05)))
    parts.append(kit.box("Hatch", (0.55, 0.55, 0.06), loc=(0.35, -6.20, -1.05)))

    # ---------------------------------------------------------------- undercarriage (tailwheel, not tricycle)
    z_ground = _min_z() - 0.06         # main wheels sit a touch below the prop tips
    leg_len = Z_GEAR - z_ground - WHEEL_R
    gl = kit.gear_leg("GearL", WHEEL_X, WING_LE - 0.15, Z_GEAR, leg_len, WHEEL_R)
    gr = kit.gear_leg("GearR", -WHEEL_X, WING_LE - 0.15, Z_GEAR, leg_len, WHEEL_R)
    parts += [gl, gr]
    tw = kit.tailwheel("TailWheel", TAILWHEEL_Y, -0.15, strut=0.30, r=0.20)
    parts.append(tw)

    # ---------------------------------------------------------------- crew
    pilot = kit.pilot(EYE)
    parts.append(pilot)

    # ---------------------------------------------------------------- national markings (USAAF)
    dec = kit.markings("USAAF", fus_x=1.28, fus_y=-3.30, fus_z=0.10, fus_r=0.62,
                       wing_y=-0.92, wing_span_x=11.5, wing_z=-0.13, wing_r=0.72,
                       fin_x=0.05, fin_y=FIN_TE_Y + 1.20, fin_z=1.20, fin_r=0.40)
    parts.append(dec)

    body = kit.build_body(parts)

    # ---------------------------------------------------------------- set the fin top so height is exact
    _set_top(fin, _min_z(exclude=("Fin",)) + HEIGHT)

    # ---------------------------------------------------------------- poly budget
    kit.refine_all(cuts=CUTS)
    for f in frames:
        kit.refine(f, 1)

    # ---------------------------------------------------------------- contract empties (root-level)
    kit.empty("CockpitEye", EYE)
    kit.empty("CockpitMount", EYE)
    # a transport carries no guns: these are the contract's weapon-marker nodes, placed at the nose
    kit.empty("MuzzleL", (0.34, NOSE_Y - 0.55, -0.05))
    kit.empty("MuzzleR", (-0.34, NOSE_Y - 0.55, -0.05))

    _accuracy()

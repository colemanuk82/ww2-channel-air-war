"""North American B-25J Mitchell - 1:1 published dimensions + station tables.

Figures (each with its source URL in tools/models/data/b25.md):
  length 16.13 m (52 ft 11 in)   span 20.60 m (67 ft 7 in)   height 4.80 m (15 ft 9 in)
  wing area 56.7 m2 (610 sq ft)  3-blade Hamilton Standard 23E50 props, 12 ft 7 in (3.84 m) dia.

Airframe: high shoulder wing, glazed bombardier nose, TWIN fin-and-rudder (H tail),
Bendix dorsal turret + twin-gun tail turret + two waist guns, two fixed nose guns, tricycle
gear with the main wheels under the nacelles. Built in metres, nose toward +Y (the glTF export
maps that onto Godot's -Z). Origin = CG station. Everything is generated here - no external mesh.
"""
import math
import bpy
import bmesh
import mathutils
import kit

# ---------------------------------------------------------------- published headline figures
LENGTH = 16.13
SPAN = 20.60
HEIGHT = 4.80
WING_AREA = 56.7

NOSE_Y = 8.00
TAIL_Y = -8.13                     # NOSE_Y - TAIL_Y == LENGTH
GROUND_Z = 1.85                    # tyre bottoms sit at z = -GROUND_Z
FIN_TOP = HEIGHT - GROUND_Z        # 2.95  (fin sets the bbox top, not the prop disc)

WING_LE_Y = 0.55
TAIL_LE_Y = -5.83                  # tailplane TE lands on TAIL_Y
TAILPLANE_HALF = 4.25
FIN_X = 2.55                       # twin fins, mounted on the tailplane

NACELLE_X = 3.55
NACELLE_Z = 0.55
PROP_R = 3.84 * 0.5                # 12 ft 7 in
MAIN_WHEEL_R = 0.60
NOSE_WHEEL_R = 0.34


# ---------------------------------------------------------------- local helpers (kit untouched)
def loft_profiles(name, profiles, flip=False):
    verts, faces = [], []
    m = len(profiles[0])
    for p in profiles:
        verts.extend(p)
    for k in range(len(profiles) - 1):
        a, b = k * m, (k + 1) * m
        for i in range(m):
            j = (i + 1) % m
            faces.append((a + j, a + i, b + i, b + j) if flip else (a + i, a + j, b + j, b + i))
    base = (len(profiles) - 1) * m
    if flip:
        faces.append(tuple(range(0, m)))
        faces.append(tuple(range(base + m - 1, base - 1, -1)))
    else:
        faces.append(tuple(range(m - 1, -1, -1)))
        faces.append(tuple(range(base, base + m)))
    return kit.new_mesh_object(name, verts, faces)


def vertical_fin(name, x0, stations, camber=0.0, n=14, flip=False):
    """A fin/rudder: airfoil sections stacked along +Z, chord along -Y, thickness along X."""
    profiles = []
    for (z, chord, y_le, th) in stations:
        ring = kit.airfoil_ring(th, camber, n)
        profiles.append([(x0 + fz * chord, y_le - chord * fx, z) for (fx, fz) in ring])
    return loft_profiles(name, profiles, flip)


def make_prop(name, sub, loc, radius, blades=3, spinner_r=0.34, blade_chord=0.34):
    """A propeller group `name` with `Spinner`/`Blades`/`PropDisc` (suffix `sub` for the 2nd engine)."""
    prop = kit.empty(name, loc)
    sp = kit.cylinder("Spinner" + sub, spinner_r * 0.95, 0.05, spinner_r * 2.3,
                      loc=(0, 0, 0), rot=(90, 0, 0), n=20)
    kit.parent_to(sp, prop)
    bl = kit.group("Blades" + sub, (0, 0, 0), prop)
    for i in range(blades):
        a = kit.TAU * i / blades
        b = kit.new_mesh_object("Blade%d%s" % (i, sub), *kit.loft([
            kit.ring_xyz(kit.airfoil_ring(0.20, 0.06, 10), -spinner_r * 0.6, scale=blade_chord * 0.5),
            kit.ring_xyz(kit.airfoil_ring(0.16, 0.05, 10), -radius * 0.55, scale=blade_chord * 0.8),
            kit.ring_xyz(kit.airfoil_ring(0.11, 0.04, 10), -radius, scale=blade_chord * 0.5),
        ], cap_start=True, cap_end=True))
        b.rotation_euler = (math.radians(90.0), 0.0, a)
        kit.parent_to(b, bl)
        tip = kit.box("BladeTip%d%s" % (i, sub), (blade_chord * 0.5, 0.18, 0.11),
                      loc=(0, 0, -radius + 0.07))
        tip.rotation_euler = (math.radians(90.0), 0.0, a)
        kit.parent_to(tip, bl)
    disc = kit.plate("PropDisc" + sub, 0.0, radius, radius, n=28, thickness=0.02)
    kit.parent_to(disc, prop)
    return prop


def belly_doors(base, x_center, y0, y1, z, half_w, seg=3):
    for i in range(seg):
        ya = y0 + (y1 - y0) * i / seg
        yb = y0 + (y1 - y0) * (i + 1) / seg
        kit.box("%s%d" % (base, i), (half_w * 2.0, abs(yb - ya) * 0.96, 0.05),
                loc=(x_center, (ya + yb) * 0.5, z))


def refine(ob, cuts=2):
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
    bm.to_mesh(me)
    bm.free()
    me.update()
    for p in me.polygons:
        p.use_smooth = True
    return ob


# ---------------------------------------------------------------- station tables
# fuselage: (y, half-width, half-height, centre-z). Longest point of the airframe -> LENGTH.
FUS_STATIONS = [
    (NOSE_Y, 0.05, 0.06, 0.02),
    (7.82, 0.30, 0.27, 0.02),
    (7.55, 0.46, 0.41, 0.03),
    (7.20, 0.58, 0.53, 0.05),
    (6.75, 0.72, 0.65, 0.08),
    (6.20, 0.83, 0.75, 0.10),
    (5.50, 0.92, 0.84, 0.12),
    (4.60, 0.96, 0.90, 0.14),
    (3.60, 0.97, 0.92, 0.16),
    (2.60, 0.96, 0.92, 0.18),
    (1.60, 0.93, 0.90, 0.20),
    (0.60, 0.87, 0.85, 0.22),
    (-0.50, 0.78, 0.78, 0.24),
    (-1.60, 0.67, 0.69, 0.26),
    (-2.70, 0.55, 0.59, 0.28),
    (-3.80, 0.44, 0.49, 0.30),
    (-4.90, 0.34, 0.40, 0.32),
    (-5.90, 0.26, 0.31, 0.34),
    (-6.80, 0.19, 0.24, 0.36),
    (-7.55, 0.12, 0.17, 0.38),
    (-8.02, 0.07, 0.10, 0.40),
    (TAIL_Y, 0.03, 0.05, 0.40),
]

# wing half: (half-span-x, chord, twist, z-offset, thickness-ratio). Straight LE, tapered TE.
WING_STATIONS = [
    (0.00, 3.60, 0.0, 0.55, 0.155),
    (0.95, 3.58, 0.0, 0.56, 0.150),
    (2.10, 3.48, 0.0, 0.585, 0.145),
    (3.30, 3.30, 0.0, 0.615, 0.140),
    (4.60, 3.02, 0.0, 0.660, 0.132),
    (6.20, 2.68, 0.0, 0.715, 0.124),
    (7.80, 2.32, 0.0, 0.775, 0.116),
    (9.10, 2.05, 0.0, 0.825, 0.110),
    (9.85, 1.90, 0.0, 0.855, 0.107),
    (SPAN * 0.5, 1.55, 0.0, 0.870, 0.104),
]

TAIL_STATIONS = [
    (0.12, 2.30, 0.0, 0.30, 0.10),
    (1.10, 2.05, 0.0, 0.325, 0.095),
    (2.30, 1.70, 0.0, 0.36, 0.09),
    (3.45, 1.35, 0.0, 0.395, 0.088),
    (TAILPLANE_HALF, 1.05, 0.0, 0.42, 0.085),
]

# fin: (z, chord, leading-edge-y, thickness). Base LE -5.58 + 2.55 == TAIL_Y.
FIN_STATIONS = [
    (0.34, 2.55, -5.58, 0.10),
    (1.20, 2.05, -5.58, 0.095),
    (1.95, 1.45, -5.60, 0.09),
    (2.55, 0.95, -5.62, 0.088),
    (FIN_TOP, 0.55, -5.66, 0.085),
]


def build():
    parts = []

    fus = kit.tube("Fuselage", FUS_STATIONS, n=44, power=2.3)
    parts.append(fus)

    wing = kit.surface("Wing", WING_STATIONS, camber=0.02, n=18)
    wing.location = (0.0, WING_LE_Y, 0.0)
    parts.append(wing)

    tail = kit.surface("Tailplane", TAIL_STATIONS, camber=0.0, n=14)
    tail.location = (0.0, TAIL_LE_Y, 0.0)
    parts.append(tail)

    fin_grp = kit.group("Fin")
    kit.parent_to(vertical_fin("FinL", FIN_X, FIN_STATIONS, n=14), fin_grp)
    kit.parent_to(vertical_fin("FinR", -FIN_X, FIN_STATIONS, n=14, flip=True), fin_grp)

    # engine nacelles + cowlings + exhausts, slung on the wing
    for sgn in (1.0, -1.0):
        sd = "L" if sgn > 0 else "R"
        nac = kit.nacelle("Nacelle" + sd, -1.10, 0.0, 0.72, 0.58, 3.70, cy=NACELLE_Z)
        nac.location = (sgn * NACELLE_X, 0.0, 0.0)          # kit.nacelle() has no x offset
        parts.append(nac)
        cowl = kit.cylinder("Cowling" + sd, 0.80, 0.78, 0.60, loc=(sgn * NACELLE_X, 0.98, NACELLE_Z),
                            rot=(90, 0, 0), n=24)
        parts.append(cowl)
        parts.append(kit.box("Exhaust" + sd, (0.14, 1.10, 0.13),
                             loc=(sgn * NACELLE_X, 0.10, NACELLE_Z + 0.62)))
        parts.append(kit.box("Intake" + sd, (0.18, 0.42, 0.30),
                             loc=(sgn * NACELLE_X, 0.95, NACELLE_Z - 0.72)))

    # propellers (3-blade) at the nacelle fronts
    make_prop("Propeller", "", (NACELLE_X, 1.02, NACELLE_Z), PROP_R, blades=3,
              spinner_r=0.36, blade_chord=0.36)
    make_prop("Propeller2", "2", (-NACELLE_X, 1.02, NACELLE_Z), PROP_R, blades=3,
              spinner_r=0.36, blade_chord=0.36)

    # glazing: bombardier 'greenhouse' nose + cockpit canopy + frames
    parts.append(kit.canopy("CanopyNose", [
        (7.60, 0.34, 0.26, 0.30),
        (7.32, 0.44, 0.34, 0.36),
        (7.00, 0.50, 0.40, 0.42),
        (6.70, 0.52, 0.42, 0.46),
    ], n=16))
    parts.append(kit.canopy("Canopy", [
        (6.55, 0.62, 0.30, 0.92),
        (6.10, 0.70, 0.36, 0.98),
        (5.50, 0.72, 0.36, 1.00),
        (4.85, 0.64, 0.32, 0.98),
        (4.35, 0.48, 0.24, 0.94),
    ], n=16))
    parts.append(kit.box("CanopyFrameTop", (0.06, 1.60, 0.06), loc=(0.0, 5.55, 1.36)))
    parts.append(kit.box("Windscreen", (0.58, 0.05, 0.36), loc=(0.0, 7.05, 0.62)))

    # defensive guns: Bendix dorsal, twin-gun tail, two waist, two fixed nose
    parts.append(kit.turret("TurretDorsal", 0.0, 1.35, 1.02, 0.56, barrels=2, length=1.10))
    parts.append(kit.turret("TurretTail", 0.0, -6.40, 0.42, 0.50, barrels=2, length=1.00))
    parts.append(kit.turret("TurretWaistL", 0.80, -1.20, 0.02, 0.26, barrels=1, length=0.85))
    parts.append(kit.turret("TurretWaistR", -0.80, -1.20, 0.02, 0.26, barrels=1, length=0.85))
    parts.append(kit.box("GunNoseL", (0.06, 0.55, 0.06), loc=(0.26, 7.72, -0.02)))
    parts.append(kit.box("GunNoseR", (0.06, 0.55, 0.06), loc=(-0.26, 7.72, -0.02)))

    # bomb bay doors along the belly
    belly_doors("BombBayDoorL", 0.42, 1.10, -2.70, -0.74, 0.40, seg=4)
    belly_doors("BombBayDoorR", -0.42, 1.10, -2.70, -0.74, 0.40, seg=4)

    # tricycle gear (main under the nacelles; nose wheel forward)
    leg_len = GROUND_Z - MAIN_WHEEL_R - 0.10
    kit.gear_leg("GearL", NACELLE_X - 0.30, -0.60, -0.10, leg_len, MAIN_WHEEL_R, track_out=0.0)
    kit.gear_leg("GearR", -(NACELLE_X - 0.30), -0.60, -0.10, leg_len, MAIN_WHEEL_R, track_out=0.0)
    nose_len = GROUND_Z - NOSE_WHEEL_R - 0.32
    kit.gear_leg("NoseGear", 0.0, 6.55, -0.32, nose_len, NOSE_WHEEL_R, track_out=0.0)

    kit.pilot((0.0, 6.10, 0.98))

    dec = kit.markings("USAAF", fus_x=0.97, fus_y=1.60, fus_z=0.30, fus_r=0.50,
                       wing_y=-1.40, wing_span_x=SPAN * 0.5, wing_z=0.70, wing_r=0.62,
                       fin_x=0.0, fin_y=-6.20, fin_z=1.60, fin_r=0.42)

    body = kit.group("Body")
    for ob in list(bpy.data.objects):
        if ob is not body and ob.parent is None:
            kit.parent_to(ob, body)

    kit.empty("CockpitEye", (0.0, 6.10, 1.00))
    kit.empty("MuzzleL", (0.26, 7.95, -0.02))
    kit.empty("MuzzleR", (-0.26, 7.95, -0.02))

    for nm in ("Fuselage", "Wing", "Tailplane", "FinL", "FinR",
               "NacelleL", "NacelleR", "CowlingL", "CowlingR", "Canopy", "CanopyNose"):
        ob = bpy.data.objects.get(nm)
        if ob is not None:
            refine(ob, 2)

    bpy.context.view_layer.update()
    gate()


# ---------------------------------------------------------------- accuracy gate
def _bounds():
    xs, ys, zs = [], [], []
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        for c in ob.bound_box:
            w = ob.matrix_world @ mathutils.Vector(c)
            xs.append(w.x); ys.append(w.y); zs.append(w.z)
    return min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)


def gate():
    x0, x1, y0, y1, z0, z1 = _bounds()
    length = y1 - y0
    span = x1 - x0
    height = z1 - z0

    def pct(a, b):
        return (a - b) / b * 100.0

    ok = (abs(pct(length, LENGTH)) <= 2.0 and abs(pct(span, SPAN)) <= 2.0
          and abs(pct(height, HEIGHT)) <= 2.0)
    print("ACCURACY b25 length %.2f/%.2fm (%+.1f%%) span %.2f/%.2fm (%+.1f%%) height %.2f/%.2fm (%+.1f%%) %s"
          % (length, LENGTH, pct(length, LENGTH), span, SPAN, pct(span, SPAN),
             height, HEIGHT, pct(height, HEIGHT), "PASS" if ok else "FAIL"))

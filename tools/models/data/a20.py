"""Douglas A-20G Havoc - 1:1 published dimensions + station tables.

Figures (each with its source URL in tools/models/data/a20.md):
  length 14.63 m (47 ft 11 7/8 in)   span 18.68 m (61 ft 3.5 in)   height 5.52 m (18 ft 1.5 in)
  wing area 43.1 m2 (464 sq ft)  3-blade Hamilton Standard, 11 ft 3 in (3.43 m) props.

Airframe: shoulder wing, SOLID six-gun nose, SINGLE fin-and-rudder, Martin 250CE dorsal turret +
ventral gun, tricycle gear with the main wheels under the under-slung nacelles.
Built in metres, nose toward +Y (the glTF export maps that onto Godot's -Z).
"""
import math
import bpy
import bmesh
import mathutils
import kit

# ---------------------------------------------------------------- published headline figures
LENGTH = 14.63
SPAN = 18.68
HEIGHT = 5.52
WING_AREA = 43.1

NOSE_Y = 7.30
TAIL_Y = -7.33                     # NOSE_Y - TAIL_Y == LENGTH
GROUND_Z = 1.95
FIN_TOP = HEIGHT - GROUND_Z        # 3.57

WING_LE_Y = 0.55
TAIL_LE_Y = -5.28                  # tailplane TE lands on TAIL_Y
TAILPLANE_HALF = 3.60

NACELLE_X = 3.15
NACELLE_Z = 0.22
PROP_R = 3.43 * 0.5                # 11 ft 3 in
MAIN_WHEEL_R = 0.52
NOSE_WHEEL_R = 0.30


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
    profiles = []
    for (z, chord, y_le, th) in stations:
        ring = kit.airfoil_ring(th, camber, n)
        profiles.append([(x0 + fz * chord, y_le - chord * fx, z) for (fx, fz) in ring])
    return loft_profiles(name, profiles, flip)


def make_prop(name, sub, loc, radius, blades=3, spinner_r=0.32, blade_chord=0.32):
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
        tip = kit.box("BladeTip%d%s" % (i, sub), (blade_chord * 0.5, 0.17, 0.10),
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
FUS_STATIONS = [
    (NOSE_Y, 0.05, 0.06, 0.02),
    (7.12, 0.28, 0.26, 0.02),
    (6.85, 0.44, 0.40, 0.03),
    (6.50, 0.56, 0.50, 0.05),
    (6.05, 0.68, 0.60, 0.08),
    (5.45, 0.77, 0.68, 0.10),
    (4.70, 0.82, 0.74, 0.12),
    (3.80, 0.83, 0.76, 0.14),
    (2.80, 0.82, 0.76, 0.16),
    (1.80, 0.80, 0.75, 0.18),
    (0.80, 0.75, 0.72, 0.20),
    (-0.30, 0.68, 0.67, 0.22),
    (-1.40, 0.59, 0.60, 0.24),
    (-2.50, 0.50, 0.52, 0.26),
    (-3.60, 0.41, 0.44, 0.28),
    (-4.70, 0.33, 0.37, 0.30),
    (-5.70, 0.25, 0.30, 0.32),
    (-6.60, 0.18, 0.23, 0.34),
    (-7.15, 0.12, 0.16, 0.36),
    (TAIL_Y, 0.05, 0.09, 0.36),
]

WING_STATIONS = [
    (0.00, 3.00, 0.0, 0.52, 0.16),
    (0.90, 2.98, 0.0, 0.525, 0.155),
    (1.90, 2.86, 0.0, 0.535, 0.15),
    (3.15, 2.68, 0.0, 0.55, 0.145),
    (4.40, 2.45, 0.0, 0.565, 0.138),
    (5.80, 2.15, 0.0, 0.58, 0.13),
    (7.20, 1.90, 0.0, 0.59, 0.122),
    (8.40, 1.70, 0.0, 0.60, 0.116),
    (8.95, 1.60, 0.0, 0.605, 0.113),
    (SPAN * 0.5, 1.35, 0.0, 0.61, 0.11),
]

TAIL_STATIONS = [
    (0.10, 2.05, 0.0, 0.28, 0.10),
    (1.00, 1.85, 0.0, 0.30, 0.095),
    (2.00, 1.55, 0.0, 0.33, 0.09),
    (2.95, 1.25, 0.0, 0.355, 0.088),
    (TAILPLANE_HALF, 0.95, 0.0, 0.375, 0.085),
]

FIN_STATIONS = [
    (0.34, 2.35, -4.98, 0.10),
    (1.05, 2.05, -4.98, 0.095),
    (1.85, 1.60, -5.02, 0.09),
    (2.70, 1.10, -5.08, 0.088),
    (FIN_TOP, 0.62, -5.15, 0.085),
]


def build():
    parts = []

    parts.append(kit.tube("Fuselage", FUS_STATIONS, n=44, power=2.3))

    wing = kit.surface("Wing", WING_STATIONS, camber=0.02, n=18)
    wing.location = (0.0, WING_LE_Y, 0.0)
    parts.append(wing)

    tail = kit.surface("Tailplane", TAIL_STATIONS, camber=0.0, n=14)
    tail.location = (0.0, TAIL_LE_Y, 0.0)
    parts.append(tail)

    parts.append(vertical_fin("Fin", 0.0, FIN_STATIONS, n=16))

    for sgn in (1.0, -1.0):
        sd = "L" if sgn > 0 else "R"
        nac = kit.nacelle("Nacelle" + sd, -0.95, 0.0, 0.72, 0.58, 3.40, cy=NACELLE_Z)
        nac.location = (sgn * NACELLE_X, 0.0, 0.0)          # kit.nacelle() has no x offset
        parts.append(nac)
        parts.append(kit.cylinder("Cowling" + sd, 0.80, 0.78, 0.56,
                                  loc=(sgn * NACELLE_X, 0.90, NACELLE_Z), rot=(90, 0, 0), n=26))
        parts.append(kit.box("Exhaust" + sd, (0.13, 1.05, 0.12),
                             loc=(sgn * NACELLE_X, 0.05, NACELLE_Z + 0.62)))
        parts.append(kit.box("Intake" + sd, (0.18, 0.42, 0.30),
                             loc=(sgn * NACELLE_X, 0.85, NACELLE_Z - 0.70)))

    make_prop("Propeller", "", (NACELLE_X, 0.98, NACELLE_Z), PROP_R, blades=3,
              spinner_r=0.32, blade_chord=0.32)
    make_prop("Propeller2", "2", (-NACELLE_X, 0.98, NACELLE_Z), PROP_R, blades=3,
              spinner_r=0.32, blade_chord=0.32)

    # solid six-gun nose, stepped cockpit canopy + frames
    for k, x in enumerate((-0.42, -0.26, -0.10, 0.10, 0.26, 0.42)):
        parts.append(kit.box("GunNose%d" % k, (0.07, 0.50, 0.07), loc=(x, 7.02, 0.06)))
    parts.append(kit.box("NoseCap", (0.62, 0.10, 0.44), loc=(0.0, 7.24, 0.02)))
    parts.append(kit.canopy("Canopy", [
        (6.55, 0.50, 0.28, 0.74),
        (6.15, 0.60, 0.34, 0.82),
        (5.60, 0.62, 0.34, 0.86),
        (5.05, 0.56, 0.30, 0.84),
        (4.60, 0.42, 0.22, 0.80),
    ], n=16))
    parts.append(kit.box("Windscreen", (0.52, 0.05, 0.34), loc=(0.0, 6.60, 0.56)))

    # dorsal turret + ventral gun + waist positions
    parts.append(kit.turret("TurretDorsal", 0.0, 1.40, 0.88, 0.52, barrels=2, length=1.05))
    parts.append(kit.turret("TurretVentral", 0.0, 1.60, -0.62, 0.30, barrels=1, length=0.90))
    parts.append(kit.turret("TurretWaistL", 0.78, -1.30, 0.00, 0.24, barrels=1, length=0.80))
    parts.append(kit.turret("TurretWaistR", -0.78, -1.30, 0.00, 0.24, barrels=1, length=0.80))

    belly_doors("BombBayDoorL", 0.34, 0.90, -2.40, -0.62, 0.32, seg=3)
    belly_doors("BombBayDoorR", -0.34, 0.90, -2.40, -0.62, 0.32, seg=3)

    leg_len = GROUND_Z - MAIN_WHEEL_R - 0.12
    kit.gear_leg("GearL", NACELLE_X - 0.25, -0.50, -0.12, leg_len, MAIN_WHEEL_R, track_out=0.0)
    kit.gear_leg("GearR", -(NACELLE_X - 0.25), -0.50, -0.12, leg_len, MAIN_WHEEL_R, track_out=0.0)
    nose_len = GROUND_Z - NOSE_WHEEL_R - 0.30
    kit.gear_leg("NoseGear", 0.0, 5.95, -0.30, nose_len, NOSE_WHEEL_R, track_out=0.0)

    kit.pilot((0.0, 5.65, 0.86))

    kit.markings("USAAF", fus_x=0.82, fus_y=1.50, fus_z=0.30, fus_r=0.46,
                 wing_y=-1.30, wing_span_x=SPAN * 0.5, wing_z=0.62, wing_r=0.58,
                 fin_x=0.0, fin_y=-5.20, fin_z=1.55, fin_r=0.40)

    body = kit.group("Body")
    for ob in list(bpy.data.objects):
        if ob is not body and ob.parent is None:
            kit.parent_to(ob, body)

    kit.empty("CockpitEye", (0.0, 5.65, 0.88))
    kit.empty("MuzzleL", (0.42, 7.27, 0.06))
    kit.empty("MuzzleR", (-0.42, 7.27, 0.06))

    for nm in ("Fuselage", "Wing", "Tailplane", "Fin",
               "NacelleL", "NacelleR", "CowlingL", "CowlingR", "Canopy"):
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
    print("ACCURACY a20 length %.2f/%.2fm (%+.1f%%) span %.2f/%.2fm (%+.1f%%) height %.2f/%.2fm (%+.1f%%) %s"
          % (length, LENGTH, pct(length, LENGTH), span, SPAN, pct(span, SPAN),
             height, HEIGHT, pct(height, HEIGHT), "PASS" if ok else "FAIL"))

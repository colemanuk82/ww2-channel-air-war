"""Heinkel He 111 H - published dimensions (He 111 H-6 / H-16, Jumo 211).

Dimensions (metres): length 16.40, span 22.60, height 4.00, wing area 87.60 m2.
Sources: https://www.warbirdsresourcegroup.org/LRG/he111.html ,
         http://airpages.ru/eng/lw/he111h.shtml ,
         https://warhistory.org/article/heinkel-he-111 (He 111 H-6 spec box).
Powerplant: 2 x Junkers Jumo 211 (3-blade VDM prop, 3.4 m dia -> radius 1.70 m).
Built in metres, nose toward +Y, up +Z, right +X (glTF export maps +Y onto Godot's -Z).

Station tables below are the authoring reference; the numeric gate at the end of build() checks the
assembled bounding box against length / span / height.
"""
import math

import bpy
import bmesh
from mathutils import Vector

import kit

ID = "he111"
LENGTH = 16.40
SPAN = 22.60
HEIGHT = 4.00
WING_AREA = 87.60
HALF = SPAN * 0.5            # 11.30
NOSE = LENGTH * 0.5          # +8.20
TAIL = -LENGTH * 0.5         # -8.20
PROP_R = 1.70                # 3.4 m VDM propeller
ENG_X = 3.95                 # engine / nacelle centreline
ENG_Z = -0.05                # engine axis height (prop tips nearly touch: lowest point)
WHEEL_R = 0.55
GEAR_X = 2.45

# ---- fuselage stations (y, halfwidth, halfheight, centre-z), nose -> tail (metal shell) ----
FUS_STATIONS = [
    (6.60, 0.62, 0.62, 0.22),
    (6.00, 0.82, 0.78, 0.22),
    (5.00, 0.95, 0.88, 0.20),
    (3.80, 1.00, 0.94, 0.16),
    (2.40, 1.00, 0.96, 0.12),
    (0.80, 0.98, 0.93, 0.08),
    (-0.80, 0.90, 0.84, 0.05),
    (-2.60, 0.78, 0.72, 0.04),
    (-4.40, 0.62, 0.56, 0.05),
    (-6.00, 0.44, 0.42, 0.06),
    (-7.20, 0.28, 0.28, 0.08),
    (-8.00, 0.12, 0.14, 0.10),
    (-8.20, 0.04, 0.05, 0.10),
]

# ---- glazed nose (bulbous "glasshouse") stations ----
GLASS_STATIONS = [
    (8.20, 0.06, 0.07, 0.16),
    (7.85, 0.34, 0.36, 0.20),
    (7.30, 0.58, 0.58, 0.24),
    (6.70, 0.76, 0.72, 0.26),
    (6.20, 0.84, 0.78, 0.24),
]

# ---- wing stations (halfspan_x, chord, twist, z_offset, thickness_ratio) ----
WING_STATIONS = [
    (0.95, 5.00, 0.0, -0.30, 0.165),
    (2.40, 4.85, 0.0, -0.24, 0.160),
    (4.30, 4.40, 0.0, -0.14, 0.155),
    (6.20, 3.85, 0.0, -0.04, 0.150),
    (8.10, 3.30, 0.0, 0.06, 0.145),
    (9.60, 2.85, 0.0, 0.15, 0.140),
    (10.60, 2.35, 0.0, 0.22, 0.135),
    (HALF, 1.75, 0.0, 0.27, 0.125),
]
WING_LE_Y = 3.00

# ---- tailplane (dihedral) ----
TAIL_STATIONS = [
    (0.25, 2.45, 0.0, 0.55, 0.11),
    (1.40, 2.25, 0.0, 0.60, 0.10),
    (2.60, 1.85, 0.0, 0.68, 0.10),
    (3.80, 1.35, 0.0, 0.76, 0.09),
]

# ---- fin (single, tall rounded). zoff is unused in the vertical mapping (it becomes lateral),
#      so the leading edge is straight and the fin is a clean vertical plate. ----
FIN_STATIONS = [
    (0.14, 3.10, 0.0, 0.00, 0.09),
    (0.95, 2.60, 0.0, 0.00, 0.085),
    (1.70, 1.90, 0.0, 0.00, 0.08),
    (2.40, 1.10, 0.0, 0.00, 0.08),
]
FIN_LE_Y = -5.10          # root LE; the root TE lands on the tail station (-8.20)


# ------------------------------------------------------------------ helpers
def _bounds():
    bpy.context.view_layer.update()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        mw = ob.matrix_world
        for v in ob.data.vertices:
            w = mw @ v.co
            for i in range(3):
                if w[i] < lo[i]:
                    lo[i] = w[i]
                if w[i] > hi[i]:
                    hi[i] = w[i]
    return lo, hi


def _set_top(ob, z_top):
    bpy.context.view_layer.update()
    mw = ob.matrix_world
    zs = [(mw @ v.co).z for v in ob.data.vertices]
    ob.location.z += (z_top - max(zs))


def _set_bottom(ob, z_bottom):
    bpy.context.view_layer.update()
    mw = ob.matrix_world
    zs = [(mw @ v.co).z for v in ob.data.vertices]
    ob.location.z += (z_bottom - min(zs))


def _min_z(exclude_names=()):
    bpy.context.view_layer.update()
    lo = 1e9
    for ob in bpy.data.objects:
        if ob.type != 'MESH' or ob.name in exclude_names:
            continue
        mw = ob.matrix_world
        for v in ob.data.vertices:
            z = (mw @ v.co).z
            if z < lo:
                lo = z
    return lo


def _refine(cuts=2):
    for ob in list(bpy.data.objects):
        if ob.type != 'MESH':
            continue
        me = ob.data
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
        bm.to_mesh(me)
        bm.free()
        me.update()
        for p in me.polygons:
            p.use_smooth = True


def _gate():
    lo, hi = _bounds()
    meas = {"length": hi.y - lo.y, "span": hi.x - lo.x, "height": hi.z - lo.z}
    pub = {"length": LENGTH, "span": SPAN, "height": HEIGHT}
    parts = []
    ok = True
    for k in ("length", "span", "height"):
        pct = abs(meas[k] - pub[k]) / pub[k] * 100.0
        good = pct <= 2.0
        ok = ok and good
        parts.append("%s %.2f/%.2fm (%.1f%%)" % (k, meas[k], pub[k], pct))
    print("ACCURACY %s %s %s" % (ID, " ".join(parts), "PASS" if ok else "FAIL"))
    return ok


# ------------------------------------------------------------------ build
def build():
    # fuselage
    fus = kit.tube("Fuselage", FUS_STATIONS, n=32, power=2.3)

    # glazed nose + frame rails
    glass = kit.canopy("Canopy", GLASS_STATIONS, n=24)
    for i, gy in enumerate((7.62, 7.05, 6.45)):
        kit.box("CanopyFrame%d" % i, (0.90, 0.06, 0.90), loc=(0.0, gy, 0.26))

    # wing (single mirrored node) with dihedral
    wing = kit.surface("Wing", WING_STATIONS, camber=0.02, n=26)
    wing.location = (0.0, WING_LE_Y, 0.0)

    # tailplane
    tail = kit.surface("Tailplane", TAIL_STATIONS, camber=0.0, n=16)
    tail.location = (0.0, -5.75, 0.0)

    # fin built vertical: span axis -> +Z, chord -> +Y, thickness -> X
    fin = kit.surface("Fin", FIN_STATIONS, camber=0.0, n=16, mirror=False)
    fin.rotation_euler = (0.0, math.radians(-90.0), 0.0)
    fin.location = (0.0, FIN_LE_Y, 0.45)

    parts = [fus, glass, wing, tail, fin]

    # ---- engines: nacelles + cowl rings + props, one per side ----
    for i, sx in enumerate((-1.0, 1.0)):
        x = ENG_X * sx
        nac = kit.nacelle("Nacelle%d" % i, 1.45, 0.0, 0.84, 0.40, 4.90, cy=ENG_Z)
        nac.location = (x, 0.0, 0.0)
        parts.append(nac)
        # annular radiator cowl at the front of the nacelle
        cowl = kit.cylinder("Cowl%d" % i, 0.86, 0.70, 0.45, loc=(x, 3.75, ENG_Z),
                            rot=(90, 0, 0), n=20)
        parts.append(cowl)
        # exhaust stub battery on the outboard side
        kit.box("Exhaust%d" % i, (0.12, 1.30, 0.14), loc=(x + 0.72 * sx, 2.30, ENG_Z + 0.55))
        # main gear leg retracting from the inner wing
        kit.gear_leg("Gear%s" % ("L" if sx < 0 else "R"), GEAR_X * sx, 0.40, 0.40,
                     1.30, WHEEL_R)

    # ---- propeller groups ----
    for i, sx in enumerate((-1.0, 1.0)):
        prop = kit.propeller(0.0, radius=PROP_R, blades=3, spinner_r=0.44, blade_chord=0.36)
        prop.location = (ENG_X * sx, 3.95, ENG_Z)
        # re-seat the disc/blades: kit places children around the (now moved) group origin

    # set the fin to the target top so the height is honest: the lowest point is a prop tip
    _set_top(fin, _min_z(exclude_names=("Fin",)) + HEIGHT)

    # dorsal + ventral defensive turrets (A-Stand / B-Stand)
    kit.turret("TurretDorsal", 0.0, 2.10, 1.02, 0.52, barrels=2, length=1.15)
    vent = kit.turret("TurretVentral", 0.0, 1.30, -1.02, 0.42, barrels=1, length=1.0)
    vent.rotation_euler = (math.radians(180.0), 0.0, 0.0)

    # cockpit interior + canopy top fairing
    kit.box("SpineFairing", (1.10, 2.20, 0.30), loc=(0.0, 3.40, 1.20))
    kit.box("WindscreenTop", (0.95, 0.06, 0.34), loc=(0.0, 5.60, 1.05))

    # national markings
    kit.markings("Luftwaffe", fus_x=0.92, fus_y=-1.40, fus_z=0.10, fus_r=0.48,
                 wing_y=1.60, wing_span_x=HALF, wing_z=0.05, wing_r=0.85,
                 fin_x=0.0, fin_y=-6.45, fin_z=1.30, fin_r=0.46)

    kit.build_body(parts)
    kit.pilot((0.0, 3.90, 0.80))
    kit.empty("CockpitEye", (0.0, 3.95, 1.17))      # above the deck (1.10)
    kit.empty("MuzzleL", (0.34, 6.10, 0.18))
    kit.empty("MuzzleR", (-0.34, 6.10, 0.18))
    kit.empty("CockpitMount", (0.0, 3.95, 1.17))

    _refine(cuts=2)
    _gate()

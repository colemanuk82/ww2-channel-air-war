"""Junkers Ju 87 B Stuka - published dimensions (Jumo 211D, single engine, inverted-gull wing).

Dimensions (metres): length 11.10, span 13.80, height 4.24, wing area 31.90 m2.
Sources: https://www.flugzeuginfo.net/acdata_php/acdata_ju87_en.php (Ju 87 B-1: 11.10 / 13.80 / 4.24 / 31.9),
         https://ww2db.com/aircraft_spec.php?aircraft_model_id=7 (Ju 87B: span 13.80, area 31.90).
Propeller: 3-blade Junkers variable-pitch metal prop, 3.658 m dia (Smithsonian NASM A19700090000),
           taken as 3.60 m (radius 1.80). Fixed spatted main gear (track estimated ~3.3 m from 3-views).
Built in metres, nose toward +Y, up +Z, right +X.
"""
import math

import bpy
import bmesh
from mathutils import Vector

import kit

ID = "ju87"
LENGTH = 11.10
SPAN = 13.80
HEIGHT = 4.24
WING_AREA = 31.90
HALF = SPAN * 0.5            # 6.90
PROP_R = 1.80
ENG_Z = 0.15
WHEEL_R = 0.55
GEAR_X = 1.65

FUS_NOSE_Y = 5.05            # front of the cowling
TAIL_Y = -5.46               # tail (rudder) station
PROP_Y = 5.20                # prop group origin (spinner reaches ~ +5.64)

# fuselage stations (slab-sided, deep cockpit)
FUS_STATIONS = [
    (5.05, 0.34, 0.36, 0.06),
    (4.70, 0.46, 0.50, 0.08),
    (4.10, 0.56, 0.64, 0.10),
    (3.40, 0.62, 0.76, 0.12),
    (2.40, 0.64, 0.82, 0.14),
    (1.20, 0.60, 0.80, 0.12),
    (-0.20, 0.56, 0.74, 0.08),
    (-1.60, 0.48, 0.62, 0.05),
    (-2.80, 0.40, 0.50, 0.04),
    (-3.90, 0.30, 0.38, 0.05),
    (-4.80, 0.18, 0.22, 0.07),
    (-5.46, 0.05, 0.06, 0.08),
]

# long multi-panel greenhouse canopy
GLASS_STATIONS = [
    (1.80, 0.28, 0.16, 1.00),
    (1.35, 0.46, 0.40, 1.16),
    (0.55, 0.50, 0.52, 1.28),
    (-0.45, 0.48, 0.50, 1.26),
    (-1.30, 0.40, 0.42, 1.16),
    (-2.25, 0.22, 0.22, 1.00),
]

# inverted-gull (cranked) wing: inner panel droops from the shoulder, outer panel rises
WING_STATIONS = [
    (0.55, 3.40, 0.0, 0.55, 0.150),
    (1.60, 3.30, 0.0, 0.20, 0.145),
    (2.70, 3.10, 0.0, -0.55, 0.140),
    (3.80, 2.95, 0.0, -0.60, 0.135),
    (4.90, 2.70, 0.0, -0.48, 0.130),
    (5.90, 2.35, 0.0, -0.30, 0.125),
    (HALF, 1.85, 0.0, -0.12, 0.120),
]
WING_LE_Y = 0.60

# braced tailplane
TAIL_STATIONS = [
    (0.14, 1.55, 0.0, 0.28, 0.10),
    (0.80, 1.30, 0.0, 0.32, 0.095),
    (1.45, 0.95, 0.0, 0.36, 0.09),
    (2.00, 0.58, 0.0, 0.40, 0.09),
]
TAIL_LE_Y = -3.55

# fin (single, tall)
FIN_STATIONS = [
    (0.10, 1.95, 0.0, 0.00, 0.09),
    (0.70, 1.55, 0.0, 0.00, 0.085),
    (1.30, 1.05, 0.0, 0.00, 0.08),
    (1.85, 0.60, 0.0, 0.00, 0.08),
]
FIN_LE_Y = -3.50


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
    fus = kit.tube("Fuselage", FUS_STATIONS, n=24, power=2.4)

    glass = kit.canopy("Canopy", GLASS_STATIONS, n=20)
    for i, gy in enumerate((1.45, 0.65, -0.15, -0.95, -1.75)):
        kit.box("CanopyFrame%d" % i, (0.52, 0.05, 1.25), loc=(0.0, gy, 1.24))
    kit.box("WindscreenFlat", (0.48, 0.06, 0.30), loc=(0.0, 1.85, 1.02), rot=(28.0, 0.0, 0.0))

    wing = kit.surface("Wing", WING_STATIONS, camber=0.02, n=22)
    wing.location = (0.0, WING_LE_Y, 0.0)

    tail = kit.surface("Tailplane", TAIL_STATIONS, camber=0.0, n=12)
    tail.location = (0.0, TAIL_LE_Y, 0.0)

    fin = kit.surface("Fin", FIN_STATIONS, camber=0.0, n=12, mirror=False)
    fin.rotation_euler = (0.0, math.radians(-90.0), 0.0)
    fin.location = (0.0, FIN_LE_Y, 0.40)

    parts = [fus, glass, wing, tail, fin]

    # tailplane bracing struts
    for sx in (-1.0, 1.0):
        kit.box("Strut%s" % ("L" if sx < 0 else "R"), (0.06, 0.06, 0.70),
                loc=(0.70 * sx, -3.05, 0.75), rot=(0.0, 0.0, 0.0))

    # engine: cowl + prop
    cowl = kit.cylinder("EngineCowl", 0.62, 0.54, 1.30, loc=(0.0, 4.45, ENG_Z), rot=(90, 0, 0), n=16)
    parts.append(cowl)
    kit.box("Radiator", (0.50, 0.70, 0.30), loc=(0.0, 3.55, ENG_Z - 0.72))

    prop = kit.propeller(0.0, radius=PROP_R, blades=3, spinner_r=0.42, blade_chord=0.36)
    prop.location = (0.0, PROP_Y, ENG_Z)

    # fixed spatted main gear + Jericho-Trumpet dive sirens
    for i, sx in enumerate((-1.0, 1.0)):
        tag = "L" if sx < 0 else "R"
        kit.gear_leg("Gear%s" % tag, GEAR_X * sx, 0.35, 0.30, 1.20, WHEEL_R)
        spat = kit.tube("Spat%s" % tag, [
            (0.78, 0.10, 0.14, 0.0),
            (0.45, 0.26, 0.42, 0.0),
            (0.00, 0.30, 0.56, 0.0),
            (-0.50, 0.24, 0.44, 0.0),
            (-0.88, 0.10, 0.16, 0.0),
        ], n=10, power=2.6)
        spat.location = (GEAR_X * sx, 0.30, -0.95)
        parts.append(spat)
        siren = kit.cylinder("Siren%s" % tag, 0.16, 0.16, 0.55, loc=(GEAR_X * sx, 0.95, -0.60),
                             rot=(90, 0, 0), n=10)
        parts.append(siren)
        # wing-mounted dive brake under the outer wing
        kit.box("DiveBrake%s" % tag, (0.80, 1.30, 0.07), loc=(3.90 * sx, -0.55, -0.72))

    _set_top(fin, _min_z(exclude_names=("Fin",)) + HEIGHT)

    # rear-facing gun
    kit.turret("TurretTail", 0.0, -1.70, 0.95, 0.26, barrels=1, length=0.85)

    kit.markings("Luftwaffe", fus_x=0.60, fus_y=-1.40, fus_z=0.05, fus_r=0.36,
                 wing_y=0.05, wing_span_x=HALF, wing_z=-0.10, wing_r=0.62,
                 fin_x=0.0, fin_y=-4.20, fin_z=1.10, fin_r=0.34)

    kit.build_body(parts)
    kit.pilot((0.0, 0.55, 1.48))
    kit.empty("CockpitEye", (0.0, 0.55, 1.54))
    kit.empty("MuzzleL", (3.30, 0.55, -0.05))
    kit.empty("MuzzleR", (-3.30, 0.55, -0.05))
    kit.empty("CockpitMount", (0.0, 0.55, 1.54))

    _refine(cuts=2)
    _gate()

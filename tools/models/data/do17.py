"""Dornier Do 17 Z - published dimensions (Bramo 323P Fafnir radials, twin fin + rudder).

Dimensions (metres): length 15.80, span 18.00, height 4.55/4.56, wing area 55.00 m2.
Sources: https://ww2db.com/aircraft_spec.php?aircraft_model_id=95 (Do 17Z-2: 15.80 / 18.00 / 4.55 / 55.00),
         https://www.rafmuseum.org.uk/dornier-17 (Bramo 323P 9-cylinder radials, 3-blade props).
Propeller: 3-blade variable-pitch VDM on the Bramo 323; diameter not commonly published, taken as 3.30 m
from 3-view scale (radius 1.65). Built in metres, nose toward +Y, up +Z, right +X.
"""
import math

import bpy
import bmesh
from mathutils import Vector

import kit

ID = "do17"
LENGTH = 15.80
SPAN = 18.00
HEIGHT = 4.55
WING_AREA = 55.00
HALF = SPAN * 0.5            # 9.00
NOSE = LENGTH * 0.5          # +7.90
TAIL = -LENGTH * 0.5         # -7.90
PROP_R = 1.65
ENG_X = 3.30
ENG_Z = -0.05
WHEEL_R = 0.55
GEAR_X = 2.95
FIN_X = 2.55

# fuselage stations (slim "flying pencil" fuselage)
FUS_STATIONS = [
    (7.90, 0.06, 0.07, 0.10),
    (7.60, 0.35, 0.40, 0.12),
    (7.00, 0.58, 0.62, 0.15),
    (6.20, 0.72, 0.80, 0.16),
    (5.00, 0.76, 0.92, 0.14),
    (3.60, 0.76, 0.94, 0.10),
    (2.00, 0.74, 0.90, 0.06),
    (0.20, 0.70, 0.82, 0.02),
    (-1.60, 0.62, 0.70, 0.00),
    (-3.40, 0.50, 0.54, 0.00),
    (-5.20, 0.36, 0.38, 0.02),
    (-6.80, 0.20, 0.22, 0.05),
    (-7.90, 0.05, 0.06, 0.06),
]

# stepped "greenhouse" nose glazing (angular / faceted)
GLASS_STATIONS = [
    (7.90, 0.05, 0.06, 0.12),
    (7.60, 0.34, 0.40, 0.14),
    (7.05, 0.56, 0.62, 0.16),
    (6.45, 0.70, 0.78, 0.16),
]

# raised cockpit canopy behind the nose step
CANOPY_STATIONS = [
    (6.20, 0.30, 0.18, 1.02),
    (5.60, 0.62, 0.50, 1.12),
    (4.60, 0.72, 0.58, 1.15),
    (3.60, 0.65, 0.50, 1.10),
    (3.00, 0.30, 0.20, 1.02),
]

# wing (shoulder wing)
WING_STATIONS = [
    (0.80, 3.15, 0.0, 0.20, 0.150),
    (2.20, 3.05, 0.0, 0.15, 0.145),
    (4.00, 2.80, 0.0, 0.08, 0.140),
    (5.60, 2.50, 0.0, 0.02, 0.135),
    (6.90, 2.15, 0.0, -0.02, 0.130),
    (7.90, 1.80, 0.0, -0.05, 0.128),
    (HALF, 1.35, 0.0, -0.08, 0.120),
]
WING_LE_Y = 2.60

# tailplane (carries the twin fins at its tips)
TAIL_STATIONS = [
    (0.20, 2.10, 0.0, 0.42, 0.10),
    (1.20, 1.95, 0.0, 0.48, 0.095),
    (2.20, 1.65, 0.0, 0.55, 0.09),
    (3.00, 1.25, 0.0, 0.62, 0.09),
]

# fin (twin, built once and mirrored as two objects)
FIN_STATIONS = [
    (0.12, 2.05, 0.0, 0.00, 0.09),
    (0.70, 1.75, 0.0, 0.00, 0.085),
    (1.30, 1.30, 0.0, 0.00, 0.08),
    (1.85, 0.75, 0.0, 0.00, 0.08),
]
FIN_LE_Y = -5.85


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


def _set_top_all(objs, z_top):
    bpy.context.view_layer.update()
    zmax = max((o.matrix_world @ v.co).z for o in objs for v in o.data.vertices)
    for o in objs:
        o.location.z += (z_top - zmax)


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
    fus = kit.tube("Fuselage", FUS_STATIONS, n=32, power=2.4)

    glass = kit.canopy("Canopy", GLASS_STATIONS, n=20)
    glass.scale = (1.0, 1.0, 1.0)
    for i, gy in enumerate((7.55, 7.15, 6.70)):
        kit.box("CanopyFrame%d" % i, (0.64, 0.05, 0.72), loc=(0.0, gy, 0.16))

    cockpit = kit.canopy("CanopyCockpit", CANOPY_STATIONS, n=22)
    for i, gy in enumerate((5.70, 4.90, 4.00)):
        kit.box("CockpitFrame%d" % i, (0.70, 0.05, 1.05), loc=(0.0, gy, 1.14))

    wing = kit.surface("Wing", WING_STATIONS, camber=0.02, n=26)
    wing.location = (0.0, WING_LE_Y, 0.0)

    tail = kit.surface("Tailplane", TAIL_STATIONS, camber=0.0, n=16)
    tail.location = (0.0, -5.55, 0.0)

    fins = []
    for i, sx in enumerate((-1.0, 1.0)):
        f = kit.surface("Fin" if sx > 0 else "FinPort", FIN_STATIONS, camber=0.0, n=16, mirror=False)
        f.rotation_euler = (0.0, math.radians(-90.0), 0.0)
        f.location = (FIN_X * sx, FIN_LE_Y, 0.55)
        fins.append(f)

    parts = [fus, glass, cockpit, wing, tail] + fins

    for i, sx in enumerate((-1.0, 1.0)):
        x = ENG_X * sx
        nac = kit.nacelle("Nacelle%d" % i, 1.05, 0.0, 0.82, 0.55, 3.60, cy=ENG_Z)
        nac.location = (x, 0.0, 0.0)
        parts.append(nac)
        # radial cowling (short, wide, circular - Bramo 323)
        cowl = kit.cylinder("Cowl%d" % i, 0.88, 0.64, 0.72, loc=(x, 2.85, ENG_Z),
                            rot=(90, 0, 0), n=22)
        parts.append(cowl)
        kit.gear_leg("Gear%s" % ("L" if sx < 0 else "R"), GEAR_X * sx, 0.10, 0.30, 1.30, WHEEL_R)

    for i, sx in enumerate((-1.0, 1.0)):
        prop = kit.propeller(0.0, radius=PROP_R, blades=3, spinner_r=0.42, blade_chord=0.34)
        prop.location = (ENG_X * sx, 3.30, ENG_Z)

    _set_top_all(fins, _min_z(exclude_names=("Fin", "FinPort")) + HEIGHT)

    kit.turret("TurretNose", 0.0, 7.30, 0.20, 0.30, barrels=2, length=0.75)
    kit.turret("TurretDorsal", 0.0, 2.60, 0.92, 0.44, barrels=1, length=0.95)
    vent = kit.turret("TurretVentral", 0.0, 2.00, -1.05, 0.34, barrels=1, length=0.85)
    vent.rotation_euler = (math.radians(180.0), 0.0, 0.0)

    kit.box("SpineFairing", (0.90, 1.60, 0.22), loc=(0.0, 2.20, 0.95))

    kit.markings("Luftwaffe", fus_x=0.74, fus_y=-1.20, fus_z=0.00, fus_r=0.42,
                 wing_y=1.55, wing_span_x=HALF, wing_z=0.00, wing_r=0.72,
                 fin_x=FIN_X, fin_y=-6.55, fin_z=1.10, fin_r=0.40)

    kit.build_body(parts)
    kit.pilot((0.0, 4.90, 1.20))
    kit.empty("CockpitEye", (0.0, 4.90, 1.26))
    kit.empty("MuzzleL", (0.30, 6.80, 0.20))
    kit.empty("MuzzleR", (-0.30, 6.80, 0.20))
    kit.empty("CockpitMount", (0.0, 4.90, 1.26))

    _refine(cuts=2)
    _gate()

"""Junkers Ju 88 A-4 - published dimensions (Jumo 211J power eggs).

Dimensions (metres): length 14.36/14.40, span 20.08, height 4.85, wing area 54.5 m2.
Sources: https://en.wikipedia.org/wiki/Junkers_Ju_88 (A-4 spec box: 14.4 / 20 / 4.8 / 54.5),
         https://uboat.net/technical/ju88.htm (Ju 88A-4: span 20.00, length 14.40, height 4.85, area 54.50).
Propeller: 3-blade VDM/Junkers, ~3.60 m diameter (https://migflug.com/aircraft/ju-88/).
Built in metres, nose toward +Y, up +Z, right +X (glTF export maps +Y onto Godot's -Z).
Gate at the end of build() checks the assembled bounding box against length / span / height.
"""
import math

import bpy
import bmesh
from mathutils import Vector

import kit

ID = "ju88"
LENGTH = 14.36
SPAN = 20.08
HEIGHT = 4.85
WING_AREA = 54.50
HALF = SPAN * 0.5            # 10.04
NOSE = LENGTH * 0.5          # +7.18
TAIL = -LENGTH * 0.5         # -7.18
PROP_R = 1.80                # 3.60 m VDM propeller
ENG_X = 3.55
ENG_Z = -0.10
WHEEL_R = 0.60
GEAR_X = 3.05

# fuselage stations (y, halfwidth, halfheight, centre-z), nose -> tail
FUS_STATIONS = [
    (6.65, 0.10, 0.12, 0.02),
    (6.30, 0.52, 0.60, 0.02),
    (5.60, 0.78, 0.85, 0.05),
    (4.60, 0.86, 0.98, 0.06),
    (3.30, 0.88, 1.02, 0.05),
    (1.80, 0.88, 1.03, 0.03),
    (0.20, 0.86, 1.00, 0.02),
    (-1.60, 0.80, 0.92, 0.02),
    (-3.40, 0.68, 0.76, 0.03),
    (-5.00, 0.50, 0.54, 0.05),
    (-6.30, 0.32, 0.34, 0.08),
    (-7.00, 0.16, 0.18, 0.10),
    (-7.18, 0.05, 0.06, 0.10),
]

# glazed "beetle" nose (engineer/glass nose) stations
GLASS_STATIONS = [
    (7.18, 0.05, 0.06, 0.00),
    (6.90, 0.30, 0.34, 0.02),
    (6.50, 0.55, 0.62, 0.05),
    (6.05, 0.72, 0.82, 0.07),
    (5.60, 0.80, 0.90, 0.08),
]

# wing stations (halfspan_x, chord, twist, z_offset, thickness_ratio) - mid/shoulder wing
WING_STATIONS = [
    (0.88, 4.05, 0.0, 0.05, 0.155),
    (2.20, 3.95, 0.0, 0.02, 0.150),
    (4.00, 3.55, 0.0, -0.02, 0.145),
    (5.80, 3.05, 0.0, -0.06, 0.140),
    (7.40, 2.60, 0.0, -0.10, 0.135),
    (8.80, 2.20, 0.0, -0.13, 0.130),
    (9.60, 1.80, 0.0, -0.15, 0.128),
    (HALF, 1.35, 0.0, -0.17, 0.120),
]
WING_LE_Y = 2.30

# tailplane
TAIL_STATIONS = [
    (0.20, 2.25, 0.0, 0.35, 0.10),
    (1.30, 2.05, 0.0, 0.42, 0.095),
    (2.40, 1.65, 0.0, 0.50, 0.09),
    (3.40, 1.15, 0.0, 0.58, 0.09),
]

# fin (single, rounded)
FIN_STATIONS = [
    (0.14, 2.85, 0.0, 0.00, 0.09),
    (0.90, 2.40, 0.0, 0.00, 0.085),
    (1.65, 1.75, 0.0, 0.00, 0.08),
    (2.35, 1.00, 0.0, 0.00, 0.08),
]
FIN_LE_Y = -4.33


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
    fus = kit.tube("Fuselage", FUS_STATIONS, n=32, power=2.4)

    glass = kit.canopy("Canopy", GLASS_STATIONS, n=24)
    for i, gy in enumerate((6.62, 6.15, 5.72)):
        kit.box("CanopyFrame%d" % i, (0.80, 0.05, 0.85), loc=(0.0, gy, 0.05))

    wing = kit.surface("Wing", WING_STATIONS, camber=0.02, n=26)
    wing.location = (0.0, WING_LE_Y, 0.0)

    tail = kit.surface("Tailplane", TAIL_STATIONS, camber=0.0, n=16)
    tail.location = (0.0, -4.85, 0.0)

    fin = kit.surface("Fin", FIN_STATIONS, camber=0.0, n=16, mirror=False)
    fin.rotation_euler = (0.0, math.radians(-90.0), 0.0)
    fin.location = (0.0, FIN_LE_Y, 0.45)

    parts = [fus, glass, wing, tail, fin]

    # ventral "Bola" gondola under the nose (gunner + bomb aimer)
    gond = kit.tube("VentralGondola", [
        (4.90, 0.28, 0.30, 0.0),
        (4.20, 0.45, 0.42, 0.0),
        (3.20, 0.50, 0.46, 0.0),
        (2.20, 0.42, 0.38, 0.0),
        (1.60, 0.22, 0.22, 0.0),
    ], n=20, power=2.2)
    gond.location = (0.0, 0.0, -1.05)
    parts.append(gond)

    for i, sx in enumerate((-1.0, 1.0)):
        x = ENG_X * sx
        nac = kit.nacelle("Nacelle%d" % i, 0.95, 0.0, 0.80, 0.38, 4.60, cy=ENG_Z)
        nac.location = (x, 0.0, 0.0)
        parts.append(nac)
        cowl = kit.cylinder("Cowl%d" % i, 0.82, 0.66, 0.50, loc=(x, 3.20, ENG_Z),
                            rot=(90, 0, 0), n=20)
        parts.append(cowl)
        kit.box("Exhaust%d" % i, (0.12, 1.20, 0.14), loc=(x + 0.66 * sx, 1.40, ENG_Z + 0.62))
        kit.gear_leg("Gear%s" % ("L" if sx < 0 else "R"), GEAR_X * sx, 0.20, 0.35, 1.35, WHEEL_R)
        # dive brake under the outer wing
        kit.box("DiveBrake%s" % ("L" if sx < 0 else "R"), (0.85, 1.40, 0.07),
                loc=(6.40 * sx, -0.40, -0.62))

    for i, sx in enumerate((-1.0, 1.0)):
        prop = kit.propeller(0.0, radius=PROP_R, blades=3, spinner_r=0.46, blade_chord=0.38)
        prop.location = (ENG_X * sx, 3.45, ENG_Z)

    _set_top(fin, _min_z(exclude_names=("Fin",)) + HEIGHT)

    kit.turret("TurretDorsal", 0.0, 1.20, 1.02, 0.50, barrels=2, length=1.05)
    vent = kit.turret("TurretVentral", 0.0, 2.40, -1.40, 0.38, barrels=1, length=0.9)
    vent.rotation_euler = (math.radians(180.0), 0.0, 0.0)
    nose = kit.turret("TurretNose", 0.0, 5.60, 0.30, 0.30, barrels=1, length=0.8)
    nose.rotation_euler = (math.radians(-90.0), 0.0, 0.0)

    kit.box("SpineFairing", (0.95, 1.90, 0.26), loc=(0.0, 2.80, 1.22))
    kit.box("WindscreenTop", (0.82, 0.05, 0.30), loc=(0.0, 5.05, 0.95))

    kit.markings("Luftwaffe", fus_x=0.80, fus_y=-1.20, fus_z=0.05, fus_r=0.44,
                 wing_y=1.30, wing_span_x=HALF, wing_z=-0.10, wing_r=0.78,
                 fin_x=0.0, fin_y=-5.10, fin_z=1.05, fin_r=0.42)

    kit.build_body(parts)
    kit.pilot((0.0, 3.05, 0.92))
    kit.empty("CockpitEye", (0.0, 3.05, 1.14))      # above the deck (1.07)
    kit.empty("MuzzleL", (0.32, 6.30, 0.20))
    kit.empty("MuzzleR", (-0.32, 6.30, 0.20))
    kit.empty("CockpitMount", (0.0, 3.05, 1.14))

    _refine(cuts=2)
    _gate()

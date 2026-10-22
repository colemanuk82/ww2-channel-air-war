"""Hawker Typhoon Mk IB - 1:1 airframe from published figures.

Published (each with its source URL in tools/models/data/typhoon.md):
  length 9.73 m (31 ft 11 in), span 12.67 m (41 ft 7 in), height 4.52 m (14 ft 10 in, level
  attitude - the naval/military sources also quote 15 ft 3 in / 4.66 m tail-down),
  wing area 25.9 m2 (279 sq ft), 4-blade de Havilland/Rotol constant-speed prop ~3.66 m (12 ft 0 in)
  dia (source-dependent, see the .md), main-wheel track 4.13 m (13 ft 6 3/4 in), main wheel 0.86 m
  (34 in) dia, 4 x 20 mm Hispano Mk II cannon in the wings, Napier Sabre IIA/IIB H-24 with the
  signature chin radiator.  Wing: 1 deg anhedral inboard of the gear, 5.5 deg dihedral outboard.

Frame: origin at the CG station, nose toward +Y, up +Z, right +X (the glTF export maps that onto
Godot's -Z forward).  Original geometry only - every station below is authored here.
"""
import math

import bpy
import kit

ID = "typhoon"
LEN = 9.73
SPAN = 12.67
HEIGHT = 4.52
AREA = 25.9

HALF = SPAN * 0.5                 # 6.335
ROOT_CHORD = 2.86
TIP_CHORD = 1.24
Z_ROOT = -0.28
SPINNER_R = 0.34
PROP_R = 1.83                     # ~12 ft 0 in / 2 (4-blade)
WHEEL_R = 0.43                    # 34 in tyre
TRACK = 4.13

WING_LE = 0.95
NOSE = WING_LE + 2.60             # 3.55: spinner tip
TAIL = NOSE - LEN                 # -6.18
TAIL_TOP = 0.36
FIN_LE = TAIL + 2.26
TAILPLANE_Y = TAIL + 1.60
EYE = (0.0, NOSE - 3.35, 0.91)     # above the deck (0.84), inside the canopy (1.015)

N_FUS = 32
N_WING = 22
N_TAIL = 18
N_FIN = 20
N_CAN = 24
N_PROP = 10
CUTS = 1

# (half_span_x, z_offset): 1 deg anhedral inboard, 5.5 deg dihedral outboard of the main gear
GULL = [(0.34, -0.28), (1.10, -0.30), (2.00, -0.32), (2.70, -0.31), (3.40, -0.24),
        (4.30, -0.12), (5.20, 0.02), (5.90, 0.14), (HALF, 0.20)]


# ------------------------------------------------------------------ local helpers

def _surface(name, sections):
    verts, faces = kit.loft(sections, True, True)
    off = len(verts)
    verts = verts + [(-x, y, z) for (x, y, z) in verts]
    for f in list(faces):
        faces.append(tuple(off + i for i in reversed(f)))
    return kit.new_mesh_object(name, verts, faces)


def _blade(name, r_hub, radius, chord, n=N_PROP, steps=6):
    secs = []
    for k in range(steps + 1):
        t = k / float(steps)
        r = r_hub + (radius - r_hub) * t
        c = chord * (1.0 - 0.28 * t)
        th = 0.19 - 0.075 * t
        ring = kit.airfoil_ring(th, 0.05 * (1.0 - 0.5 * t), n)
        secs.append([((fx - 0.40) * c, fz * c, r) for (fx, fz) in ring])
    return kit.new_mesh_object(name, *kit.loft(secs, True, True))


def _prop(nose_y, radius, blades, spinner_r, blade_chord):
    prop = kit.empty("Propeller", (0.0, nose_y, 0.0))
    sp = kit.cylinder("Spinner", 0.05, spinner_r, spinner_r * 2.30, loc=(0, 0, 0), rot=(90, 0, 0), n=24)
    kit.parent_to(sp, prop)
    grp = kit.group("Blades", (0.0, 0.0, 0.0), prop)
    dy = -0.35 * spinner_r
    for i in range(blades):
        a = kit.TAU * i / blades
        b = _blade("Blade%d" % i, spinner_r * 0.55, radius, blade_chord)
        b.location = (0.0, dy, 0.0)
        b.rotation_euler = (0.0, a, 0.0)
        kit.parent_to(b, grp)
        tip = kit.box("BladeTip%d" % i, (blade_chord * 0.72, 0.05, 0.14),
                      loc=(0.0, dy, radius - 0.07), rot=(0.0, math.degrees(a), 0.0))
        kit.parent_to(tip, grp)
    disc = kit.disc("PropDisc", 0.0, 0.0, 0.0, radius, n=28)
    disc.location = (0.0, dy, 0.0)
    kit.parent_to(disc, prop)
    return prop


def _z_max():
    from mathutils import Vector
    bpy.context.view_layer.update()
    hi = -1e9
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        for c in ob.bound_box:
            hi = max(hi, (ob.matrix_world @ Vector(c)).z)
    return hi


def _accuracy():
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


# ------------------------------------------------------------------ build

def build():
    # ---------------------------------------------------------------- fuselage (deep Sabre spine)
    fus = kit.tube("Fuselage", [
        (NOSE - 0.02, 0.13, 0.15, 0.00),
        (NOSE - 0.42, 0.34, 0.38, 0.00),      # cowling
        (NOSE - 0.95, 0.46, 0.52, 0.02),
        (NOSE - 1.50, 0.50, 0.60, 0.04),
        (NOSE - 2.05, 0.52, 0.66, 0.06),      # firewall
        (NOSE - 2.60, 0.53, 0.70, 0.08),      # windscreen base
        (NOSE - 3.25, 0.53, 0.72, 0.11),      # cockpit
        (NOSE - 3.90, 0.50, 0.70, 0.14),
        (NOSE - 4.60, 0.44, 0.64, 0.18),      # aft cockpit / spine
        (NOSE - 5.35, 0.36, 0.55, 0.22),
        (NOSE - 6.10, 0.28, 0.45, 0.26),
        (NOSE - 6.85, 0.20, 0.35, 0.29),
        (NOSE - 7.60, 0.14, 0.26, 0.31),
        (NOSE - 8.35, 0.09, 0.18, 0.33),
        (NOSE - 9.05, 0.06, 0.12, 0.34),
        (TAIL, 0.035, 0.06, TAIL_TOP),
    ], n=N_FUS, power=2.7)

    # ---------------------------------------------------------------- wing (inverted-gull plan-form)
    xs = [0.34, 1.10, 2.00, 2.70, 3.40, 4.30, 5.20, 5.90, HALF]
    xz = dict(GULL)
    secs = []
    for x in xs:
        t = x / HALF
        ch = ROOT_CHORD - (ROOT_CHORD - TIP_CHORD) * t
        if t > 0.94:
            ch *= 0.78
        ring = kit.airfoil_ring(0.150 - 0.030 * t, 0.024, N_WING)
        secs.append([(x, WING_LE - ch * fx, xz[x] + fz * ch) for (fx, fz) in ring])
    wing = _surface("Wing", secs)

    # ---------------------------------------------------------------- tailplane + fin
    txs = [0.24, 0.70, 1.16, 1.56, 1.84, 2.00]
    tsec = []
    for x in txs:
        t = x / 2.00
        ch = 1.52 - 0.62 * t
        ring = kit.airfoil_ring(0.11 - 0.02 * t, 0.0, N_TAIL)
        tsec.append([(x, TAILPLANE_Y - 0.05 * x - ch * fx, 0.22 + 0.13 * t + fz * ch) for (fx, fz) in ring])
    tail = _surface("Tailplane", tsec)

    fin = kit.fin("Fin", [
        (0.30, 2.25, FIN_LE, 0.11),
        (0.80, 2.16, FIN_LE - 0.04, 0.10),
        (1.22, 1.94, FIN_LE + 0.00, 0.095),
        (1.58, 1.56, FIN_LE + 0.06, 0.09),
        (1.82, 1.02, FIN_LE + 0.12, 0.085),
        (1.94, 0.48, FIN_LE + 0.18, 0.08),
    ], camber=0.03, n=N_FIN)

    # ---------------------------------------------------------------- canopy (bubble + aft fairing)
    canopy = kit.canopy("Canopy", [
        (NOSE - 2.55, 0.32, 0.18, 0.60),      # windscreen base
        (NOSE - 2.95, 0.38, 0.26, 0.66),
        (NOSE - 3.45, 0.40, 0.31, 0.68),      # pilot hood
        (NOSE - 4.00, 0.38, 0.29, 0.68),
        (NOSE - 4.55, 0.30, 0.22, 0.64),      # rear fairing
        (NOSE - 5.05, 0.18, 0.14, 0.58),
    ], n=N_CAN)
    frames = []
    for i, (y, hw, hh, cz) in enumerate([
            (NOSE - 2.55, 0.32, 0.18, 0.60), (NOSE - 3.45, 0.40, 0.31, 0.68),
            (NOSE - 4.55, 0.30, 0.22, 0.64)]):
        frames.append(kit.box("CanopyFrameTop%d" % i, (hw * 2.1, 0.05, 0.05), loc=(0.0, y, cz + hh)))
        frames.append(kit.box("CanopyFrameL%d" % i, (0.05, 0.05, hh * 1.9), loc=(hw, y, cz)))
        frames.append(kit.box("CanopyFrameR%d" % i, (0.05, 0.05, hh * 1.9), loc=(-hw, y, cz)))

    # ---------------------------------------------------------------- engine, prop, crew
    prop = _prop(NOSE - SPINNER_R * 1.15, PROP_R, 4, SPINNER_R, 0.36)
    pilot = kit.pilot(EYE)

    # ---------------------------------------------------------------- chin radiator, exhausts, cannon
    chin = kit.radiator("ChinRadiator", 0.0, NOSE - 1.30, -0.72, 0.96, 0.74, 1.35)
    oil = kit.radiator("OilCooler", 0.0, NOSE - 2.35, -0.60, 0.46, 0.22, 0.40)
    ex_l = kit.exhaust_bank("ExhaustL", 0.52, NOSE - 1.70, 0.30, stacks=6, spacing=0.185, r=0.055)
    ex_r = kit.exhaust_bank("ExhaustR", -0.52, NOSE - 1.70, 0.30, stacks=6, spacing=0.185, r=0.055)
    # four 20 mm Hispanos: two per wing, barrels through the leading edge
    guns = []
    for s in (1, -1):
        for k, gx in enumerate((1.50, 2.62)):
            gz = _wing_z(gx)
            guns.append(kit.box("Cannon%d_%d" % (s, k), (0.09, 1.15, 0.09),
                                loc=(s * gx, WING_LE - 0.50, gz)))
            guns.append(kit.cylinder("GunBarrel%d_%d" % (s, k), 0.045, 0.045, 0.55,
                                     loc=(s * gx, WING_LE - 0.25, gz), rot=(90, 0, 0), n=10))

    dec = kit.markings("RAF", fus_x=0.52, fus_y=NOSE - 5.60, fus_z=0.24, fus_r=0.44,
                       wing_y=WING_LE - 1.05, wing_span_x=3.10, wing_z=0.05, wing_r=0.50,
                       fin_x=0.06, fin_y=TAIL + 1.10, fin_z=1.15, fin_r=0.40)

    # ---------------------------------------------------------------- gear sized to the height gate
    z_top = _z_max()
    z_ground = z_top - HEIGHT
    z_pivot = -0.50
    gear_len = z_pivot - WHEEL_R - z_ground
    gl = kit.gear_leg("GearL", TRACK * 0.5, WING_LE - 0.45, z_pivot, gear_len, WHEEL_R)
    gr = kit.gear_leg("GearR", -TRACK * 0.5, WING_LE - 0.45, z_pivot, gear_len, WHEEL_R)
    tw = kit.tailwheel("TailWheel", TAIL + 1.05, -0.06, strut=0.46, r=0.17)

    body = kit.build_body([fus, wing, tail, fin, canopy, prop, pilot, chin, oil, ex_l, ex_r,
                           dec, gl, gr, tw] + frames + guns)

    kit.refine_all(cuts=CUTS)
    kit.empty("CockpitEye", EYE)
    kit.empty("CockpitMount", EYE)
    kit.empty("MuzzleL", (2.62, WING_LE - 0.25, _wing_z(2.62)))
    kit.empty("MuzzleR", (-2.62, WING_LE - 0.25, _wing_z(2.62)))

    _accuracy()


def _wing_z(x):
    """Wing z at half-span x, interpolated from the authored gull table (used to seat the cannon)."""
    pts = GULL
    for i in range(len(pts) - 1):
        x0, z0 = pts[i]
        x1, z1 = pts[i + 1]
        if x0 <= x <= x1:
            return z0 + (z1 - z0) * (x - x0) / (x1 - x0)
    return pts[-1][1]

"""Hawker Tempest Mk V - 1:1 airframe from published figures.

Published (each with its source URL in tools/models/data/tempest.md):
  length 10.26 m (33 ft 8 in), span 12.49 m (41 ft 0 in), height 4.52 m (14 ft 10 in, tail in the
  rigging/level position with one propeller blade vertical - 4.90 m / 16 ft 1 in tail-down),
  wing area 28.1 m2 (302 sq ft), 4-blade de Havilland Hydromatic 4.27 m (14 ft 0 in) dia prop,
  main-wheel track 4.53 m (14 ft 11 in), main wheel 0.86 m (34 in) dia, 4 x 20 mm Hispano Mk V
  cannon in the wings, Napier Sabre IIB H-24 with the chin radiator.

Frame: origin at the CG station, nose toward +Y, up +Z, right +X (the glTF export maps that onto
Godot's -Z forward).  Original geometry only - every station below is authored here.
"""
import math

import bpy
import kit

ID = "tempest"
LEN = 10.26
SPAN = 12.49
HEIGHT = 4.52
AREA = 28.1

HALF = SPAN * 0.5                 # 6.245
ROOT_CHORD = 3.05
TIP_CHORD = 1.45
Z_ROOT = -0.30
SPINNER_R = 0.36
PROP_R = 2.135                    # 14 ft 0 in / 2
WHEEL_R = 0.43                    # 34 in tyre
TRACK = 4.53

WING_LE = 1.00
NOSE = WING_LE + 2.90             # 3.90: spinner tip
TAIL = NOSE - LEN                 # -6.36
TAIL_TOP = 0.38
FIN_LE = TAIL + 2.41
TAILPLANE_Y = TAIL + 1.70
EYE = (0.0, NOSE - 3.70, 0.95)     # above the deck (0.88), inside the canopy (1.055)

N_FUS = 32
N_WING = 22
N_TAIL = 18
N_FIN = 20
N_CAN = 24
N_PROP = 10
CUTS = 1

# (half_span_x, z_offset): the Tempest's thinner laminar wing keeps a flatter centre section and
# picks up its dihedral outboard of the (inward-retracting) main gear.
GULL = [(0.34, -0.30), (1.10, -0.32), (2.30, -0.34), (3.10, -0.30), (3.90, -0.18),
        (4.80, 0.00), (5.60, 0.16), (HALF, 0.26)]


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
        tip = kit.box("BladeTip%d" % i, (blade_chord * 0.72, 0.05, 0.15),
                      loc=(0.0, dy, radius - 0.075), rot=(0.0, math.degrees(a), 0.0))
        kit.parent_to(tip, grp)
    disc = kit.disc("PropDisc", 0.0, 0.0, 0.0, radius, n=28)
    disc.location = (0.0, dy, 0.0)
    kit.parent_to(disc, prop)
    return prop


def _wing_z(x):
    pts = GULL
    for i in range(len(pts) - 1):
        x0, z0 = pts[i]
        x1, z1 = pts[i + 1]
        if x0 <= x <= x1:
            return z0 + (z1 - z0) * (x - x0) / (x1 - x0)
    return pts[-1][1]


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
    # ---------------------------------------------------------------- fuselage (long Sabre nose)
    fus = kit.tube("Fuselage", [
        (NOSE - 0.02, 0.13, 0.15, 0.00),
        (NOSE - 0.45, 0.35, 0.40, 0.00),      # cowling
        (NOSE - 1.00, 0.47, 0.54, 0.02),
        (NOSE - 1.60, 0.51, 0.62, 0.04),
        (NOSE - 2.20, 0.53, 0.68, 0.06),      # firewall
        (NOSE - 2.80, 0.54, 0.72, 0.09),      # windscreen base
        (NOSE - 3.50, 0.54, 0.74, 0.12),      # cockpit
        (NOSE - 4.20, 0.51, 0.72, 0.16),
        (NOSE - 4.95, 0.45, 0.66, 0.20),      # aft cockpit / spine
        (NOSE - 5.75, 0.37, 0.56, 0.24),
        (NOSE - 6.55, 0.28, 0.46, 0.28),
        (NOSE - 7.35, 0.20, 0.36, 0.31),
        (NOSE - 8.15, 0.14, 0.27, 0.33),
        (NOSE - 8.95, 0.09, 0.19, 0.35),
        (NOSE - 9.65, 0.06, 0.13, 0.36),
        (TAIL, 0.035, 0.06, TAIL_TOP),
    ], n=N_FUS, power=2.7)

    # ---------------------------------------------------------------- wing (thin laminar plan-form)
    xs = [0.34, 1.10, 2.30, 3.10, 3.90, 4.80, 5.60, HALF]
    xz = dict(GULL)
    secs = []
    for x in xs:
        t = x / HALF
        ch = ROOT_CHORD - (ROOT_CHORD - TIP_CHORD) * t
        if t > 0.94:
            ch *= 0.80
        ring = kit.airfoil_ring(0.145 - 0.030 * t, 0.022, N_WING)
        secs.append([(x, WING_LE - ch * fx, xz[x] + fz * ch) for (fx, fz) in ring])
    wing = _surface("Wing", secs)

    # ---------------------------------------------------------------- tailplane + fin
    txs = [0.26, 0.76, 1.26, 1.68, 1.98, 2.14]
    tsec = []
    for x in txs:
        t = x / 2.14
        ch = 1.62 - 0.66 * t
        ring = kit.airfoil_ring(0.11 - 0.02 * t, 0.0, N_TAIL)
        tsec.append([(x, TAILPLANE_Y - 0.05 * x - ch * fx, 0.24 + 0.14 * t + fz * ch) for (fx, fz) in ring])
    tail = _surface("Tailplane", tsec)

    fin = kit.fin("Fin", [
        (0.32, 2.40, FIN_LE, 0.11),
        (0.86, 2.30, FIN_LE - 0.04, 0.10),
        (1.32, 2.06, FIN_LE + 0.00, 0.095),
        (1.70, 1.64, FIN_LE + 0.07, 0.09),
        (1.94, 1.06, FIN_LE + 0.14, 0.085),
        (2.06, 0.50, FIN_LE + 0.20, 0.08),
    ], camber=0.03, n=N_FIN)

    # ---------------------------------------------------------------- canopy (bubble)
    canopy = kit.canopy("Canopy", [
        (NOSE - 2.75, 0.32, 0.18, 0.64),      # windscreen base
        (NOSE - 3.20, 0.38, 0.26, 0.70),
        (NOSE - 3.75, 0.40, 0.31, 0.72),      # pilot hood
        (NOSE - 4.35, 0.38, 0.29, 0.72),
        (NOSE - 4.95, 0.30, 0.22, 0.68),      # rear fairing
        (NOSE - 5.45, 0.18, 0.14, 0.62),
    ], n=N_CAN)
    frames = []
    for i, (y, hw, hh, cz) in enumerate([
            (NOSE - 2.75, 0.32, 0.18, 0.64), (NOSE - 3.75, 0.40, 0.31, 0.72),
            (NOSE - 4.95, 0.30, 0.22, 0.68)]):
        frames.append(kit.box("CanopyFrameTop%d" % i, (hw * 2.1, 0.05, 0.05), loc=(0.0, y, cz + hh)))
        frames.append(kit.box("CanopyFrameL%d" % i, (0.05, 0.05, hh * 1.9), loc=(hw, y, cz)))
        frames.append(kit.box("CanopyFrameR%d" % i, (0.05, 0.05, hh * 1.9), loc=(-hw, y, cz)))

    # ---------------------------------------------------------------- engine, prop, crew
    prop = _prop(NOSE - SPINNER_R * 1.15, PROP_R, 4, SPINNER_R, 0.40)
    pilot = kit.pilot(EYE)

    # ---------------------------------------------------------------- chin radiator, exhausts, cannon
    chin = kit.radiator("ChinRadiator", 0.0, NOSE - 1.40, -0.78, 1.00, 0.78, 1.45)
    oil = kit.radiator("OilCooler", 0.0, NOSE - 2.55, -0.62, 0.48, 0.24, 0.42)
    ex_l = kit.exhaust_bank("ExhaustL", 0.54, NOSE - 1.85, 0.32, stacks=6, spacing=0.19, r=0.055)
    ex_r = kit.exhaust_bank("ExhaustR", -0.54, NOSE - 1.85, 0.32, stacks=6, spacing=0.19, r=0.055)
    guns = []
    for s in (1, -1):
        for k, gx in enumerate((1.60, 2.80)):
            gz = _wing_z(gx)
            guns.append(kit.box("Cannon%d_%d" % (s, k), (0.09, 1.20, 0.09),
                                loc=(s * gx, WING_LE - 0.55, gz)))
            guns.append(kit.cylinder("GunBarrel%d_%d" % (s, k), 0.045, 0.045, 0.60,
                                     loc=(s * gx, WING_LE - 0.28, gz), rot=(90, 0, 0), n=10))

    dec = kit.markings("RAF", fus_x=0.53, fus_y=NOSE - 6.05, fus_z=0.26, fus_r=0.44,
                       wing_y=WING_LE - 1.10, wing_span_x=3.20, wing_z=0.06, wing_r=0.50,
                       fin_x=0.06, fin_y=TAIL + 1.20, fin_z=1.20, fin_r=0.40)

    # ---------------------------------------------------------------- gear sized to the height gate
    z_top = _z_max()
    z_ground = z_top - HEIGHT
    z_pivot = -0.52
    gear_len = z_pivot - WHEEL_R - z_ground
    gl = kit.gear_leg("GearL", TRACK * 0.5, WING_LE - 0.50, z_pivot, gear_len, WHEEL_R)
    gr = kit.gear_leg("GearR", -TRACK * 0.5, WING_LE - 0.50, z_pivot, gear_len, WHEEL_R)
    tw = kit.tailwheel("TailWheel", TAIL + 1.10, -0.08, strut=0.50, r=0.18)

    body = kit.build_body([fus, wing, tail, fin, canopy, prop, pilot, chin, oil, ex_l, ex_r,
                           dec, gl, gr, tw] + frames + guns)

    kit.refine_all(cuts=CUTS)
    kit.empty("CockpitEye", EYE)
    kit.empty("CockpitMount", EYE)
    kit.empty("MuzzleL", (2.80, WING_LE - 0.28, _wing_z(2.80)))
    kit.empty("MuzzleR", (-2.80, WING_LE - 0.28, _wing_z(2.80)))

    _accuracy()

"""Boulton Paul Defiant Mk I - 1:1 airframe from published figures.

Published (each with its source URL in tools/models/data/defiant.md):
  length 10.77 m (35 ft 4 in), span 11.99 m (39 ft 4 in), height 3.45 m (11 ft 4 in),
  wing area 23.23 m2 (250 sq ft), 3-blade constant-speed prop ~3.35 m (11 ft 0 in) dia,
  main-wheel track ~2.36 m, main wheel 0.80 m (31.5 in Dunlop) dia, 4 x .303 in Browning in a
  hydraulically driven dorsal turret (the Defiant carried no fixed forward-firing guns).

Frame: origin at the CG station, nose toward +Y, up +Z, right +X (the glTF export maps that onto
Godot's -Z forward).  Original geometry only - every station below is authored here.
"""
import math

import bpy
import kit

ID = "defiant"
LEN = 10.77
SPAN = 11.99
HEIGHT = 3.45
AREA = 23.23

HALF = SPAN * 0.5                 # 5.995
ROOT_CHORD = 2.66
TIP_CHORD = 1.22
Z_ROOT = -0.26
DIA_RISE = 0.42
SPINNER_R = 0.30
PROP_R = 1.675                    # ~11 ft 0 in / 2
WHEEL_R = 0.40                    # 31.5 in tyre
TRACK = 2.36

WING_LE = 0.85
NOSE = WING_LE + 2.45             # 3.30: spinner tip
TAIL = NOSE - LEN                 # -7.47
TAIL_TOP = 0.32
FIN_LE = TAIL + 1.90
TAILPLANE_Y = TAIL + 1.50
EYE = (0.0, NOSE - 3.55, 0.81)    # pilot's eye, front cockpit: above the deck (0.74), inside the canopy (0.842)
TURRET_Y = NOSE - 4.95            # dorsal turret ring

N_FUS = 32
N_WING = 22
N_TAIL = 18
N_FIN = 18
N_CAN = 24
N_PROP = 10
CUTS = 1


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
        th = 0.18 - 0.075 * t
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
        tip = kit.box("BladeTip%d" % i, (blade_chord * 0.72, 0.05, 0.13),
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
    # ---------------------------------------------------------------- fuselage (deep two-seat spine)
    fus = kit.tube("Fuselage", [
        (NOSE - 0.02, 0.11, 0.13, 0.00),
        (NOSE - 0.40, 0.31, 0.34, 0.00),      # Merlin cowling
        (NOSE - 0.90, 0.41, 0.46, 0.02),
        (NOSE - 1.40, 0.45, 0.52, 0.04),
        (NOSE - 1.90, 0.47, 0.57, 0.06),      # firewall
        (NOSE - 2.40, 0.48, 0.60, 0.08),      # windscreen base
        (NOSE - 3.00, 0.48, 0.62, 0.10),      # pilot cockpit
        (NOSE - 3.60, 0.47, 0.62, 0.12),      # gunner
        (NOSE - 4.20, 0.45, 0.60, 0.14),
        (NOSE - 4.85, 0.40, 0.55, 0.17),      # radiator bay / aft fuselage
        (NOSE - 5.55, 0.34, 0.47, 0.20),
        (NOSE - 6.25, 0.27, 0.39, 0.23),
        (NOSE - 6.95, 0.20, 0.31, 0.26),
        (NOSE - 7.65, 0.14, 0.24, 0.28),
        (NOSE - 8.35, 0.09, 0.17, 0.30),
        (NOSE - 9.05, 0.06, 0.12, 0.31),
        (NOSE - 9.75, 0.04, 0.08, 0.32),
        (TAIL, 0.03, 0.05, TAIL_TOP),
    ], n=N_FUS, power=2.45)

    # ---------------------------------------------------------------- wing
    xs = [0.34, 0.95, 1.65, 2.40, 3.20, 4.00, 4.75, 5.35, 5.75, HALF]
    secs = []
    for x in xs:
        t = x / HALF
        ch = ROOT_CHORD - (ROOT_CHORD - TIP_CHORD) * t
        if t > 0.90:
            ch *= 0.72
        ring = kit.airfoil_ring(0.150 - 0.032 * t, 0.024, N_WING)
        secs.append([(x, WING_LE - ch * fx, Z_ROOT + DIA_RISE * t + fz * ch) for (fx, fz) in ring])
    wing = _surface("Wing", secs)

    # ---------------------------------------------------------------- tailplane + fin
    txs = [0.22, 0.64, 1.06, 1.40, 1.62, 1.74]
    tsec = []
    for x in txs:
        t = x / 1.74
        ch = 1.38 - 0.58 * t
        ring = kit.airfoil_ring(0.11 - 0.02 * t, 0.0, N_TAIL)
        tsec.append([(x, TAILPLANE_Y - 0.04 * x - ch * fx, 0.16 + 0.11 * t + fz * ch) for (fx, fz) in ring])
    tail = _surface("Tailplane", tsec)

    fin = kit.fin("Fin", [
        (0.26, 1.86, FIN_LE, 0.11),
        (0.68, 1.80, FIN_LE - 0.02, 0.10),
        (1.04, 1.62, FIN_LE + 0.02, 0.095),
        (1.34, 1.30, FIN_LE + 0.06, 0.09),
        (1.54, 0.84, FIN_LE + 0.10, 0.085),
        (1.64, 0.42, FIN_LE + 0.14, 0.08),
    ], camber=0.03, n=N_FIN)

    # ---------------------------------------------------------------- canopy (long two-seat greenhouse)
    canopy = kit.canopy("Canopy", [
        (NOSE - 2.30, 0.30, 0.16, 0.54),      # windscreen base
        (NOSE - 2.62, 0.34, 0.21, 0.58),
        (NOSE - 3.05, 0.35, 0.23, 0.59),      # pilot hood
        (NOSE - 3.55, 0.33, 0.22, 0.58),
        (NOSE - 4.05, 0.30, 0.19, 0.56),      # gunner hood
        (NOSE - 4.55, 0.22, 0.14, 0.52),      # fairing into the turret ring
    ], n=N_CAN)
    frames = []
    for i, (y, hw, hh, cz) in enumerate([
            (NOSE - 2.30, 0.30, 0.16, 0.54), (NOSE - 3.05, 0.35, 0.23, 0.59),
            (NOSE - 4.05, 0.30, 0.19, 0.56), (NOSE - 4.55, 0.22, 0.14, 0.52)]):
        frames.append(kit.box("CanopyFrameTop%d" % i, (hw * 2.1, 0.045, 0.045), loc=(0.0, y, cz + hh)))
        frames.append(kit.box("CanopyFrameL%d" % i, (0.045, 0.045, hh * 1.9), loc=(hw, y, cz)))
        frames.append(kit.box("CanopyFrameR%d" % i, (0.045, 0.045, hh * 1.9), loc=(-hw, y, cz)))

    # ---------------------------------------------------------------- engine, prop, crew, turret
    prop = _prop(NOSE - SPINNER_R * 1.15, PROP_R, 3, SPINNER_R, 0.30)
    pilot = kit.pilot(EYE)
    # the gunner's head sits in the crew ring under the turret
    gunner = kit.group("Gunner", (0.0, TURRET_Y + 0.20, 0.62))
    ghead = kit.new_mesh_object("GunnerHead", *kit.loft([
        [(math.cos(kit.TAU * i / 12) * r, y, math.sin(kit.TAU * i / 12) * r)
         for i in range(12)]
        for (y, r) in ((0.11, 0.10), (-0.04, 0.115), (-0.12, 0.09), (-0.16, 0.03))], True, True))
    kit.parent_to(ghead, gunner)
    turret = kit.turret("Turret", 0.0, TURRET_Y, 0.50, 0.72, barrels=4, length=0.92)

    # ---------------------------------------------------------------- cooling, exhausts
    rad = kit.radiator("Radiator", 0.0, NOSE - 4.55, -0.60, 0.60, 0.26, 0.66)
    oil = kit.radiator("OilCooler", 0.0, NOSE - 2.15, -0.62, 0.48, 0.22, 0.40)
    ex_l = kit.exhaust_bank("ExhaustL", 0.47, NOSE - 1.60, 0.26, stacks=6, spacing=0.17)
    ex_r = kit.exhaust_bank("ExhaustR", -0.47, NOSE - 1.60, 0.26, stacks=6, spacing=0.17)

    dec = kit.markings("RAF", fus_x=0.48, fus_y=NOSE - 5.55, fus_z=0.22, fus_r=0.40,
                       wing_y=WING_LE - 0.95, wing_span_x=3.25, wing_z=0.02, wing_r=0.44,
                       fin_x=0.05, fin_y=TAIL + 1.00, fin_z=1.00, fin_r=0.34)

    # ---------------------------------------------------------------- gear sized to the height gate
    z_top = _z_max()
    z_ground = z_top - HEIGHT
    z_pivot = -0.45
    gear_len = z_pivot - WHEEL_R - z_ground
    gl = kit.gear_leg("GearL", TRACK * 0.5, WING_LE - 0.35, z_pivot, gear_len, WHEEL_R)
    gr = kit.gear_leg("GearR", -TRACK * 0.5, WING_LE - 0.35, z_pivot, gear_len, WHEEL_R)
    tw = kit.tailwheel("TailWheel", TAIL + 0.95, -0.06, strut=0.40, r=0.15)

    body = kit.build_body([fus, wing, tail, fin, canopy, prop, pilot, gunner, turret, rad, oil,
                           ex_l, ex_r, dec, gl, gr, tw] + frames)

    kit.refine_all(cuts=CUTS)
    kit.empty("CockpitEye", EYE)
    kit.empty("CockpitMount", EYE)
    # the Defiant's only armament is the dorsal turret, so the muzzle markers sit on its Brownings
    kit.empty("MuzzleL", (0.30, TURRET_Y - 0.95, 1.15))
    kit.empty("MuzzleR", (-0.30, TURRET_Y - 0.95, 1.15))

    _accuracy()

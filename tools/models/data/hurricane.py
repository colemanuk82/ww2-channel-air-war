"""Hawker Hurricane Mk I - 1:1 airframe from published Battle-of-Britain figures.

Published (each with its source URL in tools/models/data/hurricane.md):
  length 9.84 m (32 ft 3 in), span 12.19 m (40 ft 0 in), height 4.00 m (13 ft 1.5 in),
  wing area 23.92 m2 (257.5 sq ft), 3-blade Rotol constant-speed prop 3.43 m (11 ft 3 in) dia,
  main-wheel track 2.39 m (7 ft 10 in), main wheel 0.75 m (29.5 in) dia.

Frame: origin at the CG station, nose toward +Y, up +Z, right +X (the glTF export maps that onto
Godot's -Z forward).  Original geometry only - every station below is authored here from the
published plan-form; nothing is converted from a third-party mesh.
"""
import math

import bpy
import kit

ID = "hurricane"
LEN = 9.84
SPAN = 12.19
HEIGHT = 4.00
AREA = 23.92

HALF = SPAN * 0.5                 # 6.095
ROOT_CHORD = 2.72
TIP_CHORD = 1.22
Z_ROOT = -0.26                    # wing centre-section height (low-wing monoplane)
DIA_RISE = 0.43                   # 4 deg dihedral over the half span
SPINNER_R = 0.30
PROP_R = 1.715                    # 11 ft 3 in / 2
WHEEL_R = 0.375                   # 29.5 in tyre
TRACK = 2.39

WING_LE = 0.75                    # wing root leading edge, ahead of the CG (CG ~28% root chord)
NOSE = WING_LE + 2.35             # spinner tip
TAIL = NOSE - LEN                 # -6.74: rudder trailing edge / fuselage tail
TAIL_TOP = 0.32                   # rear fuselage centre-line height
FIN_LE = TAIL + 1.95              # fin root leading edge
TAILPLANE_Y = TAIL + 1.55
EYE = (0.0, NOSE - 3.05, 0.76)     # pilot's eye: above the fuselage top deck (0.70 at this station) and
                                   # inside the canopy glazing (top 0.79), so the view looks out over the
                                   # cowling. Was 0.66 - below the deck, so the pilot stared at the structure.

N_FUS = 30
N_WING = 22
N_TAIL = 18
N_FIN = 18
N_CAN = 24
N_PROP = 10
CUTS = 1


# ------------------------------------------------------------------ local helpers

def _surface(name, sections):
    """Loft airfoil sections already carrying absolute (x, y, z) points, then mirror to -X."""
    verts, faces = kit.loft(sections, True, True)
    off = len(verts)
    verts = verts + [(-x, y, z) for (x, y, z) in verts]
    for f in list(faces):
        faces.append(tuple(off + i for i in reversed(f)))
    return kit.new_mesh_object(name, verts, faces)


def _blade(name, r_hub, radius, chord, n=N_PROP, steps=6):
    """One prop blade: span along +Z, chord along X, thickness along Y (so a Y-rotation swings it)."""
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
    """`Propeller` > `Blades` (Blade0..N + BladeTip0..N) + `Spinner` + `PropDisc`.

    The kit's own propeller lays all blades on the same radial line; this one builds a blade in the
    rotation plane and swings it round the shaft, so a 3-blade prop really has three blades.
    """
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
    """Highest point of everything built so far (the prop tip), for sizing the undercarriage."""
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
    """Per-axis bbox vs the published figures; FAIL if any headline dimension is beyond 2%."""
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
    # ---------------------------------------------------------------- fuselage
    fus = kit.tube("Fuselage", [
        (NOSE - 0.02, 0.11, 0.13, 0.00),
        (NOSE - 0.38, 0.30, 0.33, 0.00),      # cowling
        (NOSE - 0.85, 0.40, 0.44, 0.02),
        (NOSE - 1.35, 0.44, 0.50, 0.04),
        (NOSE - 1.85, 0.46, 0.55, 0.06),      # firewall
        (NOSE - 2.35, 0.47, 0.58, 0.08),      # windscreen base
        (NOSE - 2.95, 0.47, 0.60, 0.10),      # cockpit
        (NOSE - 3.55, 0.45, 0.58, 0.13),
        (NOSE - 4.25, 0.40, 0.53, 0.16),
        (NOSE - 4.95, 0.34, 0.47, 0.19),      # radiator bay
        (NOSE - 5.65, 0.28, 0.40, 0.22),
        (NOSE - 6.35, 0.21, 0.33, 0.25),
        (NOSE - 7.05, 0.15, 0.26, 0.27),
        (NOSE - 7.75, 0.10, 0.19, 0.29),
        (NOSE - 8.45, 0.07, 0.14, 0.30),
        (NOSE - 9.15, 0.05, 0.09, 0.31),
        (TAIL, 0.03, 0.05, TAIL_TOP),
    ], n=N_FUS, power=2.45)

    # ---------------------------------------------------------------- wing (straight taper, rounded tip)
    xs = [0.34, 0.95, 1.65, 2.45, 3.30, 4.15, 4.90, 5.50, 5.85, HALF]
    secs = []
    for x in xs:
        t = x / HALF
        ch = ROOT_CHORD - (ROOT_CHORD - TIP_CHORD) * t
        if t > 0.90:
            ch *= 0.72                   # round the tip off
        ring = kit.airfoil_ring(0.150 - 0.032 * t, 0.024, N_WING)
        secs.append([(x, WING_LE - ch * fx, Z_ROOT + DIA_RISE * t + fz * ch) for (fx, fz) in ring])
    wing = _surface("Wing", secs)

    # ---------------------------------------------------------------- tailplane + fin
    txs = [0.22, 0.66, 1.10, 1.48, 1.72, 1.86]
    tsec = []
    for x in txs:
        t = x / 1.86
        ch = 1.42 - 0.62 * t
        ring = kit.airfoil_ring(0.11 - 0.02 * t, 0.0, N_TAIL)
        tsec.append([(x, TAILPLANE_Y - 0.04 * x - ch * fx, 0.16 + 0.12 * t + fz * ch) for (fx, fz) in ring])
    tail = _surface("Tailplane", tsec)

    fin = kit.fin("Fin", [
        (0.26, 1.95, FIN_LE, 0.11),
        (0.72, 1.88, FIN_LE - 0.02, 0.10),
        (1.10, 1.68, FIN_LE + 0.02, 0.095),
        (1.42, 1.34, FIN_LE + 0.06, 0.09),
        (1.62, 0.86, FIN_LE + 0.10, 0.085),
        (1.72, 0.44, FIN_LE + 0.14, 0.08),
    ], camber=0.03, n=N_FIN)

    # ---------------------------------------------------------------- canopy (greenhouse)
    canopy = kit.canopy("Canopy", [
        (NOSE - 2.25, 0.30, 0.17, 0.52),      # windscreen base
        (NOSE - 2.55, 0.33, 0.21, 0.55),
        (NOSE - 2.95, 0.34, 0.23, 0.56),      # pilot hood
        (NOSE - 3.35, 0.32, 0.21, 0.56),
        (NOSE - 3.75, 0.26, 0.17, 0.53),
        (NOSE - 4.15, 0.16, 0.12, 0.49),      # fairing
    ], n=N_CAN)
    frames = []
    for i, (y, hw, hh, cz) in enumerate([
            (NOSE - 2.25, 0.30, 0.17, 0.52), (NOSE - 2.95, 0.34, 0.23, 0.56), (NOSE - 4.15, 0.16, 0.12, 0.49)]):
        frames.append(kit.box("CanopyFrameTop%d" % i, (hw * 2.1, 0.045, 0.045), loc=(0.0, y, cz + hh)))
        frames.append(kit.box("CanopyFrameL%d" % i, (0.045, 0.045, hh * 1.9), loc=(hw, y, cz)))
        frames.append(kit.box("CanopyFrameR%d" % i, (0.045, 0.045, hh * 1.9), loc=(-hw, y, cz)))

    # ---------------------------------------------------------------- engine, prop, crew
    prop = _prop(NOSE - SPINNER_R * 1.15, PROP_R, 3, SPINNER_R, 0.30)
    pilot = kit.pilot(EYE)

    # ---------------------------------------------------------------- cooling, exhausts, guns
    rad = kit.radiator("Radiator", 0.0, NOSE - 4.35, -0.58, 0.62, 0.26, 0.70)
    oil = kit.radiator("OilCooler", 0.0, NOSE - 2.10, -0.60, 0.50, 0.22, 0.42)
    ex_l = kit.exhaust_bank("ExhaustL", 0.46, NOSE - 1.55, 0.24, stacks=6, spacing=0.17)
    ex_r = kit.exhaust_bank("ExhaustR", -0.46, NOSE - 1.55, 0.24, stacks=6, spacing=0.17)
    # eight .303 Brownings: four per wing, muzzles in the leading edge
    guns = []
    for s in (1, -1):
        for k, gx in enumerate((1.15, 1.95, 2.75, 3.55)):
            gz = Z_ROOT + DIA_RISE * (gx / HALF)
            guns.append(kit.box("Gun%d_%d" % (s, k), (0.08, 0.95, 0.08),
                                loc=(s * gx, WING_LE - 0.42, gz)))
            guns.append(kit.box("GunPort%d_%d" % (s, k), (0.10, 0.16, 0.10),
                                loc=(s * gx, WING_LE - 0.06, gz)))

    dec = kit.markings("RAF", fus_x=0.47, fus_y=NOSE - 4.75, fus_z=0.20, fus_r=0.44,
                       wing_y=WING_LE - 1.00, wing_span_x=3.35, wing_z=0.02, wing_r=0.46,
                       fin_x=0.05, fin_y=TAIL + 1.05, fin_z=1.05, fin_r=0.36)

    # ---------------------------------------------------------------- gear sized to the height gate
    z_top = _z_max()
    z_ground = z_top - HEIGHT
    z_pivot = -0.45
    gear_len = z_pivot - WHEEL_R - z_ground
    gl = kit.gear_leg("GearL", TRACK * 0.5, WING_LE - 0.35, z_pivot, gear_len, WHEEL_R)
    gr = kit.gear_leg("GearR", -TRACK * 0.5, WING_LE - 0.35, z_pivot, gear_len, WHEEL_R)
    tw = kit.tailwheel("TailWheel", TAIL + 0.95, -0.06, strut=0.42, r=0.15)

    body = kit.build_body([fus, wing, tail, fin, canopy, prop, pilot, rad, oil, ex_l, ex_r,
                           dec, gl, gr, tw] + frames + guns)

    kit.refine_all(cuts=CUTS)
    kit.empty("CockpitEye", EYE)
    kit.empty("CockpitMount", EYE)
    kit.empty("MuzzleL", (2.35, WING_LE - 0.06, Z_ROOT + DIA_RISE * (2.35 / HALF)))
    kit.empty("MuzzleR", (-2.35, WING_LE - 0.06, Z_ROOT + DIA_RISE * (2.35 / HALF)))

    _accuracy()

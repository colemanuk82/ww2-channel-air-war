"""Supermarine Spitfire Mk I - 1:1 airframe from published Type 300 / Merlin III figures.

Length 9.12 m, span 11.23 m, height 3.86 m, wing area 22.48 m2, 3-blade 11 ft 3 in prop (3.43 m dia),
track 1.78 m, wheels 0.67 m dia, dihedral 6 deg, wing root chord 2.55 m, tip chord ~0.85 m (elliptical).

Frame: origin at the CG station, nose toward +Y, up +Z, right +X (glTF maps that onto Godot's -Z forward).
The CG sits 0.79 m behind the wing root leading edge (31% of the root chord), and the spinner sits 2.20 m
ahead of the wing root LE - those two measurements fix every station below.
"""
import math
import kit

LEN = 9.12
SPAN = 11.23
EXPECT = (LEN, SPAN)
HEIGHT_INFO = 3.86

WING_LE = 0.79                 # wing root leading edge, ahead of the CG
ROOT_CHORD = 2.55
SEMI_CHORD = 1.27              # ellipse semi-chord: pi * 5.615 * 1.27 = 22.4 m2, i.e. the real wing area
SPINNER_Y = WING_LE + 2.20     # +2.99
TAIL_Y = SPINNER_Y - LEN       # -6.13
HALF = SPAN * 0.5              # 5.615
TAILPLANE_Y = WING_LE - 4.55
FIN_LE_Y = WING_LE - 4.42
EYE = (0.0, -0.35, 0.70)       # pilot's eye: 1.14 m behind the wing root LE, 0.70 m above the CG line


def build():
    # ---------------------------------------------------------------- fuselage
    # Merlin cowling (deep, flat-sided, top line straight) -> deepest at the cockpit -> long tapering spine
    fus = kit.tube("Fuselage", [
        (SPINNER_Y - 0.24, 0.17, 0.20, 0.03),
        (SPINNER_Y - 0.52, 0.33, 0.36, 0.06),
        (SPINNER_Y - 0.86, 0.41, 0.45, 0.09),   # the Merlin cowl is plump within 0.9 m of the spinner
        (SPINNER_Y - 1.30, 0.44, 0.49, 0.10),
        (SPINNER_Y - 1.72, 0.45, 0.52, 0.10),   # front of the cowling
        (SPINNER_Y - 2.05, 0.45, 0.54, 0.09),   # firewall
        (SPINNER_Y - 2.55, 0.44, 0.56, 0.09),   # windscreen / cockpit front
        (SPINNER_Y - 3.15, 0.43, 0.56, 0.10),   # cockpit rear
        (SPINNER_Y - 3.85, 0.39, 0.52, 0.13),
        (SPINNER_Y - 4.75, 0.32, 0.44, 0.17),
        (SPINNER_Y - 5.75, 0.23, 0.34, 0.21),
        (SPINNER_Y - 6.75, 0.14, 0.23, 0.25),
        (SPINNER_Y - 7.70, 0.08, 0.14, 0.28),
        (TAIL_Y, 0.035, 0.06, 0.29),
    ], n=32, power=2.5)

    # ---------------------------------------------------------------- wing (elliptical)
    # Two semi-ellipses on a common major axis at the spar (31.5% of the root chord - the main spar ran
    # there). The leading-edge semi-ellipse has the small minor axis (FRONT), the trailing-edge one the large
    # (REAR): equal front/rear would make both edges curve alike and the wing read as a leaf, not a Spitfire.
    A_FRONT = 0.315 * ROOT_CHORD        # 0.80 m of ellipse ahead of the spar
    A_REAR = 0.685 * ROOT_CHORD         # 1.74 m behind it
    st = []
    for t in (0.0, 0.12, 0.25, 0.38, 0.50, 0.62, 0.72, 0.80, 0.87, 0.925, 0.965, 0.99, 0.999):
        ell = math.sqrt(max(0.0, 1.0 - t * t))
        chord = max(0.16, (A_FRONT + A_REAR) * ell)     # elliptical chord distribution = elliptical area
        le = A_FRONT * (1.0 - ell)                      # nearly straight LE: sqrt tapers only slowly
        zoff = -0.26 + 0.60 * t                         # 6 deg dihedral over the half span
        twist = -2.5 * t * t                            # washout at the tip (tip stalls last)
        st.append((HALF * t, chord, twist, zoff, 0.130 - 0.068 * t, le))
    wing = kit.surface("Wing", st, camber=0.02, n=22)
    wing.location = (0.0, WING_LE, 0.0)

    # ---------------------------------------------------------------- tailplane + fin
    tail = kit.surface("Tailplane", [
        (0.10, 1.24, 0.0, 0.10, 0.10),
        (0.62, 1.06, 0.0, 0.16, 0.09),
        (1.06, 0.78, 0.0, 0.22, 0.09),
        (1.30, 0.42, 0.0, 0.26, 0.08),
    ], camber=0.0, n=16)
    tail.location = (0.0, TAILPLANE_Y, 0.10)

    # the fin + rudder: rounded, raked leading edge, chord shrinking to the rounded tip
    fin = kit.fin("Fin", [
        (0.24, 2.02, FIN_LE_Y - 0.10, 0.10),     # broad root: fin + rudder together
        (0.66, 1.96, FIN_LE_Y - 0.20, 0.095),
        (1.04, 1.86, FIN_LE_Y - 0.36, 0.09),
        (1.34, 1.66, FIN_LE_Y - 0.52, 0.085),
        (1.56, 1.34, FIN_LE_Y - 0.66, 0.08),
        (1.72, 0.96, FIN_LE_Y - 0.80, 0.075),    # rounded top, not a sharp corner
        (1.82, 0.52, FIN_LE_Y - 0.90, 0.07),
    ], camber=0.04, n=20)

    # ---------------------------------------------------------------- canopy (greenhouse with framing)
    # cz sits on the fuselage spine (the tube's top line is ~0.62 there) so the glazing clears the skin
    stations = [
        (SPINNER_Y - 2.30, 0.27, 0.19, 0.52),   # windscreen base
        (SPINNER_Y - 2.62, 0.30, 0.23, 0.56),
        (SPINNER_Y - 3.00, 0.31, 0.24, 0.58),   # pilot's hood
        (SPINNER_Y - 3.45, 0.29, 0.23, 0.58),
        (SPINNER_Y - 3.85, 0.23, 0.18, 0.56),   # rear hood
        (SPINNER_Y - 4.25, 0.14, 0.12, 0.53),   # fairing
    ]
    canopy = kit.canopy("Canopy", stations, n=24)
    frames = []
    for i, (y, hw, hh, cz) in enumerate(stations):
        frames.append(kit.box("CanopyFrameTop%d" % i, (hw * 2.1, 0.05, 0.05), loc=(0.0, y, cz + hh)))
        frames.append(kit.box("CanopyFrameL%d" % i, (0.05, 0.05, hh * 1.9), loc=(hw, y, cz + hh * 0.05)))
        frames.append(kit.box("CanopyFrameR%d" % i, (0.05, 0.05, hh * 1.9), loc=(-hw, y, cz + hh * 0.05)))
    windscreen = kit.box("WindscreenFrame", (0.62, 0.06, 0.30), loc=(0.0, SPINNER_Y - 2.42, 0.44))

    # ---------------------------------------------------------------- engine, prop, cockpit, gear
    # the spinner cone reaches 0.36 m ahead of the prop disc, so this puts the spinner TIP exactly on
    # SPINNER_Y - which is what makes the overall length measure 9.12 m
    prop = kit.propeller(SPINNER_Y - 0.36, radius=1.72, blades=3, spinner_r=0.33, blade_chord=0.30)
    pilot = kit.pilot(EYE)
    gl = kit.gear_leg("GearL", 0.89, WING_LE - 0.28, -0.26, 1.22, 0.34)
    gr = kit.gear_leg("GearR", -0.89, WING_LE - 0.28, -0.26, 1.22, 0.34)
    tail_w = kit.tailwheel("TailWheel", TAILPLANE_Y - 0.62, -0.02)

    # under-wing cooling: the starboard radiator and the port oil cooler
    rad = kit.radiator("Radiator", 1.95, WING_LE - 0.95, -0.62, 0.98, 0.24, 0.62)
    oil = kit.radiator("OilCooler", -1.20, WING_LE - 0.90, -0.60, 0.60, 0.22, 0.52)
    ex_l = kit.exhaust_bank("ExhaustL", 0.42, SPINNER_Y - 1.45, 0.20, stacks=6, spacing=0.185)
    ex_r = kit.exhaust_bank("ExhaustR", -0.42, SPINNER_Y - 1.45, 0.20, stacks=6, spacing=0.185)
    # eight .303 Brownings in the wings: barrel fairings + the muzzle reference the gunsight aims from
    guns = []
    for side in (1, -1):
        for k, gx in enumerate((2.05, 2.62)):
            guns.append(kit.box("Gun%d_%d" % (side, k), (0.075, 0.85, 0.075),
                                loc=(side * gx, WING_LE - 0.55, -0.22)))

    dec = kit.markings("RAF", fus_x=0.43, fus_y=SPINNER_Y - 4.60, fus_z=0.16, fus_r=0.42,
                       wing_y=WING_LE - 0.95, wing_span_x=3.45, wing_z=0.16, wing_r=0.44,
                       fin_x=0.05, fin_y=FIN_LE_Y - 0.55, fin_z=1.05, fin_r=0.38)

    body = kit.build_body([fus, wing, tail, fin, canopy, windscreen, prop, pilot, gl, gr, tail_w,
                           rad, oil, ex_l, ex_r, dec] + frames + guns)

    # ---------------------------------------------------------------- poly budget + contract nodes
    kit.refine_all(cuts=1)
    kit.empty("CockpitEye", EYE)
    kit.empty("CockpitMount", EYE)
    kit.empty("MuzzleL", (2.35, WING_LE - 0.55, -0.22))
    kit.empty("MuzzleR", (-2.35, WING_LE - 0.55, -0.22))

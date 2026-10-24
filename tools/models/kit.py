"""Geometry kit for the WW2 Channel Air War aircraft models (Blender 5.x, headless).

Run through:  blender --background --python tools/models/build_all.py -- <id> [<id> ...]

Conventions (must match the Godot model contract):
  * metres, **nose toward +Y**, up +Z, right +X.  The glTF export maps Blender (x, y, z) -> glTF (x, z, -y),
    so the nose lands on Godot's -Z (see scripts/aircraft_models.gd: "faces -Z").
  * the model is built around y = 0 with the spinner at the most negative... no: nose at +Y means the model
    extends from y = -tail to y = +nose; the caller passes `length` and the kit centres nothing - keep the
    origin at the centre of gravity station the spec already uses (AircraftStats.cg is not used, the model
    origin is where the Aircraft node sits, so the origin is the CG).
  * every part is its own named mesh object so the Godot rewire (scripts/models/gltf_models.gd) can assign
    the toon materials by name, and the contract nodes are named exactly:
      Body (group), Fuselage, Wing, Tailplane, Fin, Canopy (glass - hidden in cockpit view), CanopyFrame,
      Pilot, Propeller > Blades + Spinner + PropDisc, GearL, GearR, MuzzleL, MuzzleR, CockpitEye.

Everything here is deterministic: no random noise, so a rebuild is byte-identical.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

TAU = math.pi * 2.0
_SKIN_CACHE = {}


# ------------------------------------------------------------------ mesh plumbing

def new_mesh_object(name, verts, faces, smooth=True):
    """Create an object from raw verts/faces. `verts` are (x, y, z) tuples."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.update()
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def empty(name, loc=(0.0, 0.0, 0.0), parent=None, size=0.3):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = size
    e.location = loc
    bpy.context.scene.collection.objects.link(e)
    if parent is not None:
        e.parent = parent
    return e


def group(name, loc=(0.0, 0.0, 0.0), parent=None):
    """An empty used purely as a named group node (Body, Blades, ...)."""
    return empty(name, loc, parent)


def parent_to(child, parent):
    child.parent = parent
    return child


def tri_count(ob):
    me = ob.data
    return sum(len(p.vertices) - 2 for p in me.polygons)


def model_tris():
    return sum(tri_count(o) for o in bpy.data.objects if o.type == 'MESH')


# ------------------------------------------------------------------ cross sections

def superellipse(n, hw, hh, power=2.4):
    """A ring of n points: a rounded-rectangle-ish fuselage cross-section (power 2 = ellipse)."""
    pts = []
    for i in range(n):
        a = TAU * i / n
        c, s = math.cos(a), math.sin(a)
        x = math.copysign(abs(c) ** (2.0 / power), c) * hw
        z = math.copysign(abs(s) ** (2.0 / power), s) * hh
        pts.append((x, z))
    return pts


def naca_4digit(thickness=0.15, camber=0.02, camber_pos=0.4, n=14):
    """Half-cosine sampled NACA-4 style profile: returns [(x, yt_upper, yt_lower)] over chord 0..1."""
    def yt(x):
        return 5.0 * thickness * (0.2969 * math.sqrt(x) - 0.1260 * x - 0.3516 * x * x
                                  + 0.2843 * x ** 3 - 0.1015 * x ** 4)

    def yc(x):
        if camber <= 0.0:
            return 0.0, 0.0
        if x < camber_pos:
            return camber / camber_pos ** 2 * (2 * camber_pos * x - x * x), \
                   2 * camber / camber_pos ** 2 * (camber_pos - x)
        return camber / (1 - camber_pos) ** 2 * ((1 - 2 * camber_pos) + 2 * camber_pos * x - x * x), \
               2 * camber / (1 - camber_pos) ** 2 * (camber_pos - x)

    out = []
    for i in range(n + 1):
        t = 0.5 - 0.5 * math.cos(math.pi * i / n)
        x = max(t, 1e-4)
        c, _ = yc(x)
        th = yt(x)
        out.append((x, c + th, c - th))
    return out


def airfoil_ring(thickness=0.15, camber=0.02, n=14):
    """A closed loop of (x, z) profile points: upper surface nose->tail then lower surface tail->nose."""
    prof = naca_4digit(thickness, camber, 0.4, n)
    upper = [(x, z) for (x, zu, zl) in prof for z in (zu,)]
    lower = [(x, z) for (x, zu, zl) in reversed(prof) for z in (zl,)]
    return upper + lower[1:-1]


def ring_xyz(ring, y, cx=0.0, cz=0.0, scale=1.0, twist=0.0):
    """Place a 2D (x, z) ring on the plane y = const, optionally scaled / rotated about X (twist, degrees)."""
    out = []
    tr = math.radians(twist)
    ct, st = math.cos(tr), math.sin(tr)
    for (x, z) in ring:
        sx, sz = x * scale, z * scale
        rx = ct * sx - st * sz
        rz = st * sx + ct * sz
        out.append((cx + rx, y, cz + rz))
    return out


def loft(sections, cap_start=True, cap_end=True):
    """Stitch equal-length rings into a tube. Returns (verts, faces)."""
    verts, faces = [], []
    n = len(sections[0])
    for s in sections:
        assert len(s) == n, "loft sections must have the same vertex count"
        verts.extend(s)
    for k in range(len(sections) - 1):
        a = k * n
        b = (k + 1) * n
        for i in range(n):
            j = (i + 1) % n
            faces.append((a + i, a + j, b + j, b + i))
    if cap_start:
        faces.append(tuple(range(n - 1, -1, -1)))
    if cap_end:
        base = (len(sections) - 1) * n
        faces.append(tuple(range(base, base + n)))
    return verts, faces


def tube(name, stations, n=16, power=2.4, cap_start=True, cap_end=True):
    """`stations` = [(y, hw, hh, cz), ...] nose -> tail: a lofted fuselage. cz lifts the section centre."""
    secs = []
    for (y, hw, hh, cz) in stations:
        hw = max(hw, 0.004)
        hh = max(hh, 0.004)
        ring = superellipse(n, hw, hh, power)
        secs.append([(x, y, cz + z) for (x, z) in ring])
    v, f = loft(secs, cap_start, cap_end)
    return new_mesh_object(name, v, f)


def plate(name, y, hw, hz, cy=0.0, cz=0.0, n=12, thickness=0.02):
    """A flat horizontal plate in the XZ sense - used for the prop blur disc."""
    secs = []
    for dy in (-thickness * 0.5, thickness * 0.5):
        ring = superellipse(n, hw, hz, 2.0)
        secs.append([(x, y + dy, cy + z) for (x, z) in ring])
    v, f = loft(secs, True, True)
    return new_mesh_object(name, v, f)


# ------------------------------------------------------------------ wings and tails

def surface(name, stations, thickness=0.15, camber=0.02, n=12, mirror=True):
    """`stations` = [(half_span_x, chord, twist_deg, z_offset, thickness_ratio), ...] root -> tip.

    A wing half: airfoil sections laid out along +X with the leading edge at y = le(y) and z = z_offset,
    then mirrored to -X (the two halves meet at the centre).
    """
    profs = []
    for st in stations:
        x, chord, twist, zoff, th = st[0], st[1], st[2], st[3], st[4]
        le = st[5] if len(st) > 5 else 0.0      # leading-edge offset in Y: an ellipse curves BOTH edges
        ring = airfoil_ring(th if th > 0.0 else thickness, camber, n)
        # airfoil x is chord fraction: 1.0 = trailing edge, so the point sits at y = le - chord * x.
        # `twist` rotates the section about its quarter-chord point (washout: the tip sits at less incidence)
        ang = math.radians(twist)
        ca, sa = math.cos(ang), math.sin(ang)
        pts = []
        for (fx, fz) in ring:
            ry = -chord * (fx - 0.25)
            rz = fz * chord
            pts.append((x, le - 0.25 * chord + (ry * ca - rz * sa), zoff + (ry * sa + rz * ca)))
        profs.append(pts)
    verts, faces = [], []
    m = len(profs[0])
    for p in profs:
        verts.extend(p)
    for k in range(len(profs) - 1):
        a, b = k * m, (k + 1) * m
        for i in range(m):
            j = (i + 1) % m
            faces.append((a + i, a + j, b + j, b + i))
    faces.append(tuple(range(m - 1, -1, -1)))
    base = (len(profs) - 1) * m
    faces.append(tuple(range(base, base + m)))
    if mirror:
        off = len(verts)
        verts.extend([(-x, y, z) for (x, y, z) in verts[:off]])
        for f in list(faces):
            faces.append(tuple(off + i for i in reversed(f)))
    return new_mesh_object(name, verts, faces)


def box(name, size, loc=(0, 0, 0), rot=(0, 0, 0)):
    sx, sy, sz = (s * 0.5 for s in size)
    v = [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, sy, -sz), (-sx, sy, -sz),
         (-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz)]
    f = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    ob = new_mesh_object(name, v, f, smooth=False)
    ob.location = loc
    ob.rotation_euler = tuple(math.radians(a) for a in rot)
    return ob


def cylinder(name, r0, r1, length, loc=(0, 0, 0), rot=(0, 0, 0), n=14):
    """A capped cylinder along local +Z (rotate to lay it down), taper r0 (bottom) -> r1 (top)."""
    secs = []
    for (z, r) in ((-length * 0.5, r0), (length * 0.5, r1)):
        secs.append([(math.cos(TAU * i / n) * max(r, 0.002), math.sin(TAU * i / n) * max(r, 0.002), z)
                     for i in range(n)])
    v, f = loft(secs, True, True)
    ob = new_mesh_object(name, v, f)
    ob.location = loc
    ob.rotation_euler = tuple(math.radians(a) for a in rot)
    return ob


# ------------------------------------------------------------------ assembly helpers

def propeller(nose_y, radius, blades=3, spinner_r=0.32, blade_chord=0.28, spin=0.0):
    """The full prop group: `Propeller` > `Spinner`, `Blades` (the blades + yellow tips), `PropDisc`.

    The disc lies in the XZ plane at the nose and is the fast-spin blur (Aircraft keeps it hidden until the
    blades are too fast to draw - see AircraftModels.prop_blur).
    """
    prop = empty("Propeller", (0.0, nose_y, 0.0))
    spinner = cylinder("Spinner", spinner_r * 0.95, 0.04, spinner_r * 2.2, loc=(0, 0.0, 0), rot=(90, 0, 0), n=16)
    parent_to(spinner, prop)

    blades_grp = group("Blades", (0, 0, 0), prop)
    for i in range(blades):
        a = TAU * i / blades + math.radians(spin)
        # pitch twist: without it the blade sections lie flat in the disc plane and the prop renders
        # edge-on as an invisible sliver
        b = new_mesh_object("Blade%d" % i, *loft([
            ring_xyz(airfoil_ring(0.20, 0.06, 10), -spinner_r * 0.6, scale=blade_chord * 0.5, twist=-30.0),
            ring_xyz(airfoil_ring(0.15, 0.05, 10), -radius * 0.55, scale=blade_chord * 0.8, twist=-22.0),
            ring_xyz(airfoil_ring(0.11, 0.04, 10), -radius, scale=blade_chord * 0.55, twist=-14.0),
        ], cap_start=True, cap_end=True))
        # stand the blade radial (Rx) then swing it round the prop axis, which is Y (Ry); a Z rotation
        # here would spin each blade about the very axis it points along and leave them all stacked
        b.rotation_euler = (math.radians(90.0), a, 0.0)
        parent_to(b, blades_grp)
        tip = box("BladeTip%d" % i, (blade_chord * 0.45, 0.12, 0.20), loc=(0, 0, -radius + 0.07))
        tip.rotation_euler = (math.radians(90.0), a, 0.0)
        parent_to(tip, blades_grp)

    disc = plate("PropDisc", 0.0, radius, radius, n=24, thickness=0.02)
    parent_to(disc, prop)
    disc.hide_render = False
    return prop


def canopy(name, stations, n=12, glass_extra=0.0):
    """`stations` = [(y, hw, hh, cz), ...] along the cockpit - lofted glazing plus a sill frame rail."""
    glass = tube(name, stations, n=n, power=2.0, cap_start=False, cap_end=False)
    frame_v, frame_f = [], []
    for (y, hw, hh, cz) in (stations[0], stations[-1]):
        frame_v.append((hw, y, cz))
    return glass


def pilot(eye):
    """A head + shoulders + torso so there is somebody in the cockpit (tests check for a `Pilot` node)."""
    parts = []
    head = new_mesh_object("PilotHead", *loft([
        [(math.cos(TAU * i / 10) * r, y, math.sin(TAU * i / 10) * r)
         for i in range(10)]
        for (y, r) in ((0.14, 0.02), (0.10, 0.10), (-0.04, 0.115), (-0.12, 0.09), (-0.16, 0.03))
    ], True, True))
    head.location = eye
    parts.append(head)
    torso = new_mesh_object("PilotTorso", *loft([
        [(math.cos(TAU * i / 10) * w, y, math.sin(TAU * i / 10) * h)
         for i in range(10)]
        for (y, w, h) in ((0.0, 0.16, 0.14), (-0.10, 0.24, 0.18), (-0.26, 0.26, 0.2), (-0.34, 0.2, 0.16))
    ], True, True))
    torso.location = (eye[0], eye[1] - 0.20, eye[2] - 0.42)
    parts.append(torso)
    grp = group("Pilot", eye)
    for p in parts:
        parent_to(p, grp)
        p.location = (p.location.x - eye[0], p.location.y - eye[1], p.location.z - eye[2])
    return grp


def nacelle(name, y, z, r0, r1, length, cy=0.0):
    """An engine nacelle: a tapered tube along Y from the front face (y - length/2) to the rear."""
    secs = []
    n = 16
    for i in range(6):
        t = i / 5.0
        r = r0 + (r1 - r0) * t
        yy = y - length * 0.5 + length * t
        # blunt the front and pinch the back so it reads as a cowling, not a tube
        bulge = 1.0 + 0.10 * math.sin(math.pi * t)
        ring = superellipse(n, r * bulge, r * bulge * 0.92, 2.2)
        secs.append([(x, yy, cy + zz) for (x, zz) in ring])
    v, f = loft(secs, True, True)
    return new_mesh_object(name, v, f)


def turret(name, x, y, z, r, barrels=2, length=1.1):
    """A defensive turret: a glazed dome with barrels sticking out along the mount axis (see DefensiveTurrets)."""
    grp = group(name, (x, y, z))
    dome = new_mesh_object(name + "Dome", *loft([
        [(math.cos(TAU * i / 14) * rr, math.sin(TAU * i / 14) * rr, hh)
         for i in range(14)]
        for (hh, rr) in ((0.0, r), (0.45 * r, r * 0.98), (0.85 * r, r * 0.72), (1.15 * r, r * 0.30))
    ], True, True))
    parent_to(dome, grp)
    for b in range(barrels):
        off = (b - (barrels - 1) * 0.5) * r * 0.42
        bbl = cylinder(name + "Barrel%d" % b, 0.045, 0.045, length, loc=(off, 0, r * 0.9), rot=(90, 0, 0), n=8)
        parent_to(bbl, grp)
    return grp


def disc(name, y, x, z, radius, vertical=False, n=16):
    """A thin disc lying in the XZ plane (or the YZ plane when vertical) - the decal primitive."""
    secs = []
    th = 0.012
    for d in (-th, th):
        ring = [(math.cos(TAU * i / n) * radius, math.sin(TAU * i / n) * radius) for i in range(n)]
        if vertical:
            secs.append([(x + d, y + px, z + pz) for (px, pz) in ring])
        else:
            secs.append([(x + px, y + d, z + pz) for (px, pz) in ring])
    v, f = loft(secs, True, True)
    return new_mesh_object(name, v, f)


def bar(name, size, loc, rot=(0, 0, 0)):
    return box(name, size, loc, rot)


_GLYPHS = {
    "G": ("###", "#..", "#.#", "#.#", "###"), "A": (".#.", "#.#", "###", "#.#", "#.#"),
    "F": ("###", "#..", "##.", "#..", "#.."), "R": ("##.", "#.#", "##.", "#.#", "#.#"),
    "W": ("#.#", "#.#", "#.#", "###", "#.#"), "-": ("...", "...", "###", "...", "..."),
    "E": ("###", "#..", "##.", "#..", "###"), "B": ("##.", "#.#", "##.", "#.#", "##."),
    "C": ("###", "#..", "#..", "#..", "###"), "D": ("##.", "#.#", "#.#", "#.#", "##."),
    "H": ("#.#", "#.#", "###", "#.#", "#.#"), "J": ("..#", "..#", "..#", "#.#", "###"),
    "K": ("#.#", "#.#", "##.", "#.#", "#.#"), "L": ("#..", "#..", "#..", "#..", "###"),
    "M": ("#.#", "###", "###", "#.#", "#.#"), "N": ("##.", "#.#", "#.#", "#.#", "#.#"),
    "O": ("###", "#.#", "#.#", "#.#", "###"), "P": ("###", "#.#", "###", "#..", "#.."),
    "S": ("###", "#..", "###", "..#", "###"), "T": ("###", ".#.", ".#.", ".#.", ".#."),
    "U": ("#.#", "#.#", "#.#", "#.#", "###"), "Y": ("#.#", "#.#", ".#.", ".#.", ".#."),
    "Z": ("###", "..#", ".#.", "#..", "###"), "I": ("###", ".#.", ".#.", ".#.", "###"),
    "V": ("#.#", "#.#", "#.#", "#.#", ".#."), "X": ("#.#", "#.#", ".#.", "#.#", "#.#"),
    "Q": ("###", "#.#", "#.#", "###", "..#"),
}


def glyph_text(name, text, origin, cell, u_axis, v_axis, n_axis, depth=0.02):
    """Block-letter text as ONE mesh: each lit cell of the 3x5 font becomes a thin box. `origin` is the
    centre of the string, `u_axis` / `v_axis` are the reading and up directions, `n_axis` the surface normal."""
    verts, faces = [], []
    adv = cell * 4.0
    total = len(text) * adv - cell
    o = Vector(origin)
    ua, va, na = Vector(u_axis), Vector(v_axis), Vector(n_axis)
    for ci, ch in enumerate(text):
        g = _GLYPHS.get(ch)
        if g is None:
            continue
        for ri, row in enumerate(g):
            for cj, c in enumerate(row):
                if c != "#":
                    continue
                u = -total * 0.5 + ci * adv + cj * cell + cell * 0.5
                v = (2 - ri) * cell
                ctr = o + ua * u + va * v
                base = len(verts)
                for du in (-0.5, 0.5):
                    for dv in (-0.5, 0.5):
                        for dn in (0.0, 1.0):
                            q = ctr + ua * (du * cell) + va * (dv * cell) + na * (dn * depth)
                            verts.append((q.x, q.y, q.z))
                for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
                    faces.append(tuple(base + i for i in f))
    return new_mesh_object(name, verts, faces)


def markings(nation, fus_x, fus_y, fus_z, fus_r, wing_y, wing_span_x, wing_z, wing_r,
             fin_x, fin_y, fin_z, fin_r):
    """National markings as flat decal meshes (the tests look for DecalFus* inside the fuselage box and any
    other Decal* inside the airframe box). `fus_*` = a fuselage side position, `wing_*` = the wing position,
    `fin_*` = the fin position; the radii set the marking sizes.

    Luftwaffe tail markings are a plain band: the historical fin swastika is deliberately NOT modelled.
    """
    grp = group("Decals")
    # the airframe the markings sit on: sampling the real skin is what keeps a roundel flush
    wing_ob = bpy.data.objects.get("Wing") or bpy.data.objects.get("WingL")
    fus_ob = bpy.data.objects.get("Fuselage")
    if nation == "Civil":
        # a civil airliner: no national roundel, a black registration on the fuselage sides and the upper wing,
        # a blue cheat line along the cabin and a blue band on each fin
        reg = "G-AFRW"
        for i, sx in enumerate((-1.0, 1.0)):
            side_x = skin_point(fus_ob, fus_x * sx, fus_y, fus_z, "yz", sx) if fus_ob else fus_x * sx
            side_x = (side_x if side_x is not None else fus_x * sx) + 0.010 * sx
            read = Vector((0.0, sx, 0.0))      # starboard reads toward the nose, port toward the tail
            g = glyph_text("DecalFusBlackReg_%d" % i, reg, (side_x, fus_y, fus_z), fus_r * 0.30,
                           read, (0.0, 0.0, 1.0), (sx, 0.0, 0.0))
            parent_to(g, grp)
            band = bar("DecalFusBlueBand_%d" % i, (0.03, 4.1, 0.07), (side_x, fus_y + 0.55, fus_z - 0.34))
            parent_to(band, grp)
            wx = wing_span_x * sx * 0.62
            top = skin_point(wing_ob, wx, wing_y, wing_z - 0.12, "xy", 1.0) if wing_ob else None
            top = (top if top is not None else wing_z) + 0.012
            wg = glyph_text("DecalWingBlackReg_%d" % i, reg, (wx, wing_y, top), wing_r * 0.16,
                            Vector((sx, 0.0, 0.0)), Vector((0.0, 1.0, 0.0)), Vector((0.0, 0.0, 1.0)))
            parent_to(wg, grp)
        fin_ob = bpy.data.objects.get("Fin")
        for i, sx in enumerate((-1.0, 1.0)):
            fb = bar("DecalFinBlue_%d" % i, (0.04, fin_r * 1.4, fin_r * 0.8), (fin_x * sx, fin_y, fin_z))
            parent_to(fb, grp)
    elif nation == "Luftwaffe":
        # Balkenkreuz on the fuselage sides and the wings, a black/white band on the fin
        for i, sx in enumerate((-1.0, 1.0)):
            side_x = skin_point(fus_ob, fus_x * sx, fus_y, fus_z, "yz", sx) if fus_ob else fus_x * sx
            side_x = (side_x if side_x is not None else fus_x * sx) + 0.012 * sx
            for (nm, s) in (("Black", 0.62), ("White", 1.0)):
                f = bar("DecalFus%s_%d" % (nm, i), (0.03, fus_r * 2.0 * s, fus_r * 0.5 * s),
                        (side_x, fus_y, fus_z))
                parent_to(f, grp)
                g = bar("DecalFus%sV_%d" % (nm, i), (0.03, fus_r * 0.5 * s, fus_r * 2.0 * s),
                        (side_x, fus_y, fus_z))
                parent_to(g, grp)
            wx = wing_span_x * sx * 0.62
            top = skin_point(wing_ob, wx, wing_y, wing_z, "xy", 1.0) if wing_ob else wing_z
            top = (top if top is not None else wing_z) + 0.014
            u = bar("DecalWingBlackU_%d" % i, (wing_r * 0.9, wing_r * 0.34, 0.03), (wx, wing_y, top))
            parent_to(u, grp)
            u2 = bar("DecalWingBlackUv_%d" % i, (wing_r * 0.34, wing_r * 0.9, 0.03), (wx, wing_y, top))
            parent_to(u2, grp)
        band = bar("DecalFinBand", (0.04, fin_r * 1.6, fin_r * 1.2), (fin_x, fin_y, fin_z))
        parent_to(band, grp)
    elif nation in ("USAAF", "USN"):
        for i, sx in enumerate((-1.0, 1.0)):
            for (nm, s) in (("Blue", 0.72), ("White", 1.0)):
                d = skin_disc("DecalFus%s_%d" % (nm, i), fus_ob, fus_x * sx, fus_y, fus_z, fus_r * s,
                              plane="yz", sign=sx, offset=0.014 + 0.011 * (1.0 - s))
                parent_to(d, grp)
            wx = wing_span_x * sx * 0.6
            top = skin_point(wing_ob, wx, wing_y, wing_z, "xy", 1.0) if wing_ob else wing_z
            top = top if top is not None else wing_z
            wb = bar("DecalWingBlueU_%d" % i, (wing_r * 1.9, wing_r * 0.5, 0.03), (wx, wing_y, top + 0.014))
            parent_to(wb, grp)
            ws = skin_disc("DecalWingWhiteU_%d" % i, wing_ob, wx, wing_y, wing_z, wing_r * 0.5,
                           plane="xy", sign=1.0, offset=0.028)
            parent_to(ws, grp)
    else:
        # RAF: blue/white/red roundels on the fuselage sides and the upper wings, a fin flash
        for i, sx in enumerate((-1.0, 1.0)):
            for (nm, s) in (("Blue", 1.0), ("White", 0.66), ("Red", 0.34)):
                d = skin_disc("DecalFus%s_%d" % (nm, i), fus_ob, fus_x * sx, fus_y, fus_z, fus_r * s,
                              plane="yz", sign=sx, offset=0.014 + 0.011 * (1.0 - s))
                parent_to(d, grp)
            for (nm, s) in (("Blue", 1.0), ("White", 0.66), ("Red", 0.34)):
                w = skin_disc("DecalWing%sU_%d" % (nm, i), wing_ob,
                              wing_span_x * sx * 0.62, wing_y, wing_z, wing_r * s,
                              plane="xy", sign=1.0, offset=0.014 + 0.011 * (1.0 - s))
                parent_to(w, grp)
        fin_ob = bpy.data.objects.get("Fin")
        for (nm, c, off) in (("Blue", 0.72, -0.05), ("White", 0.85, 0.0), ("Red", 0.72, 0.05)):
            fx = skin_point(fin_ob, fin_x, fin_y + off, fin_z, "yz", 1.0) if fin_ob else None
            if fx is None:
                fx = skin_point(fin_ob, fin_x, fin_y + off, fin_z, "yz", -1.0) if fin_ob else None
            if fx is None:
                fx = fin_x
            fb = bar("DecalFin%s" % nm, (0.03, fin_r * 0.5, fin_r * 1.1),
                     (fx + (0.02 if fx >= 0 else -0.02), fin_y + off, fin_z))
            parent_to(fb, grp)
    return grp


def gear_leg(name, x, y, z, length, wheel_r, track_out=0.0):
    """A retractable leg: the node is the pivot (Aircraft rotates GearL/GearR about Z), the wheel hangs below."""
    pivot = empty(name, (x, y, z))
    leg = cylinder("Leg", wheel_r * 0.19, wheel_r * 0.16, length, loc=(0, 0, -length * 0.5), rot=(0, 0, 0), n=10)
    parent_to(leg, pivot)
    wheel = cylinder("Wheel", wheel_r, wheel_r, wheel_r * 0.62, loc=(track_out, 0, -length), rot=(0, 90, 0), n=18)
    parent_to(wheel, pivot)
    hub = cylinder("GearHub", wheel_r * 0.55, wheel_r * 0.55, wheel_r * 0.70, loc=(track_out, 0, -length),
                   rot=(0, 90, 0), n=14)
    parent_to(hub, pivot)
    return pivot


def build_body(parts):
    """Wrap the airframe meshes in a `Body` group (tests require it) and return it."""
    body = group("Body")
    for p in parts:
        if p.parent is None:
            parent_to(p, body)
    return body


# ------------------------------------------------------------------ output

def export_glb(path, apply=True):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_apply=apply,
                              export_yup=True, use_selection=False, export_materials='EXPORT')
    return path


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def report(id_):
    tris = model_tris()
    print("[model] %-12s tris=%6d objects=%d" % (id_, tris, len(bpy.data.objects)))
    return tris


def render_ortho(out_dir, id_, ortho_scale=None, res=768):
    """Front / side / top / three-quarter sheets, so a silhouette can be checked against a real 3-view."""
    os.makedirs(out_dir, exist_ok=True)
    scene = bpy.context.scene
    # Workbench, flat single colour on a white background. These sheets exist to be compared with a
    # blueprint silhouette, so the model must be a solid black shape: no lights, no shading, no
    # anti-aliasing artefacts. (The previous EEVEE render had no lights and no world, so every sheet
    # came out black-on-black - 128 blank PNGs, all four views byte-identical.)
    scene.render.engine = 'BLENDER_WORKBENCH'
    try:
        sh = scene.display.shading
        sh.light = 'FLAT'
        sh.color_type = 'SINGLE'
        sh.single_color = (0.0, 0.0, 0.0)
        sh.show_object_outline = False
        sh.background_type = 'VIEWPORT'
        sh.background_color = (1.0, 1.0, 1.0)
    except Exception as e:      # keep the old behaviour rather than abort the build
        print("[model] workbench shading not configured:", e)
    scene.display.render_aa = 'OFF'
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.film_transparent = False

    # fit the ortho views to the model bounds
    bpy.context.view_layer.update()
    xs, ys, zs = [], [], []
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        for c in ob.bound_box:
            w = ob.matrix_world @ __import__('mathutils').Vector(c)
            xs.append(w.x); ys.append(w.y); zs.append(w.z)
    if not xs:
        return
    cx = (min(xs) + max(xs)) / 2.0
    cy = (min(ys) + max(ys)) / 2.0
    cz = (min(zs) + max(zs)) / 2.0
    size = max(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)) * 1.15
    if ortho_scale:
        size = ortho_scale

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = size
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    views = {
        "front": ((0.0, cy, cz), (math.radians(90.0), 0.0, 0.0), (cx, 0.0, cz - cy)),   # looking -Y
        "side": ((cx - size, cy, cz), (math.radians(90.0), 0.0, math.radians(-90.0)), (0, 0, 0)),
        "top": ((cx, cy, cz + size), (0.0, 0.0, 0.0), (0, 0, 0)),
        "quarter": ((cx - size * 0.55, cy, cz + size * 0.18), (math.radians(78.0), 0.0, math.radians(-38.0)), (0, 0, 0)),
    }
    for nm, (loc, rot, _) in views.items():
        cam.location = loc
        cam.rotation_euler = rot
        scene.render.filepath = os.path.join(out_dir, "%s_%s.png" % (id_, nm))
        bpy.ops.render.render(write_still=True)
    print("[model] sheets ->", out_dir)


def _flat_workbench(scene):
    """Flat single-colour workbench render: models as solid black shapes on white, no lights needed."""
    scene.render.engine = 'BLENDER_WORKBENCH'
    try:
        sh = scene.display.shading
        sh.light = 'FLAT'
        sh.color_type = 'SINGLE'
        sh.single_color = (0.0, 0.0, 0.0)
        sh.show_object_outline = False
        sh.background_type = 'VIEWPORT'
        sh.background_color = (1.0, 1.0, 1.0)
    except Exception as e:
        print("[model] workbench shading not configured:", e)
    scene.display.render_aa = 'OFF'


def eye_report(id_):
    """Is the pilot's eye above the fuselage deck and inside the canopy?

    Every builder marks the seat with a `CockpitEye` empty, and both the cockpit camera and the
    procedural interior hang off it - so if it sits inside the fuselage the pilot stares at structure
    instead of out over the nose. The deck is read from the model's own fuselage mesh at the eye's
    station, not from a table, so this catches the whole class of error on every aircraft at once.
    """
    eye = bpy.data.objects.get("CockpitEye")
    if eye is None:
        print("[cockpit] %-12s no CockpitEye marker" % id_)
        return None
    e = eye.matrix_world.translation
    deck = None
    roof = None
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        mw = ob.matrix_world
        if ob.name.startswith("Fuselage"):
            zs = [(mw @ v.co).z for v in ob.data.vertices
                  if abs((mw @ v.co).y - e.y) <= 0.6 and abs((mw @ v.co).x) < 0.40]
            if zs:
                deck = max(zs) if deck is None else max(deck, max(zs))
        elif ob.name.startswith("Canopy"):
            zs = [(mw @ v.co).z for v in ob.data.vertices if abs((mw @ v.co).y - e.y) <= 0.9]
            if zs:
                roof = max(zs) if roof is None else max(roof, max(zs))
    clear = deck is not None and e.z > deck + 0.03
    print("[cockpit] %-12s eye z %5.3f  deck %s  canopy top %s  -> %s" % (
        id_, e.z,
        ("%5.3f" % deck) if deck is not None else "  n/a",
        ("%5.3f" % roof) if roof is not None else "  n/a",
        "clear of the deck" if clear else "*** EYE AT OR BELOW THE DECK ***"))
    return clear


def render_eye(out_dir, id_, res=560, fov=62.0):
    """REMOVED from use - left as a note, not called.

    Rendering "what the pilot sees" from the CockpitEye cannot work as a silhouette: build_body()
    joins every part into one mesh, so the windscreen glass is part of the body and cannot be hidden,
    and the camera sits inside it. Every frame came out solid black. Use `eye_report` (the numeric
    eye-vs-deck check, which is sound and covers every type) and verify the actual view in game.
    """
    return
    eye = bpy.data.objects.get("CockpitEye")   # noqa: unreachable - kept for reference only
    if eye is None:
        return
    os.makedirs(out_dir, exist_ok=True)
    scene = bpy.context.scene
    _flat_workbench(scene)
    scene.render.resolution_x = res
    scene.render.resolution_y = int(res * 0.62)
    scene.render.film_transparent = False
    cd = bpy.data.cameras.new("EyeCam")
    cd.type = 'PERSP'
    cd.angle = math.radians(fov)
    cam = bpy.data.objects.new("EyeCam", cd)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = eye.matrix_world.translation
    # builders put the nose toward +Y; the default camera looks down -Z, so (90, 0, 180) faces +Y
    cam.rotation_euler = (math.radians(90.0), 0.0, math.radians(180.0))

    hidden = []
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        if ob.name.startswith("Canopy") and "Frame" not in ob.name:
            hidden.append(ob)
            ob.hide_render = True
    scene.render.filepath = os.path.join(out_dir, "%s_eye.png" % id_)
    bpy.ops.render.render(write_still=True)
    for ob in hidden:
        ob.hide_render = False


def _skin_vertices(ob):
    """World-space vertex list of an object (cached: markings run before refine, so these are cheap)."""
    from mathutils import Vector
    key = "sv_" + ob.name
    if key in _SKIN_CACHE:
        return _SKIN_CACHE[key]
    mw = ob.matrix_world
    pts = [(mw @ v.co).copy() for v in ob.data.vertices]
    _SKIN_CACHE[key] = pts
    return pts


def skin_point(ob, x, y, z, plane="xy", sign=1.0, rad=0.30):
    """The outermost skin coordinate of `ob` near a query point, along the plane's normal axis.

    plane="xy" -> returns the skin's z (a wing's upper/lower surface; sign picks which side)
    plane="yz" -> returns the skin's x (a fuselage flank)
    A flat decal placed on a curved or dihedral surface either sinks in or floats; sampling the real skin is
    what lets a marking sit ON the aircraft instead of near it.
    """
    if ob is None:
        return None
    best = None
    for p in _skin_vertices(ob):
        if plane == "xy":
            if abs(p.x - x) > rad or abs(p.y - y) > rad:
                continue
            val = p.z
        else:
            if abs(p.y - y) > rad or abs(p.z - z) > rad:
                continue
            val = p.x
        if best is None or (val * sign) > (best * sign):
            best = val
    return best


def skin_disc(name, ob, x, y, z, radius, plane="xy", sign=1.0, offset=0.012, n=22, thickness=0.006,
              fallback=True):
    """A national-marking disc laid on `ob`'s skin, in the right plane for the surface it sits on.

    plane="xy": lies flat (span x chord) - the upper/lower wing surface.
    plane="yz": stands vertical (length x height) - a fuselage flank, normal along X.
    Every ring vertex is dropped onto the skin (plus `offset`), so the marking follows dihedral, camber and
    fuselage curvature instead of hovering on a plane. With no object to sample it falls back to a flat disc.
    """
    ring = [(math.cos(TAU * i / n) * radius, math.sin(TAU * i / n) * radius) for i in range(n)]
    if plane == "xy":
        outer = [(x + px, y + pz, z) for (px, pz) in ring]
    else:
        outer = [(x, y + px, z + pz) for (px, pz) in ring]
    if ob is not None:
        placed = []
        for q in outer:
            sp = skin_point(ob, q[0], q[1], q[2], plane, sign, rad=max(0.12, radius * 0.6))
            if plane == "xy":
                placed.append((q[0], q[1], (sp if sp is not None else q[2]) + offset * sign))
            else:
                placed.append(((sp if sp is not None else q[0]) + offset * sign, q[1], q[2]))
        outer = placed
    # extrude the ring into a thin slab along the surface normal so it renders as a painted patch
    if plane == "xy":
        secs = [[(px, py, pz - thickness * sign) for (px, py, pz) in outer], outer]
    else:
        secs = [[(px - thickness * sign, py, pz) for (px, py, pz) in outer], outer]
    v, f = loft(secs, True, True)
    return new_mesh_object(name, v, f)


# ------------------------------------------------------------------ detail + accuracy helpers

def fin(name, stations, camber=0.03, n=16):
    """`stations` = [(z_height, chord, y_le_offset, thickness_ratio), ...] bottom -> top: a vertical
    fin/rudder. The span runs along +Z and the chord along -Y (trailing edge aft); y_le_offset rakes the
    leading edge, so a rounded rudder is just a station list whose chord shrinks near the top."""
    secs = []
    for (z, chord, yle, th) in stations:
        ring = airfoil_ring(th, camber, n)
        secs.append([(fz * chord, yle - chord * fx, z) for (fx, fz) in ring])
    v, f = loft(secs, True, True)
    return new_mesh_object(name, v, f)


def radiator(name, x, y, z, w, h, length, mouth=True):
    """A shallow under-wing radiator / oil-cooler duct: camo housing plus a dark intake mouth facing forward."""
    grp = group(name, (0.0, 0.0, 0.0))
    housing = new_mesh_object(name + "Body", *loft([
        [(px, y - length * 0.5 + d, z + pz) for (px, pz) in superellipse(14, w * 0.5, h * 0.5, 3.0)]
        for d in (0.0, length)
    ], True, True))
    housing.location = (x, 0.0, 0.0)
    parent_to(housing, grp)
    if mouth:
        # a vertical intake face: build it from two rings separated along Y (not a flat horizontal plate)
        m = new_mesh_object(name + "Intake", *loft([
            [(x + px, y - length * 0.5 - d, z + pz) for (px, pz) in superellipse(12, w * 0.38, h * 0.40, 3.0)]
            for d in (0.0, 0.03)
        ], True, True))
        parent_to(m, grp)
    return grp


def exhaust_bank(name, x, y, z, stacks=6, spacing=0.19, r=0.05, length=0.30):
    """A row of Merlin-style ejector stacks along one cowling side (x sign picks the side)."""
    grp = group(name, (float(x), float(y), float(z)))
    for i in range(stacks):
        s = cylinder(name + "%d" % i, r, r * 1.05, length, loc=(0, 0, 0), rot=(0, 90, 0), n=8)
        s.location = (0.0, (i - (stacks - 1) * 0.5) * spacing, 0.0)
        parent_to(s, grp)
    return grp


def tailwheel(name, y, z, strut=0.30, r=0.16, n=12):
    """A fixed tail wheel on a short strut (the contract's GearL/GearR are the mains)."""
    grp = group(name, (0.0, float(y), float(z)))
    leg = cylinder(name + "Strut", 0.045, 0.04, strut, loc=(0, 0, -strut * 0.5), rot=(0, 0, 0), n=8)
    parent_to(leg, grp)
    wheel = new_mesh_object(name + "Tyre", *loft([
        [(math.cos(TAU * i / n) * r * s, y_off, math.sin(TAU * i / n) * r * s)
         for i in range(n)]
        for (y_off, s) in ((-0.055, 0.55), (-0.045, 1.0), (0.045, 1.0), (0.055, 0.55))
    ], True, True))
    wheel.location = (0.0, 0.0, -strut - r * 0.75)
    parent_to(wheel, grp)
    return grp


def refine(ob, cuts=1, smooth=True):
    """Subdivide a finished mesh so the dense models can reach the high-poly budget, then shade smooth."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
    bm.to_mesh(me)
    bm.free()
    me.update()
    if smooth:
        shade_smooth(me)
    return ob


def shade_smooth(me):
    for p in me.polygons:
        p.use_smooth = True


def refine_all(cuts=1, skip_flat=True):
    """Subdivide every mesh in the scene (the flat decal plates gain nothing from being smoothed)."""
    for ob in list(bpy.data.objects):
        if ob.type != 'MESH':
            continue
        if skip_flat and (ob.name.startswith("Decal") or ob.name.startswith("BladeTip")):
            continue
        refine(ob, cuts)


def bounds():
    """World-space bounds of everything that has been built: (min, max, size) with size = (X=span, Y=length, Z=height)."""
    from mathutils import Vector
    bpy.context.view_layer.update()      # matrix_world is stale until the depsgraph refreshes
    lo = [1e9, 1e9, 1e9]
    hi = [-1e9, -1e9, -1e9]
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            for a in range(3):
                lo[a] = min(lo[a], w[a])
                hi[a] = max(hi[a], w[a])
    size = tuple(hi[a] - lo[a] for a in range(3))
    return tuple(lo), tuple(hi), size


def bounds_report(id_, expect, height_info=None, tol=2.0):
    """Compare the built airframe against the published figures and print the verdict.

    `expect` = (length_m, span_m) - the two figures a model can be held to, gated at `tol` percent (a FAIL
    means the data must be fixed). Height is reported for information only when `height_info` is given: the
    published height is measured in a specific parked stance, so it is not a fair gate on model geometry.
    """
    _lo, _hi, size = bounds()
    checks = (("length", size[1], expect[0]), ("span", size[0], expect[1]))
    ok = True
    parts = []
    for (nm, got, want) in checks:
        pc = (got - want) / want * 100.0
        if abs(pc) > tol:
            ok = False
        parts.append("%s %.2f/%.2fm (%+.1f%%)" % (nm, got, want, pc))
    if height_info:
        parts.append("height %.2fm (published %.2fm, stance-dependent)" % (size[2], height_info))
    print("ACCURACY %-10s %s %s" % (id_, " ".join(parts), "PASS" if ok else "FAIL"))
    return ok

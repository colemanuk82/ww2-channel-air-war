#!/usr/bin/env python3
"""Find the seat-view camera orientation empirically, in the AUTHORED scene (nose +Y, up +Z).

The imported .glb has glTF axes (Y-up), so testing there proved nothing about render_eye, which runs
in the authored scene right after the builder. This sweeps yaw and pitch and reports how much of each
frame is open space rather than black structure.

  blender --background --python tools/models/eye_dir_test2.py
"""
import importlib.util, math, os, sys
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import kit   # noqa: E402

OUT = os.path.join(ROOT, "build", "eyedir2")
os.makedirs(OUT, exist_ok=True)

kit.clear_scene()
spec = importlib.util.spec_from_file_location("m_hurricane", os.path.join(HERE, "data", "hurricane.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.build()
print("[eyedir] built hurricane, objects=%d" % len(bpy.data.objects))

eye = bpy.data.objects.get("CockpitEye")
e = eye.matrix_world.translation
print("[eyedir] eye (authored scene) at", tuple(round(v, 3) for v in e))

scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
try:
    sh = scene.display.shading
    sh.light = 'FLAT'; sh.color_type = 'SINGLE'; sh.single_color = (0.0, 0.0, 0.0)
    sh.show_object_outline = False
    sh.background_type = 'VIEWPORT'; sh.background_color = (1.0, 1.0, 1.0)
except Exception as ex:
    print("[eyedir] shading:", ex)
scene.display.render_aa = 'OFF'
scene.render.resolution_x = 560
scene.render.resolution_y = 347
scene.render.film_transparent = False

cd = bpy.data.cameras.new("T")
cd.type = 'PERSP'
cd.angle = math.radians(62.0)
cam = bpy.data.objects.new("T", cd)
scene.collection.objects.link(cam)
scene.camera = cam
cam.location = e

for rz in (0, 90, 180, 270):
    for pitch in (0, -10, 10):
        cam.rotation_euler = (math.radians(90.0 + pitch), 0.0, math.radians(float(rz)))
        scene.render.filepath = os.path.join(OUT, "auth_rz%03d_p%+03d.png" % (rz, pitch))
        bpy.ops.render.render(write_still=True)
print("[eyedir] done")

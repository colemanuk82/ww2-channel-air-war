#!/usr/bin/env python3
"""Which way does the seat-view camera have to face? Render the Hurricane's eye view at four
rotations and measure how much of each frame is open (background) rather than structure.

Run inside Blender:
  blender --background --python tools/models/eye_dir_test.py
"""
import math, os, sys
import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GLB = os.path.join(ROOT, "assets", "models", "hurricane.glb")
OUT = os.path.join(ROOT, "build", "eyedir")
os.makedirs(OUT, exist_ok=True)

# start from a clean scene, import the built model
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)

eye = bpy.data.objects.get("CockpitEye")
if eye is None:
    print("no CockpitEye in the glb")
    sys.exit(1)
print("eye at", tuple(round(v, 3) for v in eye.matrix_world.translation))

scene = bpy.context.scene
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
    print("shading:", e)
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
cam.location = eye.matrix_world.translation

for rz in (0, 90, 180, 270):
    cam.rotation_euler = (math.radians(90.0), 0.0, math.radians(float(rz)))
    scene.render.filepath = os.path.join(OUT, "hurricane_rz%03d.png" % rz)
    bpy.ops.render.render(write_still=True)
    print("[eyedir] rendered rz=%d -> %s" % (rz, scene.render.filepath))

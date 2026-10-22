"""Build every aircraft .glb from tools/models/data/<id>.py.

  blender --background --python tools/models/build_all.py -- spitfire [bf109 ...] [--ortho]

Each data module must expose build() and return nothing; the kit owns the scene. Deterministic: no RNG.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))          # F:/ww2_dlss
sys.path.insert(0, HERE)

import kit   # noqa: E402

ASSETS = os.path.join(ROOT, "assets", "models")
SHEETS = os.path.join(ROOT, "tools", "shots", "models")


def load(id_):
    path = os.path.join(HERE, "data", id_ + ".py")
    spec = importlib.util.spec_from_file_location("m_" + id_, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ortho = "--ortho" in argv
    eye = "--eye" in argv
    ids = [a for a in argv if not a.startswith("--")]
    if not ids:
        print("usage: build_all.py -- <id> [<id>...] [--ortho]")
        return
    totals = []
    for id_ in ids:
        kit.clear_scene()
        mod = load(id_)
        mod.build()
        tris = kit.report(id_)
        exp = getattr(mod, "EXPECT", None)
        if exp:
            kit.bounds_report(id_, exp, getattr(mod, "HEIGHT_INFO", None))
        out = kit.export_glb(os.path.join(ASSETS, id_ + ".glb"))
        totals.append((id_, tris, os.path.getsize(out)))
        if ortho:
            kit.render_ortho(SHEETS, id_)
        if eye:
            kit.eye_report(id_)
    print("[models] built %d: %s" % (len(totals), ", ".join("%s=%dtris/%.0fKB" % (i, t, s / 1024.0) for i, t, s in totals)))


main()

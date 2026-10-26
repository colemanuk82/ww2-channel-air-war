# Aircraft liveries

Each aircraft wears one painted texture, `assets/liveries/<model>_<nation>.png`, the way a real aircraft
(or IL-2's skins) carries its paint job: camouflage, markings, codes and weathering are all in that one image.
Nothing is copied from any other game. The colours are the wartime paint standards (BS 381C / MAP shades,
RLM, ANA / Bulletin 41) and the patterns, demarcations and bands follow photographs of each type.

The aircraft models themselves are not changed. At load, `scripts/models/livery.gd` gives the skin parts UV
coordinates with a fixed unwrap (long bodies are unrolled round their axis, everything else split by facing into
flat charts, all packed into one square atlas). `shaders/aircraft_pbr.gdshader` samples the livery and still adds
the panel seams, rivets and grime on top. Markings that must stay switchable (the fin swastika and its disc) stay
separate meshes.

## Repainting

1. Export the unwrapped geometry (headless, no window):
   `tools\hidden\livery_geo.ps1 [-Only spitfire,bf109]`  -> `tools/liveries/geo/`
2. Paint: `python tools/liveries/paint_liveries.py [model ...]` (numpy + Pillow) -> `assets/liveries/`
3. Re-import (`tools\hidden\imp.ps1`) and check with `tools\hidden\galshot.ps1`.

Schemes (colours, pattern, demarcation, bands, wear) are the `SCHEMES` table in `paint_liveries.py`.
The PNGs can also be edited by hand; each `.json` beside a PNG records the model layout it was painted for, and a
model whose layout has changed falls back to its old look (with a warning) until it is repainted.

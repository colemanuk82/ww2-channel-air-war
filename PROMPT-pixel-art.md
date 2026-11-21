> **SUPERSEDED 2026-11-21: the pixel-art style was replaced by the Cel-shaded style (same art_style index 1, scripts/cel_shade.gd, shaders/cel/; see docs/STATUS.md). pixel_art.gd, shaders/pixel/, the palette and the pixel-grid option were removed; the notes below are historical.**

# PROGRAM: Pixel-art art style (Slotbound-like), behind a settings toggle

# PROGRAM: Pixel-art art style (Slotbound-like), behind a settings toggle

> **STATUS 2026-11-16: phase 1 is built and working.** scripts/pixel_art.gd +
> shaders/pixel/pixel_art.gdshader + tools/make_pixel_palette.py + assets/textures/pixel/palette.png,
> wired into GameState.art_style / pixel_native, a Video > Art style + Pixel grid row, and the debug
> args --pixel, --pixel-native=WxH, --pixel-shot=path. Aircraft got a hard ink silhouette
> (shaders/pixel/aircraft_ink.gdshader, Aircraft._apply_pixel_ink) so the player's aircraft reads as a
> sprite rather than a dark blob - **the player's outline is deliberately CREAM, not dark**, because the
> camouflaged airframe is dark and a dark ink swallows it. Gate: TESTS OK (4815 passed, 0 failed).
> Phases 2-5 below are still to do.

> **How to use this file:** a program brief in the style of `PROMPT-cities-towns-1940s.md`
> / `PROMPT-ground-fps.md`. Hand it to an implementation agent with no memory of the conversation.
> [Bracketed] text is a decision for the owner — answer it in phase 0 or record the assumption taken.

**Goal (the owner's words):** "give my game a pixel art style like *Slotbound*" — with the chosen
scope **"pixel mode + re-art the world to suit it"**, **toggleable in Video settings**, current look
stays the default.

**Reference (what Slotbound actually looks like — I read its Steam screenshots, do the same):**
`https://store.steampowered.com/app/4459590/Slotbound/`. Concretely:
- Native render about **480×270**, integer-scaled up (blurry-free hard pixel edges).
- Characters ~24-40 px tall; **silhouette carries the identity**, not detail.
- **Thick 1-px dark outlines** on every character, prop and UI element.
- **Flat, limited palette** (~32 colours), no gradients except **ordered (Bayer) dithering**.
- Chunky UI: pixel-border frames, bitmap numerals, drop-in panels — the UI is part of the art.

---

## Three facts that decide the design (verified on HEAD `9025207`)

1. **The whole world funnels through one factory.** Every procedural kit script builds materials via
   `ToonUtil.make_toon(color, opts)` (`scripts/toon_util.gd:67`). This is the exact lever that made
   the v6.0 realism pass possible with **no kit-script edits** (see `HANDOFF.md`, 2026-10-10). A
   pixel/cel material behind a static flag in that one function re-styles every building, road, prop,
   vehicle and airfield at once. **This is the single most important thing in this brief.**
2. **The font is one line.** `ThemeDB.fallback_font = UIKit.font()` (`scripts/game_state.gd:156`) —
   every `draw_string` in the HUD, menus and overlays reads it. Swapping it swaps the whole UI's
   typeface, which is half of what makes Slotbound *look* like Slotbound.
3. **The existing outline shader is the wrong tool, and must not simply be switched on.**
   `shaders/outline.gdshader` is an inverted-hull pass: `VERTEX += NORMAL * (thickness + d *
   dist_scale)`. At this game's view distances (LOD out to 48 km) `dist_scale` makes far outlines
   balloon, and it needs smooth normals the kit meshes do not all have. **Pixel art wants a
   screen-space 1-px edge pass on the low-res buffer**, applied last. Keep `outline.gdshader` for the
   existing opt-in look; do not reuse it for this.

**Also verified, and it constrains everything:** the world streams LOD to 48,000 units with fog and
aerial perspective tuned for altitude; `GameState.apply_graphics()` (`scripts/game_state.gd:716`) is
the one place settings are pushed to the running game; the render settings today are
`msaa_3d=2` + occlusion culling + a shader/pipeline cache (`project.godot` `[rendering]`), and
`window/stretch/mode="canvas_items"` with only `win.content_scale_factor = ui_scale` used for UI.

---

## Current context (verified by reading HEAD `9025207`)

| Area | Where | What's there now |
|---|---|---|
| World materials | `scripts/toon_util.gd` | `make_toon()` → `shaders/world_pbr.gdshader` (triplanar, real roughness/metallic, 20 × 1024² procedural textures from `tools/make_world_textures.py`), `remap_detail()` mapping old toon detail codes onto PBR modes. **The hook.** |
| Outlines | `shaders/outline.gdshader`, `ToonUtil.make_outline()` | Inverted hull, `global uniform outline_enabled`, `GameState.toggle_outlines()`. Opt-in; world surfaces do not use it. |
| Terrain | `shaders/terrain.gdshader` | Palette uniforms + imagery drape (`map_amount` ~0.72) + `field_cell=190` field lattice (must stay in step with `Scatter.FIELD_CELL`) + 256² detail texture. |
| Aircraft | `scripts/aircraft.gd`, `scripts/models/gltf_models.gd` | 43k-poly Blender `.glb` (22,964 for the Spitfire), `shaders/aircraft_pbr.gdshader` procedural camo. |
| Sky / light | `scripts/time_of_day.gd`, `shaders/sky.gdshader` | ACES tonemapping, SSAO 0.62, sky reflections, volumetric clouds (`cloud_volume.gdshader`). |
| HUD | `scripts/hud.gd` | ~1900 lines, custom `_draw()`, `ThemeDB.fallback_font` everywhere. |
| UI font / theme | `scripts/game_state.gd:156`, `scripts/uikit.gd` | `UIKit.font()` (SystemFont Bahnschrift) set as the global fallback font once. |
| Settings | `scripts/game_state.gd` (`set_graphic`, `apply_graphics`, `apply_quality`), `scripts/settings_menu.gd` (`_row(page, "Quality", [...])`) | The established pattern for adding a Video option; settings persist under `[gfx]` in `settings.cfg`. |
| Upscalers | `GameState.Upscaler` (OFF / FSR2 / DLSS) + frame generation | **Must be forced OFF in pixel mode** — they blur the low-res buffer. |
| Verification | `--shot=`, `--ui-shot=`, `tools/hidden/hidden_run.ps1`, `tools/tests.gd` → `TESTS OK` | Hidden desktop only, never a visible window. |

**Conventions (mandatory):** TABS, typed GDScript; new `class_name` ⇒ `--headless --path . --import`;
never a visible window / focus steal; `WorldCoords` only for projection; all art procedural or
CC0/CC-BY in `ATTRIBUTION.md`; **never copy Slotbound's or any game's sprites/textures**; no
commercial audio; release only through `tools/cache/ship.ps1`.

---

## Phase 0 — Decisions to record before coding

| # | Question | Default if unanswered |
|---|---|---|
| 0.1 | Native pixel resolution: 320×180 (chunkier), 480×270 (Slotbound's, recommended), 640×360 (subtler)? | **(480×270)** |
| 0.2 | Palette size and rule: fixed 32-colour palette, or 5-bit-per-channel quantise, or per-biome palettes? | **(fixed 32-colour, generated by `tools/make_pixel_palette.py`, stored in the repo)** |
| 0.3 | Does pixel mode apply **at next load** or rebuild the world live? Materials are built at load and the scatter is cached, so a live switch means a world rebuild. | **(applies on next mission/load, like a texture setting — state it in the tooltip)** |
| 0.4 | Is the **menu** in pixel style too, or only in-game? The menu art is committed photographs/paintings. | **(in-game + HUD + menu frames; leave the paintings as they are for now)** |
| 0.5 | Aircraft: keep the 43k-poly models (they rasterise to ~10 px silhouettes anyway) or make simplified pixel-era meshes? | **(keep the glb models in phase 1; simplify only in phase 3 if silhouettes fail)** |

---

## Phase 1 — The pixel pipeline (the render target)

**This phase alone produces the look; everything after it is polish.** Do it first and ship it.

1.1 `scripts/pixel_mode.gd` — a `SubViewport` holder: `size = NATIVE_RES` (0.1), `filter = false`
   on the output `TextureRect`, `stretch = false`, integer scaling with a black border (letterbox)
   when the window is not a multiple. Keep it out of the way of the HUD (the HUD is phase 2).
1.2 Post pass, in this order, all in shaders under `shaders/pixel/`:
   - **palette quantise** to the fixed palette (nearest colour in linear space, not sRGB-naive);
   - **ordered dither** (Bayer 4×4 or 8×8) applied *before* quantise, with strength as a uniform;
   - optional **scanline/`pixel_perfect`** off by default (Slotbound has none — do not add CRT vfx).
1.3 **Turn off, in pixel mode:** DLSS/FSR + frame generation, MSAA, SSAO (or drop it to a dither
   substitute), anisotropic filtering, and the aerial-perspective haze. Each of these either blurs
   the buffer or fights the palette. Do it inside `apply_graphics()` so there is one source of truth.
1.4 **Fog and view distance.** At 480×270 the 48 km LOD is sub-pixel mush. Pixel mode should pull
   fog in to ~[3-6 km] and let the far field resolve as a flat dithered band — this is what makes it
   read like art instead of a bug. Make the numbers uniforms, not magic constants, and report the
   before/after of `--perf=120:30`.
1.5 `--pixel-shot=png` debug arg: renders the game in pixel mode, saves at 4× nearest upscale, quits.
   This is the whole verification loop for the look.
1.6 **Verification:** hidden-desktop renders at dawn/noon/dusk and at ground level / low flight /
   altitude. Read them yourself. Acceptance: hard pixel edges, ≤ palette colours, readable aircraft
   silhouette, no shimmering (that is what tells you mipmaps/filtering are wrong).

---

## Phase 2 — The UI is half the style

2.1 `tools/make_pixel_font.py` → a bitmap pixel font (5×7 or 7×9 capitals, numerals, punctuation) as
   a `FontFile`/`BitmapFont`-style resource in `assets/ui/pixel/`. **Generated from a glyph table in
   the script, not copied from a game.**
2.2 `UIKit.font()` returns the pixel font when pixel mode is on; `ThemeDB.fallback_font` is set in one
   place already, so this is cheap. **Check HUD legibility at 480×270** — sizes must be *multiples*
   of the glyph height or text turns to mush.
2.3 Pixel frames for the HUD panels, ammo strip, minimap border, radio log, and menu buttons: a
   `nine_patch`/`StyleBoxTexture` set with 1-px borders and the palette colours. Replace the rounded
   Bahnschrift chrome only in pixel mode.
2.4 The **big round dials** (ASI/altimeter) are custom-drawn arcs — in pixel mode they must be drawn
   on the pixel grid or they will look pasted on. Re-draw them as stepped/dithered shapes.
2.5 **Verification:** `--ui-shot=` captures of the start menu, Options, and the in-game HUD in both
   modes; every text string still readable; no text smaller than the glyph height.

---

## Phase 3 — Re-art the 3D world to suit pixels (the expensive phase)

**This is the phase the owner explicitly chose**, and it is the one that will fight the existing
realism work. Everything here must be **behind the toggle**, so the realistic path stays intact.

3.1 **One factory, two materials.** In `ToonUtil.make_toon()`, return either the current PBR material
   or a new `shaders/pixel/world_cel.gdshader` when `ToonUtil.pixel_style` is on. Because ~100 kit
   scripts call it, this re-skins the entire procedural world without touching a single kit file.
   Do **not** fork the kits.
3.2 **Flat 2-tone shading.** Kill roughness/metallic/normal detail; quantise the lit colour into 2-3
   steps. `remap_detail()` stays (it translates the kit's old detail codes) — the cel shader must
   honour the same codes, or buildings will come out graded wrong (this exact class of bug is
   documented in `HANDOFF.md`, 2026-10-10: kits pass *old* toon detail codes).
3.3 **Silhouette-first meshes** — only where 1.6 proves it is needed: trees, hedges, houses, players'
   crew figures, vehicles. Prefer fewer, larger, flatter shapes. Keep the LOD pair system
   (`Scatter.far_mesh`) working; the far LOD should ideally *be* the pixel silhouette.
3.4 **Textures: mostly turn them off.** A 1024² photo-ish texture is the opposite of pixel art. The
   cel path should sample a small **palette index texture** (or none at all) and let the palette pass
   in phase 1 do the work. Keep `make_world_textures.py` for the realistic path untouched.
3.5 **Terrain:** flatten to the palette + field lattice. `map_amount` (imagery drape) must drop to
   near-0 in pixel mode, or the satellite imagery shows through as photo detail. `field_cell` stays
   in step with `Scatter.FIELD_CELL`.
3.6 **Aircraft:** `aircraft_pbr.gdshader` → flat 2-3 tone camo; national markings stay readable at
   ~10 px (test the roundel and the cross specifically — this is where pixel aircraft usually fail).
3.7 **Outlines:** a **screen-space edge pass at native res** (depth/normal discontinuity, 1 px,
   palette dark colour), not the inverted hull. Verify it does not vibrate when the camera moves —
   jittering edges are the classic tell of a bad pixel outline.
3.8 **Verification:** side-by-side renders (realistic | pixel) of the same six views, plus a
   silhouette test at native res: an aircraft, a house row, a tree line and a church each readable
   as what they are at 480×270.

---

## Phase 4 — The toggle, settings and performance

4.1 `GameState`: `art_style` (0 realistic, 1 pixel) in `[gfx]`, `set_graphic("art_style", i)`,
   and the push inside `apply_graphics()`. One switch, one place.
4.2 `settings_menu.gd`: a `_row(page, "Art style", ["Realistic", "Pixel art"], ...)` beside Quality,
   with the tooltip saying it applies on the next load (0.3).
4.3 **The flight game must not regress.** `--perf=120:30` in realistic mode before/after (no more than
   [2%]); pixel mode should be *cheaper* (smaller buffer, no upscaler/SSAO), so report the gain.
4.4 Docs: `docs/STATUS.md`, `HANDOFF.md` session entry, README section with two screenshots side by
   side, and an honest line: *"a pixel-art rendering style, not hand-drawn sprite art."*

---

## Phase 5 — Tests and release

5.1 `tools/tests.gd`: palette generation is deterministic and fully populates; the pixel font covers
   every glyph the game actually uses (scan the source for string literals — a missing glyph renders
   as a box); `ToonUtil` returns the cel material in pixel mode and the PBR one otherwise; the
   settings round-trip through `settings.cfg`.
5.2 A headless run of the game in pixel mode with **no script errors**, and the `--pixel-shot` set
   from phase 1 regenerated into `screenshots/` (committed, so the next agent can see regressions).
5.3 Release only via `tools/cache/ship.ps1 -msg "..."` after `TESTS OK` and the exported smoke test.
   Version bump is the ship script's job.

---

## Order and effort

1 → 2 → 4 → 3 → 5.

Phase 1 gives the look, phase 2 gives it credibility, phase 4 makes it a product feature, phase 3 is
the deep re-art and **can be split into its own release** (ship 1+2+4 as "pixel-art mode", then 3 as
"pixel world art"). Do not start with 3 — it is the largest and the most likely to be reworked.

## Risks the owner should know

- **It undoes part of v6.0.** The realism pass (PBR textures, ACES, SSAO, 43k-poly models) is the
  current look. Pixel mode re-art is a parallel path, not an addition — realistically it is a second
  art style to maintain, and every future kit script must look right in **both**.
- **The world will fight it.** 967 km of real geography with 48 km LOD is not designed for a 480×270
  buffer; fog/lod retuning (1.4) is where most of the "it looks like art" comes from.
- **Textures are the crux.** If phase 3.4 is skipped, the game looks like a photographic image with
  big pixels — which is not Slotbound, it is just "low res".
- **Scope creep guard:** one art style, one palette, no new game modes, no sprite-based remake. The
  *actual* Slotbound-like game (2D top-down pixel art on the real map) is a different program — the
  map editor already bakes that data if it is ever wanted.

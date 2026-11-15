# Map editor

Hand-made corrections to the game's world: place buildings and props, and cut removal circles so the
procedural scatter keeps out of a spot. It is a developer tool - players never see it, and it is not
part of the exported game.

The editor is a **separate app that lives inside this project**: its own scene rather than a second
Godot project, because a nested `project.godot` cannot see the game's `res://` scripts or data. That
is why it runs with the repo root as the project path. `export_presets.cfg` has
`exclude_filter="tools/*"`, so nothing in here is packed into a release.

## Running it

```powershell
cd F:\ww2_dlss
& 'F:\godot-std\bin\godot.windows.editor.double.x86_64.console.exe' --path . tools/map_editor/map_editor.tscn
```

Use the double-precision editor build, like everything else in this repo. The first run of the day
spends a few seconds baking the base map (the imagery plus the coast, rivers and 348k road segments);
after that it is one texture blit per frame.

## What it edits

`data/map_edits.json` (see `scripts/map_edits.gd`), which the game applies on top of the procedural
world:

```json
{"version": 1, "edits": [
  {"op": "add", "id": "a1", "asset": "windmill", "lat": 49.192, "lon": -0.402, "yaw": 30.0, "scale": 1.0},
  {"op": "remove", "id": "r1", "lat": 49.18, "lon": -0.36, "radius": 25.0, "what": "all"}
]}
```

`WorldPopulator` spawns every `add` as its own small site - position, yaw and scale come from the row,
and the height is taken from the terrain. `Scatter` drops houses, trees and hedges inside a `remove`
circle, and `WorldPopulator` keeps registered sites out of one marked `sites` or `all`.

Edits ship with the game. A move is just a delete plus an add, so there are no other operations.

## Controls

| Input | Action |
| --- | --- |
| wheel | zoom about the cursor |
| right-drag or middle-drag | pan |
| `1` / `2` / `3` | Select / Place / Remove tool |
| click an asset, then the map | place it |
| `Shift`+click while placing | keep placing |
| click an edit | select it (replaces the selection) |
| `Shift`+click an edit | add it to the selection, or take it back out |
| left-drag on empty ground | rubber band: select every edit inside it |
| left-drag a selected edit | move the whole selection |
| `Q` / `E` | rotate the selection about its centre, 15 deg (`Shift`: 1 deg) |
| `[` / `]` | remove-circle radius -/+ 5 m (every selected circle) |
| `Delete` | delete the whole selection |
| `Ctrl+C` / `Ctrl+V` | copy the selected `add` rows / paste them |
| `G` | the map grid on / off |
| `V` | the 3D world window on / off |
| `Esc` | drop the selection, back to the Select tool |
| `Ctrl+Z` / `Ctrl+Y` | undo / redo |
| `Ctrl+S` | save to `data/map_edits.json` |

Every action is one undo step, moves and resizes included, and so is a whole group operation:
moving, rotating or deleting a multi-selection is a single `Ctrl+Z` away from being undone.
An autosave copy goes to `user://map_edits_autosave.json` every 60 s; only `Ctrl+S` writes the file
the game reads. The title bar shows `*` while there are unsaved changes, and quitting with unsaved
changes asks first.

## Selecting several edits

The Select tool drags out a **rubber band** on empty ground and takes every edit whose centre falls
inside it; `Shift`+click adds one edit or takes it out again. A plain click on one edit replaces the
selection with that one, and clicking empty ground drops it. The last edit picked is the *primary*
one, whose yaw or radius the toolbar shows. A thin box appears round a multi-selection, with a small
cross at the centre the group rotate turns about.

The selection lives in the editor (`sel_ids`) and cleans itself up after every undo, redo and
delete, so an id that is no longer in the document is simply dropped.

## Copy and paste

`Ctrl+C` copies the selected `add` rows (a remove circle never copies). `Ctrl+V` pastes them as one
undo step: the pasted group is centred on the mouse when it has been over the map, and dropped a
little south-east of where it was copied when it has not. Every pasted row gets a fresh id from
`MapEdits.next_id`, and the paste becomes the new selection.

## Go to

The toolbar's *go to* box searches cities and airfields (from `map_base.gd`) and the edits
themselves, by label or by id. Enter jumps the view to the best match (a whole-name match first,
then a prefix, then anything containing what was typed) and reports it in the status line; Enter
again cycles the matches.

## The 3D world window

`V` (or the *3D* button) swaps the 2D map for a **top-down view of the game's real, streamed world**
at the same spot - `map_3d.gd` builds the game's own `TerrainChunkManager` and `WorldPopulator` the
way the game does, so what you see is exactly what a player would get there: the streamed terrain,
the countryside tiles with their houses, hedges and lanes, the towns, airfields and sites, the sea,
and the hand-made edits from `data/map_edits.json`.

It exists for precision. The 2D map's imagery is ~157 m a pixel, which is fine for finding a town but
useless for judging where a house goes; the 3D window is orthographic at 1.5 m a pixel, so you can
read individual roofs and gardens. Wheel zooms (1.0-8.0 m/px), right or middle drag pans, and it
reports its lat/lon back to the editor so the 2D map follows you when you switch back. A plain left
click places the current palette asset where you clicked; selecting, dragging and remove circles stay
in the 2D view on purpose - this window is for looking, and the 2D map is for editing.

It costs about 7 s to build the world the first time and ~10-25 s before everything in view has
streamed in (the corner readout shows the tile and chunk counts while it settles). Quitting closes it
first so the game's streaming worker threads are joined cleanly.

It is **live**: every change to the document (place, move, rotate, resize, delete, paste, a new remove
circle, undo, redo) shows in the open window within 0.15 s, saved or not, and opening the window shows
the unsaved document too. Only what changed is rebuilt (`WorldPopulator.refresh_map_edits`): a placed
asset moves or turns in place, and a remove circle that appears, goes or changes drops just the
scenery tiles under it, which stream straight back in without the cut houses / trees / hedges. A
`sites` (or `all`) circle keeps new sites out but does not take down a town or airfield that is
already standing; that only happens when the world is next built from the saved file (save, then
close and reopen the window), as in the game.
Self-test: `--editor-3d --editor-place=<asset>` places the asset at the 3D view's centre half way to
the `--editor-shot` frame.

## Grid

`G`, or the Grid button, draws a map-space grid. It is adaptive: the step is the smallest of
1, 2, 5, 10, 20, 50, 100, 200, 500 km whose cell would be at least 60 px wide, halved once when
that would be wider than 120 px, so the lines always land 60-120 px apart. The step is written
beside the scale bar ("grid 5 km"). It is a visual aid only: nothing snaps to it.

## Files

- `map_editor.gd` - the app shell: palette, tools, selection, keyboard, save and autosave.
- `map_view.gd` - the 2D view: baked base map, edit icons, remove circles, the map grid, the
  rubber band and pan / zoom.
- `edit_selection.gd` - selection and group-edit maths: the rubber-band test, Shift+click
  toggling, the group move / rotate / delete / paste commands and the go-to matcher (pure, unit
  tested).
- `map_base.gd` - bakes the imagery, coast, rivers and roads once, and owns the road grid used when
  zoomed in.
- `map_transform.gd` - lat/lon <-> screen maths (pure, unit tested).
- `edit_history.gd` - the undo/redo command stack (pure, unit tested).

## Tests

Headless, from the repo root:

```powershell
& 'F:\godot-std\bin\godot.windows.editor.double.x86_64.console.exe' --headless --path . scenes/tests.tscn
```

`tools/tests.gd` covers `EditHistory` (do, undo, redo, branching, move, rotate, radius, and a group
command being one step), `MapTransform` (round trips, zoom about a point, scale bar), the
add / move / rotate / delete round trip through `MapEdits`, and `EditSelection` (the rubber band,
Shift+click toggling, group move / rotate / delete as one undo step, copy and paste with fresh ids,
the go-to matcher, the selection cleaning up after an undo, and the adaptive grid step).

## Checking the drawing without a window

`_draw()` never runs under `--headless`, so the editor has its own screenshot hook. Run it on the
hidden desktop (it must not steal focus from whatever else is open):

```powershell
& .\tools\hidden\hidden_run.ps1 -Exe 'F:\godot-std\bin\godot.windows.editor.double.x86_64.exe' `
  -ArgLine "--path . tools/map_editor/map_editor.tscn --log-file build\editor.log -- --editor-shot=build\medit.png --editor-frames=120 --editor-zoom=24 --editor-at=49.18,-0.36" `
  -TimeoutSec 200
```

`--editor-shot` renders real frames, saves a PNG and quits; `--editor-zoom` and `--editor-at=lat,lon`
frame a particular spot, `--editor-select=a1,a2` preselects edits (to see a multi-selection) and
`--editor-grid=0` hides the grid. Results land in `build/` (git-ignored). For example, a
multi-selection with the grid on:

```powershell
& .\tools\hidden\hidden_run.ps1 -Exe 'F:\godot-std\bin\godot.windows.editor.double.x86_64.exe' `
  -ArgLine "--path . tools/map_editor/map_editor.tscn --log-file build\editor.log -- --editor-shot=build\p4_multi.png --editor-frames=120 --editor-zoom=24 --editor-at=49.18,-0.36 --editor-select=a1,a2,r1" `
  -TimeoutSec 200
```

## One-command check

`selfcheck.ps1` is the whole editor check in one command, from anywhere:

```powershell
.\tools\map_editor\selfcheck.ps1
```

It finds the repo root from its own location, so it works the same in a worktree as in the main
checkout, and runs three steps in order, stopping at the first failure:

1. **headless import** - `--headless --path <root> --import --quit`; fails on any `SCRIPT ERROR` or
   `Parse Error` in the output;
2. **the full test scene** - `--headless --path <root> scenes/tests.tscn`; fails unless the output
   contains `TESTS OK`;
3. **one render** on the hidden desktop via `tools\hidden\hidden_run.ps1` with `--editor-shot`, so
   the drawing code really runs without a window appearing; fails if the PNG is missing or 0 bytes.

It prints `SELFCHECK OK`, or `SELFCHECK FAILED: <why>` with a non-zero exit code. The log and the
picture land in `build\mis\` (`selfcheck.log`, `editor_selfcheck.png`, both git-ignored). Use
`-RepoRoot <path>` / `-Godot <exe>` to check another checkout or Godot build. It waits for any
`godot*.exe` that is already running to finish before it starts, so it is safe to launch next to
someone else's test run.

## Desktop shortcut

`make_shortcut.ps1` puts **Map Editor.lnk** on your desktop:

```powershell
.\tools\map_editor\make_shortcut.ps1
```

The shortcut starts the non-console double-precision Godot (the console build flashes a window) as
`--path <repo root> tools/map_editor/map_editor.tscn`, with the repo root as the working directory,
so a double-click opens the editor on this checkout. The repo root and the exe path are **baked into
the .lnk when it is created** - nothing is worked out at click time - so the shortcut belongs to one
checkout and stops working when the repo or the Godot build moves. Re-run the script after moving
either; an existing "Map Editor.lnk" is replaced silently. If the exe is missing it refuses to write
a shortcut at all rather than leave a dead one on the desktop, and it prints the .lnk path, target
and arguments it used.

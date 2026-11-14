# Debug tool: headless scenarios, state logs and a browser viewer

Full-game testing is slow. This runs the real `Airfield` + `Aircraft` + `TaxiController` headless, with no
terrain or world, in about 10 s wall time, and writes a compact JSON state log you can replay in a browser
or query from scripts.

## Quick start

```bash
python tools/dbg/dbg.py run --style raf_bomber --wingmen 3        # simulate -> build/dbg/raf_bomber.json, prints findings
python tools/dbg/dbg.py serve                                      # viewer at http://127.0.0.1:8765/
python tools/dbg/dbg.py check raf_bomber                           # analyse a log, exit 1 if there are findings
python tools/dbg/dbg.py at raf_bomber 42.5                         # every aircraft at t=42.5 s
python tools/dbg/regress_taxi.py                                   # every style, assert no findings
python tools/dbg/regress_taxi.py --aircraft lancaster "--extra=--player-hold --release-after=40"   # variants
python tools/dbg/png.py raf_bomber                                 # top-down PNG of a run (no browser needed)
```

PowerShell equivalent of `run`: `tools/dbg/run.ps1 -Style raf_bomber -Wingmen 3 [-Secs 150] [-Extra "--spot=2 --player-hold"]`.
It uses `--headless` so it never opens a window or takes focus.

## Pieces

| file | what |
|---|---|
| `scenes/dbg.tscn`, `tools/dbg/scenario.gd` | the headless runner (Godot, `--fixed-fps 60`). Args after `--`: `--style= --wingmen= --secs= --aircraft= --heading= --hz= --out= --player-hold --release-after= --props=0/1 --log` (TaxiController state every 2 s on stdout). The flight is the field's `Airfield.taxi_flight` plan |
| `tools/dbg/dbg.py` | CLI, analysis and the HTTP/JSON server. Findings: overlap, off_route, stuck, wp_stall, wrong_way (a route that doubles back, an aircraft parked facing away from its first leg, or one driving against its leg), spot_on_route (a route past another member's parked spot), prop_on_route (a tall airfield mesh on a route), deadlock (nobody taxiing moved for 30 s, tower holds excepted), no_line_up |
| `tools/dbg/png.py` | renders a run to `build/dbg/<name>.png`: pavement, taxi graph, dispersals, holds, routes, trails |
| `tools/dbg/viewer/index.html` | top-down playback: pavement, taxi graph, routes, hold-short, props, aircraft (colour = state), trails, red rings on overlaps; Space plays, arrows step, wheel zooms, drag pans, drop a `.json` to load it |
| `tools/dbg/regress_taxi.py` | runs every airfield style and fails on any finding |

## HTTP API (while `serve` runs)

`GET /api/runs`, `/api/run?name=`, `/api/summary?name=`, `/api/at?name=&t=`, and
`/api/sim?style=&wingmen=&secs=&name=&extra=` (runs the headless scenario and returns the summary).

## Log format (`build/dbg/<name>.json`)

Coordinates are in the airfield's local frame: x right, z along the runway, take-off toward -Z, yaw in degrees
clockwise from the take-off direction. `layout` holds the runway, paved segments `[from, to, half_width]`, taxi graph,
hold-short, entry, dispersals and tall props `[cx, cz, half_x, half_z, yaw, height, name]`. `agents` has each
aircraft's planned route. `frames` is `[t, [[id, x, z, yaw, speed, state, wp, throttle, brake], ...]]` at `hz`.
States: `parked`, `waiting` (on its spot until the aircraft ahead has passed where their routes meet), `taxiing`,
`queued` (stopped behind the aircraft ahead), `holding` (at the hold-short until cleared), `stopped` (for no reason:
counts toward `stuck`), `lined_up`. `layout.flight` is the plan's dispersal indices (player first), `layout.holds` the hold-shorts.

## Keep in sync

`scenario.gd` mirrors `Main._taxi_route_for` (the player's route: `Airfield.flight_route(0, ...)`, `auto_clear`),
`ModeBase._taxi_wingmen_tick` (wingmen from `Airfield.taxi_flight` in order, each `TaxiController.follow`ing the one
before) and the release chain in `Main`/`ModeBase` (each aircraft clears the next when it lines up). The route
planning and driving themselves are shared code (`Airfield`, `TaxiController`). If the spawning logic changes, update the runner.

## Model and asset viewer

`http://127.0.0.1:8765/assets.html` (three.js from unpkg, needs internet in the browser):

* **Models** - every `assets/models/*.glb`: orbit view, wireframe/flat toggles, side/top/front, a distance slider with the
  on-screen pixel width at that distance, node toggles (hide decals, gear...) and the painted livery sheet. The glbs have no
  UVs (the game maps skins in a shader), so the viewer tints by nation rather than showing the livery on the mesh.
* **Textures** - every png/jpg under `assets/`: original plus the same texture tiled 4x4 at 1/2, 1/4, 1/8, 1/16 scale, to spot
  patterns and moire at distance. Deep links: `?model=spitfire`, `?tex=textures/world/asphalt.png`.

CLI/API for scripts: `dbg.py models [id]` (tris, size, nodes, missing contract nodes, liveries), `dbg.py textures`,
`dbg.py check-models` (exit 1 on a bad glb: too few tris, implausible size, missing `CockpitEye`/`GearL`/`GearR`/`Muzzle*`,
no livery), and `GET /api/models`, `/api/model?id=`, `/api/glb?id=`, `/api/textures`, `/api/tex?path=`, `/api/check_models`.

## Airfield dressing check

`godot --headless --path . tools/dbg/dress_check.tscn -- [--styles=triangle,cross] [--no-tris]` builds every layout
with its parked aircraft, P8 furniture, service vehicles (AirfieldActivity) and crate / drum stacks (AirfieldStores),
fails if a vehicle loop crosses a runway or a stack stands on a runway, pavement, taxi-out route or parked aircraft,
prints each parked type's near / far triangle counts, and writes `build/dbg/dress_<style>.json`.
`python tools/dbg/dress_svg.py build/dbg/dress_triangle.json` draws one top-down.

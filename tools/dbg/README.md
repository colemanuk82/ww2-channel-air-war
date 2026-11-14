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
```

PowerShell equivalent of `run`: `tools/dbg/run.ps1 -Style raf_bomber -Wingmen 3 [-Secs 150] [-Extra "--spot=2 --player-hold"]`.
It uses `--headless` so it never opens a window or takes focus.

## Pieces

| file | what |
|---|---|
| `scenes/dbg.tscn`, `tools/dbg/scenario.gd` | the headless runner (Godot, `--fixed-fps 60`). Args after `--`: `--style= --wingmen= --secs= --aircraft= --heading= --spot= --hz= --out= --player-hold --release-after= --props=0/1` |
| `tools/dbg/dbg.py` | CLI, analysis (overlap, off_route, stuck, wp_stall, no_line_up) and the HTTP/JSON server |
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
States: `parked`, `taxiing`, `holding`, `stopped`, `lined_up`.

## Keep in sync

`scenario.gd` mirrors `ModeBase._taxi_wingmen_tick` (wingman spawning) and the release chain in
`Main`/`ModeBase` (each aircraft clears the next when it lines up). If that logic changes, update the runner.

## Planned (phase 2)

Model/asset viewer in the same page: glTF export of the procedural aircraft/props, three.js viewer, texture and
material pattern previews at several distances.

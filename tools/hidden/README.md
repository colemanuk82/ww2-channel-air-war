# Running the game without disturbing the desktop

Automated runs (screenshots, real-time checks, tests) must never open a visible window or take keyboard focus:
the developer is usually working in other apps while they run.

## How

* **Tests / import** need no rendering: `test.ps1` (runs `imp.ps1` then `scenes/tests.tscn`) uses `--headless`.
* **Anything that needs pictures** goes through `hidden_run.ps1`. It creates a second Windows desktop
  (`CreateDesktop("ClaudeShots")`), which is never shown, and starts the *non-console* Godot exe on it
  (`STARTUPINFO.lpDesktop = "WinSta0\ClaudeShots"`). The GPU still renders normally (50-60 fps on the
  RTX 4070 SUPER), but the window cannot appear on the user's screen or steal focus. The script waits for
  the process (with a timeout, after which it is killed) and closes the desktop.
* Output goes to `--log-file` (there is no console), screenshots via the game's own `--ui-shot=path`
  (taken `--shot-delay=N` game-seconds after the menu starts).

Do **not** use `--minimized`, `Start-Process -WindowStyle Minimized`, an off-screen `--position`, or the
console exe for picture runs: all of them still flash a window or take focus.

## Scripts

| script | what |
|---|---|
| `hidden_run.ps1 -Exe <exe> -ArgLine "<args>" [-TimeoutSec N]` | run anything on the hidden desktop |
| `shot.ps1 -Out <png> -Delay N -GameArgs "<debug args>"` | one screenshot with any game debug args |
| `introshots.ps1 [t1 t2 ...]` | frozen frames of the opening film (`--intro=t --intro-freeze`) |
| `realshots.ps1 start,delay ...` | real-time intro frames (`--intro-debug` logs t / fps / terrain / bombs) |
| `uishots.ps1 menu controls controls-flight ...` | start menu / Options pages (`WW2_SETTINGS_PAGE`, `WW2_CONTROLS_SUB`) |
| `filmshots.ps1 chapter,seconds ...` | Training Film frames (`--film=`) |
| `test.ps1` | headless import + test suite (expects `TESTS OK`) |

Notes: the first second after launch runs slowly while shaders compile, so real-time captures need about
15-20 s extra `--shot-delay`. Results land in `build/mis/` (git-ignored).

## Liveries

* `livery_build.ps1 [-Only spitfire,bf109]` - export the unwrapped skin geometry (headless), paint the liveries
  (python, numpy + Pillow) and re-import. `livery_geo.ps1` does only the export.
* `galshot.ps1 -Name x -GalArgs "--ids=bf109 --view=three"` - one model gallery shot on the hidden desktop;
  `livgal_all.ps1 [-View three] [-Ids a,b]` - one shot per aircraft (`build/gal/L_<id>_<view>.png`).

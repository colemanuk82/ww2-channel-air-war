#!/bin/bash
# v6.7 release: world visual pass - sea fixed (height-fog veil), moonlit water, wakes, plumes, flood, light shafts, airfield life.
# Sequence: test gate -> version bump -> import -> export -> smoke-test the EXPORTED binary -> commit/push -> release.
# Aborts before any commit, push or release if the tests or the exported build misbehave.
cd /f/ww2_dlss || exit 1
EXE="F:/godot-rtx/bin/godot.windows.editor.x86_64.console.exe"
FAIL=0

echo "=== 1. test gate (must be all green before anything is published) ==="
timeout 500 "$EXE" --headless --path "F:/ww2_dlss" scenes/tests.tscn > build/release_tests.log 2>&1
echo "  tests exit=$?"
grep -aE "TESTS OK|TESTS FAILED" build/release_tests.log | tail -2
if ! grep -qa "TESTS OK" build/release_tests.log; then echo "ABORT: tests did not pass"; exit 1; fi

echo "=== 2. version bump ==="
python3 - <<'PY'
import re
p = "project.godot"
s = open(p, encoding="utf-8").read()
s2 = re.sub(r'config/version="[^"]*"', 'config/version="6.7"', s, count=1)
open(p, "w", encoding="utf-8", newline="").write(s2)
print(" ", re.search(r'config/version="[^"]*"', s2).group(0))
PY

echo "=== 3. import ==="
"$EXE" --headless --path "F:/ww2_dlss" --import --quit > build/release_import.log 2>&1
echo "  import exit=$?"
grep -aE "SCRIPT ERROR|Parse Error|Failed to load" build/release_import.log | grep -v "signed by NVIDIA" | sort -u | head -5

echo "=== 4. export ==="
"$EXE" --headless --path "F:/ww2_dlss" --export-release "Windows Desktop" "F:/ww2_dlss/build/WW2ChannelAirWar.exe" > build/release_export.log 2>&1
echo "  export exit=$?"
[ -s build/WW2ChannelAirWar.exe ] || { echo "ABORT: no exe produced"; exit 1; }
ls -la build/WW2ChannelAirWar.exe | awk '{print "  exe bytes:", $5}'

echo "=== 5. smoke-test the EXPORTED binary ==="
timeout 300 "F:/ww2_dlss/build/WW2ChannelAirWar.exe" --no-window --quit-after 90 -- --skip-menu --air --cockpit --autopilot --aircraft=hurricane --plan=51.5,0.5,-,1,900,90 --frames=150 > build/release_smoke.log 2>&1
echo "  smoke exit=$?"
SMOKE=$(grep -aE "SCRIPT ERROR|Parse Error|Failed to load|Cannot open|not work on export" build/release_smoke.log | grep -v "signed by NVIDIA" | sort -u)
if [ -n "$SMOKE" ]; then echo "  --- smoke findings ---"; echo "$SMOKE" | head -10; FAIL=1; else echo "  clean: no script errors from the exported build"; fi
grep -a "HeightField: loaded" build/release_smoke.log | head -1 | sed 's/^/  /'

echo "=== 6. zip ==="
python3 - <<'PY'
import zipfile, glob, os
os.chdir("build")
name = "WW2ChannelAirWar_v6.7_win64.zip"
if os.path.exists(name): os.remove(name)
files = ["WW2ChannelAirWar.exe"] + sorted(os.path.basename(d) for d in glob.glob("*.dll"))
with zipfile.ZipFile(name, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        if os.path.exists(f): z.write(f, f)
print("  packed:", len(files), "files ->", name, os.path.getsize(name)//1024, "KB")
PY

if [ "$FAIL" != "0" ]; then echo "=== ABORTED: the exported binary reported errors; nothing committed, pushed or released ==="; exit 1; fi

echo "=== 7. commit + push ==="
git add project.godot HANDOFF.md scripts/airfield.gd scripts/dam_campaign.gd scripts/effects/fx.gd scripts/ground/dam_flood.gd scripts/ground/dam_kit.gd scripts/ground/scatter.gd scripts/hud.gd scripts/main.gd scripts/sun_glare.gd scripts/time_of_day.gd scripts/water_plane.gd scripts/weapons/weapon_world.gd scripts/effects/fx_particles.gd shaders/terrain.gdshader shaders/water.gdshader scripts/ground/player_ground_crew.gd scripts/ground/player_ground_crew.gd.uid scripts/ground/wind_sock.gd scripts/ground/wind_sock.gd.uid shaders/flood.gdshader shaders/flood.gdshader.uid shaders/god_rays.gdshader shaders/god_rays.gdshader.uid tools/fm_sim.gd.uid tools/vis_shots.sh tools/release_v67.sh screenshots/v67_before_after.jpg
git commit -q -F - <<'MSG'
World visual pass: the sea fixed, moonlit water, wakes, plumes, flood, light shafts (v6.7)

- Root cause of the white/flat sea and washed-out airfields: Godot height fog is not
  distance based. fog_height 120 / density 0.006 laid a 51% veil of fog colour over the
  sea right under the camera and ~25% over every airfield. Found by instrumenting the water
  shader (painted red -> rendered pink; sea hidden -> seabed equally pale). Height fog off.
- Sea: grey-green body, Fresnel sky reflection (new sky_top/sky_horizon globals), own
  ambient, view-space normals, irregular swell + chop + ripples, soft glints and a sheen
  that draws sun/moon glitter paths, wind-lane foam and small whitecaps, lacy surf, smooth
  depth tint, cloud shadows, drawn first among transparents so spray shows over it.
- Night: lower moon lays a path on the sea and on the dam reservoirs (water shader in lake
  mode); Chastise days flown at night.
- Ship wakes (Kelvin arms, churned track, bow wave) from the 4 nearest ships.
- Bomb plumes in the sea and reservoirs (column, crown, base surge, mist, slick).
- Dam breach: churning flood shader, spray and mist at the gap and the surge front.
- Screen-space god rays with a low sun; volumetric haze thickens at dawn/dusk.
- Airfields: wind sock follows the real wind; ground crew, trolley-acc and chocks at the
  player's aircraft walk clear when the throttle opens.
- FX particles and tracers were culled beyond 100 km of the origin (no smoke, fire, flak
  or spray over Germany at all): their bounds now cover the whole map.
- Procedural ponds rarer/darker; HUD VSI/THR text moved below the dials.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NzrQetBF6JFr4GXrmTXfbZ
MSG
echo "  commit: $(git log --oneline -1)"
GIT_TERMINAL_PROMPT=0 timeout 600 git push origin main 2>&1 | tail -3

echo "=== 8. gh release ==="
gh release create v6.7 "build/WW2ChannelAirWar_v6.7_win64.zip" \
  --title "v6.7 - the sea fixed, moonlit water, wakes, plumes, flood and light shafts" \
  --notes "**The sea finally looks like water.** The long-standing white, flat sea (and the washed-out look at low level over airfields) was a fog setting that laid a 50% veil of haze over everything near sea level, however close. It is gone, and the sea has been redone: grey-green Channel water that reflects the sky, sun and moon glitter, wind-blown foam lanes and whitecaps, surf on the shallows and drifting cloud shadows.

**Night.** The moon lays a shimmering path across the sea and across the dam reservoirs, and the Operation Chastise days are now flown at night.

**Ships** leave long V-shaped wakes. **Bombs in the water** throw up a tall white column with a crown of spray and a lingering foam slick, including the Upkeep at the dams. **A breached dam** pours churning muddy floodwater down the valley under a cloud of spray and mist.

**Smoke, fire, flak and spray over Germany** were never drawn (a culling box only covered 100 km round the map origin); they are now, including at the dams.

**Light shafts** stream from a low sun, and the haze thickens at dawn and dusk.

**Airfields:** the wind sock streams with the real wind, and on a ground start your own crew stands by with a trolley-acc and chocks, then walks clear when you open the throttle.

Gate: tests green, exported binary smoke-tested before publishing." 2>&1 | tail -3
echo "=== RELEASE SEQUENCE COMPLETE ==="

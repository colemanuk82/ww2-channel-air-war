#!/bin/bash
# v7.21 release: the rest of the ElevenLabs credits spent on radio voice takes (spotting with height, more chatter, Ops briefings).
# Sequence: import -> test gate -> version bump -> import -> export -> smoke-test the EXPORTED binary -> zip -> commit/push -> release.
# Aborts before any commit, push or release if the tests or the exported build misbehave.
cd /f/ww2_dlss || exit 1
mkdir -p build
EXE="F:/godot-rtx/bin/godot.windows.editor.x86_64.console.exe"
FAIL=0

echo "=== 0. import first (rebuilds the class cache the tests need) ==="
"$EXE" --headless --path "F:/ww2_dlss" --import --quit > build/release_import0.log 2>&1
echo "  import exit=$?"

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
s2 = re.sub(r'config/version="[^"]*"', 'config/version="7.21"', s, count=1)
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

echo "=== 6. zip (exe + every DLL the game needs, copied from the project root) ==="
cp -f /f/ww2_dlss/*.dll build/ 2>/dev/null
python3 - <<'PY'
import zipfile, glob, os
os.chdir("build")
name = "WW2ChannelAirWar_v7.21_win64.zip"
if os.path.exists(name): os.remove(name)
files = ["WW2ChannelAirWar.exe"] + sorted(os.path.basename(d) for d in glob.glob("*.dll"))
with zipfile.ZipFile(name, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        if os.path.exists(f): z.write(f, f)
print("  packed:", len(files), "files ->", name, os.path.getsize(name)//1024, "KB")
PY

if [ "$FAIL" != "0" ]; then echo "=== ABORTED: the exported binary reported errors; nothing committed, pushed or released ==="; exit 1; fi

echo "=== 7. commit + push ==="
git add project.godot tools/release_v721.sh HANDOFF.md scripts/medal_ceremony.gd scripts/effects/aircraft_damage_model.gd \
  scripts/aircraft.gd scripts/weapons/weapon_world.gd scripts/weather_manager.gd scripts/cloud_field.gd scripts/hud.gd \
  scripts/main.gd scripts/menu.gd scripts/newsreel_card.gd scripts/pilot_log.gd shaders/fx_puff.gdshader scripts/effects/fx.gd \
  shaders/fx_column.gdshader scripts/ground/battle_scene.gd
# AI ground / naval strikes (written separately on 2026-10-13, already in the v7.20 build): committed with v7.21
git add scripts/ai/ai_pilot.gd scripts/effects/sky_war.gd scripts/ground/ground_ship.gd scripts/ground/military_depth_kit.gd \
  scripts/modes/flying_bomb.gd data/military_depth_1940.json
git add scripts/medal_ceremony.gd.uid scripts/effects/aircraft_damage_model.gd.uid shaders/fx_column.gdshader.uid 2>/dev/null
git commit -q -F - <<'MSG'
Medal ceremonies, visible battle damage, moving weather fronts, night smoke, newsreel news (v7.21)

- Medal ceremony: each decoration is presented with the medal drawn on its ribbon and a citation written from the
  pilot's record, once it is safe (landed and stopped, over the results, or at the start menu). Earlier awards
  are presented once.
- Visible damage: hits land on parts (wings, tail, engine, cockpit). Bullet holes and torn panels are projected
  decals snapped to the nearest real vertex of each aircraft's own meshes and oriented to its normal, sized to
  the aircraft, so they sit flush on every type. A badly holed wing loses its aileron (ragged gap, debris).
  Handling follows: the holed wing drops, roll rate falls with a lost aileron, a hit tail makes pitch heavy and
  the nose wander, engine hits cost power, holes add drag. Cockpit: cracked canopy and oil on the windscreen.
- Weather fronts: a cold or warm front moves across the map with the wind; weather and the clouds themselves
  follow which side of it you are on (thickening cloud, a rain / thunderstorm band, showers, clearing). Shown on
  the minimap in weather-map style; Sector Control / Jafü warn of its approach and passage.
- Night smoke: blast columns were 26 lit spheres with gaps that caught the blue night sky; now 64 overlapping
  puffs with a soft translucent shader. Smoke uses its own distance haze, darkened at night (the engine aerial perspective tinted
  distant smoke sky-blue, so columns looked like strings of blue beads).
- The start-up newsreel leads with the pilot's own news: decorations, promotions, kills, ships, sorties.
- Also committed: AI pilots' rocket / bomb strikes on ships and ground targets (ai_pilot STRIKE state, sky war,
  ground ships, military depth kit, flying bomb), written separately on 13 Oct and already in the v7.20 build.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013ApSn3cDWsLo4GEguHKh1e
MSG
echo "  commit: $(git log --oneline -1)"
GIT_TERMINAL_PROMPT=0 timeout 600 git push origin main 2>&1 | tail -3

echo "=== 8. gh release ==="
gh release create v7.21 "build/WW2ChannelAirWar_v7.21_win64.zip" --repo colemanuk82/ww2-channel-air-war \
  --title "v7.21 - medal ceremonies, battle damage, weather fronts" \
  --notes "**Medals.** Each decoration is now presented: the medal on its ribbon and a citation from your own record, once you've landed, after the mission or at the start menu.

**Battle damage.** Hits leave bullet holes that sit flush on every aircraft type, and a shot-up wing can lose its aileron. Handling follows the damage: a holed wing drops, a lost aileron cuts roll rate, a hit tail makes the nose wander, engine hits cost power. In the cockpit the canopy cracks and oil smears the windscreen.

**Weather fronts.** Cold and warm fronts now move across the map: thickening cloud, a band of rain or thunderstorms, showers, then clearing. You can see the wall of cloud coming, it's drawn on the minimap, and Control warns you before it arrives.

**Polish.** Smoke columns at night no longer look like strings of blue beads. The start-up newsreel leads with your own news.

Gate: tests green, exported binary smoke-tested before publishing." 2>&1 | tail -3
echo "=== RELEASE SEQUENCE COMPLETE ==="

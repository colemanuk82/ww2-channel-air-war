#!/bin/bash
# v7.0 release: fireworks night - more flak, lingering explosions, bigger formations, V-1/V-2 blitz, city fires.
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
s2 = re.sub(r'config/version="[^"]*"', 'config/version="7.0"', s, count=1)
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
name = "WW2ChannelAirWar_v7.0_win64.zip"
if os.path.exists(name): os.remove(name)
files = ["WW2ChannelAirWar.exe"] + sorted(os.path.basename(d) for d in glob.glob("*.dll"))
with zipfile.ZipFile(name, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        if os.path.exists(f): z.write(f, f)
print("  packed:", len(files), "files ->", name, os.path.getsize(name)//1024, "KB")
PY

if [ "$FAIL" != "0" ]; then echo "=== ABORTED: the exported binary reported errors; nothing committed, pushed or released ==="; exit 1; fi

echo "=== 7. commit + push ==="
git add project.godot HANDOFF.md shaders/fx_puff.gdshader scripts/effects/fx.gd scripts/effects/sky_war.gd scripts/effects/sky_war.gd.uid scripts/effects/city_fires.gd scripts/effects/city_fires.gd.uid scripts/modes/v2_rocket.gd scripts/modes/v2_rocket.gd.uid scripts/modes/flying_bomb.gd scripts/ground/aa_gun.gd scripts/world_populator.gd scripts/ai/bomber_formation.gd scripts/sortie_manager.gd scripts/modes/escort_mode.gd scripts/weapons/weapon_world.gd scripts/main.gd tools/vis_shots.sh tools/release_v70.sh
git commit -q -F - <<'MSG'
Fireworks night: more flak, lingering bursts, bigger formations, V-1/V-2 blitz, city fires (v7.0)

- Twice the heavy flak at every defended site, half as many again light guns and searchlights; 88s fire
  3-round salvos and put up sound-located barrages at night.
- Flak smoke hangs for 20-30 s and drifts; explosions leave smoke and a pall for half a minute; bright
  flashes and glowing fragments after dark; smoke dims properly at night.
- SkyWar: distant flak salvos, light-flak tracer streams, searchlight cones, raids on towns with bomb
  flashes and fires, ambient V-1s and V-2s at London.
- V-2 rocket: slow lift-off, heavy white trail, out of sight, falls minutes later without warning.
- CityFires: bombs, V-1s and V-2s set towns alight - flames, glow, plumes and a great pall over a burning town.
- Bomber formations twice as large, flown as vics stacked in a combat box.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NzrQetBF6JFr4GXrmTXfbZ
MSG
echo "  commit: $(git log --oneline -1)"
GIT_TERMINAL_PROMPT=0 timeout 600 git push origin main 2>&1 | tail -3

echo "=== 8. gh release ==="
gh release create v7.0 "build/WW2ChannelAirWar_v7.0_win64.zip" \
  --title "v7.0 - fireworks night: flak, the V-weapons blitz and burning towns" \
  --notes "**The sky is full of it now.**

- **Lots more flak.** Every defended target has twice the heavy guns, and more light guns and searchlights. The 88s fire three-round salvos, and at night they put up a barrage even at aircraft the searchlights haven't caught.
- **Bursts that hang in the air.** Flak smoke stays for 20-30 seconds and drifts with the wind, so a barrage leaves the sky smudged with black puffs. Explosions leave smoke and a dirty pall for half a minute.
- **Fireworks night.** After dark every burst is a bright flash with glowing fragments, streams of red, orange, yellow and green light-flak tracer hose up out of the dark, and searchlight cones sweep over whatever is being attacked. Flak goes off in the distance all the time, by day now and then.
- **Raids on towns.** In free flight you will see towns being bombed miles away: bomb flashes, flak over them, searchlights, and fires taking hold.
- **Burning cities.** Bombs, V-1s and V-2s that land in a town start fires that burn for minutes, with a glow on the streets and leaning black plumes. A town with several fires gets a great pall of smoke over it.
- **V-1s and V-2s.** Flying bombs drone in toward London (shoot them down). V-2 rockets lift off from the Pas-de-Calais on a roaring flame and a towering white trail, disappear upward, and minutes later land in London without warning.
- **Bigger bomber formations.** Formations are twice the size, flown as vics stacked in a combat box.

Gate: tests green, exported binary smoke-tested before publishing." 2>&1 | tail -3
echo "=== RELEASE SEQUENCE COMPLETE ==="

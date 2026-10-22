#!/bin/bash
# v7.17 release: soft fire glow (no red square), livelier Ops Room taskings, 227 new voice takes, proper ground crew, 3-step map key.
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
s2 = re.sub(r'config/version="[^"]*"', 'config/version="7.17"', s, count=1)
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
name = "WW2ChannelAirWar_v7.17_win64.zip"
if os.path.exists(name): os.remove(name)
files = ["WW2ChannelAirWar.exe"] + sorted(os.path.basename(d) for d in glob.glob("*.dll"))
with zipfile.ZipFile(name, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        if os.path.exists(f): z.write(f, f)
print("  packed:", len(files), "files ->", name, os.path.getsize(name)//1024, "KB")
PY

if [ "$FAIL" != "0" ]; then echo "=== ABORTED: the exported binary reported errors; nothing committed, pushed or released ==="; exit 1; fi

echo "=== 7. commit + push ==="
git add project.godot tools/release_v717.sh tools/make_voice_variants.py tools/make_voice_ops.py \
  scripts/main.gd scripts/radio.gd scripts/hud.gd scripts/bombsight.gd scripts/modes/ops_room.gd \
  scripts/effects/city_fires.gd scripts/effects/fx.gd scripts/effects/ground_glow.gd scripts/ground/burning_ruin.gd \
  scripts/ground/crew_figure.gd scripts/ground/player_ground_crew.gd scripts/ground/ground_vehicle.gd \
  shaders/fx_puff.gdshader shaders/fx_ground_glow.gdshader HANDOFF.md \
  assets/voice/voice_variants.csv assets/voice/voice_ops.csv assets/voice/allies assets/voice/axis assets/voice/ops
git add scripts/effects/ground_glow.gd.uid scripts/ground/crew_figure.gd.uid shaders/fx_ground_glow.gdshader.uid 2>/dev/null
git commit -q -F - <<'MSG'
Soft fire glow, livelier Ops Room, more voice takes, proper ground crew, map key steps (v7.17)

- Fires: the 300-400 m omni lights that lit a hard-edged red square of ground and trees are now short-range;
  a soft, round, flickering firelight pool is draped over the terrain instead (GroundGlow). The city-fire halo
  fades where it meets the ground, explosion flashes are capped, and flames and smoke fade softly where they
  meet the terrain (soft particles) instead of ending in a flat edge.
- Ops Room: follow-up jobs close to the last one, shorter gaps between taskings, runs of successes earn bonus
  points and commendations, out of ammunition scrubs the job and sends you home to rearm, voiced text now
  matches its recording, twist calls no longer quote old time limits.
- Voice: 227 new takes - bandit/bomber spotting calls, kills, hits, replies, tower, take-off, scramble, lost
  contact, 17 more chatter lines, Ops openers, follow-ups, success/fail/hit calls. Only recorded takes are used.
- Ground crew: jointed CrewFigure people in RAF/Luftwaffe working dress and poses (working, kneeling, reaching,
  walking, waving) replace the capsules and boxes; a real trolley accumulator with its cable, rope-tied chocks;
  the crew stand beside and behind the wing, never in front of the aircraft; dispersal crews work with kit.
- Map key: small minimap -> large minimap -> full-screen chart -> small again.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013ApSn3cDWsLo4GEguHKh1e
MSG
echo "  commit: $(git log --oneline -1)"
GIT_TERMINAL_PROMPT=0 timeout 600 git push origin main 2>&1 | tail -3

echo "=== 8. gh release ==="
gh release create v7.17 "build/WW2ChannelAirWar_v7.17_win64.zip" \
  --title "v7.17 - fire glow, livelier Ops Room, more voices, proper ground crew" \
  --notes "**Fires.** No more red square round ground fires: a soft, flickering pool of firelight on the terrain replaces the huge lights, and flames and smoke fade softly into the ground.

**Ops Room (free flight).** Follow-up jobs near the last one, shorter waits between taskings, bonus points for runs of successes, and an out-of-ammunition call that sends you home to rearm.

**Voices.** 227 new recorded takes for the calls heard most - spotting calls, kills, hits, replies, tower, take-off and Ops Room calls - plus more background chatter.

**Ground crew.** Proper erks in working dress (working, kneeling, walking, waving) instead of capsules, a real trolley accumulator with its cable, and chocks; they stand beside and behind the wing.

**Map key (M).** Small minimap, then large, then the full-screen chart.

Gate: tests green, exported binary smoke-tested before publishing." 2>&1 | tail -3
echo "=== RELEASE SEQUENCE COMPLETE ==="

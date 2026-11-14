#!/bin/bash
# v6.6 release: hands-off level flight for every aircraft, visible Dam Busters rings, spotlight altimeter.
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
s2 = re.sub(r'config/version="[^"]*"', 'config/version="6.6"', s, count=1)
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
name = "WW2ChannelAirWar_v6.6_win64.zip"
if os.path.exists(name): os.remove(name)
files = ["WW2ChannelAirWar.exe"] + sorted(os.path.basename(d) for d in glob.glob("*.dll"))
with zipfile.ZipFile(name, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        if os.path.exists(f): z.write(f, f)
print("  packed:", len(files), "files ->", name, os.path.getsize(name)//1024, "KB")
PY

if [ "$FAIL" != "0" ]; then echo "=== ABORTED: the exported binary reported errors; nothing committed, pushed or released ==="; exit 1; fi

echo "=== 7. commit + push ==="
git add project.godot HANDOFF.md scripts/aircraft.gd scripts/hud.gd scripts/dam_campaign.gd scripts/modes/dam_run_mode.gd scripts/modes/training_mode.gd tools/fm_sim.gd tools/fm_sim.tscn tools/release_v66.sh screenshots/dam_rings_before_after.png screenshots/dam_ring_closeup.png
git commit -q -F - <<'MSG'
Hands-off level flight for every aircraft; Dam Busters rings you can see (v6.6)

Flight model (all 29 types):
- The auto-trim aimed for the ideal-wing 1 g angle of attack, but the strip wing only
  delivered ~92% of the weight there, so every hands-off aircraft sagged into a dive, and a
  1 g trim is neutrally stable (any climb or sink carried on). Measured with a new headless
  harness (tools/fm_sim.gd): a Lancaster released level at 300 m hit the sea in 25 s.
- The trim now learns the wing's real AoA offset, and with the stick released the player's
  aircraft is speed-stable: it holds its trim speed and the throttle sets the climb rate, so
  one throttle setting holds a fixed height. With the assist on it is an altitude hold.
- Throttle tap = 1% step. HUD: VSI to 0.1 m/s, LEVEL / ALT HOLD cues, THR %.

Dam Busters:
- Day 1 rings faced north-south while the course runs east (edge-on), were thin, translucent
  and fogged out. Now thick fog-free signal-orange rings facing along the course on the 60 ft
  band, pulsing halo, tall light posts, buoy, green flash when passed, TOO HIGH warning.
- Spotlight altimeter: two lamp spots on the water meet at 60 ft and turn green.
- Range marker and training rings made fog-free and thicker.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NzrQetBF6JFr4GXrmTXfbZ
MSG
echo "  commit: $(git log --oneline -1)"
GIT_TERMINAL_PROMPT=0 timeout 600 git push origin main 2>&1 | tail -3

echo "=== 8. gh release ==="
gh release create v6.6 "build/WW2ChannelAirWar_v6.6_win64.zip" \
  --title "v6.6 - hands-off level flight, visible Dam Busters rings" \
  --notes "**Level flight, every aircraft.** Let go of the stick and the aircraft now holds its speed instead of drifting into a climb or dive; the throttle sets the climb rate, so you can find the setting where the climb gauge reads LEVEL and it stays at that height. Throttle taps move 1%. Press R (LB) for altitude hold. HUD shows vertical speed to 0.1 m/s, LEVEL / ALT HOLD and throttle %.

**Dam Busters.** The day 1 rings were edge-on, thin and lost in the haze; they are now bold orange rings facing your run at 60 ft with tall light posts you can see from kilometres out, and they flash green when you pass. A spotlight altimeter puts two lamp spots on the water that meet (and turn green) at exactly 60 ft. The day 3 range marker and the training rings are easier to see too.

Gate: tests green, exported binary smoke-tested before publishing." 2>&1 | tail -3
echo "=== RELEASE SEQUENCE COMPLETE ==="

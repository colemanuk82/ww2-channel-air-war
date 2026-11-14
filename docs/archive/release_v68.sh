#!/bin/bash
# v6.8 release: dynamic free flight - Ops Room taskings every 10 minutes.
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
s2 = re.sub(r'config/version="[^"]*"', 'config/version="6.8"', s, count=1)
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
name = "WW2ChannelAirWar_v6.8_win64.zip"
if os.path.exists(name): os.remove(name)
files = ["WW2ChannelAirWar.exe"] + sorted(os.path.basename(d) for d in glob.glob("*.dll"))
with zipfile.ZipFile(name, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        if os.path.exists(f): z.write(f, f)
print("  packed:", len(files), "files ->", name, os.path.getsize(name)//1024, "KB")
PY

if [ "$FAIL" != "0" ]; then echo "=== ABORTED: the exported binary reported errors; nothing committed, pushed or released ==="; exit 1; fi

echo "=== 7. commit + push ==="
git add project.godot HANDOFF.md scripts/hud.gd scripts/menu.gd scripts/modes/free_flight_mode.gd scripts/modes/ops_room.gd scripts/modes/ops_room.gd.uid scripts/modes/dinghy.gd scripts/modes/dinghy.gd.uid tools/ops_test.sh tools/vis_shots.sh tools/release_v68.sh
git commit -q -F - <<'MSG'
Dynamic free flight: Ops Room taskings every 10 minutes (v6.8)

- Free Flight option "Ops Room taskings" (on by default). Every 10 minutes Sector
  Control (RAF) or Jafu 2 (Luftwaffe) radios a new job against a real place, with a
  waypoint on the compass and the minimap and an OPS ROOM panel showing progress.
- 11 kinds, weighted by aircraft role: strike on a real factory/rail yard/port/radar/
  bridge/battery/V-1 site, airfield attack, road convoy, train, shipping strike, E-boats,
  bomber-raid intercept, convoy cover against dive bombers, fighter sweep, air-sea rescue
  (dinghy with dye and smoke flare, circle low) and photo recce (low pass, bring it home).
- Several briefing lines per kind, side aware, places named from the nearest town.
- One job at a time; success brings the next call forward, stale jobs are replaced;
  time allowed scales with distance.
- Minimap: the objective is a pulsing diamond, or an edge arrow with the distance when it
  is off the chart (works for every mode).
- tools/ops_test.sh cycles every kind: 11/11 for typhoon (Allies), ju88 (Axis), spitfire.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NzrQetBF6JFr4GXrmTXfbZ
MSG
echo "  commit: $(git log --oneline -1)"
GIT_TERMINAL_PROMPT=0 timeout 600 git push origin main 2>&1 | tail -3

echo "=== 8. gh release ==="
gh release create v6.8 "build/WW2ChannelAirWar_v6.8_win64.zip" \
  --title "v6.8 - dynamic free flight: Ops Room taskings" \
  --notes "**Free Flight now has an Ops Room.** Tick *Ops Room taskings* on the Start Point page (it is on by default) and every 10 minutes Sector Control - or Jafü 2 if you fly for the Luftwaffe - calls you with a new job against a real place on the map: \"Red 1, Ops here. A troop convoy has been seen on the road near Saint-Omer. Steer 135, 42 km.\" A waypoint appears on the compass and on the minimap (an arrow on the edge with the distance when it is off the chart), and a panel shows the job, the distance, your progress and the time left.

**Eleven kinds of tasking**, picked to suit your aircraft: bomb a real factory, rail yard, port, radar station, bridge, gun battery or V-1 site; shoot up an enemy airfield; stop a road convoy or a train; strike a merchant convoy at sea; catch E-boats leaving harbour; intercept a bomber raid heading for one of our towns before it bombs; protect our convoy from dive bombers; sweep enemy fighters out of the sky; find a downed pilot in his dinghy and circle low until the rescue launch has a fix; and photograph an enemy site, then get the film home.

One job at a time. Finish it and the next call comes sooner; leave it too long and Ops will give you something else.

Gate: tests green, every tasking kind soak-tested on both sides, exported binary smoke-tested before publishing." 2>&1 | tail -3
echo "=== RELEASE SEQUENCE COMPLETE ==="

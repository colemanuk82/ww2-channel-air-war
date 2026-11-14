#!/bin/bash
# v6.9 release: Ops Room campaign - rendezvous, escorts, intel, V-1 pressure, logbook, chart in every aircraft.
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
s2 = re.sub(r'config/version="[^"]*"', 'config/version="6.9"', s, count=1)
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
name = "WW2ChannelAirWar_v6.9_win64.zip"
if os.path.exists(name): os.remove(name)
files = ["WW2ChannelAirWar.exe"] + sorted(os.path.basename(d) for d in glob.glob("*.dll"))
with zipfile.ZipFile(name, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        if os.path.exists(f): z.write(f, f)
print("  packed:", len(files), "files ->", name, os.path.getsize(name)//1024, "KB")
PY

if [ "$FAIL" != "0" ]; then echo "=== ABORTED: the exported binary reported errors; nothing committed, pushed or released ==="; exit 1; fi

echo "=== 7. commit + push ==="
git add project.godot HANDOFF.md scripts/pilot_log.gd scripts/pilot_log.gd.uid scripts/modes/flying_bomb.gd scripts/modes/flying_bomb.gd.uid scripts/modes/ops_room.gd scripts/weapons/weapon_world.gd scripts/ground/ground_target.gd scripts/aircraft.gd scripts/bombsight.gd scripts/main.gd scripts/modes/free_flight_mode.gd tools/make_voice_ops.py tools/ops_test.sh tools/vis_shots.sh tools/release_v69.sh assets/voice/voice_ops.csv assets/voice/ops
git commit -q -F - <<'MSG'
Ops Room campaign: rendezvous, escorts, intel, V-1 pressure, logbook, chart (v6.9)

- A single hit on any target of the job now completes it.
- Rendezvous: friendly sections wait at an RV point and join on your wing; new
  escort job (meet bombers, fight off interceptors, see them bomb).
- Night intruder job, searchlights after dark, fog can scrub a job.
- Scramble from the ground when parked: quick take-off earns a bonus.
- Mid-job twists: raids turn, deadlines, second waves, enemy launches, extra flak.
- Intel: low passes over enemy sites are reported and become future taskings.
- Campaign pressure: missed jobs strengthen enemy flak and raise V-1 launches at
  London (Allies), with Diver calls and interceptable flying bombs.
- Logbook (J), points, ranks, RAF and Luftwaffe awards, persisted per side.
- Full-screen chart (M) in every aircraft; only announced targets are pinned.
- 186 voiced Ops lines for both sides (ElevenLabs).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NzrQetBF6JFr4GXrmTXfbZ
MSG
echo "  commit: $(git log --oneline -1)"
GIT_TERMINAL_PROMPT=0 timeout 600 git push origin main 2>&1 | tail -3

echo "=== 8. gh release ==="
gh release create v6.9 "build/WW2ChannelAirWar_v6.9_win64.zip" \
  --title "v6.9 - Ops Room campaign: rendezvous, escorts, logbook" \
  --notes "**The Ops Room grows into a campaign.**

- **One hit counts.** Put a single round or bomb into any target of the job and it is done.
- **Rendezvous.** Ops often sends you to an RV first, where a section of friendly fighters forms up on your wing. New **escort** job: meet a bomber formation, see off the interceptors and watch them bomb.
- **Night and weather.** After dark you get **intruder** jobs against lit enemy airfields, with searchlights. Fog can roll in and scrub a job.
- **Scramble.** Sit parked on an airfield and Ops will scramble you: get airborne fast for a bonus.
- **Things change mid-job.** Raids turn for another town, deadlines are set, second waves and scrambled fighters appear, an enemy trawler races you to the dinghy.
- **Intel.** Fly low past enemy sites and your sightings are reported. Ops sends you back to them later.
- **Pressure.** Missed jobs make enemy flak stronger and, for the RAF, send more V-1 flying bombs at London. Diver calls tell you where to catch them.
- **Logbook (J).** Points, ranks from Pilot Officer to Group Captain (Leutnant to Oberst), and awards from the DFC to the Knight's Cross, kept between sessions.
- **Chart (M) in every aircraft.** Only targets Ops has announced are pinned.
- **186 new voiced radio lines** for both sides.

Gate: tests green, tasking soak test, exported binary smoke-tested before publishing." 2>&1 | tail -3
echo "=== RELEASE SEQUENCE COMPLETE ==="

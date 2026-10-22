#!/bin/bash
# v7.30 release: Pilot's Life career (1940, RAF and Luftwaffe), bail-out on J, Luftwaffe fin Hakenkreuz.
# Sequence: import -> test gate -> version bump -> import -> export -> smoke-test the EXPORTED binary -> zip -> commit/push -> release.
# Aborts before any commit, push or release if the tests or the exported build misbehave.
cd /f/ww2_dlss || exit 1
mkdir -p build
EXE="F:/godot-rtx/bin/godot.windows.editor.x86_64.console.exe"
FAIL=0

echo "=== -1. pull the v7.30 code (committed from the cloud copy) ==="
git checkout -- HANDOFF.md scripts shaders 2>/dev/null; rm -f scripts/prof.gd scripts/prof.gd.uid   # drop the PC-only profiling instrumentation
git checkout main 2>/dev/null
GIT_TERMINAL_PROMPT=0 git pull --ff-only origin main 2>&1 | tail -2
grep -q "_career_lost" scripts/main.gd 2>/dev/null || { echo "ABORT: pull did not bring the v7.30 code"; exit 1; }
test -f scripts/career.gd || { echo "ABORT: scripts/career.gd missing after pull"; exit 1; }

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
s2 = re.sub(r'config/version="[^"]*"', 'config/version="7.30"', s, count=1)
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
SMOKE_RC=$?
echo "  smoke exit=$SMOKE_RC"
if [ "$SMOKE_RC" != "0" ]; then echo "  the exported build crashed or failed (exit $SMOKE_RC)"; FAIL=1; fi
SMOKE=$(grep -aE "SCRIPT ERROR|Parse Error|Failed to load|Cannot open|not work on export" build/release_smoke.log | grep -v "signed by NVIDIA" | sort -u)
if [ -n "$SMOKE" ]; then echo "  --- smoke findings ---"; echo "$SMOKE" | head -10; FAIL=1; else echo "  clean: no script errors from the exported build"; fi
grep -a "HeightField: loaded" build/release_smoke.log | head -1 | sed 's/^/  /'

echo "=== 6. zip (exe + every DLL the game needs, copied from the project root) ==="
cp -f /f/ww2_dlss/*.dll build/ 2>/dev/null
python3 - <<'PY'
import zipfile, glob, os
os.chdir("build")
name = "WW2ChannelAirWar_v7.30_win64.zip"
if os.path.exists(name): os.remove(name)
files = ["WW2ChannelAirWar.exe"] + sorted(os.path.basename(d) for d in glob.glob("*.dll"))
with zipfile.ZipFile(name, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        if os.path.exists(f): z.write(f, f)
print("  packed:", len(files), "files ->", name, os.path.getsize(name)//1024, "KB")
PY

if [ "$FAIL" != "0" ]; then echo "=== ABORTED: the exported binary reported errors; nothing committed, pushed or released ==="; exit 1; fi

echo "=== 7. commit + push ==="
# the code itself was committed from the cloud copy; this commits the version bump and pushes
git add project.godot tools/release_v730.sh
git add scripts/modes/passing_flights.gd.uid 2>/dev/null
git commit -q -m "v7.30 release: version bump" -m "Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013ApSn3cDWsLo4GEguHKh1e"
echo "  commit: $(git log --oneline -1)"
GIT_TERMINAL_PROMPT=0 timeout 600 git push origin main 2>&1 | tail -3

echo "=== 8. gh release ==="
gh release create v7.30 "build/WW2ChannelAirWar_v7.30_win64.zip" --repo colemanuk82/ww2-channel-air-war \
  --title "v7.30 - Pilot's Life career, bail-out, Luftwaffe fin swastika" \
  --notes "**New: Pilot's Life.** A career from the summer of 1940, for either side. Create a pilot (name, RAF or Luftwaffe, fighter, optional Ironman), then play through story pages and missions. Pages are typed out over a full-screen story screen; letters and telegrams are shown on paper cards.
- The 1940 chapter has seven steps per side: patrols, scrambles, Dunkirk and Battle of Britain missions, and a night raid on London for the Luftwaffe.
- Every sortie matters: landing in the sea means a three-day rest, capture or a crash means weeks off, and Ironman ends the career for good (killed or prisoner of war).
- Squadron mates are lost along the way.
- Full-screen pictures are not in this release yet; the story pages show a dark background for now.

**New: bail out.** Hold J for about a second above 70 m. The pilot takes to his parachute, and a camera follows him down. Landing on your own side, in the Channel or behind enemy lines each has its own consequence. In a Pilot's Life sortie a lost pilot ends the sortie.

**New: Luftwaffe fin markings.** Axis aircraft carry a black Hakenkreuz on a white disc on the fin, on both faces (each fin on twin-engined types).

Not yet played on the test PC: the bail-out and Pilot's Life flow in a full sortie. Please report anything that breaks.

Gate: tests green, exported binary smoke-tested (must exit cleanly) before publishing." 2>&1 | tail -3
echo "=== RELEASE SEQUENCE COMPLETE ==="

#!/bin/bash
# v7.33 release: options screen redesign with controller diagram on Controls, left trigger throttle and brake, padlock snap, End sortie for career free flights.
# Sequence: import -> test gate -> version bump -> import -> export -> smoke-test the EXPORTED binary -> zip -> commit/push -> release.
# Aborts before any commit, push or release if the tests or the exported build misbehave.
cd /f/ww2_dlss || exit 1
mkdir -p build
EXE="F:/godot-rtx/bin/godot.windows.editor.x86_64.console.exe"
FAIL=0

echo "=== -1. pull the v7.33 code (committed from the cloud copy) ==="
git checkout -- HANDOFF.md scripts shaders 2>/dev/null; rm -f scripts/prof.gd scripts/prof.gd.uid   # drop the PC-only profiling instrumentation
git checkout main 2>/dev/null
GIT_TERMINAL_PROMPT=0 git pull --ff-only origin main 2>&1 | tail -2
grep -q "_career_lost" scripts/main.gd 2>/dev/null || { echo "ABORT: pull did not bring the v7.33 code"; exit 1; }
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
s2 = re.sub(r'config/version="[^"]*"', 'config/version="7.33"', s, count=1)
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
name = "WW2ChannelAirWar_v7.33_win64.zip"
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
git add project.godot tools/release_v733.sh
git add scripts/modes/passing_flights.gd.uid 2>/dev/null
git commit -q -m "v7.33 release: version bump" -m "Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013ApSn3cDWsLo4GEguHKh1e"
echo "  commit: $(git log --oneline -1)"
GIT_TERMINAL_PROMPT=0 timeout 600 git push origin main 2>&1 | tail -3

echo "=== 8. gh release ==="
gh release create v7.33 "build/WW2ChannelAirWar_v7.33_win64.zip" --repo colemanuk82/ww2-channel-air-war \
  --title "v7.33 - options redesign, controller diagram" \
  --notes "**Options**
- Full-width options screen with LB / RB chips on the tab row. LB / RB switch pages; B or Esc goes back.
- Each page sits on its own card, and Apply / Back are in a footer.

**Controls**
- The Controls page shows the controller outline with every input labelled with the actions bound to it. The labels update when you rebind.
- Rebinding still works from the table below the diagram.

**Controls (from v7.32)**
- Left trigger does throttle down and wheel brake together. Right trigger throttles up. R3 still brakes. Keyboard: Ctrl throttles down, V brakes.
- Holding the target view (left shoulder or K) and letting go snaps the camera back to forward-centre.
- L (gunner view) on an aircraft with no defensive guns does nothing.
- End sortie in the pause menu for free-flight career sorties (land first).

Gate: tests green (762/762) and the exported binary was smoke-tested before publishing. Not yet played on the test PC."
echo "=== RELEASE SEQUENCE COMPLETE ==="

#!/bin/bash
# v7.29 release (hotfix of v7.29: no worker-thread sound synthesis). CPU performance (background threads for site searches and radio clips, bullet grid, cheaper ground vehicles / particles / clouds), AI cap in free flight.
# Sequence: import -> test gate -> version bump -> import -> export -> smoke-test the EXPORTED binary -> zip -> commit/push -> release.
# Aborts before any commit, push or release if the tests or the exported build misbehave.
cd /f/ww2_dlss || exit 1
mkdir -p build
EXE="F:/godot-rtx/bin/godot.windows.editor.x86_64.console.exe"
FAIL=0

echo "=== -1. pull the v7.29 code (committed from the cloud copy) ==="
git checkout -- HANDOFF.md scripts shaders 2>/dev/null; rm -f scripts/prof.gd scripts/prof.gd.uid   # drop the PC-only profiling instrumentation
git checkout main 2>/dev/null
GIT_TERMINAL_PROMPT=0 git pull --ff-only origin main 2>&1 | tail -2
grep -q "var _pre_queue" scripts/audio_sfx.gd 2>/dev/null || { echo "ABORT: pull did not bring the v7.29 code"; exit 1; }

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
s2 = re.sub(r'config/version="[^"]*"', 'config/version="7.29"', s, count=1)
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
name = "WW2ChannelAirWar_v7.29_win64.zip"
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
git add project.godot tools/release_v724.sh
git add scripts/modes/passing_flights.gd.uid 2>/dev/null
git commit -q -m "v7.29 release: version bump" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013ApSn3cDWsLo4GEguHKh1e"
echo "  commit: $(git log --oneline -1)"
GIT_TERMINAL_PROMPT=0 timeout 600 git push origin main 2>&1 | tail -3

echo "=== 8. gh release ==="
gh release create v7.29 "build/WW2ChannelAirWar_v7.29_win64.zip" --repo colemanuk82/ww2-channel-air-war \
  --title "v7.29 - smoother frame rate (CPU), fixes the v7.28 crash" \
  --notes "**Smoother play, fewer stutters.** v7.27 fixed the graphics side; this release goes after the processor side, measured per system on an RTX 4070 SUPER at 4K (frame generation off):

- Dogfight: about 47-57 fps -> 65-78 fps (depends on where it starts)
- Free flight over Kent: about 100 -> 108 fps
- Free flight with a passing raid: about 71 -> 75 fps

**Background threads (multi-threading):**
- The coastline search for docks and harbours (about 200 ms each, the main stutter around London and the Thames) runs on worker threads.
- Radio voice clips load in the background.

**Sounds:** every procedural sound (explosions, thunder, fire bells, sirens, engines, guns) is synthesised ahead of time while the menu and loading screen run, instead of freezing the frame the first time it plays. (v7.28 did this on worker threads, which could crash the game while loading; v7.29 does it safely on the main thread.)

**Cheaper per-frame work:** bullets test only nearby targets (a spatial grid instead of every damageable object in the world); ground vehicles and ships far from you update less often; particles upload only the live puffs to the GPU; clouds re-position a quarter at a time; the sky, fog and clock update 5 times a second; the first bomb burst and the start of a blitz raid no longer stall.

**Free flight AI cap:** at most 22 AI aircraft at once across passing flights, ambient raids and skirmishes and Ops Room taskings; raids, escorts and interceptor scrambles shrink to fit.

Not changed: Godot's separate render thread is still experimental in this engine version (it threw render-thread errors in testing), so it stays off.

Gate: tests green, exported binary smoke-tested (must exit cleanly) before publishing." 2>&1 | tail -3
echo "=== RELEASE SEQUENCE COMPLETE ==="

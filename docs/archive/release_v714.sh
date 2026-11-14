#!/bin/bash
# v7.14 release: raid blackout with warden whistles, fire bells and emergency vehicles; crew wounds on the intercom;
# moon and weather in the planner; balloon cable hits and bomber stream contrails; searchlight catch and ditching
# rescue; dated operations, logbook extracts, bomb damage maps, posters and newsreel card.
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
s2 = re.sub(r'config/version="[^"]*"', 'config/version="7.14"', s, count=1)
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
name = "WW2ChannelAirWar_v7.14_win64.zip"
if os.path.exists(name): os.remove(name)
files = ["WW2ChannelAirWar.exe"] + sorted(os.path.basename(d) for d in glob.glob("*.dll"))
with zipfile.ZipFile(name, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        if os.path.exists(f): z.write(f, f)
print("  packed:", len(files), "files ->", name, os.path.getsize(name)//1024, "KB")
PY

if [ "$FAIL" != "0" ]; then echo "=== ABORTED: the exported binary reported errors; nothing committed, pushed or released ==="; exit 1; fi

echo "=== 7. commit + push ==="
git add project.godot tools/release_v714.sh
git commit -q -F - <<'MSG'
Raid blackout, crew wounds, moon and weather, balloon cables, searchlight catch, ditching rescue, history (v7.14)

- Raids: the raided town's windows go dark with warden whistles; fire bells; fire engines and an ambulance on real roads.
- Crew: navigator, wireless operator and gunners can be wounded or killed; state on a CREW panel and the intercom.
- Planner: moon phase and forecast weather for the route; bright moon helps searchlights and night fighters.
- Balloons: flying through a cable costs damage; bombers leave contrails along the raid heading.
- Searchlights: a player held in a beam draws flak and must break out; ditching creates a dinghy rescue.
- History: dated operations, logbook extracts, bomb damage maps on the results screen, menu posters and a newsreel card.

Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NzrQetBF6JFr4GXrmTXfbZ
MSG
echo "  commit: $(git log --oneline -1)"
GIT_TERMINAL_PROMPT=0 timeout 600 git push origin main 2>&1 | tail -3

echo "=== 8. gh release ==="
gh release create v7.14 "build/WW2ChannelAirWar_v7.14_win64.zip" \
  --title "v7.14 - blackout, crew wounds, moon and weather, cables, catch and rescue, history" \
  --notes "**Raids.** The raided town goes dark with warden whistles, fire bells and emergency vehicles on the roads.

**Crew.** Gunners, navigator and wireless operator can be wounded or killed, shown on the intercom.

**Planner.** Moon phase and route weather before takeoff.

**Balloons and contrails.** Cables hurt when flown into; bomber streams leave contrails along the raid heading.

**Searchlights and ditching.** A player held in a beam draws flak and must break out. Ditching leads to a dinghy rescue.

**History.** Dated operations, logbook extracts, bomb damage maps, menu posters and a newsreel card.

Gate: tests green, exported binary smoke-tested before publishing." 2>&1 | tail -3
echo "=== RELEASE SEQUENCE COMPLETE ==="

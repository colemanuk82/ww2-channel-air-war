#!/bin/bash
# v7.19 release: the rest of the ElevenLabs credits spent on radio voice takes (spotting with height, more chatter, Ops briefings).
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
s2 = re.sub(r'config/version="[^"]*"', 'config/version="7.19"', s, count=1)
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
name = "WW2ChannelAirWar_v7.19_win64.zip"
if os.path.exists(name): os.remove(name)
files = ["WW2ChannelAirWar.exe"] + sorted(os.path.basename(d) for d in glob.glob("*.dll"))
with zipfile.ZipFile(name, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        if os.path.exists(f): z.write(f, f)
print("  packed:", len(files), "files ->", name, os.path.getsize(name)//1024, "KB")
PY

if [ "$FAIL" != "0" ]; then echo "=== ABORTED: the exported binary reported errors; nothing committed, pushed or released ==="; exit 1; fi

echo "=== 7. commit + push ==="
git add project.godot tools/release_v719.sh scripts/menu.gd scripts/logbook_menu.gd scripts/pilot_log.gd scripts/mode_base.gd \
  scripts/main.gd scripts/modes/ops_room.gd
git commit -q -F - <<'MSG'
Logbook records every mode, ships count as kills, logbook opens from the menu (v7.19)

- Kills (aircraft, ground targets, ships, V-1s), hours flown and mission results are recorded by ModeBase in
  every mode; before, only free flight with Ops Room taskings wrote to the logbook. The Ops Room no longer
  records kills or hours itself, so nothing is counted twice.
- Ships sunk are their own logbook total and count in the kill count on the score sheet and results screen.
- Medals and promotions can come from missions as well as taskings; new Coastal Command / Anti-Shipping and
  ground-attack decorations. Promotions and awards are announced in every mode.
- The main-menu Logbook opened behind the menu (same screen layer); it now has its own layer above it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013ApSn3cDWsLo4GEguHKh1e
MSG
echo "  commit: $(git log --oneline -1)"
GIT_TERMINAL_PROMPT=0 timeout 600 git push origin main 2>&1 | tail -3

echo "=== 8. gh release ==="
gh release create v7.19 "build/WW2ChannelAirWar_v7.19_win64.zip" --repo colemanuk82/ww2-channel-air-war \
  --title "v7.19 - logbook records every mode, ships count as kills" \
  --notes "**Logbook.** Every mode now records your kills, ships sunk, hours flown and mission results, so rank and medals come from dogfights, bombing, ground attack, escort and campaign missions too, not just free-flight taskings. New anti-shipping and ground-attack decorations.

**Ships** count as kills on the score sheet and results screen.

**Menu.** The Logbook button works again (it was opening behind the menu).

Gate: tests green, exported binary smoke-tested before publishing." 2>&1 | tail -3
echo "=== RELEASE SEQUENCE COMPLETE ==="

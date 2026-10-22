#!/bin/bash
# v6.1 release: cockpit interior + corrected pilot eye positions + blueprint tooling.
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
s2 = re.sub(r'config/version="[^"]*"', 'config/version="6.1"', s, count=1)
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
name = "WW2ChannelAirWar_v6.1_win64.zip"
if os.path.exists(name): os.remove(name)
files = ["WW2ChannelAirWar.exe"] + sorted(os.path.basename(d) for d in glob.glob("*.dll"))
with zipfile.ZipFile(name, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        if os.path.exists(f): z.write(f, f)
print("  packed:", len(files), "files ->", name, os.path.getsize(name)//1024, "KB")
PY

if [ "$FAIL" != "0" ]; then echo "=== ABORTED: the exported binary reported errors; nothing committed, pushed or released ==="; exit 1; fi

echo "=== 7. commit + push ==="
git add -A project.godot scripts/ tools/models/ assets/models/ data/ 2>/dev/null
git commit -q -m "feat(cockpit): build the cockpit interior, and put every pilot's eye above the deck

Cockpit interior:
- scripts/cockpit_interior.gd was written but never instantiated: no caller existed, so the game's
  cockpit had no floor, walls, bulkheads, panel or framing, and the file was not even tracked.
- Aircraft now builds it under the CockpitMount for the player and toggles it with the cockpit view.
  Built lazily and player-only: each interior owns a SubViewport for the live gauge panel, so AI
  aircraft are never charged for one.

Pilot eye position (all 25 types):
- The cockpit camera hangs off the CockpitEye marker. On 12 aircraft the eye sat at or below the
  fuselage top deck, so the pilot looked at structure instead of out over the nose. Hurricane was
  0.66 vs a 0.70 deck; C-47 1.02 vs 1.29; He 111 0.86 vs 1.10, and so on.
- Each eye is now above its own deck and inside the canopy glazing. Three stale CockpitMount
  literals (He 111, Ju 88, Me 262) were brought into line with their eyes.
- `build_all.py --eye` now measures the eye against the model's own fuselage mesh, so this class of
  error is caught mechanically instead of by eye. All 25 pass; the cockpit view was then checked in
  game for representative types.

Blueprint tooling:
- tools/models/reference/ holds drawings for 23 of the 25 types (43 sheets from a public
  drawing site; removed in the 2026-10-22 copyright cleanup).
- tools/models/overlay.py compares a drawing's view against a rendered silhouette and reports the
  intersection-over-union plus both aspect ratios.
- The ortho renderer produced no usable sheets: EEVEE with no lights and no world gave 128 blank
  PNGs, with all four views of each aircraft byte-identical. It now renders flat black-on-white
  with the workbench engine, which is what a silhouette comparison needs.

Gate: scenes/tests.tscn green, and the exported binary smoke-tested in cockpit view before release." -- project.godot scripts/ tools/models/ tools/shots/models/ assets/models/ data/ 2>&1 | tail -2
echo "  commit: $(git log --oneline -1)"
GIT_TERMINAL_PROMPT=0 timeout 600 git push origin main 2>&1 | tail -3

echo "=== 8. gh release ==="
gh release create v6.1 "build/WW2ChannelAirWar_v6.1_win64.zip" \
  --title "v6.1 - cockpit interior, corrected pilot eye positions" \
  --notes "The aircraft now have a cockpit to sit in, and every pilot's eye is in the right place.

**Cockpit interior.** A procedural period interior - floor pan, belly fairing, side walls, canopy sills, front and rear bulkheads, glare shield, instrument panel with live gauges, reflector gunsight, windscreen and canopy framing, seat and controls. It was written but never instantiated, so the cockpit had none of it; it is now built for the player's aircraft and shown with the cockpit view. AI aircraft never pay for it.

**Eye positions, all 25 types.** The cockpit camera hangs off the CockpitEye marker, and on 12 aircraft that marker sat at or below the fuselage top deck - the pilot looked at structure instead of out over the nose (Hurricane 0.66 m against a 0.70 m deck; C-47 1.02 against 1.29; He 111 0.86 against 1.10). Each eye is now above its own deck and inside the canopy glazing. The build tool measures this against the model's own mesh, so it is checked mechanically, and the cockpit view was then verified in game.

**Blueprint reference library.** Drawings for 23 of the 25 types (43 sheets) are now in tools/models/reference/ with a comparison tool that reports silhouette intersection-over-union against a drawing - the start of measuring the models against real three-views rather than trusting them. The ortho sheets used for that comparison had been rendering blank (no lights, no world); they now render properly.

Gate: tests green, exported binary smoke-tested in cockpit view before publishing." 2>&1 | tail -3
echo "=== RELEASE SEQUENCE COMPLETE ==="

#!/bin/bash
# v7.18 release: the rest of the ElevenLabs credits spent on radio voice takes (spotting with height, more chatter, Ops briefings).
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
s2 = re.sub(r'config/version="[^"]*"', 'config/version="7.18"', s, count=1)
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
name = "WW2ChannelAirWar_v7.18_win64.zip"
if os.path.exists(name): os.remove(name)
files = ["WW2ChannelAirWar.exe"] + sorted(os.path.basename(d) for d in glob.glob("*.dll"))
with zipfile.ZipFile(name, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        if os.path.exists(f): z.write(f, f)
print("  packed:", len(files), "files ->", name, os.path.getsize(name)//1024, "KB")
PY

if [ "$FAIL" != "0" ]; then echo "=== ABORTED: the exported binary reported errors; nothing committed, pushed or released ==="; exit 1; fi

echo "=== 7. commit + push ==="
git add project.godot tools/release_v718.sh tools/make_voice_more.py tools/make_voice_more_data.py \
  tools/make_voice_bulk.py tools/make_voice_bulk_data.py tools/make_voice_final.py tools/make_voice_final_data.py tools/wire_voice_bulk.py \
  scripts/radio.gd scripts/modes/ops_room.gd HANDOFF.md \
  assets/voice/voice_more.csv assets/voice/voice_bulk.csv assets/voice/voice_final.csv \
  assets/voice/voice_more.csv.import assets/voice/voice_bulk.csv.import assets/voice/voice_final.csv.import assets/voice/voice_last.csv assets/voice/voice_last.csv.import \
  assets/voice/allies assets/voice/axis assets/voice/ops
git commit -q -F - <<'MSG'
Spend the remaining voice credits on radio takes (v7.18)

- Spotting calls: three more takes per clock position, plus high and low calls ("three o'clock high")
  chosen from the bandit's height relative to you (300 m either way); the on-screen text says high/low too.
- Wingman kills, hits and replies: up to 15 takes each.
- Ops Room: up to 11 briefings per job type, more openers, follow-ups, success, fail and hit calls.
- Background chatter: 161 lines on the RAF side, 158 on the Luftwaffe side (was 11 and 9 at v7.16).
- Every pick uses only takes whose recordings exist and never repeats the last one.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013ApSn3cDWsLo4GEguHKh1e
MSG
echo "  commit: $(git log --oneline -1)"
GIT_TERMINAL_PROMPT=0 timeout 600 git push origin main 2>&1 | tail -3

echo "=== 8. gh release ==="
gh release create v7.18 "build/WW2ChannelAirWar_v7.18_win64.zip" \
  --title "v7.18 - hundreds more radio voices" \
  --notes "**Voices.** The rest of the voice credits went on 970 new radio recordings: wingmen now call bandits and bombers *high* or *low* when they are well above or below you, every spotting call has several takes, kills/hits/replies have up to 15 takes, the Ops Room has up to 11 briefings per job, and the background chatter has grown to well over 100 lines per side. No line repeats back to back.

Gate: tests green, exported binary smoke-tested before publishing." 2>&1 | tail -3
echo "=== RELEASE SEQUENCE COMPLETE ==="

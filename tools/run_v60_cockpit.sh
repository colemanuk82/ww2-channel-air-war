#!/bin/bash
# Download the published v6.0 build from GitHub, run it, and take a cockpit-view screenshot.
# Extracts OUTSIDE the repo (F:/ww2_v60) so nothing lands in the working tree.
set -u
DEST="/f/ww2_v60"          # for bash's own file operations
GHDEST="F:/ww2_v60"        # for native programs (gh, the game exe): they cannot read /f/... paths
REPO="colemanuk82/ww2-channel-air-war"

rm -rf "$DEST"; mkdir -p "$DEST"
echo "=== 1. download the v6.0 asset (376 MB) ==="
gh release download v6.0 --repo "$REPO" --dir "$GHDEST" --pattern "*.zip" --clobber 2>&1 | tail -3
ls -la "$DEST"/*.zip 2>/dev/null | awk '{print "  ", $5, $9}'

echo "=== 2. extract ==="
python3 - <<'PY'
import glob, zipfile
z = sorted(glob.glob("F:/ww2_v60/*.zip"))
if not z:
    raise SystemExit("no zip")
with zipfile.ZipFile(z[0]) as f:
    for n in f.namelist():
        print("   ", n, f.getinfo(n).file_size // 1024, "KB")
    f.extractall("F:/ww2_v60/build")
print("extracted to F:/ww2_v60/build")
PY

echo "=== 3. run the v6.0 binary and take a cockpit shot ==="
EXE=$(ls "$DEST"/build/*.exe 2>/dev/null | head -1)
echo "  binary: $EXE"
cd "$DEST/build" || exit 1
timeout 400 "F:/ww2_v60/build/WW2ChannelAirWar.exe" --no-window --quit-after 400 -- \
  --skip-menu --air --cockpit --autopilot --aircraft=hurricane \
  --plan=51.3308,0.0325,-,1,900,90 --weather=clear --time=noon \
  --shot="F:/ww2_v60/cockpit_v60.png" --frames=150 > "$DEST/run.log" 2>&1
echo "  exit=$?"
grep -acE "SCRIPT ERROR|Parse Error" "$DEST/run.log" | sed 's/^/  script errors: /'
grep -a "\[shot\]" "$DEST/run.log" | head -2
ls -la "$DEST/cockpit_v60.png" 2>/dev/null | awk '{print "  shot:", $5, "bytes"}'
FF="/c/Users/colem/AppData/Local/hermes/tools/ffmpeg-9.0.1-win32-x64/bin/ffmpeg"
[ -f "$DEST/cockpit_v60.png" ] && "$FF" -y -i "$DEST/cockpit_v60.png" -vf scale=1600:-1 -q:v 3 "/f/ww2_dlss/build/share/cockpit_v60.jpg" >/dev/null 2>&1 && ls -la /f/ww2_dlss/build/share/cockpit_v60.jpg | awk '{print "  chat copy:", $5, "bytes"}'
echo "=== done ==="

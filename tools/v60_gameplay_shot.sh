#!/bin/bash
# Capture the REAL gameplay camera view from the published v6.0 binary.
#
# Not via --shot: that goes through the screenshot-tour path, which sets the cockpit flag from its own
# spec dict and applies its own orbit, so it can differ from what the player actually sees. Movie Maker
# instead records the frames the running game renders.
#
# The recording opens with a fixed loading lead (about 184 frames at 30 fps), so the shot must be taken
# well past it - hence 300 frames requested and a late frame extracted.
EXE="F:/ww2_v60/build/WW2ChannelAirWar.exe"
OUT="F:/ww2_v60"

echo "=== recording 300 frames of the v6.0 gameplay camera, cockpit view ==="
timeout 500 "$EXE" --no-window --resolution 1280x720 \
  --write-movie "$OUT/v60_gameplay.avi" --fixed-fps 30 -- \
  --skip-menu --air --cockpit --autopilot --aircraft=hurricane \
  --plan=51.3308,0.0325,-,1,900,90 --weather=clear --time=noon \
  --frames=300 > "$OUT/gameplay.log" 2>&1
echo "  exit=$? (124 = hit the timeout; frames are still written)"
grep -acE "SCRIPT ERROR|Parse Error" "$OUT/gameplay.log" | sed 's/^/  script errors: /'
ls -la "$OUT/v60_gameplay.avi" 2>/dev/null | awk '{print "  avi:", $5, "bytes"}'

echo "=== extract a frame from well past the loading lead ==="
FF="/c/Users/colem/AppData/Local/hermes/tools/ffmpeg-9.0.1-win32-x64/bin/ffmpeg"
"$FF" -y -ss 9 -i "$OUT/v60_gameplay.avi" -frames:v 1 "F:/ww2_v60/v60_gameplay_frame.png" 2>&1 | tail -1
"$FF" -y -i "F:/ww2_v60/v60_gameplay_frame.png" -vf scale=1600:-1 -q:v 3 \
  "F:/ww2_dlss/build/share/v60_gameplay.jpg" >/dev/null 2>&1
ls -la "F:/ww2_dlss/build/share/v60_gameplay.jpg" 2>/dev/null | awk '{print "  chat copy:", $5, "bytes"}'
echo "=== done ==="

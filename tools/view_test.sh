#!/bin/bash
# Record the CURRENT build the same way (Movie Maker, --cockpit) and pull a gameplay frame, so we can
# see which camera the flag actually selects on this path.
EXE="F:/godot-rtx/bin/godot.windows.editor.x86_64.console.exe"
P="F:/ww2_dlss"
FF="/c/Users/colem/AppData/Local/hermes/tools/ffmpeg-9.0.1-win32-x64/bin/ffmpeg"

rm -f "$P/build/viewtest.avi"
timeout 500 "$EXE" --no-window --resolution 1280x720 \
  --write-movie "$P/build/viewtest.avi" --fixed-fps 30 -- \
  --skip-menu --air --cockpit --autopilot --aircraft=hurricane \
  --plan=51.3308,0.0325,-,1,900,90 --weather=clear --time=noon \
  --frames=260 > "$P/build/viewtest.log" 2>&1
echo "record exit=$? (124 = timeout, frames still written)"
grep -acE "SCRIPT ERROR|Parse Error" "$P/build/viewtest.log" | sed 's/^/script errors: /'
grep -a "set_cockpit_view" "$P/build/viewtest.log" | head -3
ls -la "$P/build/viewtest.avi" 2>/dev/null | awk '{print "avi:", $5, "bytes"}'

# frame well past the ~184-frame loading lead
"$FF" -y -ss 8 -i "F:/ww2_dlss/build/viewtest.avi" -frames:v 1 "F:/ww2_dlss/build/viewtest_frame.png" 2>&1 | tail -1
"$FF" -y -i "F:/ww2_dlss/build/viewtest_frame.png" -vf scale=1600:-1 -q:v 3 "F:/ww2_dlss/build/share/viewtest.jpg" >/dev/null 2>&1
ls -la "$P/build/share/viewtest.jpg" 2>/dev/null | awk '{print "chat copy:", $5, "bytes"}'
echo "=== done ==="

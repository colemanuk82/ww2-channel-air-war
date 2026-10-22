#!/bin/bash
# In-game cockpit view check, one aircraft at a time (a single Godot instance per run).
# The authoritative check: the real camera, the real scenery, the real interior.
EXE="F:/godot-rtx/bin/godot.windows.editor.x86_64.console.exe"
P="F:/ww2_dlss"
OUT="$P/build/cockpit_check"
mkdir -p "$OUT"

shot () {
	local id="$1"; local lat="$2"; local lon="$3"; local alt="$4"
	echo "=== $id  $(date +%H:%M:%S) ==="
	timeout 400 "$EXE" --no-window --path "$P" -- \
		--skip-menu --air --cockpit --autopilot --aircraft="$id" \
		--plan="$lat,$lon,-,1,$alt,90" \
		--shot="$OUT/$id.png" --frames=200 > "$OUT/$id.log" 2>&1
	echo "    exit=$?  $(grep -c 'SCRIPT ERROR' "$OUT/$id.log") script errors  $(grep -o 'saved .*' "$OUT/$id.log" | head -1)"
}

shot spitfire  51.3308 0.0325  900
shot bf109     50.9600 1.8600  900
shot lancaster 51.5074 -0.1278 900
shot he111     51.0500 1.4200  900
shot p51       51.9000 0.6000  900
shot ju87      50.8000 1.7000  900

echo "=== done $(date +%H:%M:%S) ==="
ls -la "$OUT"/*.png 2>/dev/null | awk '{print $5, $9}'

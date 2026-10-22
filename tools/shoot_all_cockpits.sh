#!/bin/bash
# Cockpit view for every aircraft type, for review. One Godot instance at a time.
# The six already captured (build/cockpit_check) are reused; the rest are shot now.
EXE="F:/godot-rtx/bin/godot.windows.editor.x86_64.console.exe"
P="F:/ww2_dlss"
OUT="$P/build/cockpit_new"
mkdir -p "$OUT"

# inland start points, rotated so the sheets are not all the same backdrop (all over land)
LATS=(51.3308 51.5074 51.0500 52.4800 51.9000)
LONS=(0.0325 -0.1278 1.4200 -1.9000 0.6000)

ALL="a20 b25 b26 bf109 bf110 blenheim c47 defiant do17 fw190 fw200 he111 hurricane ju52 ju87 ju88 lancaster me262 mosquito p38 p47 p51 spitfire tempest typhoon"

i=0
for id in $ALL; do
	lat=${LATS[$((i % 5))]}; lon=${LONS[$((i % 5))]}
	echo "[$id] shooting at $lat,$lon  $(date +%H:%M:%S)"
	timeout 400 "$EXE" --no-window --path "$P" -- \
		--skip-menu --air --cockpit --autopilot --aircraft="$id" \
		--plan="$lat,$lon,-,1,900,90" \
		--shot="$OUT/$id.png" --frames=200 > "$OUT/$id.log" 2>&1
	rc=$?
	if [ -f "$OUT/$id.png" ]; then
		echo "    ok  exit=$rc  $(grep -c 'SCRIPT ERROR' "$OUT/$id.log") script errors"
	else
		echo "    FAILED exit=$rc (no shot) - $(grep -aoE 'Invalid aircraft|unknown aircraft|not found' "$OUT/$id.log" | head -1)"
	fi
	i=$((i + 1))
done

echo "=== captured: $(ls "$OUT"/*.png 2>/dev/null | wc -l) of 25 ==="

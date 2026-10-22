#!/bin/bash
# Soak test for the Ops Room taskings: cycles every tasking kind (each auto-completes after 3 s) and prints the
# results. Usage: tools/ops_test.sh [aircraft] [side]
cd /f/ww2_dlss || exit 1
EXE="F:/godot-rtx/bin/godot.windows.editor.x86_64.console.exe"
AC=${1:-typhoon}
SIDE=${2:-Allies}
timeout 600 "$EXE" --headless --path "F:/ww2_dlss" -- --mode=free --air --side=$SIDE --aircraft=$AC --taskings --ops-test --ops-first=3 --quit-after=300 --ops-verbose > build/ops_test_${AC}.log 2>&1
echo "exit=$?"
grep -aE "\[ops\]|SCRIPT ERROR|Parse Error|ERROR:.*ops_room|ERROR:.*dinghy" build/ops_test_${AC}.log | grep -v "signed by" | head -60

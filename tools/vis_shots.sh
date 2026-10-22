#!/bin/bash
# Visual check shots for the world (sea, coast, night water, airfield, dam). Usage: tools/vis_shots.sh <tag>
cd /f/ww2_dlss || exit 1
EXE="F:/godot-rtx/bin/godot.windows.editor.x86_64.console.exe"
TAG=${1:-base}
mkdir -p build/vis
shot() {   # name, extra args...
	local n=$1; shift
	timeout ${TMO:-300} "$EXE" --path "F:/ww2_dlss" --resolution 1280x720 -- --shot="F:/ww2_dlss/build/vis/${TAG}_${n}.png" --frames=260 "$@" > "build/vis/${TAG}_${n}.log" 2>&1
	echo "$n exit=$? $(grep -acE 'SCRIPT ERROR|Parse Error' build/vis/${TAG}_${n}.log) script errors"
}
for s in ${SHOTS:-sea dusk night coast field}; do
	case $s in
		sea)   shot sea   --air --time=noon --weather=clear --at=50.85,1.15,90,80 --chase=40 ;;
		dusk)  shot dusk  --air --time=dusk --weather=clear --at=50.85,1.15,90,260 --chase=40 ;;
		night) shot night --air --time=night --weather=clear --at=50.85,1.15,120,155 --chase=40 ;;
		coast) shot coast --air --time=noon --weather=clear --at=51.04,1.22,160,340 --chase=40 ;;
		field) shot field --time=noon --weather=scattered --chase=30 --orbit=60,10 ;;
		dam)   shot dam   --dam-day=3 --dam-near --autodrop --frames=${DAMF:-800} ;;
		dam2)  shot dam2  --dam-day=3 --dam-near --autodrop --frames=3600 ;;
		flood) shot flood --dam-day=3 --dam-near --breach-now --chase=90 --orbit=0,30 --frames=${FLOODF:-500} ;;
		plume) shot plume --air --time=noon --weather=clear --at=50.85,1.15,160,80 --chase=40 --plume-test --frames=${PLUMEF:-330} ;;
		nightdam) shot nightdam --dam-day=4 --dam-near --chase=60 --orbit=0,12 --frames=${NDF:-300} ;;
		ops)   shot ops_${OPSK:-intercept} --air --time=noon --weather=scattered --taskings --ops-first=2 --ops-kind=${OPSK:-intercept} --frames=${OPSF:-500} ;;
		chart) shot chart_${OPSK:-strike} --air --aircraft=${AC:-spitfire} --time=noon --weather=scattered --taskings --ops-first=2 --ops-kind=${OPSK:-strike} --ops-rv --chart-open --frames=${OPSF:-500} ;;
		blitz) shot blitz --air --time=night --weather=clear --at=51.40,-0.02,2400,315 --chase=40 --raid-city=London --frames=${BF:-1500} ;;
		flakn) shot flakn --air --time=night --weather=clear --at=50.60,1.75,2600,95 --chase=40 --frames=${FF:-1200} ;;
		flakd) shot flakd --air --time=noon --weather=scattered --at=50.60,1.75,2600,95 --chase=40 --skywar=3 --frames=${FF:-1200} ;;
		v2)    shot v2    --air --time=noon --weather=clear --at=50.86,1.95,1600,130 --chase=40 --v2-now --frames=${VF:-1500} ;;
		rays)  shot rays  --air --time=17.7 --weather=scattered --at=51.2,0.6,1200,249 --chase=40 ;;
		cloud) shot cloud --air --time=noon --weather=scattered --at=51.2,0.6,900,90 --chase=40 --orbit=20,-25 ;;
	esac
done
echo VIS_DONE

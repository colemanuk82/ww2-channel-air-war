# Headless taxi scenario -> build/dbg/<name>.json
# Usage: tools/dbg/run.ps1 -Style raf_bomber -Wingmen 3 [-Secs 150] [-Name x] [-Extra "--spot=2 --player-hold"]
param([string]$Style = "raf_bomber", [int]$Wingmen = 2, [int]$Secs = 150, [string]$Name = "", [string]$Extra = "", [string]$Aircraft = "spitfire")
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ($Name -eq "") { $Name = $Style }
$out = "build/dbg/$Name.json"
$exe = 'F:\godot-std\bin\godot.windows.editor.double.x86_64.console.exe'
$argl = @("--headless", "--fixed-fps", "60", "--path", "$root", "scenes/dbg.tscn", "--", "--style=$Style", "--wingmen=$Wingmen", "--secs=$Secs", "--aircraft=$Aircraft", "--out=$out") + ($Extra -split ' ' | Where-Object { $_ })
& $exe @argl 2>&1 | Select-String -Pattern 'DBG|SCRIPT ERROR|Parse Error|ERROR' | ForEach-Object { $_.Line }

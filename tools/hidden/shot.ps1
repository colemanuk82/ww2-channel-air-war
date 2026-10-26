# One screenshot of the game with any debug args, on the hidden desktop (no window on screen, no focus change).
# Usage: shot.ps1 -Out F:\ww2_dlss\build\mis\x.png -Delay 8 -GameArgs "--skip-legal --intro=40 --intro-freeze"
param([string]$Out, [double]$Delay = 8, [string]$GameArgs = "--skip-legal", [string]$Res = "1920x1080", [int]$TimeoutSec = 120)
$g = 'F:\godot-std\bin\godot.windows.editor.double.x86_64.exe'
$log = [IO.Path]::ChangeExtension($Out, '.log')
& F:\ww2_dlss\tools\hidden\hidden_run.ps1 -Exe $g -ArgLine "--path F:\ww2_dlss --audio-driver Dummy --resolution $Res --log-file $log -- $GameArgs --shot-delay=$Delay --ui-shot=$Out" -TimeoutSec $TimeoutSec

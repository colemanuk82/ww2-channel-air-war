# Intro screenshots on a hidden desktop (never visible, never takes focus).
$g = 'F:\godot-std\bin\godot.windows.editor.double.x86_64.exe'
$h = 'F:\ww2_dlss\tools\hidden\hidden_run.ps1'
$T = @(3,8,10.5,37,41,44,50,58,67,75,84,92)
if ($args.Count -gt 0) { $T = $args }
for ($i = 0; $i -lt $T.Count; $i++) {
  $o = "F:\ww2_dlss\build\mis\intro_$i"
  & $h -Exe $g -ArgLine "--path F:\ww2_dlss --audio-driver Dummy --resolution 1280x720 --log-file $o.log -- --skip-legal --intro=$($T[$i]) --intro-freeze --shot-delay=16 --ui-shot=$o.png" -TimeoutSec 150
}
'INTRODONE'

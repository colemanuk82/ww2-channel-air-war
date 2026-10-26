# Real-time (unfrozen) intro captures on the hidden desktop. Args: pairs of start,delay  e.g. 31,7.5 0,10
$g = 'F:\godot-std\bin\godot.windows.editor.double.x86_64.exe'
$h = 'F:\ww2_dlss\tools\hidden\hidden_run.ps1'
$i = 0
foreach ($p in $args) {
  $s, $d = "$p".Split(',')
  $o = "F:\ww2_dlss\build\mis\real_$i"
  & $h -Exe $g -ArgLine "--path F:\ww2_dlss --audio-driver Dummy --resolution 1280x720 --log-file $o.log -- --skip-legal --intro-debug --intro=$s --shot-delay=$d --ui-shot=$o.png" -TimeoutSec 120
  $i++
}
'REALDONE'

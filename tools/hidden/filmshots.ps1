# Training-film captures on the hidden desktop. Args: chapter,seconds pairs e.g. 1,6 4,8
$g = 'F:\godot-std\bin\godot.windows.editor.double.x86_64.exe'
$h = 'F:\ww2_dlss\tools\hidden\hidden_run.ps1'
$i = 0
foreach ($p in $args) {
  $o = "F:\ww2_dlss\build\mis\film_$i"
  & $h -Exe $g -ArgLine "--path F:\ww2_dlss --audio-driver Dummy --resolution 1280x720 --log-file $o.log -- --skip-legal --film=$p --shot-delay=12 --ui-shot=$o.png" -TimeoutSec 90
  $i++
}
'FILMDONE'

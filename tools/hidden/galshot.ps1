# Model gallery screenshot on the hidden desktop. Args: out-name  "<gallery args>" e.g. "--ids=spitfire --view=three"
param([string]$Name, [string]$GalArgs)
$g = 'F:\godot-std\bin\godot.windows.editor.double.x86_64.exe'
$o = "F:\ww2_dlss\build\gal\$Name"
New-Item -ItemType Directory -Force -Path F:\ww2_dlss\build\gal | Out-Null
& F:\ww2_dlss\tools\hidden\hidden_run.ps1 -Exe $g -ArgLine "--path F:\ww2_dlss --audio-driver Dummy --resolution 1920x1080 --log-file $o.log scenes/model_gallery.tscn -- $GalArgs --shot=$o.png" -TimeoutSec 120

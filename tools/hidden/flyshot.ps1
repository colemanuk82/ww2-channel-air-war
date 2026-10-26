# In-flight screenshot on the hidden desktop. Args: out-name  "<game args>"  [frames]
param([string]$Name, [string]$GameArgs, [int]$Frames = 900, [string]$LowCloud = "", [string]$NoFade = "")
$env:WW2_LOW_CLOUD = $LowCloud
$env:WW2_NO_FADE = $NoFade
$g = 'F:\godot-std\bin\godot.windows.editor.double.x86_64.exe'
$o = "F:\ww2_dlss\build\mis\$Name"
& F:\ww2_dlss\tools\hidden\hidden_run.ps1 -Exe $g -ArgLine "--path F:\ww2_dlss --audio-driver Dummy --resolution 1920x1080 --log-file $o.log -- --skip-legal $GameArgs --frames=$Frames --shot=$o.png" -TimeoutSec 150

$env:WW2_LOW_CLOUD = ''
$env:WW2_NO_FADE = ''

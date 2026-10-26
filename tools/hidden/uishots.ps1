# Menu + settings-page captures on the hidden desktop.  Args: page names ('menu' = start menu)
$g = 'F:\godot-std\bin\godot.windows.editor.double.x86_64.exe'
$h = 'F:\ww2_dlss\tools\hidden\hidden_run.ps1'
foreach ($p in $args) {
  $sub = ''
  if ($p -like 'controls-*') { $sub = $p.Substring(9); $page = 'controls' } else { $page = $p }
  $env:WW2_CONTROLS_SUB = $sub
  if ($p -eq 'menu') { $env:WW2_SETTINGS_PAGE = '' } else { $env:WW2_SETTINGS_PAGE = $page }
  $o = "F:\ww2_dlss\build\mis\ui_$p"
  & $h -Exe $g -ArgLine "--path F:\ww2_dlss --audio-driver Dummy --resolution 1920x1080 --log-file $o.log -- --skip-legal --shot-delay=9 --ui-shot=$o.png" -TimeoutSec 60
}
$env:WW2_SETTINGS_PAGE = ''
'UIDONE'

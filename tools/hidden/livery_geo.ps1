param([string]$Only = "")
# Headless (no window): re-import, then export the unwrapped skin geometry for the livery painter.
& F:\ww2_dlss\tools\hidden\imp.ps1
$a = @('--headless', '--path', 'F:\ww2_dlss', 'tools/liveries/export_geo.tscn')
if ($Only -ne "") { $a += @('--', "--only=$Only") }
& 'F:\godot-std\bin\godot.windows.editor.double.x86_64.console.exe' @a *> F:\ww2_dlss\build\livery_geo.log
"GEO_DONE" | Out-File F:\ww2_dlss\build\livery_geo_done.txt

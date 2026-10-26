param([string]$Only = "")
# Full livery rebuild without any window: export geometry (headless Godot), paint (python), re-import.
& F:\ww2_dlss\tools\hidden\livery_geo.ps1 -Only $Only
$ids = @()
if ($Only -ne "") { $ids = $Only.Split(",") }
$env:PYTHONUNBUFFERED = "1"
& python F:\ww2_dlss\tools\liveries\paint_liveries.py @ids *> F:\ww2_dlss\build\paint.log
& F:\ww2_dlss\tools\hidden\imp.ps1
"LIVERY_BUILD_DONE"

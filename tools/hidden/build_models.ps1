# Rebuild aircraft .glb files with Blender in background mode (no window). Args: model ids.
$b = 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'
& $b --background --python F:\ww2_dlss\tools\models\build_all.py -- @args *> F:\ww2_dlss\build\mis\blender_build.log
Select-String -Path F:\ww2_dlss\build\mis\blender_build.log -Pattern '\[model|Error|Traceback' | ForEach-Object { $_.Line }
'BUILDDONE'

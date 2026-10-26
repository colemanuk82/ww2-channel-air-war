& 'F:\godot-std\bin\godot.windows.editor.double.x86_64.console.exe' --headless --path F:\ww2_dlss --import *> F:\ww2_dlss\build\import.log
Select-String -Path F:\ww2_dlss\build\import.log -Pattern 'SCRIPT ERROR|Parse Error' -Context 0,2 | ForEach-Object { $_.ToString() }
"IMPORT_DONE"

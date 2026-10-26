& F:\ww2_dlss\tools\hidden\imp.ps1
& 'F:\godot-std\bin\godot.windows.editor.double.x86_64.console.exe' --headless --path F:\ww2_dlss scenes/tests.tscn *> F:\ww2_dlss\build\tests.log
Select-String -Path F:\ww2_dlss\build\tests.log -Pattern 'FAIL|SCRIPT ERROR|Parse Error|TESTS ' | Select-Object -Last 30 | ForEach-Object { $_.Line }
"TEST_DONE" | Out-File F:\ww2_dlss\build\tests_done.txt

# Notes for AI assistants working on this repo

* **Never open a visible game window or steal focus** on the developer's PC. Run tests headless
  (`tools/hidden/test.ps1`) and every screenshot / real-time check on the hidden desktop via
  `tools/hidden/hidden_run.ps1` (see `tools/hidden/README.md`). Do not use `--minimized`, off-screen windows
  or `Start-Process -WindowStyle Minimized` - they still take focus.
* Godot 4.7.2 double-precision build: `F:\godot-std\bin\godot.windows.editor.double.x86_64(.console).exe`.
* Release: `tools/cache/ship.ps1 -msg "..."` (bumps version, builds, tests, commits, pushes, GitHub release).
  The developer also edits README.md on GitHub: merge before pushing README changes.
* Aircraft liveries are painted textures (`assets/liveries/`, see `tools/liveries/README.md`). After changing an
  aircraft model, rebuild them headless with `tools/hidden/livery_build.ps1 [-Only id,id]`; a model whose
  layout changed falls back to its old look until repainted. Never copy textures from other games.

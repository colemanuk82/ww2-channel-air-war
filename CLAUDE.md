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
* **Never commit commercial audio.** Every audio file under `assets/` must be covered by
  `tools/audio_allowlist.json`: a royalty-free Pixabay track with its title, artist and source, or the
  `assets/voice/` prefix for our own generated voices. Film, TV, broadcast and other games' soundtracks
  (the *Battle of Britain* score, for example) can never be redistributed with the game - players import
  their own copies through **Options > Music** at run time. `python tools/check_audio_licences.py`, the
  `TESTS OK` gate and the `Audio licences` workflow all enforce this; if a check fails, delete the file
  rather than widening the allowlist.

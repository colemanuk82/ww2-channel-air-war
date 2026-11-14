# Screenshot comparison check, on the hidden desktop (never a visible window - see tools/hidden/README.md).
# Captures a fixed set of frames and compares them with tools/shotcheck/baselines/ (tools/shotcheck/shotcmp.py).
#   shotcheck.ps1                      capture + compare (prints SHOTCHECK OK / FAILED)
#   shotcheck.ps1 -Update              capture and replace the baselines (look at build/shotcheck/*.png first)
#   shotcheck.ps1 -Root F:\ww2_wt\x    run against another checkout / worktree
param([string]$Root = 'F:\ww2_dlss', [switch]$Update, [string[]]$Only = @())
$g = 'F:\godot-std\bin\godot.windows.editor.double.x86_64.exe'
$h = 'F:\ww2_dlss\tools\hidden\hidden_run.ps1'
$out = Join-Path $Root 'build\shotcheck'
New-Item -ItemType Directory -Force $out | Out-Null
Get-ChildItem $out -Filter *.png -ErrorAction SilentlyContinue | Remove-Item -Force
# name = settings page ('' = start menu) | extra game args | shot delay (game seconds)
$set = @(
  @{ n = 'menu';      page = '';         args = '';                                   d = 9 },
  @{ n = 'opt_gfx';   page = 'video'; args = '';                                   d = 9 },
  @{ n = 'opt_ctrl';  page = 'controls'; args = '';                                   d = 9 },
  @{ n = 'intro_40';  page = '';         args = '--intro=40 --intro-freeze';          d = 14 }
)
$env:WW2_SHOTCHECK = '1'     # menu background: first painting, held still
foreach ($s in $set) {
  if ($Only.Count -gt 0 -and $Only -notcontains $s.n) { continue }
  $env:WW2_SETTINGS_PAGE = $s.page
  $png = Join-Path $out "$($s.n).png"
  & $h -Exe $g -ArgLine "--path $Root --audio-driver Dummy --resolution 1280x720 --log-file $out\$($s.n).log -- --skip-legal $($s.args) --shot-delay=$($s.d) --ui-shot=$png" -TimeoutSec 120 | Out-Null
}
$env:WW2_SETTINGS_PAGE = ''
$env:WW2_SHOTCHECK = ''
if ($Update) { & python (Join-Path $Root 'tools\shotcheck\shotcmp.py') $out --update } else { $extra = @(); if ($Only.Count -gt 0) { $extra = @('--present') }; & python (Join-Path $Root 'tools\shotcheck\shotcmp.py') $out @extra }

# One-command check for the map editor: headless import, the full test scene, one hidden-desktop
# render. Nothing here opens a visible window on the developer's desktop (see tools/hidden/README.md).
#   .\tools\map_editor\selfcheck.ps1 [-RepoRoot F:\ww2_dlss] [-Godot <windowed exe>]
# Prints SELFCHECK OK, or SELFCHECK FAILED: <why> and exits non-zero.
# Log and picture: build\mis\selfcheck.log, build\mis\editor_selfcheck.png (git-ignored).
# The repo root comes from where this script sits (<root>\tools\map_editor), never from a constant,
# so the same file works in the worktree and in the main checkout.
param(
  [string]$RepoRoot = '',
  [string]$Godot = 'F:\godot-std\bin\godot.windows.editor.double.x86_64.exe'
)

$ErrorActionPreference = 'Stop'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..\..' }
if (-not (Test-Path -LiteralPath $RepoRoot)) {
  Write-Host "selfcheck: no such repo root: $RepoRoot"
  exit 1
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

# -Godot is the windowed exe (step 3 needs a real window, on the hidden desktop). The headless steps
# use the console build next to it, which is the same engine with a console.
if (-not (Test-Path -LiteralPath $Godot)) {
  Write-Host "selfcheck: Godot not found: $Godot (pass -Godot <exe>)"
  exit 1
}
$ConsoleExe = $Godot
if ($Godot -match '(?i)\.exe$' -and $Godot -notmatch '(?i)\.console\.exe$') {
  $candidate = $Godot -replace '(?i)\.exe$', '.console.exe'
  if (Test-Path -LiteralPath $candidate) { $ConsoleExe = $candidate }
}

$OutDir = Join-Path $RepoRoot 'build\mis'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$script:LogPath = Join-Path $OutDir 'selfcheck.log'
[IO.File]::WriteAllText($script:LogPath, '', $script:Utf8)

function Say {
  param([string]$Text)
  Write-Host $Text
  [IO.File]::AppendAllText($script:LogPath, $Text + "`r`n", $script:Utf8)
}

function Banner {
  param([string]$Text)
  Say ''
  Say ('=' * 70)
  Say $Text
  Say ('=' * 70)
}

function Fail {
  param([string]$Why)
  Say ''
  Say "SELFCHECK FAILED: $Why"
  Say "log: $script:LogPath"
  exit 1
}

# CLAUDE.md: never start a second Godot while another godot*.exe is running.
function Wait-ForOtherGodot {
  param([int]$TimeoutSec = 900)
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $told = $false
  while ($true) {
    $procs = @(Get-Process -Name 'godot*' -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return $true }
    if (-not $told) {
      Say "another Godot is running ($($procs.Count) process(es)), waiting up to $TimeoutSec s for it"
      $told = $true
    }
    if ((Get-Date) -ge $deadline) { return $false }
    Start-Sleep -Seconds 5
  }
}

# Runs Godot, copies everything it printed into the log, returns its exit code and output lines.
function Invoke-Godot {
  param([string]$Exe, [string[]]$GodotArgs)
  Say ''
  Say ('> "' + $Exe + '" ' + ($GodotArgs -join ' '))
  $oldPref = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $lines = @()
  & $Exe @GodotArgs 2>&1 | ForEach-Object { $lines += $_.ToString() }
  $code = $LASTEXITCODE
  $ErrorActionPreference = $oldPref
  foreach ($line in $lines) { Say $line }
  return @{ Code = $code; Lines = $lines }
}

Banner 'MAP EDITOR SELFCHECK'
Say "repo    : $RepoRoot"
Say "godot   : $Godot"
Say "console : $ConsoleExe"
Say "log     : $script:LogPath"

$TestScene = Join-Path $RepoRoot 'scenes\tests.tscn'
if (-not (Test-Path -LiteralPath $TestScene)) { Fail "missing test scene: $TestScene" }
$EditorScene = Join-Path $RepoRoot 'tools\map_editor\map_editor.tscn'
if (-not (Test-Path -LiteralPath $EditorScene)) { Fail "missing editor scene: $EditorScene" }
if (-not (Wait-ForOtherGodot)) { Fail 'gave up waiting for another godot*.exe to finish' }

# --- 1/3 headless import ------------------------------------------------------------------------
Banner 'STEP 1/3  headless import'
$r = Invoke-Godot $ConsoleExe @('--headless', '--path', $RepoRoot, '--import', '--quit')
$bad = @($r.Lines | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error' })
if ($bad.Count -gt 0) {
  foreach ($b in $bad) { Say "  ! $b" }
  Fail "the import reported $($bad.Count) SCRIPT ERROR / Parse Error line(s)"
}
if ($r.Code -ne 0) {
  # Not fatal on its own: the import can return non-zero for missing optional assets, and a real
  # script problem always prints SCRIPT ERROR / Parse Error above. Step 2 is the harder gate.
  Say "note: the import exited with code $($r.Code) but printed no script errors"
}
Say 'import clean: no SCRIPT ERROR / Parse Error'

# --- 2/3 the full test scene --------------------------------------------------------------------
Banner 'STEP 2/3  full test scene (scenes/tests.tscn)'
$r = Invoke-Godot $ConsoleExe @('--headless', '--path', $RepoRoot, 'scenes/tests.tscn')
if (($r.Lines -join "`n") -notmatch 'TESTS OK') {
  foreach ($f in @($r.Lines | Where-Object { $_ -match 'FAIL|SCRIPT ERROR|Parse Error' })) { Say "  ! $f" }
  Fail "the test scene did not print TESTS OK (exit code $($r.Code))"
}
Say 'TESTS OK'

# --- 3/3 one render on the hidden desktop -------------------------------------------------------
Banner 'STEP 3/3  hidden-desktop render (--editor-shot)'
$Hidden = Join-Path $RepoRoot 'tools\hidden\hidden_run.ps1'
if (-not (Test-Path -LiteralPath $Hidden)) { Fail "missing $Hidden" }
$Shot = Join-Path $OutDir 'editor_selfcheck.png'
$ShotLog = Join-Path $OutDir 'editor_selfcheck.log'
if (Test-Path -LiteralPath $Shot) { Remove-Item -LiteralPath $Shot -Force }

# --editor-shot draws real frames, saves the PNG and quits; the editor args come after --.
$argLine = '--path "' + $RepoRoot + '" --audio-driver Dummy --log-file "' + $ShotLog + '" tools/map_editor/map_editor.tscn -- --editor-shot="' + $Shot + '" --editor-frames=120 --editor-zoom=24 --editor-at=49.18,-0.36'
Say ''
Say ('> "' + $Hidden + '" -Exe "' + $Godot + '" -TimeoutSec 200 -ArgLine ' + $argLine)
$oldPref = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$hiddenOut = & $Hidden -Exe $Godot -ArgLine $argLine -TimeoutSec 200 2>&1
$ErrorActionPreference = $oldPref
foreach ($line in $hiddenOut) { Say $line.ToString() }

if (-not (Test-Path -LiteralPath $Shot)) {
  Fail "no picture: the editor saved nothing to $Shot (see $ShotLog)"
}
$length = (Get-Item -LiteralPath $Shot).Length
if ($length -le 0) { Fail "the picture is empty (0 bytes): $Shot" }
Say ''
Say "render ok: $Shot ($length bytes)"

Banner 'SELFCHECK OK'
Say 'import clean, TESTS OK, editor rendered on the hidden desktop'
Say "log: $script:LogPath"
exit 0

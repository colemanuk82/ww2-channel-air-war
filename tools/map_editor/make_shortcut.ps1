# Creates "Map Editor.lnk" on the desktop for this checkout of the game.
#   .\tools\map_editor\make_shortcut.ps1 [-RepoRoot F:\ww2_dlss] [-Godot <exe>] [-Name 'Map Editor']
# The shortcut runs the editor scene inside the game project:
#   godot --path <repo root> tools/map_editor/map_editor.tscn
# The repo root and the exe path are baked into the .lnk here, they are NOT resolved when it is
# clicked, so the shortcut is per-checkout: re-run this script after moving the repo or Godot.
param(
  [string]$RepoRoot = '',
  [string]$Godot = 'F:\godot-std\bin\godot.windows.editor.double.x86_64.exe',
  [string]$Name = 'Map Editor'
)

$ErrorActionPreference = 'Stop'
$Scene = 'tools/map_editor/map_editor.tscn'

# The repo root comes from where this script sits (<root>\tools\map_editor), never from a constant,
# so the same file works in the worktree and in the main checkout.
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..\..' }
if (-not (Test-Path -LiteralPath $RepoRoot)) {
  Write-Host "make_shortcut: no such repo root: $RepoRoot"
  exit 1
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

# Fail loudly rather than write a shortcut that does nothing when it is double-clicked.
if (-not (Test-Path -LiteralPath $Godot)) {
  Write-Host ''
  Write-Host 'make_shortcut: Godot not found, no shortcut written:' -ForegroundColor Red
  Write-Host "  $Godot" -ForegroundColor Red
  Write-Host 'Install the double-precision Godot build there, or pass -Godot <exe>.'
  Write-Host ''
  exit 1
}
$ScenePath = Join-Path $RepoRoot $Scene
if (-not (Test-Path -LiteralPath $ScenePath)) {
  Write-Host "make_shortcut: editor scene not found, no shortcut written: $ScenePath"
  exit 1
}

$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) {
  Write-Host "make_shortcut: no desktop folder for this user ($desktop)"
  exit 1
}
$LnkPath = Join-Path $desktop ($Name + '.lnk')

# The windowed (non-console) exe: the console build flashes a window on start.
$argLine = '--path "' + $RepoRoot + '" ' + $Scene

Write-Host "writing $LnkPath"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($LnkPath)   # an existing "Map Editor.lnk" is replaced silently
$shortcut.TargetPath = $Godot
$shortcut.Arguments = $argLine
$shortcut.WorkingDirectory = $RepoRoot
$shortcut.WindowStyle = 1
$shortcut.Description = 'WW2 Channel Air War - map editor'
$shortcut.Save()
[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut)
[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)

if (-not (Test-Path -LiteralPath $LnkPath)) {
  Write-Host "make_shortcut: the shortcut was not written: $LnkPath"
  exit 1
}

# Read it back, so what is printed is what Windows stored, not what we meant to store.
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($LnkPath)
$target = $shortcut.TargetPath
$storedArgs = $shortcut.Arguments
$storedDir = $shortcut.WorkingDirectory
[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut)
[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)

if ($target -ne $Godot) {
  Write-Host "make_shortcut: the shortcut points at '$target', not '$Godot'"
  exit 1
}

Write-Host ''
Write-Host 'Shortcut created.'
Write-Host "  .lnk    : $LnkPath"
Write-Host "  target  : $target"
Write-Host "  args    : $storedArgs"
Write-Host "  workdir : $storedDir"
Write-Host "  size    : $((Get-Item -LiteralPath $LnkPath).Length) bytes"
Write-Host ''
Write-Host 'The repo root is baked into the shortcut: re-run this script after moving the repo.'
exit 0

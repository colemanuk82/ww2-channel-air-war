$env:WW2_LOW_CLOUD = $args[0]
& F:\ww2_dlss\tools\hidden\shot.ps1 -Out F:\ww2_dlss\build\mis\cdbg_$($args[1]).png -Delay 25 -GameArgs "--skip-legal --intro=$($args[1]) --intro-freeze --cloud-debug"
$env:WW2_LOW_CLOUD = ''

# Weather check frames on the hidden desktop: rain shafts, scattered cumulus, a forced low-cloud day.
$s = 'F:\ww2_dlss\tools\hidden\shot.ps1'
$o = 'F:\ww2_dlss\build\mis'
$env:WW2_LOW_CLOUD = ''
& $s -Out "$o\wx_rain.png" -Delay 16 -GameArgs "--skip-legal --intro=24 --intro-freeze"
& $s -Out "$o\wx_scat.png" -Delay 16 -GameArgs "--skip-legal --intro=76 --intro-freeze"
$env:WW2_LOW_CLOUD = '1'
& $s -Out "$o\wx_low.png" -Delay 16 -GameArgs "--skip-legal --intro=15 --intro-freeze"
$env:WW2_LOW_CLOUD = ''
& $s -Out "$o\wx_menu.png" -Delay 7 -GameArgs "--skip-legal"
'WXDONE'

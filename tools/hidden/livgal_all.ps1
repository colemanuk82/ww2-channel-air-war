param([string]$View = "three", [string]$Ids = "spitfire,hurricane,typhoon,tempest,mosquito,blenheim,defiant,lancaster,p51,p47,p38,b25,b26,a20,c47,dh89,bf109,bf110,fw190,me262,he111,ju88,do17,ju87,ju52,fw200")
foreach ($id in $Ids.Split(",")) {
  & F:\ww2_dlss\tools\hidden\galshot.ps1 -Name "L_${id}_$View" -GalArgs "--ids=$id --view=$View" | Out-Null
}
"ALLGAL_DONE"
